-- Editable wholesale receipts; private audit survives deletion of the original row.
create table solar_private.receipt_change_audit(
 id bigint generated always as identity primary key,
 request_id uuid not null unique, actor_id uuid not null references public.profiles(id),
 transaction_id bigint not null, action text not null, before_row jsonb not null, after_row jsonb,
 created_at timestamptz not null default now()
);
alter table solar_private.receipt_change_audit enable row level security;
revoke all on solar_private.receipt_change_audit from public,anon,authenticated;

create function solar_private.customer_payment_manage(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
#variable_conflict use_variable
declare p public.profiles;t public.transactions;c public.customers;prior solar_private.finance_requests;
 rows jsonb;result jsonb;ledger jsonb;balance numeric;cash_before numeric;cash_after numeric;new_total numeric;amount numeric;token text;uid uuid;cid bigint;page_offset integer;search text;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'customerPayment','false')='true') then raise exception 'لا تملك صلاحية تسديد الجملة' using errcode='42501';end if;
 if action is null or action not in ('list','get','update','delete') or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب غير صحيح';end if;
 if action='list' then
  page_offset:=greatest(0,least(coalesce((payload->>'offset')::integer,0),1000000));search:=solar_private.customer_name_key(coalesce(payload->>'query',''));
  select coalesce(jsonb_agg(v.row order by v.created_at desc,v.id desc),'[]') into rows from (
   select tx.id,tx.created_at,jsonb_build_object('id',tx.id,'receiptNo',tx.receipt_no,'date',tx.created_at,'party',cu.name,'customerId',cu.id,'total',tx.total,'cash',tx.cash,'notes',tx.notes,'mode',tx.payment_mode,
    'cashOwnerName',coalesce(o.display_name,o.username,'غير مخصص'),'canManage',p.is_admin or coalesce(tx.cashbox_user_id,tx.created_by)=p.id) row
   from public.transactions tx join solar_private.customer_movement_links() l on l.transaction_id=tx.id join public.customers cu on cu.id=l.customer_id left join public.profiles o on o.id=coalesce(tx.cashbox_user_id,tx.created_by)
   where tx.kind='customer_payment' and cu.customer_type='wholesale' and coalesce(tx.payment_mode,'') not in ('opening_balance','account_reconciliation')
    and (p.is_admin or cu.owner_id=p.id) and (payload->>'customerId' is null or cu.id=(payload->>'customerId')::bigint)
    and (search='' or strpos(solar_private.customer_name_key(cu.name||coalesce(tx.notes,'')||coalesce(tx.receipt_no::text,tx.id::text)),search)>0)
   order by tx.created_at desc,tx.id desc limit 51 offset page_offset
  ) v;
  return jsonb_build_object('rows',rows,'offset',page_offset);
 end if;
 if action in ('update','delete') then
  if request_id is null then raise exception 'رقم طلب الحفظ مطلوب';end if;
  perform pg_advisory_xact_lock(7311,1);
  select * into prior from solar_private.finance_requests r where r.request_id=customer_payment_manage.request_id;
  if found then
   if prior.actor_id=p.id and prior.action='customer_payment_'||action and prior.payload=payload then return prior.response;end if;
   raise exception 'طلب مكرر ببيانات مختلفة' using errcode='40001';
  end if;
 end if;
 select * into t from public.transactions where id=(payload->>'id')::bigint for update;
 if t.id is null or t.kind<>'customer_payment' or coalesce(t.payment_mode,'') in ('opening_balance','account_reconciliation') then raise exception 'التسديد غير موجود أو هو رصيد افتتاحي؛ حدّث القائمة' using errcode='40001';end if;
 select l.customer_id into cid from solar_private.customer_movement_links() l where l.transaction_id=t.id;
 select * into c from public.customers where id=cid and customer_type='wholesale';
 uid:=coalesce(t.cashbox_user_id,t.created_by);
 if c.id is null or (not p.is_admin and (c.owner_id is distinct from p.id or uid is distinct from p.id)) then raise exception 'تعديل وحذف هذا الوصل متاح لصاحب القاصة أو الأدمن فقط' using errcode='42501';end if;
 if uid is null or t.cash_currency<>'IQD' or t.fx_accounted or t.system_invoice_id is not null or t.finance_request_id is not null or not((t.cash and t.total>0) or(not t.cash and t.total<0)) then raise exception 'هذا الوصل يحتاج مراجعة مالية مستقلة';end if;
 ledger:=solar_private.customer_ledger(c.id);select coalesce(sum((x->>'effect')::numeric),0) into balance from jsonb_array_elements(ledger) x;
 token:=md5(to_jsonb(t)::text||ledger::text);cash_before:=solar_private.cash_balance(uid);
 if action='get' then
  return jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'date',t.created_at,'party',c.name,'customerId',c.id,'total',t.total,'cash',t.cash,'mode',t.payment_mode,'notes',t.notes,'token',token,'balance',balance,'cashBalance',cash_before,'cashOwnerName',(select coalesce(o.display_name,o.username,'') from public.profiles o where o.id=uid));
 end if;
 if payload->>'expectedToken' is distinct from token then raise exception 'تغير الوصل أو حساب العميل؛ افتح التعديل مجدداً' using errcode='40001';end if;
 if action='update' then
  amount:=(payload->>'amount')::numeric;
  if amount is null or not(amount>0 and amount<=1000000000000) or amount::text in ('NaN','Infinity','-Infinity') or round(amount,2)<>amount or length(coalesce(payload->>'notes',''))>2000 then raise exception 'أدخل مبلغاً صحيحاً وملاحظات لا تتجاوز 2000 حرف';end if;
  new_total:=case when t.cash then amount else -amount end;
  if t.cash and new_total>t.total and balance+t.total-new_total<0 then raise exception 'المبلغ أكبر من الرصيد المتاح للتسديد';end if;
 else new_total:=0;end if;
 cash_after:=cash_before+case when t.cash then new_total-t.total else 0 end;
 if t.cash and cash_after<0 then raise exception 'رصيد قاصة صاحب الوصل لا يكفي لعكس هذا التسديد؛ أعد المبلغ للقاصة أولاً' using errcode='P0002';end if;
 if exists(select 1 from public.cash_ledger where transaction_id=t.id) or exists(select 1 from public.transaction_items where transaction_id=t.id) or exists(select 1 from public.solar_cash_entries where job_id=t.id) then raise exception 'الوصـل مرتبط بحركة أخرى ويحتاج مراجعة مستقلة';end if;
 if action='update' then
  update public.transactions set total=new_total,notes=coalesce(payload->>'notes','') where id=t.id;
 else delete from public.transactions where id=t.id;end if;
 insert into solar_private.receipt_change_audit(request_id,actor_id,transaction_id,action,before_row,after_row)
 values(request_id,p.id,t.id,'customer_payment_'||action,to_jsonb(t),(select to_jsonb(n) from public.transactions n where n.id=t.id));
 result:=jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'party',c.name,'total',new_total,'oldBalance',balance,'remaining',balance+t.total-new_total,'cashBefore',cash_before,'cashAfter',solar_private.cash_balance(uid),'action',action);
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response) values(request_id,p.id,'customer_payment_'||action,payload,result);
 return result;
end $$;
create function public.solar_customer_payment_manage(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select solar_private.customer_payment_manage(action,request_id,payload)$$;
revoke all on function solar_private.customer_payment_manage(text,uuid,jsonb),public.solar_customer_payment_manage(text,uuid,jsonb) from public,anon;
grant execute on function solar_private.customer_payment_manage(text,uuid,jsonb),public.solar_customer_payment_manage(text,uuid,jsonb) to authenticated;

-- Keep the verified weighted-cost engine; enable payment mode changes only for sale.
do $$declare def text;needle text;begin
 select pg_get_functiondef('solar_private.invoice_save_v333(uuid,jsonb)'::regprocedure) into def;
 needle:='if old_invoice.cash is distinct from (mode=''cash'') then';
 if strpos(def,needle)=0 then raise exception 'Review saved invoice mode guard';end if;
 def:=replace(def,needle,'if kind<>''sale'' and old_invoice.cash is distinct from (mode=''cash'') then');
 needle:='if existing and kind=''sale'' and old_invoice.cash and old_invoice.total-total>solar_private.cash_balance(owner_id) then';
 if strpos(def,needle)=0 then raise exception 'Review sale cash reversal guard';end if;
 def:=replace(def,needle,'if existing and kind=''sale'' and (case when old_invoice.cash then old_invoice.total else 0 end)-(case when cash then total else 0 end)>solar_private.cash_balance(owner_id) then');
 needle:='subtotal=subtotal,total=total,expenses=expenses,cost=cost,profit=';
 if strpos(def,needle)=0 then raise exception 'Review saved invoice update';end if;
 def:=replace(def,needle,'cash=cash,payment_mode=mode,subtotal=subtotal,total=total,expenses=expenses,cost=cost,profit=');
 execute def;
end $$;
create or replace function solar_private.invoice_save(request_id uuid,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;before_row public.transactions;after_row public.transactions;begin
 perform pg_advisory_xact_lock(7311,1);
 if payload->>'kind'='sale' and payload->>'invoiceId' is not null then select * into before_row from public.transactions where id=(payload->>'invoiceId')::bigint;end if;
 if payload->>'kind'='purchase' then perform set_config('solar.fx_context',case when payload ? 'marketRate' then payload::text else '{}' end,true);end if;
 result:=solar_private.invoice_save_v333(request_id,payload);
 perform set_config('solar.fx_context','',true);
 if before_row.id is not null then
  select * into after_row from public.transactions where id=before_row.id;
  if before_row.cash is distinct from after_row.cash then
   insert into solar_private.receipt_change_audit(request_id,actor_id,transaction_id,action,before_row,after_row) values(request_id,auth.uid(),before_row.id,'sale_payment_mode',to_jsonb(before_row),to_jsonb(after_row));
  end if;
 end if;
 return result;
end $$;
-- An old create request must not display a stale receipt after a later edit/delete.
do $$declare def text;needle text;begin
 select pg_get_functiondef('solar_private.customer_payment_save(uuid,jsonb)'::regprocedure) into def;
 needle:='then return prior.response;end if;';
 if strpos(def,needle)=0 then raise exception 'Review customer receipt replay';end if;
 def:=replace(def,needle,'then if exists(select 1 from solar_private.receipt_change_audit a where a.transaction_id=(prior.response->>''id'')::bigint) then raise exception ''تم تعديل أو حذف هذا الوصل؛ حدّث سجل التسديدات'' using errcode=''40001'';end if;return prior.response;end if;');
 execute def;
end $$;
