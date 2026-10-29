\set ON_ERROR_STOP on
-- The fixture is created only in a disposable local database before this test.
begin;
create function pg_temp.material_fingerprint()returns text language sql security definer set search_path=''as $$select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)order by id)from public.transactions t),'items',(select jsonb_agg(to_jsonb(t)order by id)from public.transaction_items t),'stock',(select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),'adjustments',(select jsonb_agg(to_jsonb(t)order by id)from solar_private.stock_adjustments t),'transfers',(select jsonb_agg(to_jsonb(t)order by id)from solar_private.stock_transfers t),'cash',(select jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text)from public.cash_ledger t))::text)$$;
select set_config('test.material.fingerprint',pg_temp.material_fingerprint(),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003920',true);
do $$
#variable_conflict use_column
declare r jsonb;b jsonb;x jsonb;stored jsonb;main bigint;begin
 r:=public.solar_inventory('material_report',null,'{"productId":-392001,"withPrices":true}');
 if(r->>'currentQty')::numeric<>12 then raise exception 'Current quantity must match warehouses %',r->>'currentQty';end if;
 if r->'product'->>'code'<>'39201'then raise exception 'Wrong selected material';end if;
 if not exists(select 1 from jsonb_array_elements(r->'rows')x where x->>'kind'='purchase'and(x->'pricing'->>'unitPrice')::numeric=2075)then raise exception 'USD historical base price not preserved';end if;
 select value into x from jsonb_array_elements(r->'rows')where value->>'kind'='sale';
 if x->>'preparedByName'<>'مجهز كشف المواد'or x->>'createdByName'<>'بائع كشف المواد'or(x->'pricing'->>'unitPrice')::numeric<>3000 then raise exception 'Wrong source/preparer/sale price %',x;end if;
 select value into x from jsonb_array_elements(r->'rows')where value->>'kind'='system';
 if x->'pricing'->>'kind'<>'system_total'or x->'pricing'?'unitPrice' or x->>'preparedByName'is not null then raise exception 'System unit price or preparer invented';end if;
 if not exists(select 1 from jsonb_array_elements(r->'rows')x where x->>'kind'='transfer_cancelled')or not exists(select 1 from jsonb_array_elements(r->'rows')x where x->>'kind'='transfer_return_out')then raise exception 'Transfer cancellation/reversal omitted';end if;
 if not exists(select 1 from jsonb_array_elements(r->'rows')x where x->'pricing'->>'kind'='transfer_cost'and(x->'pricing'->>'unitPrice')::numeric>0)then raise exception 'Frozen transfer cost missing';end if;
 b:=public.solar_inventory('movements',null,'{"productId":-392001}');
 if jsonb_array_length(b)<>jsonb_array_length(r->'rows')then raise exception 'Existing movement omitted/duplicated';end if;
 for stored in select * from jsonb_array_elements(b)loop
  select value into x from jsonb_array_elements(r->'rows')where value->>'id'=stored->>'id';
  if x->'balance'<>stored->'balance'or x->'inQty'<>stored->'inQty'or x->'outQty'<>stored->'outQty'then raise exception 'Ledger balance/delta changed';end if;
 end loop;
 r:=public.solar_inventory('material_report',null,'{"productId":-392001,"withPrices":false}');
 if r::text like '%"pricing"%'or r::text like '%"cost"%'or r::text like '%"unitCost"%'then raise exception 'No-price API contains financial values';end if;
 perform set_config('test.material.full',r::text,true);
end$$;
reset role;
-- Test historical opening/running balance from the original full ledger.
update solar_private.stock_adjustments set created_at=now()-interval'2 days'where product_id=-392001;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003920',true);
do $$
#variable_conflict use_column
declare r jsonb;b jsonb;x jsonb;stored jsonb;begin
 b:=public.solar_inventory('material_report',null,'{"productId":-392001}');
 r:=public.solar_inventory('material_report',null,jsonb_build_object('productId',-392001,'from',(now()at time zone'Asia/Baghdad')::date));
 if exists(select 1 from jsonb_array_elements(r->'rows')x where x->>'kind'='stock_adjustment')then raise exception 'Date filter omitted';end if;
 for x in select * from jsonb_array_elements(r->'rows')loop
  select value into stored from jsonb_array_elements(b->'rows')where value->>'id'=x->>'id';
  if x->'balance'<>stored->'balance'then raise exception 'Date filter reset opening balance';end if;
 end loop;
 r:=public.solar_inventory('material_report',null,jsonb_build_object('productId',-392001,'warehouseId',1));
 if exists(select 1 from jsonb_array_elements(r->'rows')x where(x->>'warehouseId')::bigint<>1)then raise exception 'Warehouse filter omitted';end if;
end$$;
reset role;
-- Restore only the disposable test date changes before the immutable-read proof.
update solar_private.stock_adjustments set created_at=(select(row_data->>'date')::timestamptz from jsonb_array_elements(current_setting('test.material.full')::jsonb->'rows')r(row_data)where row_data->>'id'='adjustment:'||stock_adjustments.id limit 1)where product_id=-392001;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003922',true);
do $$
#variable_conflict use_column
declare r jsonb;begin
 r:=public.solar_inventory('material_report',null,'{"productId":-392001}');
 if r::text like '%"pricing"%'or r::text like '%"cost"%'or(r->>'canShowPrices')::boolean then raise exception 'Warehouse price leak';end if;
 begin perform public.solar_inventory('material_report',null,'{"productId":-392001,"withPrices":true}');raise exception 'FAIL warehouse prices';exception when insufficient_privilege then null;end;
 begin perform public.solar_inventory('material_report',null,'{"productId":-392001,"warehouseId":2}');raise exception 'FAIL unauthorized warehouse';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003923',true);
do $$
#variable_conflict use_column
declare r jsonb;begin r:=public.solar_inventory('material_report',null,'{"productId":-392001}');if jsonb_array_length(r->'rows')<>0 then raise exception 'Foreign transaction detail leaked';end if;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003924',true);
do $$begin begin perform public.solar_inventory('material_report',null,'{"productId":-392001,"withPrices":true}');raise exception 'FAIL quantity-only financial data';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003925',true);
do $$begin begin perform public.solar_inventory('material_report',null,'{"productId":-392001}');raise exception 'FAIL engineer stock access';exception when insufficient_privilege then null;end;end$$;
reset role;
do $$begin if pg_temp.material_fingerprint()<>current_setting('test.material.fingerprint')then raise exception 'Reports changed stock or finance records';end if;if has_function_privilege('authenticated','solar_private.material_movement_report(jsonb)','execute')then raise exception 'Internal helper exposed';end if;raise notice 'PASS exact existing stock balances, prices without current FX, supplier/customer/preparer, cancellation/reversal, dates/warehouse filters, warehouse/owner/engineer isolation and immutable read-only state';end$$;
rollback;
