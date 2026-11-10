-- Local disposable PostgreSQL only. All financial fixtures roll back.
\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,permissions,phone) values
('00000000-0000-0000-0000-000000400200','مدير حذف V4',true,'admin_staff','{}','07704002000'),
('00000000-0000-0000-0000-000000400201','صاحب الوصولات V4',false,'admin_staff','{"sale":true,"system":true,"purchase":true,"stock":true,"systemPayment":true,"cash":true,"installations":true}','07704002001'),
('00000000-0000-0000-0000-000000400202','مستخدم آخر V4',false,'admin_staff','{"sale":true,"purchase":true}','07704002002'),
('00000000-0000-0000-0000-000000400203','مخزن V4',true,'warehouse','{}','07704002003'),
('00000000-0000-0000-0000-000000400204','مهندس V4',true,'installer','{}','07704002004');
insert into customers(id,name,customer_type,owner_id) values
(-400201,'زبون جملة V4','wholesale','00000000-0000-0000-0000-000000400201'),
(-400202,'زبون منظومة V4','system','00000000-0000-0000-0000-000000400201');
insert into suppliers(id,name,account_currency) values(-400201,'مورد V4','IQD');
insert into products(id,code,name,qty,cost)values(-400201,'V4-DIRECT','مادة V4',100,100000);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values(1,-400201,100)on conflict(warehouse_id,product_id)do update set qty=excluded.qty;
insert into solar_cash_entries(owner_id,actor_id,delta,entry_type) values
('00000000-0000-0000-0000-000000400201','00000000-0000-0000-0000-000000400200',10000000,'transfer_in');

create function pg_temp.v4_invoice(kind text default 'sale',mode text default 'credit') returns bigint language plpgsql as $$
declare r jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000400201',true);
 r:=public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind',kind,'mode',mode,'partyId',case when kind='system'then -400202 else -400201 end,
 'party',case when kind='purchase'then 'مورد V4'when kind='system'then 'زبون منظومة V4'else 'زبون جملة V4'end,
 'total',500000,'customerAddress','بغداد','installerId','00000000-0000-0000-0000-000000400204',
 'items',jsonb_build_array(jsonb_build_object('id',-400201,'qty',2,'price',case when kind='purchase'then 100000 else 200000 end))));
 return(r->>'id')::bigint;end$$;
create function pg_temp.v4_hash() returns text language sql security definer as $$select md5(jsonb_build_array(
 (select jsonb_agg(to_jsonb(x)order by id)from transactions x),
 (select jsonb_agg(to_jsonb(x)order by id)from transaction_items x),
 (select jsonb_agg(to_jsonb(x)order by id)from products x),
 (select jsonb_agg(to_jsonb(x)order by warehouse_id,product_id)from solar_private.warehouse_stocks x),
 (select jsonb_agg(to_jsonb(x)order by id)from solar_cash_entries x),
 (select jsonb_agg(to_jsonb(x)order by id)from solar_private.supplier_fx_entries x),
 (select jsonb_agg(to_jsonb(x)order by invoice_id)from solar_private.deleted_sales x))::text)$$;
create function pg_temp.v4_stock() returns jsonb language sql security definer as $$select to_jsonb(p)from products p where id=-400201$$;
create function pg_temp.v4_direct(invoice_id bigint) returns jsonb language plpgsql as $$
declare c jsonb;result jsonb;nonce uuid:=gen_random_uuid();body jsonb;fingerprint text;actor uuid:=auth.uid();begin
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',invoice_id));
 assert(c->>'directEligible')::boolean,'Unexpected approval-only invoice: '||coalesce(c->>'directBlockedReason','?');
 assert c->>'deletionMode'='direct';
 body:=jsonb_build_object('invoiceId',invoice_id,'expectedToken',c->>'token');
 result:=public.solar_receipt_delete_requests('delete_direct',nonce,body);
 assert result->>'status'='deleted' and(result->>'direct')::boolean;
 fingerprint:=pg_temp.v4_hash();
 assert public.solar_receipt_delete_requests('delete_direct',nonce,body)=result,'Direct retry not idempotent';
 assert pg_temp.v4_hash()=fingerprint,'Direct retry changed financial records';
 begin perform public.solar_receipt_delete_requests('delete_direct',nonce,body||'{"reason":"different"}');raise exception 'Changed retry accepted';
 exception when sqlstate 'PT409'then null;end;
 begin perform public.solar_receipt_delete_requests('request',nonce,body);raise exception 'Direct request UUID reused as approval';
 exception when sqlstate 'PT409'then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000400202',true);
 begin perform public.solar_receipt_delete_requests('delete_direct',nonce,body);raise exception 'Foreign actor replayed deletion';
 exception when sqlstate 'PT409'then null;end;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 return result;end$$;
create function pg_temp.v4_expect_approval(invoice_id bigint) returns void language plpgsql as $$
declare c jsonb;b text;begin
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',invoice_id));
 assert not(c->>'directEligible')::boolean and c->>'deletionMode'='approval';
 assert c->>'directBlockedReason' is not null;
 b:=pg_temp.v4_hash();
 begin perform public.solar_receipt_delete_requests('delete_direct',gen_random_uuid(),jsonb_build_object('invoiceId',invoice_id,'expectedToken',c->>'token'));raise exception 'Acted-on invoice direct deletion accepted';
 exception when sqlstate 'PT409'then null;end;
 assert pg_temp.v4_hash()=b,'Rejected direct deletion partly changed accounting';
end$$;

-- Original save's cash, cost and stock postings are not subsequent operations.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000400201',true);
set local role authenticated;
do $$declare j bigint;c numeric;q numeric;before_requests jsonb;begin
 c:=solar_private.cash_balance('00000000-0000-0000-0000-000000400201');q:=(pg_temp.v4_stock()->>'qty')::numeric;
 j:=pg_temp.v4_invoice('sale','cash');assert solar_private.cash_balance(auth.uid())=c+400000;
 perform pg_temp.v4_direct(j);assert solar_private.cash_balance(auth.uid())=c;
 assert(pg_temp.v4_stock()->>'qty')::numeric=q,'Stock differs';
 j:=pg_temp.v4_invoice('system','credit');perform pg_temp.v4_direct(j);
 assert(pg_temp.v4_stock()->>'qty')::numeric=q,'Stock differs';
end$$;
reset role;
do $$begin
 assert(select count(*)from solar_private.receipt_delete_executions where actor_id='00000000-0000-0000-0000-000000400201'and mode='direct'and completed_at is not null)=2;
 assert not exists(select 1 from solar_private.receipt_delete_requests where owner_id='00000000-0000-0000-0000-000000400201'),'Direct deletion created approval requests';
end$$;

-- Purchase owner can cancel directly using the exact existing stock/value plan.
set local role authenticated;
do $$declare j bigint;q numeric;cost_before numeric;cash_before numeric;begin
 q:=(pg_temp.v4_stock()->>'qty')::numeric;cost_before:=(pg_temp.v4_stock()->>'cost')::numeric;cash_before:=solar_private.cash_balance('00000000-0000-0000-0000-000000400201');
 j:=pg_temp.v4_invoice('purchase','cash');perform pg_temp.v4_direct(j);
 assert(pg_temp.v4_stock()->>'qty')::numeric=q and(pg_temp.v4_stock()->>'cost')::numeric=cost_before;assert solar_private.cash_balance(auth.uid())=cash_before;
end$$;
reset role;

-- Partial warehouse activity remains disqualifying even after the state resets.
select set_config('test.v4.prepared',pg_temp.v4_invoice()::text,true);
update transactions set warehouse_revision=1,warehouse_note='تجهيز جزئي'where id=current_setting('test.v4.prepared')::bigint;
set local role authenticated;
select pg_temp.v4_expect_approval(current_setting('test.v4.prepared')::bigint);
reset role;

-- Real direct preparation, then owner approval request and administrator review.
set local role authenticated;
do $$declare j bigint;c jsonb;r jsonb;before_hash text;begin
 j:=pg_temp.v4_invoice();c:=public.solar_sale_preparation('get',j);
 perform public.solar_sale_preparation('ready',j,c->>'token',gen_random_uuid());perform pg_temp.v4_expect_approval(j);
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',j));
 r:=public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',j,'expectedToken',c->>'token'));
 assert r->>'status'='pending';
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000400200',true);
 begin perform public.solar_sale_delete(j,public.solar_sale_delete_preview(j)->>'token');raise exception 'Admin legacy approval bypass';exception when insufficient_privilege then null;end;
 c:=public.solar_receipt_delete_requests('get',(r->>'id')::uuid);
 r:=public.solar_receipt_delete_requests('approve',(r->>'id')::uuid,jsonb_build_object('expectedToken',c->>'reviewToken'));
 assert r->>'status'='approved';assert not exists(select 1 from transactions where id=j);
 before_hash:=pg_temp.v4_hash();perform public.solar_receipt_delete_requests('approve',(r->>'id')::uuid,'{}');assert pg_temp.v4_hash()=before_hash;
end$$;
reset role;

-- A linked payment blocks direct deletion; cancelling the payment does not erase
-- its persistent request history and cannot make the invoice pristine again.
set local role authenticated;
do $$declare j bigint;c jsonb;r jsonb;payment_id bigint;begin
 j:=pg_temp.v4_invoice('system');c:=public.solar_system_payment_context(-400202);
 r:=public.solar_system_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-400202,'invoiceId',j,'amount',100000,'mode','payment','expectedToken',c->>'token'));
 payment_id:=(r->>'id')::bigint;perform pg_temp.v4_expect_approval(j);
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',payment_id));
 r:=public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',payment_id,'expectedToken',c->>'token'));
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000400200',true);
 c:=public.solar_receipt_delete_requests('get',(r->>'id')::uuid);perform public.solar_receipt_delete_requests('approve',(r->>'id')::uuid,jsonb_build_object('expectedToken',c->>'reviewToken'));
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000400201',true);perform pg_temp.v4_expect_approval(j);
end$$;
reset role;

-- New explicit direct action is required even if a pending request exists.
set local role authenticated;
do $$declare j bigint;c jsonb;r jsonb;begin
 j:=pg_temp.v4_invoice();c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',j));
 r:=public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',j,'expectedToken',c->>'token'));
 assert exists(select 1 from transactions where id=j),'Request auto-executed';perform pg_temp.v4_direct(j);
 c:=public.solar_receipt_delete_requests('get',(r->>'id')::uuid);assert c->>'status'='cancelled';
end$$;
reset role;

-- Preview/action race: an edit after context rejects direct action atomically.
select set_config('test.v4.stale',pg_temp.v4_invoice()::text,true);
select set_config('test.v4.token',(public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',current_setting('test.v4.stale')::bigint))->>'token'),true);
update transactions set notes='تعديل لاحق'where id=current_setting('test.v4.stale')::bigint;
set local role authenticated;
do $$declare b text:=pg_temp.v4_hash();begin
 begin perform public.solar_receipt_delete_requests('delete_direct',gen_random_uuid(),jsonb_build_object('invoiceId',current_setting('test.v4.stale')::bigint,'expectedToken',current_setting('test.v4.token')));raise exception 'Stale direct delete accepted';exception when sqlstate 'PT409'then null;end;
 assert pg_temp.v4_hash()=b;end$$;
reset role;

-- Any downstream cancellation failure rolls back its permit, archive, balance
-- and stock changes; the identical request can then be safely retried.
select set_config('test.v4.failure',pg_temp.v4_invoice()::text,true);
create function pg_temp.v4_fail_delete()returns trigger language plpgsql as $$begin
 if old.id=current_setting('test.v4.failure')::bigint then raise exception 'V4 injected downstream failure';end if;return old;end$$;
create trigger v4_fixture_fail_delete before delete on transactions for each row execute function pg_temp.v4_fail_delete();
do $$declare c jsonb;body jsonb;nonce uuid:=gen_random_uuid();b text;begin
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',current_setting('test.v4.failure')::bigint));
 body:=jsonb_build_object('invoiceId',current_setting('test.v4.failure')::bigint,'expectedToken',c->>'token');b:=pg_temp.v4_hash();
 begin perform public.solar_receipt_delete_requests('delete_direct',nonce,body);raise exception 'Failure fixture did not run';
 exception when raise_exception then if sqlerrm<>'V4 injected downstream failure'then raise;end if;end;
 assert pg_temp.v4_hash()=b,'Failure partly cancelled financial state';
 assert not exists(select 1 from solar_private.receipt_delete_executions where request_id=nonce),'Failed execution left an authorization';
 perform set_config('test.v4.failure','0',true);
 assert public.solar_receipt_delete_requests('delete_direct',nonce,body)->>'status'='deleted';
end$$;
drop trigger v4_fixture_fail_delete on transactions;

-- Ownership and eligibility are server facts: client flags or GUCs cannot mint
-- a permit, and revoked users cannot submit a new direct deletion.
select set_config('test.v4.permissions',pg_temp.v4_invoice()::text,true);
set local role authenticated;
do $$declare c jsonb;begin
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',current_setting('test.v4.permissions')::bigint));
 perform set_config('solar.receipt_delete_authorized','true',true);
 begin perform public.solar_sale_delete((c->>'id')::bigint,public.solar_sale_delete_preview((c->>'id')::bigint)->>'token');raise exception 'Spoofed authorization';exception when insufficient_privilege then null;end;
 begin perform solar_private.receipt_delete_requests_v3102('approve',gen_random_uuid(),'{}');raise exception 'Legacy private dispatcher exposed';exception when insufficient_privilege then null;end;
end$$;
reset role;
update profiles set active=false where id='00000000-0000-0000-0000-000000400201';
set local role authenticated;
do $$begin
 begin perform public.solar_receipt_delete_requests('delete_direct',gen_random_uuid(),jsonb_build_object('invoiceId',current_setting('test.v4.permissions')::bigint,'expectedToken','ignored','directEligible',true));raise exception 'Inactive owner deleted';exception when insufficient_privilege then null;end;
end$$;
reset role;
update profiles set active=true where id='00000000-0000-0000-0000-000000400201';

-- Dedicated roles and foreign owners cannot read context or delete, even with a
-- leaked valid token or a stale is_admin flag. Clients cannot mint execution grants.
select set_config('test.v4.auth',pg_temp.v4_invoice()::text,true);
select set_config('test.v4.auth.token',(public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',current_setting('test.v4.auth')::bigint))->>'token'),true);
set local role authenticated;
do $$declare actor text;begin
 foreach actor in array array['00000000-0000-0000-0000-000000400202','00000000-0000-0000-0000-000000400203','00000000-0000-0000-0000-000000400204']loop
  perform set_config('request.jwt.claim.sub',actor,true);
  begin perform public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',current_setting('test.v4.auth')::bigint));raise exception 'Unauthorized context';exception when insufficient_privilege then null;end;
  begin perform public.solar_receipt_delete_requests('delete_direct',gen_random_uuid(),jsonb_build_object('invoiceId',current_setting('test.v4.auth')::bigint,'expectedToken',current_setting('test.v4.auth.token')));raise exception 'Unauthorized direct delete';exception when insufficient_privilege then null;end;
 end loop;
 begin insert into solar_private.receipt_delete_executions(request_id,invoice_id,actor_id,mode,submission,snapshot,execution_txid)values(gen_random_uuid(),1,auth.uid(),'direct','{}','{}',txid_current());raise exception 'Client minted execution';exception when insufficient_privilege then null;end;
 begin perform solar_private.receipt_delete_authorized(current_setting('test.v4.auth')::bigint);raise exception 'Client called private execution helper';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000400200',true);
 perform pg_temp.v4_direct(current_setting('test.v4.auth')::bigint);
end$$;
reset role;
set constraints all immediate;
rollback;
\echo PASS V4 direct owner/admin invoice cancellation, automatic creation postings, approved activity flow, durable payment history, old pending requests, replay/staleness and server role isolation
