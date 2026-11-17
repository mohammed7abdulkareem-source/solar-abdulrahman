-- Disposable local V4.1.2 database. No production writes; all fixtures roll back.
\set ON_ERROR_STOP on
\o /dev/null
begin;
load 'safeupdate';
insert into public.profiles(id,display_name,is_admin,user_type,phone,active,permissions)values
('00000000-0000-0000-0000-000000412201','Privacy Administrator',true,'admin_staff','07700412201',true,'{}'),
('00000000-0000-0000-0000-000000412202','Privacy Account Owner',false,'admin_staff','07700412202',true,'{"customers":true,"customerStatement":true,"customerPayment":true,"systemPayment":true}'),
('00000000-0000-0000-0000-000000412203','SECRET OTHER SELLER',false,'admin_staff','07700412203',true,'{"customers":true,"customerStatement":true,"systemPayment":true}'),
('00000000-0000-0000-0000-000000412204','Privacy Warehouse',true,'warehouse','07700412204',true,'{}'),
('00000000-0000-0000-0000-000000412205','Privacy Installer',true,'installer','07700412205',true,'{}');
insert into public.customers(id,name,customer_type,owner_id)values
(-412201,'Privacy Shared Wholesale','wholesale','00000000-0000-0000-0000-000000412202'),
(-412202,'Privacy Shared Systems','system','00000000-0000-0000-0000-000000412202');
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_at,created_by,cashbox_user_id,notes)values
(-412211,'sale',-412201,'Privacy Shared Wholesale',500,false,'credit','2026-11-01 10:00Z','00000000-0000-0000-0000-000000412202','00000000-0000-0000-0000-000000412202','Own visible sale'),
(-412212,'sale',-412201,'Privacy Shared Wholesale',700,false,'credit','2026-11-02 10:00Z','00000000-0000-0000-0000-000000412203','00000000-0000-0000-0000-000000412203','SECRET FOREIGN CREDIT'),
(-412213,'sale',-412201,'Privacy Shared Wholesale',7654321,true,'cash','2026-11-03 10:00Z','00000000-0000-0000-0000-000000412201','00000000-0000-0000-0000-000000412201','SECRET FOREIGN CASH'),
(-412214,'customer_payment',-412201,'Privacy Shared Wholesale',100,true,'payment','2026-11-04 10:00Z','00000000-0000-0000-0000-000000412203','00000000-0000-0000-0000-000000412203','SECRET FOREIGN PAYMENT'),
(-412215,'customer_payment',-412201,'Privacy Shared Wholesale',-200,false,'opening_balance','2026-10-31 10:00Z','00000000-0000-0000-0000-000000412201','00000000-0000-0000-0000-000000412201','SECRET ADMIN OPENING'),
(-412216,'system',-412202,'Privacy Shared Systems',6000,false,'credit','2026-11-01 10:00Z','00000000-0000-0000-0000-000000412202','00000000-0000-0000-0000-000000412202','Own system'),
(-412217,'system',-412202,'Privacy Shared Systems',9000,false,'credit','2026-11-02 10:00Z','00000000-0000-0000-0000-000000412201','00000000-0000-0000-0000-000000412201','SECRET FOREIGN SYSTEM');
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_at,created_by,cashbox_user_id,notes)
values(-412219,'customer_payment',-412201,'Privacy Shared Wholesale',100,true,'payment','2026-11-05 10:00Z','00000000-0000-0000-0000-000000412201','00000000-0000-0000-0000-000000412202','SECRET ADMIN CASHBOX PAYMENT');
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_at,created_by,cashbox_user_id,system_invoice_id,notes)
values(-412218,'system_payment',-412202,'Privacy Shared Systems',100,true,'payment','2026-11-03 10:00Z','00000000-0000-0000-0000-000000412202','00000000-0000-0000-0000-000000412202',-412217,'Own allocated payment');
create function pg_temp.raw_ledger(cid bigint)returns jsonb language sql security definer set search_path=''as $$select solar_private.customer_ledger(cid)$$;
create function pg_temp.raw_system(cid bigint)returns jsonb language sql security definer set search_path=''as $$select solar_private.system_payment_context(cid)$$;
create function pg_temp.raw_customer(cid bigint)returns jsonb language sql security definer set search_path=''as $$select to_jsonb(c)from public.customers c where id=cid$$;
create temporary table original_financial as select id,to_jsonb(t)row from public.transactions t where id between -412219 and -412211;
create temporary table original_ledger as select cid,solar_private.customer_ledger(cid)rows from(values(-412201::bigint),(-412202::bigint))c(cid);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412202',true);
do $$declare a jsonb;s jsonb;raw jsonb;r jsonb;row jsonb;before numeric;req uuid:=gen_random_uuid();payload jsonb;receipt jsonb;begin
 raw:=pg_temp.raw_ledger(-412201);a:=public.solar_customer_get(-412201);s:=public.solar_customer_statement(-412201);
 assert(a->>'balance')::numeric=1200 and(s->>'balance')::numeric=1200,'Customer balance lost foreign account effects';
 assert(a->>'openingBalance')::numeric=200 and(a->>'openingCount')::integer=1,'Opening metadata changed';
 assert a->>'token'=md5(pg_temp.raw_customer(-412201)::text||raw::text)and s->>'token'=md5(raw::text),'Read redaction changed raw concurrency token';
 assert a->'rows'=s->'rows'and a->'rows'=public.solar_customer_get(-412201)->'rows','Projection unstable';
 assert jsonb_array_length(a->'rows')=jsonb_array_length(raw),'Projection omitted an account effect';
 assert(select sum((x->>'effect')::numeric)from jsonb_array_elements(a->'rows')x)=1200,'Projected effects do not reconcile';
 assert not(a::text~'SECRET|7654321|-412212|-412213|-412214|-412215'),'Foreign identifying/full cash-sale data leaked';
 for row in select value from jsonb_array_elements(a->'rows')where value->'receiptRestricted'='true'::jsonb loop
  assert row-array['id','date','effect','kind','mode','receiptRestricted']='{}'::jsonb,'Unexpected restricted-row fields';
  assert row->>'id'like'restricted:%'and length(row->>'id')=43,'Missing stable opaque identity';
 end loop;
 assert(select count(*)from jsonb_array_elements(a->'rows')x where x->'receiptRestricted'='true'::jsonb)=5,'Foreign rows not marked';
 assert exists(select 1 from jsonb_array_elements(a->'rows')x where x->>'id'='-412211'and x->>'notes'='Own visible sale'),'Own row changed';
 r:=public.solar_customer_payment_manage('list',null,'{"customerId":-412201}');
 assert jsonb_array_length(r->'rows')=0,'Payment manager list leaked foreign creator receipts';
 r:=public.solar_customer_payment_manage('list',null,'{"customerId":-412201,"query":"SECRET"}');
 assert jsonb_array_length(r->'rows')=0,'Payment manager search probed foreign private metadata';
 begin perform public.solar_customer_payment_manage('get',null,'{"id":-412219}');raise exception 'Cashbox ownership exposed another creator payment';exception when insufficient_privilege then null;end;
 r:=public.solar_customer_invoice_report_batch(-412201,array[-412211,-412212],a->>'token');
 assert jsonb_array_length(r->'rows')=1 and r->'rows'->0->>'id'='-412211','Batch rejected original token or leaked foreign invoice';
 begin perform public.solar_customer_movement(-412201,-412212);raise exception 'Foreign original document leaked';exception when insufficient_privilege then null;end;
 a:=public.solar_customer_get(-412202);
 row:=(select x from jsonb_array_elements(a->'rows')x where x->>'id'='-412218');
 assert not(row?'systemInvoiceId'or row?'systemReceiptNo'),'Own payment exposed foreign linked receipt';
 r:=public.solar_customer_movement(-412202,-412218);
 assert r->'receipt'->'invoice'='null'::jsonb and r->'movement'->>'label'='تسديد','Own original payment label exposed foreign system receipt';
 r:=public.solar_payment_history('get','{"id":-412218}');
 assert r->'receipt'->'invoice'='null'::jsonb,'Payment history foreign linked copy leaked';
 a:=public.solar_system_payment_context(-412202);raw:=pg_temp.raw_system(-412202);
 assert a->>'token'=raw->>'token'and a->'balance'=raw->'balance'and a->'unallocated'=raw->'unallocated','System context changed accounting token or balance';
 assert jsonb_array_length(a->'systems')=1 and a->'systems'->0->>'id'='-412216'and(a->>'restrictedSystemCount')::integer=1,'Foreign system offered as allocation choice';
 assert not(a::text~'SECRET|-412217'),'System context leaked foreign system identity';
 before:=(a->>'balance')::numeric;
 -- Existing allocation validation remains valid for a known linked invoice;
 -- the outward receipt and identical retry do not disclose that invoice.
 payload:=jsonb_build_object('customerId',-412202,'invoiceId',-412217,'amount',25,'mode','payment','notes','Own payment privacy regression','expectedToken',a->>'token');
 receipt:=public.solar_system_payment_save(req,payload);
 assert(receipt->>'remaining')::numeric=before-25,'System payment accounting changed';
 assert receipt->'invoice'='null'::jsonb and receipt->'systemInvoiceId'='null'::jsonb and receipt->'invoiceBefore'='null'::jsonb and receipt->'invoiceAfter'='null'::jsonb and receipt->'linkedReceiptRestricted'='true'::jsonb,'Foreign allocation details leaked from save';
 assert not(receipt::text~'SECRET|-412217'),'Save accountContext leaked foreign system';
 assert receipt=public.solar_system_payment_save(req,payload),'Cached retry bypassed projection or changed receipt';
 assert(public.solar_system_payment_context(-412202)->>'balance')::numeric=before-25,'Retry duplicated payment';
 perform set_config('test.customerprivacy.request',req::text,true);
 perform set_config('test.customerprivacy.payment',receipt->>'id',true);
 -- The unchanged original token still authorizes normal general account payment.
 a:=public.solar_customer_payment_context(-412201);
 r:=public.solar_customer_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-412201,'amount',25,'mode','payment','notes','Own general payment','expectedToken',a->>'token'));
 assert(r->>'remaining')::numeric=1175,'Wholesale general account payment broke';
 receipt:=public.solar_customer_payment_manage('get',null,jsonb_build_object('id',r->'id'));
 assert(receipt->>'total')::numeric=25 and receipt->>'notes'='Own general payment','Own payment detail was restricted';
 receipt:=public.solar_customer_payment_manage('list',null,'{"customerId":-412201}');
 assert jsonb_array_length(receipt->'rows')=1 and receipt->'rows'->0->>'id'=r->>'id','Own payment list changed';
 begin perform solar_private.system_payment_context(-412202);raise exception 'Raw private context exposed';exception when insufficient_privilege then null;end;
 begin perform solar_private.system_payment_save_v411(req,payload);raise exception 'Raw private replay exposed';exception when insufficient_privilege then null;end;
end$$;
reset role;
do $$declare cached jsonb;begin
 assert not exists(select 1 from original_financial b join public.transactions t on t.id=b.id where b.row<>to_jsonb(t)),'Original financial receipt changed';
 assert exists(select 1 from public.transactions where id=current_setting('test.customerprivacy.payment')::bigint and system_invoice_id=-412217 and total=25),'Original allocation write lost';
 select response into cached from solar_private.system_payment_requests where request_id=current_setting('test.customerprivacy.request')::uuid;
 assert cached->'invoice'->>'id'='-412217'and cached->'systemInvoiceId'='-412217'::jsonb,'Stored accounting snapshot was redacted';
 assert not has_function_privilege('authenticated','solar_private.customer_ledger_read_projection(jsonb,bigint)','EXECUTE'),'Arbitrary ledger projection exposed';
 assert not has_function_privilege('anon','public.solar_system_payment_context(bigint)','EXECUTE'),'Anonymous public context allowed';
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412201',true);
do $$declare a jsonb;begin
 a:=public.solar_customer_statement(-412201);assert a->'rows'=pg_temp.raw_ledger(-412201),'Admin statement changed';
 a:=public.solar_customer_payment_manage('get',null,'{"id":-412219}');assert(a->>'total')::numeric=100,'Admin foreign payment detail restricted';
 a:=public.solar_system_payment_context(-412202);assert a->'systems'=pg_temp.raw_system(-412202)->'systems','Admin system allocation choices changed';
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412203',true);
do $$begin begin perform public.solar_customer_get(-412201);raise exception 'Other customer owner scope bypass';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412204',true);
do $$begin begin perform public.solar_system_payment_context(-412202);raise exception 'Warehouse stale admin bypass';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412205',true);
do $$begin begin perform public.solar_customer_statement(-412201);raise exception 'Installer stale admin bypass';exception when insufficient_privilege then null;end;end$$;
reset role;
set constraints all immediate;
rollback;
\echo PASS customer receipt privacy: effect-only shared ledgers, raw tokens and balances preserved, own docs/admin unchanged, foreign allocations hidden, save/replay metadata scrubbed without changing stored snapshots or accounting, strict scoped ACLs.
