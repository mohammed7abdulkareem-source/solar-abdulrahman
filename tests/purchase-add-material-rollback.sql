-- Exercises the public invoice APIs against a disposable PostgreSQL database.
\set ON_ERROR_STOP on
load 'safeupdate';
begin;

insert into public.profiles(id,display_name,is_admin,user_type,active,permissions)
values ('00000000-0000-0000-0000-000000411000','مراجع إضافة المواد',true,'admin_staff',true,'{}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411000',true);
insert into public.suppliers(id,name,account_currency) values (-411000,'مورد إضافة المواد','IQD');
insert into public.customers(id,name,customer_type,owner_id)
values (-411000,'زبون إضافة المواد','wholesale',auth.uid());
insert into public.products(id,code,name,qty,cost) values
 (-411001,'ADD-A','المادة الأصلية',0,0),
 (-411002,'ADD-B','المادة الجديدة',0,0),
 (-411003,'CASH-A','مادة الوصل النقدي',0,0),
 (-411004,'CASH-B','إضافة نقدية',0,0),
 (-411005,'TIE-A','الوصل المعدّل',0,0),
 (-411006,'TIE-B','إضافة متكررة',0,0),
 (-411007,'PRISTINE-A','مادة الوصل غير المستهلك',0,0),
 (-411008,'PRISTINE-B','مادة مضافة إلى الوصل',0,0),
 (-411009,'REMOVED-A','مادة الوصل',0,0),
 (-411010,'REMOVED-B','مادة مرفوعة من الوصل',0,0);
update solar_private.wholesale_pricing_control set enabled=false where id;
update solar_private.operation_controls set sale_paused=false,purchase_paused=false where id;

create function pg_temp.item(material bigint,units numeric,price numeric)
returns jsonb language sql as $$
 select jsonb_build_object('id',material,'qty',units,'price',price)
$$;

-- Model the dates of separate real requests inside one transaction. Correction
-- requests retain now(); an earlier and a later sale straddle that timestamp.
create function pg_temp.issue(kind text,lines jsonb,minutes_from_correction int,
                              source text default 'IQD',expenses numeric default 0,
                              payment text default 'credit')
returns bigint language plpgsql as $$
declare nonce uuid:=gen_random_uuid(); result jsonb; issued public.transactions;
 stamp timestamptz:=now()+minutes_from_correction*interval '1 minute';
 previous_fx text:=coalesce(current_setting('solar.fx_context',true),'');
begin
 result:=public.solar_invoice_save(nonce,jsonb_build_object(
   'kind',kind,'partyId',-411000,'mode',payment,'expenses',expenses,'items',lines,
   'party',case when kind='purchase' then 'مورد إضافة المواد' else 'زبون إضافة المواد' end,
   'warehouseId',solar_private.primary_warehouse(),'sourceCurrency',source,'cashCurrency','IQD',
   'exchangeRate',case when source='USD' then 1000 else 1 end,'marketRate',1000,'accountRevision',0
 ));
 select * into strict issued from public.transactions where id=(result->>'id')::bigint;
 if issued.kind='purchase' then
   perform set_config('solar.fx_context',jsonb_build_object('accountRevision',issued.account_revision,
     'cashCurrency',issued.cash_currency,'marketRate',issued.market_rate)::text,true);
 end if;
 update public.transactions set created_at=stamp where id=issued.id;
 perform set_config('solar.fx_context',previous_fx,true);
 update solar_private.invoice_requests set created_at=stamp where request_id=nonce;
 return issued.id;
end
$$;

create function pg_temp.draft(invoice_id bigint,lines jsonb)
returns jsonb language sql as $$
 select jsonb_build_object(
   'kind','purchase','invoiceId',t.id,'expectedRevision',t.pricing_revision,'items',lines,
   'partyId',t.party_id,'party',t.party_name,'warehouseId',t.warehouse_id,
   'mode',t.payment_mode,'expenses',t.expenses,'sourceCurrency',t.source_currency,
   'exchangeRate',t.exchange_rate,'marketRate',t.market_rate,'cashCurrency',t.cash_currency,
   'accountRevision',t.account_revision)
 from public.transactions t where t.id=invoice_id
$$;

create function pg_temp.confirm(body jsonb,plan jsonb)
returns jsonb language plpgsql as $$
declare nonce uuid:=gen_random_uuid(); attempted jsonb; saved jsonb;
begin
 assert (plan->>'canApply')::boolean, coalesce(plan->>'blockedReason','Missing purchase preview');
 attempted:=body||jsonb_build_object('purchaseCorrectionToken',plan->>'token');
 saved:=public.solar_invoice_save(nonce,attempted);
 assert public.solar_invoice_save(nonce,attempted)=saved,'Retried correction returned a different receipt';
 return saved;
end
$$;

create function pg_temp.cancel_purchase(invoice_id bigint)
returns void language plpgsql as $$
declare nonce uuid:=gen_random_uuid(); ctx jsonb; attempted jsonb; saved jsonb;
begin
 ctx:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',invoice_id));
 assert (ctx->>'directEligible')::boolean,coalesce(ctx->>'blockedReason','Expected direct deletion');
 attempted:=jsonb_build_object('invoiceId',invoice_id,'expectedToken',ctx->>'token');
 saved:=public.solar_receipt_delete_requests('delete_direct',nonce,attempted);
 assert saved->>'status'='deleted',saved::text;
 assert public.solar_receipt_delete_requests('delete_direct',nonce,attempted)=saved;
end
$$;

do $$
declare source_b bigint; target bigint; prior_sale bigint; later_sale bigint; invoice public.transactions;
 old_item_id bigint; new_item_id bigint; body jsonb; plan jsonb; projected_b jsonb;
 prior_b jsonb; original_note jsonb; saved jsonb; cash_before numeric;
 lines jsonb:=jsonb_build_array(pg_temp.item(-411001,10,2),pg_temp.item(-411002,4,5));
begin
 perform public.solar_exchange_rate_set(1000,(public.solar_exchange_rate_get()->>'revision')::bigint);
 source_b:=pg_temp.issue('purchase',jsonb_build_array(pg_temp.item(-411002,10,1000)),-40);
 perform pg_temp.issue('purchase',jsonb_build_array(pg_temp.item(-411001,10,1000)),-35);
 target:=pg_temp.issue('purchase',jsonb_build_array(pg_temp.item(-411001,10,2)),-30,'USD',1200);
 prior_sale:=pg_temp.issue('sale',jsonb_build_array(pg_temp.item(-411001,2,3000),pg_temp.item(-411002,2,3000)),-20);
 select to_jsonb(i) into strict prior_b from public.transaction_items i where transaction_id=prior_sale and product_id=-411002;
 select * into strict invoice from public.transactions where id=target;
 select id into strict old_item_id from public.transaction_items where transaction_id=target;
 select to_jsonb(e) into strict original_note from solar_private.supplier_fx_entries e where e.transaction_id=target;
 cash_before:=solar_private.cash_balance(auth.uid());

 -- Receipt currency is historical; this rate governs only a new sale.
 perform public.solar_exchange_rate_set(1500,(public.solar_exchange_rate_get()->>'revision')::bigint);
 body:=pg_temp.draft(target,lines);
 plan:=public.solar_purchase_correction_preview(body);
 assert (plan->>'canApply')::boolean, coalesce(plan->>'blockedReason','Adding B should be supported');
 select i into strict projected_b from jsonb_array_elements(plan->'items') i where(i->>'id')::bigint=-411002;
 assert (projected_b#>>'{before,qty}')::numeric=8 and (projected_b#>>'{after,qty}')::numeric=12
    and (projected_b#>>'{after,cost}')::numeric=2383.333333,'Incorrect weighted-cost preview for B';
 assert (plan#>>'{delta,accountAmount}')::numeric=20000 and (plan#>>'{delta,cashAmount}')::numeric=0;
 assert (select qty=8 and cost=1000 from public.products where id=-411002),'Preview changed B';
 assert not exists(select 1 from public.transaction_items where transaction_id=target and product_id=-411002);
 saved:=pg_temp.confirm(body,plan);
 assert (saved->>'id')::bigint=target;
 assert (select receipt_no=invoice.receipt_no and created_at=invoice.created_at and exchange_rate=1000
    and source_subtotal=40 and expenses=1200 and total=41200 and account_amount=41200
    from public.transactions where id=target),'Purchase identity, FX or receipt amount is wrong';
 assert (select id=old_item_id and landed_cost=2060 from public.transaction_items where transaction_id=target and product_id=-411001);
 select id into strict new_item_id from public.transaction_items where transaction_id=target and product_id=-411002
    and qty=4 and source_price=5 and price=5000 and landed_cost=5150 and product_name='المادة الجديدة';
 assert (select qty=12 and cost=2383.333333 from public.products where id=-411002);
 assert (select qty=12 from solar_private.warehouse_stocks where product_id=-411002 and warehouse_id=invoice.warehouse_id);
 assert (select to_jsonb(i) from public.transaction_items i where id=(prior_b->>'id')::bigint)=prior_b,
    'Adding B repriced B on a sale that preceded its addition';
 -- Allocating the original freight over both lines lowers A's historical cost.
 assert (select cost=5060 and total=12000 and profit=6940 from public.transactions where id=prior_sale);
 assert (select to_jsonb(e) from solar_private.supplier_fx_entries e where e.transaction_id=target)=original_note;
 assert (select sum(delta)=61200 from solar_private.supplier_fx_entries where supplier_id=-411000);
 assert solar_private.cash_balance(auth.uid())=cash_before;

 -- A purchase earlier than the target must also see B arriving on its real
 -- addition date when it is corrected. Reversing that correction restores
 -- the same purchase state without rewriting the receipt's original date.
 body:=pg_temp.draft(source_b,jsonb_build_array(pg_temp.item(-411002,10,1200)));
 perform pg_temp.confirm(body,public.solar_purchase_correction_preview(body));
 assert (select cost=1200 from public.transaction_items where transaction_id=prior_sale and product_id=-411002);
 assert (select qty=12 and cost=2516.666667 from public.products where id=-411002),
    'Correction of an earlier purchase replayed B at the old receipt date';
 body:=pg_temp.draft(source_b,jsonb_build_array(pg_temp.item(-411002,10,1000)));
 perform pg_temp.confirm(body,public.solar_purchase_correction_preview(body));
 assert (select qty=12 and cost=2383.333333 from public.products where id=-411002);

 later_sale:=pg_temp.issue('sale',jsonb_build_array(pg_temp.item(-411002,2,8000)),10);
 assert (select cost=6433.33 and total=16000 from public.transactions where id=later_sale);
 -- Correct B on the same target again and cancel after units have sold.
 lines:=jsonb_build_array(pg_temp.item(-411001,10,2),pg_temp.item(-411002,4,10));
 body:=pg_temp.draft(target,lines);
 perform pg_temp.confirm(body,public.solar_purchase_correction_preview(body));
 assert (select id=new_item_id and source_price=10 and landed_cost=10200 from public.transaction_items where transaction_id=target and product_id=-411002);
 assert (select cost=1000 from public.transaction_items where transaction_id=prior_sale and product_id=-411002);
 assert (select qty=10 and cost=4066.666667 from public.products where id=-411002);
 assert (select cost=11466.67 and total=16000 from public.transactions where id=later_sale);
 perform pg_temp.cancel_purchase(target);
 assert not exists(select 1 from public.transactions where id=target);
 assert (select qty=8 and cost=1000 from public.products where id=-411001);
 assert (select qty=6 and cost=1000 from public.products where id=-411002);
 assert (select qty=6 from solar_private.warehouse_stocks where product_id=-411002 and warehouse_id=invoice.warehouse_id);
 assert (select cost=4000 and total=12000 from public.transactions where id=prior_sale);
 assert (select cost=2000 and total=16000 from public.transactions where id=later_sale);
 assert (select sum(delta)=20000 from solar_private.supplier_fx_entries where supplier_id=-411000);
 assert solar_private.cash_balance(auth.uid())=cash_before;
end
$$;

-- A new stock row on a cash purchase must debit the current cashier exactly
-- once. No existing balance in this product or in the receiving warehouse.
do $$
declare target bigint; body jsonb; plan jsonb; initial_cash numeric;
begin
 initial_cash:=solar_private.cash_balance(auth.uid());
 target:=pg_temp.issue('purchase',jsonb_build_array(pg_temp.item(-411003,10,100)),-35,'IQD',0,'cash');
 perform pg_temp.issue('purchase',jsonb_build_array(pg_temp.item(-411003,5,100)),-25);
 body:=pg_temp.draft(target,jsonb_build_array(pg_temp.item(-411003,10,100),pg_temp.item(-411004,2,300)));
 plan:=public.solar_purchase_correction_preview(body);
 assert (plan->>'canApply')::boolean, coalesce(plan->>'blockedReason','Expected cash purchase addition');
 assert (plan#>>'{delta,cashAmount}')::numeric=600;
 perform pg_temp.confirm(body,plan);
 assert solar_private.cash_balance(auth.uid())=initial_cash-1600;
 assert (select qty=2 and cost=300 from public.products where id=-411004);
 perform pg_temp.cancel_purchase(target);
 assert solar_private.cash_balance(auth.uid())=initial_cash;
 assert (select qty=0 from public.products where id=-411004);
end
$$;

-- Equal timestamps occur in bulk imports. The new line's second inclusion
-- follows both sales after it was removed and then re-added to the receipt.
do $$
declare opening bigint; target bigint; first_sale bigint; second_sale bigint;
 original_lines jsonb:=jsonb_build_array(pg_temp.item(-411005,10,100));
 added jsonb:=original_lines||jsonb_build_array(pg_temp.item(-411006,3,120));
 body jsonb; plan jsonb; attempted jsonb; rejected boolean:=false; nonce uuid:=gen_random_uuid();
begin
 opening:=pg_temp.issue('purchase',jsonb_build_array(pg_temp.item(-411006,4,100)),0);
 target:=pg_temp.issue('purchase',original_lines,0);
 perform pg_temp.issue('purchase',jsonb_build_array(pg_temp.item(-411005,1,100)),0);
 body:=pg_temp.draft(target,added);
 plan:=public.solar_purchase_correction_preview(body);
 assert (plan->>'canApply')::boolean,coalesce(plan->>'blockedReason','Valid addition expected');
 attempted:=body||jsonb_build_object('purchaseCorrectionToken',plan->>'token');

 -- A sale of the proposed product changes its cost pool after the preview.
 first_sale:=pg_temp.issue('sale',jsonb_build_array(pg_temp.item(-411006,1,140)),0);
 begin
   perform public.solar_invoice_save(nonce,attempted);
 exception when sqlstate 'PT409' then rejected:=true;
 end;
 assert rejected,'The new material changed after preview; its stale token was accepted';
 assert not exists(select 1 from public.transaction_items where transaction_id=target and product_id=-411006);
 assert not exists(select 1 from solar_private.invoice_requests where request_id=nonce);
 perform pg_temp.confirm(body,public.solar_purchase_correction_preview(body));
 assert (select qty=6 and cost=110 from public.products where id=-411006);
 second_sale:=pg_temp.issue('sale',jsonb_build_array(pg_temp.item(-411006,1,140)),0);

 body:=pg_temp.draft(target,original_lines);
 perform pg_temp.confirm(body,public.solar_purchase_correction_preview(body));
 assert (select qty=2 and cost=100 from public.products where id=-411006);
 assert (select cost=100 from public.transactions where id=second_sale);

 added:=original_lines||jsonb_build_array(pg_temp.item(-411006,2,160));
 body:=pg_temp.draft(target,added);
 perform pg_temp.confirm(body,public.solar_purchase_correction_preview(body));
 assert (select qty=4 and cost=130 from public.products where id=-411006);
 body:=pg_temp.draft(opening,jsonb_build_array(pg_temp.item(-411006,4,120)));
 perform pg_temp.confirm(body,public.solar_purchase_correction_preview(body));
 assert (select qty=4 and cost=140 from public.products where id=-411006),'Material re-add anchored to its old inclusion';
 assert (select bool_and(cost=120 and profit=20) from public.transactions where id in(first_sale,second_sale));
 body:=pg_temp.draft(target,original_lines||jsonb_build_array(pg_temp.item(-411006,2,180)));
 perform pg_temp.confirm(body,public.solar_purchase_correction_preview(body));
 assert (select qty=4 and cost=150 from public.products where id=-411006);
end
$$;

-- A pristine purchase retains its ordinary editor and a durable receipt date
-- for each added line, including after a later change to its price or count.
do $$
declare source_b bigint; target_a bigint; prior_sale bigint; r jsonb; plan jsonb; raw jsonb; marker jsonb; second jsonb;
begin
 perform public.solar_exchange_rate_set(1000,(public.solar_exchange_rate_get()->>'revision')::bigint);
 source_b:=pg_temp.issue('purchase',jsonb_build_array(pg_temp.item(-411008,10,1000)),-50);
 prior_sale:=pg_temp.issue('sale',jsonb_build_array(pg_temp.item(-411008,2,2500)),-40);
 target_a:=pg_temp.issue('purchase',jsonb_build_array(pg_temp.item(-411007,3,100)),-30);
 raw:=pg_temp.draft(target_a,jsonb_build_array(pg_temp.item(-411007,3,100),pg_temp.item(-411008,4,2000)));
 plan:=public.solar_purchase_correction_preview(raw);
 assert (plan->>'canApply')::boolean and not (plan->>'requiresCorrection')::boolean, plan::text;
 r:=public.solar_invoice_save(gen_random_uuid(),raw);
 select v into strict marker from public.transactions t, jsonb_array_elements(t.purchase_stock) v where t.id=target_a and (v->>'id')::bigint=-411008;
 assert marker ? 'addedByCorrection' and marker ? 'revision' and (marker->>'qty')::numeric=8 and (marker->>'cost')::numeric=1000,marker::text;
 assert (select qty=12 and cost=1333.333333 from public.products where id=-411008);
 raw:=pg_temp.draft(target_a,jsonb_build_array(pg_temp.item(-411007,3,100),pg_temp.item(-411008,5,3000)));
 plan:=public.solar_purchase_correction_preview(raw);
 assert (plan->>'canApply')::boolean and not (plan->>'requiresCorrection')::boolean, plan::text;
 perform public.solar_invoice_save(gen_random_uuid(),raw);
 select v into strict second from public.transactions t, jsonb_array_elements(t.purchase_stock) v where t.id=target_a and (v->>'id')::bigint=-411008;
 assert second->'addedByCorrection'=marker->'addedByCorrection' and second->'revision'=marker->'revision';
 assert (select qty=13 and cost=1769.230769 from public.products where id=-411008);
 raw:=pg_temp.draft(source_b,jsonb_build_array(pg_temp.item(-411008,10,1200)));
 plan:=public.solar_purchase_correction_preview(raw);
 assert (plan->>'canApply')::boolean, plan::text;
 perform pg_temp.confirm(raw,plan);
 assert (select qty=13 and cost=1892.307692 from public.products where id=-411008);
 assert (select cost=1200 from public.transaction_items where transaction_id=prior_sale and product_id=-411008);
end$$;

-- A material added and removed in the pristine editor contributes no stock
-- when an earlier purchase is corrected.
do $$
declare opening bigint; middle bigint; body jsonb; plan jsonb; remove_body jsonb; sale_id bigint;
begin
 perform public.solar_exchange_rate_set(1000,(public.solar_exchange_rate_get()->>'revision')::bigint);
 opening:=pg_temp.issue('purchase',jsonb_build_array(pg_temp.item(-411010,10,100)),-40);
 middle:=pg_temp.issue('purchase',jsonb_build_array(pg_temp.item(-411009,5,10)),-30);
 body:=pg_temp.draft(middle,jsonb_build_array(pg_temp.item(-411009,5,10),pg_temp.item(-411010,2,130)));
 plan:=public.solar_purchase_correction_preview(body);
 assert not(plan->>'requiresCorrection')::boolean;
 perform pg_temp.confirm(body,plan);
 remove_body:=pg_temp.draft(middle,jsonb_build_array(pg_temp.item(-411009,5,10)));
 plan:=public.solar_purchase_correction_preview(remove_body);
 perform pg_temp.confirm(remove_body,plan);
 sale_id:=pg_temp.issue('sale',jsonb_build_array(pg_temp.item(-411010,1,160)),1);
 body:=pg_temp.draft(opening,jsonb_build_array(pg_temp.item(-411010,10,110)));
 plan:=public.solar_purchase_correction_preview(body);
 perform pg_temp.confirm(body,plan);
 assert(select qty=9 and cost=110 from public.products where id=-411010);
 assert(select cost=110 from public.transactions where id=sale_id);
end $$;

set constraints all immediate;
rollback;
select 'PASS added purchase line, weighted landed cost, historical FX, scope, posting, retry and cancellation' as result;
