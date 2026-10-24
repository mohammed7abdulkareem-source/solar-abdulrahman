-- Replacement cost follows the daily USD rate. Historical procurement, cash,
-- supplier postings and prior sale quotes remain immutable book snapshots.
create function solar_private.inventory_currency_parts(material_id bigint,basis jsonb,book_cost numeric,depth integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare source jsonb;parts jsonb;t public.transactions;snapshot jsonb;units numeric;source_price numeric;landed numeric;before_qty numeric;denominator numeric;usd numeric;iqd numeric;expected_cost numeric;begin
 if depth>80 then raise exception 'تسلسل كلفة المادة غير صحيح';end if;
 if jsonb_typeof(basis->'currencyComponents')='object' then
  usd:=(basis->'currencyComponents'->>'usd')::numeric;iqd:=(basis->'currencyComponents'->>'iqd')::numeric;
  if usd is null or iqd is null or usd<0 or iqd<0 or usd::text in('NaN','Infinity') or iqd::text in('NaN','Infinity') then raise exception 'مكونات كلفة المادة غير صحيحة';end if;
  return jsonb_build_object('usd',usd,'iqd',iqd);
 end if;
 source:=basis->'lastPurchase';
 if source->>'invoiceId' is null then return jsonb_build_object('usd',0,'iqd',coalesce(book_cost,0));end if;
 select * into t from public.transactions where id=(source->>'invoiceId')::bigint and kind='purchase';
 if t.id is null then raise exception 'تعذر ربط أصل كلفة المادة بفاتورة الشراء';end if;
 select v into snapshot from jsonb_array_elements(t.purchase_stock) v where(v->>'id')::bigint=material_id;
 select sum(i.qty),sum(i.qty*coalesce(i.source_price,i.price/t.exchange_rate))/nullif(sum(i.qty),0),sum(i.qty*case when i.landed_cost>0 then i.landed_cost else i.price end)/nullif(sum(i.qty),0)
 into units,source_price,landed from public.transaction_items i where i.transaction_id=t.id and i.product_id=material_id;
 if snapshot is null or not(units>0) then raise exception 'مصدر كلفة المادة غير مكتمل';end if;
 before_qty:=(snapshot->>'qty')::numeric;denominator:=before_qty+units;
 expected_cost:=round((before_qty*(snapshot->>'cost')::numeric+units*landed)/denominator,6);
 if abs(expected_cost-book_cost)>.00001 then raise exception 'تحتاج كلفة المادة مراجعة حركات الإرجاع قبل اعتماد الصرف';end if;
 parts:=case when before_qty>0 then solar_private.inventory_currency_parts(material_id,snapshot->'basis',(snapshot->>'cost')::numeric,depth+1) else '{"usd":0,"iqd":0}'::jsonb end;
 usd:=(before_qty*(parts->>'usd')::numeric+units*case when t.source_currency='USD' then source_price else 0 end)/denominator;
 iqd:=(before_qty*(parts->>'iqd')::numeric+units*case when t.source_currency='USD' then greatest(0,landed-source_price*t.exchange_rate) else landed end)/denominator;
 return jsonb_build_object('usd',usd,'iqd',iqd);
end$$;
revoke all on function solar_private.inventory_currency_parts(bigint,jsonb,numeric,integer) from public,anon,authenticated;

create function solar_private.valuation_quote(material_id bigint,basis jsonb,book_cost numeric) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare parts jsonb;settings solar_private.exchange_settings;current_cost numeric;begin
 parts:=solar_private.inventory_currency_parts(material_id,basis,book_cost);
 select * into settings from solar_private.exchange_settings where id;
 current_cost:=case when settings.rate is null then book_cost else round((parts->>'usd')::numeric*settings.rate+(parts->>'iqd')::numeric,6) end;
 return coalesce(basis,'{}')||jsonb_build_object('currencyComponents',parts,'bookUnitCost',book_cost,'valuationUnitCost',current_cost,'valuationRate',settings.rate,'valuationRevision',settings.revision);
end$$;
revoke all on function solar_private.valuation_quote(bigint,jsonb,numeric) from public,anon,authenticated;
create function solar_private.current_unit_cost(material_id bigint,basis jsonb,book_cost numeric) returns numeric
language sql stable security definer set search_path='' as $$select(solar_private.valuation_quote(material_id,basis,book_cost)->>'valuationUnitCost')::numeric$$;
revoke all on function solar_private.current_unit_cost(bigint,jsonb,numeric) from public,anon,authenticated;

-- Capture only the products that the original protected workflow will mutate.
create function solar_private.valuation_stock_snapshot(ids bigint[]) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'qty',p.qty,'cost',p.cost,'basis',p.cost_basis,'parts',solar_private.inventory_currency_parts(p.id,p.cost_basis,p.cost)) order by p.id),'[]') from public.products p where p.id=any(ids)
$$;
revoke all on function solar_private.valuation_stock_snapshot(bigint[]) from public,anon,authenticated;

-- Sales consume the current weighted stock mix. An authorized quantity return
-- restores the historical currency components of the returned sale, not IQD
-- translated at today's rate. This function never posts cash or supplier money.
create function solar_private.valuation_reconcile_sale(snapshots jsonb,old_lines jsonb,new_lines jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare snap jsonb;p public.products;old_qty numeric;new_qty numeric;returned numeric;book_unit numeric;usd_unit numeric;iqd_unit numeric;parts jsonb;book_value numeric;usd_value numeric;iqd_value numeric;line jsonb;weight numeric;next_cost numeric;begin
 for snap in select value from jsonb_array_elements(snapshots) loop
  select coalesce(sum((x->>'qty')::numeric),0) into old_qty from jsonb_array_elements(old_lines)x where(x->>'product_id')::bigint=(snap->>'id')::bigint;
  select coalesce(sum((x->>'qty')::numeric),0) into new_qty from jsonb_array_elements(new_lines)x where(x->>'product_id')::bigint=(snap->>'id')::bigint;
  returned:=old_qty-new_qty;if returned=0 then continue;end if;
  select * into p from public.products where id=(snap->>'id')::bigint for update;
  if p.qty is distinct from(snap->>'qty')::numeric+returned then raise exception 'كمية المخزون لا تطابق تعديل الوصل' using errcode='23514';end if;
  book_unit:=(snap->>'cost')::numeric;usd_unit:=(snap->'parts'->>'usd')::numeric;iqd_unit:=(snap->'parts'->>'iqd')::numeric;
  if returned>0 then
   book_unit:=0;usd_unit:=0;iqd_unit:=0;
   for line in select value from jsonb_array_elements(old_lines) where(value->>'product_id')::bigint=p.id loop
    weight:=(line->>'qty')::numeric/old_qty;
    parts:=solar_private.inventory_currency_parts(p.id,line->'cost_basis',coalesce((line->'cost_basis'->>'bookUnitCost')::numeric,(line->>'cost')::numeric));
    book_unit:=book_unit+weight*coalesce((line->'cost_basis'->>'bookUnitCost')::numeric,(line->>'cost')::numeric);
    usd_unit:=usd_unit+weight*(parts->>'usd')::numeric;iqd_unit:=iqd_unit+weight*(parts->>'iqd')::numeric;
   end loop;
  end if;
  book_value:=(snap->>'qty')::numeric*(snap->>'cost')::numeric+returned*book_unit;
  usd_value:=(snap->>'qty')::numeric*(snap->'parts'->>'usd')::numeric+returned*usd_unit;
  iqd_value:=(snap->>'qty')::numeric*(snap->'parts'->>'iqd')::numeric+returned*iqd_unit;
  if least(book_value,usd_value,iqd_value)<-.00001 then raise exception 'قيم المخزون لا تطابق مكونات كلفته';end if;
  if new_qty>old_qty and old_qty>0 then
   -- Quantity additions consume today's book mix while the saved financial
   -- quote stays frozen. Retain the actual return basis for a future deletion.
   book_unit:=0;usd_unit:=0;iqd_unit:=0;
   for line in select value from jsonb_array_elements(old_lines) where(value->>'product_id')::bigint=p.id loop
    weight:=(line->>'qty')::numeric;
    parts:=solar_private.inventory_currency_parts(p.id,line->'cost_basis',coalesce((line->'cost_basis'->>'bookUnitCost')::numeric,(line->>'cost')::numeric));
    book_unit:=book_unit+weight*coalesce((line->'cost_basis'->>'bookUnitCost')::numeric,(line->>'cost')::numeric);
    usd_unit:=usd_unit+weight*(parts->>'usd')::numeric;iqd_unit:=iqd_unit+weight*(parts->>'iqd')::numeric;
   end loop;
   parts:=jsonb_build_object('usd',(usd_unit+(new_qty-old_qty)*(snap->'parts'->>'usd')::numeric)/new_qty,'iqd',(iqd_unit+(new_qty-old_qty)*(snap->'parts'->>'iqd')::numeric)/new_qty);
   update public.transaction_items set cost_basis=cost_basis||jsonb_build_object('bookUnitCost',(book_unit+(new_qty-old_qty)*(snap->>'cost')::numeric)/new_qty,'currencyComponents',parts) where transaction_id=(new_lines->0->>'transaction_id')::bigint and product_id=p.id;
  end if;
  if p.qty>0 then
   next_cost:=round(greatest(0,book_value)/p.qty,6);parts:=jsonb_build_object('usd',greatest(0,usd_value)/p.qty,'iqd',greatest(0,iqd_value)/p.qty);
   update public.products set cost=next_cost,cost_basis=cost_basis||jsonb_build_object('unitCost',next_cost,'currencyComponents',parts) where id=p.id;
  else
   update public.products set cost_basis=cost_basis||jsonb_build_object('currencyComponents',snap->'parts') where id=p.id;
  end if;
 end loop;
end$$;
revoke all on function solar_private.valuation_reconcile_sale(jsonb,jsonb,jsonb) from public,anon,authenticated;

do $$declare definition text;begin
 definition:=pg_get_functiondef('solar_private.invoice_save_v333(uuid,jsonb)'::regprocedure);
 if strpos(definition,'cash boolean;')=0 then raise exception 'Unexpected invoice_save_v333 valuation contract';end if;
 definition:=replace(definition,'cash boolean;','cash boolean; currency_before jsonb;currency_after jsonb;quote jsonb;');
 if strpos(definition,'else i.cost end),0) into previous_qty,previous_value')=0 then raise exception 'Unexpected invoice_save_v333 valuation contract';end if;
 definition:=replace(definition,'else i.cost end),0) into previous_qty,previous_value','else coalesce((i.cost_basis->>''bookUnitCost'')::numeric,i.cost) end),0) into previous_qty,previous_value');
 if strpos(definition,'  select v into line from jsonb_array_elements(payload->''items'') v where (v->>''id'')::bigint=product.id;')=0 then raise exception 'Unexpected invoice_save_v333 valuation contract';end if;
 definition:=replace(definition,'  select v into line from jsonb_array_elements(payload->''items'') v where (v->>''id'')::bigint=product.id;','  currency_before:=solar_private.inventory_currency_parts(product.id,case when before_stock is not null then before_stock->''basis'' else product.cost_basis end,product_cost);
  currency_after:=currency_before;
  select v into line from jsonb_array_elements(payload->''items'') v where (v->>''id'')::bigint=product.id;');
 if strpos(definition,'     next_qty:=product_qty+qty;next_cost:=round((product_qty*product_cost+qty*landed)/next_qty,6);')=0 then raise exception 'Unexpected invoice_save_v333 valuation contract';end if;
 definition:=replace(definition,'     next_qty:=product_qty+qty;next_cost:=round((product_qty*product_cost+qty*landed)/next_qty,6);','     next_qty:=product_qty+qty;next_cost:=round((product_qty*product_cost+qty*landed)/next_qty,6);
     currency_after:=jsonb_build_object(''usd'',(product_qty*(currency_before->>''usd'')::numeric+qty*case when currency=''USD'' then price else 0 end)/next_qty,''iqd'',(product_qty*(currency_before->>''iqd'')::numeric+qty*case when currency=''USD'' then greatest(0,landed-price*rate) else landed end)/next_qty);');
 if strpos(definition,'    unit_cost:=case when old_item.id is not null then old_item.cost else product.cost end;
    new_basis:=case when old_item.id is not null then old_item.cost_basis else product.cost_basis end;')=0 then raise exception 'Unexpected invoice_save_v333 valuation contract';end if;
 definition:=replace(definition,'    unit_cost:=case when old_item.id is not null then old_item.cost else product.cost end;
    new_basis:=case when old_item.id is not null then old_item.cost_basis else product.cost_basis end;','    quote:=solar_private.valuation_quote(product.id,product.cost_basis,product.cost);
    unit_cost:=case when old_item.id is not null then old_item.cost else (quote->>''valuationUnitCost'')::numeric end;
    new_basis:=case when old_item.id is not null then old_item.cost_basis else quote end;');
 if strpos(definition,'jsonb_build_object(''method'',''weighted-average'',''lastPurchase'',new_basis,''unitCost'',next_cost)')=0 then raise exception 'Unexpected invoice_save_v333 valuation contract';end if;
 definition:=replace(definition,'jsonb_build_object(''method'',''weighted-average'',''lastPurchase'',new_basis,''unitCost'',next_cost)','jsonb_build_object(''method'',''weighted-average'',''lastPurchase'',new_basis,''unitCost'',next_cost,''currencyComponents'',currency_after)');
 if strpos(definition,'else product.cost_basis end end where id=product.id;')=0 then raise exception 'Unexpected invoice_save_v333 valuation contract';end if;
 definition:=replace(definition,'else product.cost_basis end end where id=product.id;','else product.cost_basis end||jsonb_build_object(''currencyComponents'',currency_before) end where id=product.id;');
 execute definition;
end$$;

do $$declare definition text;begin
 definition:=pg_get_functiondef('solar_private.invoice_save(uuid,jsonb)'::regprocedure);
 if strpos(definition,'declare result jsonb;before_row public.transactions;after_row public.transactions;location bigint;begin')=0 then raise exception 'Unexpected invoice_save valuation contract';end if;
 definition:=replace(definition,'declare result jsonb;before_row public.transactions;after_row public.transactions;location bigint;begin','declare result jsonb;before_row public.transactions;after_row public.transactions;location bigint;before_stock jsonb;old_lines jsonb:=''[]'';new_lines jsonb;ids bigint[];cached boolean;begin');
 if strpos(definition,' result:=solar_private.invoice_save_v333(request_id,payload);')=0 then raise exception 'Unexpected invoice_save valuation contract';end if;
 definition:=replace(definition,' result:=solar_private.invoice_save_v333(request_id,payload);',' select exists(select 1 from solar_private.invoice_requests r where r.request_id=invoice_save.request_id) into cached;
 if not cached and payload->>''kind'' in(''sale'',''system'') then
  if before_row.id is not null then select coalesce(jsonb_agg(to_jsonb(i)),''[]'') into old_lines from public.transaction_items i where transaction_id=before_row.id;end if;
  select array_agg(distinct id) into ids from(select (v->>''id'')::bigint id from jsonb_array_elements(payload->''items'')v union select (v->>''product_id'')::bigint from jsonb_array_elements(old_lines)v)s;
  before_stock:=solar_private.valuation_stock_snapshot(ids);
  if payload->>''valuationRevision'' is not null and (payload->>''valuationRevision'')::bigint is distinct from(select revision from solar_private.exchange_settings where id) then raise exception ''تغير سعر الصرف؛ تم تحديث الكلفة، راجع الربح وأعد الحفظ'' using errcode=''PT409'';end if;
 end if;
 result:=solar_private.invoice_save_v333(request_id,payload);
 if not cached and payload->>''kind'' in(''sale'',''system'') then
  select coalesce(jsonb_agg(to_jsonb(i)),''[]'') into new_lines from public.transaction_items i where transaction_id=(result->>''id'')::bigint;
  perform solar_private.valuation_reconcile_sale(before_stock,old_lines,new_lines);
 end if;');
 execute definition;
end$$;

do $$declare definition text;begin
 definition:=pg_get_functiondef('solar_private.inventory_catalog(bigint)'::regprocedure);
 if strpos(definition,'jsonb_build_object(''cost'',m.cost,''cost_basis'',m.cost_basis,''costing_revision''')=0 then raise exception 'Unexpected inventory_catalog valuation contract';end if;
 definition:=replace(definition,'jsonb_build_object(''cost'',m.cost,''cost_basis'',m.cost_basis,''costing_revision''','jsonb_build_object(''cost'',solar_private.current_unit_cost(m.id,m.cost_basis,m.cost),''bookCost'',m.cost,''cost_basis'',solar_private.valuation_quote(m.id,m.cost_basis,m.cost),''costing_revision''');
 execute definition;
end$$;

do $$declare definition text;begin
 definition:=pg_get_functiondef('solar_private.capital_snapshot()'::regprocedure);
 if strpos(definition,'stock:=solar_private.inventory_catalog(null);')=0 then raise exception 'Unexpected capital_snapshot valuation contract';end if;
 definition:=replace(definition,'stock:=solar_private.inventory_catalog(null);','stock:=(select coalesce(jsonb_agg(v||jsonb_build_object(''cost'',v->''bookCost'')),''[]'') from jsonb_array_elements(solar_private.inventory_catalog(null))v);');
 execute definition;
end$$;

CREATE OR REPLACE FUNCTION solar_private.currency_sale_delete(invoice_id bigint, expected_token text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare snapshots jsonb;old_lines jsonb;ids bigint[];begin
 if auth.uid() is null then raise exception 'Active login required' using errcode='42501';end if;
 perform pg_advisory_xact_lock(7311,1);
 select coalesce(jsonb_agg(to_jsonb(i)),'[]'),array_agg(distinct i.product_id) into old_lines,ids from public.transaction_items i where i.transaction_id=invoice_id;
 snapshots:=solar_private.valuation_stock_snapshot(ids);
 perform solar_private.sale_delete(invoice_id,expected_token);
 perform solar_private.valuation_reconcile_sale(snapshots,old_lines,'[]');
end $function$;

do $$declare definition text;begin
 definition:=pg_get_functiondef('solar_private.warehouse_action_v364(bigint,text,text,jsonb,text)'::regprocedure);
 if strpos(definition,'newqty numeric; oldqty numeric; newtotal numeric; newcost numeric; wanted jsonb; id_value bigint;')=0 then raise exception 'Unexpected warehouse_action_v364 valuation contract';end if;
 definition:=replace(definition,'newqty numeric; oldqty numeric; newtotal numeric; newcost numeric; wanted jsonb; id_value bigint;','newqty numeric; oldqty numeric; newtotal numeric; newcost numeric; wanted jsonb; id_value bigint;snapshots jsonb;ids bigint[];quote jsonb;');
 if strpos(definition,'  for id_value in select product_id')=0 then raise exception 'Unexpected warehouse_action_v364 valuation contract';end if;
 definition:=replace(definition,'  for id_value in select product_id','  select array_agg(distinct id) into ids from(select product_id id from public.transaction_items where transaction_id=j.id union select (e->>''productId'')::bigint from jsonb_array_elements(lines)e)s;
  snapshots:=solar_private.valuation_stock_snapshot(ids);
  for id_value in select product_id');
 if strpos(definition,'    insert into public.transaction_items(transaction_id,product_id,product_name,brand_name,category,qty,price,cost)
    values(j.id,prod.id,prod.name,(select name from public.brands where id=prod.brand_id),prod.category,(entry->>''qty'')::numeric,0,prod.cost);')=0 then raise exception 'Unexpected warehouse_action_v364 valuation contract';end if;
 definition:=replace(definition,'    insert into public.transaction_items(transaction_id,product_id,product_name,brand_name,category,qty,price,cost)
    values(j.id,prod.id,prod.name,(select name from public.brands where id=prod.brand_id),prod.category,(entry->>''qty'')::numeric,0,prod.cost);','    quote:=solar_private.valuation_quote(prod.id,prod.cost_basis,prod.cost);
    insert into public.transaction_items(transaction_id,product_id,product_name,brand_name,category,qty,price,cost,cost_basis)
    values(j.id,prod.id,prod.name,(select name from public.brands where id=prod.brand_id),prod.category,(entry->>''qty'')::numeric,0,(quote->>''valuationUnitCost'')::numeric,quote);');
 if strpos(definition,'  select coalesce(sum(qty*price),0),coalesce(sum(qty*cost),0) into newtotal,newcost')=0 then raise exception 'Unexpected warehouse_action_v364 valuation contract';end if;
 definition:=replace(definition,'  select coalesce(sum(qty*price),0),coalesce(sum(qty*cost),0) into newtotal,newcost','  select coalesce(jsonb_agg(to_jsonb(i)),''[]'') into after_items from public.transaction_items i where transaction_id=j.id;
  perform solar_private.valuation_reconcile_sale(snapshots,before_items,after_items);
  select coalesce(sum(qty*price),0),coalesce(sum(qty*cost),0) into newtotal,newcost');
 execute definition;
end$$;

do $$declare definition text;begin
 definition:=pg_get_functiondef('solar_private.quick_search(text,text)'::regprocedure);
 if strpos(definition,'case when financial then m.cost end cost')=0 then raise exception 'Unexpected quick_search valuation contract';end if;
 definition:=replace(definition,'case when financial then m.cost end cost','case when financial then solar_private.current_unit_cost(m.id,m.cost_basis,m.cost) end cost');
 execute definition;
end$$;

do $$declare definition text;begin
 definition:=pg_get_functiondef('solar_private.inventory(text,uuid,jsonb)'::regprocedure);
 if strpos(definition,'  return result||jsonb_build_object(''transferDirections''')=0 then raise exception 'Unexpected inventory valuation contract';end if;
 definition:=replace(definition,'  return result||jsonb_build_object(''transferDirections''','  return result||case when person.user_type=''warehouse'' then ''{}''::jsonb else(select jsonb_build_object(''valuationRevision'',revision,''valuationRate'',rate) from solar_private.exchange_settings where id) end||jsonb_build_object(''transferDirections''');
 if strpos(definition,'''unitCost'',material.cost,''costBasis'',material.cost_basis')=0 then raise exception 'Unexpected inventory valuation contract';end if;
 definition:=replace(definition,'''unitCost'',material.cost,''costBasis'',material.cost_basis','''unitCost'',solar_private.current_unit_cost(material.id,material.cost_basis,material.cost),''costBasis'',solar_private.valuation_quote(material.id,material.cost_basis,material.cost)');
 execute definition;
end$$;

revoke execute on function solar_private.sale_delete(bigint,text) from public,anon,authenticated;
