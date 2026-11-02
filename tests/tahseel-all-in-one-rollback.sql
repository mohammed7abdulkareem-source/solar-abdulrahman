-- Run only on an isolated test database. Every fixture is rolled back.
\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,display_name,user_type,is_admin,permissions)values
('00000000-0000-0000-0000-000000039960','تحصيل محدود','admin_staff',false,'{"tahseel":true,"tahseelFull":false}'),
('00000000-0000-0000-0000-000000039961','تحصيل كامل','admin_staff',false,'{"tahseel":true,"tahseelFull":true}'),
('00000000-0000-0000-0000-000000039962','مخزن','warehouse',true,'{"tahseel":true}');
insert into public.products(id,code,name,category,qty,cost)values
(396001,'TEST-PANEL','لوح 600 واط','ألواح',100,100000),
(396002,'TEST-AIO5','5KW/ALLINONE','All in One',20,3500000),
(396003,'TEST-AIO10','10KW/ALLINONE','All in One',20,6500000),
(396004,'TEST-INV','انفيرتر 8 كيلو','انفيرتر',20,500000),
(396005,'TEST-BAT','بطارية 15 كيلو','بطارية',20,2000000);
create function pg_temp.aio_input(qty jsonb default '"2"') returns jsonb language sql set search_path='' as $$
 select jsonb_build_object('systemType','all_in_one','schema',5,'customer','عرض ALL IN ONE','day','15','night','15','allInOneQty',qty,
 'panel',jsonb_build_object('id',396001,'cost','1'),'allInOne',jsonb_build_object('id',396002,'cost','1'),
 'inverter',jsonb_build_object('id',396004,'cost','99999999'),'battery',jsonb_build_object('id',396005,'cost','99999999'),
 'markupPercent','0','perPanel','0','expenses','{}'::jsonb,'notes','تفاصيل الجهاز')
$$;
create function pg_temp.aio_finance_hash() returns text language sql security definer set search_path='' as $$
 select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)order by id)from public.transactions t),
 'items',(select jsonb_agg(to_jsonb(t)order by id)from public.transaction_items t),
 'products',(select jsonb_agg(to_jsonb(t)order by id)from public.products t),
 'stock',(select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),
 'cash',(select jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text)from public.cash_ledger t),
 'entries',(select jsonb_agg(to_jsonb(t)order by id)from public.solar_cash_entries t))::text)
$$;
select set_config('test.aio.financial',pg_temp.aio_finance_hash(),true);
select set_config('test.aio.legacy',(select payload::text from public.solar_quotes where id='00000000-0000-0000-0000-000000391001'),true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000039960',true);
set local role authenticated;
do $$declare r jsonb;saved jsonb;bad jsonb;begin
 r:=public.solar_limited_quote('preview',pg_temp.aio_input());
 assert jsonb_array_length(r->'errors')=0 and(r->>'price')::numeric=9683000,'Integrated devices must use inventory prices, current expenses and 15%';
 assert(r->>'panelQty')::int=7 and(r->>'allInOneQty')::int=2 and(r->>'batteryQty')::int=0 and(r->>'inverterQty')::int=0;
 assert jsonb_array_length(r->'materials')=2 and r::text!~'unitCost|materialsTotal|expensesTotal|"cost"','Preview exposed costs or included separate battery/inverter';
 r:=public.solar_limited_quote('preview',pg_temp.aio_input('"1"')||'{"allInOne":{"id":396003}}');
 assert (r->>'price')::numeric=9108000,'10KW device price is incorrect';
 r:=public.solar_limited_quote('preview',pg_temp.aio_input()||'{"night":""}');
 assert(r->>'price')::numeric=9683000 and(r->>'panelQty')::int=7,'Daytime-only automatic panel count failed';
 r:=public.solar_limited_quote('preview',pg_temp.aio_input()||'{"day":"","night":""}');
 assert r->'price'='null'::jsonb,'Empty demand without a manual panel count yielded a price';
 r:=public.solar_limited_quote('preview',pg_temp.aio_input()||'{"night":"-1"}');
 assert r->'price'='null'::jsonb,'Invalid nighttime demand yielded a price';
 r:=public.solar_limited_quote('preview',pg_temp.aio_input()||'{"day":"","night":"","allInOnePanelQty":"10"}');
 assert(r->>'price')::numeric=10183250 and(r->>'panelQty')::int=10,'Manual panels without amps must use the same expenses';
 foreach bad in array array['"0"'::jsonb,'"-1"','"1.5"','"1001"','true','[1]'] loop
  r:=public.solar_limited_quote('preview',pg_temp.aio_input()||jsonb_build_object('allInOnePanelQty',bad));
  assert r->'price'='null'::jsonb and jsonb_array_length(r->'errors')>0,'Invalid panel count yielded a price';
 end loop;
 r:=public.solar_limited_quote('preview',pg_temp.aio_input()||'{"allInOne":{"id":396004}}');
 assert r->'price'='null'::jsonb and jsonb_array_length(r->'errors')>0,'Ordinary inverter accepted as integrated device';
 foreach bad in array array['""'::jsonb,'0','-1','1.5','1001','null','true','[2]','{}','"2e0"'] loop
  r:=public.solar_limited_quote('preview',pg_temp.aio_input(bad));
  assert r->'price'='null'::jsonb and jsonb_array_length(r->'errors')>0,'Invalid integrated quantity yielded a price';
 end loop;
 begin perform public.solar_limited_quote('preview',pg_temp.aio_input()||'{"expectedExpenseDefaultsRevision":999999}'); raise exception 'FAIL stale expenses';exception when sqlstate 'PT409' then null;end;
 saved:=public.solar_limited_quote('save',pg_temp.aio_input()||'{"day":"","night":"","allInOnePanelQty":"10"}','00000000-0000-0000-0000-000000396001');
 assert saved->'payload'->>'systemType'='all_in_one' and saved->'payload'->>'allInOneQty'='2' and saved->'payload'->>'allInOnePanelQty'='10';
 assert not(saved->'payload'?'expenses') and not(saved->'payload'->'allInOne'?'cost'),'Saved result exposed costs';
 assert not exists(select 1 from public.solar_quotes),'Limited direct read must remain blocked';
 r:=public.solar_limited_quote('list');
 assert exists(select 1 from jsonb_array_elements(r)v where v->>'id'='00000000-0000-0000-0000-000000396001' and(v->'result'->>'price')::numeric=10183250),'Reload lost integrated type or price';
 assert r::text!~'unitCost|materialsTotal|expensesTotal|"cost"','List exposed costs';
 r:=public.solar_limited_quote('preview',jsonb_build_object('day','15','night','15','batteryCapacity','15','panel',jsonb_build_object('id',396001),'battery',jsonb_build_object('id',396005),'inverter',jsonb_build_object('id',396004)));
 assert (r->>'price')::numeric=4508000 and(r->>'inverterQty')::int=1,'Old standard calculation changed';
end$$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000039961',true);
set local role authenticated;
do $$begin
 assert not exists(select 1 from public.solar_quotes where id='00000000-0000-0000-0000-000000396001'),'Other user quote exposed';
 begin perform public.solar_limited_quote('save',pg_temp.aio_input(),'00000000-0000-0000-0000-000000396001',1);raise exception 'FAIL cross-owner';exception when raise_exception then if sqlerrm='FAIL cross-owner'then raise;end if;end;
end$$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000039962',true);
set local role authenticated;
do $$begin begin perform public.solar_limited_quote('preview',pg_temp.aio_input());raise exception 'FAIL warehouse';exception when insufficient_privilege then null;end;end$$;
reset role;
set local role anon;
do $$begin begin perform public.solar_limited_quote('preview','{}');raise exception 'FAIL anonymous';exception when insufficient_privilege then null;end;end$$;
reset role;
do $$begin
 assert not has_function_privilege('authenticated','solar_private.prepare_all_in_one_quote(jsonb)','execute');
 assert not has_function_privilege('anon','solar_private.prepare_all_in_one_quote(jsonb)','execute');
 assert pg_temp.aio_finance_hash()=current_setting('test.aio.financial'),'Quote changed financial or stock records';
 assert (select payload::text from public.solar_quotes where id='00000000-0000-0000-0000-000000391001')=current_setting('test.aio.legacy'),'Historical quote changed';
 raise notice 'PASS trusted ALL IN ONE prices, both models, expenses, quantity, privacy, ownership, legacy, unchanged stock and cash';
end$$;
rollback;
