-- Add the sparse per-location quantities to the same SELECT that produces
-- inventory_catalog. A reservation or transfer must never fall between the
-- reader's per-product totals and their warehouse breakdown.
do $migration$
declare definition text; updated text; needle text;
begin
 definition:=pg_get_functiondef('solar_private.inventory_v350(text,uuid,jsonb)'::regprocedure);
 needle:='if action=''catalog'' then return solar_private.inventory_catalog(location);end if;';
 updated:=replace(definition,needle,needle||$gate$
  if action='stock' and payload->'byWarehouse'='true'::jsonb
     and not(person.is_admin or person.user_type='warehouse' or solar_private.any_feature(person.permissions,'stock')) then
   raise exception 'لا تملك صلاحية كشف أرصدة المخازن' using errcode='42501';
  end if;$gate$);
 if updated=definition then raise exception 'Missing inventory stock gate';end if;
 definition:=updated;
 needle:='''canManage'',person.is_admin and person.user_type<>''warehouse'',''showCost'',person.user_type<>''warehouse'');';
 updated:=replace(definition,needle,left(needle,-1)||$balance$
    ||case when action='stock' and payload->'byWarehouse'='true'::jsonb then (
      with allowed as materialized (
       select location_row.id from solar_private.warehouses location_row
       where (location is null or location_row.id=location) and solar_private.warehouse_access_allowed(person.id,location_row.id)
      )
      select jsonb_build_object('warehouseBalances',coalesce(jsonb_agg(jsonb_build_object(
       'warehouseId',s.warehouse_id,'productId',s.product_id,'qty',s.qty,'reservedQty',s.reserved_qty,'bookQty',s.qty+s.reserved_qty)
       order by s.warehouse_id,s.product_id),'[]'::jsonb))
      from allowed allowed_location join solar_private.warehouse_stocks s on s.warehouse_id=allowed_location.id
      where s.qty<>0 or s.reserved_qty<>0
    ) else '{}'::jsonb end;$balance$);
 if updated=definition then raise exception 'Missing inventory catalog result';end if;
 execute updated;
end$migration$;
