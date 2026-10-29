\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions)values
('00000000-0000-0000-0000-000000003860','مدير الاختبار',true,'admin_staff','07700003860','{}'),
('00000000-0000-0000-0000-000000003861','صاحب الجملة',false,'admin_staff','07700003861','{"sale":true,"system":true,"profit":true,"warehouse":true}'),
('00000000-0000-0000-0000-000000003862','مستخدم آخر',false,'admin_staff','07700003862','{"sale":true,"profit":true}'),
('00000000-0000-0000-0000-000000003863','مسؤول مخزن',true,'warehouse','07700003863','{"sale":true,"profit":true}'),
('00000000-0000-0000-0000-000000003864','مهندس',true,'installer','07700003864','{"sale":true,"profit":true}');
insert into solar_private.warehouse_access(user_id,all_warehouses,warehouse_ids)values('00000000-0000-0000-0000-000000003861',false,'{1,2}');
insert into products(id,code,name,qty,cost)values(-386001,'DIR-386','مادة التجهيز المباشر',100,100),(-386002,'DIR-NEW','مادة تنتظر تسعير',20,50);
update solar_private.warehouse_stocks set qty=70 where warehouse_id=1 and product_id=-386001;
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty)values(2,-386001,30);
insert into customers(id,name,customer_type,owner_id)values(-386001,'عميل وصل الجملة','wholesale','00000000-0000-0000-0000-000000003861');
create function pg_temp.financial_fingerprint()returns text language sql as $$select md5(jsonb_build_object(
 'invoices',(select jsonb_agg(jsonb_build_array(id,created_by,party_id,warehouse_id,total,cost,profit,subtotal,expenses,cash,invoice_account)order by id)from transactions),
 'items',(select jsonb_agg(to_jsonb(i)order by id)from transaction_items i),
 'products',(select jsonb_agg(to_jsonb(p)order by id)from products p),
 'stocks',(select jsonb_agg(to_jsonb(s)order by warehouse_id,product_id)from solar_private.warehouse_stocks s),
 'cash',(select jsonb_agg(to_jsonb(e)order by id)from solar_cash_entries e))::text)$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003861',true);
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"credit","partyId":-386001,"party":"عميل وصل الجملة","warehouseId":2,"items":[{"id":-386001,"qty":2,"price":300}]}');perform set_config('test.pending',r->>'id',true);
 r:=public.solar_sale_preparation('get',(r->>'id')::bigint);perform set_config('test.token',r->>'token',true);
 if r->>'warehouseName'<>'مخزن صيادة' or r->>'warehouseStatus'<>'pending' then raise exception 'Warehouse identity missing %',r;end if;
end$$;
reset role;
select set_config('test.books',pg_temp.financial_fingerprint(),true);
set local role authenticated;
do $$declare r jsonb;nonce uuid:=gen_random_uuid();begin
 r:=public.solar_sale_preparation('ready',current_setting('test.pending')::bigint,current_setting('test.token'),nonce);
 if r->>'warehouseStatus'<>'ready' then raise exception 'Not prepared';end if;
 r:=public.solar_sale_preparation('ready',current_setting('test.pending')::bigint,current_setting('test.token'),nonce);
 if not(r->>'replayed')::boolean then raise exception 'Lost ack retry not replayed';end if;
 begin perform public.solar_sale_preparation('ready',current_setting('test.pending')::bigint,current_setting('test.token'),gen_random_uuid());raise exception 'FAIL stale token';exception when sqlstate 'PT409' then null;end;
end$$;
reset role;
do $$begin
 if pg_temp.financial_fingerprint()<>current_setting('test.books') then raise exception 'Preparation reposted stock or finances';end if;
 if(select count(*)from solar_private.warehouse_audit where invoice_id=current_setting('test.pending')::bigint and action='ready')<>1 then raise exception 'Duplicate preparation';end if;
 if not exists(select 1 from solar_notifications where job_id=current_setting('test.pending')::bigint and event='warehouse_ready')then raise exception 'Owner notification missing';end if;
end$$;
set local role authenticated;
do $$declare r jsonb;payload jsonb:='{"kind":"sale","directPreparation":true,"mode":"cash","warehouseId":1,"partyId":-386001,"party":"عميل وصل الجملة","items":[{"id":-386001,"qty":3,"price":500}]}';nonce uuid:=gen_random_uuid();begin
 r:=public.solar_invoice_save(nonce,payload);perform set_config('test.direct',r->>'id',true);
 if r->>'warehouseStatus'<>'ready' or r->>'warehouseName'<>'المخزن الرئيسي' then raise exception 'Atomic direct response incomplete %',r;end if;
 if public.solar_invoice_save(nonce,payload)<>r then raise exception 'Invoice retry lost prepared result';end if;
end$$;
reset role;
do $$begin
 if not exists(select 1 from transactions where id=current_setting('test.direct')::bigint and total=1500 and cost=300 and profit=1200 and warehouse_prepared_by='00000000-0000-0000-0000-000000003861')then raise exception 'Direct invoice amounts changed';end if;
 if(select qty from products where id=-386001)<>95 then raise exception 'Direct stock posted more than once';end if;
 if exists(select 1 from solar_notifications where job_id=current_setting('test.direct')::bigint and event='warehouse_new')then raise exception 'Direct invoice announced pending';end if;
end$$;
-- Any downstream failure must undo the entire invoice, not leave it pending.
create function pg_temp.fail_direct_audit()returns trigger language plpgsql as $$begin if new.action='ready' then raise exception 'forced_direct_failure';end if;return new;end$$;
create trigger test_direct_failure before insert on solar_private.warehouse_audit for each row execute function pg_temp.fail_direct_audit();
select set_config('test.books',pg_temp.financial_fingerprint(),true);
set local role authenticated;
do $$begin
 begin perform public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","directPreparation":true,"mode":"cash","warehouseId":1,"partyId":-386001,"party":"عميل وصل الجملة","items":[{"id":-386001,"qty":1,"price":500}]}');raise exception 'FAIL partial invoice saved';exception when raise_exception then if sqlerrm<>'forced_direct_failure'then raise;end if;end;
end$$;
reset role;
do $$begin if pg_temp.financial_fingerprint()<>current_setting('test.books')then raise exception 'Direct failure was not atomic';end if;end$$;
drop trigger test_direct_failure on solar_private.warehouse_audit;
-- A material revision invalidates a previously reviewed preparation.
set local role authenticated;
do $$declare r jsonb;lines jsonb;begin
 r:=public.solar_warehouse_orders('@id:'||current_setting('test.pending'),'')->'rows'->0;
 perform public.solar_warehouse_action((r->>'id')::bigint,r->>'token','reopen');
 r:=public.solar_warehouse_orders('@id:'||current_setting('test.pending'),'')->'rows'->0;
 perform set_config('test.oldtoken',r->>'token',true);
 select jsonb_agg(jsonb_build_object('lineId',x->'lineId','productId',x->'productId','qty',3))into lines from jsonb_array_elements(r->'items')x;
 perform public.solar_warehouse_action((r->>'id')::bigint,r->>'token','save',lines);
 begin perform public.solar_sale_preparation('ready',(r->>'id')::bigint,current_setting('test.oldtoken'),gen_random_uuid());raise exception 'FAIL materials stale';exception when sqlstate 'PT409' then null;end;
end$$;
-- New warehouse materials awaiting prices must not be marked ready directly.
do $$declare r jsonb;lines jsonb;begin
 r:=public.solar_warehouse_orders('@id:'||current_setting('test.pending'),'')->'rows'->0;
 select jsonb_agg(jsonb_build_object('lineId',x->'lineId','productId',x->'productId','qty',x->'qty'))into lines from jsonb_array_elements(r->'items')x;
 -- Product 386002 is in primary only; use the primary receipt for this guard.
 r:=public.solar_warehouse_orders('@id:'||current_setting('test.direct'),'')->'rows'->0;
 perform public.solar_warehouse_action((r->>'id')::bigint,r->>'token','reopen');
 r:=public.solar_warehouse_orders('@id:'||current_setting('test.direct'),'')->'rows'->0;
 select jsonb_agg(jsonb_build_object('lineId',x->'lineId','productId',x->'productId','qty',x->'qty'))into lines from jsonb_array_elements(r->'items')x;
 perform public.solar_warehouse_action((r->>'id')::bigint,r->>'token','save',lines||'[{"productId":-386002,"qty":1}]');
 r:=public.solar_sale_preparation('get',(r->>'id')::bigint);
 begin perform public.solar_sale_preparation('ready',(r->>'id')::bigint,r->>'token',gen_random_uuid());raise exception 'FAIL unpriced preparation';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003862',true);
do $$begin begin perform public.solar_sale_preparation('get',current_setting('test.pending')::bigint);raise exception 'FAIL another user';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003863',true);
do $$begin begin perform public.solar_sale_preparation('get',current_setting('test.pending')::bigint);raise exception 'FAIL stale warehouse admin';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003864',true);
do $$begin begin perform public.solar_sale_preparation('get',current_setting('test.pending')::bigint);raise exception 'FAIL stale engineer admin';exception when insufficient_privilege then null;end;end$$;
reset role;
update solar_private.warehouse_access set warehouse_ids='{1}'where user_id='00000000-0000-0000-0000-000000003861';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003861',true);
do $$begin begin perform public.solar_sale_preparation('get',current_setting('test.pending')::bigint);raise exception 'FAIL revoked warehouse';exception when insufficient_privilege then null;end;end$$;
reset role;
do $$begin if has_function_privilege('anon','public.solar_sale_preparation(text,bigint,text,uuid)','EXECUTE')then raise exception 'Anonymous preparation';end if;end$$;
set constraints all immediate;
rollback;
\echo PASS direct preparation: own receipt and warehouse identity, stock/cash unchanged, atomic creation and failure, retries, stale materials, pending prices, role and warehouse isolation
