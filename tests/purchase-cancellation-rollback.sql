-- Isolated regression fixtures only. Run against a local database; never production.
\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,permissions,phone) values
('00000000-0000-0000-0000-000000003990','مدير إلغاء الشراء',true,'admin_staff','{}','07700003990'),
('00000000-0000-0000-0000-000000003991','صاحب شراء الاختبار',false,'admin_staff','{"purchase":true,"sale":true,"cash":true,"stock":true,"supplierPayment":true,"exchangeRateEdit":true}','07700003991'),
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
create function pg_temp.approve_cancel(request_id uuid) returns void language plpgsql as $$declare detail jsonb;result jsonb;before_hash text;begin
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

-- Same-revision rollback retains the exact pre-purchase quantity and cost.
do $$<<newest>>declare invoice_id bigint;before_product jsonb;begin
 select jsonb_build_array(qty,cost,cost_basis)into before_product from products where id=-399001;
 invoice_id:=pg_temp.buy(-399001,2,2000);perform pg_temp.approve_cancel(pg_temp.request_cancel(invoice_id));
 assert(select jsonb_build_array(qty,cost,cost_basis)from products where id=-399001)=before_product,'Newest purchase did not restore original valuation';
 assert not exists(select 1 from transactions where id=invoice_id);
 assert exists(select 1 from solar_private.deleted_sales d where d.invoice_id=newest.invoice_id and d.invoice?'purchaseCancellation'),'Cancellation audit missing';
end$$;

-- Earlier purchase plus later procurement and sale: only the canceled purchase
-- is removed; historical later invoices, frozen sale costs and profit stay intact.
do $$declare first_id bigint;later_id bigint;sale_id bigint;request_id uuid;later_before jsonb;sale_before jsonb;qty_before numeric;value_before numeric;old_supplier jsonb;entry_id bigint;begin
 first_id:=pg_temp.buy(-399002,2,2000);request_id:=pg_temp.request_cancel(first_id);
 later_id:=pg_temp.buy(-399002,3,3000);sale_id:=pg_temp.sell(-399002,2,5000);
 select jsonb_build_array(to_jsonb(t),(select jsonb_agg(to_jsonb(i)order by id)from transaction_items i where i.transaction_id=t.id))into later_before from transactions t where id=later_id;
 select jsonb_build_array(to_jsonb(t),(select jsonb_agg(to_jsonb(i)order by id)from transaction_items i where i.transaction_id=t.id))into sale_before from transactions t where id=sale_id;
 select qty,qty*cost into qty_before,value_before from products where id=-399002;
 select id,to_jsonb(e)-'transaction_id'into entry_id,old_supplier from solar_private.supplier_fx_entries e where transaction_id=first_id;
 perform pg_temp.approve_cancel(request_id);
 assert(select qty from products where id=-399002)=qty_before-2,'Later stock was overwritten';
 assert abs((select qty*cost from products where id=-399002)-(value_before-4000))<0.001,'Remaining inventory book value incorrect';
 assert(select jsonb_build_array(to_jsonb(t),(select jsonb_agg(to_jsonb(i)order by id)from transaction_items i where i.transaction_id=t.id))from transactions t where id=later_id)=later_before,'Later purchase rewritten';
 assert(select jsonb_build_array(to_jsonb(t),(select jsonb_agg(to_jsonb(i)order by id)from transaction_items i where i.transaction_id=t.id))from transactions t where id=sale_id)=sale_before,'Historical sale/profit rewritten';
 assert(select to_jsonb(e)-'transaction_id'from solar_private.supplier_fx_entries e where id=entry_id)=old_supplier,'Original supplier posting rewritten';
 assert(select transaction_id is null from solar_private.supplier_fx_entries where id=entry_id),'Original supplier posting still linked';
 assert(select sum(delta)=0 and sum(book_delta)=0 and sum(gain)=0 from solar_private.supplier_fx_entries where id=entry_id or correction_for=first_id),'Supplier inverse is not exact';
end$$;

-- A later sale at the same cost is safely reversible when enough stock remains.
do $$declare invoice_id bigint;sale_id bigint;sale_before jsonb;begin
 invoice_id:=pg_temp.buy(-399003,2,1000);sale_id:=pg_temp.sell(-399003,2,2000);
 select to_jsonb(t)into sale_before from transactions t where id=sale_id;
 perform pg_temp.approve_cancel(pg_temp.request_cancel(invoice_id));
 assert(select qty=8 and cost=1000 from products where id=-399003),'Sale then cancellation stock mismatch';
 assert(select to_jsonb(t)from transactions t where id=sale_id)=sale_before,'Later sale mutated';end$$;

-- An actual stock shortage and a multi-product shortage roll back atomically.
do $$declare invoice_id bigint;request_id uuid;result jsonb;begin
 invoice_id:=pg_temp.buy(-399004,2,1000);perform pg_temp.sell(-399004,1,2000);request_id:=pg_temp.request_cancel(invoice_id);perform pg_temp.blocked_cancel(request_id);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003991',true);
 result:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","mode":"credit","partyId":-399001,"party":"مورد إلغاء دينار","warehouseId":1,"items":[{"id":-399005,"qty":2,"price":1000},{"id":-399006,"qty":2,"price":1000}]}');
 invoice_id:=(result->>'id')::bigint;perform pg_temp.sell(-399005,1,2000);perform pg_temp.blocked_cancel(pg_temp.request_cancel(invoice_id));
 assert(select qty from products where id=-399006)=12,'Valid line changed before blocked line';end$$;

-- Transfer history and destination stock are retained. Pending transfer stock
-- is reserved, so it cannot be consumed by deleting its source purchase.
do $$declare invoice_id bigint;target_id bigint;transfer_id uuid:=gen_random_uuid();transfer_before jsonb;payload jsonb;begin
 invoice_id:=pg_temp.buy(-399010,2,1000);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003990',true);
 target_id:=(public.solar_inventory('warehouse_save',gen_random_uuid(),'{"name":"مخزن إلغاء معزول"}')->>'id')::bigint;
 perform set_config('test.cancel.warehouse',target_id::text,true);
 payload:=jsonb_build_object('fromId',solar_private.primary_warehouse(),'toId',target_id,'items',jsonb_build_array(jsonb_build_object('productId',-399010,'qty',3,'revision',(select revision from solar_private.warehouse_stocks where warehouse_id=solar_private.primary_warehouse()and product_id=-399010))));
 perform public.solar_inventory('transfer',transfer_id,payload);perform public.solar_inventory('prepare_transfer',gen_random_uuid(),jsonb_build_object('id',transfer_id,'expectedRevision',0));
 select to_jsonb(t)into transfer_before from solar_private.stock_transfers t where id=transfer_id;
 perform pg_temp.approve_cancel(pg_temp.request_cancel(invoice_id));
 assert(select qty from products where id=-399010)=10;
 assert(select qty from solar_private.warehouse_stocks where warehouse_id=target_id and product_id=-399010)=3,'Destination stock overwritten';
 assert(select qty from solar_private.warehouse_stocks where warehouse_id=solar_private.primary_warehouse()and product_id=-399010)=7,'Wrong origin stock reversed';
 assert(select to_jsonb(t)from solar_private.stock_transfers t where id=transfer_id)=transfer_before,'Transfer history rewritten';
 invoice_id:=pg_temp.buy(-399007,5,1000);perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003990',true);
 perform public.solar_inventory('transfer',gen_random_uuid(),jsonb_build_object('fromId',solar_private.primary_warehouse(),'toId',target_id,'items',jsonb_build_array(jsonb_build_object('productId',-399007,'qty',1,'revision',(select revision from solar_private.warehouse_stocks where warehouse_id=solar_private.primary_warehouse()and product_id=-399007)))));
 perform pg_temp.blocked_cancel(pg_temp.request_cancel(invoice_id));end$$;

-- USD components follow the current market rate only for new quotes. Cancellation
-- removes original procurement value, not today's replacement price.
do $$declare first_id bigint;later_id bigint;sale_id bigint;sale_before jsonb;basis jsonb;begin
 first_id:=pg_temp.buy(-399008,2,100,'USD');later_id:=pg_temp.buy(-399008,2,200,'USD');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003990',true);
 perform public.solar_exchange_rate_set(1700,(public.solar_exchange_rate_get()->>'revision')::bigint);
 sale_id:=pg_temp.sell(-399008,1,500000);select to_jsonb(t)into sale_before from transactions t where id=sale_id;
 perform pg_temp.approve_cancel(pg_temp.request_cancel(first_id));
 assert(select qty=1 and abs(cost-375000)<0.001 from products where id=-399008),'USD historical book reversal incorrect';
 select solar_private.valuation_quote(id,cost_basis,cost)into basis from products where id=-399008;
 assert abs((basis->'currencyComponents'->>'usd')::numeric-250)<0.000001,'USD component not reversed';
 assert abs((basis->>'valuationUnitCost')::numeric-425000)<0.001,'Current rate quote lost remaining USD basis';
 assert(select to_jsonb(t)from transactions t where id=sale_id)=sale_before,'Existing sale repriced at cancellation';end$$;

-- Paid purchases refund the original payer; USD amount and book value are
-- inverted exactly while retaining original wallet entries for audit.
do $$declare invoice_id bigint;before_cash numeric;before_wallet jsonb;wallet_id bigint;wallet_before jsonb;begin
 before_cash:=solar_private.cash_balance('00000000-0000-0000-0000-000000003991');
 invoice_id:=pg_temp.buy(-399009,2,1000,'IQD','cash');
 assert solar_private.cash_balance('00000000-0000-0000-0000-000000003991')=before_cash-2000;
 perform pg_temp.approve_cancel(pg_temp.request_cancel(invoice_id));assert solar_private.cash_balance('00000000-0000-0000-0000-000000003991')=before_cash,'IQD cash refund incorrect';
 before_wallet:=solar_private.usd_wallet('00000000-0000-0000-0000-000000003991');
 invoice_id:=pg_temp.buy(-399011,1,100,'USD','cash','USD');
 select id,to_jsonb(e)-'transaction_id'into wallet_id,wallet_before from solar_private.wallet_fx_entries e where transaction_id=invoice_id;
 perform pg_temp.approve_cancel(pg_temp.request_cancel(invoice_id));
 assert solar_private.usd_wallet('00000000-0000-0000-0000-000000003991')=before_wallet,'USD amount/book refund incorrect';
 assert(select to_jsonb(e)-'transaction_id'from solar_private.wallet_fx_entries e where id=wallet_id)=wallet_before,'Original USD wallet entry rewritten';
 assert(select transaction_id is null from solar_private.wallet_fx_entries where id=wallet_id),'Original wallet entry not retained detached';
 before_cash:=solar_private.cash_balance('00000000-0000-0000-0000-000000003991');
 invoice_id:=pg_temp.buy(-399012,1,100,'USD','cash','IQD');perform pg_temp.approve_cancel(pg_temp.request_cancel(invoice_id));
 assert solar_private.cash_balance('00000000-0000-0000-0000-000000003991')=before_cash,'USD-priced IQD cash refund incorrect';
 assert solar_private.usd_wallet('00000000-0000-0000-0000-000000003991')=before_wallet,'IQD payment changed USD wallet';end$$;

-- Enough physical stock does not justify negative or orphaned remaining value.
do $$declare invoice_id bigint;begin
 invoice_id:=pg_temp.buy(-399014,1,1000);perform pg_temp.buy(-399014,1,2000);perform pg_temp.sell(-399014,1,3000);
 perform pg_temp.blocked_cancel(pg_temp.request_cancel(invoice_id));
 invoice_id:=pg_temp.buy(-399015,1,10000);perform pg_temp.buy(-399015,2,100);perform pg_temp.sell(-399015,2,12000);
 perform pg_temp.blocked_cancel(pg_temp.request_cancel(invoice_id));end$$;

-- Independent later supplier payments keep their exact invoice/posting. The
-- canceled purchase subtracts its debt only, even when the supplier was paid.
do $$declare invoice_id bigint;payment_before jsonb;entry_before jsonb;balance_before numeric;begin
 invoice_id:=pg_temp.buy(-399016,2,1000);
 perform public.solar_fx('payment',gen_random_uuid(),'{"paymentId":-399900,"supplierId":-399001,"amount":500,"currency":"IQD","cashCurrency":"IQD","rate":1700,"accountRevision":0,"mode":"cash","note":"تسديد مستقل بعد الشراء"}');
 select to_jsonb(t)into payment_before from transactions t where id=-399900;
 select to_jsonb(e)into entry_before from solar_private.supplier_fx_entries e where transaction_id=-399900;
 select sum(delta)into balance_before from solar_private.supplier_fx_entries where supplier_id=-399001 and revision=0;
 perform pg_temp.approve_cancel(pg_temp.request_cancel(invoice_id));
 assert(select to_jsonb(t)from transactions t where id=-399900)=payment_before,'Later supplier payment changed';
 assert(select to_jsonb(e)from solar_private.supplier_fx_entries e where transaction_id=-399900)=entry_before,'Later supplier payment posting changed';
 assert(select sum(delta)from solar_private.supplier_fx_entries where supplier_id=-399001 and revision=0)=balance_before-2000,'Supplier debt reversed by wrong amount';end$$;

-- A supplier currency migration cannot be silently reversed in an obsolete
-- denomination/revision. This is synthetic fixture metadata only.
do $$declare invoice_id bigint;request_id uuid;begin
 invoice_id:=pg_temp.buy(-399017,1,100,'USD');request_id:=pg_temp.request_cancel(invoice_id);
 update suppliers set currency_revision=currency_revision+1 where id=-399002;
 perform pg_temp.blocked_cancel(request_id);end$$;

-- Server authorization remains mandatory and receipt edits stale approvals.
select set_config('test.cancel.authinvoice',pg_temp.buy(-399013,2,1000)::text,true);
select set_config('test.cancel.authrequest',pg_temp.request_cancel(current_setting('test.cancel.authinvoice')::bigint)::text,true);
set local role authenticated;
do $$declare request_id uuid:=current_setting('test.cancel.authrequest')::uuid;before_hash text:=pg_temp.finance_hash();begin
 begin perform public.solar_purchase_delete(current_setting('test.cancel.authinvoice')::bigint,1);raise exception 'Owner direct-delete bypass';exception when insufficient_privilege then null;end;
 begin perform public.solar_receipt_delete_requests('approve',request_id,'{}');raise exception 'Owner self-approval';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003992',true);
 begin perform public.solar_receipt_delete_requests('get',request_id);raise exception 'Foreign request disclosure';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003993',true);
 begin perform public.solar_receipt_delete_requests('approve',request_id,'{}');raise exception 'Warehouse stale-admin approval';exception when insufficient_privilege then null;end;
 assert pg_temp.finance_hash()=before_hash,'Unauthorized request changed finances';end$$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003991',true);
select public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','purchase','mode','credit','partyId',-399001,'party','مورد إلغاء دينار','warehouseId',solar_private.primary_warehouse(),
 'invoiceId',current_setting('test.cancel.authinvoice')::bigint,'expectedRevision',(select pricing_revision from transactions where id=current_setting('test.cancel.authinvoice')::bigint),
 'sourceCurrency','IQD','marketRate',1700,'accountRevision',0,'items','[{"id":-399013,"qty":2,"price":1100}]'::jsonb));
select pg_temp.blocked_cancel(current_setting('test.cancel.authrequest')::uuid);
set constraints all immediate;
\echo PASS purchase cancellation: later procurement/sales, immutable histories, original stock valuation, stock/reservation rollback, warehouse transfers, USD original-book reversal, supplier/wallet audit, refunds, server permissions, request/approval replay and stale edits
rollback;
