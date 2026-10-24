-- Read-only receipt browsing. Existing save/edit/delete paths retain their
-- original guards, immutable issue snapshots and idempotency keys.
create function solar_private.payment_history(action text default 'list',payload jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' set statement_timeout='8s' as $$
#variable_conflict use_variable
declare p public.profiles;allowed text[]:='{}';wanted text;start_date date;end_date date;q text;skip integer;
 result jsonb;t public.transactions;c public.customers;receipt jsonb;snapshot jsonb;issued boolean;ledger jsonb;before_balance numeric;after_balance numeric;invoice_after numeric;linked public.transactions;invoice jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('installer','warehouse');
 if p.id is null then raise exception 'لا تملك صلاحية سجل التسديدات' using errcode='42501';end if;
 if p.is_admin or coalesce(p.permissions->>'customerPayment','false')='true' or coalesce(p.permissions->>'customerStatement','false')='true' or coalesce(p.permissions->>'customers','false')='true' or coalesce(p.permissions->>'customerCreate','false')='true' then allowed:=array_append(allowed,'customer_payment');end if;
 if p.is_admin or coalesce(p.permissions->>'systemPayment','false')='true' or coalesce(p.permissions->>'customerStatement','false')='true' or coalesce(p.permissions->>'customers','false')='true' or coalesce(p.permissions->>'customerCreate','false')='true' then allowed:=array_append(allowed,'system_payment');end if;
 if p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true' or coalesce(p.permissions->>'supplierStatement','false')='true' then allowed:=array_append(allowed,'supplier_payment');end if;
 if cardinality(allowed)=0 then raise exception 'لا تملك صلاحية سجل التسديدات' using errcode='42501';end if;
 if action is null or action not in('list','get') or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب غير صحيح' using errcode='22023';end if;
 if action='list' then
  wanted:=coalesce(payload->>'kind','');start_date:=nullif(payload->>'from','')::date;end_date:=nullif(payload->>'to','')::date;
  q:=solar_private.customer_name_key(coalesce(payload->>'query',''));skip:=coalesce((payload->>'offset')::integer,0);
  if length(q)>200 or skip<0 or skip>1000000 or(start_date is not null and end_date is not null and start_date>end_date) then raise exception 'اختر فترة وبحثًا صحيحين' using errcode='22023';end if;
  if q~'^[#0-9,٬[:space:]]+$' then q:=regexp_replace(q,'[#،,٬[:space:]]','','g');end if;
  if wanted<>'' and not(wanted=any(allowed)) then raise exception 'هذا النوع خارج صلاحياتك' using errcode='42501';end if;
  with matched as materialized(
   select tx.* from public.transactions tx where tx.kind=any(allowed) and tx.cash and tx.total>0
    and tx.supplier_payment_voided_at is null and(p.is_admin or tx.created_by=p.id)
    and(p.is_admin or tx.kind='supplier_payment' or exists(select 1 from solar_private.customer_movement_links() l join public.customers cu on cu.id=l.customer_id where l.transaction_id=tx.id and cu.owner_id=p.id))
    and(wanted='' or tx.kind=wanted)
    and(start_date is null or tx.created_at>=(start_date::timestamp at time zone 'Asia/Baghdad'))
    and(end_date is null or tx.created_at<((end_date+1)::timestamp at time zone 'Asia/Baghdad'))
    and(q='' or strpos(solar_private.customer_name_key(coalesce(tx.party_name,'')||' '||coalesce(tx.notes,'')||' '||coalesce(tx.receipt_no::text,tx.id::text)),q)>0)
  ),page as(select * from matched order by created_at desc,id desc limit 30 offset skip)
  select jsonb_build_object('count',(select count(*) from matched),'rows',coalesce((select jsonb_agg(jsonb_build_object(
   'id',r.id,'kind',r.kind,'receiptNo',r.receipt_no,'date',r.created_at,'party',r.party_name,'partyId',r.party_id,'notes',r.notes,
   'amount',case when r.kind='supplier_payment' then coalesce(r.source_subtotal,r.total) else r.total end,'currency',case when r.kind='supplier_payment' then r.source_currency else 'IQD' end,
   'creatorName',(select coalesce(display_name,username) from public.profiles where id=r.created_by),
   'creatorPhone',(select phone from public.profiles where id=r.created_by)) order by r.created_at desc,r.id desc) from page r),'[]')) into result;
  return result;
 end if;
 select * into t from public.transactions where id=(payload->>'id')::bigint and kind=any(allowed) and cash and total>0 and supplier_payment_voided_at is null and(p.is_admin or created_by=p.id);
 if t.id is null then raise exception 'التسديد غير متاح ضمن صلاحياتك' using errcode='42501';end if;
 if t.kind='supplier_payment' then receipt:=solar_private.supplier_payment_get(t.id);
 else
  select cu.* into c from public.customers cu join solar_private.customer_movement_links() l on l.customer_id=cu.id where l.transaction_id=t.id;
  if c.id is null or not(p.is_admin or c.owner_id=p.id) then raise exception 'العميل غير متاح ضمن صلاحياتك' using errcode='42501';end if;
  select s.response into snapshot from(
   select a.response,a.created_at from solar_private.system_payment_requests a where a.response->>'id'=t.id::text
   union all select a.response,a.created_at from solar_private.finance_requests a where a.action='customer_payment' and a.response->>'id'=t.id::text
  )s order by s.created_at desc limit 1;
  issued:=coalesce((snapshot->>'total')::numeric=t.total and(snapshot->>'date')::timestamptz=t.created_at,false);
  if issued then before_balance:=(snapshot->>'oldBalance')::numeric;after_balance:=(snapshot->>'remaining')::numeric;
  else
   ledger:=solar_private.customer_ledger(c.id);
   select coalesce(sum((x->>'effect')::numeric),0) into after_balance from jsonb_array_elements(ledger)x where((x->>'date')::timestamptz,(x->>'id')::bigint)<=(t.created_at,t.id);
   before_balance:=after_balance+t.total;
  end if;
  if t.system_invoice_id is not null then
   select * into linked from public.transactions where id=t.system_invoice_id and kind='system' and(p.is_admin or created_by=p.id);
   if linked.id is not null then
    invoice:=jsonb_build_object('id',linked.id,'receiptNo',linked.receipt_no,'items',coalesce((select jsonb_agg(jsonb_build_object('name',product_name,'brand',brand_name,'category',category,'qty',qty) order by id) from public.transaction_items where transaction_id=linked.id),'[]'));
    select(case when linked.cash then 0 else linked.total end)-coalesce(sum(x.total),0) into invoice_after from public.transactions x where x.system_invoice_id=linked.id and(x.created_at,x.id)<=(t.created_at,t.id);
   end if;
  end if;
  receipt:=coalesce(snapshot,'{}')||jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'kind',t.kind,'ledgerType',case when t.kind='customer_payment' then 'wholesale' else 'system' end,
   'party',c.name,'date',t.created_at,'total',t.total,'cash',true,'mode','payment','notes',t.notes,'oldBalance',before_balance,'remaining',after_balance,
   'balanceBasis',case when issued then 'issued' else 'retained-ledger' end,'invoice',invoice,
   'invoiceBefore',case when linked.id is not null then case when issued then coalesce((snapshot->>'invoiceBefore')::numeric,invoice_after+t.total) else invoice_after+t.total end end,
   'invoiceAfter',case when linked.id is not null then case when issued then coalesce((snapshot->>'invoiceAfter')::numeric,invoice_after) else invoice_after end end);
 end if;
 receipt:=receipt||jsonb_build_object('kind',t.kind,'creatorName',(select coalesce(display_name,username) from public.profiles where id=t.created_by),
  'creatorPhone',(select phone from public.profiles where id=t.created_by),'cashOwnerName',(select coalesce(display_name,username) from public.profiles where id=coalesce(t.cashbox_user_id,t.created_by)));
 return jsonb_build_object('type',case when t.kind='supplier_payment' then 'supplier' else 'customer' end,'receipt',receipt);
end$$;
create function public.solar_payment_history(action text default 'list',payload jsonb default '{}') returns jsonb
language sql stable security invoker set search_path='' as $$select solar_private.payment_history(action,payload)$$;
revoke all on function solar_private.payment_history(text,jsonb),public.solar_payment_history(text,jsonb) from public,anon;
grant execute on function solar_private.payment_history(text,jsonb),public.solar_payment_history(text,jsonb) to authenticated;
notify pgrst,'reload schema';
