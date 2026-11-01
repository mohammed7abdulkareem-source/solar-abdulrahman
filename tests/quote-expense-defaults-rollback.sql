\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,user_type,is_admin,permissions)values
('00000000-0000-0000-0000-000000039200','مدير مصاريف التحصيل','admin_staff',true,'{}'),
('00000000-0000-0000-0000-000000039201','مخول المصاريف','admin_staff',false,'{"tahseel":true,"tahseelFull":true,"tahseelDefaults":true}'),
('00000000-0000-0000-0000-000000039202','محدود مع صلاحية ناقصة','admin_staff',false,'{"tahseel":true,"tahseelDefaults":true}'),
('00000000-0000-0000-0000-000000039203','كامل بدون حفظ للجميع','admin_staff',false,'{"tahseel":true,"tahseelFull":true}');
create function pg_temp.shared_expense_payload()returns jsonb language sql set search_path=''as $$select '{"perPanel":"50000","expenses":{"crane":"45000","worker":"25000","programmer":"40000","delivery":"25000","electrical":"200000","commission":"75000"},"expectedRevision":1}'::jsonb$$;
create function pg_temp.shared_quote()returns jsonb language sql set search_path=''as $$select '{"day":"66.65","night":"0","batteryCapacity":"","inverterQty":"1","inverter":{"id":391001,"cost":"1"},"panel":{"id":391002,"cost":"1"},"perPanel":"0","expenses":{},"markupPercent":"0"}'::jsonb$$;
create function pg_temp.shared_finance()returns text language sql security definer set search_path=''as $$select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)order by id)from public.transactions t),'items',(select jsonb_agg(to_jsonb(t)order by id)from public.transaction_items t),'products',(select jsonb_agg(to_jsonb(t)order by id)from public.products t),'stock',(select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),'cash',(select jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text)from public.cash_ledger t),'entries',(select jsonb_agg(to_jsonb(t)order by id)from public.solar_cash_entries t))::text)$$;
select set_config('test.shared.finance',pg_temp.shared_finance(),true);
select set_config('test.shared.quotes',(select md5(jsonb_agg(to_jsonb(q)order by id)::text)from solar_quotes q),true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000039200',true);
set local role authenticated;
do $$declare s jsonb;r jsonb;begin
 s:=public.solar_quote_defaults();assert(s->>'canManage')::boolean and(s->>'revision')::int=1;
 begin perform public.solar_quote_defaults(null,gen_random_uuid(),pg_temp.shared_expense_payload());raise exception 'FAIL null action performed a save';exception when sqlstate'PT422'then null;end;
 assert s->>'perPanel'='45000'and s->'expenses'='{"crane":"40000","worker":"25000","programmer":"40000","delivery":"25000","electrical":"200000","commission":"75000"}'::jsonb,'Requested default amounts incorrect';
 r:=public.solar_limited_quote('preview',pg_temp.shared_quote());assert(r->>'panelQty')::int=31 and(r->>'price')::numeric=6210000,'31-panel total must use 1,800,000 expenses and fixed 15%';
 assert r::text!~'"expenses"|"cost"|unitCost|materialsTotal','Trusted preview exposes costs';
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000039203',true);
do $$declare s jsonb;begin
 s:=public.solar_quote_defaults();assert not(s->>'canManage')::boolean and s?'expenses','Full ordinary user should read but not change defaults';
 begin perform public.solar_quote_defaults('save',gen_random_uuid(),pg_temp.shared_expense_payload());raise exception 'FAIL full user changed shared defaults';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000039202',true);
do $$declare s jsonb;begin
 s:=public.solar_quote_defaults();assert not(s?'expenses')and not(s?'perPanel')and not(s->>'canManage')::boolean,'Limited metadata leaked expense details or write rights';
 begin perform public.solar_quote_defaults('save',gen_random_uuid(),pg_temp.shared_expense_payload());raise exception 'FAIL limited flag alone granted defaults';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000039201',true);
do $$declare r jsonb;nonce uuid:=gen_random_uuid();begin
 r:=public.solar_quote_defaults('save',nonce,pg_temp.shared_expense_payload());assert(r->>'revision')::int=2 and r->>'perPanel'='50000';
 assert public.solar_quote_defaults('save',nonce,pg_temp.shared_expense_payload())=r,'Retry changed a committed result';
 perform set_config('test.shared.nonce',nonce::text,true);perform set_config('test.shared.result',r::text,true);
 begin perform public.solar_quote_defaults('save',gen_random_uuid(),pg_temp.shared_expense_payload());raise exception 'FAIL stale writer overwrote current defaults';exception when sqlstate'PT409'then null;end;
 r:=public.solar_limited_quote('preview',pg_temp.shared_quote());assert(r->>'price')::numeric=6394000 and(r->>'expenseDefaultsRevision')::int=2,'Trusted prices did not adopt shared amounts';
 begin perform public.solar_limited_quote('save',pg_temp.shared_quote()||'{"expectedExpenseDefaultsRevision":1}','00000000-0000-0000-0000-000000392001');raise exception 'FAIL stale quote silently repriced at save';exception when sqlstate'PT409'then null;end;
end$$;
reset role;
do $$begin assert(select count(*)from solar_private.quote_expense_defaults_audit)=1,'Save retry duplicated audit';assert(select count(*)from solar_private.finance_requests where request_id=current_setting('test.shared.nonce')::uuid)=1;assert not exists(select 1 from solar_quotes where id='00000000-0000-0000-0000-000000392001');end$$;
set local role authenticated;
do $$declare bad jsonb;r jsonb;begin
 for bad in select jsonb_set(pg_temp.shared_expense_payload()||'{"expectedRevision":2}','{expenses,commission}',v)from unnest(array['""'::jsonb,'-1','"NaN"','"Infinity"','1.001','true','null','10000000001'])v loop
  begin perform public.solar_quote_defaults('save',gen_random_uuid(),bad);raise exception 'FAIL invalid expense accepted';exception when sqlstate'PT422'then null;end;
 end loop;
 begin perform public.solar_quote_defaults('save',gen_random_uuid(),pg_temp.shared_expense_payload()||'{"expectedRevision":1.5}');raise exception 'FAIL fractional revision';exception when sqlstate'PT422'then null;end;
 r:=public.solar_quote_defaults('save',gen_random_uuid(),pg_temp.shared_expense_payload()||'{"expectedRevision":2}');assert(r->>'revision')::int=2,'No-op changes revision';
end$$;
-- Cached results must still honor a permission revocation.
reset role;
update profiles set permissions='{"tahseel":true,"tahseelFull":true}'where id='00000000-0000-0000-0000-000000039201';
set local role authenticated;
do $$begin begin perform public.solar_quote_defaults('save',current_setting('test.shared.nonce')::uuid,pg_temp.shared_expense_payload());raise exception 'FAIL replay bypassed permission revocation';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000039200',true);
do $$declare p jsonb;begin
 begin perform public.solar_quote_defaults('save',current_setting('test.shared.nonce')::uuid,pg_temp.shared_expense_payload());raise exception 'FAIL another actor reused nonce';exception when sqlstate'PT409'then null;end;
 p:=jsonb_build_object('expectedRevision',2,'perPanel','0','expenses','{"crane":"0","worker":"0","programmer":"0","delivery":"0","electrical":"0","commission":"0"}'::jsonb);
 perform public.solar_quote_defaults('save',gen_random_uuid(),p);
 assert(public.solar_limited_quote('preview',pg_temp.shared_quote())->>'price')::numeric=4140000,'Zero expenses or commission rejected or miscounted';
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003914',true);
do $$begin begin perform public.solar_quote_defaults();raise exception 'FAIL warehouse access';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003915',true);
do $$begin begin perform public.solar_quote_defaults('save',gen_random_uuid(),pg_temp.shared_expense_payload());raise exception 'FAIL installer access';exception when insufficient_privilege then null;end;end$$;
reset role;
set local role anon;
do $$begin begin perform public.solar_quote_defaults();raise exception 'FAIL anonymous access';exception when insufficient_privilege then null;end;end$$;
reset role;
do $$begin
 assert not has_table_privilege('authenticated','solar_private.quote_expense_defaults','select')and not has_table_privilege('authenticated','solar_private.quote_expense_defaults','update');
 assert not has_table_privilege('authenticated','solar_private.quote_expense_defaults_audit','select')and not has_function_privilege('authenticated','solar_private.quote_defaults_state(boolean,boolean)','execute');
 assert pg_temp.shared_finance()=current_setting('test.shared.finance'),'Shared defaults changed actual stock/cash/accounting';
 assert(select md5(jsonb_agg(to_jsonb(q)order by id)::text)from solar_quotes q)=current_setting('test.shared.quotes'),'Settings or previews rewrote existing quotation snapshots';
 raise notice 'PASS exact requested amounts, 31-panel total, shared revision updates, delegated/full/limited/admin gates, exact retry and one audit, stale-save rollback, revocation, zero commission, private ACLs and unchanged quotations/financial records';
end$$;
rollback;
