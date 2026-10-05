begin;
select set_config('v320.staff',(select id::text from public.profiles where active and not is_admin and user_type='admin_staff' order by created_at limit 1),true);
select set_config('v320.other',(select id::text from public.profiles where active and not is_admin and user_type='admin_staff' and id<>current_setting('v320.staff')::uuid order by created_at limit 1),true);
select set_config('v320.admin',(select id::text from public.profiles where active and is_admin and user_type='admin' limit 1),true);
update public.profiles set permissions='{"customerDebts":true,"supplierBalances":true}' where id in (current_setting('v320.staff')::uuid,current_setting('v320.other')::uuid);
insert into public.customers(id,name,customer_type,owner_id) values
 (-932001,'TEST 320 OWN','wholesale',current_setting('v320.staff')::uuid),
 (-932002,'TEST 320 OTHER','wholesale',current_setting('v320.other')::uuid),
 (-932003,'TEST 320 SYSTEM','system',current_setting('v320.staff')::uuid),
 (-932004,'TEST 320 CASH','wholesale',current_setting('v320.staff')::uuid);
insert into public.suppliers(id,name) values(-932001,'TEST 320 SUPPLIER'),(-932002,'TEST 320 HIDDEN SUPPLIER');
insert into public.transactions(id,kind,party_id,party_name,total,cash,created_at,created_by,cashbox_user_id) values
 (-932001,'sale',-932001,'OLD NAME',1000,false,'2026-10-03 10:00Z',current_setting('v320.staff')::uuid,current_setting('v320.staff')::uuid),
 (-932002,'customer_payment',-932001,'OLD NAME',200,true,'2026-10-04 10:00Z',current_setting('v320.admin')::uuid,current_setting('v320.admin')::uuid),
 (-932003,'customer_payment',-932001,'OLD NAME',-50,false,'2026-10-04 11:00Z',current_setting('v320.staff')::uuid,current_setting('v320.staff')::uuid),
 (-932004,'sale',-932002,'TEST 320 OTHER',700,false,'2026-10-03 10:00Z',current_setting('v320.other')::uuid,current_setting('v320.other')::uuid),
 (-932005,'system',-932003,'TEST 320 SYSTEM',2000,true,'2026-10-03 10:00Z',current_setting('v320.staff')::uuid,current_setting('v320.staff')::uuid),
 (-932006,'system_payment',-932003,'TEST 320 SYSTEM',300,true,'2026-10-04 21:30Z',current_setting('v320.staff')::uuid,current_setting('v320.staff')::uuid),
 (-932007,'sale',-932004,'TEST 320 CASH',999,true,'2026-10-03 10:00Z',current_setting('v320.staff')::uuid,current_setting('v320.staff')::uuid),
 (-932008,'purchase',-932001,'TEST 320 SUPPLIER',500,false,'2026-10-03 10:00Z',current_setting('v320.staff')::uuid,current_setting('v320.staff')::uuid),
 (-932009,'purchase',-932001,'TEST 320 SUPPLIER',777,true,'2026-10-03 10:00Z',current_setting('v320.staff')::uuid,current_setting('v320.staff')::uuid),
 (-932010,'supplier_payment',-932001,'TEST 320 SUPPLIER',100,true,'2026-10-04 10:00Z',current_setting('v320.staff')::uuid,current_setting('v320.staff')::uuid),
 (-932011,'purchase',-932001,'TEST 320 SUPPLIER',1000,false,'2026-10-03 10:00Z',current_setting('v320.other')::uuid,current_setting('v320.other')::uuid),
 (-932012,'purchase',-932002,'TEST 320 HIDDEN SUPPLIER',800,false,'2026-10-03 10:00Z',current_setting('v320.other')::uuid,current_setting('v320.other')::uuid);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('v320.staff'),true);
do $$ declare r jsonb; x jsonb; begin
 r:=public.solar_party_balances('customers','2026-10-05');
 select value into x from jsonb_array_elements(r->'rows') where value->>'id'='-932001';
 if (x->>'balance')::numeric is distinct from 850 or (x->>'last_payment')::numeric is distinct from 200 then raise exception 'FAIL own full balance/last positive payment';end if;
 if exists(select 1 from jsonb_array_elements(r->'rows') where value->>'id'='-932002') then raise exception 'FAIL leaked other customer';end if;
 select value into x from jsonb_array_elements(r->'rows') where value->>'id'='-932003';
 if (x->>'balance')::numeric is distinct from 1700 then raise exception 'FAIL legacy system cash flag';end if;
 select value into x from jsonb_array_elements(r->'rows') where value->>'id'='-932004';
 if (x->>'balance')::numeric is distinct from 0 then raise exception 'FAIL cash sale creates debt';end if;
 r:=public.solar_party_balances('customers','2026-10-04');
 select value into x from jsonb_array_elements(r->'rows') where value->>'id'='-932003';
 if (x->>'balance')::numeric is distinct from 2000 or x->>'last_payment' is not null then raise exception 'FAIL Baghdad cutoff';end if;
 r:=public.solar_party_balances('suppliers','2026-10-05');
 select value into x from jsonb_array_elements(r->'rows') where value->>'id'='-932001';
 if (x->>'balance')::numeric is distinct from 400 or (x->>'last_payment')::numeric is distinct from 100 then raise exception 'FAIL supplier own balance';end if;
 if exists(select 1 from jsonb_array_elements(r->'rows') where value->>'id'='-932002') then raise exception 'FAIL supplier scope';end if;
 begin perform public.solar_party_balances('unknown','2026-10-05');raise exception 'FAIL unknown report';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('v320.admin'),true);
do $$ declare r jsonb; x jsonb; begin
 r:=public.solar_party_balances('suppliers','2026-10-05');
 select value into x from jsonb_array_elements(r->'rows') where value->>'id'='-932001';
 if (x->>'balance')::numeric is distinct from 1400 then raise exception 'FAIL admin all supplier balance';end if;
 if not exists(select 1 from jsonb_array_elements(public.solar_party_balances('customers','2026-10-05')->'rows') where value->>'id'='-932002') then raise exception 'FAIL admin customer scope';end if;
end $$;
reset role;
-- Duplicate legacy names never charge two customers or expose another account.
insert into public.customers(id,name,customer_type,owner_id) values(-932005,'TEST 320 DUP','wholesale',current_setting('v320.staff')::uuid),(-932006,'TEST 320 DUP','wholesale',current_setting('v320.other')::uuid);
insert into public.transactions(id,kind,party_name,total,cash,created_at,created_by,cashbox_user_id) values(-932013,'sale','TEST 320 DUP',50,false,'2026-10-03 10:00Z',current_setting('v320.staff')::uuid,current_setting('v320.staff')::uuid);
insert into public.customers(id,name,customer_type,owner_id) select -933000-n,'TEST 320 BULK '||n,'wholesale',current_setting('v320.staff')::uuid from generate_series(1,1005) n;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('v320.staff'),true);
do $$ declare r jsonb; begin
 r:=public.solar_party_balances('customers','2026-10-05');
 if jsonb_array_length(r->'rows')<1005 then raise exception 'FAIL 1000-row truncation';end if;
 if (r->>'unresolved')::integer<1 then raise exception 'FAIL ambiguous legacy report warning';end if;
 if exists(select 1 from jsonb_array_elements(r->'rows') where value->>'id'='-932005' and (value->>'balance')::numeric<>0) then raise exception 'FAIL duplicate attribution';end if;
end $$;
reset role;
update public.profiles set permissions='{}' where id=current_setting('v320.staff')::uuid;
set local role authenticated;
do $$ begin
 begin perform public.solar_party_balances('customers','2026-10-05');raise exception 'FAIL permission missing';exception when insufficient_privilege then null;end;
end $$;
reset role;
update public.profiles set permissions='{"customerDebts":true,"supplierBalances":true}',user_type='warehouse',is_admin=true where id=current_setting('v320.staff')::uuid;
set local role authenticated;
do $$ begin
 begin perform public.solar_party_balances('suppliers','2026-10-05');raise exception 'FAIL warehouse';exception when insufficient_privilege then null;end;
end $$;
reset role;
update public.profiles set user_type='installer' where id=current_setting('v320.staff')::uuid;
set local role authenticated;
do $$ begin
 begin perform public.solar_party_balances('customers','2026-10-05');raise exception 'FAIL installer';exception when insufficient_privilege then null;end;
end $$;
reset role;
update public.profiles set user_type='admin_staff',active=false where id=current_setting('v320.staff')::uuid;
set local role authenticated;
do $$ begin
 begin perform public.solar_party_balances('customers','2026-10-05');raise exception 'FAIL inactive';exception when insufficient_privilege then null;end;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.solar_party_balances('customers','2026-10-05');raise exception 'FAIL anonymous';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS balances, owner scope, permissions, Baghdad dates, cash invoices, legacy systems, duplicate names and 1000-row cap' as result;
rollback;
