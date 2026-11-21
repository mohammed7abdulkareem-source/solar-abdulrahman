\set ON_ERROR_STOP on
begin;
create function pg_temp.balance_user(n int) returns uuid language sql immutable as $$
 select ('00000000-0000-0000-0000-'||lpad((412700+n)::text,12,'0'))::uuid
$$;
insert into public.profiles(id,display_name,is_admin,active,user_type,permissions) values
 (pg_temp.balance_user(1),'رصيد المخزون',false,true,'admin_staff','{"stock":true,"sale":true,"capital":true,"profitUsesWholesalePrice":true}'),
 (pg_temp.balance_user(2),'بائع',false,true,'admin_staff','{"sale":true,"profitUsesWholesalePrice":true}'),
 (pg_temp.balance_user(3),'أمين المخزن',false,true,'warehouse','{"stock":true,"profitUsesWholesalePrice":true}'),
 (pg_temp.balance_user(4),'إدارة',true,true,'admin','{}'),
 (pg_temp.balance_user(5),'رأس المال',false,true,'admin_staff','{"capital":true,"profitUsesWholesalePrice":true}');
insert into solar_private.warehouses(id,name,code) overriding system value values
 (-412701,'رصيد أ','P27-A'),(-412702,'رصيد ب','P27-B'),(-412703,'رصيد ج','P27-C');
insert into solar_private.warehouse_access(user_id,warehouse_ids)
 select pg_temp.balance_user(i),array[-412701,-412702]::bigint[] from unnest(array[1,3,5])i;
insert into public.products(id,code,name,qty,cost,cost_basis) values
 (-412701,'P27-manual','مادة محددة',0,317,'{}'),
 (-412702,'P27-fx','مادة بسعر الصرف',0,500,'{"currencyComponents":{"usd":0.6,"iqd":1}}'),
 (-412703,'P27-legacy','مادة بكلفة قديمة',0,700,'{}'),
 (-412704,'P27-zero','مادة بلا كلفة',0,0,'{}');
insert into solar_private.wholesale_product_prices(product_id,enabled,minimum_price) values
 (-412701,true,300),(-412702,false,9999);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty,reserved_qty) values
 (-412701,-412701,2,0),(-412702,-412701,1,1),(-412701,-412702,3,2),(-412702,-412703,1,0),
 (-412703,-412701,99,0);
update solar_private.exchange_settings set rate=1200,revision=revision+1 where id;
create function pg_temp.stock_row(rows jsonb,product bigint) returns jsonb language sql as $$
 select v from jsonb_array_elements(rows)v where (v->>'id')::bigint=product
$$;
set local role authenticated;
do $checks$
declare result jsonb; plain jsonb; row_data jsonb; capital jsonb; snapshot jsonb; capital_user int; payload jsonb;
begin
 perform set_config('request.jwt.claim.sub',pg_temp.balance_user(1)::text,true);
 result:=public.solar_inventory('stock',null,'{"inventoryMaterialPrices":true}');
 foreach payload in array array['{}'::jsonb,'{"byWarehouse":true}'::jsonb,'{"warehouseId":-412701}'::jsonb] loop
  snapshot:=public.solar_inventory('stock',null,payload||'{"inventoryMaterialPrices":true}');
  assert pg_temp.stock_row(snapshot->'products',-412701)@>'{"cost":300,"floorSource":"configured","personalPriceBasis":true}';
  assert pg_temp.stock_row(snapshot->'products',-412702)@>'{"cost":721,"floorSource":"cost"}';
  assert pg_temp.stock_row(snapshot->'products',-412703)@>'{"cost":700,"floorSource":"cost"}';
  assert pg_temp.stock_row(snapshot->'products',-412704)@>'{"cost":0,"floorSource":"cost"}';
  assert not exists(select 1 from jsonb_array_elements(snapshot->'products')v where v?|array['bookCost','cost_basis','currencyComponents','valuationUnitCost']);
 end loop;
 assert pg_temp.stock_row(result->'products',-412701)@>'{"qty":3,"reservedQty":1,"bookQty":4}';
 assert pg_temp.stock_row(snapshot->'products',-412701)@>'{"qty":2,"reservedQty":0}';
 begin perform public.solar_inventory('stock',null,'{"warehouseId":-412703,"inventoryMaterialPrices":true}');raise exception 'Foreign location accepted';
 exception when insufficient_privilege then null;end;
 plain:=public.solar_inventory('stock');
 assert pg_temp.stock_row(plain->'products',-412702)->>'cost' is null;
 assert pg_temp.stock_row(public.solar_inventory('catalog'),-412702)->>'cost' is null;
 assert pg_temp.stock_row(public.solar_wholesale_pricing('state')->'products',-412702)->>'effectiveMinPrice' is null;
 for capital_user in select n from unnest(array[1,5])n loop
  perform set_config('request.jwt.claim.sub',pg_temp.balance_user(capital_user)::text,true);
  foreach capital in array array[public.solar_capital_snapshot(),public.solar_capital_current_snapshot()] loop
   assert (capital#>>'{stock,value}')::numeric=5505;
   assert pg_temp.stock_row(capital#>'{stock,rows}',-412702)@>'{"cost":721,"floorSource":"cost","bookQty":5}';
   assert pg_temp.stock_row(capital#>'{stock,rows}',-412701)@>'{"cost":300,"bookQty":4}';
   assert not exists(select 1 from jsonb_array_elements(capital#>'{stock,rows}')v where v?|array['bookCost','cost_basis']);
  end loop;
 end loop;
 perform set_config('request.jwt.claim.sub',pg_temp.balance_user(2)::text,true);
 begin perform public.solar_inventory('stock',null,'{"inventoryMaterialPrices":true}');raise exception 'Sale-only price read';
 exception when insufficient_privilege then null;end;
 assert pg_temp.stock_row(public.solar_inventory('stock')->'products',-412702)->>'cost' is null;
 begin perform public.solar_capital_current_snapshot();raise exception 'Sale-only capital read';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',pg_temp.balance_user(3)::text,true);
 result:=public.solar_inventory('stock',null,'{"inventoryMaterialPrices":true}');
 assert result->'showCost'='false'::jsonb and not(pg_temp.stock_row(result->'products',-412702)?|array['cost','floorSource','bookCost','cost_basis']);
 perform set_config('request.jwt.claim.sub',pg_temp.balance_user(4)::text,true);
 assert pg_temp.stock_row(public.solar_inventory('stock',null,'{"inventoryMaterialPrices":true}')->'products',-412701)@>'{"cost":317}';
 assert pg_temp.stock_row(public.solar_capital_current_snapshot()#>'{stock,rows}',-412702)@>'{"cost":500}';
 assert not has_function_privilege('authenticated','solar_private.personal_inventory_balance_prices(jsonb)','execute');
end$checks$;
reset role;
update solar_private.exchange_settings set rate=1500,revision=revision+1 where id;
set local role authenticated;
do $checks$
declare products jsonb;
begin
 perform set_config('request.jwt.claim.sub',pg_temp.balance_user(1)::text,true);
 products:=public.solar_inventory('stock',null,'{"inventoryMaterialPrices":true}')->'products';
 assert pg_temp.stock_row(products,-412702)@>'{"cost":901,"floorSource":"cost"}';
 assert pg_temp.stock_row(products,-412701)@>'{"cost":300,"floorSource":"configured"}';
 assert (public.solar_capital_current_snapshot()#>>'{stock,value}')::numeric=6405;
end$checks$;
rollback;
