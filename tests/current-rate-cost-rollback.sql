\set ON_ERROR_STOP on
begin;
update solar_private.exchange_settings set rate=null,revision=0,updated_at=null,updated_by=null where id;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions) values
('00000000-0000-0000-0000-000000003690','FX Current Admin',true,'admin_staff','07700003690','{}'),
('00000000-0000-0000-0000-000000003691','FX Current Owner',false,'admin_staff','07700003691','{"purchase":true,"sale":true,"system":true,"salesDeleteOwn":true,"stock":true,"stockAdjust":true}'),
('00000000-0000-0000-0000-000000003692','FX Current Engineer',false,'installer','07700003692','{}'),
('00000000-0000-0000-0000-000000003693','FX Current Warehouse',false,'warehouse','07700003693','{}');
insert into suppliers(id,name) values(-369001,'FX Current Supplier');
insert into customers(id,name,customer_type,owner_id) values(-369001,'FX Current Customer','wholesale','00000000-0000-0000-0000-000000003691');
insert into products(id,code,name,qty,cost) values(-369001,'FX-CURRENT','USD Current Stock',0,0),(-369002,'IQD-CURRENT','IQD Current Stock',0,0);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003690',true);
select public.solar_exchange_rate_set(1700,0);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003691',true);
select set_config('test.purchase',public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"FX Current Supplier","mode":"credit","sourceCurrency":"USD","exchangeRate":1700,"expenses":1000,"warehouseId":1,"items":[{"id":-369001,"qty":10,"price":100}]}')->>'id',true);
reset role;
do $$begin if not exists(select 1 from products where id=-369001 and cost=170100 and qty=10) then raise exception 'FAIL purchase landed book cost';end if;end$$;
select set_config('test.purchase_before',(select to_jsonb(t)::text from transactions t where id=current_setting('test.purchase')::bigint),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003690',true);
select set_config('test.capital_before',(public.solar_capital_snapshot()->'stock'->>'value'),true);
select public.solar_exchange_rate_set(1800,1);
do $$declare m jsonb;begin
 select v into m from jsonb_array_elements(public.solar_inventory('stock',null,'{"warehouseId":1}')->'products')v where(v->>'id')::bigint=-369001;
 if(m->>'cost')::numeric<>180100 or(m->>'bookCost')::numeric<>170100 then raise exception 'FAIL daily replacement cost %',m;end if;
 if public.solar_capital_snapshot()->'stock'->>'value'<>current_setting('test.capital_before') then raise exception 'FAIL daily quote changed historical capital book';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003691',true);
select set_config('test.sale_request',gen_random_uuid()::text,true);
select set_config('test.sale_payload','{"kind":"sale","party":"FX Current Customer","mode":"credit","warehouseId":1,"valuationRevision":2,"items":[{"id":-369001,"qty":2,"price":250000}]}',true);
select set_config('test.sale_result',public.solar_invoice_save(current_setting('test.sale_request')::uuid,current_setting('test.sale_payload')::jsonb)::text,true);
reset role;
do $$declare t public.transactions;i public.transaction_items;begin
 select * into t from transactions where id=(current_setting('test.sale_result')::jsonb->>'id')::bigint;
 select * into i from transaction_items where transaction_id=t.id;
 if t.cost<>360200 or t.profit<>139800 or i.cost<>180100 or(i.cost_basis->>'bookUnitCost')::numeric<>170100 then raise exception 'FAIL sale profit/current vs original cost %, %',to_jsonb(t),to_jsonb(i);end if;
 if(select cost from products where id=-369001)<>170100 then raise exception 'FAIL sale quote overwrote procurement book';end if;
end$$;
select set_config('test.sale_before',(select to_jsonb(t)::text from transactions t where id=(current_setting('test.sale_result')::jsonb->>'id')::bigint),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003690',true);
select public.solar_exchange_rate_set(1900,2);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003691',true);
do $$declare r jsonb;token text;begin
 r:=public.solar_invoice_save(current_setting('test.sale_request')::uuid,current_setting('test.sale_payload')::jsonb);
 if r::text<>current_setting('test.sale_result') then raise exception 'FAIL committed retry repriced';end if;
 begin perform public.solar_invoice_save(gen_random_uuid(),current_setting('test.sale_payload')::jsonb);raise exception 'FAIL stale rate accepted';exception when sqlstate 'PT409' then null;end;
 token:=public.solar_sale_delete_preview((r->>'id')::bigint)->>'token';
 perform public.solar_sale_delete((r->>'id')::bigint,token);
end$$;
reset role;
do $$begin
 if(select cost from products where id=-369001)<>170100 or(select qty from products where id=-369001)<>10 then raise exception 'FAIL return used current IQD instead of original book';end if;
 if(select to_jsonb(t)::text from transactions t where id=current_setting('test.purchase')::bigint)<>current_setting('test.purchase_before') then raise exception 'FAIL old purchase changed';end if;
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003690',true);
select public.solar_exchange_rate_set(1800,3);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003691',true);
-- Mix IQD procurement with USD inventory. Only the USD fraction follows FX.
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"FX Current Supplier","mode":"credit","sourceCurrency":"IQD","expenses":500,"warehouseId":1,"items":[{"id":-369001,"qty":5,"price":200000}]}');
do $$declare m jsonb;begin
 select v into m from jsonb_array_elements(public.solar_inventory('stock',null,'{"warehouseId":1}')->'products')v where(v->>'id')::bigint=-369001;
 if abs((m->>'cost')::numeric-186766.666667)>.000001 or(m->>'bookCost')::numeric<>180100 then raise exception 'FAIL mixed currency/expense allocation %',m;end if;
end$$;

-- Reconstruct legacy nested purchase snapshots without rewriting old invoices.
reset role;
update products set cost_basis=cost_basis-'currencyComponents' where id=-369001;
update transactions t set purchase_stock=(select jsonb_agg(v||jsonb_build_object('basis',(v->'basis')-'currencyComponents')) from jsonb_array_elements(t.purchase_stock)v) where t.id in(select transaction_id from transaction_items where product_id=-369001) and kind='purchase';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003691',true);
do $$declare m jsonb;begin
 select v into m from jsonb_array_elements(public.solar_inventory('stock',null,'{"warehouseId":1}')->'products')v where(v->>'id')::bigint=-369001;
 if abs((m->>'cost')::numeric-186766.666667)>.000001 then raise exception 'FAIL recursive legacy USD provenance';end if;
end$$;
-- IQD-only materials/expenses stay fixed. A falling FX rate changes only USD.
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"FX Current Supplier","mode":"credit","sourceCurrency":"IQD","expenses":250,"warehouseId":1,"items":[{"id":-369002,"qty":5,"price":5000}]}');
reset role;
select set_config('test.money_before',(select md5(jsonb_build_object('transactions',(select jsonb_agg(to_jsonb(t) order by id) from transactions t),'supplier',(select jsonb_agg(to_jsonb(e) order by id) from solar_private.supplier_fx_entries e),'wallet',(select jsonb_agg(to_jsonb(e) order by id) from solar_private.wallet_fx_entries e))::text)),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003690',true);
select public.solar_exchange_rate_set(1600,4);
do $$declare m jsonb;begin
 for m in select value from jsonb_array_elements(public.solar_inventory('stock',null,'{"warehouseId":1}')->'products') loop
  if(m->>'id')::bigint=-369002 and(m->>'cost')::numeric<>5050 then raise exception 'FAIL IQD only revalued';end if;
  if(m->>'id')::bigint=-369001 and abs((m->>'cost')::numeric-173433.333333)>.000001 then raise exception 'FAIL falling rate mixed cost %',m;end if;
 end loop;
end$$;
reset role;
do $$begin
 if(select md5(jsonb_build_object('transactions',(select jsonb_agg(to_jsonb(t) order by id) from transactions t),'supplier',(select jsonb_agg(to_jsonb(e) order by id) from solar_private.supplier_fx_entries e),'wallet',(select jsonb_agg(to_jsonb(e) order by id) from solar_private.wallet_fx_entries e))::text))<>current_setting('test.money_before') then raise exception 'FAIL FX revaluation posted cash, debt, or rewrote receipts';end if;
end$$;
-- Price-only archive edits keep the original trading cost after FX changes.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003691',true);
select set_config('test.archive',public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"FX Current Customer","mode":"credit","warehouseId":1,"valuationRevision":5,"items":[{"id":-369001,"qty":1,"price":250000}]}')::text,true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003690',true);
select public.solar_exchange_rate_set(1900,5);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003691',true);
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','sale','party','FX Current Customer','mode','credit','warehouseId',1,'invoiceId',(current_setting('test.archive')::jsonb->>'id')::bigint,'expectedRevision',1,'valuationRevision',6,'items','[{"id":-369001,"qty":1,"price":260000}]'::jsonb));
 if(r->>'cost')::numeric<>(current_setting('test.archive')::jsonb->>'cost')::numeric then raise exception 'FAIL historic price edit revalued';end if;
end$$;
-- New system and warehouse-added materials use current cost. Quantity changes
-- followed by a return conserve the original procurement book value.
reset role;
insert into customers(id,name,customer_type,owner_id) values(-369002,'FX Current System','system','00000000-0000-0000-0000-000000003691');
set local role authenticated;
select set_config('test.system',public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","party":"FX Current System","mode":"credit","warehouseId":1,"valuationRevision":6,"installerId":"00000000-0000-0000-0000-000000003692","customerAddress":"عنوان","total":1000000,"items":[{"id":-369002,"qty":1,"price":0}]}')->>'id',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003693',true);
do $$declare j jsonb;lines jsonb;begin
 j:=public.solar_warehouse_orders('@id:'||current_setting('test.system'),'')->'rows'->0;
 select jsonb_agg(jsonb_build_object('lineId',x->'lineId','productId',x->'productId','qty',x->'qty')) into lines from jsonb_array_elements(j->'items')x;
 perform public.solar_warehouse_action((j->>'id')::bigint,j->>'token','save',lines||'[{"productId":-369001,"qty":1}]','إضافة مادة بسعر صرف اليوم');
end$$;
reset role;
do $$begin
 if abs((select cost from transaction_items where transaction_id=current_setting('test.system')::bigint and product_id=-369001)-193433.333333)>.000001 then raise exception 'FAIL warehouse addition old FX';end if;
end$$;
select set_config('test.book_before',(select sum(qty*cost)::text from products where id in(-369001,-369002)),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003691',true);
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"FX Current Supplier","mode":"credit","sourceCurrency":"USD","exchangeRate":1900,"expenses":0,"warehouseId":1,"items":[{"id":-369001,"qty":5,"price":200}]}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003693',true);
do $$declare j jsonb;lines jsonb;begin
 j:=public.solar_warehouse_orders('@id:'||current_setting('test.system'),'')->'rows'->0;
 select jsonb_agg(jsonb_build_object('lineId',x->'lineId','productId',x->'productId','qty',case when(x->>'productId')::bigint=-369001 then 2 else 1 end)) into lines from jsonb_array_elements(j->'items')x;
 perform public.solar_warehouse_action((j->>'id')::bigint,j->>'token','save',lines,'زيادة كمية بعد شراء لاحق');
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003691',true);
do $$declare id bigint:=current_setting('test.system')::bigint;begin
 perform public.solar_sale_delete(id,public.solar_sale_delete_preview(id)->>'token');
end$$;
reset role;
do $$declare actual numeric;original_system_book numeric;begin
 select sum(qty*cost) into actual from products where id in(-369001,-369002);
 original_system_book:=180100+5050;
 if abs(actual-(current_setting('test.book_before')::numeric+1900000+original_system_book))>.001 then raise exception 'FAIL system return after mixed procurement %, expected %',actual,current_setting('test.book_before')::numeric+1900000+original_system_book;end if;
end$$;
set local role authenticated;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003690',true);
do $$declare target bigint;r jsonb;material jsonb;begin
 target:=(public.solar_inventory('warehouse_save',gen_random_uuid(),'{"name":"مخزن صرف تجريبي"}')->>'id')::bigint;
 select v into material from jsonb_array_elements(public.solar_inventory('stock',null,'{"warehouseId":1}')->'products')v where(v->>'id')::bigint=-369001;
 r:=public.solar_inventory('transfer',gen_random_uuid(),jsonb_build_object('fromId',1,'toId',target,'items',jsonb_build_array(jsonb_build_object('productId',-369001,'qty',1,'revision',(material->>'stockRevision')::bigint))));
 r:=public.solar_inventory('transfer_get',null,jsonb_build_object('id',r->>'id'));
 if(r->'items'->0->>'unitCost')::numeric<>(material->>'cost')::numeric then raise exception 'FAIL transfer did not retain the current company quote';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003693',true);
do $$declare r jsonb;begin r:=public.solar_inventory('stock',null,'{"warehouseId":1}');if r::text ~ '"(cost|bookCost|cost_basis|valuationRevision|valuationRate)"' then raise exception 'FAIL warehouse cost disclosure';end if;end$$;
reset role;
set constraints all immediate;
\echo PASS original dollar basis, current FX cost/profit, fixed IQD expenses, mixed procurement, frozen historical purchase, exact retry, stale-rate rollback, original-book return, capital and warehouse scope
rollback;
