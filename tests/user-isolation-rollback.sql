\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,username,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000003590','Isolation Admin','isolation_admin',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003591','Seller A','seller_a',false,'admin_staff','{"sale":true,"system":true,"purchase":true,"customers":true,"customerStatement":true,"customerPayment":true,"systemPayment":true,"supplierPayment":true,"supplierStatement":true,"cash":true,"profit":true,"profitSettlement":true,"salesHistory":true,"warehouse":true,"stockMovement":true,"installationsAll":true,"salesDeleteAll":true,"ownSales":false,"ownPayments":false}'),
('00000000-0000-0000-0000-000000003592','Seller B','seller_b',false,'admin_staff','{"sale":true,"system":true,"salesHistory":true,"warehouse":true,"stockMovement":true}'),
('00000000-0000-0000-0000-000000003593','Warehouse','isolation_warehouse',false,'warehouse','{}'),
('00000000-0000-0000-0000-000000003594','Assigned Engineer','isolation_engineer',false,'installer','{}');
insert into solar_private.warehouse_access(user_id,all_warehouses,warehouse_ids) values('00000000-0000-0000-0000-000000003593',true,'{}');
insert into customers(id,name,customer_type,owner_id) values(-359001,'PRIVATE_A_CUSTOMER','wholesale','00000000-0000-0000-0000-000000003591'),(-359002,'PRIVATE_B_CUSTOMER','system','00000000-0000-0000-0000-000000003592');
insert into products(id,code,name,qty,cost) values(-359001,'SCOPE-SHARED','Shared inventory material',100,100);
insert into suppliers(id,name) values(-359001,'Shared supplier');
insert into transactions(id,kind,total,cash,created_by,cashbox_user_id) values(-359026,'cash_income',1000,true,'00000000-0000-0000-0000-000000003592','00000000-0000-0000-0000-000000003592');
insert into transactions(id,kind,party_type,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,installer_id,installation_status,warehouse_status) values
(-359011,'sale','customer',-359001,'PRIVATE_A_CUSTOMER',200,false,'credit','00000000-0000-0000-0000-000000003591','00000000-0000-0000-0000-000000003591',null,'none','pending'),
(-359012,'system','customer',-359001,'PRIVATE_A_CUSTOMER',500,false,'credit','00000000-0000-0000-0000-000000003591','00000000-0000-0000-0000-000000003591','00000000-0000-0000-0000-000000003594','pending','ready'),
(-359021,'sale','customer',-359002,'PRIVATE_B_CUSTOMER',800,false,'credit','00000000-0000-0000-0000-000000003592','00000000-0000-0000-0000-000000003592',null,'none','pending'),
(-359022,'system','customer',-359002,'PRIVATE_B_CUSTOMER',1000,false,'credit','00000000-0000-0000-0000-000000003592','00000000-0000-0000-0000-000000003592','00000000-0000-0000-0000-000000003594','pending','pending'),
(-359023,'sale','customer',-359002,'PRIVATE_B_CUSTOMER',900,false,'credit','00000000-0000-0000-0000-000000003592','00000000-0000-0000-0000-000000003591',null,'none','pending'),
(-359024,'purchase','supplier',-359001,'Shared supplier',300,false,'credit','00000000-0000-0000-0000-000000003592','00000000-0000-0000-0000-000000003592',null,'none','pending'),
(-359025,'supplier_payment','supplier',-359001,'Shared supplier',50,true,'cash','00000000-0000-0000-0000-000000003592','00000000-0000-0000-0000-000000003592',null,'none','pending');
insert into transaction_items(transaction_id,product_id,product_name,qty,price,cost) select id,-359001,case when created_by='00000000-0000-0000-0000-000000003591' then 'PRIVATE_A_LINE' else 'PRIVATE_B_LINE' end,1,total,100 from transactions where id in(-359011,-359012,-359021,-359022,-359023,-359024);
insert into solar_private.stock_adjustments(id,product_id,old_qty,actual_qty,note,actor_id) values(-359031,-359001,100,101,'PRIVATE_A_ADJUSTMENT','00000000-0000-0000-0000-000000003591'),(-359032,-359001,101,102,'PRIVATE_B_ADJUSTMENT','00000000-0000-0000-0000-000000003592');
-- Reproduce an already delivered, old cross-user notification.
insert into solar_notifications(user_id,job_id,event,title,body) values('00000000-0000-0000-0000-000000003591',-359021,'warehouse_new','OLD_CROSS_NOTICE','PRIVATE_B_CUSTOMER');
-- Even forged/stale global flags must not broaden server-side scopes.
alter table profiles disable trigger solar_zz_own_user_scope;
update profiles set permissions=permissions||'{"installationsAll":true,"salesDeleteAll":true,"ownSales":false,"ownPayments":false}' where id='00000000-0000-0000-0000-000000003591';
alter table profiles enable trigger solar_zz_own_user_scope;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003591',true);
do $$declare r jsonb;begin
 if(select count(*) from transactions where id in(-359011,-359012,-359021,-359022,-359023,-359024,-359025))<>2 then raise exception 'raw transaction RLS leaked foreign data';end if;
 if exists(select 1 from transaction_items where product_name='PRIVATE_B_LINE') then raise exception 'raw line RLS leaked foreign data';end if;
 if exists(select 1 from customers where id=-359002) then raise exception 'raw customer RLS leak';end if;
 r:=public.solar_sales_history();if(r->>'count')::integer<>2 or r::text like '%PRIVATE_B%' then raise exception 'archive leak %',r;end if;
 r:=public.solar_warehouse_orders('','',0);if(r->>'count')::integer<>2 or(r->'statusCounts'->>'all')::integer<>2 or r::text like '%PRIVATE_B%' then raise exception 'warehouse all/counts leak %',r;end if;
 if(public.solar_warehouse_orders('@id:-359021','',0)->>'count')::integer<>0 then raise exception 'known invoice ID bypass';end if;
 r:=public.solar_warehouse_statuses(array[-359011,-359012,-359021,-359022,-359023]);if jsonb_array_length(r)<>2 then raise exception 'foreign status leak';end if;
 r:=public.solar_stock_movements();if jsonb_array_length(r)<>3 or r::text like '%PRIVATE_B%' then raise exception 'movement/adjustment leak %',r;end if;
 r:=public.solar_installation_jobs();if jsonb_array_length(r)<>1 or r::text like '%PRIVATE_B%' then raise exception 'global installation flag leak %',r;end if;
 if exists(select 1 from solar_notifications where title='OLD_CROSS_NOTICE' or body like '%PRIVATE_B%') then raise exception 'old cross-user notification visible';end if;
 if not exists(select 1 from solar_notifications where job_id=-359011) then raise exception 'own notification missing';end if;
 begin perform public.solar_warehouse_action(-359021,'forged','ready');raise exception 'foreign warehouse edit';exception when insufficient_privilege then null;end;
 begin perform public.solar_warehouse_action(-359021,'forged','save','[]','bad');raise exception 'foreign warehouse material edit';exception when insufficient_privilege then null;end;
 begin perform public.solar_installation_action(-359022,0,'close','{"amount":0}');raise exception 'foreign closing';exception when insufficient_privilege then null;end;
 begin perform public.solar_installation_action(-359022,0,'reopen');raise exception 'foreign reopen';exception when insufficient_privilege then null;end;
 begin perform public.solar_sale_delete_preview(-359021);raise exception 'global delete preview leak';exception when insufficient_privilege then null;end;
 begin perform public.solar_sale_delete(-359021,'forged');raise exception 'global deletion allowed';exception when insufficient_privilege then null;end;
 begin perform public.solar_warranty_manage('get',null,'{"id":-359021}');raise exception 'foreign warranty details';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_statement(-359002);raise exception 'foreign customer statement';exception when insufficient_privilege then null;end;
 begin perform public.solar_system_payment_context(-359002);raise exception 'foreign payment customer';exception when insufficient_privilege then null;end;
 begin perform public.solar_cash_workspace('{"ownerId":"00000000-0000-0000-0000-000000003592"}');raise exception 'foreign cashbox';exception when insufficient_privilege then null;end;
 begin perform public.solar_profit_workspace('overview',null,'{"ownerId":"00000000-0000-0000-0000-000000003592"}');raise exception 'foreign profit';exception when insufficient_privilege then null;end;
 begin perform public.solar_supplier_payment_get(-359025);raise exception 'foreign supplier receipt';exception when insufficient_privilege then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","invoiceId":-359023,"expectedRevision":0,"mode":"credit","party":"PRIVATE_A_CUSTOMER","items":[{"id":-359001,"qty":1,"price":200}]}');raise exception 'cashbox alias bypassed invoice creator';exception when insufficient_privilege then null;end;
 if not solar_private.can_close_installation(auth.uid()) or solar_private.can_close_installation('00000000-0000-0000-0000-000000003592') or solar_private.can_delete_sale('00000000-0000-0000-0000-000000003592') then raise exception 'global scope helper bypass';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003592',true);
do $$declare r jsonb;begin
 r:=public.solar_sales_history();if(r->>'count')::integer<>3 or r::text like '%PRIVATE_A%' then raise exception 'reverse archive isolation';end if;
 r:=public.solar_warehouse_orders('','',0);if(r->>'count')::integer<>3 or r::text like '%PRIVATE_A%' then raise exception 'reverse warehouse isolation';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003593',true);
do $$declare r jsonb;begin
 if exists(select 1 from transactions) or exists(select 1 from transaction_items) then raise exception 'warehouse raw financial tables';end if;
 r:=public.solar_warehouse_orders('PRIVATE_','',0);if(r->>'count')::integer<>5 or r::text ~ '"(total|price|cost|profit|invoiceAccount)"' then raise exception 'dedicated warehouse lost redacted fulfilment';end if;
 r:=public.solar_stock_movements();if jsonb_array_length(r)<>8 then raise exception 'dedicated stock movement count';end if;
 begin perform public.solar_sales_history();raise exception 'warehouse financial archive';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003594',true);
do $$declare r jsonb;begin
 r:=public.solar_installation_jobs();if jsonb_array_length(r)<>2 or r::text ~ '"(total|price|cost|profit|cash)"' then raise exception 'engineer assignment/redaction';end if;
 if exists(select 1 from transactions) then raise exception 'engineer raw receipts';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003590',true);
do $$declare r jsonb;begin
 r:=public.solar_sales_history();if(r->>'count')::integer<>5 then raise exception 'admin archive';end if;
 r:=public.solar_warehouse_orders('PRIVATE_','',0);if(r->>'count')::integer<>5 then raise exception 'admin warehouse';end if;
 if(select count(*) from transactions where id in(-359011,-359012,-359021,-359022,-359023,-359024,-359025))<>7 then raise exception 'admin raw data';end if;
 if jsonb_array_length(public.solar_installation_jobs())<>2 or not solar_private.can_close_installation('00000000-0000-0000-0000-000000003592') then raise exception 'admin oversight';end if;
end $$;
reset role;
update profiles set permissions=permissions where id='00000000-0000-0000-0000-000000003591';
do $$declare p jsonb;begin
 select permissions into p from profiles where id='00000000-0000-0000-0000-000000003591';if p->>'installationsAll'<>'false' or p->>'salesDeleteAll'<>'false' or p->>'ownSales'<>'true' or p->>'ownPayments'<>'true' or p->>'installations'<>'true' or p->>'salesDeleteOwn'<>'true' then raise exception 'profile normalization';end if;
 -- No future cross-user push or notification can be created by warehouse writers.
 if exists(select 1 from solar_notifications where user_id='00000000-0000-0000-0000-000000003591' and job_id=-359022) then raise exception 'new foreign warehouse notification';end if;
 raise notice 'PASS strict two-way staff isolation: raw RLS, archive, warehouse counters/search/actions/status, stock and adjustments, notifications, installation/delete/warranty IDOR, cash/profit/customer/supplier denial; admin and redacted operational roles preserved';
end $$;
rollback;
