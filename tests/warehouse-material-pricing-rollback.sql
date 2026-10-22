\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions) values
('00000000-0000-0000-0000-000000003650','مدير التسعير',true,'admin_staff','07700003650','{}'),
('00000000-0000-0000-0000-000000003651','صاحب الوصل',false,'admin_staff','07700003651','{"sale":true,"system":true,"customers":true,"salesHistory":true}'),
('00000000-0000-0000-0000-000000003652','مسؤول الرئيسي',false,'warehouse','07700003652','{}'),
('00000000-0000-0000-0000-000000003653','إداري آخر',false,'admin_staff','07700003653','{"sale":true}'),
('00000000-0000-0000-0000-000000003654','مهندس',false,'installer','07700003654','{}');
insert into products(id,code,name,qty,cost) values(-365001,'EDIT-A','انفيرتر التعديل',50,100),(-365002,'EDIT-B','بطارية التعديل',50,200),(-365003,'EDIT-C','لوح مضاف',50,300);
insert into customers(id,name,customer_type,owner_id) values(-365001,'عميل تعديل الجملة','wholesale','00000000-0000-0000-0000-000000003651'),(-365002,'عميل تعديل المنظومة','system','00000000-0000-0000-0000-000000003651');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003651',true);
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-365001,"party":"عميل تعديل الجملة","mode":"credit","warehouseId":1,"items":[{"id":-365001,"qty":2,"price":1000},{"id":-365002,"qty":1,"price":1000}]}');perform set_config('test.sale',r->>'id',true);
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","partyId":-365002,"party":"عميل تعديل المنظومة","mode":"credit","warehouseId":1,"installerId":"00000000-0000-0000-0000-000000003654","customerAddress":"عنوان","total":10000,"items":[{"id":-365001,"qty":2,"price":0},{"id":-365002,"qty":1,"price":0}]}');perform set_config('test.system',r->>'id',true);
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003652',true);
do $$declare row jsonb;lines jsonb;begin
 row:=public.solar_warehouse_orders('@id:'||current_setting('test.system'),'')->'rows'->0;
 if row::text ~ '"(price|cost|total|profit)"' then raise exception 'financial data leaked';end if;
 lines:=jsonb_build_array(jsonb_build_object('lineId',row->'items'->0->'lineId','productId',-365002,'qty',2));
 -- Locate by product ID rather than relying on invoice insertion order.
 select jsonb_agg(jsonb_build_object('lineId',x->'lineId','productId',x->'productId','qty',case when(x->>'productId')::bigint=-365001 then 1 else 2 end)) into lines from jsonb_array_elements(row->'items') x;
 lines:=lines||'[{"productId":-365003,"qty":3}]';
 perform public.solar_warehouse_action((row->>'id')::bigint,row->>'token','save',lines,'ثلاث فقرات كاملة');
 begin perform public.solar_warehouse_action((row->>'id')::bigint,row->>'token','ready');raise exception 'FAIL stale preparation';exception when sqlstate 'PT409' then null;end;
 row:=public.solar_warehouse_orders('@id:'||current_setting('test.system'),'')->'rows'->0;
 if jsonb_array_length(row->'items')<>3 then raise exception 'system addition lost paragraphs';end if;
 perform public.solar_warehouse_action((row->>'id')::bigint,row->>'token','ready');
end$$;
reset role;
do $$begin
 if not exists(select 1 from transactions where id=current_setting('test.system')::bigint and total=10000 and cost=1400 and profit=8600 and warehouse_status='ready') then raise exception 'system total/cost mismatch';end if;
end$$;
-- Save a full wholesale candidate with a new material. Its current books stay intact.
select set_config('test.books',(select jsonb_build_object('total',total,'cost',cost,'profit',profit,'invoiceAccount',invoice_account)::text from transactions where id=current_setting('test.sale')::bigint),true);
select set_config('test.stock',(select jsonb_agg(to_jsonb(s) order by warehouse_id,product_id)::text from solar_private.warehouse_stocks s),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003652',true);
do $$declare row jsonb;lines jsonb;begin
 row:=public.solar_warehouse_orders('@id:'||current_setting('test.sale'),'')->'rows'->0;
 select jsonb_agg(jsonb_build_object('lineId',x->'lineId','productId',x->'productId','qty',case when(x->>'productId')::bigint=-365001 then 3 else 1 end)) into lines from jsonb_array_elements(row->'items') x;
 perform public.solar_warehouse_action((row->>'id')::bigint,row->>'token','save',lines||'[{"productId":-365003,"qty":2,"price":999999}]','إضافة بدون كشف الأسعار');
 row:=public.solar_warehouse_orders('@id:'||current_setting('test.sale'),'')->'rows'->0;
 if not(row->>'pricingPending')::boolean or jsonb_array_length(row->'items')<>3 or jsonb_array_length(row->'bookedItems')<>2 or row::text ~ '"(price|cost|total|profit)"' then raise exception 'warehouse candidate unsafe/incomplete %',row;end if;
 begin perform public.solar_warehouse_action((row->>'id')::bigint,row->>'token','ready');raise exception 'FAIL pending pricing prepared';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.solar_warehouse_pricing('list');raise exception 'FAIL warehouse prices exposed';exception when insufficient_privilege then null;end;
 begin perform public.solar_warehouse_pricing('get',(row->>'id')::bigint);raise exception 'FAIL warehouse prices exposed';exception when insufficient_privilege then null;end;
end$$;
reset role;
do $$declare books text;stock text;begin
 select jsonb_build_object('total',total,'cost',cost,'profit',profit,'invoiceAccount',invoice_account)::text into books from transactions where id=current_setting('test.sale')::bigint;
 select jsonb_agg(to_jsonb(s) order by warehouse_id,product_id)::text into stock from solar_private.warehouse_stocks s;
 if books<>current_setting('test.books') or stock<>current_setting('test.stock') then raise exception 'unpriced request posted money/stock';end if;
 if exists(select 1 from solar_private.warehouse_price_edits where lines::text like '%price%') then raise exception 'warehouse input injected price';end if;
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003653',true);
do $$begin
 if jsonb_array_length(public.solar_warehouse_pricing('list')->'rows')<>0 then raise exception 'other user saw invoice';end if;
 begin perform public.solar_warehouse_pricing('get',current_setting('test.sale')::bigint);raise exception 'FAIL other user get';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003650',true);
do $$declare r jsonb;result jsonb;again jsonb;req uuid:=gen_random_uuid();begin
 if jsonb_array_length(public.solar_warehouse_pricing('list')->'rows')<>1 then raise exception 'admin queue missing request';end if;
 r:=public.solar_warehouse_pricing('get',current_setting('test.sale')::bigint);
 if jsonb_array_length(r->'items')<>3 or not exists(select 1 from jsonb_array_elements(r->'items') x where x->>'lineId' is null and x->>'price' is null) then raise exception 'admin new price not blank';end if;
 begin perform public.solar_warehouse_pricing('approve',(r->>'id')::bigint,r->>'token','[{"productId":-365003,"price":0}]',req);raise exception 'FAIL zero price';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 result:=public.solar_warehouse_pricing('approve',(r->>'id')::bigint,r->>'token','[{"productId":-365003,"price":500}]',req);
 again:=public.solar_warehouse_pricing('approve',(r->>'id')::bigint,r->>'token','[{"productId":-365003,"price":500}]',req);
 if result<>again or(result->>'total')::numeric<>5000 then raise exception 'pricing retry/total mismatch %',result;end if;
 perform set_config('test.price_request',req::text,true);
 if jsonb_array_length(public.solar_warehouse_pricing('list')->'rows')<>0 then raise exception 'approved price still queued';end if;
end$$;
reset role;
do $$begin
 if not exists(select 1 from transactions where id=current_setting('test.sale')::bigint and total=5000 and cost=1100 and profit=3900) then raise exception 'wholesale accounting mismatch';end if;
 if(select count(*) from transaction_items where transaction_id=current_setting('test.sale')::bigint)<>3 then raise exception 'priced invoice incomplete';end if;
 if(select qty from products where id=-365001)<>46 or(select qty from products where id=-365002)<>47 or(select qty from products where id=-365003)<>45 then raise exception 'stock not applied exactly once';end if;
 if(select count(*) from solar_private.invoice_requests where request_id=current_setting('test.price_request')::uuid)<>1 then raise exception 'double invoice posting';end if;
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003652',true);
do $$declare r jsonb;begin
 r:=public.solar_warehouse_orders('@id:'||current_setting('test.sale'),'')->'rows'->0;
 if(r->>'pricingPending')::boolean or jsonb_array_length(r->'items')<>3 then raise exception 'priced warehouse invoice mismatch';end if;
 perform public.solar_warehouse_action((r->>'id')::bigint,r->>'token','ready');
end$$;
reset role;
set constraints all immediate;
set constraints all deferred;
-- Cash sales post only the approved increase, and retry never repeats it.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003651',true);
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-365001,"party":"عميل تعديل الجملة","mode":"cash","warehouseId":1,"items":[{"id":-365001,"qty":1,"price":1000}]}');perform set_config('test.cash',r->>'id',true);
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003652',true);
do $$declare r jsonb;begin
 r:=public.solar_warehouse_orders('@id:'||current_setting('test.cash'),'')->'rows'->0;
 perform public.solar_warehouse_action((r->>'id')::bigint,r->>'token','save',jsonb_build_array(jsonb_build_object('lineId',r->'items'->0->'lineId','productId',-365001,'qty',1))||'[{"productId":-365003,"qty":2}]');
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003650',true);
do $$declare r jsonb;req uuid:=gen_random_uuid();begin
 r:=public.solar_warehouse_pricing('get',current_setting('test.cash')::bigint);
 perform public.solar_warehouse_pricing('approve',(r->>'id')::bigint,r->>'token','[{"productId":-365003,"price":500}]',req);
 perform public.solar_warehouse_pricing('approve',(r->>'id')::bigint,r->>'token','[{"productId":-365003,"price":500}]',req);
end$$;
reset role;
do $$begin if not exists(select 1 from transactions where id=current_setting('test.cash')::bigint and cash and total=2000 and cost=700 and profit=1300) then raise exception 'cash price increase applied incorrectly';end if;end$$;
-- Stale amendments cannot overwrite an intervening administrator edit; cancellation
-- discards only the proposed materials, leaving the posted invoice intact.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003652',true);
do $$declare r jsonb;ls jsonb;begin
 r:=public.solar_warehouse_orders('@id:'||current_setting('test.cash'),'')->'rows'->0;
 select jsonb_agg(jsonb_build_object('lineId',x->'lineId','productId',x->'productId','qty',x->'qty')) into ls from jsonb_array_elements(r->'items') x;
 perform public.solar_warehouse_action((r->>'id')::bigint,r->>'token','save',ls||'[{"productId":-365002,"qty":1}]');
end$$;
reset role;
update transactions set notes='تعديل إداري أحدث' where id=current_setting('test.cash')::bigint;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003650',true);
do $$declare r jsonb;begin
 r:=public.solar_warehouse_pricing('get',current_setting('test.cash')::bigint);
 if not(r->>'stale')::boolean then raise exception 'intervening invoice edit not detected';end if;
 begin perform public.solar_warehouse_pricing('approve',(r->>'id')::bigint,r->>'token','[{"productId":-365002,"price":400}]',gen_random_uuid());raise exception 'FAIL stale pricing applied';exception when sqlstate 'PT409' then null;end;
 perform public.solar_warehouse_pricing('cancel',(r->>'id')::bigint,r->>'token',null,gen_random_uuid());
end$$;
reset role;
do $$begin if not exists(select 1 from transactions where id=current_setting('test.cash')::bigint and notes='تعديل إداري أحدث' and total=2000 and cost=700) or exists(select 1 from solar_private.warehouse_price_edits) then raise exception 'cancellation changed posted invoice';end if;end$$;
-- Main preparers cannot edit invoices in Sayada, even when given their IDs.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003650',true);
update solar_private.warehouse_stocks set qty=qty-5 where warehouse_id=1 and product_id=-365001;
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) select id,-365001,5 from solar_private.warehouses where code='SAYADA';
select set_config('test.sayada_id',(select id::text from solar_private.warehouses where code='SAYADA'),true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','sale','partyId',-365001,'party','عميل تعديل الجملة','mode','credit','warehouseId',current_setting('test.sayada_id')::bigint,'items','[{"id":-365001,"qty":1,"price":1000}]'::jsonb));perform set_config('test.sayada',r->>'id',true);
end$$;
reset role;
select set_config('test.sayada_token',solar_private.warehouse_token(current_setting('test.sayada')::bigint),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003652',true);
do $$begin
 begin perform public.solar_warehouse_action(current_setting('test.sayada')::bigint,current_setting('test.sayada_token'),'save','[{"productId":-365002,"qty":1}]');raise exception 'FAIL cross warehouse stage';exception when insufficient_privilege then null;end;
end$$;
reset role;
set constraints all immediate;
do $$begin
 if has_function_privilege('anon','public.solar_warehouse_pricing(text,bigint,text,jsonb,uuid)','execute') or has_function_privilege('authenticated','solar_private.warehouse_action_v364(bigint,text,text,jsonb,text)','execute') or has_table_privilege('authenticated','solar_private.warehouse_price_edits','select') then raise exception 'unsafe grants';end if;
 raise notice 'PASS complete system additions, quantity-only wholesale staging, unchanged unpriced books/stock, safe warehouse payload, admin pricing/notification/ownership, zero-price rejection, exact retry, full invoice and stock delta, ready/stale guards';
end$$;
rollback;
