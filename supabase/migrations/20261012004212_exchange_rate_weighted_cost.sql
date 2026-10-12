-- V3.31: all accounting values remain IQD; original USD amounts and the
-- purchase exchange rate are immutable historical inputs, not live formulas.
alter table public.products add column costing_revision bigint not null default 0,
 add column cost_basis jsonb not null default '{}'::jsonb;
alter table public.transactions add column source_currency text not null default 'IQD' check(source_currency in ('IQD','USD')),
 add column exchange_rate numeric not null default 1 check(exchange_rate>0 and exchange_rate<=1000000),
 add column source_subtotal numeric,
 add column fx_pricing boolean not null default false,
 add column pricing_revision bigint not null default 0,
 add column purchase_stock jsonb not null default '[]'::jsonb;
alter table public.transaction_items add column source_price numeric,
 add column cost_basis jsonb not null default '{}'::jsonb;

create table solar_private.exchange_settings(
 id boolean primary key default true check(id), rate numeric check(rate>0 and rate<=1000000),
 revision bigint not null default 0, updated_at timestamptz, updated_by uuid references public.profiles(id) on delete set null
);
insert into solar_private.exchange_settings(id) values(true);
create table solar_private.exchange_history(
 id bigint generated always as identity primary key, rate numeric not null,
 changed_at timestamptz not null default now(), changed_by uuid not null
);
create table solar_private.invoice_requests(
 request_id uuid primary key, user_id uuid not null,
 payload jsonb not null, result jsonb not null, created_at timestamptz not null default now()
);
alter table solar_private.exchange_settings enable row level security;
alter table solar_private.exchange_history enable row level security;
alter table solar_private.invoice_requests enable row level security;
revoke all on solar_private.exchange_settings,solar_private.exchange_history,solar_private.invoice_requests from public,anon,authenticated;

create function solar_private.exchange_get() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; s solar_private.exchange_settings;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('warehouse','installer') then raise exception 'لا توجد صلاحية للاطلاع على سعر الصرف' using errcode='42501';end if;
 select * into s from solar_private.exchange_settings where id;
 return jsonb_build_object('rate',s.rate,'revision',s.revision,'updatedAt',s.updated_at);
end $$;
create function solar_private.exchange_set(rate numeric,expected_revision bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.profiles; s solar_private.exchange_settings;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('warehouse','installer') or not(p.is_admin or coalesce(p.permissions->>'exchangeRateEdit','false')='true') then raise exception 'تعديل سعر الصرف غير مسموح لحسابك' using errcode='42501';end if;
 if rate is null or rate::text in ('NaN','Infinity','-Infinity') or rate<=0 or rate>1000000 then raise exception 'سعر صرف غير صحيح';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into s from solar_private.exchange_settings where id for update;
 if s.revision is distinct from expected_revision then raise exception 'تغير سعر الصرف؛ حدّث البيانات' using errcode='40001';end if;
 update solar_private.exchange_settings set rate=exchange_set.rate,revision=revision+1,updated_at=now(),updated_by=p.id where id;
 insert into solar_private.exchange_history(rate,changed_by) values(rate,p.id);
 return solar_private.exchange_get();
end $$;
create function public.solar_exchange_rate_get() returns jsonb language sql security invoker set search_path='' as $$select solar_private.exchange_get()$$;
create function public.solar_exchange_rate_set(rate numeric,expected_revision bigint) returns jsonb language sql security invoker set search_path='' as $$select solar_private.exchange_set(rate,expected_revision)$$;

-- These guards stop old clients and direct REST writes from changing pricing
-- snapshots. Private accounting workflows retain their existing access.
create function solar_private.pricing_guard() returns trigger language plpgsql set search_path='' as $$
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
end $$;
create trigger solar_pricing_guard before insert or update on public.products for each row execute function solar_private.pricing_guard();
create trigger solar_pricing_guard before insert or update or delete on public.transactions for each row execute function solar_private.pricing_guard();
create trigger solar_pricing_guard before insert or update or delete on public.transaction_items for each row execute function solar_private.pricing_guard();

create function solar_private.invoice_save(request_id uuid,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare p public.profiles; old_invoice public.transactions; invoice public.transactions;
 cached solar_private.invoice_requests; product public.products; old_item public.transaction_items;
 line jsonb; computed jsonb:='[]'::jsonb; snapshots jsonb:='[]'::jsonb; before_stock jsonb;
 kind text; currency text; mode text; invoice_id bigint; item_id bigint; party_id bigint; owner_id uuid;
 rate numeric; default_rate numeric; source_sum numeric:=0; subtotal numeric:=0; expenses numeric; total numeric; cost numeric:=0;
 qty numeric; price numeric; unit_cost numeric; landed numeric; remaining_qty numeric; remaining_cost numeric;
 previous_qty numeric; previous_value numeric; next_qty numeric; next_cost numeric; product_qty numeric; product_cost numeric;
 new_basis jsonb; result jsonb; economic_change boolean:=true; existing boolean:=false; cash boolean;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') then raise exception 'لا توجد صلاحية لحفظ الفاتورة' using errcode='42501';end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب حفظ غير صحيح';end if;
 kind:=payload->>'kind';currency:=coalesce(payload->>'sourceCurrency','IQD');mode:=coalesce(payload->>'mode','cash');
 if kind not in ('purchase','sale','system') or not(p.is_admin or coalesce(p.permissions->>kind,'false')='true') then raise exception 'لا توجد صلاحية لهذا النوع من الفواتير' using errcode='42501';end if;
 if currency not in ('IQD','USD') or (kind<>'purchase' and currency<>'IQD') or mode not in ('cash','credit') then raise exception 'البيع بالدينار فقط؛ تحقق من العملة وطريقة الدفع';end if;
 if jsonb_typeof(payload->'items') is distinct from 'array' or jsonb_array_length(payload->'items') not between 1 and 500 then raise exception 'أضف مواد صحيحة للفاتورة';end if;
 if length(coalesce(payload->>'notes',''))>4000 then raise exception 'الملاحظات طويلة جداً';end if;
 expenses:=coalesce((payload->>'expenses')::numeric,0);
 if expenses::text in ('NaN','Infinity','-Infinity') or expenses<0 or expenses>1000000000000 then raise exception 'مصاريف غير صحيحة بالدينار';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into cached from solar_private.invoice_requests r where r.request_id=invoice_save.request_id;
 if cached.request_id is not null then
  if cached.user_id<>p.id or cached.payload is distinct from payload then raise exception 'معرّف الطلب مستخدم لبيانات أخرى' using errcode='42501';end if;
  if not exists(select 1 from public.transactions t where t.id=(cached.result->>'id')::bigint) then raise exception 'الفاتورة حذفت أو صفّرت؛ حدّث البيانات' using errcode='40001';end if;
  return cached.result;
 end if;
 invoice_id:=nullif(payload->>'invoiceId','')::bigint;
 if invoice_id is not null then
  select * into old_invoice from public.transactions where id=invoice_id for update;
  if old_invoice.id is null or old_invoice.kind<>kind or (not p.is_admin and coalesce(old_invoice.cashbox_user_id,old_invoice.created_by) is distinct from p.id) then raise exception 'الفاتورة غير متاحة لحسابك' using errcode='42501';end if;
  if old_invoice.pricing_revision is distinct from (payload->>'expectedRevision')::bigint then raise exception 'تغيرت الفاتورة؛ افتح التعديل مجدداً' using errcode='40001';end if;
  if kind='system' then raise exception 'استخدم متابعة التنصيب لتعديل المنظومة';end if;
  if old_invoice.cash is distinct from (mode='cash') then raise exception 'لا يمكن تغيير طريقة دفع الفاتورة المحفوظة';end if;
  existing:=true;owner_id:=coalesce(old_invoice.cashbox_user_id,old_invoice.created_by);
 else
  -- Integer ID allocation is serialized with the existing cash/stock lock.
  invoice_id:=greatest((extract(epoch from clock_timestamp())*1000)::bigint,coalesce((select max(t.id)+1 from public.transactions t),1));
  owner_id:=p.id;
 end if;
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
 subtotal:=round(source_sum*rate,2);total:=subtotal+expenses;
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
 if cash and kind='purchase' and (total-case when existing and old_invoice.cash then old_invoice.total else 0 end)>solar_private.cash_balance(owner_id) then raise exception 'رصيد قاصة صاحب الفاتورة غير كافٍ' using errcode='P0002';end if;
 if existing and kind='sale' and old_invoice.cash and old_invoice.total-total>solar_private.cash_balance(owner_id) then raise exception 'الرصيد لا يكفي لتخفيض البيع النقدي' using errcode='P0002';end if;
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
  if existing then select coalesce(sum(i.qty),0),coalesce(sum(i.qty*case when old_invoice.kind='purchase' then case when i.landed_cost>0 then i.landed_cost else i.price end else i.cost end),0) into previous_qty,previous_value from public.transaction_items i where i.transaction_id=invoice_id and i.product_id=product.id;end if;
  product_qty:=product.qty;product_cost:=product.cost;new_basis:=null;before_stock:=null;
  if kind='purchase' then
   if existing and economic_change and previous_qty>0 then
    if old_invoice.fx_pricing then
     select v into before_stock from jsonb_array_elements(old_invoice.purchase_stock) v where (v->>'id')::bigint=product.id;
     if before_stock is null or product.costing_revision is distinct from (before_stock->>'afterRevision')::bigint then raise exception 'حدثت حركة على المادة بعد الشراء. لا يمكن تغيير كلفتها التاريخية؛ استخدم تسوية أو فاتورة تصحيح' using errcode='40001';end if;
     product_qty:=(before_stock->>'qty')::numeric;product_cost:=(before_stock->>'cost')::numeric;
    else
     if exists(select 1 from public.transaction_items i join public.transactions t on t.id=i.transaction_id where i.product_id=product.id and t.id<>invoice_id and (t.created_at,t.id)>(old_invoice.created_at,old_invoice.id) and t.kind in ('purchase','sale','system')) then raise exception 'حدثت حركة لاحقة؛ لا يمكن إعادة احتساب كلفة شراء قديم' using errcode='40001';end if;
     product_qty:=product.qty-previous_qty;
     if product_qty<0 then raise exception 'لا يمكن تعديل شراء استُهلكت كميته';end if;
     if product_qty>0 then product_cost:=(product.qty*product.cost-previous_value)/product_qty;end if;
     if product_cost<0 then raise exception 'تعذر استعادة الكلفة السابقة؛ استخدم تسوية محاسبية';end if;
    end if;
   end if;
  else product_qty:=product.qty+previous_qty;end if;
  select v into line from jsonb_array_elements(payload->'items') v where (v->>'id')::bigint=product.id;
  if existing and kind='sale' and previous_qty>0 and product.cost is distinct from previous_value/previous_qty and coalesce((line->>'qty')::numeric,0)<>previous_qty then raise exception 'تغيرت كلفة المخزون بعد البيع. عدّل السعر فقط أو سجّل فاتورة تصحيح للكميات' using errcode='40001';end if;
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
     snapshots:=snapshots||jsonb_build_array(jsonb_build_object('id',product.id,'qty',product_qty,'cost',product_cost,'basis',case when before_stock is not null then before_stock->'basis' else product.cost_basis end,'afterRevision',product.costing_revision+case when (next_qty,next_cost) is distinct from (product.qty,product.cost) then 1 else 0 end));
    else next_qty:=product.qty;next_cost:=product.cost;end if;
   else
    if qty>product_qty then raise exception 'الكمية غير كافية للمادة: %',product.name;end if;
    select * into old_item from public.transaction_items i where existing and i.transaction_id=invoice_id and i.product_id=product.id order by i.id limit 1;
    unit_cost:=case when old_item.id is not null then old_item.cost else product.cost end;
    new_basis:=case when old_item.id is not null then old_item.cost_basis else product.cost_basis end;
    landed:=0;next_qty:=product_qty-qty;next_cost:=product.cost;
   end if;
   cost:=cost+qty*unit_cost;
   computed:=computed||jsonb_build_array(jsonb_build_object('id',product.id,'name',product.name,'brand',(select b.name from public.brands b where b.id=product.brand_id),'category',product.category,'qty',qty,'price',case when kind='system' then 0 else round(price*rate,6) end,'sourcePrice',case when kind='purchase' then price else null end,'cost',unit_cost,'landedCost',landed,'costBasis',new_basis));
  end if;
  if kind<>'purchase' or not existing or economic_change then
   update public.products set qty=next_qty,cost=next_cost,cost_basis=case when kind='purchase' then case when line is null and before_stock is not null then before_stock->'basis' else jsonb_build_object('method','weighted-average','lastPurchase',new_basis,'unitCost',next_cost) end else case when product.cost_basis='{}'::jsonb then jsonb_build_object('method','legacy-iqd','unitCost',next_cost) else product.cost_basis end end where id=product.id;
  end if;
 end loop;
 if jsonb_array_length(computed)<>jsonb_array_length(payload->'items') then raise exception 'إحدى المواد غير موجودة؛ حدّث البيانات';end if;
 cost:=round(cost,2);
 if existing then
  update public.transactions set party_name=nullif(payload->>'party',''),party_id=party_id,party_type=case when kind='purchase' then 'supplier' else 'customer' end,
   subtotal=subtotal,total=total,expenses=expenses,cost=cost,profit=case when kind='sale' then subtotal-cost when kind='system' then total-cost-expenses else 0 end,
   notes=nullif(payload->>'notes',''),source_currency=currency,exchange_rate=rate,source_subtotal=source_sum,fx_pricing=true,
   purchase_stock=case when kind='purchase' and economic_change then snapshots else purchase_stock end where id=invoice_id returning * into invoice;
 else
  insert into public.transactions(id,kind,party_type,party_id,party_name,payment_mode,subtotal,expenses,total,cost,profit,notes,cash,created_by,cashbox_user_id,
   source_currency,exchange_rate,source_subtotal,fx_pricing,purchase_stock,installer_id,install_date,install_time,customer_address,customer_phone,installation_status)
  values(invoice_id,kind,case when kind='purchase' then 'supplier' else 'customer' end,party_id,nullif(payload->>'party',''),mode,subtotal,expenses,total,cost,
   case when kind='sale' then subtotal-cost when kind='system' then total-cost-expenses else 0 end,nullif(payload->>'notes',''),cash,p.id,owner_id,
   currency,rate,source_sum,true,snapshots,case when kind='system' then (payload->>'installerId')::uuid end,
   nullif(payload->>'installDate','')::date,nullif(payload->>'installTime','')::time,nullif(payload->>'customerAddress',''),nullif(payload->>'customerPhone',''),case when kind='system' then 'pending' else 'none' end)
  returning * into invoice;
 end if;
 if not(existing and kind='purchase' and not economic_change) then
  delete from public.transaction_items where transaction_id=invoice_id;
  for line in select value from jsonb_array_elements(computed) loop
   insert into public.transaction_items(transaction_id,product_id,product_name,brand_name,category,qty,price,cost,landed_cost,source_price,cost_basis)
   values(invoice_id,(line->>'id')::bigint,line->>'name',line->>'brand',line->>'category',(line->>'qty')::numeric,(line->>'price')::numeric,(line->>'cost')::numeric,(line->>'landedCost')::numeric,(line->>'sourcePrice')::numeric,line->'costBasis');
  end loop;
 end if;
 select * into invoice from public.transactions where id=invoice_id;
 result:=jsonb_build_object('id',invoice.id,'receiptNo',invoice.receipt_no,'pricingRevision',invoice.pricing_revision,'total',invoice.total,'cost',invoice.cost,'profit',invoice.profit);
 insert into solar_private.invoice_requests(request_id,user_id,payload,result) values(request_id,p.id,payload,result);
 return result;
end $$;
create function public.solar_invoice_save(request_id uuid,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select solar_private.invoice_save(request_id,payload)$$;

create function solar_private.purchase_delete(invoice_id bigint,expected_revision bigint) returns void language plpgsql security definer set search_path='' as $$
declare p public.profiles; t public.transactions; snapshot jsonb; product public.products;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'purchase','false')='true') then raise exception 'لا توجد صلاحية حذف الشراء' using errcode='42501';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into t from public.transactions where id=invoice_id and kind='purchase' for update;
 if t.id is null or not t.fx_pricing or (not p.is_admin and coalesce(t.cashbox_user_id,t.created_by) is distinct from p.id) then raise exception 'الفاتورة غير متاحة' using errcode='42501';end if;
 if jsonb_array_length(t.purchase_stock)=0 or jsonb_array_length(t.purchase_stock)<>(select count(distinct i.product_id) from public.transaction_items i where i.transaction_id=t.id) then raise exception 'لا توجد كلفة سابقة موثقة لاستعادة هذه الفاتورة؛ استخدم تسوية محاسبية';end if;
 if t.pricing_revision is distinct from expected_revision then raise exception 'تغيرت الفاتورة؛ حدّث البيانات' using errcode='40001';end if;
 for snapshot in select v from jsonb_array_elements(t.purchase_stock) v order by (v->>'id')::bigint loop
  select * into product from public.products where id=(snapshot->>'id')::bigint for update;
  if product.id is null or product.costing_revision is distinct from (snapshot->>'afterRevision')::bigint then raise exception 'حدثت حركة على المادة بعد الشراء؛ لا يمكن حذف كلفتها التاريخية' using errcode='40001';end if;
  update public.products set qty=(snapshot->>'qty')::numeric,cost=(snapshot->>'cost')::numeric,cost_basis=snapshot->'basis' where id=product.id;
 end loop;
 -- Retain the original invoice and snapshots as an audit record.
 insert into solar_private.deleted_sales(invoice_id,invoice,items,deleted_by)
 select t.id,to_jsonb(t),coalesce(jsonb_agg(to_jsonb(i)),'[]'::jsonb),p.id from public.transaction_items i where i.transaction_id=t.id;
 delete from public.cash_ledger where transaction_id=t.id;
 delete from public.transactions where id=t.id;
end $$;
create function public.solar_purchase_delete(invoice_id bigint,expected_revision bigint) returns void language sql security invoker set search_path='' as $$select solar_private.purchase_delete(invoice_id,expected_revision)$$;

revoke all on function solar_private.exchange_get(),solar_private.exchange_set(numeric,bigint),solar_private.invoice_save(uuid,jsonb),solar_private.purchase_delete(bigint,bigint) from public,anon;
grant execute on function solar_private.exchange_get(),solar_private.exchange_set(numeric,bigint),solar_private.invoice_save(uuid,jsonb),solar_private.purchase_delete(bigint,bigint) to authenticated;
revoke all on function public.solar_exchange_rate_get(),public.solar_exchange_rate_set(numeric,bigint),public.solar_invoice_save(uuid,jsonb),public.solar_purchase_delete(bigint,bigint) from public,anon;
grant execute on function public.solar_exchange_rate_get(),public.solar_exchange_rate_set(numeric,bigint),public.solar_invoice_save(uuid,jsonb),public.solar_purchase_delete(bigint,bigint) to authenticated;
revoke all on function solar_private.pricing_guard() from public,anon,authenticated;

-- Returning a protected sale adds its original cost to today's stock value;
-- it must not put historic units back at today's different average cost.
create function solar_private.currency_sale_delete(invoice_id bigint,expected_token text) returns void language plpgsql security definer set search_path='' as $$
declare snapshots jsonb; snapshot jsonb; protected boolean; next_cost numeric;
begin
 if auth.uid() is null then raise exception 'Active login required' using errcode='42501';end if;
 perform pg_advisory_xact_lock(7311,1);
 select t.fx_pricing into protected from public.transactions t where t.id=invoice_id and t.kind in ('sale','system');
 if coalesce(protected,false) then
  perform 1 from public.products p where p.id in (select i.product_id from public.transaction_items i where i.transaction_id=invoice_id) order by p.id for update;
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'value',p.qty*p.cost+x.value,'qty',p.qty+x.qty)),'[]'::jsonb) into snapshots
  from public.products p join (select i.product_id,sum(i.qty) qty,sum(i.qty*i.cost) value from public.transaction_items i where i.transaction_id=invoice_id group by i.product_id) x on x.product_id=p.id;
 end if;
 -- The original routine enforces ownership, delete permissions, token, cash,
 -- approved installation expenses, audit retention and notifications.
 perform solar_private.sale_delete(invoice_id,expected_token);
 if coalesce(protected,false) then
  for snapshot in select v from jsonb_array_elements(snapshots) v loop
   next_cost:=round((snapshot->>'value')::numeric/(snapshot->>'qty')::numeric,6);
   update public.products set cost=next_cost,cost_basis=jsonb_set(cost_basis,'{unitCost}',to_jsonb(next_cost)) where id=(snapshot->>'id')::bigint;
  end loop;
 end if;
end $$;
revoke all on function solar_private.currency_sale_delete(bigint,text) from public,anon;
grant execute on function solar_private.currency_sale_delete(bigint,text) to authenticated;
create or replace function public.solar_sale_delete(invoice_id bigint,expected_token text) returns void language sql security invoker set search_path='' as $$select solar_private.currency_sale_delete(invoice_id,expected_token)$$;
revoke all on function public.solar_sale_delete(bigint,text) from public,anon;
grant execute on function public.solar_sale_delete(bigint,text) to authenticated;
