-- Run on an isolated V4.1.2 database before the V4.1.3 migration. The actual
-- migration and all purchase/notification fixtures roll back together.
\set ON_ERROR_STOP on
begin;
load 'safeupdate';
insert into public.profiles(id,display_name,is_admin,user_type,active,permissions)values
('00000000-0000-0000-0000-000000414001','Warehouse Notice Admin',true,'admin_staff',true,'{}'),
('00000000-0000-0000-0000-000000414002','Warehouse Notice Staff',false,'admin_staff',true,'{"stock":true,"purchase":true}'),
('00000000-0000-0000-0000-000000414003','Warehouse Notice Other',false,'warehouse',true,'{}');
insert into solar_private.warehouses(id,name,code)overriding system value values
(-414001,'مخزن الاستلام الأصلي','WN-A'),(-414002,'مخزن الاستلام الآخر','WN-B');
insert into solar_private.warehouse_access(user_id,warehouse_ids)values
('00000000-0000-0000-0000-000000414002','{-414001}'),('00000000-0000-0000-0000-000000414003','{-414002}');
insert into public.products(id,name,code,category,qty,cost)values
(-414001,'WAREHOUSE MATERIAL A','PRIVATE-CODE-A','ألواح',0,0),(-414002,'WAREHOUSE MATERIAL B','PRIVATE-CODE-B','بطاريات',0,0),(-414003,'WAREHOUSE LEGACY MATERIAL','PRIVATE-CODE-C','انفيرترات',0,0);
insert into public.suppliers(id,name)values(-414001,'PRIVATE WAREHOUSE SUPPLIER');
insert into public.solar_push_subscriptions(endpoint,user_id,p256dh,auth_key)values
('https://fcm.googleapis.com/fcm/send/warehouse-notice-414002','00000000-0000-0000-0000-000000414002','local-p256','local-auth');
create function pg_temp.purchase_payload(location bigint default -414001)returns jsonb language sql as $$select jsonb_build_object('kind','purchase','mode','credit','partyId',-414001,'party','PRIVATE WAREHOUSE SUPPLIER','notes','PRIVATE FINANCIAL NOTE','warehouseId',location,'sourceCurrency','IQD','expenses',777,'items','[{"id":-414001,"qty":2,"price":98765},{"id":-414002,"qty":1,"price":43210}]'::jsonb)$$;
create function pg_temp.warehouse_notice_finances()returns text language sql security definer as $$select md5(jsonb_build_array(
(select jsonb_agg(to_jsonb(t)order by id)from transactions t),(select jsonb_agg(to_jsonb(t)order by id)from transaction_items t),
(select jsonb_agg(to_jsonb(t)order by id)from products t),(select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),
(select jsonb_agg(to_jsonb(t)order by id)from solar_private.wallet_fx_entries t),(select jsonb_agg(to_jsonb(t)order by id)from solar_private.supplier_fx_entries t))::text)$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000414001',true);
set local role authenticated;
do $$declare r jsonb;begin r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.purchase_payload());perform set_config('test.wn.oldInvoice',r->>'id',true);end$$;
reset role;
set constraints solar_purchase_notice_header,solar_purchase_notice_items immediate;
set constraints solar_purchase_notice_header,solar_purchase_notice_items deferred;
update solar_private.warehouses set name='اسم مخزن جديد بعد الوصل'where id=-414001;
insert into public.solar_notifications(id,user_id,event,title,body,details,warehouse_id,created_at,read_at)values
('00000000-0000-0000-0000-000000414031','00000000-0000-0000-0000-000000414002','purchase_received','Old title must stay','Old body must stay','{"type":"purchase_received","items":[{"name":"Old material","model":"OLD-CODE","category":"ألواح","brand":"Brand","qty":2}]}',-414002,now()-interval'2 days',now()-interval'1 day');
create temp table warehouse_notice_before as select id,to_jsonb(n)row from public.solar_notifications n;
create temp table warehouse_source_before as select invoice_id,to_jsonb(s)row from solar_private.purchase_notice_sources s;
create temp table warehouse_recipient_before as select to_jsonb(r)row from solar_private.purchase_notice_recipients r;
create temp table warehouse_delivery_before as select to_jsonb(d)row from solar_private.push_deliveries d;
select set_config('test.wn.beforeFinances',pg_temp.warehouse_notice_finances(),true);
\ir ../supabase/migrations/20261117123834_purchase_received_warehouse_name_v413.sql

do $$begin
 assert pg_temp.warehouse_notice_finances()=current_setting('test.wn.beforeFinances'),'Migration changed financial rows';
 assert(select count(*)from warehouse_notice_before)=(select count(*)from solar_notifications),'Backfill emitted a new notice';
 assert not exists(select 1 from warehouse_notice_before b join solar_notifications n on n.id=b.id where
  (to_jsonb(n)-'details')<>(b.row-'details')or coalesce(n.details-'warehouseName','null'::jsonb)is distinct from b.row->'details'),'Backfill changed old notification fields/items/read state';
 assert not exists(select 1 from warehouse_source_before b join solar_private.purchase_notice_sources s using(invoice_id)where
  (to_jsonb(s)-'details')<>(b.row-'details')or coalesce(s.details-'warehouseName','null'::jsonb)is distinct from b.row->'details'),'Source backfill changed other metadata';
 assert(select jsonb_agg(row order by row::text)from warehouse_recipient_before)is not distinct from(select jsonb_agg(to_jsonb(r)order by to_jsonb(r)::text)from solar_private.purchase_notice_recipients r),'Backfill changed audience';
 assert(select jsonb_agg(row order by row::text)from warehouse_delivery_before)is not distinct from(select jsonb_agg(to_jsonb(d)order by to_jsonb(d)::text)from solar_private.push_deliveries d),'Backfill requeued/changed delivery';
 assert not exists(select 1 from solar_notifications n join solar_private.purchase_notice_recipients r on r.notification_id=n.id where r.invoice_id=current_setting('test.wn.oldInvoice')::bigint and n.details->>'warehouseName'<>'مخزن الاستلام الأصلي'),'Backfill used renamed warehouse instead of saved receipt snapshot';
 assert(select details->>'warehouseName'from solar_notifications where id='00000000-0000-0000-0000-000000414031')='مخزن الاستلام الآخر','Unlinked fallback did not follow exact warehouse ID';
 assert not has_function_privilege('authenticated','solar_private.publish_purchase_notice(bigint,boolean)','EXECUTE');
end$$;
set local role authenticated;
do $$declare r jsonb;nonce uuid:=gen_random_uuid();begin
 r:=public.solar_invoice_save(nonce,pg_temp.purchase_payload());perform set_config('test.wn.newInvoice',r->>'id',true);
 assert r=public.solar_invoice_save(nonce,pg_temp.purchase_payload()),'Canonical retry changed result';
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.purchase_payload(-414002));perform set_config('test.wn.otherInvoice',r->>'id',true);
end$$;
reset role;
set constraints solar_purchase_notice_header,solar_purchase_notice_items immediate;
set constraints solar_purchase_notice_header,solar_purchase_notice_items deferred;
do $$declare notice solar_notifications;begin
 select n.* into notice from solar_notifications n join solar_private.purchase_notice_recipients r on r.notification_id=n.id where r.invoice_id=current_setting('test.wn.newInvoice')::bigint and n.user_id='00000000-0000-0000-0000-000000414002';
 assert notice.id is not null and notice.details->>'warehouseName'='اسم مخزن جديد بعد الوصل'and notice.body like'%المخزن: اسم مخزن جديد بعد الوصل%';
 assert notice.details-array['type','items','warehouseName']='{}'::jsonb and jsonb_array_length(notice.details->'items')=2 and notice.job_id is null;
 assert(notice.details::text||notice.body)!~'PRIVATE|98765|43210|777|price|cost|supplier|receiptNo|creator','New notice leaked private metadata';
 assert(select count(*)from solar_private.purchase_notice_recipients where invoice_id=current_setting('test.wn.newInvoice')::bigint and user_id='00000000-0000-0000-0000-000000414002')=1,'Retry duplicated recipient';
 assert not exists(select 1 from solar_private.purchase_notice_recipients where invoice_id=current_setting('test.wn.newInvoice')::bigint and user_id='00000000-0000-0000-0000-000000414003'),'Other warehouse recipient leaked';
 assert exists(select 1 from solar_notifications n join solar_private.purchase_notice_recipients r on r.notification_id=n.id where r.invoice_id=current_setting('test.wn.otherInvoice')::bigint and n.user_id='00000000-0000-0000-0000-000000414003'and n.details->>'warehouseName'='مخزن الاستلام الآخر');
 -- A forged field or warehouse value must fail the shape check even for SQL.
 begin update solar_notifications set details=details||'{"warehouseName":5}'where id=notice.id;raise exception 'Numeric warehouse accepted';exception when check_violation then null;end;
 begin update solar_notifications set details=details||'{"warehouseName":" "}'where id=notice.id;raise exception 'Empty warehouse accepted';exception when check_violation then null;end;
 begin update solar_notifications set details=details||jsonb_build_object('warehouseName',repeat('x',101))where id=notice.id;raise exception 'Oversized warehouse accepted';exception when check_violation then null;end;
 begin update solar_notifications set details=details||'{"supplier":"PRIVATE"}'where id=notice.id;raise exception 'Private field accepted';exception when check_violation then null;end;
end$$;
-- Canonical metadata edits and a warehouse rename never change the frozen notice.
update solar_private.warehouses set name='تسمية أحدث للمخزن'where id=-414001;
set local role authenticated;
do $$declare t transactions;begin
 select * into t from transactions where id=current_setting('test.wn.newInvoice')::bigint;
 perform public.solar_invoice_save(gen_random_uuid(),pg_temp.purchase_payload()||jsonb_build_object('invoiceId',t.id,'expectedRevision',t.pricing_revision,'notes','PRIVATE EDIT'));
end$$;
reset role;
do $$begin assert exists(select 1 from solar_private.purchase_notice_sources where invoice_id=current_setting('test.wn.newInvoice')::bigint and details->>'warehouseName'='اسم مخزن جديد بعد الوصل');end$$;
-- Legacy header/material appends update one notice using its original label.
set local role authenticated;
insert into transactions(id,kind,created_by,party_name,total,subtotal,cash,warehouse_id)values(-414099,'purchase',auth.uid(),'PRIVATE LEGACY',10,10,false,-414001);
insert into transaction_items(transaction_id,product_id,product_name,qty,price,cost)values(-414099,-414003,'WAREHOUSE LEGACY MATERIAL',1,10,10);
reset role;
update products set qty=qty+1 where id=-414003;
set constraints solar_purchase_notice_header,solar_purchase_notice_items immediate;
set constraints solar_purchase_notice_header,solar_purchase_notice_items deferred;
select set_config('test.wn.deliveryCount',(select count(*)::text from solar_private.push_deliveries),true);
update solar_private.warehouses set name='آخر تغيير بعد إشعار المخزن'where id=-414001;
set local role authenticated;
insert into transaction_items(transaction_id,product_id,product_name,qty,price,cost)values(-414099,-414003,'WAREHOUSE LEGACY MATERIAL',1,10,10);
reset role;
update products set qty=qty+1 where id=-414003;
set constraints solar_purchase_notice_header,solar_purchase_notice_items immediate;
set constraints solar_purchase_notice_header,solar_purchase_notice_items deferred;
do $$begin
 assert(select count(*)from solar_private.push_deliveries)=current_setting('test.wn.deliveryCount')::bigint,'Legacy append re-notified';
 assert not exists(select 1 from solar_notifications n join solar_private.purchase_notice_recipients r on r.notification_id=n.id where r.invoice_id=-414099 and(n.details->>'warehouseName'<>'تسمية أحدث للمخزن'or jsonb_array_length(n.details->'items')<>2));
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000414002',true);
do $$declare nid uuid;begin
 select id into nid from solar_notifications where event='purchase_received'and warehouse_id=-414001 limit 1;assert nid is not null;
 update solar_notifications set read_at=now()where id=nid;
 begin update solar_notifications set details=details||'{"warehouseName":"FORGED"}'where id=nid;raise exception 'User changed warehouse snapshot';exception when insufficient_privilege then null;end;
 assert not exists(select 1 from solar_notifications where warehouse_id=-414002),'Warehouse scope widened';
end$$;
reset role;
-- The same short body is consumed by the existing worker; no item/cost payload.
update solar_private.push_deliveries set available_at=now()-interval'100 days'where endpoint='https://fcm.googleapis.com/fcm/send/warehouse-notice-414002';
do $$declare batch jsonb;x jsonb;found boolean:=false;begin
 batch:=public.solar_push_claim();
 for x in select value from jsonb_array_elements(batch)loop
  if x->>'endpoint'='https://fcm.googleapis.com/fcm/send/warehouse-notice-414002'and x#>>'{notification,id}'in(select notification_id::text from solar_private.purchase_notice_recipients where invoice_id=current_setting('test.wn.newInvoice')::bigint)then
   assert x#>>'{notification,body}'like'%المخزن: اسم مخزن جديد بعد الوصل%';assert not(x->'notification'?'details');found:=true;
  end if;
 end loop;
 assert found,'New warehouse label absent from push claim';
end$$;
set constraints all immediate;
rollback;
\echo PASS warehouse notice snapshots, additive backfill, exact warehouse scope, unchanged queues/read flags/financials, canonical and legacy idempotency, payload security and push body
