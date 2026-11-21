\set ON_ERROR_STOP on
begin;
create function pg_temp.price_actor(n int) returns uuid language sql immutable as $$
 select ('00000000-0000-0000-0000-'||lpad((412800+n)::text,12,'0'))::uuid
$$;
insert into public.profiles(id,display_name,is_admin,active,user_type,permissions) values
 (pg_temp.price_actor(1),'مدير المخزون',true,true,'admin_staff','{}'),
 (pg_temp.price_actor(2),'موظف المخزون',false,true,'admin_staff','{"stock":true,"wholesalePricingManage":true}'),
 (pg_temp.price_actor(3),'موظف المخزون الشخصي',false,true,'admin_staff','{"stock":true,"profitUsesWholesalePrice":true}'),
 (pg_temp.price_actor(4),'بائع',false,true,'admin_staff','{"sale":true}'),
 (pg_temp.price_actor(5),'مسؤول المخزن',true,true,'warehouse','{"stock":true}'),
 (pg_temp.price_actor(6),'مهندس',true,true,'installer','{"stock":true}'),
 (pg_temp.price_actor(7),'مدير متوقف',true,false,'admin','{}');
insert into solar_private.warehouses(id,name,code) overriding system value values
 (-412801,'رصيد أسعار أ','P28-A'),(-412802,'رصيد أسعار ب','P28-B');
insert into public.products(id,code,name,qty,cost,cost_basis) values
 (-412801,'P28-A','سعر بيع محدد',0,317,'{}'),
 (-412802,'P28-B','كلفة بعملتين',0,600,'{"currencyComponents":{"usd":0.625,"iqd":25.123456}}'),
 (-412803,'P28-C','مادة بلا سعر محدد',0,40,'{}'),
 (-412804,'P28-D','مادة بكلفة صفرية',0,0,'{}');
insert into solar_private.wholesale_product_prices(product_id,enabled,minimum_price) values
 (-412801,true,299.99),(-412802,false,1500);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty,reserved_qty) values
 (-412801,-412801,8,1),(-412802,-412801,9,2),(-412801,-412802,3,2);
update solar_private.exchange_settings set rate=1200,revision=revision+1 where id;
create function pg_temp.report_row(rows jsonb,product bigint) returns jsonb language sql as $$
 select v from jsonb_array_elements(rows)v where (v->>'id')::bigint=product
$$;
set local role authenticated;
do $checks$
declare payload jsonb; original jsonb; result jsonb; rows_original jsonb; id int;
begin
 perform set_config('request.jwt.claim.sub',pg_temp.price_actor(1)::text,true);
 foreach payload in array array['{}'::jsonb,'{"byWarehouse":true,"inventoryMaterialPrices":true}'::jsonb,
  '{"warehouseId":-412801,"byWarehouse":true}'::jsonb] loop
  original:=public.solar_inventory('stock',null,payload);
  result:=public.solar_inventory('stock',null,payload||'{"adminSalePrices":true}');
  assert public.solar_inventory('stock',null,payload||'{"adminSalePrices":false}')=original;
  assert not exists(select 1 from jsonb_array_elements(original->'products')v where v?|array['salePrice','salePriceSource']);
  select coalesce(jsonb_agg(v-'salePrice'-'salePriceSource' order by n),'[]') into rows_original
   from jsonb_array_elements(result->'products') with ordinality as t(v,n);
  assert jsonb_set(result,'{products}',rows_original)=original;
  assert pg_temp.report_row(result->'products',-412801)@>'{"cost":317,"salePrice":299.99,"salePriceSource":"configured"}';
  assert pg_temp.report_row(result->'products',-412802)@>'{"cost":775.123456,"salePrice":775.123456,"salePriceSource":"cost"}';
  assert pg_temp.report_row(result->'products',-412803)@>'{"cost":40,"salePrice":40,"salePriceSource":"cost"}';
  assert pg_temp.report_row(result->'products',-412804)@>'{"cost":0,"salePrice":0,"salePriceSource":"cost"}';
 end loop;
 assert pg_temp.report_row(result->'products',-412801)@>'{"qty":8,"bookQty":9}';
 assert not exists(select 1 from jsonb_array_elements(public.solar_inventory('catalog',null,'{"adminSalePrices":true}'))v where v?'salePrice');
 assert not exists(select 1 from jsonb_array_elements(public.solar_capital_current_snapshot()#>'{stock,rows}')v where v?'salePrice');
 for id in 2..7 loop
  perform set_config('request.jwt.claim.sub',pg_temp.price_actor(id)::text,true);
  begin perform public.solar_inventory('stock',null,'{"adminSalePrices":true,"isAdmin":true}');
   raise exception 'Unauthorized administrator selling prices for fixture %',id;exception when insufficient_privilege then null;end;
 end loop;
end$checks$;
reset role;
update solar_private.exchange_settings set rate=1500,revision=revision+1 where id;
set local role authenticated;
do $checks$
declare rows jsonb;
begin
 perform set_config('request.jwt.claim.sub',pg_temp.price_actor(1)::text,true);
 rows:=public.solar_inventory('stock',null,'{"adminSalePrices":true}')->'products';
 assert pg_temp.report_row(rows,-412802)@>'{"cost":962.623456,"salePrice":962.623456,"salePriceSource":"cost"}';
 assert pg_temp.report_row(rows,-412801)@>'{"cost":317,"salePrice":299.99,"salePriceSource":"configured"}';
end$checks$;
rollback;
