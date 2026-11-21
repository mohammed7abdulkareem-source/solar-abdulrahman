\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,display_name,is_admin,user_type,permissions) values
 ('00000000-0000-0000-0000-000000421601','إدارة الاختبار',true,'admin_staff','{}'),
 ('00000000-0000-0000-0000-000000421602','بائع الاختبار',false,'admin_staff','{"sale":true,"customerStatement":true,"salesHistory":false}'),
 ('00000000-0000-0000-0000-000000421603','بائع آخر',false,'admin_staff','{"sale":true,"customerStatement":true}'),
 ('00000000-0000-0000-0000-000000421604','مهندس الاختبار',false,'installer','{}');
insert into public.products(id,code,name,qty,cost) values(-421600,'STATEMENT-EDIT','بطارية اختبار',20,1000);
-- Simulate two retained pre-guard customer records.
alter table public.customers disable trigger solar_customer_guard;
insert into public.customers(id,name,customer_type,owner_id) values
 (-421601,'اسم متشابه للاختبار','wholesale','00000000-0000-0000-0000-000000421602'),
 (-421602,'اسم متشابه للاختبار','wholesale','00000000-0000-0000-0000-000000421603');
alter table public.customers enable trigger solar_customer_guard;
insert into customers(id,name,customer_type,owner_id) values(-421603,'زبون منظومة للاختبار','system','00000000-0000-0000-0000-000000421602');
update solar_private.wholesale_pricing_control set enabled=false where id;
set local role authenticated;
do $$declare d jsonb; t jsonb; req jsonb; sale_id bigint; begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000421602',true);
 req:='{"kind":"sale","mode":"credit","party":"اسم متشابه للاختبار","items":[{"id":-421600,"qty":2,"price":2000}]}'::jsonb;
 t:=public.solar_invoice_save(gen_random_uuid(),req);sale_id:=(t->>'id')::bigint;
 perform set_config('test.statement_sale_id',sale_id::text,true);
 d:=public.solar_statement_sale_for_edit(-421601,sale_id);
 assert (d->>'id')::bigint=sale_id and (d->'items'->0->>'cost')::numeric=1000 and d ? 'installation_revision','Missing original editor data';
 assert (d->>'party_id')::bigint=-421601 and d->>'created_by'='00000000-0000-0000-0000-000000421602','Incorrect identity';
 -- Pick the original customer's stable ID even if the administrator can see an older sorting duplicate.
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000421601',true);
 req:=req||jsonb_build_object('invoiceId',sale_id,'expectedRevision',(d->>'pricing_revision')::integer,'warehouseId',d->'warehouse_id','saleCustomerId',-421601,'notes','ملاحظة مصححة','items','[{"id":-421600,"qty":3,"price":2000}]'::jsonb);
 perform public.solar_invoice_save(gen_random_uuid(),req);
 assert exists(select 1 from public.transactions where id=sale_id and party_id=-421601 and total=6000 and profit=3000 and notes='ملاحظة مصححة'),'Sale or customer mismatch';
 assert exists(select 1 from public.products where id=-421600 and qty=17),'Stock mismatch';
 assert (public.solar_customer_movement(-421601,sale_id)->'movement'->>'balance')::numeric=6000,'Statement did not change';
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000421603',true);
 begin d:=public.solar_statement_sale_for_edit(-421602,sale_id);assert d is null,'Another account could open sale';exception when insufficient_privilege then null;end;
end $$;
reset role;
update public.profiles set permissions='{"salesHistory":true,"customerStatement":true}' where id='00000000-0000-0000-0000-000000421602';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000421602',true);
do $$begin
 assert public.solar_customer_movement(-421601,current_setting('test.statement_sale_id')::bigint)->>'type'='invoice';
 assert public.solar_statement_sale_for_edit(-421601,current_setting('test.statement_sale_id')::bigint) is null,'Read-only actor could access editor data';
end$$;
reset role;
update public.profiles set permissions='{"customerStatement":true,"system":true,"salesHistory":false}' where id='00000000-0000-0000-0000-000000421602';
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","party":"زبون منظومة للاختبار","total":5000,"installerId":"00000000-0000-0000-0000-000000421604","customerAddress":"عنوان التنصيب","items":[{"id":-421600,"qty":1,"price":0}]}');
 perform set_config('test.statement_system_id',r->>'id',true);
end$$;
reset role;
-- Legacy accounts use unambiguous customer names even when no party_id was stored.
update public.transactions set party_id=null,installation_revision=4 where id=current_setting('test.statement_system_id')::bigint;
set local role authenticated;
do $$declare d jsonb;begin
 d:=public.solar_statement_sale_for_edit(-421603,current_setting('test.statement_system_id')::bigint);
 assert d->>'kind'='system' and (d->>'installation_revision')::integer=4 and (d->>'party_id')::bigint=-421603 and d->>'installer_id'='00000000-0000-0000-0000-000000421604','Legacy system edit lost account or installation version';
 assert public.solar_statement_sale_for_edit(-421601,current_setting('test.statement_sale_id')::bigint) is null,'System-only grant exposed wholesale sale editor';
end$$;
rollback;
