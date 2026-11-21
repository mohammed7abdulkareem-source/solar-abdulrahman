-- Verify the catalog, shared snapshot and raw REST read policies together.
begin;
insert into public.profiles(id,username,display_name,is_admin,active,user_type,permissions,phone) values
 ('00000000-0000-0000-0000-000000412571','catalog_personal_staff','موظف اختبار الأسعار',false,true,'admin_staff','{"sale":true,"purchase":true,"stock":true,"capital":true,"profitUsesWholesalePrice":true}','07700000000'),
 ('00000000-0000-0000-0000-000000412572','catalog_personal_admin','مسؤول اختبار الأسعار',true,true,'admin','{}','07700000000');
insert into public.customers(id,name,customer_type,owner_id) values
 (-412571,'زبون كتالوج الاختبار','wholesale','00000000-0000-0000-0000-000000412571');
insert into public.products(id,code,name,qty,cost) values
 (-412571,'PC412571','مرجع كتالوج PC412571',200,317),(-412572,'PC412572','غير محدد كتالوج PC412572',200,416);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values(1,-412571,200),(1,-412572,200)
 on conflict(warehouse_id,product_id) do update set qty=excluded.qty;
insert into solar_private.wholesale_product_prices(product_id,enabled,minimum_price) values(-412571,true,599),(-412572,false,733);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412571',true);

do $test$
declare products jsonb:=public.solar_inventory('catalog'); receipt bigint; snapshot jsonb; selected jsonb; hidden jsonb;
begin
 select p into selected from jsonb_array_elements(products)p where p->>'id'='-412571';
 select p into hidden from jsonb_array_elements(products)p where p->>'id'='-412572';
 if selected->>'cost' is distinct from '599' or selected ?| array['bookCost','cost_basis'] or
  hidden->>'cost' is not null or hidden->>'personalPriceBasis' is distinct from 'true' then raise exception 'Incorrect catalog projection';end if;
 select x into selected from jsonb_array_elements(public.solar_wholesale_pricing('state')->'products') x where x->>'id'='-412571';
 if selected->>'cost' is distinct from '599' then raise exception 'Wrong wholesale catalog projection';end if;
 select x into selected from jsonb_array_elements(public.solar_inventory('stock',null,'{}')->'products')x where x->>'id'='-412571';
 if selected->>'cost' is distinct from '599' or selected?'bookCost' then raise exception 'Wrong warehouse stock valuation';end if;
 if exists(select 1 from public.products where id in(-412571,-412572)) then raise exception 'Raw product valuation visible';end if;
 receipt:=(public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"credit","partyId":-412571,"party":"زبون كتالوج الاختبار","warehouseId":1,"items":[{"id":-412571,"qty":2,"price":800},{"id":-412572,"qty":1,"price":898}]}'::jsonb)->>'id')::bigint;
 perform set_config('fixture.catalog_frozen_receipt',receipt::text,true);
 if exists(select 1 from public.transactions where id=receipt) or exists(select 1 from public.transaction_items where transaction_id=receipt) then raise exception 'Raw financial rows visible';end if;
 select d into snapshot from jsonb_array_elements(public.solar_personal_receipt_snapshot(null,array['sale']))d where d#>>'{header,id}'=receipt::text;
 if (snapshot#>>'{header,profit}')::numeric is distinct from 884 or snapshot#>>'{header,cost}' is not null then raise exception 'Personal receipt profit or hidden fallback incorrect: %',snapshot->'header';end if;
 select x into selected from jsonb_array_elements(snapshot->'items')x where x->>'product_id'='-412571';
 select x into hidden from jsonb_array_elements(snapshot->'items')x where x->>'product_id'='-412572';
 if (selected->>'cost')::numeric is distinct from 599 or hidden->>'cost' is not null or hidden->>'personalCostHidden' is distinct from 'true'
  or selected ?| array['bookCost','cost_basis','landed_cost','source_price'] then raise exception 'Line valuation leaked';end if;
 if public.solar_personal_receipt_snapshot(receipt,array['sale'])<>'[]' then raise exception 'Snapshot cursor did not advance';end if;
 begin perform public.solar_purchase_correction_preview('{}');raise exception 'Purchase valuation preview permitted';exception when insufficient_privilege then null;end;
end $test$;

reset role;
update public.profiles set permissions=permissions-'profitUsesWholesalePrice' where id='00000000-0000-0000-0000-000000412571';
set local role authenticated;
do $test$
declare receipt bigint:=current_setting('fixture.catalog_frozen_receipt')::bigint; snapshot jsonb; ordinary_id bigint; contacts jsonb;
begin
 contacts:=public.solar_receipt_contacts();
 if contacts#>>'{0,hasPersonalReceipts}' is distinct from 'true' then raise exception 'Frozen receipts not advertised';end if;
 select d into snapshot from jsonb_array_elements(public.solar_personal_receipt_snapshot(null,array['sale']))d where d#>>'{header,id}'=receipt::text;
 if (snapshot#>>'{header,profit}')::numeric is distinct from 884 or exists(select 1 from public.transactions where id=receipt)
    or exists(select 1 from public.transaction_items where transaction_id=receipt) then raise exception 'Former seller lost their frozen profit';end if;
 ordinary_id:=(public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"credit","partyId":-412571,"party":"زبون كتالوج الاختبار","warehouseId":1,"items":[{"id":-412571,"qty":1,"price":801}]}'::jsonb)->>'id')::bigint;
 if not exists(select 1 from public.transactions where id=ordinary_id and profit=484)
   or not exists(select 1 from public.transaction_items where transaction_id=ordinary_id and cost=317)
   or jsonb_array_length(public.solar_personal_receipt_snapshot(null,array['sale']))<>1 then raise exception 'Subsequent receipt did not use restored cost basis';end if;
end $test$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412572',true);
do $test$ declare ordinary jsonb;begin
 select x into ordinary from jsonb_array_elements(public.solar_inventory('catalog'))x where x->>'id'='-412571';
 if (ordinary->>'cost')::numeric is distinct from 317 or not(ordinary?'bookCost') then raise exception 'Admin company valuation modified';end if;
 if not exists(select 1 from public.products where id=-412572 and cost=416) then raise exception 'Admin raw reads denied';end if;
 begin perform public.solar_personal_receipt_snapshot(null,array['sale']);raise exception 'Personal RPC invoked outside its role';exception when insufficient_privilege then null;end;
end $test$;
rollback;
