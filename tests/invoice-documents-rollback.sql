\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,permissions,user_type) values
('00000000-0000-0000-0000-000000003480','Invoice Admin',true,'{}','admin_staff'),
('00000000-0000-0000-0000-000000003481','Warehouse',false,'{}','warehouse');
insert into customers(id,name,customer_type,owner_id) values(-348001,'Invoice Customer','wholesale','00000000-0000-0000-0000-000000003480'),(-348002,'Other Account','wholesale','00000000-0000-0000-0000-000000003480');
insert into products(id,code,name,qty,cost) values(-348001,'INV-DOC','بطارية ضمان',100,50000);
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_at,created_by,cashbox_user_id) values
(-348010,'customer_payment',-348001,'Invoice Customer',-2000000,false,'opening_balance',now()-interval '10 days','00000000-0000-0000-0000-000000003480','00000000-0000-0000-0000-000000003480'),
(-348011,'sale',-348001,'Invoice Customer',500000,false,'credit',now()-interval '9 days','00000000-0000-0000-0000-000000003480','00000000-0000-0000-0000-000000003480'),
(-348012,'sale',-348001,'Invoice Customer',400000,true,'cash',now()-interval '8 days','00000000-0000-0000-0000-000000003480','00000000-0000-0000-0000-000000003480'),
(-348013,'customer_payment',-348001,'Invoice Customer',300000,true,'cash',now()-interval '7 days','00000000-0000-0000-0000-000000003480','00000000-0000-0000-0000-000000003480'),
(-348014,'customer_payment',-348001,'Invoice Customer',-50000,false,'credit',now()-interval '6 days','00000000-0000-0000-0000-000000003480','00000000-0000-0000-0000-000000003480'),
(-348015,'customer_payment',-348002,'Other Account',9999999,true,'cash',now()-interval '1 day','00000000-0000-0000-0000-000000003480','00000000-0000-0000-0000-000000003480');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003480',true);
do $$declare r jsonb;p jsonb;a jsonb;q jsonb;begin
 p:='{"kind":"sale","mode":"credit","party":"Invoice Customer","sourceCurrency":"IQD","expenses":0,"items":[{"id":-348001,"qty":1,"price":150000}],"warranty":{"enabled":true,"items":[{"id":-348001,"duration":2,"unit":"years"}],"maintenance":{"duration":6,"unit":"months"}}}';
 r:=public.solar_invoice_save('00000000-0000-0000-0000-000000034801',p);a:=r->'invoiceAccount';
 if (a->>'previousBalance')::numeric<>2250000 or(a->>'invoiceTotal')::numeric<>150000 or(a->>'paidNow')::numeric<>0 or(a->>'balanceAfter')::numeric<>2400000 then raise exception 'wrong invoice account %',a;end if;
 if(a->'lastPayment'->>'amount')::numeric<>300000 or(a->'lastPayment'->>'id')::bigint<>-348013 then raise exception 'wrong previous cash payment %',a;end if;
 if public.solar_invoice_save('00000000-0000-0000-0000-000000034801',p)<>r then raise exception 'replay changed snapshot';end if;
 if r->>'warehouseQrToken' is null or r->>'warehouseQrToken'=r->>'warrantyToken' then raise exception 'warehouse QR isolation';end if;
 q:=public.solar_warranty_verify((r->>'warehouseQrToken')::uuid);
 if q->>'copy'<>'warehouse' or q ? 'total' or q ? 'currency' or q ? 'invoiceAccount' or q::text like '%"price"%' or q::text like '%'||(r->>'warrantyToken')||'%' then raise exception 'warehouse public financial leak %',q;end if;
 if not(q->'items'->0->'status'->>'active')::boolean or q->'items'->0->>'name'<>'بطارية ضمان' then raise exception 'warehouse warranty/details missing';end if;
 q:=public.solar_warranty_verify((r->>'warrantyToken')::uuid);if(q->>'total')::numeric<>150000 then raise exception 'customer certificate lost price';end if;
 begin update transactions set invoice_account='{}' where id=(r->>'id')::bigint;raise exception 'snapshot tamper accepted';exception when insufficient_privilege then null;end;
 begin update transactions set warehouse_qr_token=gen_random_uuid() where id=(r->>'id')::bigint;raise exception 'token tamper accepted';exception when insufficient_privilege then null;end;
 perform set_config('test.invoice_id',r->>'id',true);perform set_config('test.invoice_snapshot',a::text,true);perform set_config('test.invoice_payload',p::text,true);perform set_config('test.invoice_result',r::text,true);
end $$;
reset role;
-- Later receipts, removal/edit of an earlier receipt do not rewrite printed history.
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_at,created_by,cashbox_user_id) values(-348016,'customer_payment',-348001,'Invoice Customer',100000,true,'cash',now()+interval '1 minute','00000000-0000-0000-0000-000000003480','00000000-0000-0000-0000-000000003480');
update transactions set total=250000 where id=-348013;
delete from transactions where id=-348016;
do $$begin if(select invoice_account from transactions where id=current_setting('test.invoice_id')::bigint)<>current_setting('test.invoice_snapshot')::jsonb then raise exception 'later activity rewrote issued snapshot';end if;end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003480',true);
do $$declare r jsonb;a jsonb;p jsonb;begin
 r:=current_setting('test.invoice_result')::jsonb;p:=current_setting('test.invoice_payload')::jsonb;
 r:=public.solar_invoice_save(gen_random_uuid(),p||jsonb_build_object('mode','cash','invoiceId',r->'id','expectedRevision',r->'pricingRevision','expectedWarrantyRevision',r->'warrantyRevision'));
 a:=r->'invoiceAccount';if(a->>'previousBalance')::numeric<>2250000 or(a->>'paidNow')::numeric<>150000 or(a->>'balanceAfter')::numeric<>2250000 or(a->'lastPayment'->>'amount')::numeric<>300000 then raise exception 'cash edit broke fixed prior context %',a;end if;
end $$;
reset role;
create temporary table issued_before_rename as select invoice_account data from transactions where id=current_setting('test.invoice_id')::bigint;
update transactions set party_name='Invoice Customer Renamed' where id=current_setting('test.invoice_id')::bigint;
do $$begin if (select invoice_account from transactions where id=current_setting('test.invoice_id')::bigint)<>(select data from issued_before_rename) then raise exception 'customer rename rewrote fixed snapshot';end if;end $$;
update transactions set party_name='Invoice Customer' where id=current_setting('test.invoice_id')::bigint;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003481',true);
do $$declare q jsonb;begin
 q:=public.solar_warehouse_orders('Invoice Customer','',0);
 if q::text like '%invoice_account%' or q::text like '%invoiceAccount%' or q::text like '%"total"%' or q::text like '%warranty_token%' or q::text like '%"price"%' then raise exception 'warehouse role financial leak';end if;
 if not exists(select 1 from jsonb_array_elements(q->'rows')r where (r->>'id')::bigint=current_setting('test.invoice_id')::bigint and r->>'warehouseQrToken' is not null and (r->'warranty'->>'enabled')::boolean) then raise exception 'warehouse document lacks verification data';end if;
end $$;
reset role;
update transactions set party_id=-348002,party_name='Other Account' where id=current_setting('test.invoice_id')::bigint;
do $$declare a jsonb;begin select invoice_account into a from transactions where id=current_setting('test.invoice_id')::bigint;if(a->>'customerId')::bigint<>-348002 or(a->>'previousBalance')::numeric<>-9999999 or(a->'lastPayment'->>'amount')::numeric<>9999999 then raise exception 'account reassignment retained another customer context %',a;end if;end $$;
do $$begin raise notice 'PASS issue-time previous account, real prior payment, excluded opening/additions/other accounts, atomic replay, fixed history after later edits, cash mode edit, protected metadata, separate safe warehouse QR';end $$;
rollback;
