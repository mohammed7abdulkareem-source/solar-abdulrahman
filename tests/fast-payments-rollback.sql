\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,username,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000003460','Fast Admin','fast_admin',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003461','Fast Staff','fast_staff',false,'admin_staff','{"systemPayment":true,"customerPayment":true,"cash":true}'),
('00000000-0000-0000-0000-000000003462','Other Cashier','fast_other',false,'admin_staff','{"cash":true}');
insert into customers(id,name,customer_type,owner_id) values(-346001,'Fast System','system','00000000-0000-0000-0000-000000003461'),(-346002,'Fast Wholesale','wholesale','00000000-0000-0000-0000-000000003461');
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id) values(-346001,'system_payment',-346001,'Fast System',-3707000,false,'opening_balance','00000000-0000-0000-0000-000000003461','00000000-0000-0000-0000-000000003461'),(-346002,'customer_payment',-346002,'Fast Wholesale',-200000,false,'opening_balance','00000000-0000-0000-0000-000000003461','00000000-0000-0000-0000-000000003461');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003461',true);
set local role authenticated;
do $$declare a jsonb;r jsonb;payload jsonb;rid uuid:=gen_random_uuid();begin
 a:=public.solar_system_payment_context(-346001);
 payload:=jsonb_build_object('customerId',-346001,'invoiceId',null,'amount',3707000,'mode','payment','notes','','expectedToken',a->>'token');
 r:=public.solar_system_payment_save(rid,payload);
 if r->'accountContext' is distinct from public.solar_system_payment_context(-346001) or(r->'accountContext'->>'balance')::numeric<>0 or(r->'accountContext'->>'cashBalance')::numeric<>3707000 then raise exception 'system confirmation context';end if;
 if public.solar_system_payment_save(rid,payload) is distinct from r then raise exception 'receipt replay changed';end if;
 a:=public.solar_customer_payment_context(-346002);
 r:=public.solar_customer_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-346002,'amount',50000,'mode','payment','notes','','expectedToken',a->>'token'));
 if r->'accountContext' is distinct from public.solar_customer_payment_context(-346002) or(r->'accountContext'->>'balance')::numeric<>150000 then raise exception 'wholesale confirmation context';end if;
 a:=r->'accountContext';r:=public.solar_customer_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-346002,'amount',150000,'mode','payment','notes','','expectedToken',a->>'token'));
 if(r->'accountContext'->>'balance')::numeric<>0 then raise exception 'next receipt token not ready';end if;
 a:=public.solar_cash_workspace('{}');if jsonb_array_length(a->'owners')<>1 or(a->'owners'->0->>'IQD')::numeric<>3907000 then raise exception 'own cash or privacy';end if;
 begin perform public.solar_cash_workspace('{"ownerId":"00000000-0000-0000-0000-000000003460"}');raise exception 'foreign cash visible';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003460',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003460","mode":"capital_deposit","currency":"USD","amount":1000.25,"rate":1660,"note":"USD wallet fixture"}');
do $$declare a jsonb;r jsonb;row jsonb;begin
 a:=public.solar_cash_workspace('{"from":"2099-01-01","ownerId":"00000000-0000-0000-0000-000000003460"}');
 if jsonb_array_length(a->'owners')<>3 then raise exception 'admin cash list missing';end if;
 select x into row from jsonb_array_elements(a->'owners')x where x->>'id'='00000000-0000-0000-0000-000000003461';if(row->>'IQD')::numeric<>3907000 then raise exception 'current owner balance affected by filters';end if;
 select x into row from jsonb_array_elements(a->'owners')x where x->>'id'='00000000-0000-0000-0000-000000003460';if(row->>'USD')::numeric<>1000.25 or(row->>'IQD')::numeric<>0 then raise exception 'currencies mixed';end if;
end $$;
reset role;
do $$begin if(select count(*) from transactions where payment_mode='payment' and kind='system_payment')<>1 then raise exception 'duplicate payment';end if;raise notice 'PASS committed contexts, immediate next token, exactly-once retry, full opening balance, current per-user cash and USD cents independent of filters, scoped access';end $$;
rollback;
