-- Isolated projection of one closed legacy system. Positive and negative access checks use real authenticated entry points.
\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,username,display_name,active,is_admin,user_type,permissions,phone) values
('00000000-0000-0000-0000-000000412410','profit_admin_4124','مدير اختبار الربح',true,true,'admin_staff','{}','07700000000'),
('00000000-0000-0000-0000-000000412411','profit_seller_4124','البائع الأول',true,false,'admin_staff','{"system":true,"installations":true,"systemPayment":true,"profit":true}','07700000000'),
('00000000-0000-0000-0000-000000412412','profit_recipient_4124','مستلم الاختبار',true,false,'admin_staff','{"system":true,"installations":true,"systemPayment":true,"profit":true}','07700000000'),
('00000000-0000-0000-0000-000000412413','profit_peer_4124','موظف آخر',true,false,'admin_staff','{"system":true,"profit":true}','07700000000'),
('00000000-0000-0000-0000-000000412414','profit_engineer_4124','مهندس اختبار',true,false,'installer','{}','07700000000');
insert into public.customers(id,name,customer_type,owner_id) values(-412410,'ملف مراجعة ربح صناعي','system','00000000-0000-0000-0000-000000412411');
insert into public.products(id,code,name,category,qty,cost) values(-412410,'DP-FIX-A','لوح صناعي','ألواح',25,120000),(-412411,'DP-FIX-B','بطارية صناعية','بطارية',25,80000);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values(1,-412410,25),(1,-412411,25) on conflict(warehouse_id,product_id) do update set qty=excluded.qty;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412411',true);
select set_config('fixture.profit_id',(public.solar_invoice_save(gen_random_uuid(),
 '{"kind":"system","mode":"credit","partyId":-412410,"party":"ملف مراجعة ربح صناعي","warehouseId":1,"installerId":"00000000-0000-0000-0000-000000412414","customerAddress":"موقع تجريبي","total":1295000,"items":[{"id":-412410,"qty":3,"price":0},{"id":-412411,"qty":2,"price":0}]}')->>'id'),true);
do $$declare context jsonb;begin
 context:=public.solar_system_payment_context(-412410);
 perform public.solar_system_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-412410,'invoiceId',current_setting('fixture.profit_id')::bigint,'amount',90000,'mode','payment','notes','استلام تجريبي','expectedToken',context->>'token'));
end$$;
reset role;
update public.transactions set warehouse_status='ready' where id=current_setting('fixture.profit_id')::bigint;
update public.products set cost=990000 where id in(-412410,-412411);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412414',true);
select public.solar_installation_action(current_setting('fixture.profit_id')::bigint,0,'start');
select public.solar_installation_action(current_setting('fixture.profit_id')::bigint,1,'complete','{"checks":{"materials":true,"tested":true,"handover":true},"notes":"تم الفحص والتسليم","expenses":[]}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412411',true);
select public.solar_installation_action(current_setting('fixture.profit_id')::bigint,2,'close','{"amount":60000}');
reset role;
-- Configure custody and financial entitlement independently, as on an already-posted receipt.
update public.customers set owner_id='00000000-0000-0000-0000-000000412412' where id=-412410;
insert into solar_private.customer_receipt_responsibility(transaction_id,customer_id,owner_id,assigned_by,request_id)
 values(current_setting('fixture.profit_id')::bigint,-412410,'00000000-0000-0000-0000-000000412412','00000000-0000-0000-0000-000000412410',gen_random_uuid());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412412',true);
do $$begin
 begin perform public.solar_profit_detail('tx:'||current_setting('fixture.profit_id'));
 raise exception 'custody alone exposed attributed profit';exception when insufficient_privilege then null;end;
end$$;
reset role;
insert into solar_private.invoice_profit_owners(invoice_id,owner_id,updated_by)
 values(current_setting('fixture.profit_id')::bigint,'00000000-0000-0000-0000-000000412413','00000000-0000-0000-0000-000000412410');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412413',true);
do $$declare r jsonb;begin
 r:=public.solar_profit_workspace('overview');assert (r->>'available')::numeric=715000;
 assert exists(select 1 from jsonb_array_elements(r->'rows') e where e->>'receiptRestricted'='true' and nullif(e->>'receiptNo','') is null);
 r:=public.solar_profit_detail('tx:'||current_setting('fixture.profit_id'));
 assert r->'invoice'='null'::jsonb and (r->'breakdown' is null or r->'breakdown'='null'::jsonb),'profit alone must preserve redaction';
end$$;
reset role;
update solar_private.invoice_profit_owners set owner_id='00000000-0000-0000-0000-000000412412' where invoice_id=current_setting('fixture.profit_id')::bigint;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412412',true);
do $$declare d jsonb;b jsonb;w jsonb;v bigint:=current_setting('fixture.profit_id')::bigint;begin
 w:=public.solar_profit_workspace('overview');assert (w->>'available')::numeric=715000;
 d:=public.solar_profit_detail('tx:'||v);b:=d->'breakdown';
 assert jsonb_typeof(b)='object' and not coalesce((w->'rows'->0->>'receiptRestricted')::boolean,false),'dual-assigned receipt was still redacted';
 assert (b->>'sales')::numeric=1295000 and (b->>'materialsCost')::numeric=520000 and (b->>'grossProfit')::numeric=775000;
 assert (b->>'installationExpenses')::numeric=60000 and (b->>'netProfit')::numeric=715000;
 assert (b->>'profitAdjustment')::numeric=0,'installation payout was labeled again as a separate adjustment';
 assert jsonb_array_length(b->'items')=2,'detailed items missing';
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412410',true);
 w:=public.solar_pending_systems();
 perform set_config('fixture.company_pending',w#>>'{summary,provisionalProfit}',true);
 perform set_config('fixture.company_collections',w#>>'{summary,accountCollections}',true);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412412',true);
 perform public.solar_installation_action(v,3,'reopen');
 w:=public.solar_profit_workspace('overview');
 assert (w->>'available')::numeric=0 and jsonb_array_length(w->'rows')=0,'open work counted as final profit';
 w:=public.solar_pending_systems();
 assert jsonb_array_length(w->'assignedRows')=1,'dual-assigned open work missing';
 assert (w#>>'{summary,provisionalProfit}')::numeric=715000 and (w#>>'{summary,accountCollections}')::numeric=0;
 assert not (w->'assignedRows'->0 ?| array['balance','accountCollections','collected','cash','receiptCount']);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412411',true);
 w:=public.solar_pending_systems();
 assert (w#>>'{summary,provisionalProfit}')::numeric=0,'original seller still counted profit after an effective dual assignment';
 assert exists(select 1 from jsonb_array_elements(w->'rows') e where (e->>'id')::bigint=v
      and (e->>'profitAttributedElsewhere')::boolean and (e->>'provisionalProfit')::numeric=0 and (e->>'receiptProvisionalProfit')::numeric=715000);
 assert (w#>>'{summary,accountCollections}')::numeric=90000,'receipt collection left its actual recipient';
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412410',true);
 w:=public.solar_pending_systems();
 assert (w#>>'{summary,provisionalProfit}')::numeric-current_setting('fixture.company_pending')::numeric=715000,'company must see this profit only once';
 assert (w#>>'{summary,accountCollections}')::numeric-current_setting('fixture.company_collections')::numeric=90000;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412412',true);
 perform public.solar_installation_action(v,4,'close','{"amount":75000}');
 w:=public.solar_profit_workspace('overview');assert (w->>'available')::numeric=700000;
 d:=public.solar_profit_detail('tx:'||v);assert (d->'breakdown'->>'netProfit')::numeric=700000,'expense correction must be booked once';
 w:=public.solar_pending_systems();assert jsonb_array_length(w->'assignedRows')=0;
end$$;
reset role;
do $$declare i bigint:=current_setting('fixture.profit_id')::bigint;begin
 assert(select created_by='00000000-0000-0000-0000-000000412411'::uuid and cost=520000 and profit=700000 from transactions where id=i);
 assert(select -sum(delta)=60000 from solar_cash_entries where job_id=i and owner_id='00000000-0000-0000-0000-000000412411');
 assert(select -sum(delta)=15000 from solar_cash_entries where job_id=i and owner_id='00000000-0000-0000-0000-000000412412');
end$$;
-- Revoking the operating assignment must immediately restore receipt redaction and preserve the monetary entitlement.
update solar_private.customer_receipt_responsibility set owner_id='00000000-0000-0000-0000-000000412413' where transaction_id=current_setting('fixture.profit_id')::bigint;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412412',true);
do $$declare view jsonb;begin
 view:=public.solar_profit_workspace('overview');
 assert (view->>'available')::numeric=700000 and (view->'rows'->0->>'receiptRestricted')::boolean;
 view:=public.solar_profit_detail('tx:'||current_setting('fixture.profit_id'));assert view->'breakdown'='null'::jsonb;
end$$;
rollback;
