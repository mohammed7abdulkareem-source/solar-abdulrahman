-- An empty legacy basis did not record a currency mix. Its IQD fallback is
-- not contradictory historical evidence; all numeric and full-stock replay
-- proofs remain mandatory, and every explicit/nonempty basis stays strict.
do $$declare definition text;needle text;begin
 definition:=pg_get_functiondef('solar_private.purchase_correction_plan(jsonb,boolean)'::regprocedure);
 if md5(definition)<>'e1f91807d492207d875a31069ac7b19f'then raise exception 'Purchase correction plan changed before legacy basis compatibility';end if;
 needle:=$old$    or abs((old_state->'parts'->>'usd')::numeric-(solar_private.inventory_currency_parts(item.product_id,item.cost_basis,coalesce((item.cost_basis->>'bookUnitCost')::numeric,item.cost))->>'usd')::numeric)>.000001
    or abs((old_state->'parts'->>'iqd')::numeric-(solar_private.inventory_currency_parts(item.product_id,item.cost_basis,coalesce((item.cost_basis->>'bookUnitCost')::numeric,item.cost))->>'iqd')::numeric)>.000001 then$old$;
 if strpos(definition,needle)=0 then raise exception 'Purchase line currency proof contract changed';end if;
 execute replace(definition,needle,$new$    or(item.cost_basis is distinct from '{}'::jsonb and(
     abs((old_state->'parts'->>'usd')::numeric-(solar_private.inventory_currency_parts(item.product_id,item.cost_basis,coalesce((item.cost_basis->>'bookUnitCost')::numeric,item.cost))->>'usd')::numeric)>.000001
     or abs((old_state->'parts'->>'iqd')::numeric-(solar_private.inventory_currency_parts(item.product_id,item.cost_basis,coalesce((item.cost_basis->>'bookUnitCost')::numeric,item.cost))->>'iqd')::numeric)>.000001))then$new$);
end$$;
notify pgrst,'reload schema';
