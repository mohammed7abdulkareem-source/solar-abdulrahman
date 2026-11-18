\set ON_ERROR_STOP on
load 'safeupdate';
begin;
insert into public.profiles(id,display_name,is_admin,user_type,phone,permissions)values
 ('00000000-0000-0000-0000-000000419801','V419 derived cost admin',true,'admin_staff','07700419801','{}'),
 ('00000000-0000-0000-0000-000000419802','V419 derived cost installer',false,'installer','07700419802','{}'),
 ('00000000-0000-0000-0000-000000419803','V419 derived cost staff',false,'admin_staff','07700419803','{"purchase":true,"sale":true}');
insert into public.suppliers(id,name)values(-419801,'V419 derived supplier');
insert into public.customers(id,name,customer_type,owner_id)values
 (-419801,'V419 derived wholesale','wholesale','00000000-0000-0000-0000-000000419801'),
 (-419802,'V419 derived system','system','00000000-0000-0000-0000-000000419801');
insert into public.products(id,code,name,qty,cost)values(-419801,'V419-DERIVED-A','V419 affected material',0,0),(-419802,'V419-DERIVED-B','V419 unchanged material',10,200);
update solar_private.operation_controls set system_free_pricing=false,system_markup_percent=25,revision=revision+1 where id;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419801',true);
select set_config('derived.purchase',public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"V419 derived supplier","mode":"credit","sourceCurrency":"IQD","warehouseId":1,"items":[{"id":-419801,"qty":10,"price":100}]}')->>'id',true);
select set_config('derived.sale',public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"V419 derived wholesale","mode":"credit","warehouseId":1,"expenses":20,"expensesOnCustomer":false,"items":[{"id":-419801,"qty":4,"price":200},{"id":-419802,"qty":1,"price":300}]}')->>'id',true);
select set_config('derived.unrelated',public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"V419 derived wholesale","mode":"credit","warehouseId":1,"items":[{"id":-419802,"qty":1,"price":300}]}')->>'id',true);
select set_config('derived.system',public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","party":"V419 derived system","mode":"credit","warehouseId":1,"installerId":"00000000-0000-0000-0000-000000419802","customerAddress":"V419 address","total":2000,"items":[{"id":-419801,"qty":2,"price":0},{"id":-419802,"qty":1,"price":0}]}')->>'id',true);
reset role;
update public.transactions set warehouse_status='ready',warehouse_prepared_at=now(),warehouse_prepared_by='00000000-0000-0000-0000-000000419801'where id in(current_setting('derived.sale')::bigint,current_setting('derived.system')::bigint);
update public.transactions set installation_status='closed',installation_revision=installation_revision+1,installation_closed_at=now(),installation_report='{"test":"completed before correction"}'where id=current_setting('derived.system')::bigint;
set constraints all immediate;
set constraints all deferred;
update solar_private.operation_controls set system_markup_percent=15,revision=revision+1 where id;
select set_config('derived.before',(select jsonb_agg(to_jsonb(t)order by id)::text from public.transactions t where id in(current_setting('derived.sale')::bigint,current_setting('derived.system')::bigint)),true);
select set_config('derived.lines_before',(select jsonb_agg(to_jsonb(i)order by id)::text from public.transaction_items i where transaction_id in(current_setting('derived.sale')::bigint,current_setting('derived.system')::bigint)),true);
select set_config('derived.unrelated_before',(select to_jsonb(t)::text from public.transactions t where id=current_setting('derived.unrelated')::bigint),true);
select set_config('derived.stock_before',(select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)::text from solar_private.warehouse_stocks t),true);
select set_config('derived.product_before',(select jsonb_agg(to_jsonb(t)order by id)::text from public.products t),true);
select set_config('derived.notice_before',(select count(*)::text from public.solar_notifications),true);
select set_config('derived.cash_before',(select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text),'[]')::text from public.cash_ledger t),true);
select set_config('derived.finance_before',jsonb_build_object('supplier',(select coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')from solar_private.supplier_fx_entries x),'wallet',(select coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')from solar_private.wallet_fx_entries x),'cash',(select coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')from public.solar_cash_entries x),'settlements',(select coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')from solar_private.profit_settlements x),'checkpoints',(select coalesce(jsonb_agg(to_jsonb(x)order by owner_id,source_key),'[]')from solar_private.profit_checkpoints x))::text,true);
select set_config('derived.request','00000000-0000-0000-0000-000000419899',true);
insert into solar_private.purchase_corrections(request_id,invoice_id,actor_id,before_invoice,before_items,plan)
select current_setting('derived.request')::uuid,t.id,auth.uid(),to_jsonb(t),(select jsonb_agg(to_jsonb(i))from public.transaction_items i where i.transaction_id=t.id),
 jsonb_build_object('affectedLines',(
  select jsonb_agg(jsonb_build_object('itemId',i.id,'invoiceId',i.transaction_id,'productId',i.product_id,'before',jsonb_build_object('cost',i.cost,'costBasis',i.cost_basis),
   'after',jsonb_build_object('cost',case when i.transaction_id=current_setting('derived.sale')::bigint then 150 else 1000 end,'costBasis',i.cost_basis||jsonb_build_object('bookUnitCost',case when i.transaction_id=current_setting('derived.sale')::bigint then 150 else 1000 end,'valuationUnitCost',case when i.transaction_id=current_setting('derived.sale')::bigint then 150 else 1000 end,'currencyComponents',jsonb_build_object('usd',0,'iqd',case when i.transaction_id=current_setting('derived.sale')::bigint then 150 else 1000 end))))order by i.id)
  from public.transaction_items i where i.transaction_id in(current_setting('derived.sale')::bigint,current_setting('derived.system')::bigint)and i.product_id=-419801),
 'affectedInvoices',(
  select jsonb_agg(jsonb_build_object('id',s.id,'ownerId',s.created_by,'before',jsonb_build_object('cost',s.cost,'profit',s.profit,'pricingRevision',s.pricing_revision),
   'after',jsonb_build_object('cost',case when s.kind='sale'then 800 else 2200 end,'profit',case when s.kind='sale'then 280 else -200 end),'legacySettlementId',null)order by s.id)
  from public.transactions s where s.id in(current_setting('derived.sale')::bigint,current_setting('derived.system')::bigint)))
from public.transactions t where t.id=current_setting('derived.purchase')::bigint;
insert into solar_private.purchase_correction_execution(request_id,invoice_id,actor_id,backend_txid)values(current_setting('derived.request')::uuid,current_setting('derived.purchase')::bigint,auth.uid(),txid_current());

-- An untrusted role cannot manufacture or invoke the protected path, even if
-- it sets convincing custom flags in its own transaction.
set local role authenticated;
select set_config('solar.purchase_derived_cost','true',true);
select set_config('solar.purchase_correction',current_setting('derived.request'),true);
do $$begin
 if has_function_privilege('authenticated','solar_private.apply_purchase_derived_cost(uuid)','execute')or has_function_privilege('authenticated','solar_private.purchase_derived_cost_allowed(text,jsonb,jsonb)','execute')or has_table_privilege('authenticated','solar_private.purchase_correction_execution','insert')then raise exception 'Derived path exposed';end if;
 begin perform solar_private.apply_purchase_derived_cost(current_setting('derived.request')::uuid);raise exception 'Authenticated caller invoked derived writer';exception when insufficient_privilege then null;end;
 begin update public.transaction_items set cost=1000 where transaction_id=current_setting('derived.sale')::bigint and product_id=-419801;raise exception 'Forged flag authorized raw protected item update';exception when insufficient_privilege then null;end;
end$$;
reset role;
-- Invalid/stale plan is rejected before rewriting the receipt.
do $$begin
 begin perform solar_private.apply_purchase_derived_cost(gen_random_uuid());raise exception 'Missing proof accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419803',true);
 begin perform solar_private.apply_purchase_derived_cost(current_setting('derived.request')::uuid);raise exception 'Other actor accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419801',true);
end$$;
do $$declare before_row jsonb;after_row jsonb;change jsonb;begin
 select to_jsonb(t)into before_row from public.transactions t where id=current_setting('derived.sale')::bigint;
 select value into change from solar_private.purchase_corrections c,jsonb_array_elements(c.plan->'affectedInvoices')where c.request_id=current_setting('derived.request')::uuid and value->>'id'=current_setting('derived.sale');
 after_row:=before_row||jsonb_build_object('cost',change->'after'->'cost','profit',change->'after'->'profit','pricing_revision',(before_row->>'pricing_revision')::bigint+1);
 if not solar_private.purchase_derived_cost_allowed('transactions',before_row,after_row)then raise exception 'Exact header plan not recognized';end if;
 if solar_private.purchase_derived_cost_allowed('transactions',before_row,after_row||'{"notes":"forged alongside derived cost"}')then raise exception 'Derived proof permitted unrelated header field';end if;
 begin update solar_private.purchase_correction_execution set backend_txid=-1 where request_id=current_setting('derived.request')::uuid;perform solar_private.apply_purchase_derived_cost(current_setting('derived.request')::uuid);raise exception 'Other transaction proof accepted';exception when insufficient_privilege then null;end;
end$$;
select solar_private.apply_purchase_derived_cost(current_setting('derived.request')::uuid);
-- Deferred constraints must recognize the exact audit plan at transaction end.
set constraints all immediate;
do $$declare t jsonb;prior jsonb;i jsonb;old_i jsonb;begin
 for t in select to_jsonb(x)from public.transactions x where x.id in(current_setting('derived.sale')::bigint,current_setting('derived.system')::bigint)loop
  select value into prior from jsonb_array_elements(current_setting('derived.before')::jsonb)where value->>'id'=t->>'id';
  if(t-array['cost','profit','pricing_revision'])is distinct from(prior-array['cost','profit','pricing_revision'])then raise exception 'Derived cost changed nonfinancial receipt fields';end if;
  if(t->>'pricing_revision')::bigint<>(prior->>'pricing_revision')::bigint+1 then raise exception 'Stale edit revision not invalidated';end if;
  if t->>'warehouse_status'<>'ready'then raise exception 'Prepared receipt reopened';end if;
  if t->>'kind'='system'and(t->>'installation_status'<>'closed'or t->>'system_min_profit_percent'<>'25')then raise exception 'Operational state or pricing snapshot changed';end if;
 end loop;
 for i in select to_jsonb(x)from public.transaction_items x where x.transaction_id in(current_setting('derived.sale')::bigint,current_setting('derived.system')::bigint)loop
  select value into old_i from jsonb_array_elements(current_setting('derived.lines_before')::jsonb)where value->>'id'=i->>'id';
  if i->>'product_id'='-419801'then
   if(i-array['cost','cost_basis'])is distinct from(old_i-array['cost','cost_basis'])or(i->>'cost')::numeric<>(case when(i->>'transaction_id')::bigint=current_setting('derived.sale')::bigint then 150 else 1000 end)then raise exception 'Affected line did not stay cost-only';end if;
  elsif i is distinct from old_i then raise exception 'Other material on same receipt changed';end if;
 end loop;
 if(select to_jsonb(x)::text from public.transactions x where x.id=current_setting('derived.unrelated')::bigint)<>current_setting('derived.unrelated_before')then raise exception 'Unrelated receipt changed';end if;
 if(select jsonb_agg(to_jsonb(x)order by warehouse_id,product_id)::text from solar_private.warehouse_stocks x)<>current_setting('derived.stock_before')then raise exception 'Derived costs changed physical stock';end if;
 if(select jsonb_agg(to_jsonb(x)order by id)::text from public.products x)<>current_setting('derived.product_before')then raise exception 'Derived costs changed current material rows';end if;
 if(select count(*)::text from public.solar_notifications)<>current_setting('derived.notice_before')then raise exception 'Derived costs notified a warehouse reopen';end if;
 if(select coalesce(jsonb_agg(to_jsonb(x)order by to_jsonb(x)::text),'[]')::text from public.cash_ledger x)<>current_setting('derived.cash_before')then raise exception 'Derived costs changed money';end if;
 if jsonb_build_object('supplier',(select coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')from solar_private.supplier_fx_entries x),'wallet',(select coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')from solar_private.wallet_fx_entries x),'cash',(select coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')from public.solar_cash_entries x),'settlements',(select coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')from solar_private.profit_settlements x),'checkpoints',(select coalesce(jsonb_agg(to_jsonb(x)order by owner_id,source_key),'[]')from solar_private.profit_checkpoints x))::text<>current_setting('derived.finance_before')then raise exception 'Derived write changed financial ledgers or paid settlements';end if;
 begin perform solar_private.apply_purchase_derived_cost(current_setting('derived.request')::uuid);raise exception 'Repeated derived writer accepted';exception when sqlstate'PT409'then null;end;
 -- Changing price, quantity or arbitrary cost is never covered by the plan.
 begin update public.transactions set total=1 where id=current_setting('derived.system')::bigint;raise exception 'Exact plan bypass leaked into price edit';exception when sqlstate'PT422'then null;end;
 begin update public.transaction_items set cost=1200 where transaction_id=current_setting('derived.system')::bigint and product_id=-419801;raise exception 'Exact plan bypass leaked into arbitrary cost';exception when sqlstate'PT422'then null;end;
end$$;
-- Production inserts its proof and applies cost writes within one RPC. The
-- volatile match helper must see that freshly inserted protected context.
do $$declare nonce uuid:=gen_random_uuid();source jsonb;derived jsonb;begin
 select plan into source from solar_private.purchase_corrections where request_id=current_setting('derived.request')::uuid;
 select jsonb_build_object('affectedLines',(select jsonb_agg(jsonb_build_object('itemId',i.id,'invoiceId',i.transaction_id,'productId',i.product_id,'before',jsonb_build_object('cost',i.cost,'costBasis',i.cost_basis),'after',jsonb_build_object('cost',i.cost,'costBasis',i.cost_basis||'{"derivedProofSameRPC":true}')))from public.transaction_items i where i.transaction_id=current_setting('derived.system')::bigint and i.product_id=-419801),'affectedInvoices',(select jsonb_agg(jsonb_build_object('id',t.id,'before',jsonb_build_object('cost',t.cost,'profit',t.profit,'pricingRevision',t.pricing_revision),'after',jsonb_build_object('cost',t.cost,'profit',t.profit)))from public.transactions t where t.id=current_setting('derived.system')::bigint))into derived;
 insert into solar_private.purchase_corrections(request_id,invoice_id,actor_id,before_invoice,before_items,plan)select nonce,invoice_id,actor_id,before_invoice,before_items,derived from solar_private.purchase_corrections where request_id=current_setting('derived.request')::uuid;
 insert into solar_private.purchase_correction_execution(request_id,invoice_id,actor_id,backend_txid)values(nonce,current_setting('derived.purchase')::bigint,auth.uid(),txid_current());
 perform solar_private.apply_purchase_derived_cost(nonce);
 if not exists(select 1 from public.transactions where id=current_setting('derived.system')::bigint and warehouse_status='ready'and installation_status='closed'and system_min_profit_percent=25)then raise exception 'Same RPC proof visibility lost derived protection';end if;
end$$;
rollback;
\echo PASS exact protected derived writes preserve all other lines/fields, physical stock, cash, warehouse/install state and old pricing snapshots; queued guards honor only current actor/transaction plan; forged flags and arbitrary/stale/repeated writes fail
