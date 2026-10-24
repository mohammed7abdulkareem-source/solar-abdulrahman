\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions) values
('00000000-0000-0000-0000-000000003710','مدير الفترة',true,'admin_staff','07700003710','{}'),
('00000000-0000-0000-0000-000000003711','بائع الفترة',false,'admin_staff','07700003711','{"sale":true,"system":true,"salesHistory":true}'),
('00000000-0000-0000-0000-000000003712','بائع آخر',false,'admin_staff','07700003712','{"sale":true}'),
('00000000-0000-0000-0000-000000003713','سجل فقط',false,'admin_staff','07700003713','{"sale":true,"salesHistory":true}'),
('00000000-0000-0000-0000-000000003714','مهندس الفترة',true,'installer','07700003714','{}'),
('00000000-0000-0000-0000-000000003715','مخزن الفترة',false,'warehouse','07700003715','{}'),
('00000000-0000-0000-0000-000000003716','بدون صلاحية',false,'admin_staff','07700003716','{}');
insert into brands(id,name) values(-371001,'FULLMAX');
insert into products(id,code,name,brand_id,category,qty,cost) values
(-371001,'0002','مادة بنفس الاسم',-371001,'ألواح',1000,10),
(-371002,'0010','مادة بنفس الاسم',-371001,'ألواح',1000,20),
(-371003,'0001','مادة كسرية',-371001,'مستلزمات',1000,30);
insert into customers(id,name,customer_type,owner_id) values
(-371001,'عميل الفترة','wholesale','00000000-0000-0000-0000-000000003711'),
(-371002,'منظومة الفترة','system','00000000-0000-0000-0000-000000003711'),
(-371003,'عميل مستخدم آخر','wholesale','00000000-0000-0000-0000-000000003712'),
(-371004,'عميل السجل فقط','wholesale','00000000-0000-0000-0000-000000003713');
insert into suppliers(id,name) values(-371001,'مورد رصيد لاحق');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003711',true);
do $$declare i integer;r jsonb;begin
 for i in 1..40 loop
  r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-371001,"party":"عميل الفترة","mode":"credit","warehouseId":1,"items":[{"id":-371001,"qty":2,"price":100}]}');
  update transactions set created_at='2026-10-24T12:00Z'::timestamptz+i*interval '1 second' where id=(r->>'id')::bigint;
 end loop;
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-371001,"party":"عميل الفترة","mode":"credit","warehouseId":1,"items":[{"id":-371001,"qty":1,"price":200}]}');
 update transactions set created_at='2026-10-24T20:59:59Z' where id=(r->>'id')::bigint;
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-371001,"party":"عميل الفترة","mode":"credit","warehouseId":1,"items":[{"id":-371001,"qty":4,"price":200}]}');
 update transactions set created_at='2026-10-24T21:00:00Z' where id=(r->>'id')::bigint;
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","partyId":-371002,"party":"منظومة الفترة","mode":"credit","warehouseId":1,"installerId":"00000000-0000-0000-0000-000000003714","customerAddress":"عنوان","total":500000,"items":[{"id":-371001,"qty":5,"price":0},{"id":-371002,"qty":1,"price":0}]}');
 update transactions set created_at='2026-10-24T14:00Z' where id=(r->>'id')::bigint;
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-371001,"party":"عميل الفترة","mode":"credit","warehouseId":1,"items":[{"id":-371002,"qty":3,"price":100},{"id":-371003,"qty":1.125,"price":100}]}');
 update transactions set created_at='2026-10-24T15:00Z' where id=(r->>'id')::bigint;
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-371001,"party":"عميل الفترة","mode":"credit","warehouseId":1,"items":[{"id":-371003,"qty":0.001,"price":0}]}');
 update transactions set created_at='2026-10-24T15:01Z' where id=(r->>'id')::bigint;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003712',true);
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-371003,"party":"عميل مستخدم آخر","mode":"credit","warehouseId":1,"items":[{"id":-371001,"qty":7,"price":999999}]}');
 update transactions set created_at='2026-10-24T16:00Z' where id=(r->>'id')::bigint;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003713',true);
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-371004,"party":"عميل السجل فقط","mode":"credit","warehouseId":1,"items":[{"id":-371002,"qty":2,"price":100}]}');
 update transactions set created_at='2026-10-24T17:00Z' where id=(r->>'id')::bigint;
end$$;
update profiles set permissions='{"salesHistory":true}' where id='00000000-0000-0000-0000-000000003713';
-- A fixture transfer keeps company quantity unchanged and creates a stock scope difference.
select solar_private.change_warehouse_stock(1,-371001,-25);
select solar_private.change_warehouse_stock((select id from solar_private.warehouses where not is_primary order by id limit 1),-371001,25);

-- Add committed receipts, staged warehouse lines and a transfer before the
-- rename, then compare read projections and immutable business records.
update profiles set permissions=permissions||'{"systemPayment":true,"customerPayment":true,"profit":true,"cash":true}'::jsonb where id='00000000-0000-0000-0000-000000003711';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003711',true);
do $$declare r jsonb;a jsonb;j jsonb;lines jsonb;begin
 r:=public.solar_invoice_save('00000000-0000-0000-0000-000000037201','{"kind":"sale","partyId":-371001,"party":"عميل الفترة","mode":"cash","warehouseId":1,"items":[{"id":-371001,"qty":1,"price":100}]}');
 perform set_config('test.brand.cash',r->>'id',true);perform set_config('test.brand.saved',r::text,true);
 perform set_config('test.brand.system',(select id::text from transactions where kind='system' and party_id=-371002 limit 1),true);
 a:=public.solar_system_payment_context(-371002);
 r:=public.solar_system_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-371002,'invoiceId',current_setting('test.brand.system')::bigint,'amount',2000,'mode','payment','expectedToken',a->>'token'));
 perform set_config('test.brand.payment',r->>'id',true);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003715',true);
 j:=public.solar_warehouse_orders('@id:'||current_setting('test.brand.cash'),'')->'rows'->0;
 select jsonb_agg(jsonb_build_object('lineId',x->'lineId','productId',x->'productId','qty',x->'qty')) into lines from jsonb_array_elements(j->'items')x;
 perform public.solar_warehouse_action((j->>'id')::bigint,j->>'token','save',lines||'[{"productId":-371002,"qty":1}]','طلب فقرة جديدة');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003710',true);
 r:=public.solar_inventory('transfer',gen_random_uuid(),jsonb_build_object('fromId',1,'toId',(select id from solar_private.warehouses where not is_primary order by id limit 1),'items',jsonb_build_array(jsonb_build_object('productId',-371001,'qty',1,'revision',(select revision from solar_private.warehouse_stocks where warehouse_id=1 and product_id=-371001)))));
 perform set_config('test.brand.transfer',r->>'id',true);
end$$;
create function pg_temp.brand_views() returns jsonb language plpgsql as $$declare a jsonb;b jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003710',true);
 a:=jsonb_build_object(
  'period',public.solar_sales_period(),
  'history',public.solar_sales_history(),
  'customer',public.solar_customer_movement(-371001,current_setting('test.brand.cash')::bigint),
  'systemCustomer',public.solar_customer_movement(-371002,current_setting('test.brand.payment')::bigint),
  'payment',public.solar_payment_history('get',jsonb_build_object('id',current_setting('test.brand.payment')::bigint)),
  'systemContext',public.solar_system_payment_context(-371002),
  'cash',public.solar_cash_movement_detail('tx:'||current_setting('test.brand.cash')),
  'profit',public.solar_profit_detail('tx:'||current_setting('test.brand.cash'),'00000000-0000-0000-0000-000000003711'),
  'movements',public.solar_inventory('movements',null,'{"warehouseId":1}'),
  'transfer',public.solar_inventory('transfer_get',null,jsonb_build_object('id',current_setting('test.brand.transfer'))),
  'pricing',public.solar_warehouse_pricing('get',current_setting('test.brand.cash')::bigint),
  'certificate',public.solar_warranty_verify((select warehouse_qr_token from transactions where id=current_setting('test.brand.cash')::bigint)));
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003715',true);
 a:=a||jsonb_build_object('warehouse',public.solar_warehouse_orders(),'warehouseTransfer',public.solar_inventory('transfer_get',null,jsonb_build_object('id',current_setting('test.brand.transfer'))));
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003714',true);
 a:=a||jsonb_build_object('engineer',public.solar_installation_jobs());
 return a;
end$$;
create function pg_temp.without_brands(v jsonb) returns jsonb language plpgsql as $$begin
 if jsonb_typeof(v)='object' then return(select coalesce(jsonb_object_agg(key,pg_temp.without_brands(value)),'{}') from jsonb_each(v) where key not in('brand','brand_name'));
 elsif jsonb_typeof(v)='array' then return(select coalesce(jsonb_agg(pg_temp.without_brands(value) order by ordinality),'[]') from jsonb_array_elements(v) with ordinality);
 end if;return v;
end$$;
do $$declare before_views jsonb;after_views jsonb;before_money text;before_token text;k text;v jsonb;j jsonb;begin
 before_views:=pg_temp.brand_views();
 select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t) order by id) from transactions t),'items',(select jsonb_agg(to_jsonb(i) order by id) from transaction_items i),'productValues',(select jsonb_agg(jsonb_build_array(id,qty,cost,cost_basis,costing_revision) order by id) from products),'stocks',(select jsonb_agg(to_jsonb(w) order by warehouse_id,product_id) from solar_private.warehouse_stocks w),'requests',(select jsonb_agg(to_jsonb(r) order by request_id) from solar_private.finance_requests r))::text) into before_money;
 before_token:=solar_private.warehouse_token(current_setting('test.brand.cash')::bigint);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003710',true);
 update brands set name='BRAND_RENAMED' where id=-371001;
 after_views:=pg_temp.brand_views();
 for k,v in select * from jsonb_each(after_views) loop
  if v::text like '%FULLMAX%' then raise exception 'FAIL obsolete brand in %',k;end if;
  if v::text not like '%BRAND_RENAMED%' then raise exception 'FAIL missing current brand in %',k;end if;
 end loop;
 if pg_temp.without_brands(before_views)<>pg_temp.without_brands(after_views) then raise exception 'FAIL rename changed non-label response values in %',(select jsonb_agg(key) from jsonb_each(before_views) where pg_temp.without_brands(value)<>pg_temp.without_brands(after_views->key));end if;
 -- Reassign a single material to another existing brand; grouping remains by ID.
 insert into brands(id,name) values(-372001,'BRAND_REASSIGNED');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003710',true);
 perform public.solar_inventory('catalog_save',gen_random_uuid(),'{"rows":[{"id":-371001,"code":"0002","name":"مادة بنفس الاسم","brand_id":-372001,"category":"ألواح"}],"removed":[]}');
 j:=public.solar_sales_period();
 if(select value->>'brand' from jsonb_array_elements(j->'rows') where(value->>'productId')::bigint=-371001)<>'BRAND_REASSIGNED' then raise exception 'FAIL brand reassignment';end if;
 if solar_private.warehouse_token(current_setting('test.brand.cash')::bigint)<>before_token then raise exception 'FAIL rename invalidated preparation token';end if;
 if (select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t) order by id) from transactions t),'items',(select jsonb_agg(to_jsonb(i) order by id) from transaction_items i),'productValues',(select jsonb_agg(jsonb_build_array(id,qty,cost,cost_basis,costing_revision) order by id) from products),'stocks',(select jsonb_agg(to_jsonb(w) order by warehouse_id,product_id) from solar_private.warehouse_stocks w),'requests',(select jsonb_agg(to_jsonb(r) order by request_id) from solar_private.finance_requests r))::text))<>before_money then raise exception 'FAIL brand edit rewrote business history';end if;
 -- Clearing a valid material's brand must not resurrect its old saved brand.
 update products set brand_id=null where id=-371001;
 if solar_private.current_product_brand(-371001,'FULLMAX')<>'' or solar_private.current_product_brand(null,'LEGACY')<>'LEGACY' or solar_private.current_product_brand(-999999,'DELETED')<>'DELETED' then raise exception 'FAIL empty/deleted/legacy brand fallback';end if;
 if has_function_privilege('authenticated','solar_private.current_product_brand(bigint,text)','execute') or has_function_privilege('anon','solar_private.current_item_brands(jsonb)','execute') then raise exception 'FAIL label helper exposed';end if;
end$$;
set constraints all immediate;
\echo PASS brand rename across period/archive/customer/payment/cash/profit/warehouse/engineer/transfer/warranty, reassignment and removal; original money, stock, saved snapshots and tokens unchanged
rollback;
