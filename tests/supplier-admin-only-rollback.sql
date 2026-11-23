-- The protected object is the supplier account, independent of the employee's name.
\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,display_name,active,is_admin,user_type,permissions) values
 ('00000000-0000-0000-0000-000000413301','مدير المورد التجريبي',true,true,'admin_staff','{}'),
 ('00000000-0000-0000-0000-000000413302','عبدالرحمن التجريبي',true,true,'admin_staff','{}'),
 ('00000000-0000-0000-0000-000000413303','مشتري تجريبي',true,false,'admin_staff','{"purchase":true,"cash":true}');
insert into public.suppliers(id,name,account_currency) values
 (-4133001,'ABDULRAHMAN','IQD'),(-4133005,'ABDULRAHMAN TRADING','IQD');

-- Create historical payments as the later-demoted employee; their relationship
-- to this supplier must still be checked after their own admin access is lost.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413302',true);
do $$
declare payload jsonb := '{"paymentId":-4133002,"supplierId":-4133001,"amount":9000,"currency":"IQD","rate":1450,"accountRevision":0,"mode":"charge_old_balance","note":"protected-ledger-fixture"}';
 receipt jsonb;
begin
 payload:=payload||jsonb_build_object('rate',public.solar_exchange_rate_get()->'rate');
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',auth.uid(),'mode','deposit','currency','IQD','amount',12000,'note','قاصة اختبار'));
 perform public.solar_fx('payment','00000000-0000-0000-0000-000000413306',payload);
 perform public.solar_fx('payment',gen_random_uuid(),payload||'{"paymentId":-4133003,"amount":1000,"mode":"cash"}'::jsonb);
 receipt:=public.solar_supplier_payment_manage('get',null,'{"id":-4133003}');
 assert (receipt->>'balance')::numeric=8000 and (receipt->>'cashBalance')::numeric=11000;
 perform set_config('test.supplier.token',receipt->>'token',true);
 perform set_config('test.supplier.payload',payload::text,true);
end $$;
reset role;
update public.profiles set is_admin=false,permissions='{"supplierPayment":true,"supplierStatement":true,"supplierBalances":true,"purchase":true,"suppliers":true,"cash":true,"deletionRequests":true}'
 where id='00000000-0000-0000-0000-000000413302';
set local role authenticated;
do $$
declare payload jsonb:=current_setting('test.supplier.payload')::jsonb;
 edit jsonb:=jsonb_build_object('id',-4133003,'amount',1000,'rate',payload->'rate','notes','تعديل','expectedToken',current_setting('test.supplier.token'));
 result jsonb; context jsonb; operation text;
begin
 assert exists(select 1 from public.suppliers where id=-4133005);
 assert not exists(select 1 from public.suppliers where id=-4133001);
 assert exists(select 1 from public.solar_purchase_suppliers() where id=-4133005);
 assert not exists(select 1 from public.solar_purchase_suppliers() where id=-4133001);
 result:=public.solar_supplier_directory();
 assert exists(select 1 from jsonb_array_elements(result) s where s->>'id'='-4133005');
 assert not exists(select 1 from jsonb_array_elements(result) s where s->>'id'='-4133001');
 result:=public.solar_fx('state',null,'{}');
 assert not exists(select 1 from jsonb_array_elements(result->'accountEntries') s where s->>'supplier_id'='-4133001');
 foreach operation in array array['account','statement'] loop
  begin
   perform public.solar_fx(operation,null,'{"supplierId":-4133001}');
   raise exception 'Direct supplier % was permitted',operation;
  exception when insufficient_privilege then null;end;
 end loop;
 foreach operation in array array['cash','charge_old_balance','charge_other'] loop
  begin
   perform public.solar_fx('payment',gen_random_uuid(),payload||jsonb_build_object('paymentId',-4133004,'mode',operation));
   raise exception 'Staff permitted to post % to protected supplier',operation;
  exception when insufficient_privilege then null;end;
 end loop;
 begin
  perform public.solar_fx('payment','00000000-0000-0000-0000-000000413306',payload);
  raise exception 'Demoted creator replayed a protected posting';
 exception when insufficient_privilege then null;end;
 foreach operation in array array['get','update','delete'] loop
  begin
   perform public.solar_supplier_payment_manage(operation,gen_random_uuid(),edit);
   raise exception 'Staff could % their old protected payment',operation;
  exception when insufficient_privilege then null;end;
 end loop;
 begin
  perform public.solar_supplier_movement_save(gen_random_uuid(),-4133004,-4133001,100,'charge_old_balance','تجريبي');
  raise exception 'Legacy supplier movement allowed protected posting';
 exception when insufficient_privilege then null;end;
 begin
  perform public.solar_supplier_payment_save(gen_random_uuid(),-4133004,-4133001,100,'تجريبي');
  raise exception 'Legacy payment allowed protected posting';
 exception when insufficient_privilege then null;end;
 begin
  context:=public.solar_receipt_delete_requests('context',null,'{"invoiceId":-4133003}');
  assert not coalesce((context->>'canRequest')::boolean,false) and not coalesce((context->>'directEligible')::boolean,false);
 exception when insufficient_privilege then null;end;

 -- The same employee, using the same grants, can post, read and manage their
 -- own ordinary supplier receipts. Similar names must remain distinct.
 perform public.solar_fx('payment',gen_random_uuid(),payload||'{"supplierId":-4133005,"paymentId":-4133006,"amount":5000}'::jsonb);
 perform public.solar_fx('payment',gen_random_uuid(),payload||'{"supplierId":-4133005,"paymentId":-4133007,"amount":700,"mode":"cash"}'::jsonb);
 result:=public.solar_fx('statement',null,'{"supplierId":-4133005}');
 assert (result->>'balance')::numeric=4300;
 assert jsonb_array_length(result->'rows')=2;
 result:=public.solar_supplier_payment_manage('get',null,'{"id":-4133007}');
 result:=public.solar_supplier_payment_manage('update',gen_random_uuid(),jsonb_build_object('id',-4133007,'amount',700,'rate',payload->'rate','expectedToken',result->>'token','notes','تصحيح عادي'));
 assert (result->>'notesOnly')::boolean;
 context:=public.solar_receipt_delete_requests('context',null,'{"invoiceId":-4133007}');
 assert (context->>'canRequest')::boolean;
 result:=public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',-4133007,'expectedToken',context->>'token'));
 assert result->>'status'='pending';
 perform set_config('test.supplier.ordinary_request',result->>'id',true);
 result:=public.solar_cash_movement_detail('tx:-4133003');
 assert (result->>'delta')::numeric=-1000 and result->>'document' is null and nullif(result->>'party','') is null;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413303',true);
do $$
declare option jsonb;
begin
 assert not exists(select 1 from public.solar_purchase_suppliers() where id=-4133001);
 select to_jsonb(s) into strict option from public.solar_purchase_suppliers() s where s.id=-4133005;
 assert option - array['id','name','account_currency','currency_revision']='{}'::jsonb;
 begin
  perform public.solar_fx('payment',gen_random_uuid(),current_setting('test.supplier.payload')::jsonb||'{"supplierId":-4133005,"paymentId":-4133008}'::jsonb);
  raise exception 'Purchase alone allowed ordinary supplier payments';
 exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413301',true);
do $$
declare receipt jsonb;
begin
 assert exists(select 1 from public.suppliers where id=-4133001);
 receipt:=public.solar_receipt_delete_requests('get',current_setting('test.supplier.ordinary_request')::uuid);
 receipt:=public.solar_receipt_delete_requests('approve',current_setting('test.supplier.ordinary_request')::uuid,jsonb_build_object('expectedToken',receipt->>'reviewToken'));
 assert receipt->>'status'='approved';
 assert exists(select 1 from public.solar_purchase_suppliers() where id=-4133001);
 receipt:=public.solar_supplier_payment_manage('get',null,'{"id":-4133003}');
 assert receipt->>'token'=current_setting('test.supplier.token') and (receipt->>'balance')::numeric=8000;
 receipt:=public.solar_supplier_payment_manage('delete',gen_random_uuid(),jsonb_build_object('id',-4133003,'expectedToken',receipt->>'token'));
 assert (receipt->>'balance')::numeric=9000 and (receipt->>'cashBalance')::numeric=12000;
end $$;
rollback;
