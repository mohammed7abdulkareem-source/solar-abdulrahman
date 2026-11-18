-- Independent V4.1.9 calculation oracle. Isolated local database only.
-- Expected values are derived from weighted averages, not the correction engine.
\set ON_ERROR_STOP on
load 'safeupdate';
begin;
insert into public.profiles(id,display_name,is_admin,user_type,phone,active,permissions)values
('00000000-0000-0000-0000-000000419700','مدير مراجعة الكلفة',true,'admin_staff','07700419700',true,'{}'),
('00000000-0000-0000-0000-000000419701','صاحب تصحيح الكلفة',false,'admin_staff','07700419701',true,'{"purchase":true,"sale":true,"profit":true,"exchangeRateEdit":true}');
insert into public.suppliers(id,name,account_currency)values(-419701,'مورد مراجعة الكلفة','IQD');
insert into public.customers(id,name,customer_type,owner_id)values
(-419701,'عميل مراجعة الكلفة','wholesale','00000000-0000-0000-0000-000000419701');
insert into public.products(id,code,name,qty,cost)
select -419700-n,'COST-ORACLE-'||n,'مادة مراجعة الكلفة '||n,0,0 from generate_series(1,13)n;
update solar_private.wholesale_pricing_control set enabled=false where id;
update solar_private.operation_controls set sale_paused=false,purchase_paused=false where id;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419700',true);
select public.solar_exchange_rate_set(1000,(public.solar_exchange_rate_get()->>'revision')::bigint);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419701',true);

-- Separate real HTTP calls have advancing transaction timestamps. A rollback
-- fixture has one now(), so assign deterministic, strictly ordered event dates.
create function pg_temp.oracle_stamp(nonce uuid,invoice_id bigint)returns void
language plpgsql security definer set search_path='' as $$
declare step integer:=coalesce(nullif(current_setting('test.oracle.clock',true),''),'0')::integer+1;
 stamp timestamptz;t public.transactions;old_context text:=coalesce(current_setting('solar.fx_context',true),'');
begin
 perform set_config('test.oracle.clock',step::text,true);
 stamp:='2026-11-01 00:00:00+00'::timestamptz+step*interval '1 minute';
 select * into t from public.transactions where id=invoice_id;
 if t.kind='purchase'then perform set_config('solar.fx_context',jsonb_build_object('accountRevision',t.account_revision,'marketRate',t.market_rate,'cashCurrency',t.cash_currency)::text,true);end if;
 update public.transactions set created_at=stamp where id=invoice_id;
 perform set_config('solar.fx_context',old_context,true);
 update solar_private.invoice_requests set created_at=stamp where request_id=nonce;
 update solar_private.supplier_fx_entries set created_at=stamp where transaction_id=invoice_id;
 update solar_private.wallet_fx_entries set created_at=stamp where transaction_id=invoice_id;
end$$;

create function pg_temp.oracle_buy(material bigint,units numeric,price numeric,source text default 'IQD')returns bigint
language plpgsql security definer set search_path='' as $$
declare nonce uuid:=gen_random_uuid();r jsonb;invoice_id bigint;begin
 r:=public.solar_invoice_save(nonce,jsonb_build_object('kind','purchase','mode','credit','partyId',-419701,'party','مورد مراجعة الكلفة',
 'warehouseId',solar_private.primary_warehouse(),'sourceCurrency',source,'cashCurrency','IQD','exchangeRate',case when source='USD'then 1000 else 1 end,
 'marketRate',1000,'accountRevision',0,'expenses',0,'items',jsonb_build_array(jsonb_build_object('id',material,'qty',units,'price',price))));
 invoice_id:=(r->>'id')::bigint;perform pg_temp.oracle_stamp(nonce,invoice_id);return invoice_id;
end$$;
create function pg_temp.oracle_sell(lines jsonb)returns bigint
language plpgsql security definer set search_path='' as $$
declare nonce uuid:=gen_random_uuid();r jsonb;invoice_id bigint;begin
 r:=public.solar_invoice_save(nonce,jsonb_build_object('kind','sale','mode','credit','partyId',-419701,'party','عميل مراجعة الكلفة',
 'warehouseId',solar_private.primary_warehouse(),'expenses',0,'items',lines));
 invoice_id:=(r->>'id')::bigint;perform pg_temp.oracle_stamp(nonce,invoice_id);return invoice_id;
end$$;
create function pg_temp.oracle_sell(material bigint,units numeric,price numeric)returns bigint
language sql security definer set search_path='' as $$
select pg_temp.oracle_sell(jsonb_build_array(jsonb_build_object('id',material,'qty',units,'price',price)))$$;
create function pg_temp.oracle_correct(invoice_id bigint,units numeric,price numeric)returns jsonb
language plpgsql security definer set search_path='' as $$
declare t public.transactions;material bigint;body jsonb;plan jsonb;r jsonb;nonce uuid:=gen_random_uuid();begin
 select * into t from public.transactions where id=invoice_id;
 select product_id into strict material from public.transaction_items where transaction_id=t.id;
 body:=jsonb_build_object('kind','purchase','mode',t.payment_mode,'partyId',t.party_id,'party',t.party_name,'warehouseId',t.warehouse_id,
 'sourceCurrency',t.source_currency,'cashCurrency',t.cash_currency,'exchangeRate',t.exchange_rate,'marketRate',t.market_rate,
 'accountRevision',t.account_revision,'expenses',t.expenses,'invoiceId',t.id,'expectedRevision',t.pricing_revision,
 'items',jsonb_build_array(jsonb_build_object('id',material,'qty',units,'price',price)));
 plan:=public.solar_purchase_correction_preview(body);
 assert (plan->>'canApply')::boolean,coalesce(plan->>'blockedReason','Missing correction preview');
 assert not(plan ?| array['affectedLines','affectedInvoices','purchaseSnapshots','normalizedItems','ledgerPlan']),
  'Public preview exposed private correction provenance';
 assert not exists(select 1 from jsonb_array_elements(plan->'items')i where(i->'before')?'basis' or(i->'after')?'basis'),
  'Public preview exposed another purchase cost basis';
 body:=body||jsonb_build_object('purchaseCorrectionToken',plan->>'token');
 r:=public.solar_invoice_save(nonce,body);
 assert public.solar_invoice_save(nonce,body)=r,'Same correction retry returned a different acknowledgement';
 return r;
end$$;
create function pg_temp.oracle_invoice(id bigint)returns jsonb language sql security definer set search_path='' as $$
select jsonb_build_array(to_jsonb(t),(select jsonb_agg(to_jsonb(i)order by i.id)from public.transaction_items i where i.transaction_id=t.id))
from public.transactions t where t.id=$1$$;

-- Exact user example: pre-existing 500 @100,000 plus600 @130,000, changed to400.
do $$declare target bigint;begin
 perform pg_temp.oracle_buy(-419701,500,100000);target:=pg_temp.oracle_buy(-419701,600,130000);
 perform pg_temp.oracle_correct(target,400,130000);
 assert(select qty=900 and cost=113333.333333 from public.products where id=-419701),'500+400 weighted cost is wrong';
 assert(select sum(qty+reserved_qty)=900 from solar_private.warehouse_stocks where product_id=-419701),'Warehouse quantity differs';
end$$;

-- Same quantity correction after an actual sale affects its100 units and800 left.
do $$declare target bigint;sale bigint;before_header jsonb;begin
 perform pg_temp.oracle_buy(-419702,500,100000);target:=pg_temp.oracle_buy(-419702,600,130000);
 sale:=pg_temp.oracle_sell(-419702,100,150000);
 select to_jsonb(t)-'cost'-'profit'-'pricing_revision' into before_header from public.transactions t where id=sale;
 perform pg_temp.oracle_correct(target,400,130000);
 assert(select qty=800 and cost=113333.333333 from public.products where id=-419702),'Remaining quantity was overwritten';
 assert(select cost=11333333.33 and profit=3666666.67 and total=15000000 from public.transactions where id=sale),'Only sold quantity should change profit';
 assert(select to_jsonb(t)-'cost'-'profit'-'pricing_revision' from public.transactions t where id=sale)=before_header,'Unrelated sale header changed';
end$$;

-- User's4 sold/6 remaining case, with another material on the same sale.
-- Approved checkpoint remains the original200; available profit becomes−80.
do $$declare target bigint;sale bigint;other_line jsonb;settlement uuid:=gen_random_uuid();checkpoint jsonb;before_cash numeric;before_debt numeric;after_debt numeric;profit_row jsonb;begin
 target:=pg_temp.oracle_buy(-419703,10,100);perform pg_temp.oracle_buy(-419704,2,20);
 sale:=pg_temp.oracle_sell(jsonb_build_array(jsonb_build_object('id',-419703,'qty',4,'price',150),jsonb_build_object('id',-419704,'qty',1,'price',20)));
 select to_jsonb(i)into other_line from public.transaction_items i where transaction_id=sale and product_id=-419704;
 insert into solar_private.profit_settlements(id,owner_id,snapshot,profit,status,date_to,share,receipt)
 values(settlement,auth.uid(),'[]',200,'approved',(now()at time zone'Asia/Baghdad')::date,0,'{}');
 insert into solar_private.profit_checkpoints(owner_id,source_key,value,row_data,settlement_id)
 values(auth.uid(),'tx:'||sale,200,jsonb_build_object('date',now(),'kind','sale','value',200),settlement);
 select to_jsonb(c)into checkpoint from solar_private.profit_checkpoints c where source_key='tx:'||sale and owner_id=auth.uid();
 before_cash:=solar_private.cash_balance(auth.uid());
 select sum((x->>'effect')::numeric)into before_debt from jsonb_array_elements(solar_private.customer_ledger(-419701))x;
 perform pg_temp.oracle_correct(target,10,120);
 assert(select qty=6 and cost=120 and qty*cost=720 from public.products where id=-419703);
 assert(select cost=500 and profit=120 and total=620 from public.transactions where id=sale);
 assert(select to_jsonb(i)from public.transaction_items i where transaction_id=sale and product_id=-419704)=other_line,'Other material line changed';
 assert(select to_jsonb(c)from solar_private.profit_checkpoints c where source_key='tx:'||sale and owner_id=auth.uid())=checkpoint,'Paid profit checkpoint changed';
 select x into profit_row from jsonb_array_elements(solar_private.profit_rows(auth.uid()))x where x->>'key'='tx:'||sale;
 assert(profit_row->>'value')::numeric=120 and(profit_row->>'settled')::numeric=200 and(profit_row->>'available')::numeric=-80;
 select sum((x->>'effect')::numeric)into after_debt from jsonb_array_elements(solar_private.customer_ledger(-419701))x;
 assert after_debt=before_debt and solar_private.cash_balance(auth.uid())=before_cash,'Purchase correction changed customer cash/debt';
end$$;

-- The influence survives later purchases proportionally, not FIFO by receipt.
do $$declare target bigint;first_sale bigint;later_purchase bigint;second_sale bigint;later_before jsonb;begin
 perform pg_temp.oracle_buy(-419705,10,100);target:=pg_temp.oracle_buy(-419705,10,200);
 first_sale:=pg_temp.oracle_sell(-419705,4,300);later_purchase:=pg_temp.oracle_buy(-419705,4,250);second_sale:=pg_temp.oracle_sell(-419705,5,300);
 select jsonb_build_array(total,source_subtotal,exchange_rate,account_amount,cash_amount)into later_before from public.transactions where id=later_purchase;
 perform pg_temp.oracle_correct(target,10,300);
 assert(select cost=800 and profit=400 from public.transactions where id=first_sale);
 assert(select cost=1050 and profit=450 from public.transactions where id=second_sale);
 assert(select qty=15 and cost=210 and qty*cost=3150 from public.products where id=-419705);
 assert(select jsonb_build_array(total,source_subtotal,exchange_rate,account_amount,cash_amount)from public.transactions where id=later_purchase)=later_before,'Later purchase price/account was repriced';
end$$;

-- Changing quantity changes the mix. Book cost is rounded6; currency parts
-- retain precision, so financial valuation can differ by one millionth.
do $$declare target bigint;first_sale bigint;second_sale bigint;begin
 perform pg_temp.oracle_buy(-419706,10,100);target:=pg_temp.oracle_buy(-419706,10,200);
 first_sale:=pg_temp.oracle_sell(-419706,4,300);perform pg_temp.oracle_buy(-419706,4,250);second_sale:=pg_temp.oracle_sell(-419706,5,300);
 perform pg_temp.oracle_correct(target,8,200);
 assert(select qty=13 and cost=167.901234 from public.products where id=-419706),'Book precision changed';
 assert(select cost=577.78 and profit=622.22 from public.transactions where id=first_sale);
 assert(select cost=839.51 and profit=660.49 from public.transactions where id=second_sale);
 assert(select cost=167.901235 and(cost_basis->>'bookUnitCost')::numeric=167.901234 from public.transaction_items where transaction_id=second_sale and product_id=-419706),'Historical valuation and book cost were conflated';
end$$;

-- Once the stock pool is exhausted, a price-only correction must not touch
-- later purchases/sales. A quantity increase can legitimately extend the pool.
do $$declare target bigint;first_sale bigint;later_purchase bigint;second_sale bigint;second_before jsonb;begin
 target:=pg_temp.oracle_buy(-419707,10,100);first_sale:=pg_temp.oracle_sell(-419707,10,150);
 later_purchase:=pg_temp.oracle_buy(-419707,5,200);second_sale:=pg_temp.oracle_sell(-419707,2,300);second_before:=pg_temp.oracle_invoice(second_sale);
 perform pg_temp.oracle_correct(target,10,120);
 assert(select profit=300 from public.transactions where id=first_sale);
 assert pg_temp.oracle_invoice(second_sale)=second_before,'Unrelated sale after pool exhaustion changed';
 assert(select qty=3 and cost=200 from public.products where id=-419707);
 target:=pg_temp.oracle_buy(-419708,10,100);first_sale:=pg_temp.oracle_sell(-419708,10,150);
 perform pg_temp.oracle_buy(-419708,5,200);second_sale:=pg_temp.oracle_sell(-419708,2,300);
 perform pg_temp.oracle_correct(target,12,100);
 assert(select profit=500 from public.transactions where id=first_sale);
 assert(select cost=342.86 and profit=257.14 from public.transactions where id=second_sale);
 assert(select qty=5 and cost=171.428571 from public.products where id=-419708);
end$$;

-- Reprice the affected financial quantity at its SAVED sale valuation rate.
-- Today's2500 rate must not replace the historic1500 rate or purchase1000 rate.
do $$declare target bigint;sale bigint;begin
 target:=pg_temp.oracle_buy(-419709,10,2,'USD');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419700',true);
 perform public.solar_exchange_rate_set(1500,(public.solar_exchange_rate_get()->>'revision')::bigint);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419701',true);
 sale:=pg_temp.oracle_sell(-419709,4,4000);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419700',true);
 perform public.solar_exchange_rate_set(2500,(public.solar_exchange_rate_get()->>'revision')::bigint);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419701',true);
 perform pg_temp.oracle_correct(target,10,3);
 assert(select qty=6 and cost=3000 and qty*cost=18000 from public.products where id=-419709);
 assert(select cost=18000 and profit=-2000 and total=16000 from public.transactions where id=sale),'Correction used today FX instead of historic sale rate';
 assert(select cost=4500 and(cost_basis->>'valuationRate')::numeric=1500 and(cost_basis->>'bookUnitCost')::numeric=3000 from public.transaction_items where transaction_id=sale);
 assert(select source_currency='USD' and exchange_rate=1000 from public.transactions where id=target);
end$$;

-- Deleting the mistaken purchase is the same scoped zero contribution: the
-- opening500 units cover the100 sold, leaving400 at their own100,000 cost.
-- It must not retain the blended cost contributed by the cancelled600 units.
do $$declare target bigint;sale bigint;context jsonb;body jsonb;nonce uuid:=gen_random_uuid();r jsonb;begin
 perform pg_temp.oracle_buy(-419710,500,100000);target:=pg_temp.oracle_buy(-419710,600,130000);
 sale:=pg_temp.oracle_sell(-419710,100,150000);
 context:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',target));
 assert(context->>'directEligible')::boolean,coalesce(context->>'blockedReason','Purchase direct cancellation unavailable');
 assert not((context->'purchaseCancellation') ?| array['supplierEntry','walletEntry','ledgerTotals']),
  'Public cancellation exposed private accounting entries';
 assert not exists(select 1 from jsonb_array_elements(context#>'{purchaseCancellation,items}')i
  where i?'warehouseBefore' or(i->'before')?'basis' or(i->'after')?'basis'),
  'Public cancellation exposed purchase provenance';
 body:=jsonb_build_object('invoiceId',target,'expectedToken',context->>'token');
 r:=public.solar_receipt_delete_requests('delete_direct',nonce,body);
 assert r->>'status'='deleted';
 assert not exists(select 1 from public.transactions where id=target);
 assert(select qty=400 and cost=100000 from public.products where id=-419710),'Cancelled purchase still affects current weighted cost';
 assert(select cost=10000000 and profit=5000000 and total=15000000 from public.transactions where id=sale),'Cancellation repriced the wrong sold quantity';
 assert public.solar_receipt_delete_requests('delete_direct',nonce,body)=r,'Cancellation replay changed acknowledgement';
 assert(select qty=400 and cost=100000 from public.products where id=-419710),'Cancellation replay changed stock twice';
end$$;

-- A history/current-value mismatch must be blocked before any financial write.
-- The one-unit cost discrepancy is isolated fixture corruption, not a workflow.
do $$declare target bigint;sale bigint;t public.transactions;body jsonb;plan jsonb;nonce uuid:=gen_random_uuid();
 before_invoice jsonb;before_sale jsonb;before_product jsonb;before_supplier jsonb;rejected boolean:=false;
begin
 target:=pg_temp.oracle_buy(-419711,10,100);sale:=pg_temp.oracle_sell(-419711,4,150);
 update public.products set cost=101 where id=-419711;
 select * into t from public.transactions where id=target;
 body:=jsonb_build_object('kind','purchase','mode',t.payment_mode,'partyId',t.party_id,'party',t.party_name,'warehouseId',t.warehouse_id,
  'sourceCurrency',t.source_currency,'cashCurrency',t.cash_currency,'exchangeRate',t.exchange_rate,'marketRate',t.market_rate,
  'accountRevision',t.account_revision,'expenses',t.expenses,'invoiceId',t.id,'expectedRevision',t.pricing_revision,
  'items',jsonb_build_array(jsonb_build_object('id',-419711,'qty',10,'price',120)));
 before_invoice:=pg_temp.oracle_invoice(target);before_sale:=pg_temp.oracle_invoice(sale);
 select to_jsonb(p) into before_product from public.products p where id=-419711;
 select jsonb_agg(to_jsonb(e)order by e.id) into before_supplier from solar_private.supplier_fx_entries e where supplier_id=-419701;
 plan:=public.solar_purchase_correction_preview(body);
 assert not(plan->>'canApply')::boolean and length(plan->>'blockedReason')>0,'Unreconciled history was presented as applicable';
 begin
  perform public.solar_invoice_save(nonce,body||jsonb_build_object('purchaseCorrectionToken',plan->>'token'));
 exception when sqlstate 'PT409' or sqlstate 'P0002' then rejected:=true;end;
 assert rejected,'Unreconciled history was saved';
 assert pg_temp.oracle_invoice(target)=before_invoice and pg_temp.oracle_invoice(sale)=before_sale,'Rejected plan changed invoices';
 assert(select to_jsonb(p)from public.products p where id=-419711)=before_product,'Rejected plan changed stock valuation';
 assert(select jsonb_agg(to_jsonb(e)order by e.id)from solar_private.supplier_fx_entries e where supplier_id=-419701)=before_supplier,'Rejected plan posted supplier entries';
 assert not exists(select 1 from solar_private.purchase_corrections where request_id=nonce)
  and not exists(select 1 from solar_private.invoice_requests where request_id=nonce),'Rejected plan consumed its nonce';
end$$;

-- A receipt created before this purchase may only acquire its material later.
-- Its complete original item list proves zero units at the purchase anchor;
-- seeding the current one-unit line would omit the later consumption entirely.
do $$declare target bigint;sale bigint;nonce uuid:=gen_random_uuid();r jsonb;revision bigint;stamp timestamptz;step integer;
begin
 perform pg_temp.oracle_buy(-419712,2,20);
 sale:=pg_temp.oracle_sell(-419712,1,30);
 target:=pg_temp.oracle_buy(-419713,1,800000);
 select pricing_revision into revision from public.transactions where id=sale;
 r:=public.solar_invoice_save(nonce,jsonb_build_object('kind','sale','invoiceId',sale,'expectedRevision',revision,'mode','credit',
  'partyId',-419701,'party','عميل مراجعة الكلفة','warehouseId',solar_private.primary_warehouse(),'expenses',0,
  'items',jsonb_build_array(jsonb_build_object('id',-419712,'qty',1,'price',30),jsonb_build_object('id',-419713,'qty',1,'price',900000))));
 step:=current_setting('test.oracle.clock')::integer+1;perform set_config('test.oracle.clock',step::text,true);
 stamp:='2026-11-01 00:00:00+00'::timestamptz+step*interval '1 minute';
 update solar_private.invoice_requests set created_at=stamp where request_id=nonce;
 assert(select qty=0 from public.products where id=-419713),'Later-added material was not consumed';
 perform pg_temp.oracle_correct(target,1,800001);
 assert(select qty=0 and cost=800001 from public.products where id=-419713),'Material absent at anchor was double counted';
 assert(select cost=800021 and total=900030 and profit=100009 from public.transactions where id=sale),'Later-added material profit was not corrected';
 assert(select cost=20 from public.transaction_items where transaction_id=sale and product_id=-419712),'Original unrelated material changed';
end$$;

set constraints all immediate;
rollback;
select 'Independent purchase correction scope oracle PASS' result;
