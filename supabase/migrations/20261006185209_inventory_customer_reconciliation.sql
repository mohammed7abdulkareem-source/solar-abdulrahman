-- Reconciliation is an append-only, non-cash entry; never rewrite invoices.
create table solar_private.reconciliation_requests (
 id uuid primary key, actor_id uuid not null references public.profiles(id),
 action text not null, payload jsonb not null, result jsonb not null,
 created_at timestamptz not null default now()
);
create table solar_private.stock_adjustments (
 id bigint generated always as identity primary key,
 product_id bigint not null references public.products(id),
 old_qty numeric not null, actual_qty numeric not null check(actual_qty>=0),
 note text not null, actor_id uuid not null references public.profiles(id),
 created_at timestamptz not null default clock_timestamp()
);
alter table solar_private.reconciliation_requests enable row level security;
alter table solar_private.stock_adjustments enable row level security;
revoke all on solar_private.reconciliation_requests,solar_private.stock_adjustments from public,anon,authenticated;

-- Internal ledger shared by matching and the authorized statement API.
create function solar_private.customer_ledger(customer_id bigint) returns jsonb
language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'kind',t.kind,'mode',t.payment_mode,
 'date',t.created_at,'total',t.total,'cash',t.cash,'notes',t.notes,'effect',
 case when t.kind in ('customer_payment','system_payment') then -t.total when t.kind='sale' and t.cash then 0 else t.total end)
 order by t.created_at,t.id),'[]'::jsonb)
 from public.transactions t join public.customers c on c.id=customer_id
 where t.kind in ('sale','system','customer_payment','system_payment') and
 (t.party_id=c.id or (t.party_id is null and t.party_name=c.name and (select count(*) from public.customers x where x.name=c.name)=1))
$$;
revoke all on function solar_private.customer_ledger(bigint) from public,anon,authenticated;
create function solar_private.customer_statement(customer_id bigint) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; c public.customers; rows jsonb; balance numeric;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 select * into c from public.customers where id=customer_id;
 if p.id is null or p.user_type in ('installer','warehouse') or c.id is null or
 not(p.is_admin or (c.owner_id=p.id and p.permissions->>'customerStatement'='true')) then raise exception 'لا تملك صلاحية كشف هذا العميل' using errcode='42501';end if;
 rows:=solar_private.customer_ledger(c.id);
 select coalesce(sum((r->>'effect')::numeric),0) into balance from jsonb_array_elements(rows) r;
 return jsonb_build_object('rows',rows,'balance',balance,'token',md5(rows::text),'name',c.name);
end $$;
revoke all on function solar_private.customer_statement(bigint) from public,anon;
grant execute on function solar_private.customer_statement(bigint) to authenticated;
create function public.solar_customer_statement(customer_id bigint) returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.customer_statement(customer_id)$$;
revoke all on function public.solar_customer_statement(bigint) from public,anon;
grant execute on function public.solar_customer_statement(bigint) to authenticated;

create function solar_private.reconcile(action text,request_id uuid,payload jsonb) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare p public.profiles; c public.customers; product public.products; prior solar_private.reconciliation_requests;
 result jsonb; rows jsonb; old_balance numeric; target numeric; delta numeric; movement_id bigint; adjustment_id bigint; owner uuid;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') then raise exception 'غير مسموح' using errcode='42501';end if;
 if request_id is null or payload is null or action not in ('create_customer','customer_balance','stock_balance') or action is null then raise exception 'طلب غير صحيح';end if;
 if not(p.is_admin or (action='create_customer' and p.permissions->>'customers'='true') or
 (action='customer_balance' and p.permissions->>'customerReconcile'='true' and p.permissions->>'customerStatement'='true') or
 (action='stock_balance' and p.permissions->>'stockAdjust'='true')) then raise exception 'لا تملك صلاحية هذه العملية' using errcode='42501';end if;
 -- Same lock as invoices, cash writes and reset: avoid a reconciliation racing a sale.
 perform pg_advisory_xact_lock(7311,1);
 select * into prior from solar_private.reconciliation_requests where id=request_id;
 if prior.id is not null then
  if prior.actor_id<>p.id or prior.action<>action or prior.payload<>payload then raise exception 'طلب مكرر ببيانات مختلفة' using errcode='40001';end if;
  return prior.result;
 end if;
 if action='stock_balance' then
  select * into product from public.products where id=(payload->>'productId')::bigint for update;
  if product.id is null then raise exception 'المادة غير موجودة';end if;
  target:=(payload->>'actual')::numeric;
  if target is null or not(target between 0 and 1000000000) or round(target,3)<>target then raise exception 'أدخل كمية فعلية صحيحة';end if;
  if product.qty is distinct from (payload->>'expected')::numeric then raise exception 'تغيّر رصيد المادة. حدّث الرصيد ثم راجع الجرد' using errcode='40001';end if;
  if length(trim(coalesce(payload->>'note','')))=0 then raise exception 'اكتب سبب التسوية';end if;
  insert into solar_private.stock_adjustments(product_id,old_qty,actual_qty,note,actor_id)
  values(product.id,product.qty,target,left(payload->>'note',2000),p.id) returning id into adjustment_id;
  update public.products set qty=target where id=product.id;
  result:=jsonb_build_object('id',adjustment_id,'previous',product.qty,'actual',target,'delta',target-product.qty);
 else
  if action='create_customer' then
   if length(trim(coalesce(payload->>'name','')))=0 or (payload->>'id')::bigint is null then raise exception 'اكتب اسم العميل';end if;
   owner:=case when p.is_admin then coalesce(nullif(payload->>'ownerId','')::uuid,p.id) else p.id end;
   if not exists(select 1 from public.profiles where id=owner and active and user_type not in ('installer','warehouse')) then raise exception 'اختر مستخدماً مسؤولاً فعالاً';end if;
   insert into public.customers(id,name,phone,customer_type,owner_id)
   values((payload->>'id')::bigint,trim(payload->>'name'),payload->>'phone',payload->>'customerType',owner) returning * into c;
   old_balance:=0;target:=coalesce((payload->>'openingBalance')::numeric,0);
  else
   select * into c from public.customers where id=(payload->>'customerId')::bigint for update;
   if c.id is null or not(p.is_admin or c.owner_id=p.id) then raise exception 'لا تملك صلاحية هذا العميل' using errcode='42501';end if;
   rows:=solar_private.customer_ledger(c.id);
   if md5(rows::text) is distinct from payload->>'token' then raise exception 'تغير حساب العميل. حدّث الكشف ثم راجع المطابقة' using errcode='40001';end if;
   select coalesce(sum((r->>'effect')::numeric),0) into old_balance from jsonb_array_elements(rows) r;
   target:=(payload->>'actual')::numeric;
   if length(trim(coalesce(payload->>'note','')))=0 then raise exception 'اكتب ملاحظة المطابقة';end if;
  end if;
  if target is null or not(target between -1000000000000000 and 1000000000000000) or round(target,2)<>target then raise exception 'أدخل رصيداً صحيحاً';end if;
  delta:=target-old_balance;
  if action='customer_balance' or payload->>'openingBalance' is not null then
   movement_id:=floor(extract(epoch from clock_timestamp())*1000000)::bigint;
   while exists(select 1 from public.transactions where id=movement_id) loop movement_id:=movement_id+1;end loop;
   insert into public.transactions(id,kind,party_type,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,notes,created_at)
   values(movement_id,case when c.customer_type='system' then 'system_payment' else 'customer_payment' end,'customer',c.id,c.name,-delta,false,
    case action when 'create_customer' then 'opening_balance' else 'account_reconciliation' end,p.id,p.id,
    case action when 'create_customer' then 'رصيد افتتاحي' else 'مطابقة حساب: '||left(payload->>'note',2000) end||
    ' | الرصيد السابق: '||old_balance||' | الرصيد المعتمد: '||target,clock_timestamp());
  end if;
  result:=jsonb_build_object('customerId',c.id,'previous',old_balance,'actual',target,'delta',delta,'movementId',movement_id);
 end if;
 insert into solar_private.reconciliation_requests(id,actor_id,action,payload,result) values(request_id,p.id,action,payload,result);
 return result;
end $$;
revoke all on function solar_private.reconcile(text,uuid,jsonb) from public,anon;
grant execute on function solar_private.reconcile(text,uuid,jsonb) to authenticated;
create function public.solar_reconcile(action text,request_id uuid,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select solar_private.reconcile(action,request_id,payload)$$;
revoke all on function public.solar_reconcile(text,uuid,jsonb) from public,anon;
grant execute on function public.solar_reconcile(text,uuid,jsonb) to authenticated;

-- A normal transaction upsert must not forge or erase reconciliations.
create function solar_private.guard_reconciliation() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('anon','authenticated') and
 ((tg_op<>'INSERT' and old.payment_mode in ('opening_balance','account_reconciliation')) or
 (tg_op<>'DELETE' and new.payment_mode in ('opening_balance','account_reconciliation'))) then
  raise exception 'استخدم إجراء الرصيد الافتتاحي أو مطابقة الحساب' using errcode='42501';
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
create trigger solar_reconciliation_guard before insert or update or delete on public.transactions for each row execute function solar_private.guard_reconciliation();

-- Stock adjustment rows join the same running balance as purchases and sales.
create or replace function solar_private.stock_movements(product_filter bigint default null,customer_filter text default '',date_from date default null,date_to date default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.user_type<>'installer' and (p.user_type='warehouse' or p.is_admin or p.permissions->>'stockMovement'='true' or p.permissions->>'warehouse'='true')) then raise exception 'Not permitted' using errcode='42501';end if;
 with movements as (
  select 'line:'||i.id id,i.product_id,i.product_name,i.brand_name,i.category,t.id invoice_id,t.receipt_no,t.kind,t.party_name,t.created_at,
  case when t.kind='purchase' then i.qty else -i.qty end delta,p.qty current_qty,''::text note
  from public.transaction_items i join public.transactions t on t.id=i.transaction_id join public.products p on p.id=i.product_id
  where t.kind in ('purchase','sale','system') and (product_filter is null or i.product_id=product_filter)
  union all
  select 'adjustment:'||a.id,a.product_id,p.name,b.name,p.category,a.id,a.id,'stock_adjustment','',a.created_at,
   a.actual_qty-a.old_qty,p.qty,a.note||' | السابق: '||a.old_qty||' | الفعلي: '||a.actual_qty
  from solar_private.stock_adjustments a join public.products p on p.id=a.product_id left join public.brands b on b.id=p.brand_id
  where product_filter is null or a.product_id=product_filter
 ), balances as (
  select *,current_qty-sum(delta) over(partition by product_id)+sum(delta) over(partition by product_id order by created_at,invoice_id,id rows unbounded preceding) balance from movements
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'productId',product_id,'name',product_name,'brand',brand_name,'category',category,'receiptNo',receipt_no,'kind',kind,'party',party_name,'date',created_at,'note',note,'inQty',greatest(delta,0),'outQty',greatest(-delta,0),'balance',balance) order by created_at,invoice_id,id),'[]'::jsonb) into result from balances
 where (customer_filter='' or (kind in ('sale','system') and strpos(lower(coalesce(party_name,'')),lower(customer_filter))>0))
 and (date_from is null or created_at >= (date_from::timestamp at time zone 'Asia/Baghdad'))
 and (date_to is null or created_at < ((date_to+1)::timestamp at time zone 'Asia/Baghdad'));
 return result;
end $$;

-- Opening credits and reconciliations are not cash collections / last payments.
do $$declare definition text;begin
 select pg_get_functiondef('solar_private.party_balances(text,date)'::regprocedure) into definition;
 definition:=replace(definition,'and t.total>0) as payment','and t.total>0 and coalesce(t.payment_mode,'''') not in (''opening_balance'',''account_reconciliation'')) as payment');
 execute definition;
 -- Include all new records in the existing backup/confirmation/reset workflow.
 select pg_get_functiondef('solar_private.reset_snapshot()'::regprocedure) into definition;
 definition:=replace(definition,'''solar_private.cash_transfers''','''solar_private.stock_adjustments'',''solar_private.reconciliation_requests'',''solar_private.cash_transfers''');execute definition;
 select pg_get_functiondef('solar_private.lock_reset_tables()'::regprocedure) into definition;
 definition:=replace(definition,'solar_private.cash_transfers,','solar_private.stock_adjustments,solar_private.reconciliation_requests,solar_private.cash_transfers,');execute definition;
 select pg_get_functiondef('public.solar_execute_reset(uuid,uuid,text)'::regprocedure) into definition;
 definition:=replace(definition,'delete from public.products;','delete from solar_private.stock_adjustments; delete from solar_private.reconciliation_requests; delete from public.products;');execute definition;
end $$;
