-- Cash handover events use the same durable push outbox as installation tasks.
alter table public.solar_notifications add column transfer_id uuid references solar_private.cash_transfers(id);
alter table public.solar_notifications drop constraint solar_notifications_event_check;
alter table public.solar_notifications add constraint solar_notifications_event_check check(event in ('assigned','completed','test','cash_received','cash_accepted','cash_rejected','cash_cancelled','invoice_deleted'));
create index solar_notifications_transfer on public.solar_notifications(transfer_id) where transfer_id is not null;
create function solar_private.notify_cash_transfer() returns trigger language plpgsql security definer set search_path='' as $$
declare recipient uuid; event_name text; heading text; detail text; nid uuid;
begin
 if tg_op='INSERT' then
  recipient:=new.recipient_id;event_name:='cash_received';heading:='طلب استلام أموال جديد';detail:='أرسل إليك أحد المستخدمين أموال القاصة. افتح الطلب للمراجعة والموافقة على الاستلام.';
 elsif old.status='pending' and new.status in ('accepted','rejected','cancelled') then
  recipient:=case when new.status='cancelled' then new.recipient_id else new.sender_id end;
  event_name:='cash_'||case new.status when 'accepted' then 'accepted' when 'rejected' then 'rejected' else 'cancelled' end;
  heading:=case new.status when 'accepted' then 'تمت الموافقة على تسليم الأموال' when 'rejected' then 'تم رفض طلب تسليم الأموال' else 'تم إلغاء طلب تسليم الأموال' end;
  detail:=case new.status when 'accepted' then 'أكد مسؤول المالية استلام الأموال، واكتملت حركة التحويل.' when 'rejected' then 'أُعيد مبلغ التحويل إلى قاصتك. المصروف السابق يبقى مسجلاً.' else 'ألغى المرسل الطلب وأُعيد المبلغ إلى قاصته.' end;
 else return new;end if;
 if not exists(select 1 from public.profiles where id=recipient and active) then return new;end if;
 insert into public.solar_notifications(user_id,transfer_id,event,title,body) values(recipient,new.id,event_name,heading,detail) returning id into nid;
 insert into solar_private.push_deliveries(notification_id,endpoint) select nid,s.endpoint from public.solar_push_subscriptions s where s.user_id=recipient;
 perform solar_private.wake_push();
 return new;
end $$;
revoke all on function solar_private.notify_cash_transfer() from public,anon,authenticated;
create trigger solar_cash_notifications after insert or update on solar_private.cash_transfers for each row execute function solar_private.notify_cash_transfer();
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='solar_notifications') then alter publication supabase_realtime add table public.solar_notifications;end if;
end $$;

-- Deleted invoices remain in a private audit record, while active accounting and
-- stock are reversed atomically. No audit data is exposed to client roles.
create table solar_private.deleted_sales(
 invoice_id bigint primary key, invoice jsonb not null, items jsonb not null,
 deleted_by uuid not null references public.profiles(id), deleted_at timestamptz not null default now()
);
alter table solar_private.deleted_sales enable row level security;
revoke all on solar_private.deleted_sales from public,anon,authenticated;

create function solar_private.can_delete_sale(owner_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.user_type<>'installer'
 and (p.is_admin or p.permissions->>'salesDeleteAll'='true' or (p.permissions->>'salesDeleteOwn'='true' and p.id=owner_id)))
$$;
revoke all on function solar_private.can_delete_sale(uuid) from public,anon;
grant execute on function solar_private.can_delete_sale(uuid) to authenticated;

create function solar_private.sale_delete_data(invoice_id bigint) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare t public.transactions; line_data jsonb; blocked text;
begin
 select * into t from public.transactions where id=invoice_id and kind in ('sale','system');
 if t.id is null or not solar_private.can_delete_sale(t.created_by) then raise exception 'Not permitted' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]') into line_data from public.transaction_items i where i.transaction_id=t.id;
 if exists(select 1 from public.solar_cash_entries where job_id=t.id) or coalesce(t.installation_expenses,0)>0 then
  blocked:='لا يمكن حذف فاتورة مرتبطة بمصاريف تنصيب معتمدة أو مدفوعة؛ يجب معالجة مصاريفها محاسبياً أولاً.';
 elsif exists(select 1 from public.transaction_items i where i.transaction_id=t.id and (i.product_id is null or i.qty is null or i.qty<=0)) then
  blocked:='لا يمكن حذف الفاتورة لوجود مادة محذوفة أو كمية غير صحيحة؛ راجع المواد أولاً.';
 elsif t.cash and t.total>0 and solar_private.cash_balance(coalesce(t.cashbox_user_id,t.created_by))<t.total then
  blocked:='لا يمكن حذف الوصل النقدي لأن رصيد قاصة صاحبه لا يكفي لإلغاء المبلغ؛ سوِّ القاصة أولاً.';
 end if;
 return jsonb_build_object('token',md5(to_jsonb(t)::text||line_data::text),'party',t.party_name,'total',t.total,'kind',t.kind,'blockedReason',blocked);
end $$;
revoke all on function solar_private.sale_delete_data(bigint) from public,anon;
grant execute on function solar_private.sale_delete_data(bigint) to authenticated;
create function public.solar_sale_delete_preview(invoice_id bigint) returns jsonb language sql security invoker set search_path='' as $$select solar_private.sale_delete_data(invoice_id)$$;
revoke all on function public.solar_sale_delete_preview(bigint) from public,anon;
grant execute on function public.solar_sale_delete_preview(bigint) to authenticated;

create function solar_private.sale_delete(invoice_id bigint,expected_token text) returns void language plpgsql security definer set search_path='' as $$
declare t public.transactions; preview jsonb; line_data jsonb; archived jsonb; nid uuid; target uuid;
begin
 perform pg_advisory_xact_lock(7311,1);
 select * into t from public.transactions where id=invoice_id and kind in ('sale','system') for update;
 if t.id is null then
  select invoice into archived from solar_private.deleted_sales d where d.invoice_id=sale_delete.invoice_id;
  if archived is not null and solar_private.can_delete_sale((archived->>'created_by')::uuid) then return;end if;
  raise exception 'Not permitted' using errcode='42501';
 end if;
 preview:=solar_private.sale_delete_data(t.id);
 if preview->>'token' is distinct from expected_token then raise exception 'Invoice changed' using errcode='40001';end if;
 if preview->>'blockedReason' is not null then raise exception '%',preview->>'blockedReason';end if;
 select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]') into line_data from public.transaction_items i where i.transaction_id=t.id;
 insert into solar_private.deleted_sales(invoice_id,invoice,items,deleted_by) values(t.id,to_jsonb(t),line_data,auth.uid());
 update public.products p set qty=coalesce(p.qty,0)+x.qty from (select i.product_id,sum(i.qty) qty from public.transaction_items i where i.transaction_id=t.id group by i.product_id) x where p.id=x.product_id;
 delete from public.cash_ledger where transaction_id=t.id;
 delete from public.transactions where id=t.id;
 -- An engineer must not keep travelling to a deleted assignment.
 for target in select distinct x from unnest(array[t.installer_id,t.created_by]) x where x is not null and x<>auth.uid() loop
  if exists(select 1 from public.profiles p where p.id=target and p.active) then
   insert into public.solar_notifications(user_id,event,title,body) values(target,'invoice_deleted','تم حذف فاتورة مرتبطة بك','تم حذف الفاتورة #'||t.id::text||' وإلغاء تكليف التنصيب المرتبط بها إن وجد.') returning id into nid;
   insert into solar_private.push_deliveries(notification_id,endpoint) select nid,s.endpoint from public.solar_push_subscriptions s where s.user_id=target;
  end if;
 end loop;
 perform solar_private.wake_push();
end $$;
revoke all on function solar_private.sale_delete(bigint,text) from public,anon;
grant execute on function solar_private.sale_delete(bigint,text) to authenticated;
create function public.solar_sale_delete(invoice_id bigint,expected_token text) returns void language sql security invoker set search_path='' as $$select solar_private.sale_delete(invoice_id,expected_token)$$;
revoke all on function public.solar_sale_delete(bigint,text) from public,anon;
grant execute on function public.solar_sale_delete(bigint,text) to authenticated;

create function solar_private.guard_sale_delete() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' then
  if current_user in ('authenticated','anon') and new.kind is distinct from old.kind then raise exception 'Invoice kind is immutable' using errcode='42501';end if;
  return new;
 end if;
 if current_user in ('authenticated','anon') and old.kind in ('sale','system') then raise exception 'Use authorized invoice deletion' using errcode='42501';end if;
 return old;
end $$;
revoke all on function solar_private.guard_sale_delete() from public,anon,authenticated;
create trigger solar_guard_sale_delete before delete or update on public.transactions for each row execute function solar_private.guard_sale_delete();
create function solar_private.guard_deleted_sale_id() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from solar_private.deleted_sales where invoice_id=new.id) then raise exception 'Deleted invoice cannot be recreated' using errcode='40001';end if;
 return new;
end $$;
revoke all on function solar_private.guard_deleted_sale_id() from public,anon,authenticated;
create trigger solar_guard_deleted_sale_id before insert on public.transactions for each row execute function solar_private.guard_deleted_sale_id();
-- Coordinate item edits with deletion, as existing transaction writes already do.
create trigger solar_items_write_lock before insert or update or delete on public.transaction_items for each statement execute function solar_private.lock_cash_writes();
create trigger solar_products_write_lock before insert or update or delete on public.products for each statement execute function solar_private.lock_cash_writes();

create or replace function solar_private.sales_history(
 search_text text default '', sale_kind text default '', date_from date default null,
 date_to date default null, job_status text default '', page_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; result jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active=true;
 if p.id is null or p.user_type='installer' then raise exception 'Not permitted' using errcode='42501'; end if;
 with permitted as (
 select t.* from public.transactions t where t.kind in ('sale','system')
 and (p.is_admin or p.permissions->>'salesDeleteAll'='true' or (t.created_by=p.id and p.permissions->>'salesDeleteOwn'='true') or
  (t.created_by=p.id and (p.permissions->>'salesHistory'='true'
   or (t.kind='sale' and p.permissions->>'sale'='true')
   or (t.kind='system' and (p.permissions->>'system'='true' or p.permissions->>'installations'='true'))))
  or (t.kind='system' and p.permissions->>'installationsAll'='true'))
 and (coalesce(sale_kind,'')='' or t.kind=sale_kind)
 and (coalesce(search_text,'')='' or strpos(lower(coalesce(t.party_name,'')||' '||t.id::text),lower(search_text))>0)
 and (date_from is null or t.created_at >= (date_from::timestamp at time zone 'Asia/Baghdad'))
 and (date_to is null or t.created_at < ((date_to+1)::timestamp at time zone 'Asia/Baghdad'))
 and (coalesce(job_status,'')='' or (t.kind='system' and t.installation_status=job_status))
 ), page_rows as (select * from permitted order by created_at desc,id desc limit 30 offset greatest(coalesce(page_offset,0),0))
 select jsonb_build_object('count',(select count(*) from permitted),'rows',coalesce((
 select jsonb_agg(to_jsonb(t)||jsonb_build_object(
 'canDelete',solar_private.can_delete_sale(t.created_by),
 'creatorName',(select coalesce(x.display_name,x.username) from public.profiles x where x.id=t.created_by),
 'installerName',(select coalesce(x.display_name,x.username) from public.profiles x where x.id=t.installer_id),
 'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]'::jsonb)
 ) order by t.created_at desc,t.id desc) from page_rows t),'[]'::jsonb)) into result;
 return result;
end $$;

create or replace function public.solar_push_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 with eligible as (
 select d.id from solar_private.push_deliveries d join public.solar_notifications n on n.id=d.notification_id
 join public.solar_push_subscriptions s on s.endpoint=d.endpoint and s.user_id=n.user_id
 join public.profiles p on p.id=n.user_id and p.active
 where d.attempts<5 and n.created_at>now()-interval '1 day' and ((d.status='pending' and d.available_at<=now()) or (d.status='sending' and d.lease_until<now()))
 order by d.available_at for update of d skip locked limit 20
 ), claimed as (
 update solar_private.push_deliveries d set status='sending',attempts=attempts+1,lease_until=now()+interval '2 minutes'
 from eligible e where d.id=e.id returning d.*
 )
 select coalesce(jsonb_agg(jsonb_build_object('deliveryId',d.id,'attempt',d.attempts,'endpoint',s.endpoint,'keys',jsonb_build_object('p256dh',s.p256dh,'auth',s.auth_key),'notification',jsonb_build_object('id',n.id,'userId',n.user_id,'jobId',n.job_id,'transferId',n.transfer_id,'title',n.title,'body',n.body))),'[]'::jsonb)
 into result from claimed d join public.solar_notifications n on n.id=d.notification_id join public.solar_push_subscriptions s on s.endpoint=d.endpoint and s.user_id=n.user_id;
 return result;
end $$;
