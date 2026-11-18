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
select -419700-n,'COST-ORACLE-'||n,'مادة مراجعة الكلفة '||n,0,0 from generate_series(1,11)n;
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


-- Historical warehouse/system edits saved full sum precision; correction keeps
-- that proven mode and changes only the affected cost/profit.
do $$declare target bigint;sale bigint;unchanged jsonb;header_before jsonb;rid uuid;bad_plan jsonb;before_line jsonb;failed boolean;begin
 perform pg_temp.oracle_buy(-419701,2,100);target:=pg_temp.oracle_buy(-419701,1,101.01);
 perform pg_temp.oracle_buy(-419704,2,20);
 sale:=pg_temp.oracle_sell(jsonb_build_array(jsonb_build_object('id',-419701,'qty',1,'price',200),jsonb_build_object('id',-419704,'qty',1,'price',50)));
 update public.transactions set cost=120.336667,profit=129.663333,warehouse_status='ready',warehouse_prepared_at=now(),warehouse_prepared_by=auth.uid()where id=sale;
 select to_jsonb(i)into unchanged from public.transaction_items i where transaction_id=sale and product_id=-419704;
 select to_jsonb(t)-'cost'-'profit'-'pricing_revision'into header_before from public.transactions t where id=sale;
 perform pg_temp.oracle_correct(target,1,102.02);
 assert(select cost=120.673333 and profit=129.326667 from public.transactions where id=sale),'Historical exact cost was rounded';
 perform pg_temp.oracle_correct(target,1,103.04);
 assert(select cost=121.013333 and profit=128.986667 from public.transactions where id=sale),'Repeated exact correction drifted';
 assert(select to_jsonb(i)from public.transaction_items i where transaction_id=sale and product_id=-419704)=unchanged,'Unrelated material changed';
 assert(select to_jsonb(t)-'cost'-'profit'-'pricing_revision'from public.transactions t where id=sale)=header_before,'Historical nonfinancial fields changed';
 -- A protected plan cannot switch exact mode to an arbitrary rounded header.
 select to_jsonb(i)into before_line from public.transaction_items i where transaction_id=sale and product_id=-419701;
 select jsonb_build_object('affectedLines',jsonb_build_array(jsonb_build_object('itemId',i.id,'invoiceId',sale,'productId',i.product_id,'before',jsonb_build_object('cost',i.cost,'costBasis',i.cost_basis),'after',jsonb_build_object('cost',101.333,'costBasis',i.cost_basis||'{"precisionRejectionProbe":true}'))),'affectedInvoices',jsonb_build_array(jsonb_build_object('id',sale,'before',jsonb_build_object('cost',t.cost,'profit',t.profit,'pricingRevision',t.pricing_revision),'after',jsonb_build_object('cost',121.33,'profit',128.67))))into bad_plan
 from public.transaction_items i join public.transactions t on t.id=i.transaction_id where i.transaction_id=sale and i.product_id=-419701;
 failed:=false;
 begin
  rid:=gen_random_uuid();
  insert into solar_private.purchase_corrections(request_id,invoice_id,actor_id,before_invoice,before_items,plan)select rid,t.id,auth.uid(),to_jsonb(t),'[]',bad_plan from public.transactions t where id=target;
  insert into solar_private.purchase_correction_execution(request_id,invoice_id,actor_id,backend_txid)values(rid,target,auth.uid(),txid_current());
  perform solar_private.apply_purchase_derived_cost(rid);
 exception when sqlstate'22023'then failed:=true;end;
 assert failed,'Derived helper accepted a wrong precision mode';
 assert(select to_jsonb(i)from public.transaction_items i where transaction_id=sale and product_id=-419701)=before_line,'Rejected precision plan changed line';
end$$;

-- Current rounded headers stay rounded, including repeat corrections.
do $$declare target bigint;sale bigint;begin
 perform pg_temp.oracle_buy(-419702,3,100);target:=pg_temp.oracle_buy(-419702,2,101.01);sale:=pg_temp.oracle_sell(-419702,1,200);
 assert(select cost=100.40 from public.transactions where id=sale);
 perform pg_temp.oracle_correct(target,2,102.02);assert(select cost=100.81 and profit=99.19 from public.transactions where id=sale);
 perform pg_temp.oracle_correct(target,2,103.03);assert(select cost=101.21 and profit=98.79 from public.transactions where id=sale);
end$$;

-- When both historical representations match, canonical round2 wins.
do $$declare target bigint;sale bigint;begin
 perform pg_temp.oracle_buy(-419703,3,100);target:=pg_temp.oracle_buy(-419703,2,100);sale:=pg_temp.oracle_sell(-419703,1,200);
 perform pg_temp.oracle_correct(target,2,100.01);
 assert(select cost=100 and profit=100 from public.transactions where id=sale),'Equal original precision did not use canonical round2';
 assert(select cost=100.004 from public.transaction_items where transaction_id=sale),'Canonical rounded header changed exact unit cost';
end$$;

-- Actual pre-existing totals with unexplained offsets still block; no epsilon
-- allowance is used. System installation expense remains part of profit.
do $$declare t public.transactions;r jsonb;failed boolean;begin
 t.kind:='system';t.total:=10000000;t.cost:=9479391.320754;t.profit:=520608.679246;t.expenses:=0;t.installation_expenses:=0;
 r:=solar_private.purchase_derived_totals(t,9479391.320754,9479392.123456);
 assert r->>'mode'='exact'and(r->>'cost')::numeric=9479392.123456 and(r->>'profit')::numeric=520607.876544;
 t.installation_expenses:=25;t.profit:=t.profit-25;r:=solar_private.purchase_derived_totals(t,9479391.320754,9479392.123456);
 assert(r->>'profit')::numeric=520582.876544;
 failed:=false;begin perform solar_private.purchase_derived_totals(t,9479391.31,9479392.123456);exception when sqlstate'PT409'then failed:=true;end;
 assert failed,'Unexplained header cost offset accepted';
 t.profit:=t.profit+1;failed:=false;begin perform solar_private.purchase_derived_totals(t,9479391.320754,9479392.123456);exception when sqlstate'PT409'then failed:=true;end;
 assert failed,'Unexplained profit offset accepted';
 assert not has_function_privilege('authenticated','solar_private.purchase_derived_totals(public.transactions,numeric,numeric)','execute');
end$$;
rollback;
\echo PASS historical exact and canonical rounded headers retain their precision, repeat safely and reject inconsistent/wrong-mode plans
