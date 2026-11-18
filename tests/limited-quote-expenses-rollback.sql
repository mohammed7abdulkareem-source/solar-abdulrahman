\set ON_ERROR_STOP on
begin;
insert into solar_private.quote_expense_defaults(id)values(true) on conflict(id) do nothing;
update solar_private.quote_expense_defaults set per_panel=45000,crane=40000,worker=25000,programmer=40000,delivery=25000,electrical=200000,commission=75000,revision=7 where id;

insert into public.profiles(id,display_name,user_type,permissions)values
 ('00000000-0000-0000-0000-000000411491','Limited quote fixture','admin_staff','{"tahseel":true,"tahseelFull":false,"tahseelDefaults":true}'),
 ('00000000-0000-0000-0000-000000411492','Second quote fixture','admin_staff','{"tahseel":true}');
insert into public.products(id,code,name,category,qty,cost)values
 (41149101,'EXP-PANEL','Panel','ألواح',10,100),(41149102,'EXP-INV','Inverter','انفيرتر',10,1000),
 (41149103,'EXP-AIO','All in One','ALL IN ONE',10,4000);
create function pg_temp.quote_expense_input() returns jsonb language sql as $$
 select '{"day":"4","night":"0","inverterQty":"1","inverter":{"id":41149102,"cost":0},"panel":{"id":41149101,"cost":0},
 "expenseOverride":true,"perPanel":"10.25","expenses":{"crane":"100.5","worker":0,"programmer":0,"delivery":"1.25","electrical":"0","commission":"2.25"},"markupPercent":"90","profit":999999}'::jsonb
$$;
-- This pre-feature draft has a stored expense snapshot and no decision to override defaults.
insert into public.solar_quotes(id,user_id,payload) values
 ('00000000-0000-0000-0000-000000411493','00000000-0000-0000-0000-000000411491',pg_temp.quote_expense_input()-'expenseOverride');
select set_config('test.limited.original',(select md5(payload::text)from public.solar_quotes where id='00000000-0000-0000-0000-000000411493'),true);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411491',true);
do $$ declare r jsonb; f jsonb:=pg_temp.quote_expense_input(); q jsonb; bad jsonb; begin
 r:=public.solar_quote_defaults();
 assert r->'canManage'='false'::jsonb and r->>'perPanel'='45000' and r->'expenses'->>'commission'='75000';
 begin perform public.solar_quote_defaults('save',gen_random_uuid(),f||'{"expectedRevision":7}');raise exception 'Limited user changed shared expenses';exception when insufficient_privilege then null;end;
 assert (public.solar_limited_quote('preview',f-'expenseOverride')->>'price')::numeric=570630,'Old clients must follow shared settings';
 assert (public.solar_limited_quote('preview',f||'{"expenseOverride":false}')->>'price')::numeric=570630;
 r:=public.solar_limited_quote('preview',f||'{"expectedExpenseDefaultsRevision":7}');
 assert (r->>'price')::numeric=1523.18 and (r->>'markupPercent')::numeric=15,'Standard quote did not use only chosen expenses and the fixed markup';
 assert r::text !~ '"(cost|unitCost|materialsTotal|markup|profit|expensesTotal)"','Price preview leaked internal values';

 r:=public.solar_limited_quote('save',f,'00000000-0000-0000-0000-000000411494');
 assert r->'payload'->'expenseOverride'='true'::jsonb and r->'payload'->>'perPanel'='10.25' and r->'payload'->'expenses'->>'worker'='0';
 assert r::text !~ '"(cost|unitCost|materialsTotal|markup|profit|expensesTotal)"','Saved payload leaked material costs or profit';
 q:=f||'{"systemType":"all_in_one","allInOnePanelQty":2,"allInOneQty":"2","allInOne":{"id":41149103,"cost":1}}';
 r:=public.solar_limited_quote('save',q,'00000000-0000-0000-0000-000000411495');
 assert (r->'result'->>'price')::numeric=9573.18 and r->'payload'->'expenseOverride'='true'::jsonb;
 assert not(r->'payload'?'inverter') and not(r->'payload'->'allInOne'?'cost');
 for bad in select jsonb_set(f,'{expenses,delivery}',value) from jsonb_array_elements('[-1,"",true,null,{},"NaN","1e4",10000000001,0.004]') loop
  begin perform public.solar_limited_quote('preview',bad);raise exception 'Accepted invalid override amount';exception when sqlstate 'PT422' then null;end;
 end loop;
 foreach bad in array array[f-'perPanel',f-'expenses',f#-'{expenses,commission}',f||'{"expenseOverride":"true"}'] loop
  begin perform public.solar_limited_quote('save',bad,'00000000-0000-0000-0000-000000411496');raise exception 'Accepted incomplete override';exception when sqlstate 'PT422' then null;end;
 end loop;
 assert not exists(select from public.solar_quotes),'Limited account accessed raw stored costs';
end $$;
reset role;
update solar_private.quote_expense_defaults set per_panel=20000,revision=8 where id;
set local role authenticated;
do $$ declare rowdata jsonb; f jsonb:=pg_temp.quote_expense_input(); begin
 for rowdata in select value from jsonb_array_elements(public.solar_limited_quote('list')) loop
  case rowdata->>'id'
   when '00000000-0000-0000-0000-000000411493' then assert rowdata->'payload'->'expenseOverride'='false'::jsonb and (rowdata->'result'->>'price')::numeric=513130;
   when '00000000-0000-0000-0000-000000411494' then assert (rowdata->'result'->>'price')::numeric=1523.18 and rowdata->'payload'->'expenses'->>'delivery'='1.25';
   when '00000000-0000-0000-0000-000000411495' then assert (rowdata->'result'->>'price')::numeric=9573.18;
   else raise exception 'Unexpected draft owner'; end case;
 end loop;
 assert jsonb_array_length(public.solar_limited_quote('list'))=3;
 begin perform public.solar_limited_quote('save',f||'{"expectedExpenseDefaultsRevision":7}','00000000-0000-0000-0000-000000411494',1);raise exception 'Outdated defaults accepted';exception when sqlstate 'PT409' then null;end;
 rowdata:=public.solar_limited_quote('save',f||'{"expenseOverride":false,"expectedExpenseDefaultsRevision":8}','00000000-0000-0000-0000-000000411494',1);
 assert rowdata->'payload'->'expenseOverride'='false'::jsonb and rowdata->>'revision'='2' and(rowdata->'result'->>'price')::numeric=513130;
 begin perform public.solar_limited_quote('save',f,'00000000-0000-0000-0000-000000411494',1);raise exception 'FAIL stale draft update';exception when raise_exception then if sqlerrm='FAIL stale draft update' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411492',true);
do $$begin assert public.solar_limited_quote('list')='[]'::jsonb;end $$;
reset role;
do $$begin
 assert not has_function_privilege('authenticated','solar_private.limited_quote_expenses(jsonb)','execute');
 assert (select md5(payload::text) from public.solar_quotes where id='00000000-0000-0000-0000-000000411493')=current_setting('test.limited.original'),'Reading a legacy draft rewrote it';
 assert (select revision=8 and per_panel=20000 and crane=40000 from solar_private.quote_expense_defaults where id);
end $$;
rollback;
