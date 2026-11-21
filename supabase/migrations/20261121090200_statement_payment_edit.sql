-- The customer account and the original cashier have separate ownership rules.
-- A statement may contain the balance effect of a receipt the reader cannot open.
create function solar_private.statement_payment_editable(t public.transactions, c public.customers, p public.profiles)
returns boolean language sql stable set search_path='' as $$
 select coalesce(p.active and p.user_type not in ('warehouse','installer')
  and t.kind in ('customer_payment','system_payment') and c.id is not null
  and (p.is_admin or (c.owner_id=p.id and t.created_by=p.id and coalesce(t.cashbox_user_id,t.created_by)=p.id))
  and (p.is_admin or solar_private.delete_kind_feature(p.permissions,t.kind))
  and (t.kind='system_payment' or (c.customer_type='wholesale' and t.system_invoice_id is null))
  and coalesce(t.cashbox_user_id,t.created_by) is not null
  and coalesce(t.payment_mode,'') not in ('opening_balance','account_reconciliation')
  and ((t.cash and t.total>0) or (not t.cash and t.total<0))
  and t.cash_currency='IQD' and t.source_currency='IQD' and t.account_currency='IQD'
  and not t.fx_accounted and not t.fx_pricing and t.finance_request_id is null
  and t.profit_settlement_id is null and t.profit_supplier_settlement_id is null
  and not exists(select 1 from public.cash_ledger l where l.transaction_id=t.id)
  and not exists(select 1 from public.transaction_items i where i.transaction_id=t.id)
  and not exists(select 1 from public.solar_cash_entries e where e.job_id=t.id)
  and not exists(select 1 from solar_private.wallet_fx_entries w where w.transaction_id=t.id)
  and not exists(select 1 from solar_private.supplier_fx_entries s where s.transaction_id=t.id),false)
$$;
revoke all on function solar_private.statement_payment_editable(public.transactions,public.customers,public.profiles) from public,anon,authenticated;

-- Keep the wholesale workflow's existing audit, stale-write checks and retry IDs.
-- Its mutation must enforce receipt visibility as well as its preview.
do $$
declare definition text:=pg_get_functiondef('solar_private.customer_payment_manage(text,uuid,jsonb)'::regprocedure);
 needle text:=' if uid is null or t.cash_currency';
begin
 if strpos(definition,needle)=0 then raise exception 'Review wholesale payment permissions before migrating'; end if;
 execute replace(definition,needle,' if not solar_private.invoice_read_allowed(t.id) then raise exception ''التسديد غير متاح ضمن صلاحياتك'' using errcode=''42501''; end if;'||chr(10)||needle);
end $$;

create function solar_private.statement_system_payment(action text,request_id uuid default null,payload jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
 actor public.profiles; receipt public.transactions; customer public.customers; cashier uuid;
 ledger jsonb; balance numeric; cash_before numeric; token text; amount numeric; new_total numeric;
 invoice_remaining numeric; cash_after numeric; corrected public.transactions; result jsonb;
 prior solar_private.finance_requests;
begin
 select * into actor from public.profiles where id=auth.uid() and active and user_type not in ('warehouse','installer');
 if actor.id is null or not (actor.is_admin or solar_private.any_feature(actor.permissions,'systemPayment')) then
  raise exception 'لا تملك صلاحية تسديد المنظومات' using errcode='42501';
 end if;
 if action is null or action not in ('get','update') or jsonb_typeof(payload) is distinct from 'object' then
  raise exception 'عملية تسديد غير صحيحة';
 end if;
 if action='update' then
  if request_id is null then raise exception 'رقم طلب التعديل مطلوب'; end if;
  perform pg_advisory_xact_lock(7311,1);
 end if;
 select * into receipt from public.transactions where id=(payload->>'id')::bigint and kind='system_payment';
 select c.* into customer from public.customers c join solar_private.customer_movement_links() l on l.customer_id=c.id
 where l.transaction_id=receipt.id;
 if not solar_private.statement_payment_editable(receipt,customer,actor) then
  raise exception 'هذا التسديد غير متاح للتعديل ضمن صلاحياتك' using errcode='42501';
 end if;
 if action='update' then
  select * into prior from solar_private.finance_requests r where r.request_id=statement_system_payment.request_id;
  if found then
   if prior.actor_id=actor.id and prior.action='system_payment_update' and prior.payload=payload then return prior.response; end if;
   raise exception 'رقم طلب التعديل مستخدم لعملية أخرى' using errcode='PT409';
  end if;
 end if;
 cashier:=coalesce(receipt.cashbox_user_id,receipt.created_by);
 cash_before:=solar_private.cash_balance(cashier);
 ledger:=solar_private.customer_ledger(customer.id);
 select coalesce(sum((x->>'effect')::numeric),0) into balance from jsonb_array_elements(ledger) x;
 token:=md5(to_jsonb(receipt)::text||ledger::text||cash_before::text);
 if action='get' then
  return jsonb_build_object('id',receipt.id,'receiptNo',receipt.receipt_no,'customerId',customer.id,'party',customer.name,
   'date',receipt.created_at,'total',receipt.total,'cash',receipt.cash,'mode',receipt.payment_mode,'notes',receipt.notes,
   'balance',balance,'cashBalance',cash_before,'token',token,'cashOwnerName',
   (select solar_private.user_name(p.display_name,p.username,p.honorific) from public.profiles p where p.id=cashier));
 end if;
 if payload->>'expectedToken' is distinct from token then
  raise exception 'تغيّر التسديد أو الرصيد. حدّث المعاينة قبل الحفظ.' using errcode='PT409';
 end if;
 amount:=(payload->>'amount')::numeric;
 if amount is null or not(amount>0 and amount<=1e12 and round(amount,2)=amount)
  or length(coalesce(payload->>'notes',''))>2000 or (not receipt.cash and trim(coalesce(payload->>'notes',''))='') then
  raise exception 'راجع مبلغ التسديد وبيان الإضافة على الحساب';
 end if;
 new_total:=case when receipt.cash then amount else -amount end;
 if receipt.cash and new_total>receipt.total and balance+receipt.total-new_total<0 then
  raise exception 'المبلغ أكبر من رصيد العميل المتاح للتسديد';
 end if;
 if receipt.system_invoice_id is not null and new_total>receipt.total then
  select (case when s.cash then 0 else s.total end)-coalesce((select sum(pay.total) from public.transactions pay
   where pay.system_invoice_id=s.id and pay.kind='system_payment'),0) into invoice_remaining
   from public.transactions s where s.id=receipt.system_invoice_id and s.kind='system';
  if invoice_remaining is null or invoice_remaining+receipt.total-new_total<0 then
   raise exception 'التعديل يتجاوز المتبقي على المنظومة المرتبطة بالتسديد';
  end if;
 end if;
 cash_after:=cash_before+case when receipt.cash then new_total-receipt.total else 0 end;
 if receipt.cash and cash_after<cash_before and cash_after<0 then raise exception 'رصيد القاصة لا يكفي لعكس فرق التسديد'; end if;
 update public.transactions set total=new_total,notes=coalesce(payload->>'notes','') where id=receipt.id returning * into corrected;
 insert into solar_private.receipt_change_audit(request_id,actor_id,transaction_id,action,before_row,after_row)
 values(request_id,actor.id,receipt.id,'system_payment_update',to_jsonb(receipt),to_jsonb(corrected));
 result:=jsonb_build_object('id',receipt.id,'receiptNo',receipt.receipt_no,'remaining',balance+receipt.total-new_total,'cashAfter',cash_after,'action','update');
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response)
 values(request_id,actor.id,'system_payment_update',payload,result);
 return result;
end $$;
create function public.solar_statement_system_payment(action text,request_id uuid default null,payload jsonb default '{}')
returns jsonb language sql security invoker set search_path='' as $$
 select solar_private.statement_system_payment(action,request_id,payload)
$$;
revoke all on function solar_private.statement_system_payment(text,uuid,jsonb),public.solar_statement_system_payment(text,uuid,jsonb) from public,anon;
grant execute on function solar_private.statement_system_payment(text,uuid,jsonb),public.solar_statement_system_payment(text,uuid,jsonb) to authenticated;

-- A retry of the original creation must not print the amount it had before a correction.
do $$
declare definition text:=pg_get_functiondef('solar_private.system_payment_save_v411(uuid,jsonb)'::regprocedure);
 needle text:='   return prior.response;';
begin
 if strpos(definition,needle)=0 then raise exception 'Review system payment creation replay before migrating'; end if;
 execute replace(definition,needle,'   if exists(select 1 from solar_private.receipt_change_audit a where a.transaction_id=(prior.response->>''id'')::bigint) then raise exception ''تم تعديل التسديد؛ افتح الوصل من كشف الحساب'' using errcode=''PT409''; end if;'||chr(10)||needle);
end $$;
-- A cashier can differ from the person who entered a payment. Apply receipt
-- ownership to approval previews and archived requests as well as statement rows.
create function solar_private.statement_payment_delete_projection(context jsonb) returns jsonb
language sql stable set search_path='' as $$
 select case when context->>'kind'='system_payment'
   and context#>>'{invoice,system_invoice_id}' is not null
   and not solar_private.invoice_read_allowed((context#>>'{invoice,system_invoice_id}')::bigint)
  then context #- '{invoice,system_invoice_id}' else context end
$$;
revoke all on function solar_private.statement_payment_delete_projection(jsonb) from public,anon,authenticated;
do $$
declare definition text; needle text;
begin
 definition:=pg_get_functiondef('solar_private.receipt_delete_context(bigint)'::regprocedure);
 needle:='and solar_private.delete_kind_feature(solar_private.office_features(),t.kind)';
 if strpos(definition,needle)=0 then raise exception 'Review deletion receipt access';end if;
 execute replace(definition,needle,needle||'
   and (t.kind not in (''customer_payment'',''system_payment'') or t.created_by=auth.uid())');

 definition:=pg_get_functiondef('solar_private.receipt_delete_requests_v3102(text,uuid,jsonb)'::regprocedure);
 needle:='q.owner_id=p.id and solar_private.delete_kind_feature(p.permissions,q.kind)';
 if strpos(definition,needle)=0 then raise exception 'Review deletion archive list access';end if;
 definition:=replace(definition,needle,needle||' and (q.kind not in (''customer_payment'',''system_payment'') or q.snapshot#>>''{invoice,created_by}''=p.id::text)');
 needle:='r.owner_id<>p.id or not solar_private.delete_kind_feature(p.permissions,r.kind)';
 if strpos(definition,needle)=0 then raise exception 'Review deletion request access';end if;
 definition:=replace(definition,needle,needle||' or (r.kind in (''customer_payment'',''system_payment'') and r.snapshot#>>''{invoice,created_by}'' is distinct from p.id::text)');
 execute definition;

 -- Project the response after validation so the admin retains the original
 -- allocation in the audit snapshot, regardless of who submitted the request.
 definition:=pg_get_functiondef('solar_private.receipt_delete_requests(text,uuid,jsonb)'::regprocedure);
 needle:='if action not in(''delete_direct'',''approve'') then
  return solar_private.receipt_delete_requests_v3102(action,request_id,payload);';
 if strpos(definition,needle)=0 then raise exception 'Review protected deletion read responses';end if;
 execute replace(definition,needle,'if action not in(''delete_direct'',''approve'') then
  result:=solar_private.receipt_delete_requests_v3102(action,request_id,payload);
  if action=''context'' then return solar_private.statement_payment_delete_projection(result);end if;
  if action=''get'' then
   result:=jsonb_set(result,''{snapshot}'',solar_private.statement_payment_delete_projection(result->''snapshot''));
   result:=jsonb_set(result,''{current}'',solar_private.statement_payment_delete_projection(result->''current''));
  end if;
  return result;');
end $$;

notify pgrst,'reload schema';
