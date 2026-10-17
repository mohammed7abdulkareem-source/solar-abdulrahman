-- A system customer can owe an opening balance without an invoice. Account
-- receipts therefore have an optional, persistent invoice allocation.
alter table public.transactions add column system_invoice_id bigint references public.transactions(id) on delete restrict;
create index transactions_system_invoice_idx on public.transactions(system_invoice_id) where system_invoice_id is not null;
alter table public.transactions add constraint system_payment_link_kind check(system_invoice_id is null or kind='system_payment');
create table solar_private.system_payment_requests(
 request_id uuid primary key,actor_id uuid not null references public.profiles(id),
 payload jsonb not null,response jsonb not null,created_at timestamptz not null default now()
);
alter table solar_private.system_payment_requests enable row level security;
revoke all on solar_private.system_payment_requests from public,anon,authenticated;

create function solar_private.system_payment_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('anon','authenticated') then
  if (tg_op<>'INSERT' and old.kind='system_payment') or(tg_op<>'DELETE' and new.kind='system_payment') then
   raise exception 'حدّث البرنامج واستخدم تسديد المنظومات المحمي' using errcode='42501';
  end if;
  if tg_op='UPDATE' and old.kind='system' and exists(select 1 from public.transactions t where t.system_invoice_id=old.id) and
   (new.id,new.kind,new.party_id,new.party_name,new.total,new.cash) is distinct from(old.id,old.kind,old.party_id,old.party_name,old.total,old.cash) then
   raise exception 'هذه المنظومة مرتبطة بتسديدات محفوظة؛ لا يمكن تغيير حسابها';
  end if;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
create trigger solar_system_payment_guard before insert or update or delete on public.transactions for each row execute function solar_private.system_payment_guard();
revoke all on function solar_private.system_payment_guard() from public,anon,authenticated;

create function solar_private.system_payment_context(customer_id bigint default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;c public.customers;ledger jsonb;systems jsonb;balance numeric;directory jsonb;token text;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'systemPayment','false')='true') then raise exception 'لا تملك صلاحية تسديد المنظومات' using errcode='42501';end if;
 if customer_id is null then
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'phone',coalesce(a.phone,''),'customer_type',a.customer_type,'owner_name',coalesce(o.display_name,o.username,'غير مخصص')) order by a.name,a.id),'[]') into directory
  from public.customers a left join public.profiles o on o.id=a.owner_id
  where a.active and(p.is_admin or a.owner_id=p.id) and(a.customer_type='system' or exists(
   select 1 from public.transactions t join solar_private.customer_movement_links() l on l.transaction_id=t.id where t.kind='system' and l.customer_id=a.id));
  return jsonb_build_object('customers',directory);
 end if;
 select * into c from public.customers where id=customer_id and active;
 if c.id is null or (p.is_admin or c.owner_id=p.id) is distinct from true then raise exception 'هذا العميل غير متاح ضمن صلاحياتك' using errcode='42501';end if;
 if c.customer_type<>'system' and not exists(select 1 from public.transactions t join solar_private.customer_movement_links() l on l.transaction_id=t.id where t.kind='system' and l.customer_id=c.id) then raise exception 'اختر عميل منظومات';end if;
 ledger:=solar_private.customer_ledger(c.id);
 select coalesce(sum((x->>'effect')::numeric),0) into balance from jsonb_array_elements(ledger) x;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'date',t.created_at,'total',t.total,'paid',coalesce(m.paid,0),
  'remaining',case when t.cash then 0 else t.total end-coalesce(m.paid,0),
  'items',(select coalesce(jsonb_agg(jsonb_build_object('id',i.product_id,'name',i.product_name,'brand',i.brand_name,'category',i.category,'qty',i.qty) order by i.id),'[]') from public.transaction_items i where i.transaction_id=t.id)) order by t.created_at,t.id),'[]') into systems
 from public.transactions t join solar_private.customer_movement_links() l on l.transaction_id=t.id
 left join lateral(select sum(x.total) paid from public.transactions x where x.system_invoice_id=t.id and x.kind='system_payment') m on true
 where t.kind='system' and l.customer_id=c.id;
 token:=md5(jsonb_build_object('customer',to_jsonb(c),'ledger',ledger,'systems',systems)::text);
 return jsonb_build_object('id',c.id,'name',c.name,'phone',c.phone,'balance',balance,'systems',systems,'token',token,
  'cashBalance',solar_private.cash_balance(p.id),'cashOwnerName',coalesce(p.display_name,p.username,'المستلم'),
  'unallocated',coalesce((select sum(t.total) from public.transactions t join solar_private.customer_movement_links() l on l.transaction_id=t.id where l.customer_id=c.id and t.kind='system_payment' and t.system_invoice_id is null and t.cash),0));
end $$;

create function solar_private.system_payment_save(request_id uuid,payload jsonb) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
#variable_conflict use_variable
declare p public.profiles;c public.customers;prior solar_private.system_payment_requests;t public.transactions;
 account jsonb;invoice jsonb;after_account jsonb;amount numeric;mode text;invoice_id bigint;customer_id bigint;
 account_before numeric;invoice_before numeric;cash_before numeric;result jsonb;new_id bigint;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'systemPayment','false')='true') then raise exception 'لا تملك صلاحية تسديد المنظومات' using errcode='42501';end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب الحفظ غير صحيح';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into prior from solar_private.system_payment_requests r where r.request_id=system_payment_save.request_id;
 if found then
  if prior.actor_id=p.id and prior.payload=payload then
   if not exists(select 1 from public.transactions where id=(prior.response->>'id')::bigint) then raise exception 'الحركة حذفت أو صفّرت؛ حدّث البيانات' using errcode='40001';end if;
   return prior.response;
  end if;
  raise exception 'طلب مكرر ببيانات مختلفة' using errcode='40001';
 end if;
 customer_id:=(payload->>'customerId')::bigint;invoice_id:=nullif(payload->>'invoiceId','')::bigint;
 amount:=(payload->>'amount')::numeric;mode:=payload->>'mode';
 if amount is null or not(amount>0 and amount<=1000000000000) or round(amount,2)<>amount or mode is null or mode not in ('payment','charge_extra_expense','charge_old_balance','charge_other') or length(coalesce(payload->>'notes',''))>2000 then raise exception 'أدخل مبلغاً ونوع حركة صحيحين';end if;
 if mode<>'payment' and length(trim(coalesce(payload->>'notes','')))=0 then raise exception 'اكتب سبب الإضافة على حساب الزبون';end if;
 account:=solar_private.system_payment_context(customer_id);
 if account->>'id' is null then raise exception 'اختر العميل';end if;
 if payload->>'expectedToken' is distinct from account->>'token' then raise exception 'تغير حساب الزبون؛ راجع الرصيد الجديد قبل الحفظ' using errcode='40001';end if;
 account_before:=(account->>'balance')::numeric;cash_before:=(account->>'cashBalance')::numeric;
 if invoice_id is not null then
  select x into invoice from jsonb_array_elements(account->'systems') x where (x->>'id')::bigint=invoice_id;
  if invoice is null then raise exception 'المنظومة لا تخص هذا الزبون أو لم تعد موجودة';end if;
  invoice_before:=(invoice->>'remaining')::numeric;
  if mode='payment' and amount>greatest(invoice_before,0) then raise exception 'المبلغ أكبر من المتبقي على المنظومة';end if;
 end if;
 if mode='payment' and amount>greatest(account_before,0) then raise exception 'المبلغ أكبر من الرصيد المتبقي على حساب الزبون';end if;
 select * into c from public.customers where id=customer_id;
 new_id:=greatest((extract(epoch from clock_timestamp())*1000)::bigint,coalesce((select max(id)+1 from public.transactions),1));
 insert into public.transactions(id,kind,party_type,party_id,party_name,system_invoice_id,total,cash,payment_mode,created_by,cashbox_user_id,notes)
 values(new_id,'system_payment','customer',c.id,c.name,invoice_id,case when mode='payment' then amount else -amount end,mode='payment',mode,p.id,p.id,coalesce(payload->>'notes','')) returning * into t;
 after_account:=solar_private.system_payment_context(c.id);
 result:=jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'kind',t.kind,'customerId',c.id,'party',c.name,'date',t.created_at,'total',t.total,'amount',amount,'cash',t.cash,'mode',mode,'notes',t.notes,
  'systemInvoiceId',invoice_id,'invoice',invoice,'oldBalance',account_before,'remaining',(after_account->>'balance')::numeric,
  'invoiceBefore',invoice_before,'invoiceAfter',case when invoice_id is not null then invoice_before-t.total end,
  'cashBefore',cash_before,'cashAfter',(after_account->>'cashBalance')::numeric,'cashOwnerName',account->>'cashOwnerName');
 insert into solar_private.system_payment_requests(request_id,actor_id,payload,response) values(request_id,p.id,payload,result);
 return result;
end $$;
revoke all on function solar_private.system_payment_context(bigint),solar_private.system_payment_save(uuid,jsonb) from public,anon;
grant execute on function solar_private.system_payment_context(bigint),solar_private.system_payment_save(uuid,jsonb) to authenticated;
create function public.solar_system_payment_context(customer_id bigint default null) returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.system_payment_context(customer_id)$$;
create function public.solar_system_payment_save(request_id uuid,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select solar_private.system_payment_save(request_id,payload)$$;
revoke all on function public.solar_system_payment_context(bigint),public.solar_system_payment_save(uuid,jsonb) from public,anon;
grant execute on function public.solar_system_payment_context(bigint),public.solar_system_payment_save(uuid,jsonb) to authenticated;

-- Display an allocation in account statements, but do not guess allocations for
-- historical receipts whose old client never persisted an invoice identifier.
do $$declare def text;needle text:='''date'',t.created_at';begin
 select pg_get_functiondef('solar_private.customer_ledger(bigint)'::regprocedure) into def;
 if strpos(def,needle)=0 then raise exception 'Review statement invoice allocation integration';end if;
 execute replace(def,needle,'''systemInvoiceId'',t.system_invoice_id,''systemReceiptNo'',(select i.receipt_no from public.transactions i where i.id=t.system_invoice_id),'||needle);
 select pg_get_functiondef('solar_private.sale_delete_data(bigint)'::regprocedure) into def;
 needle:='if exists(select 1 from public.solar_cash_entries';
 if strpos(def,needle)=0 then raise exception 'Review deletion payment allocation integration';end if;
 execute replace(def,needle,'if exists(select 1 from public.transactions x where x.system_invoice_id=t.id) then blocked:=''هذه المنظومة مرتبطة بتسديدات محفوظة؛ لا يمكن حذفها''; elsif exists(select 1 from public.solar_cash_entries');
 if to_regprocedure('solar_private.reset_snapshot()') is not null then
  select pg_get_functiondef('solar_private.reset_snapshot()'::regprocedure) into def;
  execute replace(def,'''solar_private.receipt_counters''','''solar_private.system_payment_requests'',''solar_private.receipt_counters''');
  select pg_get_functiondef('solar_private.lock_reset_tables()'::regprocedure) into def;
  execute replace(def,'solar_private.receipt_counters','solar_private.system_payment_requests,solar_private.receipt_counters');
  select pg_get_functiondef('public.solar_execute_reset(uuid,uuid,text)'::regprocedure) into def;
  execute replace(def,'delete from public.transactions','delete from solar_private.system_payment_requests; delete from public.transactions');
 end if;
end $$;
notify pgrst,'reload schema';
