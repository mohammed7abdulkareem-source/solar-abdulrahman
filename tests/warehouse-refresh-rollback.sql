\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,username,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000003450','Office Admin','office_test',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003451','Warehouse User','warehouse_test',false,'warehouse','{}'),
('00000000-0000-0000-0000-000000003452','Other Seller','other_test',false,'admin_staff','{"sale":true}'),
('00000000-0000-0000-0000-000000003453','Installer','installer_test',false,'installer','{}');
insert into public.solar_push_subscriptions(endpoint,user_id,p256dh,auth_key) values('https://fcm.googleapis.com/fake-warehouse','00000000-0000-0000-0000-000000003451','fixture','fixture'),('https://fcm.googleapis.com/fake-owner','00000000-0000-0000-0000-000000003450','fixture','fixture');
insert into customers(id,name,customer_type,owner_id) values(-345001,'Warehouse Customer','wholesale','00000000-0000-0000-0000-000000003450'),(-345002,'System Office Customer','system','00000000-0000-0000-0000-000000003450');
insert into products(id,code,name,qty,cost) values(-345001,'WH-FLOW','Warehouse Panel',10,100);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003450',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003450","mode":"capital_deposit","currency":"IQD","amount":500,"note":"office cash"}');
do $$declare r jsonb;s jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"credit","party":"Warehouse Customer","items":[{"id":-345001,"qty":1,"price":200}]}');perform set_config('wh.first',r->>'id',true);
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"credit","party":"Warehouse Customer","items":[{"id":-345001,"qty":2,"price":200}]}');perform set_config('wh.second',r->>'id',true);
 begin perform public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","party":"System Office Customer","expenses":123,"total":1000,"installerId":"00000000-0000-0000-0000-000000003453","customerAddress":"عنوان","items":[{"id":-345001,"qty":2,"price":0}]}');raise exception 'initial expenses accepted';exception when raise_exception then if sqlerrm='initial expenses accepted' then raise;end if;end;
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","party":"System Office Customer","expenses":0,"total":1000,"installerId":"00000000-0000-0000-0000-000000003453","customerAddress":"عنوان","items":[{"id":-345001,"qty":2,"price":0}]}');perform set_config('wh.system',r->>'id',true);
 begin perform public.solar_installation_action((r->>'id')::bigint,0,'close','{"amount":150}');raise exception 'close before stock preparation';exception when raise_exception then if sqlerrm='close before stock preparation' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003451',true);
do $$declare q jsonb;r jsonb;s jsonb;begin
 q:=public.solar_warehouse_orders();if(q->>'count')::integer<>3 or(q->'statusCounts'->>'pending')::integer<>3 then raise exception 'missing invoices';end if;
 if q::text ~ '"(cost|profit|price|total|cash)"' then raise exception 'financial fields in warehouse response';end if;
 if(select count(*) from solar_notifications where event='warehouse_new')<>3 then raise exception 'new notice missing';end if;
 r:=public.solar_warehouse_orders('@id:'||current_setting('wh.first'),'')->'rows'->0;
 perform public.solar_warehouse_action((r->>'id')::bigint,r->>'token','ready');
 q:=public.solar_warehouse_orders();if(q->>'count')::integer<>2 or(q->'statusCounts'->>'ready')::integer<>1 or(q->'statusCounts'->>'all')::integer<>3 then raise exception 'queue counters';end if;
 q:=public.solar_warehouse_orders('','ready');if(q->>'count')::integer<>1 then raise exception 'ready list';end if;
 q:=public.solar_warehouse_orders('','');if(q->>'count')::integer<>3 then raise exception 'all list';end if;
 r:=public.solar_warehouse_orders('@id:'||current_setting('wh.second'),'')->'rows'->0;
 perform public.solar_warehouse_action((r->>'id')::bigint,r->>'token','ready');
 r:=public.solar_warehouse_orders('@id:'||current_setting('wh.system'),'')->'rows'->0;
 perform public.solar_warehouse_action((r->>'id')::bigint,r->>'token','ready');
 q:=public.solar_warehouse_orders();if(q->>'count')::integer<>0 or(q->'statusCounts'->>'ready')::integer<>3 then raise exception 'empty pending hides ready history';end if;
 s:=public.solar_warehouse_statuses(array[current_setting('wh.first')::bigint,current_setting('wh.second')::bigint]);if jsonb_array_length(s)<>2 or s::text ~ '"(cost|profit|price|total)"' then raise exception 'safe statuses';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003452',true);
do $$begin if jsonb_array_length(public.solar_warehouse_statuses(array[current_setting('wh.first')::bigint]))<>0 then raise exception 'foreign status leak';end if;begin perform public.solar_warehouse_orders();raise exception 'unauthorized warehouse';exception when insufficient_privilege then null;end;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003450',true);
do $$declare jobs jsonb;j jsonb;begin
 jobs:=public.solar_installation_jobs();select x into j from jsonb_array_elements(jobs)x where x->>'id'=current_setting('wh.system');
 if j->>'warehouseStatus'<>'ready' or not(j->>'canManage')::boolean then raise exception 'office return state';end if;
 perform public.solar_installation_action((j->>'id')::bigint,(j->>'installationRevision')::bigint,'close','{"amount":150,"notes":"كامل المصاريف النهائية"}');
 begin perform public.solar_installation_action((j->>'id')::bigint,(j->>'installationRevision')::bigint,'close','{"amount":150}');raise exception 'duplicate closing';exception when serialization_failure then null;end;
end $$;
reset role;
do $$declare delivery jsonb;begin
 if(select qty from products where id=-345001)<>5 then raise exception 'preparation deducted stock twice';end if;
 if solar_private.cash_balance('00000000-0000-0000-0000-000000003450')<>350 then raise exception 'final expenses not paid once';end if;
 if not exists(select 1 from transactions where id=current_setting('wh.system')::bigint and expenses=0 and installation_expenses=150 and profit=650 and installation_status='closed' and installation_report='{}') then raise exception 'office final profit/expense';end if;
 if not exists(select 1 from solar_notifications where user_id='00000000-0000-0000-0000-000000003450' and job_id=current_setting('wh.system')::bigint and event='warehouse_ready') or not exists(select 1 from solar_notifications where job_id=current_setting('wh.system')::bigint and event='installation_closed') then raise exception 'office notice missing';end if;
 if not exists(select 1 from solar_private.push_deliveries d join solar_notifications n on n.id=d.notification_id where n.user_id='00000000-0000-0000-0000-000000003451' and n.event='warehouse_new') then raise exception 'warehouse push not queued';end if;
 for delivery in select * from jsonb_array_elements(public.solar_push_claim()) loop
  if delivery->'notification'->>'event'='warehouse_ready' and delivery->'notification'->>'jobId'=current_setting('wh.system') and delivery->'notification'->>'invoiceKind'<>'system' then raise exception 'office push deep link missing';end if;
 end loop;
 if has_function_privilege('anon','public.solar_warehouse_statuses(bigint[])','execute') then raise exception 'anonymous status access';end if;
 raise notice 'PASS pending/ready/all counts, both receipts, safe statuses, warehouse notifications and outbox, no initial system expense, office close after preparation without report, one cash payout, fixed stock/profit and scoped access';
end $$;
rollback;
