-- The price used to quote a system is separate from the price paid for its
-- stock and the personal profit basis. Keep only the agreed unit prices here.
create table solar_private.system_receipt_material_prices (
 invoice_id bigint primary key references public.transactions(id) on delete cascade,
 signature jsonb not null,
 prices jsonb not null
);
alter table solar_private.system_receipt_material_prices enable row level security;
revoke all on solar_private.system_receipt_material_prices from public,anon,authenticated;

alter function solar_private.assert_system_pricing(bigint) rename to assert_system_pricing_v4125;
revoke all on function solar_private.assert_system_pricing_v4125(bigint) from public,anon,authenticated;

create function solar_private.check_system_material_prices(receipt_id bigint, prepared jsonb, expected_tokens jsonb, negotiated boolean)
returns void language plpgsql security definer set search_path='' as $$
declare
 invoice public.transactions; prior solar_private.system_receipt_material_prices; signature jsonb; quantities jsonb;
 quoted jsonb; prices jsonb; minimum_total numeric; hidden boolean; ids bigint[];
begin
 select * into invoice from public.transactions t where t.id=receipt_id and t.kind='system';
 if not found then return;end if;
 select * into prior from solar_private.system_receipt_material_prices s where s.invoice_id=receipt_id;
 if prior.invoice_id is null and not negotiated then
  perform solar_private.assert_system_pricing_v4125(receipt_id);
  return;
 end if;

 select coalesce(jsonb_object_agg(product_id,quantity),'{}'::jsonb),array_agg(product_id)
 into quantities,ids from (
  select i.product_id,sum(i.qty) quantity from public.transaction_items i
  where i.transaction_id=receipt_id and i.product_id is not null group by i.product_id
 ) lines;
 signature:=jsonb_build_object('total',invoice.total,'items',quantities);
 if prior.signature is distinct from signature then
  quoted:=coalesce(prepared,solar_private.wholesale_floor_snapshot(ids));
  if expected_tokens is not null and (jsonb_typeof(expected_tokens) is distinct from 'object' or
    exists(select from unnest(ids) as n(product_id)
      where expected_tokens->>n.product_id::text is distinct from quoted->n.product_id::text->>'floorToken')) then
   raise exception 'تغيّر سعر إحدى مواد المنظومة؛ حدّث أسعار المواد ثم احفظ الوصل' using errcode='PT409';
  end if;
  if exists(select from public.transaction_items i where i.transaction_id=receipt_id and (i.product_id is null or
      quoted->i.product_id::text->>'effectiveMinPrice' is null or
      (quoted->i.product_id::text->>'effectiveMinPrice')::numeric<0 or
      quoted->i.product_id::text->>'effectiveMinPrice' in('NaN','Infinity','-Infinity'))) then
   raise exception 'تعذّر تحديد سعر إحدى مواد المنظومة' using errcode='PT422';
  end if;
  select coalesce(jsonb_object_agg(n.id,jsonb_build_object('price',quoted->n.id::text->'effectiveMinPrice',
   'source',quoted->n.id::text->'floorSource')),'{}'::jsonb) into prices from unnest(ids)n(id);
  insert into solar_private.system_receipt_material_prices(invoice_id,signature,prices) values(receipt_id,signature,prices)
   on conflict on constraint system_receipt_material_prices_pkey do update set signature=excluded.signature,prices=excluded.prices;
 else
  prices:=prior.prices;
 end if;
 if invoice.system_min_profit_percent is null or (select c.system_free_pricing from solar_private.operation_controls c where c.id) then return;end if;
 select ceil((round(coalesce(sum(q.value::numeric*(prices->q.key->>'price')::numeric),0),2)+coalesce(invoice.expenses,0)
               +coalesce(invoice.installation_expenses,0))*(100+invoice.system_min_profit_percent))/100,
  coalesce(bool_or(prices->q.key->>'source'='cost'),false)
 into minimum_total,hidden from jsonb_each_text(quantities) q;
 if invoice.total<minimum_total then
  if hidden and (solar_private.personal_archive_priced(receipt_id) or
    exists(select from public.profiles p where p.id=auth.uid() and p.user_type in('warehouse','installer'))) then
   raise exception 'سعر المنظومة أقل من الحد المسموح بعد احتساب أسعار المواد والمصاريف' using errcode='PT422';
  end if;
  raise exception 'أقل سعر مسموح للمنظومة بعد احتساب أسعار المواد والمصاريف هو % د.ع',minimum_total using errcode='PT422';
 end if;
end $$;
revoke all on function solar_private.check_system_material_prices(bigint,jsonb,jsonb,boolean) from public,anon,authenticated;

create function solar_private.assert_system_pricing(invoice_id bigint) returns void
language sql security definer set search_path='' as $$
 select solar_private.check_system_material_prices(invoice_id,null,null,false)
$$;
revoke all on function solar_private.assert_system_pricing(bigint) from public,anon,authenticated;

-- The ordinary writer can capture the pre-posting FX valuation even when a
-- sale depletes the stock. Older clients need no price fields in their payload.
do $writer$
declare definition text:=pg_get_functiondef('solar_private.invoice_save(uuid,jsonb)'::regprocedure);
 begin_block constant text:=$o$if not cached and payload->>'kind'='system'then
  select * into after_row from public.transactions where id=(invoice_result->>'id')::bigint;$o$;
begin
 if strpos(definition,begin_block)=0 or strpos(definition,'before_stock:=solar_private.valuation_stock_snapshot(ids);')=0 or
   strpos(definition,'perform solar_private.assert_system_pricing(after_row.id);')=0 then raise exception 'Review system material save path';end if;
 definition:=replace(definition,'declare invoice_result jsonb;','declare invoice_result jsonb; system_floors jsonb; renegotiated boolean;');
 definition:=replace(definition,'before_stock:=solar_private.valuation_stock_snapshot(ids);',$n$before_stock:=solar_private.valuation_stock_snapshot(ids);
  if payload->>'kind'='system' then
   system_floors:=solar_private.wholesale_floor_snapshot(ids);
  end if;$n$);
 definition:=replace(definition,begin_block,begin_block||$n$
  renegotiated:=before_row.id is null or before_row.total is distinct from after_row.total or exists (
   select product_id,sum(qty) from (
    select (i->>'product_id')::bigint product_id,(i->>'qty')::numeric qty from jsonb_array_elements(old_lines)i
    union all
    select (i->>'product_id')::bigint,-(i->>'qty')::numeric from jsonb_array_elements(new_lines)i
   ) amounts group by product_id having sum(qty)<>0
  );$n$);
 definition:=replace(definition,'if before_row.id is null or expense_change or(before_row.total','if renegotiated or expense_change or(before_row.total');
 execute replace(definition,'perform solar_private.assert_system_pricing(after_row.id);',
   'perform solar_private.check_system_material_prices(after_row.id,system_floors,payload->''systemMaterialPriceTokens'',renegotiated);');
end $writer$;

-- Writes by older protected workflows also validate their final bundle. A
-- change only to expenses or a purchase-cost correction keeps its agreed prices.
do $guards$
declare definition text:=pg_get_functiondef('solar_private.guard_system_pricing()'::regprocedure);
begin
 if strpos(definition,'perform solar_private.assert_system_pricing(invoice_id);')=0 or
   strpos(definition,'perform solar_private.assert_system_pricing(old.transaction_id);')=0 then raise exception 'Review deferred system pricing guard';end if;
 definition:=replace(definition,'perform solar_private.assert_system_pricing(invoice_id);',$n$
 if tg_table_name='transactions' then
  perform solar_private.check_system_material_prices(invoice_id,null,null,tg_op='INSERT' or new.total is distinct from old.total);
 else
  if tg_op='UPDATE' and new.cost is distinct from old.cost and
     (new.product_id,new.qty,new.transaction_id) is not distinct from (old.product_id,old.qty,old.transaction_id) and
     exists(select from public.transactions t where t.id=invoice_id and t.kind='system' and
        round(t.cost,2) is distinct from (select round(coalesce(sum(i.qty*i.cost),0),2) from public.transaction_items i where i.transaction_id=t.id)) then
   raise exception 'كلفة مواد المنظومة لا تطابق كلفة الوصل المحفوظة' using errcode='PT422';
  end if;
  perform solar_private.check_system_material_prices(invoice_id,null,null,tg_op in('INSERT','DELETE') or
    (new.product_id,new.qty,new.transaction_id) is distinct from (old.product_id,old.qty,old.transaction_id));
 end if;$n$);
 execute replace(definition,'perform solar_private.assert_system_pricing(old.transaction_id);','perform solar_private.check_system_material_prices(old.transaction_id,null,null,true);');
end $guards$;

create function solar_private.system_material_prices(product_ids bigint[], invoice_id bigint default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare viewer public.profiles; invoice public.transactions; restricted boolean; prices jsonb; items jsonb;
begin
 select * into viewer from public.profiles p where p.id=auth.uid() and p.active and p.user_type not in('warehouse','installer');
 if viewer.id is null or not(viewer.is_admin or solar_private.any_feature(viewer.permissions,'system') or
      (invoice_id is not null and solar_private.receipt_feature(viewer.permissions,'system',false))) then
  raise exception 'لا تملك صلاحية أسعار مواد المنظومات' using errcode='42501';
 end if;
 if product_ids is null or cardinality(product_ids)>500 or coalesce(array_ndims(product_ids),1)<>1 then
  raise exception 'اختر حتى 500 مادة للمنظومة' using errcode='22023';
 end if;
 if array_position(product_ids,null) is not null then
  raise exception 'اختر حتى 500 مادة للمنظومة' using errcode='22023';
 end if;
 if invoice_id is null then
  restricted:=solar_private.viewer_uses_personal_prices();
  prices:=solar_private.wholesale_floor_snapshot(array(
   select distinct n.id from unnest(product_ids)n(id) where solar_private.can_read_global_stock() or exists(
    select from solar_private.warehouse_stocks w where w.product_id=n.id and solar_private.warehouse_access_allowed(viewer.id,w.warehouse_id))
  ));
  select jsonb_agg(jsonb_build_object('productId',v->'productId','priceSource',v->'floorSource','priceToken',v->'floorToken',
   'priceHidden',restricted and v->>'floorSource'='cost','materialPrice',case when not restricted or v->>'floorSource'='configured'
   then v->'effectiveMinPrice' end) order by (v->>'productId')::bigint)
   into items from jsonb_each(prices) q(k,v);
 else
  select * into invoice from public.transactions t where t.id=invoice_id and t.kind='system' and
   (viewer.is_admin or (t.created_by=viewer.id and coalesce(t.cashbox_user_id,t.created_by)=viewer.id)
      or solar_private.assigned_profit_receipt(t.id,viewer.id,false));
  if invoice.id is null then raise exception 'هذا الوصل خارج صلاحيتك' using errcode='42501';end if;
  restricted:=solar_private.personal_archive_priced(invoice_id);
  select s.prices into prices from solar_private.system_receipt_material_prices s where s.invoice_id=system_material_prices.invoice_id;
  with saved as (
   select i.product_id,sum(i.qty*i.cost)/nullif(sum(i.qty),0) historical_cost
   from public.transaction_items i where i.transaction_id=invoice.id and i.product_id=any(product_ids) group by i.product_id
  ), unit_prices as (
   select i.product_id,case when prices is null then 'historical' else prices->i.product_id::text->>'source' end origin,
    case when prices is null then solar_private.personal_line_cost(invoice.id,i.product_id,i.historical_cost) else (prices->i.product_id::text->>'price')::numeric end price,
    case when prices is null then solar_private.personal_line_has_price(invoice.id,i.product_id) else prices->i.product_id::text->>'source'='configured' end configured
   from saved i
  )
  select jsonb_agg(jsonb_build_object('productId',product_id,'priceSource',origin,'priceHidden',restricted and not configured,
     'materialPrice',case when not restricted or configured then price end) order by product_id) into items from unit_prices;
 end if;
 return jsonb_build_object('items',coalesce(items,'[]'::jsonb));
end $$;
create function public.solar_system_material_prices(product_ids bigint[], invoice_id bigint default null)
returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.system_material_prices(product_ids,invoice_id)$$;
revoke all on function solar_private.system_material_prices(bigint[],bigint), public.solar_system_material_prices(bigint[],bigint) from public,anon;
grant execute on function solar_private.system_material_prices(bigint[],bigint), public.solar_system_material_prices(bigint[],bigint) to authenticated;

do $backup$
declare definition text;anchor text;
begin
 definition:=pg_get_functiondef('solar_private.reset_snapshot()'::regprocedure);
 anchor:='''solar_private.personal_price_receipts''';
 if strpos(definition,anchor)=0 then raise exception 'Review reset backup';end if;
 execute replace(definition,anchor,'''solar_private.system_receipt_material_prices'','||anchor);
 definition:=pg_get_functiondef('solar_private.lock_reset_tables()'::regprocedure);
 anchor:='solar_private.personal_price_receipts,solar_private.personal_price_items';
 if strpos(definition,anchor)=0 then raise exception 'Review reset lock';end if;
 execute replace(definition,anchor,'solar_private.system_receipt_material_prices,'||anchor);
end $backup$;
notify pgrst,'reload schema';
