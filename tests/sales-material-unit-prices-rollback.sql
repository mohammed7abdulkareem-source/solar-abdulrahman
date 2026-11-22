\set ON_ERROR_STOP on
begin;
create function pg_temp.price_user(n int) returns uuid language sql immutable as $$
 select ('00000000-0000-0000-0000-'||lpad((413000+n)::text,12,'0'))::uuid
$$;
insert into public.profiles(id,display_name,is_admin,active,user_type,permissions) values
 (pg_temp.price_user(1),'موظف البيع',false,true,'admin_staff','{"sale":true,"system":true,"profitUsesWholesalePrice":true}'),
 (pg_temp.price_user(2),'إدارة الأسعار فقط',false,true,'admin_staff','{"wholesalePricingManage":true,"profitUsesWholesalePrice":true}'),
 (pg_temp.price_user(3),'التحصيل فقط',false,true,'admin_staff','{"tahseel":true}'),
 (pg_temp.price_user(4),'المخزن',true,true,'warehouse','{}'),
 (pg_temp.price_user(5),'التنصيب',true,true,'installer','{}'),
 (pg_temp.price_user(6),'مدير غير فعال',true,false,'admin','{}');
insert into solar_private.warehouses(id,name,code) overriding system value values
 (-413001,'مخزن البيع للتجربة','SELL30-A'),(-413002,'مخزن خارجي للتجربة','SELL30-B');
insert into solar_private.warehouse_access(user_id,warehouse_ids) values(pg_temp.price_user(1),array[-413001]::bigint[]);
insert into public.products(id,code,name,qty,cost,cost_basis) values
 (-413001,'SELL30C','سعر جملة معتمد',0,900,'{}'),
 (-413002,'SELL30F','سعر متغير',0,700,'{"currencyComponents":{"usd":0.35,"iqd":0.004567}}'),
 (-413003,'SELL30Z','سعر صفري',0,0,'{}'),(-413004,'SELL30X','مادة خارج المخزن',0,421,'{}');
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values
 (-413001,-413001,12),(-413001,-413002,6),(-413001,-413003,0),(-413002,-413004,3);
insert into solar_private.wholesale_product_prices(product_id,minimum_price,enabled) values(-413001,650,true),(-413002,5500,false);
update solar_private.exchange_settings set rate=1500,revision=revision+1 where id;
update solar_private.wholesale_pricing_control set enabled=false,scope_mode='all',scope_configured=true where id;
update solar_private.operation_controls set system_free_pricing=true where id;
create function pg_temp.wh_row(state jsonb,pid bigint) returns jsonb language sql as $$
 select v from jsonb_array_elements(state->'products')v where (v->>'id')::bigint=pid
$$;
create function pg_temp.sys_row(state jsonb,pid bigint) returns jsonb language sql as $$
 select v from jsonb_array_elements(state->'items')v where (v->>'productId')::bigint=pid
$$;
set local role authenticated;
do $test$
declare plain jsonb; sale jsonb; system_prices jsonb; person int; aut jsonb; manual jsonb;
begin
 perform set_config('request.jwt.claim.sub',pg_temp.price_user(1)::text,true);
 plain:=public.solar_wholesale_pricing('state');
 sale:=public.solar_wholesale_pricing('state',null,'{"saleMaterialPrices":true}');
 assert sale->'effectiveEnforced'='false'::jsonb and sale-'products'=plain-'products';
 aut:=pg_temp.wh_row(sale,-413002);
 manual:=pg_temp.wh_row(sale,-413001);
 assert manual@>'{"effectiveMinPrice":650,"floorSource":"configured","cost":650}';
 assert aut@>'{"effectiveMinPrice":525.004567,"floorSource":"cost","cost":null}';
 assert aut-'effectiveMinPrice'=pg_temp.wh_row(plain,-413002)-'effectiveMinPrice';
 assert pg_temp.wh_row(plain,-413002)->'effectiveMinPrice'='null'::jsonb;
 assert pg_temp.wh_row(sale,-413003)@>'{"effectiveMinPrice":0,"cost":null}';
 assert pg_temp.wh_row(sale,-413004)->>'effectiveMinPrice' is null;
 assert not exists(select 1 from jsonb_array_elements(sale->'products')v where v?|array['cost_basis','bookCost','valuationUnitCost','currencyComponents']);
 assert not exists(select 1 from public.products where id between -413004 and -413001);
 system_prices:=public.solar_system_material_prices(array[-413001,-413002,-413003,-413004]);
 assert pg_temp.sys_row(system_prices,-413001)@>'{"materialPrice":650,"priceSource":"configured","priceHidden":false}';
 assert pg_temp.sys_row(system_prices,-413002)@>'{"materialPrice":525.004567,"priceSource":"cost","priceHidden":false}';
 assert pg_temp.sys_row(system_prices,-413003)@>'{"materialPrice":0,"priceHidden":false}';
 assert pg_temp.sys_row(system_prices,-413004) is null;
 assert pg_temp.sys_row(system_prices,-413002)->>'priceToken'=aut->>'floorToken';
 perform set_config('test.sales_material_price_token',aut->>'floorToken',true);
 for person in 2..6 loop
  perform set_config('request.jwt.claim.sub',pg_temp.price_user(person)::text,true);
  begin perform public.solar_wholesale_pricing('state',null,'{"saleMaterialPrices":true}');raise exception 'Wholesale sale price privilege extended to %',person;
  exception when insufficient_privilege then null;end;
  begin perform public.solar_system_material_prices(array[-413002]);raise exception 'System price privilege extended to %',person;
  exception when insufficient_privilege then null;end;
 end loop;
end$test$;
reset role;
update solar_private.exchange_settings set rate=1400,revision=revision+1 where id;
update solar_private.wholesale_pricing_control set enabled=true,revision=revision+1 where id;
update solar_private.operation_controls set system_free_pricing=false where id;
set local role authenticated;
do $test$
declare sale jsonb; aut jsonb;
begin
 perform set_config('request.jwt.claim.sub',pg_temp.price_user(1)::text,true);
 sale:=public.solar_wholesale_pricing('state',null,'{"saleMaterialPrices":true}');
 assert sale->'effectiveEnforced'='true'::jsonb;
 aut:=pg_temp.wh_row(sale,-413002);
 assert aut@>'{"effectiveMinPrice":490.004567,"cost":null}' and aut->>'floorToken'<>current_setting('test.sales_material_price_token');
 assert (pg_temp.wh_row(sale,-413001)->>'effectiveMinPrice')::numeric=650;
 assert public.solar_system_material_prices(array[-413002])#>'{items,0,materialPrice}'='490.004567'::jsonb;
end$test$;
rollback;
