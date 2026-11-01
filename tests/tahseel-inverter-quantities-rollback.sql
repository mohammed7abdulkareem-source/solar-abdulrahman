\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,user_type,is_admin,permissions,phone)values
('00000000-0000-0000-0000-000000003911','عرض كامل','admin_staff',false,'{"tahseel":true,"tahseelFull":true}','07700003911'),
('00000000-0000-0000-0000-000000003912','عرض محدود','admin_staff',false,'{"tahseel":true,"tahseelFull":false}','07700003912'),
('00000000-0000-0000-0000-000000003913','مستخدم آخر','admin_staff',false,'{"tahseel":true,"tahseelFull":true}','07700003913'),
('00000000-0000-0000-0000-000000003914','مخزن','warehouse',true,'{"tahseel":true,"tahseelFull":true}','07700003914'),
('00000000-0000-0000-0000-000000003915','مهندس','installer',true,'{"tahseel":true,"tahseelFull":true}','07700003915');
insert into products(id,code,name,category,qty,cost)values(391001,'QTY-INV','انفيرتر 8 كيلو','انفيرتر',100,500000),(391002,'QTY-PNL','لوح 600 واط','الواح',1000,100000),(391003,'QTY-BAT','بطارية 15 كيلو','بطارية',100,2000000);
create function pg_temp.quote_input(qty jsonb default '"2"')returns jsonb language sql set search_path=''as $$select jsonb_build_object('schema',4,'customer','زبون تعدد الانفيرترات','day','15','night','15','batteryCapacity','15','inverterQty',qty,'inverter',jsonb_build_object('id',391001,'cost','1'),'panel',jsonb_build_object('id',391002,'cost','1'),'battery',jsonb_build_object('id',391003,'cost','1'),'notes',E'ملاحظات الزبون\nجهازان 8 كيلو <script> & تفاصيل','markupPercent','0','perPanel','0','expenses','{}'::jsonb)$$;
create function pg_temp.quote_finance_hash()returns text language sql security definer set search_path=''as $$select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)order by id)from public.transactions t),'items',(select jsonb_agg(to_jsonb(t)order by id)from public.transaction_items t),'products',(select jsonb_agg(to_jsonb(t)order by id)from public.products t),'stock',(select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),'cash',(select jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text)from public.cash_ledger t),'entries',(select jsonb_agg(to_jsonb(t)order by id)from public.solar_cash_entries t))::text)$$;
insert into solar_quotes(id,user_id,payload)values('00000000-0000-0000-0000-000000391001','00000000-0000-0000-0000-000000003912',pg_temp.quote_input()-'inverterQty'||'{"schema":3}');
select set_config('test.quote_qty.financial',pg_temp.quote_finance_hash(),true);
select set_config('test.quote_qty.legacy',(select payload::text from solar_quotes where id='00000000-0000-0000-0000-000000391001'),true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003912',true);
set local role authenticated;
do $$declare r jsonb;saved jsonb;bad jsonb;begin
 r:=public.solar_limited_quote('preview',pg_temp.quote_input());
 assert jsonb_array_length(r->'errors')=0 and(r->>'price')::numeric=4789750,'Two units must use actual unit cost, fixed shop expenses and 15%';
 assert(r->>'inverterQty')::numeric=2;
 assert(select(v->>'qty')::numeric=2 from jsonb_array_elements(r->'materials')v where v->>'key'='inverter');
 assert r::text!~'unitCost|materialsTotal|expensesTotal|"cost"','Preview exposes private costs';
 r:=public.solar_limited_quote('preview',pg_temp.quote_input('"3"'));
 assert(r->>'price')::numeric=5364750 and(r->>'inverterQty')::numeric=3,'Three inverters priced as one';
 foreach bad in array array['""'::jsonb,'0','-1','1.5','1001','null','true','[2]','{}','"2e0"']loop
  r:=public.solar_limited_quote('preview',pg_temp.quote_input(bad));
  assert r->'price'='null'::jsonb and jsonb_array_length(r->'errors')>0,'Invalid quantity yielded a final price';
 end loop;
 r:=public.solar_limited_quote('preview',pg_temp.quote_input()-'inverterQty'||'{"schema":3}');
 assert(r->>'price')::numeric=4214750 and(r->>'inverterQty')::numeric=1,'Old client or draft no longer means one inverter';
 saved:=public.solar_limited_quote('save',pg_temp.quote_input(),'00000000-0000-0000-0000-000000391002');
 assert saved->'payload'->>'inverterQty'='2'and saved->'payload'->>'notes'=pg_temp.quote_input()->>'notes';
 assert not(saved->'payload'?'expenses')and not(saved->'payload'?'perPanel')and not(saved->'payload'->'inverter'?'cost'),'Saved quote exposes private cost fields';
 assert not exists(select 1 from public.solar_quotes),'Limited direct read must remain blocked';
 saved:=public.solar_limited_quote('save',pg_temp.quote_input('"3"'),'00000000-0000-0000-0000-000000391002',1);
 assert(saved->>'revision')::int=2 and saved->'payload'->>'inverterQty'='3';
 begin perform public.solar_limited_quote('save',pg_temp.quote_input(),'00000000-0000-0000-0000-000000391002',1);raise exception 'FAIL stale update';exception when raise_exception then if sqlerrm='FAIL stale update'then raise;end if;end;
 r:=public.solar_limited_quote('list');
 assert exists(select 1 from jsonb_array_elements(r)v where v->>'id'='00000000-0000-0000-0000-000000391002'and v->'payload'->>'inverterQty'='3'and(v->'result'->>'price')::numeric=5364750),'Reload lost quantity or quote price';
 assert r::text!~'unitCost|materialsTotal|expensesTotal|"cost"','List exposes private prices';
end$$;
reset role;
do $$begin assert(select payload::text from solar_quotes where id='00000000-0000-0000-0000-000000391001')=current_setting('test.quote_qty.legacy'),'Read or preview rewrote historical quote';end$$;
-- Full details retain their editable snapshots, quantity and notes under RLS.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003911',true);
set local role authenticated;
do $$begin
 insert into solar_quotes(id,user_id,payload)values('00000000-0000-0000-0000-000000391003',auth.uid(),pg_temp.quote_input('"3"')||'{"inverter":{"id":391001,"name":"انفيرتر 8 كيلو","cost":"600000"}}');
 assert exists(select 1 from solar_quotes where id='00000000-0000-0000-0000-000000391003'and payload->>'inverterQty'='3'and payload->'inverter'->>'cost'='600000');
 assert not exists(select 1 from solar_quotes where user_id='00000000-0000-0000-0000-000000003912'),'Cross-owner quote leaked';
 begin perform public.solar_limited_quote('save',pg_temp.quote_input(),'00000000-0000-0000-0000-000000391002',2);raise exception 'FAIL cross-owner update';exception when raise_exception then if sqlerrm='FAIL cross-owner update'then raise;end if;end;
end$$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003914',true);
set local role authenticated;
do $$begin begin perform public.solar_limited_quote('preview',pg_temp.quote_input());raise exception 'FAIL warehouse access';exception when insufficient_privilege then null;end;end$$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003915',true);
set local role authenticated;
do $$begin begin perform public.solar_limited_quote('list');raise exception 'FAIL installer access';exception when insufficient_privilege then null;end;end$$;
reset role;
set local role anon;
do $$begin begin perform public.solar_limited_quote('preview','{}');raise exception 'FAIL anonymous access';exception when insufficient_privilege then null;end;end$$;
reset role;
do $$begin
 assert not has_function_privilege('authenticated','solar_private.prepare_limited_quote(jsonb)','execute'),'Private helper became public';
 assert pg_temp.quote_finance_hash()=current_setting('test.quote_qty.financial'),'Quote operations changed actual financial/stock records';
 raise notice 'PASS two/three inverter pricing, fixed limited rules, legacy default without rewriting, notes/draft persistence, invalid quantity handling, hidden costs, stale guards, ownership and unchanged financial/stock records';
end$$;
rollback;
