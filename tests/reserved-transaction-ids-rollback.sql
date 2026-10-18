\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,username,is_admin,user_type,permissions) values('00000000-0000-0000-0000-000000003480','Reserved ID Admin','reserved_test',true,'admin_staff','{}');
insert into customers(id,name,customer_type,owner_id)values(-348001,'Opening Balance Example','system','00000000-0000-0000-0000-000000003480'),(-348002,'Wholesale Example','wholesale','00000000-0000-0000-0000-000000003480');
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id)values(1792246234855192,'system_payment',-348001,'Opening Balance Example',-3707000,false,'opening_balance','00000000-0000-0000-0000-000000003480','00000000-0000-0000-0000-000000003480'),(1792246234855191,'customer_payment',-348002,'Wholesale Example',-200000,false,'opening_balance','00000000-0000-0000-0000-000000003480','00000000-0000-0000-0000-000000003480');
insert into solar_private.deleted_sales(invoice_id,invoice,items,deleted_by)values(1792246234855193,'{"kind":"sale"}','[]','00000000-0000-0000-0000-000000003480');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003480',true);
do $$declare a jsonb;r jsonb;payload jsonb;rid uuid:=gen_random_uuid();begin
 a:=public.solar_system_payment_context(-348001);payload:=jsonb_build_object('customerId',-348001,'invoiceId',null,'amount',3707000,'mode','payment','notes','بيد محمد','expectedToken',a->>'token');
 r:=public.solar_system_payment_save(rid,payload);if(r->>'id')::bigint<>1792246234855194 or(r->>'remaining')::numeric<>0 or(r->>'cashAfter')::numeric<>3707000 then raise exception 'reserved ID payment failed';end if;
 if public.solar_system_payment_save(rid,payload) is distinct from r then raise exception 'duplicate retry';end if;
 begin perform public.solar_system_payment_save(gen_random_uuid(),payload);raise exception 'stale account accepted';exception when sqlstate 'PT409' then null;end;
 a:=public.solar_customer_payment_context(-348002);r:=public.solar_customer_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-348002,'amount',200000,'mode','payment','notes','','expectedToken',a->>'token'));if(r->>'remaining')::numeric<>0 then raise exception 'wholesale posting';end if;
end $$;
reset role;
insert into solar_private.reset_record_ids(table_name,record_id)values('transactions',1792246234855200);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003480","mode":"capital_deposit","currency":"IQD","amount":1000,"note":"skip reserved reset ID"}');if(r->>'id')::bigint<>1792246234855201 then raise exception 'cash reset ID reused';end if;
end $$;
reset role;
do $$begin
 if(select count(*) from transactions where party_id=-348001 and payment_mode='payment')<>1 then raise exception 'duplicate financial effect';end if;
 begin insert into transactions(id,kind,total,cash)values(1792246234855193,'cash_income',1,true);raise exception 'deleted ID accepted';exception when sqlstate 'PT409' then null;end;
 if(select count(*) from solar_private.deleted_sales where invoice_id=1792246234855193)<>1 then raise exception 'deleted invoice history changed';end if;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='solar_private' and p.prokind='f' and pg_get_functiondef(p.oid)~'errcode[[:space:]]*=[[:space:]]*''40001''') then raise exception 'custom serialization error remains';end if;
 if has_function_privilege('authenticated','solar_private.next_transaction_id()','execute') then raise exception 'allocator exposed';end if;
 raise notice 'PASS exact deleted-highest-ID reproduction: full 3,707,000 payment, committed cash/zero customer balance, stable retry, stale conflicts fail without serialization retry, reset IDs skipped and deleted history guarded';
end $$;
rollback;
