-- Synthetic fixtures only. Run after accounts-bootstrap and the migrations.
begin;
insert into public.profiles(id,display_name,is_admin,permissions,user_type) values
 ('00000000-0000-0000-0000-000000003330','مدير الاختبار',true,'{}','admin_staff'),
 ('00000000-0000-0000-0000-000000003331','مبيعات أول',false,'{"customerDebts":true,"customerStatement":true,"customers":true,"supplierBalances":true}','admin_staff'),
 ('00000000-0000-0000-0000-000000003332','مبيعات ثان',false,'{"customerDebts":true,"customerStatement":true}','admin_staff'),
 ('00000000-0000-0000-0000-000000003333','كشف فقط',false,'{"customerStatement":true}','admin_staff'),
 ('00000000-0000-0000-0000-000000003334','بلا صلاحيات',false,'{}','admin_staff'),
 ('00000000-0000-0000-0000-000000003335','مهندس',false,'{"customerDebts":true,"customerStatement":true}','installer'),
 ('00000000-0000-0000-0000-000000003336','مخزن',true,'{}','warehouse');
insert into public.customers(id,name,phone,customer_type,owner_id) values
 (-333001,'أحمد علي','07701234567','wholesale','00000000-0000-0000-0000-000000003331'),
 (-333002,'سيف حسن','','system','00000000-0000-0000-0000-000000003331'),
 (-333003,'محمد الثاني','','wholesale','00000000-0000-0000-0000-000000003332'),
 (-333004,'عميل الكشف','','system','00000000-0000-0000-0000-000000003333');
-- Legacy duplicates predate the guard. They remain unassigned when ambiguous.
alter table public.customers disable trigger solar_customer_guard;
insert into public.customers(id,name,customer_type,owner_id) values
 (-333005,'اسم قديم مكرر','wholesale','00000000-0000-0000-0000-000000003331'),
 (-333006,'اسم قديم مكرر','system','00000000-0000-0000-0000-000000003332');
alter table public.customers enable trigger solar_customer_guard;
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_at,created_by,cashbox_user_id) values
 (-333001,'customer_payment',-333001,'أحمد علي',-2000000,false,'opening_balance','2026-10-01 10:00Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331'),
 (-333002,'sale',-333001,'اسم سابق',500000,false,'credit','2026-10-02 10:00Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331'),
 (-333003,'customer_payment',-333001,'أحمد علي',500000,true,'payment','2026-10-03 10:00Z','00000000-0000-0000-0000-000000003330','00000000-0000-0000-0000-000000003330'),
 (-333004,'sale',null,'احمدعلي',50000,false,'credit','2026-10-04 10:00Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331'),
 (-333005,'system_payment',-333002,'سيف حسن',-3000000,false,'opening_balance','2026-10-01 10:00Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331'),
 (-333006,'system_payment',-333002,'سيف حسن',1000000,true,'payment','2026-10-04 21:30Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331'),
 (-333007,'customer_payment',-333003,'محمد الثاني',-4000000,false,'opening_balance','2026-10-01 10:00Z','00000000-0000-0000-0000-000000003332','00000000-0000-0000-0000-000000003332'),
 (-333008,'customer_payment',-399999,'أحمد علي',-2000,false,'opening_balance','2026-10-01 10:00Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331'),
 (-333009,'sale',null,'اسم قديم مكرر',10000,false,'credit','2026-10-01 10:00Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331'),
 (-333010,'system',null,'منظومة غير مرتبطة',8000,true,'credit','2026-10-01 10:00Z','00000000-0000-0000-0000-000000003332','00000000-0000-0000-0000-000000003332'),
 (-333011,'sale',null,'بيع نقدي مجهول',9000,true,'cash','2026-10-01 10:00Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331');
insert into public.suppliers(id,name) values(-333001,'مورد تجريبي');
insert into public.transactions(id,kind,party_id,party_name,total,cash,created_at,created_by,cashbox_user_id) values
 (-333012,'purchase',-333001,'مورد تجريبي',1000,false,'2026-10-02 10:00Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331'),
 (-333013,'supplier_payment',-333001,'مورد تجريبي',200,true,'2026-10-03 10:00Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331'),
 (-333014,'purchase',-333001,'مورد تجريبي',400,false,'2026-10-02 10:00Z','00000000-0000-0000-0000-000000003332','00000000-0000-0000-0000-000000003332');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003331',true);
do $$declare r jsonb;x jsonb;ledger jsonb;c jsonb;begin
 r:=public.solar_party_balances('customers','2026-10-05');
 select value into x from jsonb_array_elements(r->'rows') where (value->>'id')::bigint=-333001;
 if (x->>'balance')::numeric<>2050000 or (x->>'last_payment')::numeric<>500000 or x->>'owner_name'<>'مبيعات أول' then raise exception 'FAIL full balance/owner/last payment';end if;
 ledger:=public.solar_customer_statement(-333001);
 if (ledger->>'balance')::numeric<>2050000 or jsonb_array_length(ledger->'rows')<>4 then raise exception 'FAIL statement/report resolution parity';end if;
 if (r->>'unresolved')::int<>2 or not exists(select 1 from jsonb_array_elements(r->'unresolved_rows') u where u->>'reason'='deleted_opening' and (u->>'effect')::numeric=2000) then raise exception 'FAIL legacy appendix';end if;
 if exists(select 1 from jsonb_array_elements(r->'unresolved_rows') u where (u->>'id')::bigint=-333010) then raise exception 'FAIL another user legacy leakage';end if;
 if exists(select 1 from jsonb_array_elements(r->'rows') u where (u->>'id')::bigint=-333003) then raise exception 'FAIL another user account leakage';end if;
 if jsonb_array_length(public.solar_statement_customers())<>3 then raise exception 'FAIL authorized picker directory';end if;
 r:=public.solar_party_balances('customers','2026-10-04');
 select value into x from jsonb_array_elements(r->'rows') where (value->>'id')::bigint=-333002;
 if (x->>'balance')::numeric<>3000000 then raise exception 'FAIL Baghdad date boundary';end if;
 r:=public.solar_party_balances('suppliers','2026-10-05');
 if (r->'rows'->0->>'balance')::numeric<>800 then raise exception 'FAIL supplier cashbox scope';end if;
 -- Renaming a customer retains newly resolved legacy entries and amounts.
 c:=public.solar_customer_get(-333001);
 perform public.solar_customer_save('update','00000000-0000-0000-0000-000000333001',jsonb_build_object('id',-333001,'token',c->>'token','name','أحمد علي الجديد','phone','07701234567','customerType','wholesale','openingBalance',2000000));
 ledger:=public.solar_customer_statement(-333001);
 if (ledger->>'balance')::numeric<>2050000 or not exists(select 1 from public.transactions where id=-333004 and party_id=-333001 and total=50000) then raise exception 'FAIL rename lost normalized legacy entry';end if;
 begin perform public.solar_customer_statement(-333003);raise exception 'FAIL cross-user statement';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003330',true);
do $$declare r jsonb;begin
 r:=public.solar_party_balances('customers','2026-10-05');
 if (r->>'unresolved')::int<>3 or jsonb_array_length(r->'owners')<>3 then raise exception 'FAIL admin legacy/owner visibility';end if;
 if (public.solar_party_balances('suppliers','2026-10-05')->'rows'->0->>'balance')::numeric<>1200 then raise exception 'FAIL admin supplier total';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003333',true);
do $$begin
 if jsonb_array_length(public.solar_statement_customers())<>1 or (public.solar_customer_statement(-333004)->>'balance')::numeric<>0 then raise exception 'FAIL statement-only permission';end if;
 begin perform public.solar_party_balances('customers','2026-10-05');raise exception 'FAIL missing debtor permission';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003334',true);
do $$begin
 begin perform public.solar_statement_customers();raise exception 'FAIL missing picker permission';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_statement(-333001);raise exception 'FAIL missing statement permission';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003335',true);
do $$begin begin perform public.solar_statement_customers();raise exception 'FAIL installer picker';exception when insufficient_privilege then null;end;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003336',true);
do $$begin begin perform public.solar_party_balances('customers','2026-10-05');raise exception 'FAIL warehouse report';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$begin
 if has_function_privilege('anon','public.solar_statement_customers()','EXECUTE') or has_function_privilege('authenticated','solar_private.customer_movement_links()','EXECUTE') then raise exception 'FAIL private resolver exposure';end if;
 if (select count(*) from public.transactions)<>14 then raise exception 'FAIL legacy movements were deleted';end if;
 if not exists(select 1 from public.transactions where id=-333008 and total=-2000 and party_id=-399999) then raise exception 'FAIL orphan rewritten';end if;
end $$;
-- Neither the metadata picker nor the financial RPC silently stops at 1000.
insert into public.customers(id,name,customer_type,owner_id)
 select -336000-n,'عميل دليل كبير '||n,'system','00000000-0000-0000-0000-000000003333'::uuid from generate_series(1,1005) n;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003333',true);
do $$begin if jsonb_array_length(public.solar_statement_customers())<>1006 then raise exception 'FAIL picker directory truncation';end if;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003330',true);
do $$begin if jsonb_array_length(public.solar_party_balances('customers','2026-10-05')->'rows')<>1011 then raise exception 'FAIL account report truncation';end if;end $$;
reset role;
select 'PASS: assigned owner balances, categories, shared ledger, legacy appendix, dates, rename and permissions' as result;
rollback;
