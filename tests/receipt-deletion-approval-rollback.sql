begin;
insert into profiles(id,display_name,is_admin,user_type,permissions,phone)values
('00000000-0000-0000-0000-000000003830','مدير حذف الوصل',true,'admin_staff','{}','07701234567'),
('00000000-0000-0000-0000-000000003831','صاحب الوصل',false,'admin_staff','{"system":true,"installations":true,"systemPayment":true,"cash":true}','07701234567'),
('00000000-0000-0000-0000-000000003832','مستخدم آخر',false,'admin_staff','{}','07701234567'),
('00000000-0000-0000-0000-000000003833','مخزن',true,'warehouse','{"salesDeleteOwn":true}','07701234567'),
('00000000-0000-0000-0000-000000003834','مهندس',true,'installer','{"salesDeleteOwn":true}','07701234567');
insert into customers(id,name,customer_type,owner_id)values(-383001,'عميل حذف الوصل','system','00000000-0000-0000-0000-000000003831');
insert into products(id,code,name,qty,cost)values(-383001,'VOID-383','مادة الوصل المحذوف',10,100000);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty)values(1,-383001,10)on conflict(warehouse_id,product_id)do update set qty=excluded.qty;
insert into solar_cash_entries(owner_id,actor_id,delta,entry_type,created_at)values
('00000000-0000-0000-0000-000000003830','00000000-0000-0000-0000-000000003830',2000000,'transfer_in','2026-09-30T12:00Z'),
('00000000-0000-0000-0000-000000003831','00000000-0000-0000-0000-000000003830',1000000,'transfer_in','2026-09-30T12:00Z');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003831',true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","partyId":-383001,"party":"عميل حذف الوصل","total":3000000,"customerAddress":"بغداد","installerId":"00000000-0000-0000-0000-000000003834","warranty":{"enabled":true,"items":[{"id":-383001,"duration":12,"unit":"months"}],"maintenance":{"duration":0,"unit":"months"}},"items":[{"id":-383001,"qty":2,"price":0}]}');
 perform set_config('test.delete.main',r->>'id',true);
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","partyId":-383001,"party":"عميل حذف الوصل","total":1000000,"customerAddress":"بغداد","installerId":"00000000-0000-0000-0000-000000003834","items":[{"id":-383001,"qty":1,"price":0}]}');
 perform set_config('test.delete.orphan',r->>'id',true);
end$$;
reset role;
update transactions set warehouse_status='ready'where id=current_setting('test.delete.main')::bigint;
set local role authenticated;
do $$declare j transactions;c jsonb;begin
 select * into j from transactions where id=current_setting('test.delete.main')::bigint;
 perform public.solar_installation_action(j.id,j.installation_revision,'close','{"amount":479000}');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003830',true);
 select * into j from transactions where id=j.id;perform public.solar_installation_action(j.id,j.installation_revision,'reopen');
 select * into j from transactions where id=j.id;perform public.solar_installation_action(j.id,j.installation_revision,'close','{"amount":600000}');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003831',true);
 c:=public.solar_system_payment_context(-383001);
 perform public.solar_system_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-383001,'invoiceId',j.id,'amount',100000,'mode','payment','expectedToken',c->>'token'));
end$$;
reset role;
update solar_cash_entries set created_at=case when owner_id='00000000-0000-0000-0000-000000003831'then '2026-10-01T12:00Z'::timestamptz else '2026-10-02T12:00Z'::timestamptz end where job_id=current_setting('test.delete.main')::bigint;
update profiles set permissions='{"cash":true,"systemPayment":true,"salesDeleteOwn":false}'where id='00000000-0000-0000-0000-000000003831';
insert into transactions(id,kind,party_name,total,created_by)values(-383999,'sale','وصل المستخدم الآخر',500,'00000000-0000-0000-0000-000000003832');
insert into profiles(id,display_name,is_admin,user_type,permissions,phone)values('00000000-0000-0000-0000-000000003840','الإدارة الثانية',true,'admin_staff','{}','07701234567');
insert into solar_push_subscriptions(endpoint,user_id,p256dh,auth_key)values
('https://fcm.googleapis.com/fcm/send/local-approval-A','00000000-0000-0000-0000-000000003830','local-test-public-key','local-test-auth'),
('https://fcm.googleapis.com/fcm/send/local-approval-B','00000000-0000-0000-0000-000000003840','local-test-public-key','local-test-auth');
create function pg_temp.financial_hash()returns text language sql security definer as $$select md5(jsonb_build_array(
 (select jsonb_agg(to_jsonb(t)order by id)from public.transactions t),(select jsonb_agg(to_jsonb(t)order by id)from public.transaction_items t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.products t),(select jsonb_agg(to_jsonb(t)order by id)from public.solar_cash_entries t),
 (select jsonb_agg(to_jsonb(t)order by id)from solar_private.supplier_fx_entries t),(select jsonb_agg(to_jsonb(t)order by id)from solar_private.wallet_fx_entries t))::text)$$;
set local role authenticated;
do $$declare c jsonb;r jsonb;d jsonb;nonce uuid:=gen_random_uuid();fingerprint text;payload jsonb;j bigint:=current_setting('test.delete.main')::bigint;begin
 fingerprint:=pg_temp.financial_hash();
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',j));
 payload:=jsonb_build_object('invoiceId',j,'expectedToken',c->>'token');
 r:=public.solar_receipt_delete_requests('request',nonce,payload);assert public.solar_receipt_delete_requests('request',nonce,payload)=r;
 assert pg_temp.financial_hash()=fingerprint,'Request changed accounting';
 assert r->>'status'='pending';perform set_config('test.approval.request',r->>'id',true);
 begin perform public.solar_sale_delete(j,public.solar_sale_delete_preview(j)->>'token');raise exception 'Direct sale delete bypass';exception when insufficient_privilege then null;end;
 begin perform public.solar_purchase_delete(-123,0);raise exception 'Direct purchase bypass';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_payment_manage('delete',gen_random_uuid(),'{}');raise exception 'Direct customer receipt bypass';exception when insufficient_privilege then null;end;
 begin perform public.solar_supplier_payment_manage('delete',gen_random_uuid(),'{}');raise exception 'Direct supplier receipt bypass';exception when insufficient_privilege then null;end;
 begin perform public.solar_receipt_delete_requests('approve',(r->>'id')::uuid,'{}');raise exception 'Owner approved own request';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003832',true);
 begin perform public.solar_receipt_delete_requests('get',(r->>'id')::uuid);raise exception 'Foreign request read';exception when insufficient_privilege then null;end;
 begin perform public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',j));raise exception 'Foreign receipt request';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003834',true);
 begin perform public.solar_receipt_delete_requests('approve',(r->>'id')::uuid);raise exception 'Engineer stale admin approved';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003830',true);
 perform public.solar_receipt_delete_requests('reject',(r->>'id')::uuid,'{"note":"إبقاء الوصل"}');
 assert pg_temp.financial_hash()=fingerprint,'Rejection changed accounting';
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003831',true);
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',j));
 r:=public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',j,'expectedToken',c->>'token'));
 perform set_config('test.approval.approved',r->>'id',true);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003830',true);
 d:=public.solar_receipt_delete_requests('get',(r->>'id')::uuid);assert not(d->>'stale')::boolean;
 r:=public.solar_receipt_delete_requests('approve',(r->>'id')::uuid,jsonb_build_object('expectedToken',d->>'reviewToken'));
 assert r->>'status'='approved';fingerprint:=pg_temp.financial_hash();
 perform public.solar_receipt_delete_requests('approve',(r->>'id')::uuid,jsonb_build_object('expectedToken',d->>'reviewToken'));
 assert pg_temp.financial_hash()=fingerprint,'Repeated approval changed accounting';
 assert not exists(select 1 from transactions where id=j);
 assert solar_private.cash_balance('00000000-0000-0000-0000-000000003831')=1100000;
 assert solar_private.cash_balance('00000000-0000-0000-0000-000000003830')=2000000;
 assert exists(select 1 from transactions where kind='system_payment'and party_id=-383001 and system_invoice_id is null);
end$$;
reset role;
do $$declare r uuid:=current_setting('test.approval.request')::uuid;batch jsonb;begin
 assert(select count(*)from solar_notifications where delete_request_id=r and event='receipt_delete_requested')=2;
 assert not exists(select 1 from solar_notifications n join profiles p on p.id=n.user_id where n.delete_request_id=r and n.event='receipt_delete_requested'and(not p.is_admin or p.user_type in('warehouse','installer')));
 assert(select count(*)from solar_private.push_deliveries d join solar_notifications n on n.id=d.notification_id where n.delete_request_id=r and n.event='receipt_delete_requested')=2;
 batch:=public.solar_push_claim();assert exists(select 1 from jsonb_array_elements(batch)x where x->'notification'->>'deleteRequestId'=r::text);
 assert(select qty from products where id=-383001)=9;
end$$;
-- Editing a receipt after submission invalidates the pending approval.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003831',true);
set local role authenticated;
do $$declare c jsonb;r jsonb;begin
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',current_setting('test.delete.orphan')::bigint));
 r:=public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',c->'id','expectedToken',c->>'token'));perform set_config('test.approval.stale',r->>'id',true);
end$$;
reset role;
update transactions set notes='تعديل بعد الطلب'where id=current_setting('test.delete.orphan')::bigint;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003830',true);
set local role authenticated;
do $$declare d jsonb;b text;begin
 d:=public.solar_receipt_delete_requests('get',current_setting('test.approval.stale')::uuid);assert(d->>'stale')::boolean;b:=pg_temp.financial_hash();
 begin perform public.solar_receipt_delete_requests('approve',(d->>'id')::uuid,jsonb_build_object('expectedToken',d->>'reviewToken'));raise exception 'Stale approval accepted';exception when sqlstate 'PT409'then null;end;
 assert pg_temp.financial_hash()=b;
end$$;
reset role;
-- All other receipt types use the same protected workflow.
-- A demoted administrator must not retain access to another owner's requests.
do $$declare c jsonb;r jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003840',true);
 c:=public.solar_receipt_delete_requests('context',null,'{"invoiceId":-383999}');
 r:=public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',-383999,'expectedToken',c->>'token'));perform set_config('test.approval.demoted',r->>'id',true);
end$$;
update profiles set is_admin=false where id='00000000-0000-0000-0000-000000003840';
set local role authenticated;
do $$declare r uuid:=current_setting('test.approval.demoted')::uuid;d jsonb;begin
 begin perform public.solar_receipt_delete_requests('get',r);raise exception 'Demoted admin foreign read';exception when insufficient_privilege then null;end;
 d:=public.solar_receipt_delete_requests('list');assert not exists(select 1 from jsonb_array_elements(d->'rows')x where x->>'id'=r::text);
end$$;
reset role;
create function pg_temp.approve_fixture(id bigint)returns void language plpgsql as $$declare c jsonb;r jsonb;d jsonb;b text;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003831',true);b:=pg_temp.financial_hash();
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',id));r:=public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',id,'expectedToken',c->>'token'));assert pg_temp.financial_hash()=b;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003830',true);d:=public.solar_receipt_delete_requests('get',(r->>'id')::uuid);
 r:=public.solar_receipt_delete_requests('approve',(r->>'id')::uuid,jsonb_build_object('expectedToken',d->>'reviewToken'));assert r->>'status'='approved';
end$$;
do $$begin perform pg_temp.approve_fixture((select id from transactions where kind='system_payment'and party_id=-383001));assert solar_private.cash_balance('00000000-0000-0000-0000-000000003831')=1000000;end$$;
insert into customers(id,name,customer_type,owner_id)values(-384002,'عميل تسديد الموافقة','wholesale','00000000-0000-0000-0000-000000003831');
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id)values(-384002,'customer_payment',-384002,'عميل تسديد الموافقة',1000,true,'payment','00000000-0000-0000-0000-000000003831','00000000-0000-0000-0000-000000003831');
select pg_temp.approve_fixture(-384002);
do $$begin assert not exists(select 1 from transactions where id=-384002);assert solar_private.cash_balance('00000000-0000-0000-0000-000000003831')=1000000;end$$;
insert into suppliers(id,name,account_currency)values(-384001,'مورد موافقة الحذف','IQD');
update profiles set permissions=permissions||'{"purchase":true,"supplierPayment":true}'where id='00000000-0000-0000-0000-000000003831';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003831',true);
set local role authenticated;
select public.solar_fx('payment',gen_random_uuid(),'{"paymentId":-384100,"supplierId":-384001,"amount":100000,"currency":"IQD","rate":1660,"accountRevision":0,"mode":"charge_old_balance","note":"رصيد الاختبار"}');
select public.solar_fx('payment',gen_random_uuid(),'{"paymentId":-384101,"supplierId":-384001,"amount":25000,"currency":"IQD","rate":1660,"accountRevision":0,"mode":"cash"}');
reset role;
select pg_temp.approve_fixture(-384101);
do $$begin assert(select supplier_payment_voided_at from transactions where id=-384101)is not null;assert solar_private.cash_balance('00000000-0000-0000-0000-000000003831')=1000000;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003831',true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","mode":"credit","partyId":-384001,"party":"مورد موافقة الحذف","sourceCurrency":"IQD","items":[{"id":-383001,"qty":2,"price":50000}]}');perform set_config('test.approval.purchase',r->>'id',true);
end$$;
reset role;
select pg_temp.approve_fixture(current_setting('test.approval.purchase')::bigint);
do $$begin assert not exists(select 1 from transactions where id=current_setting('test.approval.purchase')::bigint);assert(select qty from products where id=-383001)=9;end$$;
set constraints all immediate;
\echo PASS admin deletion approvals for sales/systems/purchases/customer/supplier/system payments, unchanged request/reject accounting, own-only/role/direct-RPC gates, two-admin notification queue and push deep link, expense refunds, stale/replay protection
rollback;
