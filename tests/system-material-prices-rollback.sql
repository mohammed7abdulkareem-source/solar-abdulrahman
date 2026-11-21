-- Exercise the ordinary issuer, manager, employee with price masking, installer,
-- and previous-release receipt paths without retaining any fixture writes.
\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,username,display_name,user_type,permissions,is_admin,phone) values
 ('00000000-0000-0000-0000-000000412651','sysmaterial_admin','مدير السعر','admin_staff','{}',true,'07700000000'),
 ('00000000-0000-0000-0000-000000412652','sysmaterial_owner','بائع منظومات','admin_staff','{"system":true,"installations":true}',false,'07700000000'),
 ('00000000-0000-0000-0000-000000412653','sysmaterial_field','مهندس','installer','{}',false,'07700000000'),
 ('00000000-0000-0000-0000-000000412654','sysmaterial_other','بائع آخر','admin_staff','{"system":true}',false,'07700000000');
insert into public.customers(id,name,owner_id,customer_type) values(-412651,'زبون مادة المنظومة','00000000-0000-0000-0000-000000412652','system');
insert into public.products(id,code,name,cost,qty) values(-412651,'SM-A','مادة يدوية',300,500),(-412652,'SM-B','مادة تلقائية',100,500);
insert into solar_private.wholesale_product_prices(product_id,minimum_price,enabled) values(-412651,500,true),(-412652,800,false);
update solar_private.operation_controls set system_free_pricing=false,system_markup_percent=25 where id;
create function pg_temp.system_invoice(amount numeric,id bigint default null) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('kind','system','mode','credit','warehouseId',1,'installerId','00000000-0000-0000-0000-000000412653','customerAddress','عنوان تجريبي','partyId',-412651,
 'party','زبون مادة المنظومة','items','[{"id":-412651,"qty":1,"price":0},{"id":-412652,"qty":1,"price":0}]'::jsonb,'total',amount)||
 case when $2 is null then '{}'::jsonb else (select jsonb_build_object('invoiceId',t.id,'expectedRevision',t.pricing_revision,'expectedInstallationRevision',t.installation_revision) from public.transactions t where t.id=$2) end
$$;
create function pg_temp.install_revision(id bigint) returns bigint language sql stable security definer set search_path='' as $$
 select t.installation_revision from public.transactions t where t.id=$1
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412652',true);
do $$declare q jsonb; price_tokens jsonb; key uuid:=gen_random_uuid(); cmd jsonb; answer jsonb;begin
 q:=public.solar_system_material_prices(array[-412651,-412652]);
 assert exists(select from jsonb_array_elements(q->'items')x where x->>'productId'='-412651' and x->>'priceSource'='configured' and (x->>'materialPrice')::numeric=500);
 assert exists(select from jsonb_array_elements(q->'items')x where x->>'productId'='-412652' and x->>'priceSource'='cost' and (x->>'materialPrice')::numeric=100);
 select jsonb_object_agg(x->>'productId',x->'priceToken') into price_tokens from jsonb_array_elements(q->'items')x;
 cmd:=pg_temp.system_invoice(750)||jsonb_build_object('systemMaterialPriceTokens',price_tokens);
 begin perform public.solar_invoice_save(gen_random_uuid(),cmd||'{"total":749.99}');raise exception 'system floor failed';exception when sqlstate 'PT422' then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),jsonb_set(cmd,'{systemMaterialPriceTokens,-412652}','"stale"'));raise exception 'stale quote accepted';exception when sqlstate 'PT409' then null;end;
 answer:=public.solar_invoice_save(key,cmd);
 assert (answer->>'cost')::numeric=400 and (answer->>'profit')::numeric=350,'company/personal accounting mutated';
 assert public.solar_invoice_save(key,cmd)=answer;
 perform set_config('test.system_material_id',answer->>'id',true);
 perform set_config('test.original_tokens',price_tokens::text,true);
end $$;
reset role;
set constraints all immediate;
set constraints all deferred;
update solar_private.wholesale_product_prices set minimum_price=720 where product_id=-412651;
insert into solar_private.warehouse_access(user_id,all_warehouses,warehouse_ids)
 values('00000000-0000-0000-0000-000000412654',false,'{}') on conflict(user_id) do update set all_warehouses=false,warehouse_ids='{}';
insert into solar_private.customer_receipt_responsibility(transaction_id,customer_id,owner_id,assigned_by,request_id)
 values(current_setting('test.system_material_id')::bigint,-412651,'00000000-0000-0000-0000-000000412654','00000000-0000-0000-0000-000000412651',gen_random_uuid());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412654',true);
do $$begin
 assert public.solar_system_material_prices(array[-412651,-412652])->'items'='[]'::jsonb,'prices outside assigned warehouses';
 begin perform public.solar_system_material_prices(array[-412651],current_setting('test.system_material_id')::bigint);raise exception 'warehouse or operational assignment alone exposed prices';exception when insufficient_privilege then null;end;
end $$;
reset role;
delete from solar_private.customer_receipt_responsibility where transaction_id=current_setting('test.system_material_id')::bigint;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412652',true);
do $$declare id bigint:=current_setting('test.system_material_id')::bigint;q jsonb;begin
 q:=public.solar_system_material_prices(array[-412651],id);
 assert(q#>>'{items,0,materialPrice}')::numeric=500 and not(q#>'{items,0}'?'priceToken');
 assert(public.solar_system_material_prices(array[-412651])#>>'{items,0,materialPrice}')::numeric=720;
 perform public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(750,id)||'{"notes":"ملاحظة جديدة"}');
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(900,id));raise exception 'negotiated price reused old floor';exception when sqlstate 'PT422' then null;end;
 perform public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(1025,id));
 assert(public.solar_system_material_prices(array[-412651],id)#>>'{items,0,materialPrice}')::numeric=720;
end $$;
reset role;
set constraints all immediate;
set constraints all deferred;
update public.profiles set permissions=permissions||'{"profitUsesWholesalePrice":true}'::jsonb where id='00000000-0000-0000-0000-000000412652';
set local role authenticated;
do $$declare id bigint:=current_setting('test.system_material_id')::bigint;q jsonb;begin
 q:=public.solar_system_material_prices(array[-412652],id);
 assert(q#>>'{items,0,priceHidden}')::boolean and q#>'{items,0,materialPrice}'='null'::jsonb;
 q:=public.solar_system_material_prices(array[-412652]);
 assert(q#>>'{items,0,priceHidden}')::boolean and q#>'{items,0,materialPrice}'='null'::jsonb and length(q#>>'{items,0,priceToken}')>=32;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(750));raise exception 'private floor ignored';exception when sqlstate 'PT422' then assert sqlerrm!~'[0-9]','automatic cost disclosed';end;
end $$;
reset role;
-- Emulate the exact prior receipt state, after draining every original trigger.
-- Its payment, costs, rows and pricing revision remain those produced by the
-- real invoice writer. There was no material snapshot before this release.
delete from solar_private.system_receipt_material_prices where invoice_id=current_setting('test.system_material_id')::bigint;
update solar_private.wholesale_product_prices set minimum_price=2200 where product_id=-412651;
update public.profiles set permissions=permissions-'profitUsesWholesalePrice' where id='00000000-0000-0000-0000-000000412652';
set local role authenticated;
do $$declare id bigint:=current_setting('test.system_material_id')::bigint;begin
 perform public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(1025,id)||'{"notes":"ملاحظة لوصل سابق"}');
 assert(public.solar_system_material_prices(array[-412651],id)#>>'{items,0,materialPrice}')::numeric=300;
end $$;
reset role;
update public.transactions set warehouse_status='ready' where id=current_setting('test.system_material_id')::bigint;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412653',true);
do $$declare id bigint:=current_setting('test.system_material_id')::bigint;begin
 begin perform public.solar_system_material_prices(array[-412651]);raise exception 'installer priced materials';exception when insufficient_privilege then null;end;
 perform public.solar_installation_action(id,pg_temp.install_revision(id),'start');
 perform public.solar_installation_action(id,pg_temp.install_revision(id),'complete','{"checks":{"materials":true,"tested":true,"handover":true},"notes":"تسليم كامل","expenses":[]}');
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412652',true);
select public.solar_installation_action(current_setting('test.system_material_id')::bigint,pg_temp.install_revision(current_setting('test.system_material_id')::bigint),'close','{"amount":60}');
reset role;
set constraints all immediate;
do $$declare id bigint:=current_setting('test.system_material_id')::bigint;begin
 assert not exists(select from solar_private.system_receipt_material_prices s where s.invoice_id=id),'legacy notes or installation repriced a receipt';
 assert(select t.cost=400 and t.profit=565 and t.system_min_profit_percent=25 from public.transactions t where t.id=current_setting('test.system_material_id')::bigint);
 assert solar_private.reset_snapshot()?'solar_private.system_receipt_material_prices';
end $$;
rollback;
