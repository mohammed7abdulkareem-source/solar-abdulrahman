-- Wholesale manual expenses: customer reimbursement or company profit deduction.
-- NULL retains the legacy customer-paid behavior; no historical rows are repriced.
-- Purchase landed costs and system installation expenses are unchanged.
do $guard$
begin
 if md5(pg_get_functiondef('solar_private.pricing_guard()'::regprocedure))<>'f95bb3184a426b10624080da9f8eb67c' then raise exception 'Unexpected pricing_guard definition before expense allocation migration';end if;
 if md5(pg_get_functiondef('solar_private.profit_detail(text,uuid)'::regprocedure))<>'9d04e0129aae6f6924c19d5e162f94ef' then raise exception 'Unexpected profit_detail definition before expense allocation migration';end if;
 if md5(pg_get_functiondef('solar_private.invoice_save_v333(uuid,jsonb)'::regprocedure))<>'a4aa2ea10db4baf0545240564c5d94f9' then raise exception 'Unexpected invoice_save_v333 definition before expense allocation migration';end if;
 if md5(pg_get_functiondef('solar_private.warehouse_pricing(text,bigint,text,jsonb,uuid)'::regprocedure))<>'4563dda5f283e546dbcb11fd7d4ba452' then raise exception 'Unexpected warehouse_pricing definition before expense allocation migration';end if;
 if md5(pg_get_functiondef('solar_private.warehouse_action_v364(bigint,text,text,jsonb,text)'::regprocedure))<>'c29b6ae36c61cb4cba9a25be05f92717' then raise exception 'Unexpected warehouse_action_v364 definition before expense allocation migration';end if;
 if md5(pg_get_functiondef('solar_private.assert_wholesale_pricing(bigint,bigint)'::regprocedure))<>'f53cd50da930762f7d168c0bf4f49bcb' then raise exception 'Unexpected assert_wholesale_pricing definition before expense allocation migration';end if;
 if md5(pg_get_functiondef('solar_private.customer_invoice_document(transactions)'::regprocedure))<>'8c382c7b951754d90a1b5976413c976b' then raise exception 'Unexpected customer_invoice_document definition before expense allocation migration';end if;
 if md5(pg_get_functiondef('solar_private.wholesale_economic_signature(bigint)'::regprocedure))<>'274f4ff985e4c1a7b4ec398aa99553f9' then raise exception 'Unexpected wholesale_economic_signature definition before expense allocation migration';end if;
end $guard$;

alter table public.transactions add column expenses_on_customer boolean;
comment on column public.transactions.expenses_on_customer is 'Wholesale expense allocation. NULL preserves historical customer reimbursement; false is a protected company-paid sale expense.';
alter table public.transactions add constraint transactions_sale_expense_allocation check (expenses_on_customer is null or (kind='sale' and (expenses_on_customer or fx_pricing)));

CREATE OR REPLACE FUNCTION solar_private.invoice_save_v333(request_id uuid, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_variable
declare p public.profiles; old_invoice public.transactions; invoice public.transactions;
 cached solar_private.invoice_requests; product public.products; old_item public.transaction_items;
 line jsonb; computed jsonb:='[]'::jsonb; snapshots jsonb:='[]'::jsonb; before_stock jsonb;
 kind text; currency text; mode text; invoice_id bigint; item_id bigint; party_id bigint; owner_id uuid;
 rate numeric; default_rate numeric; source_sum numeric:=0; subtotal numeric:=0; expenses numeric; total numeric; cost numeric:=0;
 qty numeric; price numeric; unit_cost numeric; landed numeric; remaining_qty numeric; remaining_cost numeric;
 previous_qty numeric; previous_value numeric; next_qty numeric; next_cost numeric; product_qty numeric; product_cost numeric;
 new_basis jsonb; result jsonb; system_items_changed boolean:=false;economic_change boolean:=true; existing boolean:=false; expense_customer boolean:=true; cash boolean; currency_before jsonb;currency_after jsonb;quote jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') then raise exception 'لا توجد صلاحية لحفظ الفاتورة' using errcode='42501';end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب حفظ غير صحيح';end if;
 kind:=payload->>'kind';currency:=coalesce(payload->>'sourceCurrency','IQD');mode:=coalesce(payload->>'mode','cash');
 if kind not in ('purchase','sale','system') or not(p.is_admin or coalesce(p.permissions->>kind,'false')='true') then raise exception 'لا توجد صلاحية لهذا النوع من الفواتير' using errcode='42501';end if;
 if currency not in ('IQD','USD') or (kind<>'purchase' and currency<>'IQD') or mode not in ('cash','credit') then raise exception 'البيع بالدينار فقط؛ تحقق من العملة وطريقة الدفع';end if;
 if jsonb_typeof(payload->'items') is distinct from 'array' or jsonb_array_length(payload->'items') not between 1 and 500 then raise exception 'أضف مواد صحيحة للفاتورة';end if;
 if length(coalesce(payload->>'notes',''))>4000 then raise exception 'الملاحظات طويلة جداً';end if;
 if payload ? 'expensesOnCustomer' and (jsonb_typeof(payload->'expensesOnCustomer') is distinct from 'boolean' or (kind<>'sale' and payload->>'expensesOnCustomer'='false')) then raise exception 'خيار المصاريف على حساب الزبون خاص ببيع الجملة ويجب أن يكون اختيارًا صحيحًا' using errcode='22023';end if;
 expenses:=coalesce((payload->>'expenses')::numeric,0); if kind='system' and nullif(payload->>'invoiceId','') is null and expenses<>0 then raise exception 'مصاريف التنصيب تعتمد كاملة بعد التجهيز عند إغلاق الملف';end if;
 if expenses::text in ('NaN','Infinity','-Infinity') or expenses<0 or expenses>1000000000000 then raise exception 'مصاريف غير صحيحة بالدينار';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into cached from solar_private.invoice_requests r where r.request_id=invoice_save_v333.request_id;
 if cached.request_id is not null then
  if cached.user_id<>p.id or cached.payload is distinct from payload then raise exception 'معرّف الطلب مستخدم لبيانات أخرى' using errcode='42501';end if;
  if not exists(select 1 from public.transactions t where t.id=(cached.result->>'id')::bigint) then raise exception 'الفاتورة حذفت أو صفّرت؛ حدّث البيانات' using errcode='PT409';end if;
  return cached.result;
 end if;
 if solar_private.operation_paused(kind) then raise exception '%' ,case when kind='purchase' then 'الشراء متوقف مؤقتًا بقرار الإدارة' else 'البيع متوقف مؤقتًا بقرار الإدارة' end using errcode='PT423';end if;
 invoice_id:=nullif(payload->>'invoiceId','')::bigint;
 if invoice_id is not null then
  select * into old_invoice from public.transactions where id=invoice_id for update;
  if old_invoice.id is null or not solar_private.can_access_invoice(old_invoice.created_by,false) or old_invoice.kind<>kind or (not p.is_admin and coalesce(old_invoice.cashbox_user_id,old_invoice.created_by) is distinct from p.id) then raise exception 'الفاتورة غير متاحة لحسابك' using errcode='42501';end if;
  if old_invoice.pricing_revision is distinct from (payload->>'expectedRevision')::bigint then raise exception 'تغيرت الفاتورة؛ افتح التعديل مجدداً' using errcode='PT409';end if;
  if kind='system' then
   if old_invoice.installation_revision is distinct from (payload->>'expectedInstallationRevision')::bigint then raise exception 'تغيّر ملف التنصيب؛ افتح تعديل الفاتورة مجدداً' using errcode='PT409';end if;
   if expenses is distinct from coalesce(old_invoice.expenses,0) then raise exception 'المصاريف تعدّل من ملف التنصيب بعد مراجعتها';end if;
   system_items_changed:=(select coalesce(jsonb_agg(jsonb_build_array(i.product_id,i.qty) order by i.product_id),'[]') from public.transaction_items i where i.transaction_id=old_invoice.id)
    is distinct from(select jsonb_agg(jsonb_build_array((value->>'id')::bigint,(value->>'qty')::numeric) order by(value->>'id')::bigint) from jsonb_array_elements(payload->'items'));
  end if;
  if kind<>'sale' and old_invoice.cash is distinct from (mode='cash') then raise exception 'لا يمكن تغيير طريقة دفع الفاتورة المحفوظة';end if;
  existing:=true;owner_id:=coalesce(old_invoice.cashbox_user_id,old_invoice.created_by);
 else
  -- Integer ID allocation is serialized with the existing cash/stock lock.
  invoice_id:=solar_private.next_transaction_id();
  owner_id:=p.id;
 end if;
 if kind='sale' then expense_customer:=coalesce((payload->>'expensesOnCustomer')::boolean,old_invoice.expenses_on_customer,true);end if;
 if currency='USD' then
  rate:=(payload->>'exchangeRate')::numeric;
  if rate is null or rate::text in ('NaN','Infinity','-Infinity') or rate<=0 or rate>1000000 then raise exception 'سعر صرف غير صحيح';end if;
  select s.rate into default_rate from solar_private.exchange_settings s where s.id;
  if not(p.is_admin or coalesce(p.permissions->>'exchangeRateEdit','false')='true') and rate is distinct from default_rate
   and not(existing and old_invoice.source_currency='USD' and old_invoice.exchange_rate=rate) then raise exception 'تغيير صرف الفاتورة يحتاج صلاحية تعديل سعر الصرف' using errcode='42501';end if;
 else rate:=1;end if;
 if exists(select 1 from jsonb_array_elements(payload->'items') x group by x->>'id' having count(*)>1) then raise exception 'المادة مكررة في الفاتورة';end if;
 for line in select value from jsonb_array_elements(payload->'items') loop
  if jsonb_typeof(line) is distinct from 'object' or jsonb_typeof(line->'id') is distinct from 'number' or jsonb_typeof(line->'qty') is distinct from 'number' or jsonb_typeof(line->'price') is distinct from 'number' then raise exception 'مواد الفاتورة غير صحيحة';end if;
  qty:=(line->>'qty')::numeric;price:=(line->>'price')::numeric;
  if qty::text in ('NaN','Infinity','-Infinity') or price::text in ('NaN','Infinity','-Infinity') or qty<=0 or qty>100000000 or price<0 or price>1000000000000 then raise exception 'كمية أو سعر غير صحيح';end if;
  source_sum:=source_sum+qty*price;
 end loop;
 if source_sum=0 and expenses>0 and kind='purchase' then raise exception 'لا يمكن توزيع مصاريف على مواد مجموع أسعارها صفر';end if;
 subtotal:=round(source_sum*rate,2);total:=subtotal+case when kind<>'sale' or expense_customer then expenses else 0 end;
 if kind='system' then
  total:=(payload->>'total')::numeric;subtotal:=total;
  if total is null or total::text in ('NaN','Infinity','-Infinity') or total<=0 or total>1000000000000 then raise exception 'سعر بيع منظومة غير صحيح';end if;
  if coalesce(trim(payload->>'customerAddress'),'')='' or not exists(select 1 from public.profiles x where x.id=(payload->>'installerId')::uuid and x.active and x.user_type='installer') then raise exception 'اختر مهندساً فعالاً واكتب عنوان التنصيب';end if;
  if (nullif(payload->>'installDate','') is null) is distinct from (nullif(payload->>'installTime','') is null) then raise exception 'حدد يوم وساعة الموعد معاً';end if;
 end if;
 party_id:=null;
 if coalesce(payload->>'party','')<>'' then
  if kind='purchase' then
   select id into party_id from public.suppliers where name=payload->>'party' and active order by id limit 1;
  else
   select c.id into party_id from public.customers c where c.name=payload->>'party' and (p.is_admin or c.owner_id=p.id) order by c.id limit 1;
  end if;
  if party_id is null then raise exception 'اختر طرفاً موجوداً ضمن صلاحياتك' using errcode='42501';end if;
 elsif mode='credit' or kind='system' then raise exception 'اختر العميل أو المورد';end if;
 cash:=mode='cash' and kind<>'system';
 -- IQD cash purchases can overdraw; receipts repay the signed balance.
 if existing and kind='sale' and (case when old_invoice.cash then old_invoice.total else 0 end)-(case when cash then total else 0 end)>greatest(0,solar_private.cash_balance(owner_id)) then raise exception 'الرصيد لا يكفي لتخفيض البيع النقدي' using errcode='P0002';end if;
 if existing and kind='purchase' then
  economic_change:=old_invoice.source_currency<>currency or old_invoice.exchange_rate<>rate or old_invoice.expenses<>expenses or
   (select coalesce(jsonb_agg(jsonb_build_object('id',i.product_id,'qty',i.qty,'price',coalesce(i.source_price,i.price)) order by i.product_id),'[]'::jsonb) from public.transaction_items i where i.transaction_id=invoice_id)
   is distinct from (select jsonb_agg(jsonb_build_object('id',(x->>'id')::bigint,'qty',(x->>'qty')::numeric,'price',(x->>'price')::numeric) order by (x->>'id')::bigint) from jsonb_array_elements(payload->'items') x);
 end if;
 -- Lock affected products in ID order. No cost supplied by the client is used.
 for product in select x.* from public.products x where x.id in (
  select (v->>'id')::bigint from jsonb_array_elements(payload->'items') v
  union select i.product_id from public.transaction_items i where existing and i.transaction_id=invoice_id
 ) order by x.id for update loop
  previous_qty:=0;previous_value:=0;
  if existing then select coalesce(sum(i.qty),0),coalesce(sum(i.qty*case when old_invoice.kind='purchase' then case when i.landed_cost>0 then i.landed_cost else i.price end else coalesce((i.cost_basis->>'bookUnitCost')::numeric,i.cost) end),0) into previous_qty,previous_value from public.transaction_items i where i.transaction_id=invoice_id and i.product_id=product.id;end if;
  product_qty:=product.qty;product_cost:=product.cost;new_basis:=null;before_stock:=null;
  if kind='purchase' then
   if existing and economic_change and previous_qty>0 then
    if old_invoice.fx_pricing then
     select v into before_stock from jsonb_array_elements(old_invoice.purchase_stock) v where (v->>'id')::bigint=product.id;
     if before_stock is null or product.costing_revision is distinct from (before_stock->>'afterRevision')::bigint then raise exception 'حدثت حركة على المادة بعد الشراء. لا يمكن تغيير كلفتها التاريخية؛ استخدم تسوية أو فاتورة تصحيح' using errcode='PT409';end if;
     product_qty:=(before_stock->>'qty')::numeric;product_cost:=(before_stock->>'cost')::numeric;
    else
     if exists(select 1 from public.transaction_items i join public.transactions t on t.id=i.transaction_id where i.product_id=product.id and t.id<>invoice_id and (t.created_at,t.id)>(old_invoice.created_at,old_invoice.id) and t.kind in ('purchase','sale','system')) then raise exception 'حدثت حركة لاحقة؛ لا يمكن إعادة احتساب كلفة شراء قديم' using errcode='PT409';end if;
     product_qty:=product.qty-previous_qty;
     if product_qty<0 then raise exception 'لا يمكن تعديل شراء استُهلكت كميته';end if;
     if product_qty>0 then product_cost:=(product.qty*product.cost-previous_value)/product_qty;end if;
     if product_cost<0 then raise exception 'تعذر استعادة الكلفة السابقة؛ استخدم تسوية محاسبية';end if;
    end if;
   end if;
  else product_qty:=product.qty+previous_qty;end if;
  currency_before:=solar_private.inventory_currency_parts(product.id,case when before_stock is not null then before_stock->'basis' else product.cost_basis end,product_cost);
  currency_after:=currency_before;
  select v into line from jsonb_array_elements(payload->'items') v where (v->>'id')::bigint=product.id;
  if existing and kind='sale' and previous_qty>0 and product.cost is distinct from previous_value/previous_qty and coalesce((line->>'qty')::numeric,0)<>previous_qty then raise exception 'تغيرت كلفة المخزون بعد البيع. عدّل السعر فقط أو سجّل فاتورة تصحيح للكميات' using errcode='PT409';end if;
  if line is null then
   if kind='purchase' then next_qty:=product_qty;next_cost:=product_cost;else next_qty:=product_qty;next_cost:=product.cost;end if;
  else
   qty:=(line->>'qty')::numeric;price:=(line->>'price')::numeric;
   if kind='purchase' then
    landed:=round(price*rate+case when source_sum>0 then expenses*price/source_sum else 0 end,6);
    unit_cost:=landed;
    new_basis:=jsonb_build_object('currency',currency,'rate',rate,'sourcePrice',price,'invoiceId',invoice_id);
    if not existing or economic_change then
     next_qty:=product_qty+qty;next_cost:=round((product_qty*product_cost+qty*landed)/next_qty,6);
     currency_after:=jsonb_build_object('usd',(product_qty*(currency_before->>'usd')::numeric+qty*case when currency='USD' then price else 0 end)/next_qty,'iqd',(product_qty*(currency_before->>'iqd')::numeric+qty*case when currency='USD' then greatest(0,landed-price*rate) else landed end)/next_qty);
     snapshots:=snapshots||jsonb_build_array(jsonb_build_object('id',product.id,'qty',product_qty,'cost',product_cost,'basis',case when before_stock is not null then before_stock->'basis' else product.cost_basis end,'afterRevision',product.costing_revision+case when (next_qty,next_cost) is distinct from (product.qty,product.cost) then 1 else 0 end));
    else next_qty:=product.qty;next_cost:=product.cost;end if;
   else
    if qty>product_qty then raise exception 'الكمية غير كافية للمادة: %',product.name;end if;
    select * into old_item from public.transaction_items i where existing and i.transaction_id=invoice_id and i.product_id=product.id order by i.id limit 1;
    quote:=solar_private.valuation_quote(product.id,product.cost_basis,product.cost);
    unit_cost:=case when old_item.id is not null then old_item.cost else (quote->>'valuationUnitCost')::numeric end;
    new_basis:=case when old_item.id is not null then old_item.cost_basis else quote end;
    landed:=0;next_qty:=product_qty-qty;next_cost:=product.cost;
   end if;
   cost:=cost+qty*unit_cost;
   computed:=computed||jsonb_build_array(jsonb_build_object('id',product.id,'name',product.name,'brand',(select b.name from public.brands b where b.id=product.brand_id),'category',product.category,'qty',qty,'price',case when kind='system' then 0 else round(price*rate,6) end,'sourcePrice',case when kind='purchase' then price else null end,'cost',unit_cost,'landedCost',landed,'costBasis',new_basis));
  end if;
  if kind<>'purchase' or not existing or economic_change then
   update public.products set qty=next_qty,cost=next_cost,cost_basis=case when kind='purchase' then case when line is null and before_stock is not null then before_stock->'basis' else jsonb_build_object('method','weighted-average','lastPurchase',new_basis,'unitCost',next_cost,'currencyComponents',currency_after) end else case when product.cost_basis='{}'::jsonb then jsonb_build_object('method','legacy-iqd','unitCost',next_cost) else product.cost_basis end||jsonb_build_object('currencyComponents',currency_before) end where id=product.id;
  end if;
 end loop;
 if jsonb_array_length(computed)<>jsonb_array_length(payload->'items') then raise exception 'إحدى المواد غير موجودة؛ حدّث البيانات';end if;
 cost:=round(cost,2);
 if existing then
  update public.transactions set party_name=nullif(payload->>'party',''),party_id=party_id,party_type=case when kind='purchase' then 'supplier' else 'customer' end,
   cash=cash,payment_mode=mode,subtotal=subtotal,total=total,expenses=expenses,expenses_on_customer=case when kind='sale' then expense_customer end,cost=cost,profit=case when kind='sale' then subtotal-cost-case when expense_customer then 0 else expenses end when kind='system' then total-cost-expenses-coalesce(old_invoice.installation_expenses,0) else 0 end,
   installer_id=case when kind='system' then(payload->>'installerId')::uuid else installer_id end,
   install_date=case when kind='system' then nullif(payload->>'installDate','')::date else install_date end,
   install_time=case when kind='system' then nullif(payload->>'installTime','')::time else install_time end,
   customer_address=case when kind='system' then payload->>'customerAddress' else customer_address end,
   customer_phone=case when kind='system' then payload->>'customerPhone' else customer_phone end,
   installation_status=case when kind='system' and system_items_changed and old_invoice.installation_status='closed' then 'completed' else installation_status end,
   installation_closed_at=case when kind='system' and system_items_changed then null else installation_closed_at end,
   installation_revision=case when kind='system' then old_invoice.installation_revision+1 else installation_revision end,
   notes=nullif(payload->>'notes',''),source_currency=currency,exchange_rate=rate,source_subtotal=source_sum,fx_pricing=true,
   purchase_stock=case when kind='purchase' and economic_change then snapshots else purchase_stock end where id=invoice_id returning * into invoice;
 else
  insert into public.transactions(id,kind,party_type,party_id,party_name,payment_mode,subtotal,expenses,expenses_on_customer,total,cost,profit,notes,cash,created_by,cashbox_user_id,
   source_currency,exchange_rate,source_subtotal,fx_pricing,purchase_stock,installer_id,install_date,install_time,customer_address,customer_phone,installation_status)
  values(invoice_id,kind,case when kind='purchase' then 'supplier' else 'customer' end,party_id,nullif(payload->>'party',''),mode,subtotal,expenses,case when kind='sale' then expense_customer end,total,cost,
   case when kind='sale' then subtotal-cost-case when expense_customer then 0 else expenses end when kind='system' then total-cost-expenses-coalesce(old_invoice.installation_expenses,0) else 0 end,nullif(payload->>'notes',''),cash,p.id,owner_id,
   currency,rate,source_sum,true,snapshots,case when kind='system' then (payload->>'installerId')::uuid end,
   nullif(payload->>'installDate','')::date,nullif(payload->>'installTime','')::time,nullif(payload->>'customerAddress',''),nullif(payload->>'customerPhone',''),case when kind='system' then 'pending' else 'none' end)
  returning * into invoice;
 end if;
 if not(existing and kind='purchase' and not economic_change) then if not(existing and kind='system' and not system_items_changed) then
  delete from public.transaction_items where transaction_id=invoice_id;
  for line in select value from jsonb_array_elements(computed) loop
   insert into public.transaction_items(transaction_id,product_id,product_name,brand_name,category,qty,price,cost,landed_cost,source_price,cost_basis)
   values(invoice_id,(line->>'id')::bigint,line->>'name',line->>'brand',line->>'category',(line->>'qty')::numeric,(line->>'price')::numeric,(line->>'cost')::numeric,(line->>'landedCost')::numeric,(line->>'sourcePrice')::numeric,line->'costBasis');
  end loop;
 end if;
 end if;
 select * into invoice from public.transactions where id=invoice_id;
 result:=jsonb_build_object('id',invoice.id,'receiptNo',invoice.receipt_no,'pricingRevision',invoice.pricing_revision,'total',invoice.total,'cost',invoice.cost,'profit',invoice.profit,'invoiceAccount',invoice.invoice_account,'warehouseQrToken',invoice.warehouse_qr_token,'warehouseId',invoice.warehouse_id,'warehouseName',invoice.warehouse_name);
 if kind='sale' then result:=result||jsonb_build_object('expensesOnCustomer',coalesce(invoice.expenses_on_customer,true));end if;
 if kind in ('sale','system') then if existing and payload ? 'warranty' and coalesce((payload->>'expectedWarrantyRevision')::bigint,-1)<>invoice.warranty_revision then raise exception 'تغيّر ضمان الفاتورة؛ افتح التعديل مجدداً' using errcode='PT409';end if;result:=result||solar_private.warranty_apply(invoice_id,payload->'warranty');end if; insert into solar_private.invoice_requests(request_id,user_id,payload,result) values(request_id,p.id,payload,result);
 return result;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.pricing_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare protected boolean;
begin
 if tg_table_name='products' then
  if tg_op='UPDATE' then
   if current_user in ('anon','authenticated') and
    ((new.cost_basis,new.costing_revision) is distinct from (old.cost_basis,old.costing_revision)
     or ((old.cost_basis<>'{}'::jsonb or new.cost_basis<>'{}'::jsonb) and (new.qty,new.cost) is distinct from (old.qty,old.cost))) then
    raise exception 'استخدم حفظ الفاتورة أو تسوية المخزون المحمية' using errcode='42501';
   end if;
   if (new.qty,new.cost) is distinct from (old.qty,old.cost) then new.costing_revision:=old.costing_revision+1;end if;
  elsif current_user in ('anon','authenticated') and (new.cost_basis<>'{}'::jsonb or new.costing_revision<>0) then raise exception 'الكلفة المحمية غير قابلة للتعديل المباشر' using errcode='42501';end if;
 elsif tg_table_name='transactions' then
  if current_user in ('anon','authenticated') then
   if (tg_op='INSERT' and new.expenses_on_customer is not null) or (tg_op='UPDATE' and new.expenses_on_customer is distinct from old.expenses_on_customer) then raise exception 'استخدم حفظ الفاتورة المحمي لتحديد جهة المصاريف' using errcode='42501';end if;
   if tg_op='INSERT' and (new.fx_pricing or new.source_currency<>'IQD' or new.exchange_rate<>1 or new.source_subtotal is not null or new.purchase_stock<>'[]'::jsonb or new.pricing_revision<>0) then raise exception 'استخدم حفظ الفاتورة المحمي' using errcode='42501';end if;
   if tg_op<>'INSERT' and old.fx_pricing then raise exception 'استخدم إجراء الفاتورة المحمي' using errcode='42501';end if;
   if tg_op='UPDATE' and (new.fx_pricing,new.source_currency,new.exchange_rate,new.source_subtotal,new.purchase_stock,new.pricing_revision) is distinct from (old.fx_pricing,old.source_currency,old.exchange_rate,old.source_subtotal,old.purchase_stock,old.pricing_revision) then raise exception 'استخدم حفظ الفاتورة المحمي' using errcode='42501';end if;
  end if;
  if tg_op='UPDATE' then new.pricing_revision:=old.pricing_revision+1;end if;
 else
  if current_user in ('anon','authenticated') then
   select coalesce(bool_or(t.fx_pricing),false) into protected from public.transactions t where t.id in (case when tg_op<>'INSERT' then old.transaction_id end,case when tg_op<>'DELETE' then new.transaction_id end);
   if protected or (tg_op<>'DELETE' and (new.source_price is not null or new.cost_basis<>'{}'::jsonb)) then raise exception 'استخدم حفظ مواد الفاتورة المحمي' using errcode='42501';end if;
  end if;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.warehouse_action_v364(invoice_id bigint, expected_token text, action text, lines jsonb DEFAULT NULL::jsonb, note text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j public.transactions; before_items jsonb; after_items jsonb; entry jsonb; oldline public.transaction_items; prod public.products;
 newqty numeric; oldqty numeric; newtotal numeric; newcost numeric; wanted jsonb; id_value bigint;snapshots jsonb;ids bigint[];quote jsonb;
begin
 if auth.uid() is null or not solar_private.warehouse_allowed() then raise exception 'Not permitted' using errcode='42501';end if;
 if action not in ('save','ready','reopen') then raise exception 'Invalid action';end if;
 perform pg_advisory_xact_lock(7311,1); select * into j from public.transactions where id=invoice_id and kind in ('sale','system') for update;
 if j.id is null or not solar_private.warehouse_access_allowed(auth.uid(),j.warehouse_id) or not solar_private.can_access_invoice(j.created_by,true) then raise exception 'الفاتورة غير متاحة' using errcode='42501';end if;
 if solar_private.warehouse_token(j.id) is distinct from expected_token then raise exception 'تغيّرت الفاتورة، حدّث الصفحة وحاول مجدداً' using errcode='PT409';end if;
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
  select array_agg(distinct id) into ids from(select product_id id from public.transaction_items where transaction_id=j.id union select (e->>'productId')::bigint from jsonb_array_elements(lines)e)s;
  snapshots:=solar_private.valuation_stock_snapshot(ids);
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
    quote:=solar_private.valuation_quote(prod.id,prod.cost_basis,prod.cost);
    insert into public.transaction_items(transaction_id,product_id,product_name,brand_name,category,qty,price,cost,cost_basis)
    values(j.id,prod.id,prod.name,(select name from public.brands where id=prod.brand_id),prod.category,(entry->>'qty')::numeric,0,(quote->>'valuationUnitCost')::numeric,quote);
   end if;
  end loop;
  select coalesce(jsonb_agg(to_jsonb(i)),'[]') into after_items from public.transaction_items i where transaction_id=j.id;
  perform solar_private.valuation_reconcile_sale(snapshots,before_items,after_items);
  select coalesce(sum(qty*price),0),coalesce(sum(qty*cost),0) into newtotal,newcost from public.transaction_items where transaction_id=j.id;
  update public.transactions set subtotal=case when kind='sale' then newtotal else subtotal end,total=case when kind='sale' then newtotal+case when coalesce(expenses_on_customer,true) then coalesce(expenses,0) else 0 end else total end,
  cost=newcost,profit=case when kind='sale' then newtotal-newcost-case when coalesce(expenses_on_customer,true) then 0 else coalesce(expenses,0) end-coalesce(installation_expenses,0) else total-newcost-coalesce(expenses,0)-coalesce(installation_expenses,0) end,
  warehouse_status='pending',warehouse_prepared_at=null,warehouse_prepared_by=null,warehouse_note=coalesce(note,''),warehouse_revision=warehouse_revision+1 where id=j.id;
  perform solar_private.warehouse_notice(j.created_by,j.id,'warehouse_edited');
 elsif action='ready' then
  if j.warehouse_status<>'pending' then raise exception 'الفاتورة مجهزة مسبقاً';end if;
  if not exists(select 1 from public.transaction_items where transaction_id=j.id) then raise exception 'الفاتورة بدون مواد';end if;
  update public.transactions set warehouse_status='ready',warehouse_prepared_at=now(),warehouse_prepared_by=auth.uid(),warehouse_note=coalesce(note,''),warehouse_revision=warehouse_revision+1 where id=j.id;
 else
  if j.installation_status in ('in_progress','completed','closed') then raise exception 'بدأ تنفيذ المنظومة؛ لا يمكن إعادة التجهيز الآن';end if;
  if j.warehouse_status<>'ready' then raise exception 'الفاتورة بانتظار التجهيز أصلاً';end if;
  update public.transactions set warehouse_status='pending',warehouse_prepared_at=null,warehouse_prepared_by=null,warehouse_revision=warehouse_revision+1 where id=j.id;
 end if;
 select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]'::jsonb) into after_items from public.transaction_items i where transaction_id=j.id;
 insert into solar_private.warehouse_audit(invoice_id,actor_id,action,before_items,after_items) values(j.id,auth.uid(),action,before_items,after_items);
end $function$;

CREATE OR REPLACE FUNCTION solar_private.assert_wholesale_pricing(invoice_id bigint, expected_revision bigint DEFAULT NULL::bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare invoice public.transactions;actor public.profiles;control solar_private.wholesale_pricing_control;accepted solar_private.wholesale_invoice_pricing;
 scope jsonb;signature jsonb;gross numeric;net numeric;factor numeric;line record;enforced boolean:=false;override_allowed boolean:=false;floors jsonb:='[]';
begin
 select * into invoice from public.transactions t where t.id=invoice_id and t.kind='sale';
 if invoice.id is null then return;end if;
 perform pg_advisory_xact_lock(7311,1);
 signature:=solar_private.wholesale_economic_signature(invoice_id);
 select * into accepted from solar_private.wholesale_invoice_pricing p where p.invoice_id=assert_wholesale_pricing.invoice_id for update;
 if accepted.invoice_id is not null and accepted.accepted_signature=signature then return;end if;
 if invoice.source_currency is distinct from'IQD'or invoice.exchange_rate is distinct from 1 then raise exception 'بيع الجملة محفوظ بالدينار العراقي؛ بيانات العملة أو الصرف غير صحيحة'using errcode='PT422';end if;
 select * into control from solar_private.wholesale_pricing_control where id;
 select * into actor from public.profiles where id=auth.uid()and active;
 scope:=solar_private.wholesale_scope_effective(invoice.created_by,auth.uid());override_allowed:=(scope->>'canOverride')::boolean;
 if expected_revision is not null and control.revision is distinct from expected_revision then raise exception 'تغيّرت أسعار بيع الجملة؛ حدّث الأسعار وأعد الحفظ'using errcode='PT409';end if;
 if (scope->>'effectiveEnforced')::boolean then
  if actor.id is null then raise exception 'تعذر تأكيد صلاحية التسعير؛ أعد تسجيل الدخول'using errcode='42501';end if;
  if exists(select 1 from public.transaction_items i where i.transaction_id=invoice_id and(i.product_id is null or not exists(select 1 from public.products p where p.id=i.product_id)))then raise exception 'اختر مواد مسجلة حتى يمكن التحقق من أسعار بيع الجملة'using errcode='PT422';end if;
  if exists(select 1 from public.transaction_items i where i.transaction_id=invoice_id and(i.qty<=0 or i.price<0 or i.qty::text in('NaN','Infinity','-Infinity')or i.price::text in('NaN','Infinity','-Infinity')))then raise exception 'كمية أو سعر غير صحيح في مواد بيع الجملة'using errcode='PT422';end if;
  select round(coalesce(sum(i.qty*i.price),0),2)into gross from public.transaction_items i where i.transaction_id=invoice_id;
  net:=least(coalesce(invoice.subtotal,invoice.total-case when coalesce(invoice.expenses_on_customer,true) then coalesce(invoice.expenses,0) else 0 end),invoice.total-case when coalesce(invoice.expenses_on_customer,true) then coalesce(invoice.expenses,0) else 0 end);
  if net is null or net::text in('NaN','Infinity','-Infinity')or gross::text in('NaN','Infinity','-Infinity')then raise exception 'مبلغ بيع الجملة غير صحيح'using errcode='PT422';end if;
  factor:=case when gross>0 then least(1,net/gross)when net<0 then 0 else 1 end;
  for line in select i.product_id,i.product_name,i.price,i.qty,p.minimum_price,p.revision from public.transaction_items i join solar_private.wholesale_product_prices p on p.product_id=i.product_id and p.enabled where i.transaction_id=invoice_id loop
   enforced:=true;
   if line.price is null or line.price::text in('NaN','Infinity','-Infinity')or line.qty::text in('NaN','Infinity','-Infinity')or line.qty<=0 or line.price*factor<line.minimum_price then
    if actor.user_type in('warehouse','installer')then raise exception 'تحتاج مواد وصل الجملة إلى مراجعة التسعير من المسؤول'using errcode='PT422';end if;
    raise exception 'سعر مادة % بعد الخصم أقل من الحد الأدنى المسموح: % د.ع',line.product_name,line.minimum_price using errcode='PT422';
   end if;
  end loop;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('productId',p.product_id,'minPrice',p.minimum_price,'enabled',p.enabled,'revision',p.revision)order by p.product_id),'[]')into floors
 from solar_private.wholesale_product_prices p where p.product_id in(select i.product_id from public.transaction_items i where i.transaction_id=invoice_id);
 insert into solar_private.wholesale_invoice_pricing(invoice_id,accepted_signature,policy_revision,prices_snapshot,enforced,override_used,actor_id,accepted_at)
 values(invoice_id,signature,control.revision,floors,enforced,control.enabled and override_allowed,actor.id,now())
 on conflict on constraint wholesale_invoice_pricing_pkey do update set accepted_signature=excluded.accepted_signature,policy_revision=excluded.policy_revision,prices_snapshot=excluded.prices_snapshot,enforced=excluded.enforced,override_used=excluded.override_used,actor_id=excluded.actor_id,accepted_at=excluded.accepted_at;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.wholesale_economic_signature(invoice_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select jsonb_build_object('kind',t.kind,'currency',t.source_currency,'exchangeRate',t.exchange_rate,
  'net',least(coalesce(t.subtotal,t.total-case when coalesce(t.expenses_on_customer,true) then coalesce(t.expenses,0) else 0 end),t.total-case when coalesce(t.expenses_on_customer,true) then coalesce(t.expenses,0) else 0 end),
  'items',coalesce((select jsonb_agg(jsonb_build_object('productId',i.product_id,'qty',i.qty,'price',i.price)order by i.product_id,i.qty,i.price)
   from public.transaction_items i where i.transaction_id=t.id),'[]'::jsonb))
 from public.transactions t where t.id=invoice_id and t.kind='sale'
$function$;

CREATE OR REPLACE FUNCTION solar_private.customer_invoice_document(t transactions)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select jsonb_build_object('id',t.id,'kind',t.kind,'receipt_no',t.receipt_no,'created_at',t.created_at,
  'party_name',t.party_name,'customer_phone',t.customer_phone,'customer_address',t.customer_address,
  'total',t.total,'expenses',t.expenses,'expenses_on_customer',t.expenses_on_customer,'cash',t.cash,'payment_mode',t.payment_mode,'notes',t.notes,
  'creatorName',(select solar_private.user_name(display_name,username,honorific) from public.profiles where id=t.created_by),
  'creatorPhone',(select phone from public.profiles where id=t.created_by),
  'installerName',(select solar_private.user_name(display_name,username,honorific) from public.profiles where id=t.installer_id),
  'install_date',t.install_date,'install_time',t.install_time,'warehouse_name',t.warehouse_name,'warehouse_status',t.warehouse_status,
  'warranty',t.warranty,'warranty_token',t.warranty_token,'warehouse_qr_token',t.warehouse_qr_token,'invoice_account',t.invoice_account,
  'items',coalesce((select jsonb_agg(jsonb_build_object('product_id',i.product_id,'product_name',i.product_name,'brand_name',solar_private.current_product_brand(i.product_id,i.brand_name),
   'category',i.category,'qty',i.qty)||case when t.kind='sale' then jsonb_build_object('price',i.price) else '{}'::jsonb end order by i.id)
   from public.transaction_items i where i.transaction_id=t.id),'[]'))
$function$;

CREATE OR REPLACE FUNCTION solar_private.profit_detail(source_key text, owner_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles;uid uuid;movement jsonb;t public.transactions;invoice jsonb;breakdown jsonb;lines jsonb;materials_cost numeric;sales numeric;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 if p.id is null or not(p.is_admin or p.permissions->>'profit'='true' or p.permissions->>'profitSettlement'='true') then raise exception 'لا تملك صلاحية الأرباح' using errcode='42501';end if;
 uid:=coalesce(owner_id,p.id);
 if not p.is_admin and uid<>p.id then raise exception 'يمكنك مشاهدة وصولات أرباحك فقط' using errcode='42501';end if;
 select value into movement from jsonb_array_elements(solar_private.profit_rows(uid)) where value->>'key'=source_key;
 if movement is null then raise exception 'الحركة غير متاحة ضمن هذا الحساب' using errcode='42501';end if;
 if source_key ~ '^tx:-?[0-9]+$' and not coalesce((movement->>'deleted')::boolean,false) then
  select * into t from public.transactions where id=substr(source_key,4)::bigint;
  if t.id is not null then
   if t.kind in('sale','system') and not solar_private.invoice_read_allowed(t.id) then
    return jsonb_build_object('movement',solar_private.profit_read_projection(movement),'invoice',null,'transferred',true,'breakdown',null,'receiptRestricted',true);
   end if;
   if t.kind in('sale','system') then
    select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'productId',i.product_id,'code',m.code,'name',i.product_name,
     'brand',solar_private.current_product_brand(i.product_id,i.brand_name),'category',i.category,'qty',i.qty,'unitCost',i.cost,'lineCost',i.qty*i.cost,
     'unitPrice',case when t.kind='sale' then i.price end,'lineSales',case when t.kind='sale' then i.qty*i.price end,
     'lineProfit',case when t.kind='sale' then i.qty*(i.price-i.cost) end) order by i.id),'[]'),coalesce(sum(i.qty*i.cost),0)
    into lines,materials_cost from public.transaction_items i left join public.products m on m.id=i.product_id where i.transaction_id=t.id;
    sales:=case when t.kind='sale' then coalesce(t.subtotal,t.total) else t.total end;
    breakdown:=jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'kind',t.kind,'party',t.party_name,'date',t.created_at,'warehouseName',t.warehouse_name,
     'creatorName',(select solar_private.user_name(display_name,username,honorific) from public.profiles where id=t.created_by),
     'total',t.total,'sales',sales,'materialsCost',materials_cost,'invoiceExpenses',coalesce(t.expenses,0),
     'invoiceExpensesOnCustomer',t.kind='sale' and coalesce(t.expenses_on_customer,true),
     'customerInvoiceExpenses',case when t.kind='sale' and coalesce(t.expenses_on_customer,true) then coalesce(t.expenses,0) else 0 end,
     'companyInvoiceExpenses',case when t.kind='sale' and coalesce(t.expenses_on_customer,true) then 0 else coalesce(t.expenses,0) end,'installationExpenses',coalesce(t.installation_expenses,0),
     'grossProfit',sales-materials_cost,'netProfit',(movement->>'value')::numeric,'profitAdjustment',(movement->>'value')::numeric-(sales-materials_cost),'items',lines);
   end if;
   if not p.is_admin and coalesce(t.created_by,t.cashbox_user_id)<>p.id then return jsonb_build_object('movement',movement,'invoice',null,'transferred',true,'breakdown',breakdown);end if;
   invoice:=solar_private.receipt_contact_json(to_jsonb(t)||jsonb_build_object('items',coalesce((select jsonb_agg((to_jsonb(i)||jsonb_build_object('brand_name',solar_private.current_product_brand(i.product_id,i.brand_name))) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]'),
    'installerName',(select solar_private.user_name(display_name,username,honorific) from public.profiles where id=t.installer_id)),'transaction');
  end if;
 end if;
 return jsonb_build_object('movement',solar_private.profit_read_projection(movement),'invoice',invoice,'breakdown',breakdown);
end$function$;


CREATE OR REPLACE FUNCTION solar_private.warehouse_pricing(action text, invoice_id bigint DEFAULT NULL::bigint, expected_token text DEFAULT NULL::text, prices jsonb DEFAULT NULL::jsonb, request_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_variable
declare p public.profiles;t public.transactions;e solar_private.warehouse_price_edits;previous solar_private.warehouse_price_requests;
 payload jsonb:=jsonb_build_object('action',action,'invoiceId',invoice_id,'expectedToken',expected_token,'prices',prices);
 result jsonb;items jsonb;line jsonb;unit_price numeric;u uuid;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 if p.id is null or not(p.is_admin or coalesce(p.permissions->>'sale','false')='true') then raise exception 'تسعير المواد للإدارة فقط' using errcode='42501';end if;
 if action='list' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(jsonb_build_object('id',tx.id,'receiptNo',tx.receipt_no,'party',tx.party_name,'warehouseName',tx.warehouse_name,'count',jsonb_array_length(pe.lines),'date',pe.updated_at) order by pe.updated_at,tx.id)
   from solar_private.warehouse_price_edits pe join public.transactions tx on tx.id=pe.invoice_id where(p.is_admin or tx.created_by=p.id) and solar_private.warehouse_access_allowed(p.id,tx.warehouse_id)),'[]'));
 end if;
 if action not in('get','approve','cancel') then raise exception 'إجراء غير صحيح';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into t from public.transactions where id=invoice_id and kind='sale' for update;
 if t.id is null or not(p.is_admin or t.created_by=p.id) or not solar_private.warehouse_access_allowed(p.id,t.warehouse_id) then raise exception 'الفاتورة غير متاحة ضمن صلاحياتك' using errcode='42501';end if;
 if action in('approve','cancel') then
  if request_id is null then raise exception 'معرّف الطلب مطلوب';end if;
  select * into previous from solar_private.warehouse_price_requests r where r.request_id=warehouse_pricing.request_id;
  if previous.request_id is not null then
   if previous.actor_id<>p.id or previous.payload is distinct from payload then raise exception 'أعد تأكيد نفس الطلب السابق' using errcode='PT409';end if;
   return previous.result;
  end if;
 end if;
 select * into e from solar_private.warehouse_price_edits x where x.invoice_id=t.id for update;
 if e.invoice_id is null then raise exception 'لا توجد فقرات بانتظار التسعير';end if;
 if action='get' then
  select jsonb_agg(x.value||jsonb_build_object('price',i.price) order by x.ordinality) into items from jsonb_array_elements(e.lines) with ordinality x(value,ordinality)
   left join public.transaction_items i on i.id=(x.value->>'lineId')::bigint and i.transaction_id=t.id;
  return jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'party',t.party_name,'warehouseName',t.warehouse_name,'items',solar_private.current_item_brands(items),'token',solar_private.warehouse_token(t.id),'stale',e.base_token is distinct from solar_private.warehouse_token_v364(t.id),'total',t.total,'expenses',t.expenses,'expensesOnCustomer',coalesce(t.expenses_on_customer,true));
 end if;
 if solar_private.warehouse_token(t.id) is distinct from expected_token then raise exception 'تغيّر طلب المواد؛ افتحه مجددًا' using errcode='PT409';end if;
 if action='approve' then
  if e.base_token is distinct from solar_private.warehouse_token_v364(t.id) then raise exception 'تغيّرت الفاتورة بعد طلب المواد؛ ألغِ الطلب وافتح تعديلًا جديدًا' using errcode='PT409';end if;
  if t.installation_status in('in_progress','completed','closed') then raise exception 'الفاتورة مقفلة للتعديل';end if;
  if jsonb_typeof(prices) is distinct from 'array' or jsonb_array_length(prices)<>(select count(*) from jsonb_array_elements(e.lines) x where x->>'lineId' is null)
   or(select count(*) from jsonb_array_elements(prices))<>(select count(distinct x->>'productId') from jsonb_array_elements(prices) x) then raise exception 'حدّد سعر كل مادة جديدة مرة واحدة';end if;
  items:='[]';
  for line in select value from jsonb_array_elements(e.lines) loop
   if line->>'lineId' is null then
    select(x->>'price')::numeric into unit_price from jsonb_array_elements(prices) x where x->>'productId'=line->>'productId' and jsonb_typeof(x->'price')='number';
    if unit_price is null or unit_price<=0 or unit_price>1000000000000 then raise exception 'أدخل سعر بيع موجب لكل مادة جديدة';end if;
   else select i.price into unit_price from public.transaction_items i where i.id=(line->>'lineId')::bigint and i.transaction_id=t.id;end if;
   if unit_price is null then raise exception 'تغيّرت إحدى الفقرات؛ افتح الطلب مجددًا' using errcode='PT409';end if;
   items:=items||jsonb_build_array(jsonb_build_object('id',(line->>'productId')::bigint,'qty',(line->>'qty')::numeric,'price',unit_price));
  end loop;
  result:=solar_private.invoice_save(request_id,jsonb_build_object('kind','sale','invoiceId',t.id,'expectedRevision',t.pricing_revision,'warehouseId',t.warehouse_id,
   'partyId',t.party_id,'party',t.party_name,'mode',case when t.cash then 'cash' else 'credit' end,'notes',coalesce(t.notes,''),'expenses',coalesce(t.expenses,0),
   'sourceCurrency','IQD','exchangeRate',1,'items',items));
  delete from solar_private.warehouse_price_edits x where x.invoice_id=t.id;
  result:=jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'total',result->'total','pricingPending',false);
 else
  delete from solar_private.warehouse_price_edits x where x.invoice_id=t.id;
  update public.transactions set warehouse_revision=warehouse_revision+1 where id=t.id;
  result:=jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'cancelled',true);
 end if;
 insert into solar_private.warehouse_price_requests(request_id,actor_id,invoice_id,payload,result) values(request_id,p.id,t.id,payload,result);
 for u in select person.id from public.profiles person where person.active and(person.user_type='warehouse' or(person.permissions->>'warehouse'='true' and(person.is_admin or person.id=t.created_by))) and solar_private.warehouse_access_allowed(person.id,t.warehouse_id) loop
  perform solar_private.warehouse_notice(u,t.id,'warehouse_reopened');
 end loop;
 perform solar_private.warehouse_notice(t.created_by,t.id,'warehouse_edited');
 return result;
end$function$;

notify pgrst, 'reload schema';
