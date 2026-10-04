-- Stable, server allocated receipt numbers; each transaction kind starts at 1.
alter table public.transactions add column receipt_no bigint;
with numbered as (select id,row_number() over(partition by kind order by created_at,id) n from public.transactions)
update public.transactions t set receipt_no=n.n from numbered n where n.id=t.id;
alter table public.transactions alter column receipt_no set not null;
alter table public.transactions add constraint solar_receipt_positive check(receipt_no>0);
create unique index solar_receipt_number on public.transactions(kind,receipt_no);
create table solar_private.receipt_counters(kind text primary key,last_number bigint not null check(last_number>=0));
alter table solar_private.receipt_counters enable row level security;
revoke all on solar_private.receipt_counters from public,anon,authenticated;
insert into solar_private.receipt_counters select kind,max(receipt_no) from public.transactions group by kind;
create function solar_private.assign_receipt_number() returns trigger language plpgsql security definer set search_path='' as $$
declare existing bigint;
begin
 perform pg_advisory_xact_lock(7311,1);
 if tg_op='UPDATE' then new.receipt_no:=old.receipt_no;return new;end if;
 select receipt_no into existing from public.transactions where id=new.id;
 if existing is not null then new.receipt_no:=existing;return new;end if;
 insert into solar_private.receipt_counters(kind,last_number) values(new.kind,1)
 on conflict(kind) do update set last_number=solar_private.receipt_counters.last_number+1
 returning last_number into new.receipt_no;
 return new;
end $$;
revoke all on function solar_private.assign_receipt_number() from public,anon,authenticated;
create trigger solar_assign_receipt before insert or update on public.transactions for each row execute function solar_private.assign_receipt_number();

-- Retain a private snapshot before a user-requested business-data reset.
create table solar_private.reset_backups(id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),data jsonb not null);
alter table solar_private.reset_backups enable row level security;
revoke all on solar_private.reset_backups from public,anon,authenticated;
create table solar_private.reset_record_ids(table_name text not null,record_id bigint not null,primary key(table_name,record_id));
alter table solar_private.reset_record_ids enable row level security;
revoke all on solar_private.reset_record_ids from public,anon,authenticated;
create function solar_private.guard_reset_records() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from solar_private.reset_record_ids where table_name=tg_table_name and record_id=new.id) then
 raise exception 'Old data was reset. Refresh the application before saving.' using errcode='40001';end if;
 return new;
end $$;
revoke all on function solar_private.guard_reset_records() from public,anon,authenticated;
create trigger solar_reset_record_guard before insert or update on public.transactions for each row execute function solar_private.guard_reset_records();
create trigger solar_reset_record_guard before insert or update on public.products for each row execute function solar_private.guard_reset_records();
create trigger solar_reset_record_guard before insert or update on public.brands for each row execute function solar_private.guard_reset_records();
create trigger solar_reset_record_guard before insert or update on public.customers for each row execute function solar_private.guard_reset_records();
create trigger solar_reset_record_guard before insert or update on public.suppliers for each row execute function solar_private.guard_reset_records();

CREATE OR REPLACE FUNCTION solar_private.installation_jobs()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles; result jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active=true;
 if p.id is null then raise exception 'Active login required' using errcode='42501'; end if;
 if p.user_type<>'installer' and not p.is_admin and not (coalesce(p.permissions->>'installations','false')='true' or coalesce(p.permissions->>'installationsAll','false')='true' or coalesce(p.permissions->>'system','false')='true') then return '[]'::jsonb; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
 'id',t.id,'receiptNo',t.receipt_no,'kind','system','party',t.party_name,'installerId',t.installer_id,
 'installerName',(select coalesce(x.display_name,x.username) from public.profiles x where x.id=t.installer_id),
 'installDate',t.install_date,'installTime',t.install_time,'customerPhone',t.customer_phone,'customerAddress',t.customer_address,
 'installationStatus',t.installation_status,'installationStartedAt',t.installation_started_at,
 'installationCompletedAt',t.installation_completed_at,'installationClosedAt',t.installation_closed_at,
 'installationRevision',t.installation_revision,'installationReport',t.installation_report,
 'canManage',solar_private.can_close_installation(t.created_by),
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.product_name,'brand',i.brand_name,'qty',i.qty) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]'::jsonb)
 ) || case when solar_private.can_close_installation(t.created_by) then
 jsonb_build_object('cost',t.cost,'expenses',t.expenses,'total',t.total,'installationExpenses',t.installation_expenses,'installationExpenseNotes',t.installation_expense_notes)
 else '{}'::jsonb end order by t.install_date nulls last,t.install_time nulls last,t.id),'[]'::jsonb) into result
 from public.transactions t where t.kind='system' and t.installation_status<>'none' and
 (case when p.user_type='installer' then t.installer_id=p.id else p.is_admin or coalesce(p.permissions->>'installationsAll','false')='true' or t.created_by=p.id end);
 return result;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.supplier_payment_get(payment_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles; t public.transactions;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type='installer' or not (p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true' or coalesce(p.permissions->>'supplierStatement','false')='true') then raise exception 'Not permitted' using errcode='42501';end if;
 select * into t from public.transactions where id=payment_id and kind='supplier_payment';
 if t.id is null or (p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id) is distinct from true then raise exception 'Not permitted' using errcode='42501';end if;
 return jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'supplierId',t.party_id,'party',t.party_name,'total',t.total,'notes',t.notes,'date',t.created_at,'token',md5(to_jsonb(t)::text));
end $function$;

CREATE OR REPLACE FUNCTION solar_private.sale_delete_data(invoice_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 return jsonb_build_object('receiptNo',t.receipt_no,'token',md5(to_jsonb(t)::text||line_data::text),'party',t.party_name,'total',t.total,'kind',t.kind,'blockedReason',blocked);
end $function$;

CREATE OR REPLACE FUNCTION solar_private.sales_history(search_text text DEFAULT ''::text, sale_kind text DEFAULT ''::text, date_from date DEFAULT NULL::date, date_to date DEFAULT NULL::date, job_status text DEFAULT ''::text, page_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 and (coalesce(search_text,'')='' or strpos(lower(coalesce(t.party_name,'')||' '||t.receipt_no::text),lower(search_text))>0)
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
end $function$;
