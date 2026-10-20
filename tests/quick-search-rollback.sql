\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions) values
('00000000-0000-0000-0000-000000003610','إدارة البحث',true,'admin_staff','07700003610','{}'),
('00000000-0000-0000-0000-000000003611','صاحب البحث',false,'admin_staff','07700003611','{"customers":true,"suppliers":true,"supplierStatement":true,"stock":true,"sale":true,"purchase":true}'),
('00000000-0000-0000-0000-000000003612','مستخدم آخر',false,'admin_staff','07700003612','{"customers":true,"suppliers":true,"stock":true,"sale":true}'),
('00000000-0000-0000-0000-000000003613','مخزن بصلاحيات قديمة',true,'warehouse','07700003613','{"customers":true,"suppliers":true,"stock":true,"sale":true}'),
('00000000-0000-0000-0000-000000003614','مهندس بصلاحيات قديمة',true,'installer','07700003614','{"customers":true,"suppliers":true,"stock":true}'),
('00000000-0000-0000-0000-000000003615','دون صلاحيات',false,'admin_staff','07700003615','{}');
insert into solar_private.warehouse_access(user_id,warehouse_ids) values
('00000000-0000-0000-0000-000000003611',array[1]::bigint[]),
('00000000-0000-0000-0000-000000003612',array[2]::bigint[]),
('00000000-0000-0000-0000-000000003613',array[1]::bigint[]);
insert into brands(id,name) values(-361001,'FULLMAX');
insert into products(id,code,name,brand_id,category,qty,cost) values
(-361001,'QS-001','إنفيرتر البحث',-361001,'انفيرتر',20,1000),
(-361002,'QS-002','بطارية البحث الصفرية',-361001,'بطارية',0,800);
update solar_private.warehouse_stocks set qty=15 where product_id=-361001 and warehouse_id=1;
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values(2,-361001,5);
insert into customers(id,name,phone,customer_type,owner_id) values
(-361001,'أَحمد البحث','07700011111','wholesale','00000000-0000-0000-0000-000000003611'),
(-361002,'أحمد البحث الآخر','07700022222','wholesale','00000000-0000-0000-0000-000000003612'),
(-361003,'زبون البحث المسدد','07700033333','wholesale','00000000-0000-0000-0000-000000003611');
insert into suppliers(id,name,phone,account_currency) values(-361001,'مورد البحث','07700100000','IQD');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003610',true);
select public.solar_exchange_rate_set(1660,(public.solar_exchange_rate_get()->>'revision')::bigint);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003611',true);
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"أَحمد البحث","partyId":-361001,"mode":"credit","warehouseId":1,"items":[{"id":-361001,"qty":2,"price":1200}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"مورد البحث","partyId":-361001,"mode":"credit","warehouseId":1,"sourceCurrency":"IQD","exchangeRate":1,"marketRate":1660,"accountRevision":0,"items":[{"id":-361001,"qty":1,"price":1000}]}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003612',true);
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"أحمد البحث الآخر","partyId":-361002,"mode":"credit","warehouseId":2,"items":[{"id":-361001,"qty":1,"price":9900}]}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003610',true);
reset role;
select public.solar_inventory('transfer',gen_random_uuid(),jsonb_build_object('fromId',1,'toId',2,'items',jsonb_build_array(jsonb_build_object('productId',-361001,'qty',2,'revision',(select revision from solar_private.warehouse_stocks where warehouse_id=1 and product_id=-361001))),'note','حجز اختبار البحث'));
reset role;
do $$declare r jsonb;row jsonb;before_count bigint;begin
 select count(*) into before_count from transactions;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003611',true);
 r:=public.solar_quick_search('احمد');
 if jsonb_array_length(r->'customers')<>1 or r->'customers'->0->>'name'<>'أَحمد البحث' or(r->'customers'->0->>'balance')::numeric<>2400 then raise exception 'customer balance or isolation failed %',r;end if;
 if r->'customers'->0 ? 'rows' or r->'customers'->0 ? 'token' then raise exception 'search leaked ledger/details';end if;
 r:=public.solar_quick_search('٠٧٧٠٠٠١١١١١','customers');if jsonb_array_length(r->'customers')<>1 then raise exception 'Arabic phone search failed';end if;
 r:=public.solar_quick_search('المسدد');if(r->'customers'->0->>'balance')::numeric<>0 then raise exception 'zero customer unavailable for quick lookup';end if;
 r:=public.solar_quick_search('fullmax QS-001');row:=r->'products'->0;
 if jsonb_array_length(r->'products')<>1 or(row->>'qty')::numeric<>12 or(row->>'reserved')::numeric<>2 or(row->>'cost')::numeric<>1000 then raise exception 'stock/cost incorrect %',r;end if;
 if jsonb_array_length(row->'warehouses')<>1 or row->'warehouses'->0->>'id'<>'1' then raise exception 'other warehouse leaked';end if;
 if(row->'lastSale'->>'amount')::numeric<>1200 then raise exception 'latest sale leaked other user price or mislabeled cost %',row;end if;
 r:=public.solar_quick_search('الصفرية');if(r->'products'->0->>'qty')::numeric<>0 or r->'products'->0->'lastSale'<>'null'::jsonb then raise exception 'zero stock or no-sale distinction failed';end if;
 r:=public.solar_quick_search('مورد البحث');if(r->'suppliers'->0->>'balance')::numeric<>1000 then raise exception 'supplier own balance wrong %',r;end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003612',true);
 r:=public.solar_quick_search('مورد البحث');if(r->'suppliers'->0->>'balance')::numeric<>0 then raise exception 'supplier other owner debt leaked';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003610',true);
 r:=public.solar_quick_search('احمد');if jsonb_array_length(r->'customers')<>2 then raise exception 'admin missing customer';end if;
 r:=public.solar_quick_search('QS-001');row:=r->'products'->0;
 if(row->>'qty')::numeric<>16 or jsonb_array_length(row->'warehouses')<>2 or(row->'lastSale'->>'amount')::numeric<>9900 then raise exception 'admin totals or latest price wrong %',r;end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003613',true);
 r:=public.solar_quick_search('البحث');
 if jsonb_array_length(r->'customers')<>0 or jsonb_array_length(r->'suppliers')<>0 or jsonb_array_length(r->'products')<>2 then raise exception 'warehouse financial search leaked or no stock';end if;
 if r->'products'->0 ? 'cost' or r->'products'->0 ? 'lastSale' then raise exception 'warehouse price leaked';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003614',true);
 r:=public.solar_quick_search('البحث');if r->'available'<>'[]'::jsonb then raise exception 'installer finance or stock leaked';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003615',true);
 r:=public.solar_quick_search('البحث');if r->'available'<>'[]'::jsonb then raise exception 'permissionless search leaked';end if;
 r:=public.solar_quick_search('ا');if jsonb_array_length(r->'products')<>0 then raise exception 'short query should not scan';end if;
 r:=public.solar_quick_search('%');if jsonb_array_length(r->'customers')<>0 then raise exception 'wildcard query not literal';end if;
 begin perform public.solar_quick_search('احمد','bad');raise exception 'invalid category accepted';exception when invalid_parameter_value then null;end;
 begin perform public.solar_quick_search(repeat('ا',101));raise exception 'oversized query accepted';exception when invalid_parameter_value then null;end;
 if(select count(*) from transactions)<>before_count then raise exception 'read-only lookup changed records';end if;
end$$;
-- Bounded result sets and live revocation, without changing any business history.
insert into products(id,code,name,qty,cost) select -361010-i,'LIMIT-'||i,'حدود البحث '||i,0,0 from generate_series(1,25) i;
set local role authenticated;
do $$declare r jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003611',true);
 r:=public.solar_quick_search('حدود');if jsonb_array_length(r->'products')<>6 or r->'more'->>'products'<>'true' then raise exception 'global limit failed';end if;
 r:=public.solar_quick_search('حدود','products');if jsonb_array_length(r->'products')<>20 or r->'more'->>'products'<>'true' then raise exception 'category limit failed';end if;
end$$;
reset role;
update profiles set permissions='{}' where id='00000000-0000-0000-0000-000000003611';
set local role authenticated;
do $$declare r jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003611',true);
 r:=public.solar_quick_search('البحث');if r->'available'<>'[]'::jsonb then raise exception 'revoked permission still worked';end if;
end$$;
reset role;
update profiles set active=false where id='00000000-0000-0000-0000-000000003611';
set local role authenticated;
do $$begin
 begin perform public.solar_quick_search('البحث');raise exception 'inactive account searched';exception when insufficient_privilege then null;end;
end$$;
reset role;
do $$begin
 if has_function_privilege('anon','public.solar_quick_search(text,text)','execute') then raise exception 'anonymous search exposed';end if;
 if has_function_privilege('authenticated','solar_private.quick_search_key(text)','execute') then raise exception 'helper exposed';end if;
 raise notice 'PASS scoped customer balances, supplier own debt, warehouse availability/reservations, explicit latest price vs cost, Arabic search, role isolation, bounded results, live revocation and read-only behavior';
end$$;
rollback;
