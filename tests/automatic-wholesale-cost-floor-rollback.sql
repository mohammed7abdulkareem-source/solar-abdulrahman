\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,display_name,is_admin,user_type,phone,active,permissions) values
 ('00000000-0000-0000-0000-000000412601','مسؤول الأسعار',true,'admin_staff','07700412601',true,'{}'),
 ('00000000-0000-0000-0000-000000412602','بائع بسعر شخصي',false,'admin_staff','07700412602',true,'{"sale":true,"profitUsesWholesalePrice":true}');
insert into public.customers(id,name,customer_type,owner_id) values
 (-412601,'عميل السعر المتجدد','wholesale','00000000-0000-0000-0000-000000412602');
insert into public.products(id,code,name,qty,cost,cost_basis) values
 (-412601,'AUTO-FX','مادة بسعر الصرف',30,101,'{"currencyComponents":{"usd":0.1,"iqd":1.001234}}'),
 (-412602,'MANUAL-FX','مادة بسعر يدوي',30,600,'{"currencyComponents":{"usd":0,"iqd":600}}');
insert into solar_private.wholesale_product_prices(product_id,minimum_price,enabled)
 values(-412601,210,false),(-412602,550,true);
update solar_private.exchange_settings set rate=1000,revision=revision+1 where id;
update solar_private.wholesale_pricing_control set enabled=true,scope_mode='all',scope_configured=true where id;

create function pg_temp.row_price(product bigint) returns jsonb language sql as $$
 select v from jsonb_array_elements(public.solar_wholesale_pricing('state')->'products')v where (v->>'id')::bigint=product
$$;
create function pg_temp.sale_payload(product bigint,price numeric,tokens jsonb)returns jsonb language sql as $$
 select jsonb_build_object('kind','sale','sourceCurrency','IQD','exchangeRate',1,'mode','credit',
 'party','عميل السعر المتجدد','expenses',0,'items',jsonb_build_array(jsonb_build_object('id',product,'qty',1,'price',price)),
 'wholesaleFloorTokens',tokens)
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412601',true);
do $$
declare a jsonb:=pg_temp.row_price(-412601); m jsonb:=pg_temp.row_price(-412602);
begin
 if (a->>'effectiveMinPrice')::numeric is distinct from 101.001234 or (a->>'minPrice')::numeric is distinct from 210
 or a->>'floorSource' is distinct from 'cost' or coalesce(a->>'floorToken','')!~'^[0-9a-f]{64}$' then raise exception 'Initial FX floor incorrect %',a;end if;
 if (m->>'effectiveMinPrice')::numeric is distinct from 550 or m->>'floorSource' is distinct from 'configured' then raise exception 'Below-cost override not effective';end if;
 perform set_config('test.floor_before_fx',a->>'floorToken',true);
 perform set_config('test.manual',m->>'floorToken',true);
 if has_function_privilege('authenticated','solar_private.wholesale_floor_snapshot(bigint[])','execute') or
    has_table_privilege('authenticated','solar_private.wholesale_floor_token_key','select') then raise exception 'Raw floors or token key accessible';end if;
end$$;
reset role;
update solar_private.exchange_settings set rate=1100,revision=revision+1 where id;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412602',true);
do $$
declare a jsonb:=pg_temp.row_price(-412601); m jsonb:=pg_temp.row_price(-412602); id uuid:=gen_random_uuid(); r jsonb; p jsonb;
begin
 if a->'effectiveMinPrice' is distinct from 'null'::jsonb or a->'cost' is distinct from 'null'::jsonb
 or a->>'floorToken' is not distinct from current_setting('test.floor_before_fx') then raise exception 'Private FX floor/refresh invalid %',a;end if;
 if m->>'floorToken' is distinct from current_setting('test.manual') or (m->>'effectiveMinPrice')::numeric is distinct from 550 then raise exception 'FX changed fixed sale floor';end if;
 p:=pg_temp.sale_payload(-412601,120,jsonb_build_object('-412601',current_setting('test.floor_before_fx')));
 begin perform public.solar_invoice_save(id,p);raise exception 'Stale FX floor accepted';exception when sqlstate 'PT409' then null;end;
 p:=pg_temp.sale_payload(-412601,111,jsonb_build_object('-412601',a->>'floorToken'));
 begin perform public.solar_invoice_save(id,p);raise exception 'Below fractional floor accepted';exception when sqlstate 'PT422' then
  if sqlerrm ~ '[0-9]' then raise exception 'Private cost in validation message %',sqlerrm;end if;end;
 p:=pg_temp.sale_payload(-412601,111.01,jsonb_build_object('-412601',a->>'floorToken'));
 r:=public.solar_invoice_save(id,p);
 perform set_config('test.floor_id',r->>'id',true);
 perform set_config('test.floor_response',r::text,true);
 perform set_config('test.floor_request',id::text,true);
 perform set_config('test.floor_payload',p::text,true);
 perform public.solar_invoice_save(gen_random_uuid(),pg_temp.sale_payload(-412602,550,jsonb_build_object('-412602',m->>'floorToken')));
end$$;
set constraints all immediate;
set constraints all deferred;
reset role;
-- Change only acquisition cost: the FX revision and policy revision stay put.
update public.products set cost_basis=jsonb_set(cost_basis,'{currencyComponents,iqd}','12.345678')
 where id=-412601;
select set_config('test.floor_edit',jsonb_build_object('invoiceId',id,'expectedRevision',pricing_revision,'warehouseId',warehouse_id)::text,true)
 from public.transactions where id=current_setting('test.floor_id')::bigint;
set local role authenticated;
do $$
declare orig jsonb:=current_setting('test.floor_payload')::jsonb; p jsonb;
begin
 if public.solar_invoice_save(current_setting('test.floor_request')::uuid,orig) is distinct from current_setting('test.floor_response')::jsonb then
  raise exception 'Stale successful retry changed';end if;
 p:=jsonb_set(orig,'{items,0,price}','999');
 begin perform public.solar_invoice_save(gen_random_uuid(),p);raise exception 'Stale purchase-cost floor accepted';exception when sqlstate 'PT409' then null;end;
 -- An already accepted receipt can keep its price for an ordinary note edit.
 p:=orig||current_setting('test.floor_edit')::jsonb||jsonb_build_object('notes','ملاحظة جديدة');
 perform public.solar_invoice_save(gen_random_uuid(),p);
end$$;
reset role;
do $$
declare snapshot jsonb;
begin
 select prices_snapshot->0 into snapshot from solar_private.wholesale_invoice_pricing where invoice_id=current_setting('test.floor_id')::bigint;
 if (snapshot->>'effectiveMinPrice')::numeric is distinct from 111.001234 or snapshot->>'floorSource' is distinct from 'cost' then
  raise exception 'Historical sale floor changed %',snapshot;end if;
end$$;
set constraints all immediate;
rollback;
