-- Resolve identities only for sale lines already returned to this caller by
-- the warehouse ledger. Filtering afterwards preserves every running balance.
create function solar_private.inventory_customer_movements(action text,payload jsonb)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
 material bigint:=nullif(payload->>'productId','')::bigint;
 location bigint:=nullif(payload->>'warehouseId','')::bigint;
 first_day date:=nullif(payload->>'from','')::date;
 last_day date:=nullif(payload->>'to','')::date;
 selected text:=payload->>'customerKey';
 history jsonb; result jsonb;
begin
 if jsonb_typeof(payload) is distinct from 'object' or material is null or first_day>last_day
   or action not in ('movement_customers','movements') then
  raise exception 'اختر المادة والفترة الصحيحة' using errcode='22023';
 end if;
 if action='movements' and (selected is null or selected !~ '^customer:-?[0-9]{1,19}$') then
  raise exception 'اختر عميلاً من قائمة حركة المادة' using errcode='22023';
 end if;
 history:=solar_private.inventory_movements(location,material,'',first_day,last_day);

 with visible as (
  select item.id line_id,item.transaction_id,x.row_data,x.seq
  from jsonb_array_elements(history) with ordinality x(row_data,seq)
  join public.transaction_items item on item.id=case when x.row_data->>'id' ~ '^line:-?[0-9]+$'
    then substr(x.row_data->>'id',6)::bigint end
  where x.row_data->>'kind' in('sale','system') and item.product_id=material
 ), resolved as materialized (
  select 'customer:'||c.id as customer_key,c.id,
   case when solar_private.role_name()='admin' or c.owner_id=auth.uid() then c.name end directory_name,
   nullif(btrim(v.row_data->>'party'),'') receipt_name,v.row_data,v.seq
  from visible v join solar_private.customer_movement_links() link on link.transaction_id=v.transaction_id
  join public.customers c on c.id=link.customer_id
 ), options as (
  select distinct on (r.id) r.id,r.customer_key,
   coalesce(r.directory_name,r.receipt_name,'عميل رقم '||r.id) customer_name
  from resolved r
  order by r.id,r.receipt_name is null,r.seq desc
 )
 select case when action='movement_customers' then (
  select coalesce(jsonb_agg(jsonb_build_object('key',o.customer_key,'name',o.customer_name,'hint','رقم العميل '||o.id)
   order by o.customer_name,o.id),'[]'::jsonb) from options o
 ) else (
  select coalesce(jsonb_agg(r.row_data||jsonb_build_object('customerKey',r.customer_key) order by r.seq),'[]'::jsonb)
  from resolved r where r.customer_key=selected
 ) end into result;
 return result;
end$$;
revoke all on function solar_private.inventory_customer_movements(text,jsonb) from public,anon,authenticated;

-- The inventory router has already validated the active user and feature scope.
-- Older movement requests still use the original dispatch and response shape.
do $patch$
declare
 original text:=pg_get_functiondef('solar_private.inventory(text,uuid,jsonb)'::regprocedure);
 anchor text:=' if action=''material_report''then return solar_private.material_movement_report(payload);end if;';
begin
 if strpos(original,anchor)=0 then raise exception 'Review material report routing before adding customer selections';end if;
 execute replace(original,anchor,$route$ if action='movement_customers' or (action='movements' and payload ? 'customerKey') then
  return solar_private.inventory_customer_movements(action,payload);
 end if;
$route$||anchor);
end$patch$;
notify pgrst,'reload schema';
