-- Isolated regression fixtures only. Run against a local database; never production.
\set ON_ERROR_STOP on
begin;
-- Reuse the same financial assertions against both cancellation entrypoints.
\if :{?direct_mode}
select set_config('test.cancel.direct_mode',:'direct_mode',true);
\else
select set_config('test.cancel.direct_mode','false',true);
\endif
insert into profiles(id,display_name,is_admin,user_type,permissions,phone) values
('00000000-0000-0000-0000-000000003990','مدير إلغاء الشراء',true,'admin_staff','{}','07700003990'),
('00000000-0000-0000-0000-000000003991','صاحب شراء الاختبار',false,'admin_staff','{"purchase":true,"sale":true,"cash":true,"stock":true,"supplierPayment":true,"supplierStatement":true,"exchangeRateEdit":true}','07700003991'),
('00000000-0000-0000-0000-000000003992','مستخدم آخر',false,'admin_staff','{"purchase":true}','07700003992'),
('00000000-0000-0000-0000-000000003993','مخزن بصلاحية قديمة',true,'warehouse','{}','07700003993');
insert into suppliers(id,name,account_currency) values(-399001,'مورد إلغاء دينار','IQD'),(-399002,'مورد إلغاء دولار','USD');
insert into customers(id,name,customer_type,owner_id) values(-399001,'عميل إلغاء الشراء','wholesale','00000000-0000-0000-0000-000000003991');
insert into products(id,code,name,qty,cost)
select -399000-n,'VOID-V399-'||n,'مادة إلغاء '||n,case when n in(1,2,3,6,10)then 10 else 0 end,case when n in(1,2,3,6,10)then 1000 else 0 end from generate_series(1,17)n;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003990',true);
select public.solar_exchange_rate_set(1500,(public.solar_exchange_rate_get()->>'revision')::bigint);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003991","mode":"deposit","currency":"IQD","amount":10000000,"note":"رصيد اختبار معزول"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003991","mode":"deposit","currency":"USD","amount":1000,"rate":1500,"note":"دولار اختبار معزول"}');

create function pg_temp.finance_hash() returns text language sql security definer set search_path='' as $$
select md5(jsonb_build_array(
 (select jsonb_agg(to_jsonb(t)order by id)from public.transactions t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.transaction_items t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.products t),
 (select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),
 (select jsonb_agg(to_jsonb(t)order by id)from solar_private.supplier_fx_entries t),
 (select jsonb_agg(to_jsonb(t)order by id)from solar_private.wallet_fx_entries t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.solar_cash_entries t),
 (select jsonb_agg(to_jsonb(t)order by invoice_id)from solar_private.deleted_sales t))::text)$$;

create function pg_temp.buy(product_id bigint,quantity numeric,price numeric,source_currency text default 'IQD',mode text default 'credit',cash_currency text default 'IQD',expenses numeric default 0)
returns bigint language plpgsql as $$declare result jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003991',true);
 result:=public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','purchase','mode',mode,'partyId',case when source_currency='USD'then -399002 else -399001 end,
 'party',case when source_currency='USD'then 'مورد إلغاء دولار'else 'مورد إلغاء دينار'end,'warehouseId',solar_private.primary_warehouse(),
 'sourceCurrency',source_currency,'cashCurrency',cash_currency,'exchangeRate',case when source_currency='USD'then 1500 else 1 end,'marketRate',1500,'accountRevision',0,'expenses',expenses,
 'items',jsonb_build_array(jsonb_build_object('id',product_id,'qty',quantity,'price',price))));return(result->>'id')::bigint;end$$;
create function pg_temp.sell(product_id bigint,quantity numeric,price numeric default 500000) returns bigint language plpgsql as $$declare result jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003991',true);
 result:=public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','sale','mode','credit','partyId',-399001,'party','عميل إلغاء الشراء','warehouseId',solar_private.primary_warehouse(),
 'items',jsonb_build_array(jsonb_build_object('id',product_id,'qty',quantity,'price',price))));return(result->>'id')::bigint;end$$;
create function pg_temp.request_cancel(invoice_id bigint) returns uuid language plpgsql as $$declare context jsonb;result jsonb;nonce uuid:=gen_random_uuid();body jsonb;before_hash text;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003991',true);before_hash:=pg_temp.finance_hash();
 context:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',invoice_id));
 body:=jsonb_build_object('invoiceId',invoice_id,'expectedToken',context->>'token');
 result:=public.solar_receipt_delete_requests('request',nonce,body);
 assert public.solar_receipt_delete_requests('request',nonce,body)=result,'Request retry differs';
 assert before_hash=pg_temp.finance_hash(),'Request changed financial records';return(result->>'id')::uuid;end$$;
create function pg_temp.approve_cancel(request_id uuid) returns void language plpgsql as $$declare detail jsonb;result jsonb;before_hash text;nonce uuid:=gen_random_uuid();body jsonb;target_id bigint;begin
 if current_setting('test.cancel.direct_mode',true)='true' then
  select invoice_id into target_id from solar_private.receipt_delete_requests where id=request_id;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003991',true);
  detail:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',target_id));
  assert(detail->>'directEligible')::boolean,'Safe purchase not directly cancellable';
  body:=jsonb_build_object('invoiceId',target_id,'expectedToken',detail->>'token');
  result:=public.solar_receipt_delete_requests('delete_direct',nonce,body);
  assert result->>'status'='deleted';before_hash:=pg_temp.finance_hash();
  assert public.solar_receipt_delete_requests('delete_direct',nonce,body)=result,'Direct cancellation retry differs';
  assert pg_temp.finance_hash()=before_hash,'Repeated direct cancellation changed finances';
  assert(select status from solar_private.receipt_delete_requests where id=request_id)='cancelled','Old request silently approved';
  return;
 end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003990',true);
 detail:=public.solar_receipt_delete_requests('get',request_id);
 result:=public.solar_receipt_delete_requests('approve',request_id,jsonb_build_object('expectedToken',detail->>'reviewToken'));
 assert result->>'status'='approved','Approval failed';before_hash:=pg_temp.finance_hash();
 assert public.solar_receipt_delete_requests('approve',request_id,jsonb_build_object('expectedToken',detail->>'reviewToken'))=result,'Approval retry differs';
 assert pg_temp.finance_hash()=before_hash,'Repeated approval changed finances';end$$;
create function pg_temp.blocked_cancel(request_id uuid) returns void language plpgsql as $$declare detail jsonb;before_hash text;blocked boolean:=false;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003990',true);
 detail:=public.solar_receipt_delete_requests('get',request_id);before_hash:=pg_temp.finance_hash();
 begin perform public.solar_receipt_delete_requests('approve',request_id,jsonb_build_object('expectedToken',detail->>'reviewToken'));
 exception when sqlstate 'PT409' or sqlstate 'P0001' then blocked:=true;end;
 assert blocked,'Unsafe purchase cancellation accepted';assert pg_temp.finance_hash()=before_hash,'Rejected cancellation partly changed finances';
 assert(select status from solar_private.receipt_delete_requests where id=request_id)='pending','Rejected cancellation lost pending request';end$$;

-- This isolated harness simulates core persistence around the private ledger helpers.
-- It tests accounting integration only; core replay/profit tests are separate.
create function pg_temp.correct_ledger(invoice_id bigint,new_total numeric,new_source numeric)
returns jsonb language plpgsql as $$
declare t public.transactions; items jsonb; rid uuid:=gen_random_uuid(); result jsonb; line record; unit numeric; oldtotal numeric;
begin
 select * into t from public.transactions where id=invoice_id;
 select jsonb_agg(to_jsonb(i)order by id) into items from public.transaction_items i where transaction_id=t.id;
 insert into solar_private.purchase_originals(invoice_id,invoice,items)values(t.id,to_jsonb(t),items)on conflict do nothing;
 insert into solar_private.purchase_corrections(request_id,invoice_id,actor_id,before_invoice,before_items,plan)values(rid,t.id,auth.uid(),to_jsonb(t),items,'{}');
 result:=solar_private.purchase_correction_ledger_apply(rid,t.id,jsonb_build_object('total',new_total,'expenses',0,'sourceSubtotal',new_source));
 update public.transactions set total=new_total,expenses=0,source_subtotal=new_source,account_amount=(result->'after'->>'accountAmount')::numeric,cash_amount=(result->'after'->>'cashAmount')::numeric where id=t.id;
 for line in select * from public.transaction_items where transaction_id=t.id loop
  unit:=new_total/line.qty;
  update public.products set cost=round((qty*cost+new_total-t.total)/qty,6),cost_basis=jsonb_build_object('currencyComponents',jsonb_build_object('usd',case when t.source_currency='USD'then new_source/line.qty else 0 end,'iqd',case when t.source_currency='USD'then 0 else unit end),'unitCost',unit)where id=line.product_id;
  update public.transaction_items set price=unit,landed_cost=unit,source_price=new_source/line.qty where id=line.id;
 end loop;
 update solar_private.purchase_corrections c set after_invoice=(select to_jsonb(x)from public.transactions x where x.id=t.id),after_items=(select jsonb_agg(to_jsonb(x)order by id)from public.transaction_items x where x.transaction_id=t.id)where c.request_id=rid;
 return result||jsonb_build_object('requestId',rid);
end$$;

-- Later supplier payments and original entry remain byte-for-byte unchanged.
do $$
declare v_invoice bigint; original jsonb; eid bigint; payment jsonb; result jsonb; later_id bigint; begin
 v_invoice:=pg_temp.buy(-399004,2,1000);
 select e.id,to_jsonb(e)into eid,original from solar_private.supplier_fx_entries e where transaction_id=v_invoice;
 result:=public.solar_fx('payment',gen_random_uuid(),jsonb_build_object('paymentId',-399900,'supplierId',-399001,'amount',500,'currency','IQD','cashCurrency','IQD','rate',1500,'accountRevision',0,'mode','cash','note','later supplier payment'));
 select to_jsonb(e)into payment from solar_private.supplier_fx_entries e where supplier_id=-399001 order by e.id desc limit 1;
 result:=pg_temp.correct_ledger(v_invoice,3000,3000);
 assert(select to_jsonb(e)from solar_private.supplier_fx_entries e where e.id=eid)=original,'Original supplier entry changed';
 assert exists(select 1 from solar_private.supplier_fx_entries e where to_jsonb(e)=payment),'Later supplier payment changed';
 assert(result->>'supplierDelta')::numeric=1000;
 assert(solar_private.purchase_correction_ledger_totals(v_invoice)->>'supplierDelta')::numeric=3000;
 assert(result->'after'->>'cashAmount')::numeric=0;
 assert exists(select 1 from jsonb_array_elements(public.solar_fx('statement',null,jsonb_build_object('supplierId',-399001))->'rows')r where (r->>'transaction_id')::bigint=v_invoice and(r->>'ledgerAmount')::numeric=2000 and(r#>>'{transaction,account_amount}')::numeric=3000 and(r#>>'{originalTransaction,account_amount}')::numeric=2000 and(r#>>'{originalItems,0,price}')::numeric=1000),'Supplier original ledger amount lost immutable value';
 assert exists(select 1 from jsonb_array_elements(public.solar_fx('statement',null,jsonb_build_object('supplierId',-399001))->'rows')r where r->>'id'=result->>'supplierEntryId'and r->>'note' like 'تصحيح شراء #%'),'Supplier correction mislabeled cancellation';
end$$;

-- IQD keeps the original dated cash debit; both corrections append differences.
do $$
declare v_invoice bigint; original jsonb; before_balance numeric; result jsonb; original_cash jsonb; nonce uuid; archive jsonb; begin
 before_balance:=solar_private.cash_balance('00000000-0000-0000-0000-000000003991');
 v_invoice:=pg_temp.buy(-399009,2,1000,'IQD','cash');
 -- Historical fixture timestamp, set before first correction snapshot.
 perform set_config('solar.fx_context','{"accountRevision":0,"marketRate":1500,"cashCurrency":"IQD"}',true);
 update public.transactions set created_at=now()-interval '7 days' where id=v_invoice;
 perform set_config('solar.fx_context','',true);
 update solar_private.supplier_fx_entries set created_at=now()-interval '7 days' where transaction_id=v_invoice;
 select to_jsonb(m)into original_cash from solar_private.cash_movements()m where m.id='tx:'||v_invoice;
 result:=pg_temp.correct_ledger(v_invoice,3000,3000);
 assert(result->>'cashDelta')::numeric=-1000;
 assert(select created_at from solar_private.wallet_fx_entries where id=(result->>'walletEntryId')::bigint)>(original_cash->>'created_at')::timestamptz,'Correction was backdated';
 assert(select to_jsonb(m)from solar_private.cash_movements()m where m.id='tx:'||v_invoice)=original_cash,'Original dated IQD cash debit changed';
 result:=pg_temp.correct_ledger(v_invoice,1000,1000);
 assert(result->>'cashDelta')::numeric=2000;
 assert(solar_private.cash_movement_detail('tx:'||v_invoice)->>'amount')::numeric=2000;
 assert(solar_private.cash_movement_detail('tx:'||v_invoice)#>>'{items,0,total}')::numeric=2000,'Original cash detail showed corrected line amount';
 assert(select total from public.transactions where id=v_invoice)=1000,'Live purchase total was frozen with cash projection';
 assert exists(select 1 from jsonb_array_elements(public.solar_fx('statement',null,jsonb_build_object('supplierId',-399001))->'rows')r where (r->>'transaction_id')::bigint=v_invoice and(r->>'ledgerAmount')::numeric=2000 and(r->>'delta')::numeric=0),'Cash purchase statement lost original bill amount';
 assert solar_private.cash_balance('00000000-0000-0000-0000-000000003991')=before_balance-1000;
 assert(select sum(delta)from solar_private.cash_movements()where owner_id='00000000-0000-0000-0000-000000003991'and currency='IQD')=before_balance-1000,'Cash projections disagree';
 perform pg_temp.approve_cancel(pg_temp.request_cancel(v_invoice));
 assert solar_private.cash_balance('00000000-0000-0000-0000-000000003991')=before_balance,'Corrected IQD cancellation refund incorrect';
 select invoice->'purchaseCancellation'into archive from solar_private.deleted_sales where invoice_id=v_invoice;
 assert(archive->>'cashRefund')::numeric=1000;
 assert exists(select 1 from solar_private.cash_movements()m where m.id='fx:'||(archive#>>'{walletEntry,id}')and m.delta=-2000 and m.created_at=(original_cash->>'created_at')::timestamptz),'Original IQD dated debit lost on cancellation';
 assert(select delta from solar_private.wallet_fx_entries where id=(archive->>'walletReversalId')::bigint)=1000,'Cancellation did not reverse aggregate';
end$$;

-- USD extra debit consumes present weighted wallet book; later refund uses only
-- this purchase cumulative assigned book. Existing gains and deposits never move.
do $$
declare v_invoice bigint; before_wallet jsonb; current_wallet jsonb; original jsonb; wid bigint; result jsonb; extra_book numeric; assigned_book numeric; deposit jsonb; begin
 before_wallet:=solar_private.usd_wallet('00000000-0000-0000-0000-000000003991');
 v_invoice:=pg_temp.buy(-399011,1,100,'USD','cash','USD');
 select w.id,to_jsonb(w)into wid,original from solar_private.wallet_fx_entries w where transaction_id=v_invoice;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003990',true);
 perform public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003991","mode":"deposit","currency":"USD","amount":200,"rate":1700,"note":"later USD deposit"}');
 select to_jsonb(w)into deposit from solar_private.wallet_fx_entries w where owner_id='00000000-0000-0000-0000-000000003991' order by w.id desc limit 1;
 perform public.solar_exchange_rate_set(1700,(public.solar_exchange_rate_get()->>'revision')::bigint);
 current_wallet:=solar_private.usd_wallet('00000000-0000-0000-0000-000000003991');
 extra_book:=round(50*(current_wallet->>'book')::numeric/(current_wallet->>'amount')::numeric,2);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003991',true);
 result:=pg_temp.correct_ledger(v_invoice,225000,150);
 assert(result->>'cashDelta')::numeric=-50 and(result->>'cashBookDelta')::numeric=-extra_book,'USD correction used wrong book rate';
 assert(select to_jsonb(w)from solar_private.wallet_fx_entries w where w.id=wid)=original,'Original USD entry/gain changed';
 assigned_book:=150000+extra_book;
 result:=pg_temp.correct_ledger(v_invoice,120000,80);
 assert(result->>'cashDelta')::numeric=70 and(result->>'cashBookDelta')::numeric=round(70*assigned_book/150,2),'USD refund used unrelated wallet book';
 assert exists(select 1 from solar_private.wallet_fx_entries w where to_jsonb(w)=deposit),'Later USD deposit changed';
 perform pg_temp.approve_cancel(pg_temp.request_cancel(v_invoice));
 current_wallet:=solar_private.usd_wallet('00000000-0000-0000-0000-000000003991');
 assert(current_wallet->>'amount')::numeric=(before_wallet->>'amount')::numeric+200,'USD aggregate cancellation amount incorrect';
 assert(current_wallet->>'book')::numeric=(before_wallet->>'book')::numeric+340000,'USD aggregate cancellation book incorrect';
 assert(select to_jsonb(w)-'transaction_id'from solar_private.wallet_fx_entries w where w.id=wid)=original-'transaction_id','Cancellation rewrote original USD gain';
end$$;

-- Availability already excludes reservations: do not subtract reserved stock twice.
do $$
declare v_invoice bigint; target bigint; transfer uuid:=gen_random_uuid(); pending jsonb; begin
 v_invoice:=pg_temp.buy(-399010,2,1000);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003990',true);
 target:=(public.solar_inventory('warehouse_save',gen_random_uuid(),'{"name":"reservation availability ledger fixture"}')->>'id')::bigint;
 perform public.solar_inventory('transfer',transfer,jsonb_build_object('fromId',solar_private.primary_warehouse(),'toId',target,'items',jsonb_build_array(jsonb_build_object('productId',-399010,'qty',6,'revision',(select revision from solar_private.warehouse_stocks where warehouse_id=solar_private.primary_warehouse()and product_id=-399010)))));
 select to_jsonb(s)into pending from solar_private.stock_transfers s where s.id=transfer;
 assert(select qty=6 and reserved_qty=6 from solar_private.warehouse_stocks where warehouse_id=solar_private.primary_warehouse()and product_id=-399010);
 perform pg_temp.approve_cancel(pg_temp.request_cancel(v_invoice));
 assert(select qty=4 and reserved_qty=6 from solar_private.warehouse_stocks where warehouse_id=solar_private.primary_warehouse()and product_id=-399010),'Reservation availability double-subtracted or reservation lost';
 assert(select to_jsonb(s)from solar_private.stock_transfers s where s.id=transfer)=pending,'Pending transfer changed';
end$$;

-- Correction execution proof rejects immutable routing edits and duplicate apply;
-- both rejected attempts leave the append-only ledgers unchanged.
do $$declare v_invoice bigint; t public.transactions; items jsonb; rid uuid:=gen_random_uuid(); result jsonb; blocked boolean:=false; before_hash text; begin
 v_invoice:=pg_temp.buy(-399015,1,1000);
 select * into t from public.transactions where id=v_invoice;
 select jsonb_agg(to_jsonb(i)order by id)into items from transaction_items i where transaction_id=v_invoice;
 before_hash:=pg_temp.finance_hash();
 begin
  insert into solar_private.purchase_originals(invoice_id,invoice,items)values(t.id,to_jsonb(t),items);
  insert into solar_private.purchase_corrections(request_id,invoice_id,actor_id,before_invoice,before_items,plan)values(rid,t.id,auth.uid(),to_jsonb(t),items,'{}');
  result:=solar_private.purchase_correction_ledger_apply(rid,t.id,'{"total":2000,"expenses":0,"sourceSubtotal":2000}');
  update transactions set party_id=-399002,total=2000,source_subtotal=2000,account_amount=2000,cash_amount=0 where id=t.id;
 exception when sqlstate 'PT409' then blocked:=true;end;
 assert blocked,'Proof allowed original supplier change';
 assert pg_temp.finance_hash()=before_hash,'Rejected correction changed finance';
 result:=pg_temp.correct_ledger(v_invoice,2000,2000);before_hash:=pg_temp.finance_hash();blocked:=false;
 begin perform solar_private.purchase_correction_ledger_apply((result->>'requestId')::uuid,v_invoice,'{"total":2000,"expenses":0,"sourceSubtotal":2000}');
 exception when sqlstate '42501' or sqlstate 'PT409' then blocked:=true;end;
 assert blocked and pg_temp.finance_hash()=before_hash,'Duplicate apply changed finance';
end$$;

-- The cashbox owner may see a financial effect without gaining access to a
-- foreign creator receipt; detached correction entries retain that linkage.
do $$declare v_invoice bigint; result jsonb; row_data jsonb; entry_id bigint; begin
 v_invoice:=pg_temp.buy(-399013,1,1000,'IQD','cash');
 perform set_config('solar.fx_context','{"accountRevision":0,"marketRate":1500,"cashCurrency":"IQD"}',true);
 update transactions set created_by='00000000-0000-0000-0000-000000003992' where id=v_invoice;
 perform set_config('solar.fx_context','',true);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003990',true);
 result:=pg_temp.correct_ledger(v_invoice,2000,2000);entry_id:=(result->>'walletEntryId')::bigint;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003991',true);
 select solar_private.fx_entry_read_projection(to_jsonb(w),'wallet')into row_data from solar_private.wallet_fx_entries w where w.id=entry_id;
 assert(row_data->>'receiptRestricted')::boolean and row_data->>'note'='حركة مالية مرتبطة بوصل محجوب','Detached correction leaked foreign receipt';
 select solar_private.cash_read_projection(to_jsonb(m))into row_data from solar_private.cash_movements()m where m.id='fx:'||entry_id;
 assert(row_data->>'receiptRestricted')::boolean and row_data->>'receipt_no' is null and row_data->>'party'='','Cash correction leaked receipt metadata';
 assert(row_data->>'delta')::numeric=-1000,'Restricted effect lost monetary balance';
end$$;

-- Rounding may leave USD account amount unchanged while IQD cost changes.
-- Recognize only the new rounding gain; do not revalue outstanding/settled debt.
do $$declare v_invoice bigint; t public.transactions; result jsonb; previous_book numeric; state text; begin
 v_invoice:=pg_temp.buy(-399016,1,100,'USD');
 select * into t from transactions where id=v_invoice;
 foreach state in array array['positive','zero','negative']loop
  if state='zero' then
   perform public.solar_fx('payment',gen_random_uuid(),jsonb_build_object('paymentId',-399901,'supplierId',-399002,'amount',100,'currency','USD','cashCurrency','USD','rate',1500,'accountRevision',0,'mode','cash','note','settle USD invoice'));
  elsif state='negative' then
   perform public.solar_fx('payment',gen_random_uuid(),jsonb_build_object('paymentId',-399902,'supplierId',-399002,'amount',1,'currency','USD','cashCurrency','USD','rate',1500,'accountRevision',0,'mode','cash','note','advance USD credit'));
  end if;
  select coalesce(sum(book_delta),0)into previous_book from solar_private.supplier_fx_entries where supplier_id=-399002;
  result:=solar_private.purchase_correction_ledger_plan(t,'{"total":150001,"expenses":1,"sourceSubtotal":100}');
  assert(result->>'supplierDelta')::numeric=0 and(result->>'supplierBookDelta')::numeric=0 and(result->>'supplierGain')::numeric=1,'Zero rounded account delta repriced supplier book';
  assert(result#>>'{after,supplier,book}')::numeric=previous_book,'Unchanged USD amount changed debt/credit book';
 end loop;
end$$;

-- Legacy IQD receipts can have a complete original supplier posting without
-- the newer fx_accounted flag; accept only that coherent all-IQD rate1 case.
do $$declare v_invoice bigint; result jsonb; original jsonb; blocked boolean:=false; begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003991',true);
 result:=public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','purchase','mode','cash','partyId',-399001,'party','مورد إلغاء دينار','warehouseId',solar_private.primary_warehouse(),'items',jsonb_build_array(jsonb_build_object('id',-399017,'qty',1,'price',1000))));
 v_invoice:=(result->>'id')::bigint;
 assert(select fx_pricing and not fx_accounted and market_rate=1 and account_amount=1000 from transactions where id=v_invoice),'Legacy IQD fixture did not use legacy accounting path';
 select to_jsonb(e)into original from solar_private.supplier_fx_entries e where transaction_id=v_invoice;
 result:=pg_temp.correct_ledger(v_invoice,2000,2000);
 assert(result->>'cashDelta')::numeric=-1000 and(result->>'supplierDelta')::numeric=0;
 assert(select not fx_accounted and market_rate=1 and total=2000 from transactions where id=v_invoice),'Legacy snapshot was silently upgraded';
 assert(select to_jsonb(e)from solar_private.supplier_fx_entries e where transaction_id=v_invoice)=original,'Legacy supplier posting rewritten';
 begin
  delete from solar_private.supplier_fx_entries where transaction_id=v_invoice;
  perform pg_temp.correct_ledger(v_invoice,3000,3000);
 exception when sqlstate 'PT409' then blocked:=true;end;
 assert blocked,'Missing legacy ledger was accepted';
end$$;

-- These helpers cannot be called by authenticated clients directly.
do $$begin
 assert not has_function_privilege('authenticated','solar_private.purchase_correction_ledger_apply(uuid,bigint,jsonb)','EXECUTE');
 assert not has_function_privilege('authenticated','solar_private.purchase_correction_fx_update(public.transactions,public.transactions)','EXECUTE');
 assert not has_table_privilege('authenticated','solar_private.purchase_correction_execution','INSERT');
end$$;
rollback;
