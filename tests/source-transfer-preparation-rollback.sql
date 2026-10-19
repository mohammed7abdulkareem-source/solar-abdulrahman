\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,username,is_admin,user_type,permissions) values
 ('00000000-0000-0000-0000-000000003510','Transfer Admin','transfer_admin',true,'admin_staff','{}'),
 ('00000000-0000-0000-0000-000000003511','Outgoing User','outgoing_user',false,'admin_staff','{"sale":true,"stock":true,"stockMovement":true}'),
 ('00000000-0000-0000-0000-000000003512','Incoming User','incoming_user',false,'admin_staff','{"stock":true,"stockMovement":true}'),
 ('00000000-0000-0000-0000-000000003513','Main Preparer','main_preparer_351',false,'warehouse','{}'),
 ('00000000-0000-0000-0000-000000003514','Sayada Preparer','sayada_preparer_351',false,'warehouse','{}');
insert into products(id,code,name,qty,cost) values(-351001,'SOURCE-351','Source transfer panel',20,100),(-351002,'SOURCE-352','Second transfer product',10,50);
insert into customers(id,name,customer_type,owner_id) values(-351001,'Transfer Customer','wholesale','00000000-0000-0000-0000-000000003511');
insert into public.solar_push_subscriptions(endpoint,user_id,p256dh,auth_key) values
 ('https://fcm.googleapis.com/local-main-351','00000000-0000-0000-0000-000000003513','fixture','fixture'),
 ('https://fcm.googleapis.com/local-sayada-351','00000000-0000-0000-0000-000000003514','fixture','fixture');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003510',true);
do $$declare r jsonb;main bigint:=solar_private.primary_warehouse();secondary bigint;begin
 select id into secondary from solar_private.warehouses where code='SAYADA';
 perform public.solar_inventory('access_save',gen_random_uuid(),jsonb_build_object('userId','00000000-0000-0000-0000-000000003511','all',true,'ids','[]'::jsonb,'revision',0,'transferDirections','{"fromPrimary":true,"toPrimary":false,"other":false}'::jsonb));
 perform public.solar_inventory('access_save',gen_random_uuid(),jsonb_build_object('userId','00000000-0000-0000-0000-000000003512','all',true,'ids','[]'::jsonb,'revision',0,'transferDirections','{"fromPrimary":false,"toPrimary":true,"other":false}'::jsonb));
 perform public.solar_inventory('access_save',gen_random_uuid(),jsonb_build_object('userId','00000000-0000-0000-0000-000000003514','all',false,'ids',jsonb_build_array(secondary),'revision',0,'transferDirections','{}'::jsonb));
 r:=public.solar_inventory('manage');if not exists(select 1 from jsonb_array_elements(r->'users') u where u->>'id'='00000000-0000-0000-0000-000000003511' and u->'transferDirections'='{"fromPrimary":true,"toPrimary":false,"other":false}') then raise exception 'direction permissions missing';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003511',true);
do $$declare p jsonb;r jsonb;request uuid:=gen_random_uuid();main bigint:=solar_private.primary_warehouse();secondary bigint;begin
 select id into secondary from solar_private.warehouses where code='SAYADA';
 p:=jsonb_build_object('fromId',main,'toId',secondary,'items','[{"productId":-351001,"qty":2,"revision":0},{"productId":-351002,"qty":1,"revision":0}]'::jsonb,'note','First source request');
 r:=public.solar_inventory('transfer',request,p);if r->>'status'<>'pending' or public.solar_inventory('transfer',request,p)<>r then raise exception 'request/replay incorrect';end if;
 perform set_config('test.outgoing_one',request::text,true);
 if(select qty from products where id=-351001)<>20 or(select cost from products where id=-351001)<>100 then raise exception 'request changed global quantity/cost';end if;
 if(select qty from solar_private.warehouse_stocks where product_id=-351001 and warehouse_id=main)<>18 or(select reserved_qty from solar_private.warehouse_stocks where product_id=-351001 and warehouse_id=main)<>2 then raise exception 'source not reserved once';end if;
 if exists(select 1 from solar_private.warehouse_stocks where product_id=-351001 and warehouse_id=secondary and qty<>0) then raise exception 'destination credited before preparation';end if;
 r:=public.solar_inventory('catalog');if not exists(select 1 from jsonb_array_elements(r) x where(x->>'id')::bigint=-351001 and(x->>'qty')::numeric=18 and(x->>'bookQty')::numeric=20 and(x->>'reservedQty')::numeric=2) then raise exception 'availability/book stock lost reservation';end if;
 r:=public.solar_inventory('transfer',gen_random_uuid(),jsonb_build_object('fromId',main,'toId',secondary,'items','[{"productId":-351001,"qty":3,"revision":1}]'::jsonb));
 perform set_config('test.outgoing_two',r->>'id',true);
 begin perform public.solar_inventory('prepare_transfer',gen_random_uuid(),jsonb_build_object('id',request,'expectedRevision',0));raise exception 'requester self-prepared';exception when insufficient_privilege then null;end;
 begin perform public.solar_inventory('transfer',gen_random_uuid(),jsonb_build_object('fromId',secondary,'toId',main,'items','[{"productId":-351001,"qty":1,"revision":0}]'::jsonb));raise exception 'outbound-only user returned from Sayada';exception when insufficient_privilege then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','sale','warehouseId',main,'party','Transfer Customer','partyId',-351001,'mode','credit','items','[{"id":-351001,"qty":16,"price":200}]'::jsonb));raise exception 'reserved stock was sold';exception when sqlstate 'PT409' then null;end;
 if exists(select 1 from transactions) then raise exception 'transfer made a financial transaction';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003513',true);
set local role authenticated;
do $$declare q jsonb;r jsonb;command uuid:=gen_random_uuid();p jsonb;begin
 q:=public.solar_inventory('transfer_queue');if(q->>'count')::integer<>2 then raise exception 'Main preparer missing requests %',q;end if;
 if q::text like '%unitCost%' or q::text like '%costBasis%' or q::text like '%companyQty%' then raise exception 'preparer cost leak';end if;
 if(select count(*) from solar_notifications where event='stock_transfer_pending')<>2 then raise exception 'Main notifications missing/duplicated';end if;
 p:=jsonb_build_object('id',current_setting('test.outgoing_one'),'expectedRevision',0);
 r:=public.solar_inventory('prepare_transfer',command,p);if r->>'status'<>'posted' or public.solar_inventory('prepare_transfer',command,p)<>r then raise exception 'prepare replay not atomic';end if;
 begin perform public.solar_inventory('prepare_transfer',gen_random_uuid(),p);raise exception 'duplicate preparation succeeded';exception when sqlstate 'PT409' then null;end;
end$$;
reset role;
do $$declare secondary bigint;begin
 select id into secondary from solar_private.warehouses where code='SAYADA';
 if(select qty from solar_private.warehouse_stocks where product_id=-351001 and warehouse_id=secondary)<>2 or(select qty from solar_private.warehouse_stocks where product_id=-351002 and warehouse_id=secondary)<>1 then raise exception 'prepare did not deliver all lines once';end if;
 if(select qty from solar_private.warehouse_stocks where product_id=-351001 and warehouse_id=solar_private.primary_warehouse())<>15 then raise exception 'prepare deducted source twice';end if;
 if(select reserved_qty from solar_private.warehouse_stocks where product_id=-351001 and warehouse_id=solar_private.primary_warehouse())<>3 then raise exception 'other request reservation lost';end if;
 if exists(select 1 from solar_notifications where user_id='00000000-0000-0000-0000-000000003514' and stock_transfer_id=current_setting('test.outgoing_one')::uuid) then raise exception 'destination preparer notified about another source';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003512',true);
do $$declare main bigint:=solar_private.primary_warehouse();secondary bigint;r jsonb;begin
 select id into secondary from solar_private.warehouses where code='SAYADA';
 begin perform public.solar_inventory('transfer',gen_random_uuid(),jsonb_build_object('fromId',main,'toId',secondary,'items','[{"productId":-351001,"qty":1,"revision":3}]'::jsonb));raise exception 'inbound-only user sent from Main';exception when insufficient_privilege then null;end;
 r:=public.solar_inventory('transfer',gen_random_uuid(),jsonb_build_object('fromId',secondary,'toId',main,'items',jsonb_build_array(jsonb_build_object('productId',-351001,'qty',1,'revision',(select revision from solar_private.warehouse_stocks where warehouse_id=secondary and product_id=-351001)))));
 perform set_config('test.return_request',r->>'id',true);
 r:=public.solar_inventory('transfers');if jsonb_array_length(r)<>1 or r->0->>'id'<>current_setting('test.return_request') then raise exception 'another user transfer disclosed';end if;
end$$;
-- An old/misrouted notification is hidden too, not merely omitted from future pushes.
insert into solar_notifications(user_id,stock_transfer_id,event,title,body) values('00000000-0000-0000-0000-000000003513',current_setting('test.return_request')::uuid,'stock_transfer_pending','WRONG_SOURCE','Hidden');
insert into solar_private.push_deliveries(notification_id,endpoint) select id,'https://fcm.googleapis.com/local-main-351' from solar_notifications where title='WRONG_SOURCE';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003513',true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_inventory('transfer_queue','00000000-0000-0000-0000-000000003599','{"state":""}');if(r->>'count')::integer<>2 or r::text like '%'||current_setting('test.return_request')||'%' then raise exception 'Main queue shows a different source';end if;
 r:=public.solar_inventory('transfers');if jsonb_array_length(r)<>2 then raise exception 'Main transfer history includes incoming source';end if;
 r:=public.solar_inventory('movements');if r::text like '%'||current_setting('test.return_request')||'%' then raise exception 'incoming transfer exposed in movement report';end if;
 if exists(select 1 from solar_notifications where title='WRONG_SOURCE') then raise exception 'misrouted notification exposed';end if;
 begin perform public.solar_inventory('transfer_get',null,jsonb_build_object('id',current_setting('test.return_request')));raise exception 'known-ID transfer leak';exception when insufficient_privilege then null;end;
 begin perform public.solar_inventory('prepare_transfer',gen_random_uuid(),jsonb_build_object('id',current_setting('test.return_request'),'expectedRevision',0));raise exception 'Main prepared a Sayada source';exception when insufficient_privilege then null;end;
end$$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003514',true);
do $$declare r jsonb;begin
 r:=public.solar_inventory('transfer_queue');if(r->>'count')::integer<>1 or r->'rows'->0->>'id'<>current_setting('test.return_request') then raise exception 'Sayada preparer missing own source';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003510',true);
do $$declare r jsonb;begin
 begin perform public.solar_inventory('reverse_transfer',gen_random_uuid(),jsonb_build_object('id',current_setting('test.outgoing_one'),'expectedRevision',1));raise exception 'reverse consumed reserved destination quantity';exception when sqlstate 'PT409' then null;end;
 r:=public.solar_inventory('cancel_transfer',gen_random_uuid(),jsonb_build_object('id',current_setting('test.return_request'),'expectedRevision',0));if r->>'status'<>'cancelled' then raise exception 'request cancellation missing';end if;
 perform public.solar_inventory('reverse_transfer',gen_random_uuid(),jsonb_build_object('id',current_setting('test.outgoing_one'),'expectedRevision',1));
 perform public.solar_inventory('cancel_transfer',gen_random_uuid(),jsonb_build_object('id',current_setting('test.outgoing_two'),'expectedRevision',0));
 if exists(select 1 from solar_private.warehouse_stocks where reserved_qty<>0) then raise exception 'reservation survived preparation/cancellation';end if;
 if(select qty from solar_private.warehouse_stocks where product_id=-351001 and warehouse_id=solar_private.primary_warehouse())<>20 or(select qty from products where id=-351001)<>20 or(select cost from products where id=-351001)<>100 then raise exception 'quantities/book cost not restored';end if;
 if exists(select 1 from transactions) then raise exception 'transfers changed finances';end if;
 r:=public.solar_inventory('manage');if jsonb_array_length(r->'users')<>4 then raise exception 'access manager failed';end if;
 if has_function_privilege('authenticated','solar_private.inventory_v350(text,uuid,jsonb)','EXECUTE') then raise exception 'old generic permission bypass callable';end if;
end$$;
do $$declare delivery jsonb;begin
 for delivery in select value from jsonb_array_elements(public.solar_push_claim()) loop
  if delivery->'notification'->>'title'='WRONG_SOURCE' then raise exception 'wrong-source mobile push was claimed';end if;
  if delivery->'notification'->>'event' like 'stock_transfer_%' and delivery->'notification'->>'stockTransferId' is null then raise exception 'mobile push lost transfer routing id';end if;
 end loop;
end$$;
-- Weighted cost includes stock still owned by the company while it is reserved.
insert into suppliers(id,name) values(-351001,'Transfer Book Supplier');
do $$declare r jsonb;request uuid:=gen_random_uuid();main bigint:=solar_private.primary_warehouse();secondary bigint;begin
 select id into secondary from solar_private.warehouses where code='SAYADA';
 r:=public.solar_inventory('transfer',request,jsonb_build_object('fromId',main,'toId',secondary,'items',jsonb_build_array(jsonb_build_object('productId',-351001,'qty',2,'revision',(select revision from solar_private.warehouse_stocks where warehouse_id=main and product_id=-351001)))));
 perform public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','purchase','warehouseId',main,'party','Transfer Book Supplier','partyId',-351001,'mode','credit','marketRate',1660,'accountRevision',(select currency_revision from suppliers where id=-351001),'items','[{"id":-351001,"qty":10,"price":200}]'::jsonb));
 if abs((select cost from products where id=-351001)-133.333333)>0.000001 or(select qty from products where id=-351001)<>30 then raise exception 'reservation changed company weighted costing';end if;
 if(select (items->0->>'unitCost')::numeric from solar_private.stock_transfers where id=request)<>100 then raise exception 'later purchase changed frozen transfer cost';end if;
 perform public.solar_inventory('prepare_transfer',gen_random_uuid(),jsonb_build_object('id',request,'expectedRevision',0));
 if(select qty from solar_private.warehouse_stocks where product_id=-351001 and warehouse_id=secondary)<>2 or(select qty from products where id=-351001)<>30 then raise exception 'preparation changed total company quantity';end if;
end$$;
set constraints all immediate;
select 'PASS source-only preparation, directional permissions, reservation/receipt accounting, multi-line atomic replay, incoming isolation, notices, cancellation and reversal';
rollback;
