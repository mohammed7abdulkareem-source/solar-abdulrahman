create index customer_payment_document_lookup on solar_private.system_payment_requests((response->>'id'),created_at desc);
create index customer_wholesale_document_lookup on solar_private.finance_requests((response->>'id'),created_at desc) where action='customer_payment';
-- Original customer copies, read-only and independently authorized from edit/create rights.
create function solar_private.customer_invoice_document(t public.transactions) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',t.id,'kind',t.kind,'receipt_no',t.receipt_no,'created_at',t.created_at,
  'party_name',t.party_name,'customer_phone',t.customer_phone,'customer_address',t.customer_address,
  'total',t.total,'expenses',t.expenses,'cash',t.cash,'payment_mode',t.payment_mode,'notes',t.notes,
  'creatorName',(select coalesce(display_name,username) from public.profiles where id=t.created_by),
  'creatorPhone',(select phone from public.profiles where id=t.created_by),
  'installerName',(select coalesce(display_name,username) from public.profiles where id=t.installer_id),
  'install_date',t.install_date,'install_time',t.install_time,'warehouse_name',t.warehouse_name,'warehouse_status',t.warehouse_status,
  'warranty',t.warranty,'warranty_token',t.warranty_token,'warehouse_qr_token',t.warehouse_qr_token,'invoice_account',t.invoice_account,
  'items',coalesce((select jsonb_agg(jsonb_build_object('product_id',i.product_id,'product_name',i.product_name,'brand_name',i.brand_name,
   'category',i.category,'qty',i.qty)||case when t.kind='sale' then jsonb_build_object('price',i.price) else '{}'::jsonb end order by i.id)
   from public.transaction_items i where i.transaction_id=t.id),'[]'))
$$;
revoke all on function solar_private.customer_invoice_document(public.transactions) from public,anon,authenticated;

create function solar_private.customer_documents(customer_id bigint,movement_id bigint default null,date_from date default null,date_to date default null,category text default 'all',search_text text default '') returns jsonb
language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_variable
declare p public.profiles;c public.customers;r record;t public.transactions;linked public.transactions;snapshot jsonb;
 rows jsonb:='[]';movement jsonb;receipt jsonb;invoice jsonb;before_balance numeric;after_balance numeric;invoice_after numeric;
 q text:=lower(trim(coalesce(search_text,'')));issued boolean;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 select * into c from public.customers where id=customer_id;
 if p.id is null or c.id is null or not(p.is_admin or(coalesce(c.owner_id=p.id,false) and(coalesce(p.permissions->>'customers','false')='true' or coalesce(p.permissions->>'customerCreate','false')='true' or coalesce(p.permissions->>'customerStatement','false')='true'))) then
  raise exception 'لا تملك صلاحية وصولات هذا العميل' using errcode='42501';end if;
 if category is null or category not in('all','invoices','payments','other') or length(q)>200 or(date_from is not null and date_to is not null and date_from>date_to) then raise exception 'اختر فترة ونوع حركات صحيحين' using errcode='22023';end if;
 for r in
  with ledger as materialized(select (x->>'id')::bigint id,(x->>'effect')::numeric effect,x from jsonb_array_elements(solar_private.customer_ledger(c.id)) x),
  ranked as(select tx.*,l.effect,sum(l.effect) over(order by tx.created_at,tx.id rows unbounded preceding) balance,
   case when tx.payment_mode in('opening_balance','account_reconciliation') then 'other' when tx.kind in('sale','system') then 'invoices' when tx.total>0 then 'payments' else 'other' end tab,
   coalesce(case tx.payment_mode when 'opening_balance' then 'رصيد افتتاحي' when 'account_reconciliation' then 'مطابقة حساب' when 'charge_extra_expense' then 'مصروف إضافي' when 'charge_old_balance' then 'حساب قديم' when 'charge_other' then 'إضافة أخرى' end,
    case when tx.kind in('customer_payment','system_payment') then case when tx.total<0 then 'إضافة على الحساب' else 'تسديد' end when tx.kind='system' then 'بيع منظومة' when tx.cash then 'فاتورة بيع نقدية' else 'فاتورة بيع' end)||
    case when l.x->>'systemReceiptNo' is not null then ' · المنظومة #'||(l.x->>'systemReceiptNo') else '' end label
   from ledger l join public.transactions tx on tx.id=l.id),
  filtered as(select * from ranked where(p.is_admin or created_by=p.id) and(movement_id is null or id=movement_id)
   and(movement_id is not null or((date_from is null or created_at>=(date_from::timestamp at time zone 'Asia/Baghdad'))
    and(date_to is null or created_at<((date_to+1)::timestamp at time zone 'Asia/Baghdad')) and(category='all' or tab=category)
    and(q='' or strpos(lower(label||' '||coalesce(notes,'')||' '||coalesce(receipt_no::text,'')),q)>0))))
  select *,count(*) over() matched from filtered order by created_at,id limit 101
 loop
  if movement_id is null and r.matched>100 then raise exception 'الفترة تحتوي أكثر من 100 وصل؛ اختر فترة أقصر لتصدير الوصولات كاملة' using errcode='22023';end if;
  select * into t from public.transactions where id=r.id;
  movement:=jsonb_build_object('id',r.id,'kind',r.kind,'mode',r.payment_mode,'date',r.created_at,'receiptNo',r.receipt_no,'total',r.total,
   'cash',r.cash,'effect',r.effect,'amount',abs(r.total),'balance',r.balance,'before',r.balance-r.effect,'notes',r.notes,'label',r.label,
   'creatorName',(select coalesce(display_name,username) from public.profiles where id=t.created_by),'creatorPhone',(select phone from public.profiles where id=t.created_by));
  if t.kind in('sale','system') then
   rows:=rows||jsonb_build_array(jsonb_build_object('type','invoice','movement',movement,'invoice',solar_private.customer_invoice_document(t)));
  elsif coalesce(t.payment_mode,'') not in('opening_balance','account_reconciliation') then
   select s.response into snapshot from(
    select a.response,a.created_at from solar_private.system_payment_requests a where a.response->>'id'=t.id::text
    union all select a.response,a.created_at from solar_private.finance_requests a where a.action='customer_payment' and a.response->>'id'=t.id::text
   ) s order by s.created_at desc limit 1;
   issued:=coalesce((snapshot->>'total')::numeric=t.total and(snapshot->>'date')::timestamptz=t.created_at,false);
   before_balance:=case when issued then(snapshot->>'oldBalance')::numeric else r.balance-r.effect end;
   after_balance:=case when issued then(snapshot->>'remaining')::numeric else r.balance end;
   invoice:=null;linked:=null;
   if t.system_invoice_id is not null then
    select i.* into linked from public.transactions i join solar_private.customer_movement_links() l on l.transaction_id=i.id and l.customer_id=c.id
     where i.id=t.system_invoice_id and i.kind='system' and(p.is_admin or i.created_by=p.id);
    if linked.id is not null then
     invoice:=jsonb_build_object('id',linked.id,'receiptNo',linked.receipt_no,'items',coalesce((select jsonb_agg(jsonb_build_object('name',i.product_name,'brand',i.brand_name,'category',i.category,'qty',i.qty) order by i.id) from public.transaction_items i where i.transaction_id=linked.id),'[]'));
     select(case when linked.cash then 0 else linked.total end)-coalesce(sum(x.total),0) into invoice_after from public.transactions x where x.system_invoice_id=linked.id and(x.created_at,x.id)<=(t.created_at,t.id);
    end if;
   end if;
   receipt:=jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'kind',t.kind,'ledgerType',case when t.kind='customer_payment' then 'wholesale' else 'system' end,
    'party',c.name,'date',t.created_at,'total',t.total,'cash',t.cash,'mode',case when t.total>0 then 'payment' else coalesce(nullif(t.payment_mode,''),'charge_other') end,
    'notes',t.notes,'oldBalance',before_balance,'remaining',after_balance,'balanceBasis',case when issued then 'issued' else 'retained-ledger' end,
    'cashOwnerName',(select coalesce(display_name,username) from public.profiles where id=coalesce(t.cashbox_user_id,t.created_by)),
    'creatorName',movement->>'creatorName','creatorPhone',movement->>'creatorPhone','invoice',invoice,
    'invoiceBefore',case when linked.id is not null then case when issued then coalesce((snapshot->>'invoiceBefore')::numeric,invoice_after+t.total) else invoice_after+t.total end end,
    'invoiceAfter',case when linked.id is not null then case when issued then coalesce((snapshot->>'invoiceAfter')::numeric,invoice_after) else invoice_after end end);
   rows:=rows||jsonb_build_array(jsonb_build_object('type','payment','movement',movement,'receipt',receipt));
  else rows:=rows||jsonb_build_array(jsonb_build_object('type','adjustment','movement',movement));
  end if;
 end loop;
 if movement_id is not null and jsonb_array_length(rows)=0 then raise exception 'الوصل غير متاح ضمن صلاحياتك' using errcode='42501';end if;
 return jsonb_build_object('rows',rows,'count',jsonb_array_length(rows),'customerId',c.id,'customerName',c.name,'from',date_from,'to',date_to);
end$$;
create function public.solar_customer_movement(customer_id bigint,movement_id bigint) returns jsonb language sql stable security invoker set search_path='' as $$
 select case when movement_id is not null then solar_private.customer_documents(customer_id,movement_id)->'rows'->0 end
$$;
create function public.solar_customer_documents(customer_id bigint,date_from date default null,date_to date default null,category text default 'all',search_text text default '') returns jsonb
 language sql stable security invoker set search_path='' as $$select solar_private.customer_documents(customer_id,null,date_from,date_to,category,search_text)$$;
revoke all on function solar_private.customer_documents(bigint,bigint,date,date,text,text),public.solar_customer_movement(bigint,bigint),public.solar_customer_documents(bigint,date,date,text,text) from public,anon;
grant execute on function solar_private.customer_documents(bigint,bigint,date,date,text,text),public.solar_customer_movement(bigint,bigint),public.solar_customer_documents(bigint,date,date,text,text) to authenticated;
