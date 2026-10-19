\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,username,is_admin,user_type,permissions) values
 ('00000000-0000-0000-0000-000000003500','Warehouse Admin','multi_admin',true,'admin_staff','{}'),
 ('00000000-0000-0000-0000-000000003501','Multi Seller','multi_seller',false,'admin_staff','{"sale":true,"system":true,"purchase":true,"exchangeRateEdit":true,"stock":true,"stockAdjust":true,"stockMovement":true,"products":true,"salesHistory":true,"warehouse":true}'),
 ('00000000-0000-0000-0000-000000003502','Main preparer','main_preparer',false,'warehouse','{}'),
 ('00000000-0000-0000-0000-000000003503','Sayada preparer','sayada_preparer',false,'warehouse','{}'),
 ('00000000-0000-0000-0000-000000003504','Other seller','other_seller',false,'admin_staff','{"sale":true,"warehouse":true,"stock":true,"stockMovement":true}');
insert into products(id,code,name,qty,cost) values(-350001,'MULTI-01','Multi location panel',10,100),(-350002,'MULTI-02','Other material',2,50);
insert into suppliers(id,name,account_currency) values(-350001,'USD Multi Supplier','USD');
insert into customers(id,name,customer_type,owner_id) values(-350001,'Multi Customer','wholesale','00000000-0000-0000-0000-000000003501');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003500',true);
do $$declare main bigint:=solar_private.primary_warehouse();sayada bigint; r jsonb;payload jsonb;request uuid:=gen_random_uuid();before_cost numeric;before_tx bigint;begin
 select id into sayada from solar_private.warehouses where code='SAYADA';
 r:=public.solar_inventory('manage');if jsonb_array_length(r->'warehouses')<>2 then raise exception 'warehouse management context';end if;
 if(select qty from solar_private.warehouse_stocks where warehouse_id=main and product_id=-350001)<>10 then raise exception 'initial stock not in main';end if;
 r:=public.solar_inventory('access_save',gen_random_uuid(),jsonb_build_object('userId','00000000-0000-0000-0000-000000003501','all',true,'ids','[]'::jsonb,'canTransfer',true,'revision',0));
 perform public.solar_inventory('access_save',gen_random_uuid(),jsonb_build_object('userId','00000000-0000-0000-0000-000000003503','all',false,'ids',jsonb_build_array(sayada),'canTransfer',false,'revision',0));
 select cost into before_cost from products where id=-350001;select count(*) into before_tx from transactions;
 payload:=jsonb_build_object('fromId',main,'toId',sayada,'items',jsonb_build_array(jsonb_build_object('productId',-350001,'qty',3,'revision',0)),'note','Transfer at book cost');
 r:=public.solar_inventory('transfer',request,payload);
 if public.solar_inventory('transfer',request,payload)<>r then raise exception 'idempotent transfer result changed';end if;
 if(select qty from solar_private.warehouse_stocks where warehouse_id=sayada and product_id=-350001)<>3 or(select qty from products where id=-350001)<>10 or(select cost from products where id=-350001)<>before_cost or(select count(*) from transactions)<>before_tx then raise exception 'transfer changed company accounting or repeated';end if;
 if(select (items->0->>'unitCost')::numeric from solar_private.stock_transfers where id=request)<>100 then raise exception 'transfer cost not frozen';end if;
 begin perform public.solar_inventory('transfer',request,payload||'{"note":"changed"}');raise exception 'changed replay allowed';exception when sqlstate 'PT409' then null;end;
 begin
  perform public.solar_inventory('transfer',gen_random_uuid(),jsonb_build_object('fromId',main,'toId',sayada,'items',jsonb_build_array(jsonb_build_object('productId',-350002,'qty',1,'revision',0),jsonb_build_object('productId',-350001,'qty',99,'revision',1))));
  raise exception 'insufficient transfer allowed';
 exception when sqlstate 'PT409' then null;end;
 if(select qty from solar_private.warehouse_stocks where warehouse_id=main and product_id=-350002)<>2 then raise exception 'partial transfer survived rollback';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003501',true);
do $$declare main bigint:=solar_private.primary_warehouse();sayada bigint;r jsonb;sale jsonb;invoice bigint;local_cost numeric;begin
 select id into sayada from solar_private.warehouses where code='SAYADA';
 r:=public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','purchase','warehouseId',sayada,'party','USD Multi Supplier','partyId',-350001,'mode','credit','sourceCurrency','USD','exchangeRate',1660,'marketRate',1660,'accountRevision',(select currency_revision from suppliers where id=-350001),'items',jsonb_build_array(jsonb_build_object('id',-350001,'qty',2,'price',1.25))));
 if(select qty from solar_private.warehouse_stocks where warehouse_id=main and product_id=-350001)<>7 or(select qty from solar_private.warehouse_stocks where warehouse_id=sayada and product_id=-350001)<>5 or(select qty from products where id=-350001)<>12 then raise exception 'USD purchase location allocation incorrect';end if;
 if abs((select cost from products where id=-350001)-(5150::numeric/12))>0.000001 then raise exception 'global weighted average lost';end if;
 sale:=jsonb_build_object('kind','sale','warehouseId',sayada,'party','Multi Customer','partyId',-350001,'mode','credit','items',jsonb_build_array(jsonb_build_object('id',-350001,'qty',2,'price',1000)));
 r:=public.solar_invoice_save(gen_random_uuid(),sale);invoice:=(r->>'id')::bigint;
 if(r->>'warehouseId')::bigint<>sayada or r->>'warehouseName'<>'مخزن صيادة' then raise exception 'invoice warehouse omitted';end if;
 select cost into local_cost from transactions where id=invoice;
 if abs(local_cost-858.33)>0.01 then raise exception 'sale book cost incorrect %',local_cost;end if;
 begin perform public.solar_invoice_save(gen_random_uuid(),jsonb_set(sale,'{items,0,qty}','4'));raise exception 'global quantity bypassed local shortage';exception when sqlstate 'PT409' then null;end;
 if(select qty from solar_private.warehouse_stocks where warehouse_id=sayada and product_id=-350001)<>3 then raise exception 'failed sale changed balance';end if;
 perform public.solar_invoice_save(gen_random_uuid(),sale||jsonb_build_object('warehouseId',main,'items',jsonb_build_array(jsonb_build_object('id',-350002,'qty',1,'price',100))));
 r:=public.solar_warehouse_orders('','',0);if(r->>'count')::integer<>2 then raise exception 'all warehouses missing invoices';end if;
 if(public.solar_inventory('orders',null,jsonb_build_object('warehouseId',sayada,'state',''))->>'count')::integer<>1 then raise exception 'warehouse filter wrong';end if;
 r:=public.solar_inventory('movements',null,jsonb_build_object('warehouseId',sayada,'productId',-350001));
 if not exists(select 1 from jsonb_array_elements(r) m where m->>'kind'='purchase') then raise exception 'purchase movement missing';end if;
 perform public.solar_reconcile('stock_balance',gen_random_uuid(),jsonb_build_object('warehouseId',sayada,'productId',-350001,'expected',3,'actual',4,'note','Sayada physical count'));
 if(select qty from products where id=-350001)<>11 or(select qty from solar_private.warehouse_stocks where warehouse_id=main and product_id=-350001)<>7 then raise exception 'scoped adjustment changed other warehouse';end if;
 if(select cost from transactions where id=invoice)<>local_cost then raise exception 'frozen sale cost changed';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003502',true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_warehouse_orders('','',0);if(r->>'count')::integer<>1 or r::text like '%مخزن صيادة%' then raise exception 'main-only preparer saw Sayada orders %',r;end if;
 r:=public.solar_stock_quantities();if r::text like '%unitCost%' or r::text like '%cost_basis%' or r::text like '%companyQty%' or r::text like '%"cost"%' then raise exception 'preparer cost disclosure';end if;
 if(select count(*) from products)<>0 then raise exception 'raw global quantity leaked';end if;
 begin perform public.solar_inventory('stock',null,jsonb_build_object('warehouseId',(r->0->>'id')::bigint+99999));raise exception 'location IDOR';exception when insufficient_privilege then null;end;
 begin perform public.solar_inventory('manage');raise exception 'nonadmin manage allowed';exception when insufficient_privilege then null;end;
end$$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003503',true);
do $$declare r jsonb;invoice_value bigint;begin
 r:=public.solar_warehouse_orders('','pending',0);if(r->>'count')::integer<>1 or r->'rows'->0->>'warehouseName'<>'مخزن صيادة' then raise exception 'Sayada preparer missing order %',r;end if;
 if(r->'rows'->0) ? 'invoiceAccount' or(r->'rows'->0) ? 'total' then raise exception 'financial detail in warehouse order';end if;
 invoice_value:=(r->'rows'->0->>'id')::bigint;
 perform public.solar_warehouse_action(invoice_value,r->'rows'->0->>'token','ready');
 if(select warehouse_status from transactions where transactions.id=invoice_value)<>'ready' then raise exception 'Sayada order not prepared';end if;
 if exists(select 1 from solar_notifications n where n.user_id='00000000-0000-0000-0000-000000003502' and n.job_id=invoice_value) then raise exception 'wrong warehouse push recipient';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003504',true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_inventory('catalog');if exists(select 1 from jsonb_array_elements(r) m where m->>'companyQty' is not null) then raise exception 'scoped seller global quantity disclosure';end if;
 if exists(select 1 from products) then raise exception 'raw product quantities disclosed';end if;
 if(public.solar_warehouse_orders('','',0)->>'count')::integer<>0 then raise exception 'warehouse assignment bypassed creator privacy';end if;
 if jsonb_array_length(public.solar_stock_movements())<>0 then raise exception 'foreign movement disclosure';end if;
 begin update products set qty=999 where id=-350001;exception when insufficient_privilege then null;end;
end$$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003500',true);
do $$declare r jsonb;main bigint:=solar_private.primary_warehouse();sayada bigint;future bigint;invoice public.transactions;body jsonb;old_balance numeric;old_total numeric;request uuid:=gen_random_uuid();begin
 select id into sayada from solar_private.warehouses where code='SAYADA';
 select * into invoice from transactions where kind='sale' and warehouse_id=sayada;
 body:=jsonb_build_object('kind','sale','warehouseId',sayada,'party','Multi Customer','partyId',-350001,'mode','cash','invoiceId',invoice.id,'expectedRevision',invoice.pricing_revision,'items',jsonb_build_array(jsonb_build_object('id',-350001,'qty',1,'price',1000)));
 r:=public.solar_invoice_save(gen_random_uuid(),body);
 if(select qty from solar_private.warehouse_stocks where product_id=-350001 and warehouse_id=sayada)<>5 then raise exception 'sale edit did not return quantity locally';end if;
 if(select qty from solar_private.warehouse_stocks where product_id=-350001 and warehouse_id=main)<>7 then raise exception 'sale edit changed other warehouse';end if;
 body:=body||jsonb_build_object('warehouseId',main,'expectedRevision',r->'pricingRevision');
 begin perform public.solar_invoice_save(gen_random_uuid(),body);raise exception 'saved invoice source changed';exception when insufficient_privilege then null;end;
 -- Actual protected deletion must return this warehouse's stock exactly once.
 r:=public.solar_sale_delete_preview(invoice.id);
 perform public.solar_sale_delete(invoice.id,r->>'token');
 if(select qty from solar_private.warehouse_stocks where product_id=-350001 and warehouse_id=sayada)<>6 or(select qty from products where id=-350001)<>13 then raise exception 'sale deletion returned wrong stock';end if;
 r:=public.solar_inventory('warehouse_save',gen_random_uuid(),'{"name":"Future test warehouse"}');future:=(r->>'id')::bigint;
 if not solar_private.warehouse_access_allowed('00000000-0000-0000-0000-000000003501',future) or solar_private.warehouse_access_allowed('00000000-0000-0000-0000-000000003502',future) then raise exception 'future warehouse access incorrect';end if;
 r:=public.solar_inventory('transfer',request,jsonb_build_object('fromId',main,'toId',future,'items',jsonb_build_array(jsonb_build_object('productId',-350002,'qty',1,'revision',(select revision from solar_private.warehouse_stocks where product_id=-350002 and warehouse_id=main)))));
 begin perform public.solar_inventory('warehouse_save',gen_random_uuid(),jsonb_build_object('id',future,'name','Future test warehouse','revision',0,'active',false));raise exception 'nonempty warehouse deactivated';exception when raise_exception then if sqlerrm='nonempty warehouse deactivated' then raise;end if;end;
 perform public.solar_inventory('reverse_transfer',gen_random_uuid(),jsonb_build_object('id',request));
 if(select qty from solar_private.warehouse_stocks where product_id=-350002 and warehouse_id=main)<>1 or(select qty from solar_private.warehouse_stocks where product_id=-350002 and warehouse_id=future)<>0 then raise exception 'transfer reversal incorrect';end if;
 perform public.solar_inventory('warehouse_save',gen_random_uuid(),jsonb_build_object('id',future,'name','Future test warehouse','revision',0,'active',false));
 -- The admin only changes metadata via the protected catalog; no scoped quantity overwrites the company balance.
 perform public.solar_inventory('catalog_save',gen_random_uuid(),'{"rows":[{"id":-350001,"code":"MULTI-01","name":"Renamed material","qty":999999,"cost":1}]}');
 if(select qty from products where id=-350001)<>13 or(select cost from products where id=-350001)=1 then raise exception 'metadata write changed inventory value';end if;
 -- A new purchase can be edited and removed from its receiving warehouse.
 insert into products(id,code,name,qty,cost) values(-350003,'MULTI-03','Editable purchase',0,0);
 body:=jsonb_build_object('kind','purchase','warehouseId',sayada,'party','USD Multi Supplier','partyId',-350001,'mode','credit','sourceCurrency','USD','exchangeRate',1660,'marketRate',1660,'accountRevision',(select currency_revision from suppliers where id=-350001),'items',jsonb_build_array(jsonb_build_object('id',-350003,'qty',2,'price',1.25)));
 r:=public.solar_invoice_save(gen_random_uuid(),body);
 body:=body||jsonb_build_object('invoiceId',r->'id','expectedRevision',r->'pricingRevision','items',jsonb_build_array(jsonb_build_object('id',-350003,'qty',3,'price',1.50)));
 r:=public.solar_invoice_save(gen_random_uuid(),body);
 if(select qty from solar_private.warehouse_stocks where product_id=-350003 and warehouse_id=sayada)<>3 or(select qty from products where id=-350003)<>3 then raise exception 'purchase edit location incorrect';end if;
 perform public.solar_purchase_delete((r->>'id')::bigint,(r->>'pricingRevision')::bigint);
 if(select qty from products where id=-350003)<>0 or(select qty from solar_private.warehouse_stocks where product_id=-350003 and warehouse_id=sayada)<>0 then raise exception 'purchase delete not restored';end if;
end$$;
set constraints all immediate;
select 'multi-warehouse quantities, transfers, FX costs, access, fulfillment and privacy passed';
rollback;
