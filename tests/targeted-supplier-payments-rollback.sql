\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,username,display_name,is_admin,user_type,active,permissions) values
 ('00000000-0000-0000-0000-000000413401','supplier_test_admin_4134','مدير الاختبار',true,'admin_staff',true,'{}'),
 ('00000000-0000-0000-0000-000000413402','supplier_test_user_4134','موظف الاختبار',true,'admin_staff',true,'{}');
insert into public.suppliers(id,name) values(-413401,'AbdulRahman'),(-413402,'مورد اعتيادي للتجربة');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413402',true);
-- A real receipt, originally posted by an admin before losing that role.
select set_config('test.supplier_rate',(public.solar_exchange_rate_get()->>'rate'),true);
select public.solar_fx('payment','00000000-0000-0000-0000-000000413403',
 '{"paymentId":-413410,"supplierId":-413401,"amount":10000,"currency":"IQD","rate":1450,"accountRevision":0,"mode":"charge_old_balance","note":"أصل الحساب المحمي"}');
reset role;
update public.profiles set is_admin=false,permissions='{"suppliers":true,"purchase":true,"supplierPayment":true,"supplierStatement":true}'
 where id='00000000-0000-0000-0000-000000413402';
set local role authenticated;
do $test$
declare
 ordinary jsonb:='{"paymentId":-413411,"supplierId":-413402,"amount":10000,"currency":"IQD","rate":1450,"accountRevision":0,"mode":"charge_old_balance","note":"أصل الحساب الاعتيادي"}';
 entry jsonb; row_data jsonb;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and permissions->'supplierPayment'='true') then raise exception 'Ordinary grant was stripped';end if;
 if exists(select 1 from public.suppliers where id=-413401) or not exists(select 1 from public.suppliers where id=-413402) then raise exception 'Raw directory scope incorrect';end if;
 if exists(select 1 from public.solar_purchase_suppliers() s where s.id=-413401) or not exists(select 1 from public.solar_purchase_suppliers() s where s.id=-413402) then raise exception 'Purchase selector scope incorrect';end if;
 if exists(select 1 from jsonb_array_elements(public.solar_supplier_directory()) s where s->>'id'='-413401') then raise exception 'Directory included restricted supplier';end if;
 select s into strict row_data from jsonb_array_elements(public.solar_supplier_directory()) s where s->>'id'='-413402';
 perform public.solar_supplier_save(gen_random_uuid(),jsonb_build_object('id',-413402,'name','مورد اعتيادي محدّث','currency','IQD','phone','07700000123','token',row_data->>'token'));
 perform public.solar_fx('payment',gen_random_uuid(),ordinary||jsonb_build_object('rate',current_setting('test.supplier_rate')::numeric));
 entry:=public.solar_supplier_payment_manage('get',null,'{"id":-413411}');
 if (entry->>'balance')::numeric is distinct from 10000 then raise exception 'Ordinary supplier charge failed';end if;
 perform public.solar_supplier_payment_manage('update',gen_random_uuid(),jsonb_build_object('id',-413411,'amount',10000,'rate',current_setting('test.supplier_rate')::numeric,'notes','تصحيح بيان اعتيادي','expectedToken',entry->>'token'));
 if exists(select 1 from jsonb_array_elements(public.solar_supplier_payment_manage('list')->'rows') s where s->>'id'='-413410') then raise exception 'Managed receipts listed a protected account';end if;
 if exists(select 1 from jsonb_array_elements(public.solar_fx('state')->'accountEntries') e where e->>'supplier_id'='-413401') then raise exception 'FX state returned hidden account';end if;
 begin perform public.solar_fx('statement',null,'{"supplierId":-413401}');raise exception 'Protected FX read allowed';exception when insufficient_privilege then null;end;
 begin perform public.solar_fx('account',null,'{"supplierId":-413402,"paymentId":-413410}');raise exception 'Protected receipt mismatched with ordinary account allowed';exception when insufficient_privilege then null;end;
 begin perform public.solar_fx('payment','00000000-0000-0000-0000-000000413403','{"paymentId":-413410,"supplierId":-413401,"amount":10000,"currency":"IQD","rate":1450,"accountRevision":0,"mode":"charge_old_balance","note":"أصل الحساب المحمي"}');raise exception 'Protected acknowledgement replay allowed after demotion';exception when insufficient_privilege then null;end;
 begin perform public.solar_supplier_payment_get(-413410);raise exception 'Protected legacy GET allowed';exception when insufficient_privilege then null;end;
 begin perform public.solar_supplier_account(-413401);raise exception 'Protected legacy account read allowed';exception when insufficient_privilege then null;end;
 begin perform public.solar_supplier_payment_save(gen_random_uuid(),-413412,-413401,100);raise exception 'Protected legacy payment allowed';exception when insufficient_privilege then null;end;
 begin perform public.solar_supplier_movement_save(gen_random_uuid(),-413413,-413401,100,'charge_old_balance','اختبار');raise exception 'Protected legacy charge allowed';exception when insufficient_privilege then null;end;
 begin perform public.solar_supplier_payment_manage('update',gen_random_uuid(),'{"id":-413410,"notes":"اختبار"}');raise exception 'Protected notes edit allowed';exception when insufficient_privilege then null;end;
 begin perform public.solar_supplier_save(gen_random_uuid(),'{"name":" ABDUL RAHMAN ","currency":"IQD"}');raise exception 'Duplicate protected account allowed';exception when insufficient_privilege then null;end;
end $test$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413401',true);
update public.suppliers set name='حساب المورد بعد التسمية' where id=-413401;
do $test$
begin
 if not exists(select 1 from public.suppliers where id=-413401 and admin_only) then raise exception 'Admin cannot access renamed supplier';end if;
 if (public.solar_fx('account',null,'{"supplierId":-413401}')->>'balance')::numeric<>10000 then raise exception 'Protected balance changed';end if;
 begin insert into public.suppliers(id,name) values(-413404,'ABDULRAHMAN');raise exception 'Old supplier name was reassigned to a different account';exception when unique_violation then null;end;
end $test$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413402',true);
do $test$
begin
 begin insert into public.suppliers(id,name) values(-413404,'حساب المورد بعد التسمية');raise exception 'Renamed protected identity reused by nonadmin';exception when insufficient_privilege then null;end;
 begin insert into public.suppliers(id,name) values(-413404,'abdulrahman');raise exception 'Original protected identity reused by nonadmin';exception when insufficient_privilege then null;end;
 begin perform public.solar_supplier_account(-413401);raise exception 'Renamed protected supplier readable';exception when insufficient_privilege then null;end;
end $test$;
rollback;
