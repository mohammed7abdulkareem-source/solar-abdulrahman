\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,permissions)values
('00000000-0000-0000-0000-000000003910','مدير رصيد الأرباح',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003911','صاحب رصيد الأرباح',false,'admin_staff','{"cash":true,"cashExpense":true,"profit":true,"profitSettlement":true}'),
('00000000-0000-0000-0000-000000003912','مستخدم أرباح آخر',false,'admin_staff','{"profit":true}'),
('00000000-0000-0000-0000-000000003913','مخزن رصيد الأرباح',true,'warehouse','{}'),
('00000000-0000-0000-0000-000000003914','مهندس رصيد الأرباح',true,'installer','{}'),
('00000000-0000-0000-0000-000000003915','بدون صلاحية أرباح',false,'admin_staff','{}');
insert into suppliers(id,name,account_currency)values(-391001,'مورد رصيد الأرباح','IQD');
insert into transactions(id,kind,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id,created_at)values
(-391001,'sale',10000000,10000000,7535136.32,true,false,'credit','00000000-0000-0000-0000-000000003911','00000000-0000-0000-0000-000000003911',now()-interval '2 days');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003911',true);
do $$declare c jsonb;r jsonb;d jsonb;s jsonb;begin
 c:=public.solar_profit_workspace('balance');
 if(c->>'remaining')::numeric<>7535136.32 then raise exception 'Initial retained balance';end if;
 r:=public.solar_profit_workspace('overview');
 if(r->>'retainedProfit')::numeric<>7535136.32 then raise exception 'Own dashboard missing authoritative balance';end if;
 r:=public.solar_profit_workspace('request',gen_random_uuid(),jsonb_build_object('expectedToken',r->>'token'));
 perform set_config('test.balance.settlement',r->>'id',true);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003910',true);
 c:=public.solar_profit_workspace('overview');select value into d from jsonb_array_elements(c->'requests')where value->>'id'=r->>'id';
 select value into s from jsonb_array_elements(c->'suppliers')where(value->>'id')::bigint=-391001;
 perform public.solar_profit_workspace('approve',gen_random_uuid(),jsonb_build_object('id',r->>'id','expectedToken',d->>'token','share',3768000,'collectionConfirmed',true,'settlementModel','owner_debit_supplier_charge','supplierId',-391001,'supplierToken',s->>'token','supplierRate',s->'rate'));
 c:=public.solar_profit_workspace('balance',null,'{"ownerId":"00000000-0000-0000-0000-000000003911"}');
 if(c->>'remaining')::numeric<>0 or(c->'period'->>'earned')::numeric<>7535136.32 or(c->'period'->>'settled')::numeric<>7535136.32 or(c->'period'->>'available')::numeric<>0 then raise exception 'Supplier remainder is still reported as available %',c;end if;
 -- A date filter that excludes the approval must not resurrect settled profit.
 c:=public.solar_profit_workspace('balance',null,jsonb_build_object('ownerId','00000000-0000-0000-0000-000000003911','to',((now()at time zone'Asia/Baghdad')::date-1)::text));
 if(c->>'remaining')::numeric<>0 or(c->'period'->>'available')::numeric<>0 then raise exception 'Historical date resurrected settled profit';end if;
end$$;
reset role;
insert into transactions(id,kind,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id)values
(-391002,'sale',500000,500000,500000,true,false,'credit','00000000-0000-0000-0000-000000003911','00000000-0000-0000-0000-000000003911');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003910',true);
do $$declare c jsonb;s jsonb;r jsonb;begin
 c:=public.solar_profit_workspace('balance',null,jsonb_build_object('ownerId','00000000-0000-0000-0000-000000003911','to',((now()at time zone'Asia/Baghdad')::date-1)::text,'type','system'));
 if(c->>'remaining')::numeric<>500000 or(c->'period'->>'earned')::numeric<>0 then raise exception 'Current balance incorrectly follows period/type filter';end if;
 c:=public.solar_cash_record('get','profit:'||current_setting('test.balance.settlement'));
 select value into s from jsonb_array_elements(c->'suppliers')where(value->>'id')::bigint=-391001;
 perform public.solar_cash_record('update','profit:'||current_setting('test.balance.settlement'),gen_random_uuid(),jsonb_build_object('amount',0,'note','تصحيح حصة المستخدم إلى صفر','expectedToken',c->>'token','supplierId',-391001,'supplierToken',s->>'token'));
 c:=public.solar_profit_workspace('balance',null,'{"ownerId":"00000000-0000-0000-0000-000000003911"}');
 if(c->>'remaining')::numeric<>500000 or(c->'period'->>'settled')::numeric<>7535136.32 then raise exception 'Allocation correction reopens/double deducts already settled sources';end if;
 perform public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003911","mode":"deposit","currency":"IQD","amount":5000000,"note":"تمويل الاختبار المعزول"}');
 r:=public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003911","mode":"expense","currency":"IQD","amount":20000,"note":"مصروف الاختبار المعزول"}');
 c:=public.solar_cash_record('get','tx:'||(r->>'id'));
 perform public.solar_cash_record('update','tx:'||(r->>'id'),gen_random_uuid(),jsonb_build_object('amount',40000,'note','مصروف مصحح','rate',1,'expectedToken',c->>'token'));
 c:=public.solar_profit_workspace('balance',null,'{"ownerId":"00000000-0000-0000-0000-000000003911"}');
 if(c->>'remaining')::numeric<>460000 or(c->'period'->>'available')::numeric<>460000 then raise exception 'Edited expense is duplicated or omitted';end if;
 perform public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003911","mode":"distribution","currency":"IQD","amount":100000,"note":"توزيع الاختبار المعزول"}');
 c:=public.solar_profit_workspace('balance',null,'{"ownerId":"00000000-0000-0000-0000-000000003911"}');
 if(c->>'remaining')::numeric<>360000 then raise exception 'Admin profit withdrawal omitted from current balance';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003911',true);
 c:=public.solar_profit_workspace('overview');
 if(c->>'retainedProfit')::numeric<>360000 then raise exception 'Own dashboard disagrees with company current balance';end if;
 begin perform public.solar_profit_workspace('balance',null,'{"ownerId":"all"}');raise exception 'FAIL staff all owners';exception when insufficient_privilege then null;end;
 begin perform public.solar_profit_workspace('balance',null,'{"ownerId":"00000000-0000-0000-0000-000000003912"}');raise exception 'FAIL staff foreign owner';exception when insufficient_privilege then null;end;
 begin perform solar_private.profit_balance('{}');raise exception 'FAIL direct private helper';exception when insufficient_privilege then null;end;
 if c::text like '%مستخدم أرباح آخر%' then raise exception 'Foreign user data leak';end if;
end$$;
reset role;
-- Reports must include stopped owners' retained profits, and preserve negatives.
update profiles set active=false where id='00000000-0000-0000-0000-000000003912';
insert into transactions(id,kind,total,cash,created_by,cashbox_user_id,cash_purpose)values
(-391003,'cash_expense',1000000,false,'00000000-0000-0000-0000-000000003912','00000000-0000-0000-0000-000000003912','expense');
create function pg_temp.balance_fingerprint()returns text language sql security definer set search_path='' as $$
 select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)order by id)from public.transactions t),
 'cash',(select jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text)from public.cash_ledger t),
 'supplier',(select jsonb_agg(to_jsonb(t)order by id)from solar_private.supplier_fx_entries t),
 'requests',(select jsonb_agg(to_jsonb(t)order by request_id)from solar_private.finance_requests t),
 'settlements',(select jsonb_agg(to_jsonb(t)order by id)from solar_private.profit_settlements t),
 'checkpoints',(select jsonb_agg(to_jsonb(t)order by owner_id,source_key)from solar_private.profit_checkpoints t))::text)
$$;
select set_config('test.balance.fingerprint',pg_temp.balance_fingerprint(),true);
select set_config('test.balance.all',(select sum(solar_private.retained_profit(id))from profiles where user_type not in('installer','warehouse'))::text,true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003910',true);
do $$declare r jsonb;bad text;begin
 r:=public.solar_profit_workspace('balance',null,'{"ownerId":"all"}');
 if(r->>'remaining')::numeric<>current_setting('test.balance.all')::numeric then raise exception 'Company balance differs from authoritative sum / inactive owner dropped';end if;
 r:=public.solar_profit_workspace('balance',null,'{"ownerId":"00000000-0000-0000-0000-000000003912"}');
 if(r->>'remaining')::numeric<>-1000000 then raise exception 'Negative profit clamped';end if;
 begin perform public.solar_profit_workspace('balance',null,'{"type":"bad"}');raise exception 'FAIL invalid type';exception when raise_exception then if sqlerrm='FAIL invalid type'then raise;end if;end;
 begin perform public.solar_profit_workspace('balance',null,'{"from":"2026-10-29","to":"2026-10-01"}');raise exception 'FAIL inverted dates';exception when raise_exception then if sqlerrm='FAIL inverted dates'then raise;end if;end;
 foreach bad in array array['00000000-0000-0000-0000-000000003913','00000000-0000-0000-0000-000000003914','00000000-0000-0000-0000-000000003915']loop
  perform set_config('request.jwt.claim.sub',bad,true);
  begin perform public.solar_profit_workspace('balance');raise exception 'FAIL role access';exception when insufficient_privilege then null;end;
 end loop;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003910',true);
 for i in 1..10 loop perform public.solar_profit_workspace('balance',null,'{"ownerId":"all"}');end loop;
end$$;
reset role;
do $$begin
 if pg_temp.balance_fingerprint()<>current_setting('test.balance.fingerprint') then raise exception 'Read-only reports mutated financial records';end if;
 if has_function_privilege('anon','public.solar_profit_workspace(text,uuid,jsonb)','execute')or has_function_privilege('authenticated','solar_private.profit_balance(jsonb)','execute')then raise exception 'New public access granted';end if;
 raise notice 'PASS full supplier/user allocation, old dates, type filters, new profits, zero-share correction, expense edits, distributions, inactive/negative balances, role isolation, unchanged financial records';
end$$;
rollback;
