-- Disposable local V4.1 database only. All fixtures and financial writes roll back.
\set ON_ERROR_STOP on
\o /dev/null
begin;
insert into public.profiles(id,display_name,is_admin,user_type,phone,active,permissions)values
('00000000-0000-0000-0000-000000411001','Notice Admin',true,'admin_staff','07700411001',true,'{}'),
('00000000-0000-0000-0000-000000411002','Notice Owner',false,'admin_staff','07700411002',true,'{"purchase":true,"sale":true,"stock":true}'),
('00000000-0000-0000-0000-000000411003','Notice Manager',false,'admin_staff','07700411003',true,'{"wholesalePricingManage":true}'),
('00000000-0000-0000-0000-000000411004','Notice Stock',false,'admin_staff','07700411004',true,'{"stock":true}'),
('00000000-0000-0000-0000-000000411005','Notice Warehouse',true,'warehouse','07700411005',true,'{}'),
('00000000-0000-0000-0000-000000411006','Notice Foreign',false,'admin_staff','07700411006',true,'{"stock":true,"sale":true}'),
('00000000-0000-0000-0000-000000411007','Notice Installer',true,'installer','07700411007',true,'{}'),
('00000000-0000-0000-0000-000000411008','Notice None',false,'admin_staff','07700411008',true,'{}'),
('00000000-0000-0000-0000-000000411009','Notice Inactive',true,'admin_staff','07700411009',false,'{"sale":true}'),
('00000000-0000-0000-0000-000000411010','Notice System',false,'admin_staff','07700411010',true,'{"system":true}'),
('00000000-0000-0000-0000-000000411011','Notice Revoke',false,'admin_staff','07700411011',true,'{"sale":true}');
insert into solar_private.warehouses(id,name,code)overriding system value values(-411001,'Notice Other Warehouse','NR-OTHER');
insert into solar_private.warehouse_access(user_id,warehouse_ids)values
('00000000-0000-0000-0000-000000411006','{-411001}'),
('00000000-0000-0000-0000-000000411005','{1}');
insert into public.brands(id,name)values(-411001,'NOTICE BRAND');
insert into public.products(id,name,code,brand_id,qty,cost,category)values
(-411001,'Notice Material A','MODEL-A',-411001,0,0,'ألواح'),(-411002,'Notice Material B','MODEL-B',-411001,0,0,'ألواح'),(-411003,'Notice Zero Stock','MODEL-ZERO',-411001,0,0,'ألواح'),(-411004,'Notice Legacy A','LEGACY-A',-411001,0,0,'ألواح'),(-411005,'Notice Legacy B','LEGACY-B',-411001,0,0,'ألواح');
insert into public.suppliers(id,name)values(-411001,'PRIVATE SUPPLIER MUST NEVER LEAK');
insert into public.solar_push_subscriptions(endpoint,user_id,p256dh,auth_key)
select 'https://fcm.googleapis.com/fcm/send/notice-'||id,id,'local-key','local-auth'from public.profiles where id::text between '00000000-0000-0000-0000-000000411001'and'00000000-0000-0000-0000-000000411011';
create function pg_temp.nr_count(kind text)returns bigint language sql security definer set search_path=''as $$
 select count(*)from public.solar_notifications where event=kind and user_id::text between'00000000-0000-0000-0000-000000411001'and'00000000-0000-0000-0000-000000411011'
$$;
create function pg_temp.nr_deliveries()returns bigint language sql security definer set search_path=''as $$
 select count(*)from solar_private.push_deliveries d join public.solar_notifications n on n.id=d.notification_id where n.user_id::text between'00000000-0000-0000-0000-000000411001'and'00000000-0000-0000-0000-000000411011'
$$;
create function pg_temp.nr_sources()returns bigint language sql security definer set search_path=''as $$select count(*)from solar_private.purchase_notice_sources$$;
create function pg_temp.nr_purchase()returns jsonb language sql as $$select '{"kind":"purchase","partyId":-411001,"party":"PRIVATE SUPPLIER MUST NEVER LEAK","notes":"PRIVATE FINANCIAL NOTE","mode":"credit","sourceCurrency":"IQD","warehouseId":1,"expenses":777,"items":[{"id":-411001,"qty":3,"price":98765},{"id":-411002,"qty":2,"price":43210}]}'::jsonb$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411003',true);
do $$declare request uuid:=gen_random_uuid();payload jsonb;r jsonb;begin
 assert exists(select 1 from jsonb_array_elements(public.solar_wholesale_pricing()->'products')x where(x->>'id')::bigint=-411003),'Shared state must retain zero-stock archive pricing';
 payload:='{"items":[{"productId":-411001,"expectedRevision":0,"minPrice":150000,"enabled":true},{"productId":-411002,"expectedRevision":0,"minPrice":90000,"enabled":false}]}';
 r:=public.solar_wholesale_pricing('save',request,payload);
 assert(r->>'changedCount')::integer=2 and(r->>'notifiedCount')::integer>=5,'Real save counters';
 assert pg_temp.nr_count('wholesale_prices_updated')=5,'Price role audience';
 assert public.solar_wholesale_pricing('save',request,payload)=r,'Exact retry response';
 assert pg_temp.nr_count('wholesale_prices_updated')=5,'Retry duplicated price notices';
 r:=public.solar_wholesale_pricing('save',gen_random_uuid(),'{"items":[{"productId":-411001,"expectedRevision":1,"minPrice":150000,"enabled":true}]}');
 assert(r->>'changedCount')::integer=0 and(r->>'notifiedCount')::integer=0,'No-op counters';
 assert pg_temp.nr_count('wholesale_prices_updated')=5,'No-op sent notice';
 begin
  perform public.solar_wholesale_pricing('save',gen_random_uuid(),'{"items":[{"productId":-411001,"expectedRevision":1,"minPrice":160000,"enabled":true},{"productId":-411002,"expectedRevision":0,"minPrice":91000,"enabled":true}]}');
  raise exception 'Stale batch accepted';
 exception when sqlstate 'PT409'then null;end;
 assert pg_temp.nr_count('wholesale_prices_updated')=5,'Failed batch sent notice';
 r:=public.solar_wholesale_pricing('state');
 assert exists(select 1 from jsonb_array_elements(r->'products')x where(x->>'id')::bigint=-411001 and(x->>'minPrice')::numeric=150000),'Failed batch left earlier row changed';
 assert exists(select 1 from jsonb_array_elements(r->'products')x where(x->>'id')::bigint=-411002 and(x->>'minPrice')::numeric=90000),'Failed batch partially saved';
 r:=public.solar_wholesale_pricing('save',gen_random_uuid(),'{"items":[{"productId":-411001,"expectedRevision":1,"minPrice":150000,"enabled":true},{"productId":-411002,"expectedRevision":1,"minPrice":null,"enabled":false}]}');
 assert(r->>'changedCount')::integer=1,'Only actually changed rows count';
 assert pg_temp.nr_count('wholesale_prices_updated')=10,'Single changed batch per recipient';
end$$;
reset role;
do $$begin
 assert not exists(select 1 from public.solar_notifications where event='wholesale_prices_updated'and user_id::text between'00000000-0000-0000-0000-000000411001'and'00000000-0000-0000-0000-000000411011'and(details::text~'cost|supplier|98765|43210'or body~'150000|90000')),'Price notices expose procurement/lockscreen amounts';
 assert exists(select 1 from public.solar_notifications where user_id='00000000-0000-0000-0000-000000411002'and event='wholesale_prices_updated'and jsonb_array_length(details->'items')=1 and details->'items'->0->'minPrice'='null'::jsonb),'Cleared price details';
 assert not exists(select 1 from public.solar_notifications n cross join lateral jsonb_array_elements(n.details->'items')item where n.event='wholesale_prices_updated'and n.user_id::text between'00000000-0000-0000-0000-000000411001'and'00000000-0000-0000-0000-000000411011'and(item?'model'or item?'code'or item->>'category'<>'ألواح')),'New price notice must contain category, never material code/model';
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411002',true);
-- Canonical emission must contain ALL lines even with notice triggers immediate.
set constraints solar_purchase_notice_header,solar_purchase_notice_items immediate;
do $$declare request uuid:=gen_random_uuid();r jsonb;begin
 r:=public.solar_invoice_save(request,pg_temp.nr_purchase());
 perform set_config('test.nr.purchase',r->>'id',true);
 perform set_config('test.nr.sources',pg_temp.nr_sources()::text,true);
 perform set_config('test.nr.ownerDetails',(select jsonb_agg(details order by id)::text from public.solar_notifications where event='purchase_received'),true);
 assert pg_temp.nr_count('purchase_received')=7,'Purchase role and warehouse audience';
 assert public.solar_invoice_save(request,pg_temp.nr_purchase())=r,'Purchase exact retry';
 assert pg_temp.nr_count('purchase_received')=7,'Purchase retry duplicated notices';
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.nr_purchase()||jsonb_build_object('invoiceId',(r->>'id')::bigint,'expectedRevision',r->'pricingRevision','notes','Changed private note'));
 assert pg_temp.nr_count('purchase_received')=7,'Purchase metadata edit resent notice';
 assert(select jsonb_agg(details order by id)::text from public.solar_notifications where event='purchase_received')=current_setting('test.nr.ownerDetails'),'Canonical edit changed original notice';
 begin
  perform public.solar_invoice_save(gen_random_uuid(),pg_temp.nr_purchase());
  raise exception using errcode='PT499',message='simulate rollback after notice emission';
 exception when sqlstate 'PT499'then null;end;
 assert pg_temp.nr_count('purchase_received')=7,'Rolled-back save leaked notices';
 assert pg_temp.nr_sources()=current_setting('test.nr.sources')::bigint,'Rolled-back save left purchase marker';
end$$;
set constraints solar_purchase_notice_header,solar_purchase_notice_items immediate;
set constraints solar_purchase_notice_header,solar_purchase_notice_items deferred;
reset role;
do $$declare n public.solar_notifications;begin
 assert pg_temp.nr_count('purchase_received')=7,'Deferred triggers duplicated canonical notice';
 select * into n from public.solar_notifications where event='purchase_received'and user_id='00000000-0000-0000-0000-000000411005';
 assert n.job_id is null and n.warehouse_id=1,'Purchase notice must not expose private invoice link';
 assert n.details=jsonb_build_object('type','purchase_received','items','[{"name":"Notice Material B","category":"ألواح","brand":"NOTICE BRAND","qty":2},{"name":"Notice Material A","category":"ألواح","brand":"NOTICE BRAND","qty":3}]'::jsonb),'Purchase detail whitelist/order';
 assert not exists(select 1 from public.solar_notifications where event='purchase_received'and user_id::text between'00000000-0000-0000-0000-000000411001'and'00000000-0000-0000-0000-000000411011'and (details::text||title||body)~'PRIVATE|98765|43210|777|cost|price|supplier|total'),'Purchase financial metadata leaked';
 assert not exists(select 1 from public.solar_notifications where event='purchase_received'and user_id='00000000-0000-0000-0000-000000411006'),'Foreign warehouse disclosure';
end$$;

\echo PASS canonical save and notices
-- Direct legacy header/items can arrive in separate API transactions. Flush
-- deferred triggers separately to reproduce that order without committing data.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411001',true);
do $$declare j bigint;begin
 j:=floor(extract(epoch from clock_timestamp())*1000000)::bigint;
 insert into public.transactions(id,kind,created_by,party_name,party_type,total,subtotal,cash)values(j,'purchase',auth.uid(),'PRIVATE LEGACY SUPPLIER','supplier',123456,123456,false);
 perform set_config('test.nr.legacy',j::text,true);
end$$;
set constraints solar_purchase_notice_header,solar_purchase_notice_items immediate;
set constraints solar_purchase_notice_header,solar_purchase_notice_items deferred;
do $$begin assert pg_temp.nr_count('purchase_received')=7,'Empty legacy header sent notice';end$$;
insert into public.transaction_items(transaction_id,product_id,product_name,qty,price,cost)values(current_setting('test.nr.legacy')::bigint,-411004,'Notice Legacy A',1,123456,123456);
reset role;
-- Match the legacy importer stock bookkeeping without weakening raw-stock guards.
update public.products set qty=qty+1 where id=-411004;
set local role authenticated;
set constraints solar_purchase_notice_header,solar_purchase_notice_items immediate;
set constraints solar_purchase_notice_header,solar_purchase_notice_items deferred;
do $$begin assert pg_temp.nr_count('purchase_received')=14,'Legacy first material did not notify';perform set_config('test.nr.deliveryCount',pg_temp.nr_deliveries()::text,true);end$$;
insert into public.transaction_items(transaction_id,product_id,product_name,qty,price,cost)values(current_setting('test.nr.legacy')::bigint,-411005,'Notice Legacy B',4,22222,22222);
reset role;
update public.products set qty=qty+4 where id=-411005;
set local role authenticated;
set constraints solar_purchase_notice_header,solar_purchase_notice_items immediate;
set constraints solar_purchase_notice_header,solar_purchase_notice_items deferred;
do $$begin
 assert pg_temp.nr_count('purchase_received')=14,'Legacy second line duplicated receipt notice';
 assert pg_temp.nr_deliveries()=current_setting('test.nr.deliveryCount')::bigint,'Legacy second line duplicated push';
end$$;
reset role;
do $$begin
 assert exists(select 1 from public.solar_notifications n join solar_private.purchase_notice_recipients r on r.notification_id=n.id where r.invoice_id=current_setting('test.nr.legacy')::bigint and n.user_id='00000000-0000-0000-0000-000000411002'and jsonb_array_length(n.details->'items')=2),'Legacy materials not aggregated into same notice';
end$$;

\echo PASS legacy notices
-- Inbox metadata remains immutable; reading/marking owned notices still works.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411005',true);
do $$declare nid uuid;begin
 select id into nid from public.solar_notifications where event='purchase_received'limit 1;
 assert nid is not null,'Scoped warehouse cannot read safe materials';
 update public.solar_notifications set read_at=now()where id=nid;
 begin update public.solar_notifications set details='{"type":"purchase_received","items":[]}'where id=nid;raise exception 'Forged details accepted';exception when insufficient_privilege then null;end;
 begin update public.solar_notifications set user_id='00000000-0000-0000-0000-000000411006'where id=nid;raise exception 'Recipient reassignment accepted';exception when insufficient_privilege then null;end;
 begin update public.solar_notifications set warehouse_id=-411001 where id=nid;raise exception 'Forged scope accepted';exception when insufficient_privilege then null;end;
 assert not exists(select 1 from public.solar_notifications where event='wholesale_prices_updated'),'Warehouse sees price notices';
 assert not exists(select 1 from public.solar_notifications where user_id<>auth.uid()),'Notification owner RLS bypass';
end$$;
reset role;
insert into solar_private.warehouse_access(user_id,warehouse_ids)values('00000000-0000-0000-0000-000000411004','{-411001}');
update solar_private.warehouse_access set warehouse_ids='{-411001}'where user_id='00000000-0000-0000-0000-000000411005';
update public.profiles set permissions='{}'where id='00000000-0000-0000-0000-000000411011';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411005',true);
do $$begin assert not exists(select 1 from public.solar_notifications where event='purchase_received'),'Revoked warehouse access still reads arrivals';end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411011',true);
do $$begin assert not exists(select 1 from public.solar_notifications where event in('purchase_received','wholesale_prices_updated')),'Revoked role still reads operational notices';end$$;
reset role;
-- Drain bounded local fixture delivery batches; no push network service runs.
do $$declare batch jsonb;row jsonb;begin
 for attempt in 1..20 loop
  batch:=public.solar_push_claim();exit when jsonb_array_length(batch)=0;
  for row in select value from jsonb_array_elements(batch)loop
   if row->'notification'->>'event'in('purchase_received','wholesale_prices_updated')then
    assert not(row->'notification'?'details'),'Structured materials leaked into push payload';
    assert row->'notification'->>'userId'<>'00000000-0000-0000-0000-000000411011','Revoked pricing recipient got push';
    if row->'notification'->>'event'='purchase_received'then
     assert row->'notification'->>'userId'not in('00000000-0000-0000-0000-000000411004','00000000-0000-0000-0000-000000411005'),'Revoked warehouse scope got push';
    end if;
   end if;
  end loop;
 end loop;
 assert not has_column_privilege('authenticated','public.solar_notifications','details','UPDATE'),'New details update grant';
 assert not has_table_privilege('authenticated','solar_private.purchase_notice_sources','SELECT'),'Private marker exposed';
 assert not has_function_privilege('authenticated','solar_private.publish_purchase_notice(bigint,boolean)','EXECUTE'),'Emitter exposed';
end$$;
set constraints all immediate;
rollback;
\echo PASS V4.1 price changes/no-op/stale/replay; canonical and legacy purchase arrival dedupe; financial-detail redaction; warehouse/role recipient scopes; read-only metadata and revoked access/push filtering.
