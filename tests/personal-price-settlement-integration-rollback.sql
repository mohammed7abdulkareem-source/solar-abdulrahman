-- A package can earn 20m for the company and 14m for its seller. The optional
-- policy must not alter costs, earlier cash movements, or the seller's share twice.
\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,username,display_name,is_admin,active,user_type,permissions,phone) values
 ('00000000-0000-0000-0000-000000412510','basis_admin_412510','مدير اختبار أساس الربح',true,true,'admin_staff','{}','07700000000'),
 ('00000000-0000-0000-0000-000000412511','basis_seller_412511','بائع اختبار أساس الربح',false,true,'admin_staff','{"sale":true,"customers":true,"profit":true,"profitSettlement":true}','07700000000');
insert into public.customers(id,name,owner_id,customer_type)
 values(-412510,'متجر اختبار تسوية أساس الربح','00000000-0000-0000-0000-000000412511','wholesale');
insert into public.products(id,code,name,qty,cost) values(-412510,'SETTLE-BASIS-412510','منظومة اختبار شركة',3,30000000);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values(1,-412510,3) on conflict(warehouse_id,product_id) do update set qty=excluded.qty;
set local role authenticated;
do $test$
declare
 manager constant uuid:='00000000-0000-0000-0000-000000412510';
 seller constant uuid:='00000000-0000-0000-0000-000000412511';
 request_no uuid:=gen_random_uuid();
 price_row jsonb; admins jsonb; original jsonb; result jsonb; settlement jsonb; approved jsonb;
 initial_company jsonb; after_sale jsonb; after_settlement jsonb; receipt_id bigint;
begin
 perform set_config('request.jwt.claim.sub',manager::text,true);
 initial_company:=public.solar_profit_workspace('balance',null,'{"ownerId":"all"}');
 select x into strict price_row from jsonb_array_elements(public.solar_wholesale_pricing('state')->'products')x where x->>'id'='-412510';
 perform public.solar_wholesale_pricing('save',gen_random_uuid(),jsonb_build_object('items',jsonb_build_array(
   jsonb_build_object('productId',-412510,'minPrice',36000000,'expectedRevision',price_row->'revision','enabled',true))));
 admins:=public.solar_profit_basis_users('state');
 perform public.solar_profit_basis_users('save',gen_random_uuid(),jsonb_build_object('changes',jsonb_build_array(jsonb_build_object('id',seller,'enabled',true)),'token',admins->'token'));
 perform set_config('request.jwt.claim.sub',seller::text,true);
 result:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"cash","partyId":-412510,"party":"متجر اختبار تسوية أساس الربح","warehouseId":1,"items":[{"id":-412510,"qty":1,"price":50000000}]}');
 receipt_id:=(result->>'id')::bigint;
 assert receipt_id is not null;
 perform set_config('fixture.bill',receipt_id::text,true);
 result:=public.solar_profit_workspace('balance',null,jsonb_build_object('ownerId',seller));
 assert not(result?'comparison'),'seller received company comparison';
 assert(result#>>'{period,earned}')::numeric=14000000,'personal balance differs from seller margin';
 original:=public.solar_profit_workspace('overview');
 assert(original->>'available')::numeric=14000000 and (original->>'retainedProfit')::numeric=14000000,'wrong personal retained';
 perform public.solar_profit_workspace('request',request_no,jsonb_build_object('expectedToken',original->>'token'));
 perform set_config('request.jwt.claim.sub',manager::text,true);
 result:=public.solar_profit_workspace('balance',null,jsonb_build_object('ownerId',seller));
 assert(result#>>'{comparison,companyEarned}')::numeric=20000000,'company margin for this seller absent';
 assert(result#>>'{comparison,personalEarned}')::numeric=14000000,'individual margin alongside real figure absent';
 after_sale:=public.solar_profit_workspace('balance',null,'{"ownerId":"all"}');
 assert(after_sale#>>'{period,earned}')::numeric-(initial_company#>>'{period,earned}')::numeric=20000000,'all-company earnings incorrectly use seller basis';
 select x into strict settlement from jsonb_array_elements(public.solar_profit_workspace('overview',null,jsonb_build_object('ownerId',seller))->'requests')x where x->>'id'=request_no::text;
 assert(settlement->>'profit')::numeric=14000000,'settlement included reserved 6m';
 begin
  perform public.solar_profit_workspace('approve',gen_random_uuid(),jsonb_build_object('id',request_no,'expectedToken',settlement->>'token','share',20000000,'collectionConfirmed',true,'settlementModel','owner_debit_supplier_charge'));
  raise exception 'Allowed another 6m to be distributed' using errcode='P0022';
 exception when others then if sqlstate='P0022' then raise;end if;end;
 approved:=public.solar_profit_workspace('approve',gen_random_uuid(),jsonb_build_object('id',request_no,'expectedToken',settlement->>'token','share',14000000,'collectionConfirmed',true,'settlementModel','owner_debit_supplier_charge'));
 after_settlement:=public.solar_profit_workspace('balance',null,'{"ownerId":"all"}');
 assert(after_settlement->>'remaining')::numeric-(initial_company->>'remaining')::numeric=6000000,'company retained spread changed after actual payout';
 perform set_config('request.jwt.claim.sub',seller::text,true);
 result:=public.solar_profit_workspace('overview');
 assert(result->>'available')::numeric=0 and (result->>'retainedProfit')::numeric=0,'personal retained balance or checkpoint not exhausted';
end $test$;
reset role;
do $integrity$
declare invoice public.transactions;
begin
 select * into strict invoice from public.transactions where id=current_setting('fixture.bill')::bigint;
 assert invoice.cost=30000000 and invoice.profit=20000000 and invoice.total=50000000;
 assert(select sum(qty*cost)=30000000 from public.transaction_items where transaction_id=invoice.id),'inventory snapshots overwritten with seller price';
 assert solar_private.cash_balance('00000000-0000-0000-0000-000000412511')=36000000,'unexpected cash beyond sale collection and one earned payout';
 assert(select count(*)=1 and sum(total)=14000000 from public.transactions t where t.profit_settlement_id in
  (select s.id from solar_private.profit_settlements s where s.owner_id='00000000-0000-0000-0000-000000412511')),'unexpected cash/supplier posting for pricing spread';
 assert(select value=14000000 from solar_private.profit_checkpoints where owner_id='00000000-0000-0000-0000-000000412511' and source_key='tx:'||invoice.id);
end $integrity$;
rollback;
\echo PASS company and personal figures, supervisor view, recognized settlement and single payout.
