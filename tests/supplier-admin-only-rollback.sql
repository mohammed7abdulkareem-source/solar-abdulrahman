\set ON_ERROR_STOP on
begin;
-- Generate real receipts before demoting their original owner. Old grants,
-- notes-only updates and acknowledged writes must honor the current role.
insert into public.profiles(id,username,display_name,is_admin,user_type,active,permissions,phone) values
 ('00000000-0000-0000-0000-000000413301','supplier_admin_4133','مدير المورد التجريبي',true,'admin_staff',true,'{}','07700000101'),
 ('00000000-0000-0000-0000-000000413302','abdulrahman_test_4133','عبدالرحمن التجريبي',true,'admin_staff',true,'{}','07700000102');
insert into public.suppliers(id,name,account_currency) values(-4133001,'مورد الصلاحيات التجريبي','IQD');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413302',true);
do $$
declare
 payload jsonb:='{"paymentId":-4133002,"supplierId":-4133001,"amount":9000,"currency":"IQD","rate":1450,"accountRevision":0,"mode":"charge_old_balance","note":"رصيد اختباري"}';
 receipt jsonb;
begin
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',auth.uid(),'mode','deposit','currency','IQD','amount',12000,'note','قاصة اختبار'));
 perform public.solar_fx('payment','00000000-0000-0000-0000-000000413306',payload);
 perform public.solar_fx('payment',gen_random_uuid(),payload||'{"paymentId":-4133003,"amount":1000,"mode":"cash","note":"تسديد اختباري"}'::jsonb);
 receipt:=public.solar_supplier_payment_manage('get',null,'{"id":-4133003}');
 if (receipt->>'balance')::numeric<>8000 or (receipt->>'cashBalance')::numeric<>11000 then raise exception 'Admin payment did not post once to the supplier and payer';end if;
 perform set_config('test.supplier4133.token',receipt->>'token',true);
 perform set_config('test.supplier4133.payload',payload::text,true);
end $$;
reset role;
update public.profiles set is_admin=false,permissions='{"supplierPayment":true,"supplierStatement":true,"supplierBalances":true,"purchase":true,"suppliers":true,"cash":true,"deletionRequests":true}'
 where id='00000000-0000-0000-0000-000000413302';
set local role authenticated;
do $$
declare payload jsonb:=current_setting('test.supplier4133.payload')::jsonb;
 edit jsonb:=jsonb_build_object('id',-4133003,'amount',1000,'rate',1450,'notes','تعديل','expectedToken',current_setting('test.supplier4133.token'));
 account jsonb;
 supplier jsonb;
 context jsonb;
 operation text;
begin
 perform public.solar_supplier_save(gen_random_uuid(),'{"name":"مورد دليل تجريبي مستقل","currency":"IQD"}');
 select v into strict supplier from jsonb_array_elements(public.solar_supplier_directory()) v where v->>'id'='-4133001';
 perform public.solar_supplier_save(gen_random_uuid(),jsonb_build_object('id',-4133001,'name',supplier->>'name','phone','07700000103','currency','IQD','token',supplier->>'token'));
 select v into strict supplier from jsonb_array_elements(public.solar_supplier_directory()) v where v->>'id'='-4133001';
 begin
  perform public.solar_supplier_save(gen_random_uuid(),jsonb_build_object('id',-4133001,'name','تسمية مالية جديدة','phone','07700000103','currency','IQD','token',supplier->>'token'));
  raise exception 'Staff could rename an account with posted supplier receipts';
 exception when insufficient_privilege then null;end;
 begin
  delete from public.suppliers where id=-4133001;
  if found then raise exception 'Staff could remove a supplier with posted receipts';end if;
 exception when insufficient_privilege then null;end;
 begin
  context:=public.solar_receipt_delete_requests('context',null,'{"invoiceId":-4133003}');
  if coalesce((context->>'canRequest')::boolean,true) or coalesce((context->>'directEligible')::boolean,false) then raise exception 'Staff could initiate supplier receipt removal';end if;
 exception when insufficient_privilege then null;end;
 begin
  perform public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',-4133003,'expectedToken',context->>'token'));
  raise exception 'Staff could submit a supplier receipt removal request';
 exception when insufficient_privilege then null;end;
 account:=public.solar_fx('statement',null,'{"supplierId":-4133001}');
 if (account->>'balance')::numeric<>8000 or jsonb_array_length(account->'rows')<2 then raise exception 'Staff could not view own supplier statement';end if;
 foreach operation in array array['cash','charge_old_balance','charge_other'] loop
  begin
   perform public.solar_fx('payment',gen_random_uuid(),payload||jsonb_build_object('paymentId',-4133004,'mode',operation));
   raise exception 'Staff permitted to post %',operation;
  exception when insufficient_privilege then null;end;
 end loop;
 begin
  perform public.solar_fx('payment','00000000-0000-0000-0000-000000413306',payload);
  raise exception 'Demoted creator could replay a previously successful supplier posting';
 exception when insufficient_privilege then null;end;
 foreach operation in array array['update','delete'] loop
  begin
   perform public.solar_supplier_payment_manage(operation,gen_random_uuid(),edit);
   raise exception 'Demoted creator could % own receipt',operation;
  exception when insufficient_privilege then null;end;
 end loop;
 begin
  perform public.solar_supplier_movement_save(gen_random_uuid(),-4133004,-4133001,100,'charge_old_balance','تجريبي');
  raise exception 'Legacy supplier movement accepted staff';
 exception when insufficient_privilege then null;end;
 begin
  perform public.solar_supplier_payment_save(gen_random_uuid(),-4133004,-4133001,100,'تجريبي');
  raise exception 'Legacy supplier payment accepted staff';
 exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413301',true);
do $$
declare receipt jsonb; edit jsonb; result jsonb;
begin
 receipt:=public.solar_supplier_payment_manage('get',null,'{"id":-4133003}');
 if receipt->>'token'<>current_setting('test.supplier4133.token') or (receipt->>'balance')::numeric<>8000 or (receipt->>'cashBalance')::numeric<>11000 then
  raise exception 'Rejected operations changed the receipt, supplier statement or cashbox';
 end if;
 edit:=jsonb_build_object('id',-4133003,'expectedToken',receipt->>'token','amount',1000,'rate',1450,'notes','ملاحظة الإدارة');
 result:=public.solar_supplier_payment_manage('update',gen_random_uuid(),edit);
 if not (result->>'notesOnly')::boolean then raise exception 'Admin notes correction did not succeed';end if;
 receipt:=public.solar_supplier_payment_manage('get',null,'{"id":-4133003}');
 result:=public.solar_supplier_payment_manage('delete',gen_random_uuid(),jsonb_build_object('id',-4133003,'expectedToken',receipt->>'token'));
 if (result->>'balance')::numeric<>9000 or (result->>'cashBalance')::numeric<>12000 then raise exception 'Admin cancellation did not restore the supplier and the original payer';end if;
end $$;
reset role;
update public.profiles set permissions='{"purchase":true,"cash":true}' where id='00000000-0000-0000-0000-000000413302';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413302',true);
do $$
declare
 option jsonb;
 response jsonb;
 operation text;
begin
 -- A purchase still needs a supplier ID and its contractual currency. Its
 -- selector must not convey a protected directory row, ledger or cash debt.
 select to_jsonb(s) into strict option from public.solar_purchase_suppliers() s where s.id=-4133001;
 if option - array['id','name','account_currency','currency_revision'] <> '{}'::jsonb
  or option->>'account_currency' is distinct from 'IQD' then raise exception 'Unexpected purchase supplier projection';end if;
 if exists(select 1 from public.suppliers where id=-4133001) then raise exception 'Purchase-only staff read full directory rows';end if;
 foreach operation in array array['account','statement'] loop
  begin
   perform public.solar_fx(operation,null,'{"supplierId":-4133001}');
   raise exception 'Purchase-only staff could view %',operation;
  exception when insufficient_privilege then null;end;
 end loop;
 begin
  perform public.solar_supplier_account(-4133001);
  raise exception 'Legacy supplier account readable for purchase-only staff';
 exception when insufficient_privilege then null;end;
 begin
  response:=public.solar_supplier_directory();
  if jsonb_array_length(response)>0 then raise exception 'Purchase-only staff could browse supplier directory';end if;
 exception when insufficient_privilege then null;end;
 begin
  perform public.solar_party_balances('suppliers',current_date);
  raise exception 'Purchase-only staff could request supplier balances';
 exception when insufficient_privilege then null;end;
 response:=public.solar_fx('state',null,'{}');
 if coalesce(jsonb_array_length(response->'accountEntries'),0)<>0 then raise exception 'FX state exposed supplier activity through cash permission';end if;
 response:=public.solar_cash_workspace('{}');
 if response::text like '%رصيد اختباري%' or response::text like '%تسديد اختباري%' or response::text like '%مورد الصلاحيات التجريبي%' then
  raise exception 'Cash workspace disclosed the revoked supplier receipt';
 end if;
 select v into strict option from jsonb_array_elements(response->'rows') v where v->>'kind'='supplier_payment' and (v->>'delta')::numeric=-1000;
 if option->>'receiptRestricted' is distinct from 'true' or nullif(option->>'receipt_no','') is not null then raise exception 'Cash workspace did not redact the historic supplier payment';end if;
 response:=public.solar_cash_movement_detail('tx:-4133003');
 if response->>'receiptRestricted' is distinct from 'true' or (response->>'delta')::numeric is distinct from -1000
  or response->>'document' is not null or coalesce((response#>>'{edit,canEdit}')::boolean,false)
  or nullif(response->>'party','') is not null or coalesce((response#>>'{deletion,canRequest}')::boolean,false) then
  raise exception 'Cash movement detail exposed the revoked supplier document or changed its amount';
 end if;
 begin
  response:=public.solar_quick_search('مورد الصلاحيات','suppliers');
  if coalesce(jsonb_array_length(response->'suppliers'),0)>0 then raise exception 'Quick search exposed supplier';end if;
 exception when insufficient_privilege then null;end;
end $$;
rollback;
