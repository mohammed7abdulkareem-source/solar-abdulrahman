-- A real warehouse addition represented in the old empty-basis format.
-- All accounting uses public RPCs; only that isolated historical metadata is
-- restored to its documented legacy representation. Everything rolls back.
\set ON_ERROR_STOP on
load 'safeupdate';
begin;
insert into public.profiles(id,display_name,is_admin,user_type,phone,active,permissions)values
 ('00000000-0000-0000-0000-000000419920','Legacy basis admin',true,'admin_staff','07700419920',true,'{}'),
 ('00000000-0000-0000-0000-000000419921','Legacy basis owner',false,'admin_staff','07700419921',true,'{"purchase":true,"system":true,"warehouse":true,"profit":true}'),
 ('00000000-0000-0000-0000-000000419922','Legacy basis installer',false,'installer','07700419922',true,'{}');
insert into public.suppliers(id,name,account_currency)values(-419921,'Legacy basis supplier','IQD');
insert into public.customers(id,name,customer_type,owner_id)values(-419921,'Legacy basis customer','system','00000000-0000-0000-0000-000000419921');
insert into public.products(id,code,name,qty,cost)values(-419921,'LEGACY-BASIS-UNCHANGED','Unchanged material',2,100),(-419922,'LEGACY-BASIS-USD','Legacy USD material',0,0);
update solar_private.operation_controls set system_free_pricing=true,system_paused=false,purchase_paused=false where id;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419920',true);
select public.solar_exchange_rate_set(1690,(public.solar_exchange_rate_get()->>'revision')::bigint);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419921',true);

-- Deterministic dates represent distinct HTTP transactions inside rollback.
create function pg_temp.legacy_stamp(nonce uuid,invoice_id bigint,stamp timestamptz)returns void
language plpgsql security definer set search_path='' as $$
declare t public.transactions;ctx text:=coalesce(current_setting('solar.fx_context',true),'');begin
 select * into t from public.transactions where id=invoice_id;
 if t.kind='purchase'then perform set_config('solar.fx_context',jsonb_build_object('accountRevision',t.account_revision,'marketRate',t.market_rate,'cashCurrency',t.cash_currency)::text,true);end if;
 update public.transactions set created_at=stamp where id=invoice_id;
 perform set_config('solar.fx_context',ctx,true);
 update solar_private.invoice_requests set created_at=stamp where request_id=nonce;
end$$;

do $$declare system_id bigint;purchase_id bigint;nonce uuid;r jsonb;lines jsonb;begin
 nonce:=gen_random_uuid();r:=public.solar_invoice_save(nonce,jsonb_build_object('kind','system','mode','credit','partyId',-419921,'party','Legacy basis customer',
  'warehouseId',solar_private.primary_warehouse(),'installerId','00000000-0000-0000-0000-000000419922','customerAddress','Fixture address','total',200000,
  'items',jsonb_build_array(jsonb_build_object('id',-419921,'qty',1,'price',0))));
 system_id:=(r->>'id')::bigint;perform pg_temp.legacy_stamp(nonce,system_id,'2026-11-01 00:01Z');
 nonce:=gen_random_uuid();r:=public.solar_invoice_save(nonce,jsonb_build_object('kind','purchase','mode','credit','partyId',-419921,'party','Legacy basis supplier',
  'warehouseId',solar_private.primary_warehouse(),'sourceCurrency','USD','exchangeRate',1690,'marketRate',1690,'cashCurrency','IQD','accountRevision',0,'expenses',0,
  'items',jsonb_build_array(jsonb_build_object('id',-419922,'qty',20,'price',6))));
 purchase_id:=(r->>'id')::bigint;perform pg_temp.legacy_stamp(nonce,purchase_id,'2026-11-01 00:02Z');
 select jsonb_agg(jsonb_build_object('lineId',i.id,'productId',i.product_id,'qty',i.qty))into lines from public.transaction_items i where transaction_id=system_id;
 perform public.solar_warehouse_action(system_id,solar_private.warehouse_token(system_id),'save',lines||'[{"productId":-419922,"qty":5}]','Legacy addition fixture');
 update solar_private.warehouse_audit set created_at='2026-11-01 00:03Z' where invoice_id=system_id and action='save';
 -- This reproduces audit40/item189 from the legacy warehouse writer. No
 -- quantity, price, saved financial cost, or global stock basis is changed.
 update public.transaction_items set cost_basis='{}' where transaction_id=system_id and product_id=-419922;
 update solar_private.warehouse_audit a set after_items=(select jsonb_agg(case when(i->>'product_id')::bigint=-419922 then i||'{"cost_basis":{}}'::jsonb else i end)from jsonb_array_elements(a.after_items)i)
  where a.invoice_id=system_id and a.action='save';
 perform public.solar_warehouse_action(system_id,solar_private.warehouse_token(system_id),'ready');
 update solar_private.warehouse_audit set created_at='2026-11-01 00:04Z' where invoice_id=system_id and action='ready';
 perform set_config('legacy.system',system_id::text,true);perform set_config('legacy.purchase',purchase_id::text,true);
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419920',true);
select public.solar_exchange_rate_set(2500,(public.solar_exchange_rate_get()->>'revision')::bigint);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419921',true);

do $$declare t public.transactions;body jsonb;plan jsonb;r jsonb;nonce uuid:=gen_random_uuid();legacy_item bigint;before_system jsonb;other_item jsonb;before_stock jsonb;bad_basis jsonb;
begin
 select * into t from public.transactions where id=current_setting('legacy.purchase')::bigint;
 body:=jsonb_build_object('kind','purchase','mode',t.payment_mode,'partyId',t.party_id,'party',t.party_name,'warehouseId',t.warehouse_id,
  'sourceCurrency',t.source_currency,'cashCurrency',t.cash_currency,'exchangeRate',t.exchange_rate,'marketRate',t.market_rate,'accountRevision',t.account_revision,
  'expenses',t.expenses,'invoiceId',t.id,'expectedRevision',t.pricing_revision,'items',jsonb_build_array(jsonb_build_object('id',-419922,'qty',20,'price',7)));
 select id into legacy_item from public.transaction_items where transaction_id=current_setting('legacy.system')::bigint and product_id=-419922;
 -- A nonempty claimed currency mix must still match the replay exactly.
 foreach bad_basis in array array['{"bookUnitCost":10140,"currencyComponents":{"usd":0,"iqd":10140}}'::jsonb,'null'::jsonb]loop
  update public.transaction_items set cost_basis=bad_basis where id=legacy_item;
  plan:=public.solar_purchase_correction_preview(body);
  assert not(plan->>'canApply')::boolean,'Nonempty or null incorrect basis bypassed component verification';
  assert not exists(select 1 from solar_private.purchase_corrections where invoice_id=t.id),'Blocked preview posted correction';
 end loop;
 update public.transaction_items set cost_basis='{}' where id=legacy_item;
 update public.transaction_items set cost=10141 where id=legacy_item;
 plan:=public.solar_purchase_correction_preview(body);
 assert not(plan->>'canApply')::boolean,'Empty basis incorrectly bypassed the saved financial/book cost comparison';
 update public.transaction_items set cost=10140 where id=legacy_item;
 perform public.solar_warehouse_action(current_setting('legacy.system')::bigint,solar_private.warehouse_token(current_setting('legacy.system')::bigint),'ready');
 update solar_private.warehouse_audit set created_at='2026-11-01 00:05Z' where invoice_id=current_setting('legacy.system')::bigint and action='ready' and created_at>'2026-11-01 00:04Z';
 assert(select warehouse_status='ready'from public.transactions where id=current_setting('legacy.system')::bigint);
 select to_jsonb(x)-'cost'-'profit'-'pricing_revision'into before_system from public.transactions x where id=current_setting('legacy.system')::bigint;
 select to_jsonb(i)into other_item from public.transaction_items i where transaction_id=current_setting('legacy.system')::bigint and product_id=-419921;
 select jsonb_agg(to_jsonb(s)order by warehouse_id)into before_stock from solar_private.warehouse_stocks s where product_id=-419922;
 plan:=public.solar_purchase_correction_preview(body);
 assert(plan->>'canApply')::boolean,coalesce(plan->>'blockedReason','Legacy empty basis not applicable');
 body:=body||jsonb_build_object('purchaseCorrectionToken',plan->>'token');r:=public.solar_invoice_save(nonce,body);
 assert public.solar_invoice_save(nonce,body)=r,'Legacy correction replay changed acknowledgement';
 assert(select qty=15 and cost=11830 and(cost_basis#>>'{currencyComponents,usd}')::numeric=7 and(cost_basis#>>'{currencyComponents,iqd}')::numeric=0 from public.products where id=-419922),'Global proven USD basis changed incorrectly';
 assert(select qty=5 and cost=11830 and(cost_basis->>'bookUnitCost')::numeric=11830 and(cost_basis#>>'{currencyComponents,usd}')::numeric=7 and cost_basis->>'valuationRate'is null from public.transaction_items where id=legacy_item),'Legacy book quote was converted at today FX or assigned an invented rate';
 assert(select cost=59250 and profit=140750 and total=200000 from public.transactions where id=current_setting('legacy.system')::bigint),'Legacy system profit correction is wrong';
 assert(select to_jsonb(x)-'cost'-'profit'-'pricing_revision'from public.transactions x where id=current_setting('legacy.system')::bigint)=before_system,'Correction changed system status/customer/debt';
 assert(select to_jsonb(i)from public.transaction_items i where transaction_id=current_setting('legacy.system')::bigint and product_id=-419921)=other_item,'Unrelated item changed';
 assert(select jsonb_agg(to_jsonb(s)order by warehouse_id)from solar_private.warehouse_stocks s where product_id=-419922)=before_stock,'Price correction changed warehouse quantities';
 assert(select exchange_rate=1690 and market_rate=1690 and total=236600 from public.transactions where id=t.id),'Original purchase rate changed';
end$$;
set constraints all immediate;
rollback;
select 'Legacy empty basis correction and strict nonempty rejection PASS' result;
