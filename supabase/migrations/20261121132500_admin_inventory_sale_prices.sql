-- Add selling prices to an explicitly requested office administrator stock
-- report. The scoped catalog already contains the live IQD acquisition cost
-- for this role. Keep that independent figure even for configured prices.
do $migration$
declare
 definition text:=pg_get_functiondef('solar_private.inventory(text,uuid,jsonb)'::regprocedure);
 stock_read constant text:=$old$result:=solar_private.inventory_v350(action,request_id,payload);
  if action='stock' and payload->'inventoryMaterialPrices'=$old$;
begin
 if md5(definition)<>'70162d2d535ad1b6034f19ea5237fd97' then
  raise exception 'Review inventory read permissions before adding administrator selling prices';
 end if;
 definition:=replace(definition,stock_read,$new$
  if action='stock' and payload->'adminSalePrices'='true'::jsonb and
     (person.is_admin is not true or person.user_type in('warehouse','installer')) then
   raise exception 'عرض أسعار البيع في كشف المخزون متاح للأدمن فقط' using errcode='42501';
  end if;
  result:=solar_private.inventory_v350(action,request_id,payload);
  if action='stock' and payload->'adminSalePrices'='true'::jsonb then
   result:=jsonb_set(result,'{products}',(
    select coalesce(jsonb_agg(item||jsonb_build_object(
     'salePrice',coalesce(price.minimum_price,(item->>'cost')::numeric),
     'salePriceSource',case when price.product_id is null then 'cost' else 'configured' end
    ) order by position),'[]'::jsonb)
    from jsonb_array_elements(result->'products') with ordinality as rows(item,position)
    left join solar_private.wholesale_product_prices price on price.product_id=(item->>'id')::bigint
     and price.enabled and price.minimum_price>0
   ));
  end if;
  if action='stock' and payload->'inventoryMaterialPrices'=$new$);
 execute definition;
end $migration$;
