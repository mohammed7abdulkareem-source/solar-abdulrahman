-- The wholesale manager's shared state keeps its existing cost projection.
-- A sale-authorized office issuer can request the approved material price
-- when composing an invoice. Only automatic prices previously withheld from
-- this seller need resolving. Both reads use the same statement snapshot.
create function solar_private.wholesale_sale_price_state() returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare
 viewer uuid:=auth.uid();
 state jsonb;
 prices jsonb;
begin
 if not exists(select from public.profiles p where p.id=viewer and p.active
   and p.user_type not in ('warehouse','installer') and (p.is_admin or solar_private.any_feature(p.permissions,'sale'))) then
  raise exception 'عرض سعر المادة في فاتورة الجملة يتطلب صلاحية البيع' using errcode='42501';
 end if;
 state:=solar_private.wholesale_pricing_state();
 if not solar_private.viewer_uses_personal_prices() then return state;end if;
 select coalesce(jsonb_agg(case when m.id is not null then
   row_data||jsonb_build_object('effectiveMinPrice',solar_private.current_unit_cost(m.id,m.cost_basis,m.cost))
   else row_data end order by position),'[]'::jsonb)
 into prices
 from jsonb_array_elements(state->'products') with ordinality as catalog(row_data,position)
 left join public.products m on m.id=(row_data->>'id')::bigint and row_data->>'floorSource'='cost'
  and ((select solar_private.can_read_global_stock()) or exists(
   select from solar_private.warehouse_stocks w where w.product_id=m.id and solar_private.warehouse_access_allowed(viewer,w.warehouse_id)));
 return jsonb_set(state,'{products}',prices);
end$$;
revoke all on function solar_private.wholesale_sale_price_state() from public,anon,authenticated;

do $patch$
declare
 wholesale_definition text:=pg_get_functiondef('solar_private.wholesale_pricing(text,uuid,jsonb)'::regprocedure);
 system_definition text:=pg_get_functiondef('solar_private.system_material_prices(bigint[],bigint)'::regprocedure);
 state_read constant text:=$old$if action='state'then
  result:=solar_private.wholesale_pricing_state();$old$;
 live_personal constant text:=$old$if invoice_id is null then
  restricted:=solar_private.viewer_uses_personal_prices();$old$;
 live_price constant text:=$old$'priceHidden',restricted and v->>'floorSource'='cost','materialPrice',case when not restricted or v->>'floorSource'='configured'
   then v->'effectiveMinPrice' end$old$;
begin
 if array_length(string_to_array(wholesale_definition,state_read),1) is distinct from 2 or
    array_length(string_to_array(system_definition,live_personal),1) is distinct from 2 or
    array_length(string_to_array(system_definition,live_price),1) is distinct from 2 then
  raise exception 'Review the live wholesale and system material price projections';
 end if;
 execute replace(wholesale_definition,state_read,$new$if action='state'then
  result:=case when payload->'saleMaterialPrices'='true'::jsonb then solar_private.wholesale_sale_price_state()
   else solar_private.wholesale_pricing_state() end;$new$);
 -- A system invoice id selects the signed receipt branch. Its access check,
 -- saved prices, and historical disclosure policy are untouched.
 system_definition:=replace(system_definition,live_personal,'if invoice_id is null then');
 execute replace(system_definition,live_price,$new$'priceHidden',false,'materialPrice',v->'effectiveMinPrice'$new$);
end $patch$;
