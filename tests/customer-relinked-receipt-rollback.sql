-- An actual, authorized system invoice correction after an admin handoff.
\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,display_name,is_admin,user_type,permissions) values
 ('00000000-0000-0000-0000-000000422701','مدير',true,'admin_staff','{}'),
 ('00000000-0000-0000-0000-000000422702','مسؤول الفاتورة',false,'admin_staff','{"system":true,"installations":true,"customers":true,"customerStatement":true}'),
 ('00000000-0000-0000-0000-000000422703','مسؤول الزبون',false,'admin_staff','{"system":true,"installations":true,"customers":true,"customerStatement":true}'),
 ('00000000-0000-0000-0000-000000422704','مهندس',false,'installer','{}');
insert into public.customers(id,name,customer_type,owner_id) values
 (-422701,'اختبار عميل الوصل القديم','system','00000000-0000-0000-0000-000000422702'),
 (-422702,'اختبار عميل الوصل الصحيح','system','00000000-0000-0000-0000-000000422702');
insert into public.products(id,code,name,qty,cost) values(-422701,'RELINK4227','بطارية اختبار الربط',10,500);
create temp table original(request_id uuid default gen_random_uuid(),payload jsonb,invoice_id bigint,transfer_id uuid default gen_random_uuid(),transfer_args jsonb);
grant select,insert,update on original to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422702',true);
insert into original(payload) values('{"kind":"system","mode":"credit","party":"اختبار عميل الوصل القديم","saleCustomerId":-422701,"total":10000,"installerId":"00000000-0000-0000-0000-000000422704","customerAddress":"موقع اختبار","items":[{"id":-422701,"qty":2,"price":0}]}');
update original set invoice_id=(public.solar_invoice_save(request_id,payload)->>'id')::bigint;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422701',true);
update original set transfer_args=jsonb_build_object('id',-422701,'ownerId','00000000-0000-0000-0000-000000422703',
 'token',public.solar_customer_get(-422701)->>'token','receiptToken',public.solar_customer_transfer_receipts(-422701)->>'receiptToken','receiptIds',jsonb_build_array(invoice_id));
select public.solar_customer_save('transfer_owner',transfer_id,transfer_args)->>'receiptCount' from original;
reset role;
-- A legacy writer may record the same customer by its unique name only.
update public.transactions set party_id=null where id=(select invoice_id from original);
do $$begin assert exists(select 1 from solar_private.customer_receipt_responsibility where transaction_id=(select invoice_id from original)),'Unique name normalization broke delegation';end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422701',true);
select public.solar_customer_save('rename',gen_random_uuid(),jsonb_build_object('id',-422701,'name','الاسم المضبوط للعميل القديم','token',public.solar_customer_get(-422701)->>'token'))->>'name';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422703',true);
do $$declare receipt_id bigint:=(select invoice_id from original);begin
 assert exists(select 1 from jsonb_array_elements(public.solar_installation_jobs()) j where j->>'id'=receipt_id::text),'Account rename broke delegated installation file';
 assert exists(select 1 from jsonb_array_elements(public.solar_sales_history_by_user(auth.uid(),'','system',null,null,'',0,true)->'rows') j where j->>'id'=receipt_id::text and j->>'assignedReceipt'='true'),'Missing before correction';
end$$;
reset role;
create temp table finances as
 select total,cost,profit,created_by,cashbox_user_id,(select qty from public.products where id=-422701) as stock,
  solar_private.cash_balance(created_by) as cash from public.transactions where id=(select invoice_id from original);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422702',true);
-- Same quantity, same value, same issuer. Only the invoiced customer changes.
do $$declare d record; t public.transactions; amended jsonb;begin
 select * into d from original;
 select * into t from public.transactions where id=d.invoice_id;
 amended:=d.payload||jsonb_build_object('invoiceId',d.invoice_id,'saleCustomerId',-422702,'party','اختبار عميل الوصل الصحيح',
  'expectedRevision',t.pricing_revision,'expectedInstallationRevision',t.installation_revision,'warehouseId',t.warehouse_id);
 assert (public.solar_invoice_save(gen_random_uuid(),amended)->>'id')::bigint=d.invoice_id;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422703',true);
do $$declare receipt_id bigint:=(select invoice_id from original);begin
 assert not exists(select 1 from jsonb_array_elements(public.solar_installation_jobs()) j where j->>'id'=receipt_id::text),'Previous delegate still sees the corrected customer installation';
 assert not exists(select 1 from jsonb_array_elements(public.solar_sales_history_by_user(auth.uid(),'','system',null,null,'',0,true)->'rows') j where j->>'id'=receipt_id::text),'Previous delegate still sees a different customer receipt';
 assert (public.solar_customer_statement(-422701)->>'balance')::numeric=0;
 begin perform public.solar_customer_movement(-422701,receipt_id);raise exception 'Old customer still contains corrected invoice';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_movement(-422702,receipt_id);raise exception 'Former delegate opened correct customer';exception when insufficient_privilege then null;end;
 begin perform public.solar_installation_action(receipt_id,0,'close','{"amount":5}');raise exception 'Former delegate can modify costs';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422701',true);
do $$begin
 begin perform public.solar_customer_save('transfer_owner',transfer_id,transfer_args) from original;raise exception 'Obsolete transfer replayed after customer changed';exception when sqlstate 'PT409' then null;end;
 assert (public.solar_customer_statement(-422702)->>'balance')::numeric=10000;
end$$;
reset role;
do $$declare receipt_id bigint:=(select invoice_id from original);begin
 assert exists(select 1 from public.transactions t cross join finances f
  where t.id=receipt_id and t.party_id=-422702 and (t.total,t.cost,t.profit,t.created_by,t.cashbox_user_id) is not distinct from(f.total,f.cost,f.profit,f.created_by,f.cashbox_user_id)
  and solar_private.cash_balance(t.created_by)=f.cash and (select qty from public.products where public.products.id=-422701)=f.stock),'Correction changed ownership or financial figures';
 assert not exists(select 1 from solar_private.customer_receipt_responsibility r where r.transaction_id=receipt_id);
 assert exists(select 1 from solar_private.relinked_receipt_assignments a cross join original o where
  a.transaction_id=o.invoice_id and a.assignment_request_id=o.transfer_id and a.assignment->>'customer_id'='-422701' and a.assignment->>'owner_id'='00000000-0000-0000-0000-000000422703'
  and a.new_customer_id=-422702 and a.actor_id='00000000-0000-0000-0000-000000422702'),'Revoked assignment audit lost its parties';
 assert not has_table_privilege('authenticated','solar_private.relinked_receipt_assignments','select,insert,update,delete')
  and not has_function_privilege('authenticated','solar_private.revoke_relinked_receipt(bigint,bigint)','execute');
end$$;
set constraints all immediate;
rollback;
