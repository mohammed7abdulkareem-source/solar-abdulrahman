begin;
select set_config('wh.actor',(select id::text from public.profiles where active and not is_admin and user_type='admin_staff' order by created_at limit 1),true);
select set_config('wh.owner',(select id::text from public.profiles where active and is_admin order by created_at limit 1),true);
select set_config('wh.engineer',(select id::text from public.profiles where active and user_type='installer' order by created_at limit 1),true);
update public.profiles set user_type='warehouse',is_admin=true,permissions='{"all":true,"profit":true,"installationsAll":true}' where id=current_setting('wh.actor')::uuid;
do $$begin
 if not exists(select 1 from public.profiles where id=current_setting('wh.actor')::uuid and not is_admin and permissions='{"warehouse":true,"stock":true,"stockMovement":true}'::jsonb) then raise exception 'FAIL role normalization';end if;
end $$;
insert into public.products(id,code,name,qty,cost) values(-963001,'WH-TEST-A','WH TEST A',10,20),(-963002,'WH-TEST-B','WH TEST B',15,40);
insert into public.transactions(id,kind,party_name,total,subtotal,cost,profit,created_by,cashbox_user_id,installation_status) values
 (-963001,'sale','WH TEST CUSTOMER',100,100,40,60,current_setting('wh.owner')::uuid,current_setting('wh.owner')::uuid,'none'),
 (-963002,'system','WH TEST SYSTEM',500,500,40,460,current_setting('wh.owner')::uuid,current_setting('wh.owner')::uuid,'pending');
insert into public.transaction_items(id,transaction_id,product_id,product_name,qty,price,cost) values
 (-963001,-963001,-963001,'WH TEST A',2,50,20),(-963002,-963002,-963001,'WH TEST A',2,0,20);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('wh.actor'),true);
do $$declare row jsonb; stock jsonb; mov jsonb; token text;begin
 if exists(select 1 from public.products) or exists(select 1 from public.transactions) or exists(select 1 from public.transaction_items) or exists(select 1 from public.solar_cash_entries) then raise exception 'FAIL financial tables readable';end if;
 begin perform public.solar_sales_history();raise exception 'FAIL financial history callable';exception when insufficient_privilege then null;end;
 begin perform public.solar_installation_jobs();raise exception 'FAIL installations callable';exception when insufficient_privilege then null;end;
 stock:=public.solar_stock_quantities();
 if stock::text ~ '"(cost|price|profit|total)"' or not exists(select 1 from jsonb_array_elements(stock) x where (x->>'id')::bigint=-963001 and (x->>'qty')::numeric=10) then raise exception 'FAIL safe stock';end if;
 row:=(public.solar_warehouse_orders('WH TEST CUSTOMER','')->'rows')->0;
 if row is null or row::text ~ '"(cost|price|profit|total)"' then raise exception 'FAIL safe order';end if;
 if not exists(select 1 from public.solar_notifications where job_id=-963001 and event='warehouse_new') then raise exception 'FAIL new order notification';end if;
 token:=row->>'token';
 begin perform public.solar_warehouse_action(-963001,token,'save','[{"lineId":-963002,"productId":-963001,"qty":3}]');raise exception 'FAIL foreign line accepted';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.solar_warehouse_action(-963001,token,'save','[{"lineId":-963001,"productId":-963001,"qty":200}]');raise exception 'FAIL overselling';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 perform public.solar_warehouse_action(-963001,token,'save','[{"lineId":-963001,"productId":-963001,"qty":3}]');
 begin perform public.solar_warehouse_action(-963001,token,'ready');raise exception 'FAIL stale edit accepted';exception when serialization_failure then null;end;
 row:=(public.solar_warehouse_orders('WH TEST CUSTOMER','')->'rows')->0;
 perform public.solar_warehouse_action(-963001,row->>'token','ready');
 row:=(public.solar_warehouse_orders('WH TEST CUSTOMER','')->'rows')->0;
 if row->>'status'<>'ready' or row->>'preparedBy' is null then raise exception 'FAIL preparation';end if;
 if not exists(select 1 from jsonb_array_elements(public.solar_stock_quantities()) x where (x->>'id')::bigint=-963001 and (x->>'qty')::numeric=9) then raise exception 'FAIL duplicate stock deduction';end if;
 mov:=public.solar_stock_movements(-963001,'WH TEST CUSTOMER');
 if jsonb_array_length(mov)<>1 or mov::text ~ '"(cost|price|profit|total)"' or (mov->0->>'outQty')::numeric<>3 then raise exception 'FAIL customer movement';end if;
 row:=(public.solar_warehouse_orders('WH TEST SYSTEM','')->'rows')->0;
 perform public.solar_warehouse_action(-963002,row->>'token','save','[{"lineId":-963002,"productId":-963001,"qty":1},{"productId":-963002,"qty":2}]');
end $$;
reset role;
do $$begin
 if not exists(select 1 from public.transactions where id=-963001 and total=150 and cost=60 and profit=90 and warehouse_status='ready') then raise exception 'FAIL wholesale financial recalculation';end if;
 if not exists(select 1 from public.transactions where id=-963002 and total=500 and cost=100 and profit=400) then raise exception 'FAIL system financial recalculation';end if;
 if (select qty from public.products where id=-963001)<>10 or (select qty from public.products where id=-963002)<>13 then raise exception 'FAIL system stock delta';end if;
 if (select count(*) from public.solar_notifications where user_id=current_setting('wh.owner')::uuid and job_id=-963001 and event in ('warehouse_edited','warehouse_ready'))<>2 then raise exception 'FAIL owner notices';end if;
 if (select count(*) from solar_private.warehouse_audit where invoice_id in (-963001,-963002))<>3 then raise exception 'FAIL audit';end if;
end $$;
-- Later seller edits must return a prepared order to the queue.
update public.transaction_items set qty=qty where id=-963001;
do $$begin if not exists(select 1 from public.transactions where id=-963001 and warehouse_status='pending') then raise exception 'FAIL edited order not reopened';end if;end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('wh.engineer'),true);
do $$begin
 begin perform public.solar_warehouse_orders();raise exception 'FAIL engineer warehouse access';exception when insufficient_privilege then null;end;
 begin perform public.solar_stock_quantities();raise exception 'FAIL engineer stock access';exception when insufficient_privilege then null;end;
 begin perform public.solar_stock_movements();raise exception 'FAIL engineer movement access';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
select 'warehouse permissions, edits, stock deltas, notifications and reports passed; all fixtures rolled back' as result;
