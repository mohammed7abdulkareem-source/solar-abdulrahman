-- Abort rather than replace a concurrently changed accounting workflow.
do $$declare f record;begin
 for f in select * from(values
  ('solar_private.purchase_delete(bigint,bigint)','0032df10d9e6be8fdae84ed744362a03'),
  ('solar_private.inventory_currency_parts(bigint,jsonb,numeric,integer)','fbc7695e7f49329476c3a9a1c4e69e24'),
  ('solar_private.receipt_delete_context(bigint)','0dd5199fbe7976c41b85f83ad6d25155'),
  ('solar_private.fx(text,uuid,jsonb)','9d9f3e5f06100ca54e41ca42820fb7b8'),
  ('solar_private.cash_movements()','c046dbfee771b48c1420e9d788b64eb3')
 ) expected(signature,hash)loop
  if md5(pg_get_functiondef(f.signature::regprocedure))<>f.hash then
   raise exception 'Accounting function changed before migration: %',f.signature;
  end if;
 end loop;
end$$;

-- Cancel an approved purchase against CURRENT stock without rewriting later
-- sales, receipts, exchange gains or settled profit checkpoints.
-- No historical data is changed by installing this migration.
create function solar_private.purchase_delete_plan(invoice_id bigint) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor public.profiles;t public.transactions;p public.products;s public.suppliers;
 e solar_private.supplier_fx_entries;w solar_private.wallet_fx_entries;stock solar_private.warehouse_stocks;
 snap jsonb;line record;parts jsonb;next_basis jsonb;rows jsonb:='[]';
 next_qty numeric;next_cost numeric;book_value numeric;usd_value numeric;iqd_value numeric;tolerance numeric;
begin
 select * into actor from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 select * into t from public.transactions where id=invoice_id and kind='purchase';
 if actor.id is null or t.id is null or(not actor.is_admin and t.created_by is distinct from actor.id) then
  raise exception 'الفاتورة غير متاحة ضمن صلاحياتك' using errcode='42501';end if;
 if not t.fx_pricing or jsonb_array_length(t.purchase_stock)=0
  or jsonb_array_length(t.purchase_stock)<>(select count(distinct i.product_id) from public.transaction_items i where i.transaction_id=t.id)
  or exists(select 1 from public.transaction_items i where i.transaction_id=t.id and i.product_id is null) then
  raise exception 'كلفة الشراء الأصلية غير مكتملة؛ راجع الوصل قبل إلغائه' using errcode='PT409';end if;
 select * into e from solar_private.supplier_fx_entries where transaction_id=t.id;
 if e.id is not null then
  select * into s from public.suppliers where id=e.supplier_id;
  if s.id is null or s.currency_revision is distinct from e.revision or s.account_currency is distinct from e.currency then
   raise exception 'تغيرت عملة حساب المورد بعد هذا الشراء؛ يلزم تصحيح الحساب بالعملة الحالية قبل إلغاء الوصل' using errcode='PT409';end if;
 elsif t.fx_accounted then
  raise exception 'قيد حساب المورد غير مكتمل؛ راجع الوصل قبل إلغائه' using errcode='PT409';
 end if;
 select * into w from solar_private.wallet_fx_entries where transaction_id=t.id;
 if t.cash and t.cash_currency='USD' then
  if w.id is null or w.currency is distinct from 'USD' or w.owner_id is distinct from coalesce(t.cashbox_user_id,t.created_by)
   or w.delta is distinct from -t.cash_amount or w.book_delta>0 then
   raise exception 'قيد دولار الشراء غير متوازن؛ راجع الوصل قبل إلغائه' using errcode='PT409';end if;
 elsif w.id is not null then raise exception 'للشراء قيد قاصة غير متوقع؛ راجعه قبل الإلغاء' using errcode='PT409';end if;
 for line in
  select i.product_id,sum(i.qty) qty,sum(i.qty*case when i.landed_cost>0 then i.landed_cost else i.price end) book,
   sum(i.qty*case when t.source_currency='USD' then coalesce(i.source_price,i.price/t.exchange_rate) else 0 end) usd,
   sum(i.qty*case when t.source_currency='USD' then greatest(0,(case when i.landed_cost>0 then i.landed_cost else i.price end)-coalesce(i.source_price,i.price/t.exchange_rate)*t.exchange_rate)
    else case when i.landed_cost>0 then i.landed_cost else i.price end end) iqd
  from public.transaction_items i where i.transaction_id=t.id group by i.product_id order by i.product_id
 loop
  select * into p from public.products where id=line.product_id;
  select * into stock from solar_private.warehouse_stocks where warehouse_id=t.warehouse_id and product_id=line.product_id;
  select value into snap from jsonb_array_elements(t.purchase_stock) where(value->>'id')::bigint=line.product_id;
  if p.id is null or snap is null or not(line.qty>0) then raise exception 'بيانات مادة الشراء غير مكتملة' using errcode='PT409';end if;
  if coalesce(stock.qty-stock.reserved_qty,0)<line.qty or p.qty<line.qty then
   raise exception 'لا يمكن إلغاء شراء مادة «%»: المطلوب % والمتاح غير المحجوز في «%» %. أعد الكمية إلى مخزن الوصل أو أكمل معالجة حجزها أولًا.',
    p.name,line.qty,t.warehouse_name,coalesce(stock.qty-stock.reserved_qty,0) using errcode='PT409';end if;
  next_qty:=p.qty-line.qty;
  if p.costing_revision=(snap->>'afterRevision')::bigint and next_qty=(snap->>'qty')::numeric then
   next_cost:=(snap->>'cost')::numeric;next_basis:=snap->'basis';
  else
   parts:=solar_private.inventory_currency_parts(p.id,p.cost_basis,p.cost);
   book_value:=p.qty*p.cost-line.book;
   usd_value:=p.qty*(parts->>'usd')::numeric-line.usd;
   iqd_value:=p.qty*(parts->>'iqd')::numeric-line.iqd;
   -- Unit book costs are stored rounded to six places. Only forgive their
   -- possible accumulated rounding error, never a real negative valuation.
   tolerance:=greatest(.00001,(p.qty+line.qty)*.0000005);
   if book_value < -tolerance or iqd_value < -tolerance or usd_value < -.00001
    or(next_qty=0 and(abs(book_value)>tolerance or abs(iqd_value)>tolerance or abs(usd_value)>.00001)) then
    raise exception 'إلغاء شراء مادة «%» يترك فرق كلفة مرتبطًا بالحركات اللاحقة؛ يلزم تصحيح الكلفة قبل الإلغاء.',p.name using errcode='PT409';end if;
   if next_qty>0 then
    next_cost:=round(greatest(0,book_value)/next_qty,6);
    next_basis:=jsonb_build_object('method','purchase-cancellation','unitCost',next_cost,'cancelledPurchaseId',t.id,
     'currencyComponents',jsonb_build_object('usd',greatest(0,usd_value)/next_qty,'iqd',greatest(0,iqd_value)/next_qty));
   else
    next_cost:=(snap->>'cost')::numeric;next_basis:=snap->'basis';
   end if;
  end if;
  rows:=rows||jsonb_build_array(jsonb_build_object('id',p.id,'name',p.name,'quantity',line.qty,
   'before',jsonb_build_object('qty',p.qty,'cost',p.cost,'basis',p.cost_basis,'revision',p.costing_revision),
   'after',jsonb_build_object('qty',next_qty,'cost',next_cost,'basis',next_basis),
   'warehouseBefore',to_jsonb(stock),'warehouseAfter',stock.qty-line.qty));
 end loop;
 return jsonb_build_object('warehouseId',t.warehouse_id,'warehouseName',t.warehouse_name,'items',rows,
  'cashRefund',case when t.cash then case when t.cash_currency='USD' then t.cash_amount else t.total end else 0 end,
  'cashCurrency',t.cash_currency,'accountCurrency',e.currency,'accountEffect',-coalesce(e.delta,0),
  'supplierEntry',to_jsonb(e),'walletEntry',to_jsonb(w));
end$$;
revoke all on function solar_private.purchase_delete_plan(bigint) from public,anon,authenticated;

create or replace function solar_private.purchase_delete(invoice_id bigint,expected_revision bigint) returns void
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare actor public.profiles;t public.transactions;plan jsonb;item jsonb;original_items jsonb;
 e solar_private.supplier_fx_entries;w solar_private.wallet_fx_entries;reversal_id bigint;wallet_reversal_id bigint;note text;
begin
 select * into actor from public.profiles where id=auth.uid() and active and is_admin and user_type not in('warehouse','installer');
 if actor.id is null then raise exception 'لا يمكن حذف الوصل قبل موافقة الإدارة' using errcode='42501';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into t from public.transactions where id=invoice_id and kind='purchase' for update;
 if t.id is null or not solar_private.can_access_invoice(t.created_by,false) then raise exception 'الفاتورة غير متاحة' using errcode='42501';end if;
 if t.pricing_revision is distinct from expected_revision then raise exception 'تغيرت الفاتورة؛ حدّث البيانات' using errcode='PT409';end if;
 perform 1 from public.products p where p.id in(select i.product_id from public.transaction_items i where i.transaction_id=t.id) order by p.id for update;
 perform 1 from solar_private.warehouse_stocks s where s.warehouse_id=t.warehouse_id and s.product_id in(select i.product_id from public.transaction_items i where i.transaction_id=t.id) order by s.product_id for update;
 select * into e from solar_private.supplier_fx_entries where transaction_id=t.id for update;
 if e.id is not null then perform 1 from public.suppliers where id=e.supplier_id for update;end if;
 select * into w from solar_private.wallet_fx_entries where transaction_id=t.id for update;
 plan:=solar_private.purchase_delete_plan(t.id);
 select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]') into original_items from public.transaction_items i where i.transaction_id=t.id;
 -- The archive retains the exact invoice, lines and linked ledger postings.
 -- Existing request tokens remain compatible: no new columns on ledger rows.
 insert into solar_private.deleted_sales(invoice_id,invoice,items,deleted_by)
 values(t.id,to_jsonb(t)||jsonb_build_object('purchaseCancellation',plan),original_items,actor.id);
 note:='إلغاء شراء #'||coalesce(t.receipt_no::text,t.id::text)||' · '||coalesce(t.party_name,'');
 if e.id is not null then
  update solar_private.supplier_fx_entries set transaction_id=null where id=e.id;
  insert into solar_private.supplier_fx_entries(supplier_id,owner_id,currency,revision,delta,book_delta,gain,rate,note,correction_for)
  values(e.supplier_id,e.owner_id,e.currency,e.revision,-e.delta,-e.book_delta,-e.gain,e.rate,note,t.id) returning id into reversal_id;
 end if;
 if w.id is not null then
  update solar_private.wallet_fx_entries set transaction_id=null where id=w.id;
  insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,gain,entry_type,note)
  values(w.owner_id,w.currency,-w.delta,-w.book_delta,w.rate,-w.gain,'purchase_refund',note) returning id into wallet_reversal_id;
 end if;
 for item in select value from jsonb_array_elements(plan->'items') loop
  update public.products set qty=(item->'after'->>'qty')::numeric,cost=(item->'after'->>'cost')::numeric,cost_basis=item->'after'->'basis' where id=(item->>'id')::bigint;
 end loop;
 update solar_private.deleted_sales d set invoice=d.invoice||jsonb_build_object('purchaseCancellation',plan||jsonb_build_object('supplierReversalId',reversal_id,'walletReversalId',wallet_reversal_id)) where d.invoice_id=t.id;
 delete from public.cash_ledger where transaction_id=t.id;
 -- The existing trigger removes only this receipt's warehouse quantity.
 -- IQD cash is refunded by removal of its purchase debit, exactly once.
 delete from public.transactions where id=t.id;
end$$;

-- Read-only preview, without adding current stock to the immutable receipt
-- token. Approval re-locks and rechecks the latest stock in the same transaction.
do $$declare definition text;begin
 definition:=pg_get_functiondef('solar_private.receipt_delete_context(bigint)'::regprocedure);
 if strpos(definition,'blocked text;profit_delta')=0 or strpos(definition,'select * into t from public.transactions where id=invoice_id;')=0 then
  raise exception 'Unexpected receipt context contract';end if;
 definition:=replace(definition,'blocked text;profit_delta','purchase_context jsonb;purchase_plan jsonb;blocked text;profit_delta');
 definition:=replace(definition,'select * into t from public.transactions where id=invoice_id;',
 'select * into t from public.transactions where id=invoice_id;
 if t.kind=''purchase'' and p.is_admin then
  purchase_context:=solar_private.receipt_delete_context_v387(invoice_id);
  begin purchase_plan:=solar_private.purchase_delete_plan(invoice_id);
  exception when sqlstate ''PT409'' then return purchase_context||jsonb_build_object(''blockedReason'',sqlerrm);end;
  return purchase_context||jsonb_build_object(''purchaseCancellation'',purchase_plan-''supplierEntry''-''walletEntry'');
 end if;');
 execute definition;
end$$;

CREATE OR REPLACE FUNCTION solar_private.inventory_currency_parts(material_id bigint, basis jsonb, book_cost numeric, depth integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare source jsonb;parts jsonb;archived_items jsonb;archived_invoice jsonb;t public.transactions;snapshot jsonb;units numeric;source_price numeric;landed numeric;before_qty numeric;denominator numeric;usd numeric;iqd numeric;expected_cost numeric;begin
 if depth>80 then raise exception 'تسلسل كلفة المادة غير صحيح';end if;
 if jsonb_typeof(basis->'currencyComponents')='object' then
  usd:=(basis->'currencyComponents'->>'usd')::numeric;iqd:=(basis->'currencyComponents'->>'iqd')::numeric;
  if usd is null or iqd is null or usd<0 or iqd<0 or usd::text in('NaN','Infinity') or iqd::text in('NaN','Infinity') then raise exception 'مكونات كلفة المادة غير صحيحة';end if;
  return jsonb_build_object('usd',usd,'iqd',iqd);
 end if;
 source:=basis->'lastPurchase';
 if source->>'invoiceId' is null then return jsonb_build_object('usd',0,'iqd',coalesce(book_cost,0));end if;
 select * into t from public.transactions where id=(source->>'invoiceId')::bigint and kind='purchase';
 if t.id is null then
  -- Historical sale/return bases may still refer to an approved, archived
  -- purchase. Reconstruct its original snapshot without changing old costs.
  select d.invoice,d.items
  into archived_invoice,archived_items from solar_private.deleted_sales d
  where d.invoice_id=(source->>'invoiceId')::bigint and d.invoice->>'kind'='purchase';
  t:=jsonb_populate_record(null::public.transactions,archived_invoice);
  if t.id is not null and jsonb_typeof(archived_items) is distinct from 'array' then raise exception 'مصدر كلفة المادة غير مكتمل';end if;
 end if;
 if t.id is null then raise exception 'تعذر ربط أصل كلفة المادة بفاتورة الشراء';end if;
 select v into snapshot from jsonb_array_elements(t.purchase_stock) v where(v->>'id')::bigint=material_id;
 if archived_items is null then
  select sum(i.qty),sum(i.qty*coalesce(i.source_price,i.price/t.exchange_rate))/nullif(sum(i.qty),0),sum(i.qty*case when i.landed_cost>0 then i.landed_cost else i.price end)/nullif(sum(i.qty),0)
  into units,source_price,landed from public.transaction_items i where i.transaction_id=t.id and i.product_id=material_id;
 else
  select sum(i.qty),sum(i.qty*coalesce(i.source_price,i.price/t.exchange_rate))/nullif(sum(i.qty),0),sum(i.qty*case when i.landed_cost>0 then i.landed_cost else i.price end)/nullif(sum(i.qty),0)
  into units,source_price,landed from jsonb_populate_recordset(null::public.transaction_items,archived_items) i
  where i.transaction_id=t.id and i.product_id=material_id;
 end if;
 if snapshot is null or units is null or units<=0 then raise exception 'مصدر كلفة المادة غير مكتمل';end if;
 before_qty:=(snapshot->>'qty')::numeric;denominator:=before_qty+units;
 expected_cost:=round((before_qty*(snapshot->>'cost')::numeric+units*landed)/denominator,6);
 if abs(expected_cost-book_cost)>.00001 then raise exception 'تحتاج كلفة المادة مراجعة حركات الإرجاع قبل اعتماد الصرف';end if;
 parts:=case when before_qty>0 then solar_private.inventory_currency_parts(material_id,snapshot->'basis',(snapshot->>'cost')::numeric,depth+1) else '{"usd":0,"iqd":0}'::jsonb end;
 usd:=(before_qty*(parts->>'usd')::numeric+units*case when t.source_currency='USD' then source_price else 0 end)/denominator;
 iqd:=(before_qty*(parts->>'iqd')::numeric+units*case when t.source_currency='USD' then greatest(0,landed-source_price*t.exchange_rate) else landed end)/denominator;
 return jsonb_build_object('usd',usd,'iqd',iqd);
end$function$;
revoke all on function solar_private.inventory_currency_parts(bigint,jsonb,numeric,integer) from public,anon,authenticated;

-- Read-only metadata for detached original purchase postings and their reversal.
-- Only fields needed for statement labels are returned; never the private plan.
create function solar_private.purchase_archive_entry(entry_source text,entry_id bigint) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor public.profiles;se solar_private.supplier_fx_entries;we solar_private.wallet_fx_entries;
 archived jsonb;cancelled_at timestamptz;entry_role text;
begin
 select * into actor from public.profiles where id=auth.uid() and active and user_type not in('installer','warehouse');
 if actor.id is null then return null;end if;
 if entry_source='supplier' then
  select * into se from solar_private.supplier_fx_entries where id=entry_id and transaction_id is null;
  if se.id is null or(not actor.is_admin and se.owner_id is distinct from actor.id)then return null;end if;
  if se.correction_for is not null then
   select d.invoice,d.deleted_at,'reversal' into archived,cancelled_at,entry_role
   from solar_private.deleted_sales d where d.invoice_id=se.correction_for and d.invoice->>'kind'='purchase'
    and d.invoice#>>'{purchaseCancellation,supplierReversalId}'=se.id::text;
  else
   select d.invoice,d.deleted_at,'original' into archived,cancelled_at,entry_role
   from solar_private.deleted_sales d where d.invoice->>'kind'='purchase' and d.invoice?'purchaseCancellation'
    and d.invoice#>>'{purchaseCancellation,supplierEntry,id}'=se.id::text;
  end if;
 elsif entry_source='wallet' then
  select * into we from solar_private.wallet_fx_entries where id=entry_id and transaction_id is null;
  if we.id is null or(not actor.is_admin and we.owner_id is distinct from actor.id)then return null;end if;
  select matched.invoice,matched.deleted_at,matched.entry_role into archived,cancelled_at,entry_role
  from(
   select d.invoice,d.deleted_at,'original'::text entry_role from solar_private.deleted_sales d
   where d.invoice->>'kind'='purchase' and d.invoice?'purchaseCancellation'
    and d.invoice#>>'{purchaseCancellation,walletEntry,id}'=we.id::text
   union all
   select d.invoice,d.deleted_at,'reversal'::text from solar_private.deleted_sales d
   where d.invoice->>'kind'='purchase' and d.invoice?'purchaseCancellation'
    and d.invoice#>>'{purchaseCancellation,walletReversalId}'=we.id::text
  )matched;
 else return null;end if;
 if archived is null then return null;end if;
 return jsonb_build_object('id',archived->'id','receiptNo',archived->'receipt_no','party',archived->'party_name',
  'notes',archived->'notes','originalKind','purchase','cancelledAt',cancelled_at,'entryRole',entry_role);
end$$;
revoke all on function solar_private.purchase_archive_entry(text,bigint) from public,anon,authenticated;

create index deleted_purchase_supplier_entry on solar_private.deleted_sales((invoice#>>'{purchaseCancellation,supplierEntry,id}'))
 where invoice->>'kind'='purchase' and invoice?'purchaseCancellation';
create index deleted_purchase_wallet_entry on solar_private.deleted_sales((invoice#>>'{purchaseCancellation,walletEntry,id}'))
 where invoice->>'kind'='purchase' and invoice?'purchaseCancellation';
create index deleted_purchase_wallet_reversal on solar_private.deleted_sales((invoice#>>'{purchaseCancellation,walletReversalId}'))
 where invoice->>'kind'='purchase' and invoice?'purchaseCancellation';

-- Preserve supplier ledger amounts and its existing owner filter. Archived
-- purchases remain adjustments; transaction stays null and items stay empty.
do $$declare definition text;needle text;replacement text;begin
 definition:=pg_get_functiondef('solar_private.fx(text,uuid,jsonb)'::regprocedure);
 needle:='select coalesce(jsonb_agg(to_jsonb(e)||jsonb_build_object(''transaction'',to_jsonb(x),''items'',';
 if strpos(definition,needle)=0 then raise exception 'Unexpected supplier statement projection';end if;
 replacement:='select coalesce(jsonb_agg(to_jsonb(e)||case when ap.summary is null then ''{}''::jsonb else jsonb_build_object(''archivedPurchase'',ap.summary,''note'',case when ap.summary->>''entryRole''=''original'' then ''شراء ملغى #'' else ''إلغاء شراء #'' end||coalesce(ap.summary->>''receiptNo'',ap.summary->>''id'')||'' · ''||coalesce(ap.summary->>''party'',''''))end||jsonb_build_object(''transaction'',to_jsonb(x),''items'',';
 definition:=replace(definition,needle,replacement);
 needle:='from solar_private.supplier_fx_entries e left join public.transactions x on x.id=e.transaction_id where e.supplier_id=sid and(p.is_admin or e.owner_id=p.id);';
 if strpos(definition,needle)=0 then raise exception 'Unexpected supplier statement owner scope';end if;
 replacement:='from solar_private.supplier_fx_entries e left join public.transactions x on x.id=e.transaction_id
    left join lateral(select case when e.transaction_id is null then solar_private.purchase_archive_entry(''supplier'',e.id)end summary offset 0)ap on true
    where e.supplier_id=sid and(p.is_admin or e.owner_id=p.id);';
 definition:=replace(definition,needle,replacement);
 execute definition;
end$$;

-- Keep cash delta/book_delta untouched and restore original receipt metadata.
-- A purchase cancellation refund is a separate dated movement, exactly once.
do $$declare definition text;needle text;replacement text;begin
 definition:=pg_get_functiondef('solar_private.cash_movements()'::regprocedure);
 needle:='union all select ''fx:''||e.id,e.owner_id,e.currency,e.delta,e.book_delta,e.entry_type,case when fr.action=''admin_cash_transfer'' then case when e.entry_type=''admin_transfer_out'' then ''إلى ''||coalesce(fr.response->>''recipientName'','''') else ''من ''||coalesce(fr.response->>''senderName'','''') end else '''' end,e.note,(fr.response->>''receiptNo'')::bigint,e.rate,e.currency,abs(e.delta),e.created_at,e.finance_request_id from solar_private.wallet_fx_entries e left join solar_private.finance_requests fr on fr.request_id=e.finance_request_id where e.transaction_id is null';
 if strpos(definition,needle)=0 then raise exception 'Unexpected cash movement archive projection';end if;
 replacement:='union all select ''fx:''||e.id,e.owner_id,e.currency,e.delta,e.book_delta,
  case when ap.summary->>''entryRole''=''original'' then ''purchase_cancelled'' else e.entry_type end,
  case when ap.summary is not null then coalesce(ap.summary->>''party'','''') when fr.action=''admin_cash_transfer'' then case when e.entry_type=''admin_transfer_out'' then ''إلى ''||coalesce(fr.response->>''recipientName'','''') else ''من ''||coalesce(fr.response->>''senderName'','''') end else '''' end,
  case when ap.summary->>''entryRole''=''original'' then ''شراء ملغى #''||coalesce(ap.summary->>''receiptNo'',ap.summary->>''id'')||case when coalesce(ap.summary->>''notes'','''')<>'''' then '' · ''||(ap.summary->>''notes'')else '''' end else e.note end,
  coalesce((ap.summary->>''receiptNo'')::bigint,(fr.response->>''receiptNo'')::bigint),e.rate,e.currency,abs(e.delta),e.created_at,e.finance_request_id
  from solar_private.wallet_fx_entries e left join solar_private.finance_requests fr on fr.request_id=e.finance_request_id
  left join lateral(select solar_private.purchase_archive_entry(''wallet'',e.id)summary offset 0)ap on true
  where e.transaction_id is null';
 definition:=replace(definition,needle,replacement);
 execute definition;
end$$;

notify pgrst,'reload schema';
