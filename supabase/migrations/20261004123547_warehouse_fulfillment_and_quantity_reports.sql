-- Dedicated warehouse role never receives financial rows, even with stale flags.
create or replace function solar_private.role_name() returns text
language sql stable security definer set search_path='' as $$
 select case when p.user_type='installer' then 'installer' when p.user_type='warehouse' then 'warehouse' when p.is_admin then 'admin' else 'staff' end
 from public.profiles p where p.id=auth.uid() and p.active
$$;
create or replace function solar_private.normalize_warehouse_profile() returns trigger language plpgsql set search_path='' as $$
begin
 if new.user_type='warehouse' then new.is_admin:=false; new.permissions:='{"warehouse":true,"stock":true,"stockMovement":true}'::jsonb; end if;
 return new;
end $$;
revoke all on function solar_private.normalize_warehouse_profile() from public,anon,authenticated;
create trigger solar_warehouse_profile before insert or update on public.profiles for each row execute function solar_private.normalize_warehouse_profile();
create or replace function public.is_solar_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and is_admin and active and user_type not in ('warehouse','installer'))
$$;
-- Explicitly deny financial/workflow RPCs to the price-free role.
do $$ declare f record; definition text; begin
 for f in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='solar_private' and p.proname in
 ('installation_jobs','installation_action','staff_directory','cash_transfer_overview','cash_transfer_send','cash_transfer_decide','sales_history','sale_delete_data','sale_delete','supplier_payment_get','supplier_payment_save') loop
  definition:=pg_get_functiondef(f.oid);
  definition:=regexp_replace(definition,E'\\mbegin\\M',E'begin\n if solar_private.role_name()=''warehouse'' then raise exception ''Not permitted'' using errcode=''42501'';end if;', 'i');
  execute definition;
 end loop;
end $$;

alter table public.transactions add column warehouse_status text not null default 'pending' check(warehouse_status in ('pending','ready'));
alter table public.transactions add column warehouse_revision bigint not null default 0;
alter table public.transactions add column warehouse_prepared_at timestamptz;
alter table public.transactions add column warehouse_prepared_by uuid references public.profiles(id);
alter table public.transactions add column warehouse_note text not null default '';
create index solar_warehouse_pending on public.transactions(warehouse_status,created_at desc) where kind in ('sale','system');
create table solar_private.warehouse_audit(
 id bigint generated always as identity primary key, invoice_id bigint not null, actor_id uuid not null,
 action text not null, before_items jsonb not null, after_items jsonb not null, created_at timestamptz not null default now()
);
alter table solar_private.warehouse_audit enable row level security;
revoke all on solar_private.warehouse_audit from public,anon,authenticated;

create or replace function solar_private.warehouse_allowed() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.user_type<>'installer'
 and (p.user_type='warehouse' or p.is_admin or p.permissions->>'warehouse'='true'))
$$;
revoke all on function solar_private.warehouse_allowed() from public,anon;
grant execute on function solar_private.warehouse_allowed() to authenticated;

create or replace function solar_private.warehouse_token(invoice_id bigint) returns text language sql stable set search_path='' as $$
 select md5(to_jsonb(t)::text||coalesce((select jsonb_agg(to_jsonb(i) order by i.id)::text from public.transaction_items i where i.transaction_id=t.id),'[]')) from public.transactions t where t.id=invoice_id
$$;
revoke all on function solar_private.warehouse_token(bigint) from public,anon,authenticated;
create or replace function solar_private.warehouse_orders(search_text text default '',state text default 'pending',page_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not solar_private.warehouse_allowed() then raise exception 'Not permitted' using errcode='42501'; end if;
 with matched as (
 select t.* from public.transactions t where kind in ('sale','system') and (state='' or warehouse_status=state)
 and (search_text='' or strpos(lower(coalesce(t.party_name,'')||' '||t.receipt_no::text),lower(search_text))>0)
 ), paged as (select * from matched order by created_at desc,id desc limit 30 offset greatest(page_offset,0))
 select jsonb_build_object('count',(select count(*) from matched),'rows',coalesce((select jsonb_agg(jsonb_build_object(
 'id',t.id,'receiptNo',t.receipt_no,'kind',t.kind,'party',t.party_name,'phone',t.customer_phone,'address',t.customer_address,'date',t.created_at,
 'status',t.warehouse_status,'preparedAt',t.warehouse_prepared_at,'preparedBy',(select coalesce(display_name,username) from public.profiles where id=t.warehouse_prepared_by),
 'note',t.warehouse_note,'token',solar_private.warehouse_token(t.id),'canEdit',t.installation_status not in ('in_progress','completed','closed'),
 'items',coalesce((select jsonb_agg(jsonb_build_object('lineId',i.id,'productId',i.product_id,'name',i.product_name,'brand',i.brand_name,'category',i.category,'qty',i.qty) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]'::jsonb)
 ) order by t.created_at desc,t.id desc) from paged t),'[]'::jsonb)) into result;
 return result;
end $$;
revoke all on function solar_private.warehouse_orders(text,text,integer) from public,anon;
grant execute on function solar_private.warehouse_orders(text,text,integer) to authenticated;
create or replace function public.solar_warehouse_orders(search_text text default '',state text default 'pending',page_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select solar_private.warehouse_orders(search_text,state,page_offset)$$;
revoke all on function public.solar_warehouse_orders(text,text,integer) from public,anon;
grant execute on function public.solar_warehouse_orders(text,text,integer) to authenticated;

alter table public.solar_notifications drop constraint solar_notifications_event_check;
alter table public.solar_notifications add constraint solar_notifications_event_check check(event in ('assigned','completed','test','cash_received','cash_accepted','cash_rejected','cash_cancelled','invoice_deleted','warehouse_new','warehouse_reopened','warehouse_ready','warehouse_edited'));
create or replace function solar_private.warehouse_notice(recipient uuid,invoice_id bigint,event_name text) returns void
language plpgsql security definer set search_path='' as $$
declare nid uuid; heading text; detail text;
begin
 if not exists(select 1 from public.profiles where id=recipient and active) then return;end if;
 heading:=case event_name when 'warehouse_ready' then 'تم تجهيز الفاتورة' when 'warehouse_edited' then 'تعديل مواد الفاتورة من المخزن' when 'warehouse_reopened' then 'الفاتورة تحتاج تجهيزاً من جديد' else 'فاتورة جديدة للتجهيز' end;
 select 'وصل #'||t.receipt_no||' • '||coalesce(t.party_name,'زبون نقدي') into detail from public.transactions t where id=invoice_id;
 insert into public.solar_notifications(user_id,job_id,event,title,body) values(recipient,invoice_id,event_name,heading,detail) returning id into nid;
 insert into solar_private.push_deliveries(notification_id,endpoint) select nid,endpoint from public.solar_push_subscriptions where user_id=recipient;
 perform solar_private.wake_push();
end $$;
revoke all on function solar_private.warehouse_notice(uuid,bigint,text) from public,anon,authenticated;
create or replace function solar_private.warehouse_notify() returns trigger language plpgsql security definer set search_path='' as $$
declare u record; event_name text;
begin
 if new.kind not in ('sale','system') then return new;end if;
 if tg_op='INSERT' then event_name:='warehouse_new';
 elsif old.warehouse_status='ready' and new.warehouse_status='pending' then event_name:='warehouse_reopened';
 elsif old.warehouse_status='pending' and new.warehouse_status='ready' then
  perform solar_private.warehouse_notice(new.created_by,new.id,'warehouse_ready');return new;
 else return new;end if;
 for u in select id from public.profiles where active and user_type<>'installer' and (user_type='warehouse' or permissions->>'warehouse'='true') loop
  perform solar_private.warehouse_notice(u.id,new.id,event_name);
 end loop;
 return new;
end $$;
revoke all on function solar_private.warehouse_notify() from public,anon,authenticated;
create trigger solar_warehouse_notify after insert or update on public.transactions for each row execute function solar_private.warehouse_notify();

create or replace function solar_private.warehouse_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('authenticated','anon') then
  if tg_op='INSERT' and (new.warehouse_status<>'pending' or new.warehouse_revision<>0 or new.warehouse_prepared_at is not null or new.warehouse_prepared_by is not null or new.warehouse_note<>'') then raise exception 'Use warehouse workflow' using errcode='42501';end if;
  if tg_op='UPDATE' and (new.warehouse_status,new.warehouse_revision,new.warehouse_prepared_at,new.warehouse_prepared_by,new.warehouse_note) is distinct from (old.warehouse_status,old.warehouse_revision,old.warehouse_prepared_at,old.warehouse_prepared_by,old.warehouse_note) then raise exception 'Use warehouse workflow' using errcode='42501';end if;
 end if;
 return new;
end $$;
revoke all on function solar_private.warehouse_guard() from public,anon,authenticated;
create trigger solar_warehouse_guard before insert or update on public.transactions for each row execute function solar_private.warehouse_guard();
-- An administrator changing already prepared lines reopens the preparation queue.
create or replace function solar_private.warehouse_items_changed() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public.transactions set warehouse_status='pending',warehouse_prepared_at=null,warehouse_prepared_by=null,warehouse_revision=warehouse_revision+1
 where id=coalesce(new.transaction_id,old.transaction_id) and kind in ('sale','system') and warehouse_status='ready';
 return null;
end $$;
revoke all on function solar_private.warehouse_items_changed() from public,anon,authenticated;
create trigger solar_warehouse_items_changed after insert or update or delete on public.transaction_items for each row execute function solar_private.warehouse_items_changed();

create or replace function solar_private.warehouse_action(invoice_id bigint,expected_token text,action text,lines jsonb default null,note text default '') returns void
language plpgsql security definer set search_path='' as $$
declare j public.transactions; before_items jsonb; after_items jsonb; entry jsonb; oldline public.transaction_items; prod public.products;
 newqty numeric; oldqty numeric; newtotal numeric; newcost numeric; wanted jsonb; id_value bigint;
begin
 if auth.uid() is null or not solar_private.warehouse_allowed() then raise exception 'Not permitted' using errcode='42501';end if;
 if action not in ('save','ready','reopen') then raise exception 'Invalid action';end if;
 select * into j from public.transactions where id=invoice_id and kind in ('sale','system') for update;
 if j.id is null then raise exception 'الفاتورة غير متاحة' using errcode='42501';end if;
 if solar_private.warehouse_token(j.id) is distinct from expected_token then raise exception 'تغيّرت الفاتورة، حدّث الصفحة وحاول مجدداً' using errcode='40001';end if;
 if length(coalesce(note,''))>2000 then raise exception 'الملاحظات طويلة';end if;
 select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]'::jsonb) into before_items from public.transaction_items i where transaction_id=j.id;
 if action='save' then
  if j.installation_status in ('in_progress','completed','closed') then raise exception 'بدأ تنفيذ المنظومة؛ راجع الإداري قبل تعديل موادها';end if;
  if jsonb_typeof(lines) is distinct from 'array' or jsonb_array_length(lines)=0 or jsonb_array_length(lines)>300 then raise exception 'أضف مادة واحدة على الأقل';end if;
  if exists(select 1 from jsonb_array_elements(lines) e where jsonb_typeof(e->'qty') is distinct from 'number' or (e->>'qty')::numeric<=0 or (e->>'qty')::numeric>1000000 or (e->>'qty')::numeric<>round((e->>'qty')::numeric,3)) then raise exception 'الكميات غير صحيحة';end if;
  if (select count(*) from jsonb_array_elements(lines) e where e->>'lineId' is not null)<>(select count(distinct e->>'lineId') from jsonb_array_elements(lines) e where e->>'lineId' is not null) then raise exception 'مادة مكررة';end if;
  -- Lock the union of old/new products in a stable order.
  perform 1 from public.products p where p.id in (select i.product_id from public.transaction_items i where i.transaction_id=j.id union select (e->>'productId')::bigint from jsonb_array_elements(lines) e) order by p.id for update;
  for entry in select value from jsonb_array_elements(lines) loop
   if entry->>'lineId' is not null then
    select * into oldline from public.transaction_items where id=(entry->>'lineId')::bigint and transaction_id=j.id;
    if oldline.id is null or oldline.product_id is distinct from (entry->>'productId')::bigint then raise exception 'مادة لا تخص هذه الفاتورة';end if;
   else
    if j.kind<>'system' then raise exception 'إضافة مادة جملة جديدة تحتاج الإداري لتحديد سعر البيع';end if;
    if not exists(select 1 from public.products where id=(entry->>'productId')::bigint) then raise exception 'المادة غير موجودة';end if;
   end if;
  end loop;
  for id_value in select product_id from public.transaction_items where transaction_id=j.id union select (e->>'productId')::bigint from jsonb_array_elements(lines) e loop
   select coalesce(sum(qty),0) into oldqty from public.transaction_items where transaction_id=j.id and product_id=id_value;
   select coalesce(sum((e->>'qty')::numeric),0) into newqty from jsonb_array_elements(lines) e where (e->>'productId')::bigint=id_value;
   update public.products set qty=qty+oldqty-newqty,updated_at=now() where id=id_value and qty+oldqty-newqty>=0;
   if not found then raise exception 'الكمية المتوفرة لا تكفي أو المادة غير متاحة';end if;
  end loop;
  delete from public.transaction_items i where transaction_id=j.id and not exists(select 1 from jsonb_array_elements(lines) e where (e->>'lineId')::bigint=i.id);
  for entry in select value from jsonb_array_elements(lines) loop
   if entry->>'lineId' is not null then update public.transaction_items set qty=(entry->>'qty')::numeric where id=(entry->>'lineId')::bigint and transaction_id=j.id;
   else
    select * into prod from public.products where id=(entry->>'productId')::bigint;
    insert into public.transaction_items(transaction_id,product_id,product_name,brand_name,category,qty,price,cost)
    values(j.id,prod.id,prod.name,(select name from public.brands where id=prod.brand_id),prod.category,(entry->>'qty')::numeric,0,prod.cost);
   end if;
  end loop;
  select coalesce(sum(qty*price),0),coalesce(sum(qty*cost),0) into newtotal,newcost from public.transaction_items where transaction_id=j.id;
  update public.transactions set subtotal=case when kind='sale' then newtotal else subtotal end,total=case when kind='sale' then newtotal+coalesce(expenses,0) else total end,
  cost=newcost,profit=case when kind='sale' then newtotal-newcost-coalesce(installation_expenses,0) else total-newcost-coalesce(expenses,0)-coalesce(installation_expenses,0) end,
  warehouse_status='pending',warehouse_prepared_at=null,warehouse_prepared_by=null,warehouse_note=coalesce(note,''),warehouse_revision=warehouse_revision+1 where id=j.id;
  perform solar_private.warehouse_notice(j.created_by,j.id,'warehouse_edited');
 elsif action='ready' then
  if j.warehouse_status<>'pending' then raise exception 'الفاتورة مجهزة مسبقاً';end if;
  if not exists(select 1 from public.transaction_items where transaction_id=j.id) then raise exception 'الفاتورة بدون مواد';end if;
  update public.transactions set warehouse_status='ready',warehouse_prepared_at=now(),warehouse_prepared_by=auth.uid(),warehouse_note=coalesce(note,''),warehouse_revision=warehouse_revision+1 where id=j.id;
 else
  if j.warehouse_status<>'ready' then raise exception 'الفاتورة بانتظار التجهيز أصلاً';end if;
  update public.transactions set warehouse_status='pending',warehouse_prepared_at=null,warehouse_prepared_by=null,warehouse_revision=warehouse_revision+1 where id=j.id;
 end if;
 select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]'::jsonb) into after_items from public.transaction_items i where transaction_id=j.id;
 insert into solar_private.warehouse_audit(invoice_id,actor_id,action,before_items,after_items) values(j.id,auth.uid(),action,before_items,after_items);
end $$;
revoke all on function solar_private.warehouse_action(bigint,text,text,jsonb,text) from public,anon;
grant execute on function solar_private.warehouse_action(bigint,text,text,jsonb,text) to authenticated;
create or replace function public.solar_warehouse_action(invoice_id bigint,expected_token text,action text,lines jsonb default null,note text default '') returns void language sql security invoker set search_path='' as $$select solar_private.warehouse_action(invoice_id,expected_token,action,lines,note)$$;
revoke all on function public.solar_warehouse_action(bigint,text,text,jsonb,text) from public,anon;
grant execute on function public.solar_warehouse_action(bigint,text,text,jsonb,text) to authenticated;

create or replace function solar_private.stock_quantities() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.user_type<>'installer' and (p.user_type='warehouse' or p.is_admin or p.permissions->>'stock'='true' or p.permissions->>'stockMovement'='true' or p.permissions->>'warehouse'='true')) then raise exception 'Not permitted' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name,'brand',b.name,'category',p.category,'qty',p.qty) order by p.name,p.id),'[]'::jsonb) from public.products p left join public.brands b on b.id=p.brand_id);
end $$;
revoke all on function solar_private.stock_quantities() from public,anon;
grant execute on function solar_private.stock_quantities() to authenticated;
create or replace function public.solar_stock_quantities() returns jsonb language sql security invoker set search_path='' as $$select solar_private.stock_quantities()$$;
revoke all on function public.solar_stock_quantities() from public,anon;
grant execute on function public.solar_stock_quantities() to authenticated;

create or replace function solar_private.stock_movements(product_filter bigint default null,customer_filter text default '',date_from date default null,date_to date default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.user_type<>'installer' and (p.user_type='warehouse' or p.is_admin or p.permissions->>'stockMovement'='true' or p.permissions->>'warehouse'='true')) then raise exception 'Not permitted' using errcode='42501';end if;
 with movements as (
  select i.id,i.product_id,i.product_name,i.brand_name,i.category,i.qty,t.id invoice_id,t.receipt_no,t.kind,t.party_name,t.created_at,
  case when t.kind='purchase' then i.qty else -i.qty end delta,p.qty current_qty
  from public.transaction_items i join public.transactions t on t.id=i.transaction_id join public.products p on p.id=i.product_id
  where t.kind in ('purchase','sale','system') and (product_filter is null or i.product_id=product_filter)
 ), balances as (
  select *,current_qty-sum(delta) over(partition by product_id)+sum(delta) over(partition by product_id order by created_at,invoice_id,id rows unbounded preceding) balance from movements
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'productId',product_id,'name',product_name,'brand',brand_name,'category',category,'receiptNo',receipt_no,'kind',kind,'party',party_name,'date',created_at,'inQty',case when delta>0 then qty else 0 end,'outQty',case when delta<0 then qty else 0 end,'balance',balance) order by created_at,invoice_id,id),'[]'::jsonb) into result from balances
 where (customer_filter='' or (kind in ('sale','system') and strpos(lower(coalesce(party_name,'')),lower(customer_filter))>0))
 and (date_from is null or created_at >= (date_from::timestamp at time zone 'Asia/Baghdad'))
 and (date_to is null or created_at < ((date_to+1)::timestamp at time zone 'Asia/Baghdad'));
 return result;
end $$;
revoke all on function solar_private.stock_movements(bigint,text,date,date) from public,anon;
grant execute on function solar_private.stock_movements(bigint,text,date,date) to authenticated;
create or replace function public.solar_stock_movements(product_filter bigint default null,customer_filter text default '',date_from date default null,date_to date default null) returns jsonb language sql security invoker set search_path='' as $$select solar_private.stock_movements(product_filter,customer_filter,date_from,date_to)$$;
revoke all on function public.solar_stock_movements(bigint,text,date,date) from public,anon;
grant execute on function public.solar_stock_movements(bigint,text,date,date) to authenticated;

-- Add routing metadata to existing encrypted push payloads.
do $$ declare definition text;begin
 select pg_get_functiondef('public.solar_push_claim()'::regprocedure) into definition;
 definition:=replace(definition,'''jobId'',n.job_id,','''jobId'',n.job_id,''event'',n.event,');
 execute definition;
end $$;
