-- Resolve brand labels when reading documents. Financial snapshots, quantities,
-- prices, costs, revision tokens and saved request payloads remain authoritative.
create function solar_private.current_product_brand(material_id bigint,fallback text) returns text
language sql stable security invoker set search_path='' as $$
 select case when m.id is null then fallback else coalesce(b.name,'') end
 from (values(1)) anchor(n) left join public.products m on m.id=material_id left join public.brands b on b.id=m.brand_id
$$;
create function solar_private.current_item_brands(lines jsonb) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
begin
 if jsonb_typeof(lines) is distinct from 'array' then return lines;end if;
 return (select coalesce(jsonb_agg(value||jsonb_build_object('brand',solar_private.current_product_brand((case when value?'productId' then value->>'productId' else value->>'id' end)::bigint,value->>'brand')) order by ordinality),'[]') from jsonb_array_elements(lines) with ordinality);
end$$;
revoke all on function solar_private.current_product_brand(bigint,text),solar_private.current_item_brands(jsonb) from public,anon,authenticated;

-- Guard every narrowly scoped read projection before replacing its brand label.
-- No authorization, money calculation, write statement or concurrency token is changed.
do $$declare patch jsonb;definition text;begin
 for patch in select value from jsonb_array_elements($patches$
[
  {
    "function": "solar_private.cash_movement_detail(text)",
    "old": "'brand',i.brand_name",
    "new": "'brand',solar_private.current_product_brand(i.product_id,i.brand_name)"
  },
  {
    "function": "solar_private.customer_documents(bigint,bigint,date,date,text,text)",
    "old": "'brand',i.brand_name",
    "new": "'brand',solar_private.current_product_brand(i.product_id,i.brand_name)"
  },
  {
    "function": "solar_private.customer_invoice_document(public.transactions)",
    "old": "'brand_name',i.brand_name",
    "new": "'brand_name',solar_private.current_product_brand(i.product_id,i.brand_name)"
  },
  {
    "function": "solar_private.installation_jobs()",
    "old": "'brand',i.brand_name",
    "new": "'brand',solar_private.current_product_brand(i.product_id,i.brand_name)"
  },
  {
    "function": "solar_private.warehouse_orders_v364(text,text,integer)",
    "old": "'brand',i.brand_name",
    "new": "'brand',solar_private.current_product_brand(i.product_id,i.brand_name)"
  },
  {
    "function": "solar_private.warranty_verify(uuid)",
    "old": "'brand',i.brand_name",
    "new": "'brand',solar_private.current_product_brand(i.product_id,i.brand_name)"
  },
  {
    "function": "solar_private.system_payment_context(bigint)",
    "old": "'systems',systems,'token'",
    "new": "'systems',(select coalesce(jsonb_agg(x.value||jsonb_build_object('items',solar_private.current_item_brands(x.value->'items')) order by x.ordinality),'[]') from jsonb_array_elements(systems) with ordinality x(value,ordinality)),'token'"
  },
  {
    "function": "solar_private.payment_history(text,jsonb)",
    "old": "'brand',brand_name",
    "new": "'brand',solar_private.current_product_brand(product_id,brand_name)"
  },
  {
    "function": "solar_private.sales_history(text,text,date,date,text,integer)",
    "old": "to_jsonb(i)",
    "new": "(to_jsonb(i)||jsonb_build_object('brand_name',solar_private.current_product_brand(i.product_id,i.brand_name)))"
  },
  {
    "function": "solar_private.profit_detail(text,uuid)",
    "old": "to_jsonb(i)",
    "new": "(to_jsonb(i)||jsonb_build_object('brand_name',solar_private.current_product_brand(i.product_id,i.brand_name)))"
  },
  {
    "function": "solar_private.fx(text,uuid,jsonb)",
    "old": "to_jsonb(i)",
    "new": "(to_jsonb(i)||jsonb_build_object('brand_name',solar_private.current_product_brand(i.product_id,i.brand_name)))"
  },
  {
    "function": "solar_private.sales_period(text,text,date,date,text)",
    "old": "'brand',coalesce(brand,'')",
    "new": "'brand',solar_private.current_product_brand(product_id,coalesce(brand,''))"
  },
  {
    "function": "solar_private.inventory_movements(bigint,bigint,text,date,date)",
    "old": "i.product_name,i.brand_name,i.category",
    "new": "i.product_name,solar_private.current_product_brand(i.product_id,i.brand_name) brand_name,i.category"
  },
  {
    "function": "solar_private.inventory_movements(bigint,bigint,text,date,date)",
    "old": "line.value->>'brand'",
    "new": "solar_private.current_product_brand((line.value->>'productId')::bigint,line.value->>'brand')"
  },
  {
    "function": "solar_private.warehouse_orders(text,text,integer)",
    "old": "'items',e.lines",
    "new": "'items',solar_private.current_item_brands(e.lines)"
  },
  {
    "function": "solar_private.transfer_json(uuid)",
    "old": "t.items",
    "new": "solar_private.current_item_brands(t.items)"
  },
  {
    "function": "solar_private.warehouse_pricing(text,bigint,text,jsonb,uuid)",
    "old": "'items',items,'token'",
    "new": "'items',solar_private.current_item_brands(items),'token'"
  }
]
$patches$::jsonb) loop
  definition:=pg_get_functiondef((patch->>'function')::regprocedure);
  if strpos(definition,patch->>'old')=0 then raise exception 'Brand display projection contract missing: %',patch->>'function';end if;
  definition:=replace(definition,patch->>'old',patch->>'new');execute definition;
 end loop;
end$$;
notify pgrst,'reload schema';
