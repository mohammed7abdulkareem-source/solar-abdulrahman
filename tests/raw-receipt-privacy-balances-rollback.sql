\set ON_ERROR_STOP on
begin;
load 'safeupdate';
insert into public.profiles(id,display_name,is_admin,user_type,active,permissions)values
('00000000-0000-0000-0000-000000413001','Raw privacy admin',true,'admin_staff',true,'{}'),
('00000000-0000-0000-0000-000000413002','Raw privacy owner',false,'admin_staff',true,'{"customerPayment":true,"systemPayment":true,"supplierPayment":true,"supplierStatement":true}'),
('00000000-0000-0000-0000-000000413003','SECRET FOREIGN CREATOR',false,'admin_staff',true,'{"customerPayment":true}'),
('00000000-0000-0000-0000-000000413004','Warehouse stale admin',true,'warehouse',true,'{}'),
('00000000-0000-0000-0000-000000413005','Installer stale admin',true,'installer',true,'{}'),
('00000000-0000-0000-0000-000000413006','Inactive cash owner',false,'admin_staff',false,'{}'),
('00000000-0000-0000-0000-000000413007','Zero balance office',false,'admin_staff',true,'{}');
insert into public.customers(id,name,customer_type,owner_id)values(-413001,'Own shared account','wholesale','00000000-0000-0000-0000-000000413002');
insert into public.suppliers(id,name)values(-413001,'SECRET shared supplier');
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,notes)values
(-413001,'customer_payment',-413001,'Own shared account',100,true,'payment','00000000-0000-0000-0000-000000413001','00000000-0000-0000-0000-000000413002','SECRET admin payment'),
(-413002,'system_payment',-413001,'Own shared account',200,true,'payment','00000000-0000-0000-0000-000000413003','00000000-0000-0000-0000-000000413002','SECRET foreign system payment'),
(-413003,'supplier_payment',-413001,'SECRET shared supplier',50,true,'cash','00000000-0000-0000-0000-000000413001','00000000-0000-0000-0000-000000413002','SECRET supplier payment'),
(-413004,'customer_payment',-413001,'Own shared account',25,true,'payment','00000000-0000-0000-0000-000000413002','00000000-0000-0000-0000-000000413002','Own payment'),
(-413005,'system',null,'Own installation',0,false,'credit','00000000-0000-0000-0000-000000413002','00000000-0000-0000-0000-000000413002','Own system'),
(-413006,'system',null,'SECRET foreign installation',0,false,'credit','00000000-0000-0000-0000-000000413003','00000000-0000-0000-0000-000000413003','SECRET installation'),
(-413007,'cash_income',null,'Own admin deposit',400,true,'cash','00000000-0000-0000-0000-000000413001','00000000-0000-0000-0000-000000413002','Own standalone deposit'),
(-413008,'cash_income',null,'Inactive deposit',90,true,'cash','00000000-0000-0000-0000-000000413001','00000000-0000-0000-0000-000000413006','Inactive standalone deposit'),
(-413009,'supplier_payment',-413001,'Own supplier payment',0,true,'cash','00000000-0000-0000-0000-000000413002','00000000-0000-0000-0000-000000413002','Own supplier control');
insert into solar_private.deleted_sales(invoice_id,invoice,items,deleted_by)values
(-413011,'{"id":-413011,"kind":"system","created_by":"00000000-0000-0000-0000-000000413003","party_name":"SECRET archived system","notes":"SECRET archive","receipt_no":413011}','[]','00000000-0000-0000-0000-000000413001'),
(-413012,'{"id":-413012,"kind":"system","created_by":"00000000-0000-0000-0000-000000413002","party_name":"Own archived system","receipt_no":413012}','[]','00000000-0000-0000-0000-000000413001');
insert into public.solar_cash_entries(id,owner_id,actor_id,delta,entry_type,notes,job_id,deleted_job_id)values
('00000000-0000-0000-0000-000000413011','00000000-0000-0000-0000-000000413002','00000000-0000-0000-0000-000000413003',-30,'installation_payout','SECRET job entry',-413006,null),
('00000000-0000-0000-0000-000000413012','00000000-0000-0000-0000-000000413002','00000000-0000-0000-0000-000000413003',-20,'installation_payout','SECRET archived entry',null,-413011),
('00000000-0000-0000-0000-000000413013','00000000-0000-0000-0000-000000413002','00000000-0000-0000-0000-000000413002',-10,'installation_payout','Own job entry',-413005,null),
('00000000-0000-0000-0000-000000413014','00000000-0000-0000-0000-000000413002','00000000-0000-0000-0000-000000413001',7,'transfer_in','Own ordinary handover',null,null),
('00000000-0000-0000-0000-000000413015',null,'00000000-0000-0000-0000-000000413001',12,'transfer_transit','Unassigned transit',null,null),
('00000000-0000-0000-0000-000000413016','00000000-0000-0000-0000-000000413002','00000000-0000-0000-0000-000000413002',-3,'installation_payout','Own archive entry',null,-413012);
insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,entry_type,note)values
('00000000-0000-0000-0000-000000413002','USD',5,7500,1500,'deposit','Own USD'),
('00000000-0000-0000-0000-000000413006','USD',3,4500,1500,'deposit','Inactive USD');
-- Represents an earlier authorized update acknowledgement. Its raw audit/cache
-- must remain intact even though outward reads now hide its foreign creator.
insert into solar_private.finance_requests(request_id,actor_id,action,payload,response)values
('00000000-0000-0000-0000-000000413021','00000000-0000-0000-0000-000000413002','customer_payment_update','{"id":-413001,"amount":100,"expectedToken":"historical-token"}',jsonb_build_object('id',-413001,'receiptNo',(select receipt_no from transactions where id=-413001),'party','SECRET old receipt','total',100,'oldBalance',300,'remaining',200,'cashBefore',500,'cashAfter',600,'action','update')),
('00000000-0000-0000-0000-000000413022','00000000-0000-0000-0000-000000413002','customer_payment_update','{"id":-413004,"amount":25,"expectedToken":"own-token"}',jsonb_build_object('id',-413004,'receiptNo',(select receipt_no from transactions where id=-413004),'party','Own shared account','total',25,'oldBalance',225,'remaining',200,'cashBefore',575,'cashAfter',600,'action','update'));
insert into solar_private.fx_requests(request_id,actor_id,action,payload,response)values
('00000000-0000-0000-0000-000000413023','00000000-0000-0000-0000-000000413002','payment','{"paymentId":-413003,"amount":50}',jsonb_build_object('id',-413003,'receiptNo',413003,'party','SECRET supplier cached','total',50,'sourceCurrency','IQD','cashAmount',50,'token','preserved-receipt-token','accountContext',jsonb_build_object('supplierId',-413001,'currency','IQD','balance',123,'bookBalance',123,'token','preserved-account-token','cashBalance',619,'cashOwnerName','SECRET old actor')));
insert into solar_private.finance_requests(request_id,actor_id,action,payload,response)values
('00000000-0000-0000-0000-000000413024','00000000-0000-0000-0000-000000413002','supplier_payment_update','{"id":-413003,"amount":50}',jsonb_build_object('id',-413003,'action','update','party','SECRET supplier manage','replacement',jsonb_build_object('receiptNo',413003,'notes','SECRET replaced receipt'),'accountCurrency','IQD','balance',123,'cashBalance',619));
create function pg_temp.raw_balances(uid uuid default null)returns jsonb language sql security definer as $$
 select jsonb_build_object('IQD',coalesce(sum(delta)filter(where currency='IQD'),0),'USD',coalesce(sum(delta)filter(where currency='USD'),0),'usdBook',coalesce(sum(book_delta)filter(where currency='USD'),0))from solar_private.cash_movements()where uid is null or owner_id=uid
$$;
create function pg_temp.raw_financial_hash()returns text language sql security definer as $$select md5(jsonb_build_array(
 (select jsonb_agg(to_jsonb(t)order by id)from public.transactions t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.solar_cash_entries t),
 (select jsonb_agg(to_jsonb(t)order by id)from solar_private.wallet_fx_entries t),
 (select jsonb_agg(to_jsonb(t)order by request_id)from solar_private.finance_requests t),
 (select jsonb_agg(to_jsonb(t)order by request_id)from solar_private.fx_requests t),
 (select jsonb_agg(to_jsonb(t)order by invoice_id)from solar_private.deleted_sales t))::text)$$;
select set_config('test.raw_read.hash',pg_temp.raw_financial_hash(),true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413002',true);
set local role authenticated;
do $$declare r jsonb;expected jsonb;begin
 assert not exists(select 1 from public.transactions where id in(-413001,-413002,-413003)),'Raw payment headers bypassed creator scope';
 assert exists(select 1 from public.transactions where id=-413004 and notes='Own payment'),'Own payment hidden';
 assert exists(select 1 from public.transactions where id=-413007),'Own admin deposit hidden';
 assert not exists(select 1 from public.transactions where notes like'SECRET%'),'Raw secret search revealed foreign payment';
 assert not exists(select 1 from public.solar_cash_entries where id in('00000000-0000-0000-0000-000000413011','00000000-0000-0000-0000-000000413012')),'Raw foreign job entry leaked';
 assert(select count(*)=3 from public.solar_cash_entries where id in('00000000-0000-0000-0000-000000413013','00000000-0000-0000-0000-000000413014','00000000-0000-0000-0000-000000413016')),'Own live/archive job or ordinary transfer changed';
 assert not solar_private.cash_entry_invoice_read_allowed('00000000-0000-0000-0000-000000413011'),'Policy helper exposed foreign job permission';
 assert not solar_private.cash_entry_invoice_read_allowed('00000000-0000-0000-0000-000000413015'),'Policy helper allowed other/unassigned entry';
 assert solar_private.cash_entry_invoice_read_allowed('00000000-0000-0000-0000-000000413013');
 begin perform public.solar_supplier_payment_get(-413003);raise exception 'Foreign supplier receipt leaked';exception when insufficient_privilege then null;end;
 r:=public.solar_supplier_payment_get(-413009);assert r->>'notes'='Own supplier control';
 r:=public.solar_supplier_payment_manage('list');assert not(r::text~'SECRET|-413003'),'Supplier management list leaked foreign creator';
 begin perform public.solar_supplier_payment_manage('get',null,'{"id":-413003}');raise exception 'Supplier management get leaked foreign creator';exception when insufficient_privilege then null;end;
 r:=public.solar_fx('payment','00000000-0000-0000-0000-000000413023','{"paymentId":-413003,"amount":50}');
 assert r->'receiptRestricted'='true'::jsonb and r->'receiptNo'='null'::jsonb and r->>'token'='preserved-receipt-token'and r#>>'{accountContext,token}'='preserved-account-token'and r#>>'{accountContext,balance}'='123'and r::text not like'%SECRET%','FX cached receipt bypassed read privacy';
 r:=public.solar_supplier_payment_manage('update','00000000-0000-0000-0000-000000413024','{"id":-413003,"amount":50}');
 assert r->'receiptRestricted'='true'::jsonb and r->'replacement'='null'::jsonb and r->>'balance'='123'and r->>'cashBalance'='619'and r::text not like'%SECRET%','Supplier cached receipt bypassed read privacy';
 begin perform public.solar_payment_history('get','{"id":-413001}');raise exception 'Foreign payment history leaked';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_payment_manage('get',null,'{"id":-413001}');raise exception 'Foreign customer payment detail leaked';exception when insufficient_privilege then null;end;
 -- The account has no Cash Workspace permission, but already owns these funds.
 begin perform public.solar_cash_workspace('{}');raise exception 'Expected no cash-workspace permission';exception when insufficient_privilege then null;end;
 r:=public.solar_cash_read_balances();expected:=pg_temp.raw_balances(auth.uid());
 assert r->'summary'=expected and expected='{"IQD":619,"USD":5,"usdBook":7500}'::jsonb,'Own balances lost hidden payment/job effects';
 assert r->>'ownerId'=auth.uid()::text and jsonb_array_length(r->'owners')=1;
 assert r->'owners'->0=jsonb_build_object('id',auth.uid())||expected;
 assert r-array['asOf','ownerId','summary','owners']='{}'::jsonb and r::text not like'%SECRET%','Balance endpoint exposed unrelated metadata';
 r:=public.solar_customer_payment_manage('update','00000000-0000-0000-0000-000000413021','{"id":-413001,"amount":100,"expectedToken":"historical-token"}');
 assert r->'receiptRestricted'='true'::jsonb and r->'id'='null'::jsonb and r->'receiptNo'='null'::jsonb and r->>'party'='';
 assert r->>'remaining'='200'and r->>'cashAfter'='600'and r->>'action'='update'and r::text not like'%SECRET%','Historical acknowledgement lost effects or leaked metadata';
 r:=public.solar_customer_payment_manage('update','00000000-0000-0000-0000-000000413022','{"id":-413004,"amount":25,"expectedToken":"own-token"}');
 assert r->>'id'='-413004'and r->'receiptNo'<>'null'::jsonb,'Own cached receipt changed';
end$$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413001',true);
set local role authenticated;
do $$declare r jsonb;begin
 assert(select count(*)=3 from transactions where id in(-413001,-413002,-413003)),'Admin raw receipts restricted';
 assert(select count(*)=2 from solar_cash_entries where id in('00000000-0000-0000-0000-000000413011','00000000-0000-0000-0000-000000413012')),'Admin raw cash entries restricted';
 r:=public.solar_supplier_payment_get(-413003);assert r->>'notes'='SECRET supplier payment';
 r:=public.solar_cash_read_balances();assert r->'summary'=pg_temp.raw_balances()and r->'ownerId'='null'::jsonb,'Admin company cash changed';
 assert exists(select 1 from jsonb_array_elements(r->'owners')x where x->>'id'='00000000-0000-0000-0000-000000413006'and x->>'IQD'='90'and x->>'USD'='3'and x->>'usdBook'='4500'),'Inactive owner omitted';
 assert exists(select 1 from jsonb_array_elements(r->'owners')x where x->'id'='null'::jsonb and(x->>'IQD')::numeric>=12),'Unassigned transit omitted';
 assert r->'summary'=(public.solar_cash_workspace('{}')->'summary')-array['transit','periodIQDIn','periodIQDOut','periodUSDIn','periodUSDOut'],'Authoritative source differs from Cash Workspace';
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413007',true);
do $$declare r jsonb;begin r:=public.solar_cash_read_balances();assert r->'summary'='{"IQD":0,"USD":0,"usdBook":0}'::jsonb and jsonb_array_length(r->'owners')=1 and r->'owners'->0->>'id'=auth.uid()::text;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413004',true);
do $$begin
 begin perform public.solar_cash_read_balances();raise exception 'Warehouse stale-admin cash read';exception when insufficient_privilege then null;end;
 assert not exists(select 1 from transactions where id=-413001)and not exists(select 1 from solar_cash_entries where id='00000000-0000-0000-0000-000000413011');
 assert not solar_private.cash_entry_invoice_read_allowed('00000000-0000-0000-0000-000000413011');
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413005',true);
do $$begin begin perform public.solar_cash_read_balances();raise exception 'Installer stale-admin cash read';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413006',true);
do $$begin begin perform public.solar_cash_read_balances();raise exception 'Inactive cash read';exception when insufficient_privilege then null;end;end$$;
reset role;
do $$begin
 assert pg_temp.raw_financial_hash()=current_setting('test.raw_read.hash'),'Read privacy migration/tests changed financial records or cached acknowledgements';
 assert not has_function_privilege('anon','public.solar_cash_read_balances()','EXECUTE')and not has_function_privilege('anon','solar_private.cash_read_balances()','EXECUTE');
 assert not has_function_privilege('authenticated','solar_private.customer_payment_ack_read_projection(jsonb)','EXECUTE')and not has_function_privilege('authenticated','solar_private.supplier_payment_ack_read_projection(jsonb)','EXECUTE');
 assert(select bool_and(polcmd='r'and not polpermissive)from pg_policy where polname in('solar_payment_creator_read','solar_cash_entry_invoice_read')),'Privacy policies changed write authorization';
end$$;
set constraints all immediate;
rollback;
\echo PASS raw receipt/cash-entry privacy, own/admin totals including USD/inactive/transit, zero balance, no-cash office access, unchanged audit/financial data, private old acknowledgements and operational-role denial
