-- Both callers start with the redacted, warehouse-scoped personal catalog.
-- Its cost is the active configured price (or null). Resolve a null only for
-- an authorized inventory balance or capital stock statement.
create function solar_private.personal_inventory_balance_prices(catalog_rows jsonb) returns jsonb
language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(
  case when row_data->'personalPriceBasis' is distinct from 'true'::jsonb then row_data
       when row_data->>'cost' is not null then row_data||jsonb_build_object('floorSource','configured')
       else row_data||jsonb_build_object('floorSource','cost','cost',solar_private.current_unit_cost(p.id,p.cost_basis,p.cost))
  end order by position),'[]'::jsonb)
 from jsonb_array_elements(catalog_rows) with ordinality as x(row_data,position)
 join public.products p on p.id=(row_data->>'id')::bigint
$$;
revoke all on function solar_private.personal_inventory_balance_prices(jsonb) from public,anon,authenticated;

do $migration$
declare inventory text:=pg_get_functiondef('solar_private.inventory(text,uuid,jsonb)'::regprocedure);
 capital text:=pg_get_functiondef('solar_private.capital_snapshot(boolean)'::regprocedure);
begin
 if md5(inventory)<>'6e6456f9ae9c6e1fa00b8e95734dc049' or md5(capital)<>'02f735c9c38e03f85e97fae09493858a' then
  raise exception 'Review the inventory and capital projections before enabling prices for balances';
 end if;
 inventory:=replace(inventory,'result:=solar_private.inventory_v350(action,request_id,payload);
  dirs:=',$new$
  if action='stock' and payload->'inventoryMaterialPrices'='true'::jsonb and
     not(person.is_admin or person.user_type='warehouse' or solar_private.any_feature(person.permissions,'stock')) then
   raise exception 'لا تملك صلاحية كشف أرصدة المخازن' using errcode='42501';
  end if;
  result:=solar_private.inventory_v350(action,request_id,payload);
  if action='stock' and payload->'inventoryMaterialPrices'='true'::jsonb and
     result->'showCost'='true'::jsonb and solar_private.viewer_uses_personal_prices() then
   result:=jsonb_set(result,'{products}',solar_private.personal_inventory_balance_prices(result->'products'));
  end if;
  dirs:=$new$);
 capital:=replace(capital,'select coalesce(sum((v->>''bookQty'')',$new$
 if solar_private.viewer_uses_personal_prices() then
  stock:=solar_private.personal_inventory_balance_prices(stock);
 end if;
 select coalesce(sum((v->>'bookQty')$new$);
 execute inventory;
 execute capital;
end $migration$;
