\set ON_ERROR_STOP on
begin;
-- Use a single account first as a seller, then with the legacy quote-only grants.
insert into public.profiles(id,display_name,is_admin,user_type,permissions,phone) values
('00000000-0000-0000-0000-000000414101','مستخدم فحص الصلاحيات',false,'admin_staff','{"sale":true,"system":true,"deletionRequests":true}','07700000011'),
('00000000-0000-0000-0000-000000414102','مسؤول فحص الصلاحيات',true,'admin_staff','{}','07700000012'),
('00000000-0000-0000-0000-000000414103','مهندس فحص الصلاحيات',false,'installer','{}','07700000013');
insert into public.products(id,code,name,category,qty,cost) values
(414101,'PERM-PANEL','لوح 600 واط','ألواح',80,100000),
(414102,'PERM-INVERTER','انفيرتر 8 كيلو','انفيرتر',50,500000),
(414103,'PERM-BATTERY','بطارية 15 كيلو','بطارية',40,2000000);
insert into public.customers(id,name,customer_type,owner_id) values
(-414101,'ROLE-QW WHOLESALE','wholesale','00000000-0000-0000-0000-000000414101'),
(-414102,'ROLE-QW SYSTEM','system','00000000-0000-0000-0000-000000414101');
select set_config('test.qw.seller','00000000-0000-0000-0000-000000414101',true);
select set_config('test.qw.admin','00000000-0000-0000-0000-000000414102',true);
select set_config('request.jwt.claim.sub',current_setting('test.qw.seller'),true);
create function pg_temp.denied(statement text) returns void language plpgsql security invoker as $$
begin
 begin execute statement;
 exception when insufficient_privilege then return;
 end;
 raise exception 'Expected permission denial for %',statement;
end $$;
create function pg_temp.assert_catalog(full_access boolean) returns void language plpgsql security invoker as $$
declare item jsonb; allowed text[]:=array['id','code','name','brand','brand_id','brands','category'];
begin
 select p into item from jsonb_array_elements(public.solar_inventory('catalog')) p where p->>'id'='414101';
 assert item is not null and item->>'name'='لوح 600 واط','Quote catalogue lost an available material';
 if full_access then allowed:=array_append(allowed,'cost');assert (item->>'cost')::numeric=100000,'Full quote missed material cost';end if;
 assert item-allowed='{}'::jsonb,'Quote-only picker exposes raw inventory details';
end $$;
select set_config('test.qw.sale_payload','{"kind":"sale","mode":"credit","warehouseId":1,"partyId":-414101,"party":"ROLE-QW WHOLESALE","items":[{"id":414101,"qty":1,"price":130000}],"warranty":{"enabled":true,"items":[{"id":414101,"duration":12,"unit":"months"}]}}',true);
select set_config('test.qw.system_payload','{"kind":"system","mode":"credit","warehouseId":1,"partyId":-414102,"party":"ROLE-QW SYSTEM","total":3000000,"customerAddress":"بغداد","installerId":"00000000-0000-0000-0000-000000414103","items":[{"id":414102,"qty":1,"price":0}]}',true);
set local role authenticated;
do $$declare s jsonb; j jsonb; ctx jsonb; begin
 s:=public.solar_invoice_save(gen_random_uuid(),current_setting('test.qw.sale_payload')::jsonb);
 j:=public.solar_invoice_save(gen_random_uuid(),current_setting('test.qw.system_payload')::jsonb);
 perform set_config('test.qw.sale',s->>'id',true);
 perform set_config('test.qw.system',j->>'id',true);
 perform set_config('test.qw.qr',s->>'warrantyToken',true);
 ctx:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',s->'id'));
 perform set_config('test.qw.delete_token',ctx->>'token',true);
 assert ctx->>'id'=s->>'id','Original authorized seller cannot review own sale';
end $$;
reset role;
insert into public.transactions(id,kind,party_name,created_by,cashbox_user_id,total,cash) values
(-414103,'purchase','ROLE-QW PURCHASE',current_setting('test.qw.seller')::uuid,current_setting('test.qw.seller')::uuid,650000,false),
(-414104,'customer_payment','ROLE-QW PAYMENT',current_setting('test.qw.seller')::uuid,current_setting('test.qw.seller')::uuid,33000,true);
insert into public.solar_cash_entries(owner_id,actor_id,delta,entry_type,notes)
 values(current_setting('test.qw.seller')::uuid,current_setting('test.qw.admin')::uuid,111000,'transfer_in','QW historical cash');
insert into solar_private.receipt_delete_requests(id,invoice_id,kind,owner_id,requested_by,status,request_token,snapshot,submission) values
 ('00000000-0000-0000-0000-000000414150',current_setting('test.qw.sale')::bigint,'sale',current_setting('test.qw.seller')::uuid,current_setting('test.qw.seller')::uuid,'rejected','old-token','{"party":"ROLE-QW WHOLESALE","receiptNo":55}','{}');
update public.profiles set permissions='{"ownCustomers":true,"ownPayments":true,"ownProfit":true,"ownSales":true,"salesDeleteOwn":true,"tahseel":true,"tahseelFull":true,"installations":false,"installationsAll":false,"salesDeleteAll":false,"tahseelDefaults":false}' where id=current_setting('test.qw.seller')::uuid;
insert into public.solar_quotes(id,user_id,payload) values ('00000000-0000-0000-0000-000000414180',current_setting('test.qw.admin')::uuid,'{"customer":"private"}');
set local role authenticated;
do $$declare cert jsonb;begin
 assert not exists(select from public.transactions where created_by=auth.uid()),'Legacy scope flags exposed historical transactions';
 assert not exists(select from public.transaction_items where transaction_id in(current_setting('test.qw.sale')::bigint,current_setting('test.qw.system')::bigint)),'Historic invoice items leaked';
 assert not exists(select from public.customers where owner_id=auth.uid()),'Legacy scope flags exposed customers';
 assert not exists(select from public.solar_cash_entries where owner_id=auth.uid()),'Own previous cash entries leaked';
 assert not exists(select from public.products where id=414101),'Raw stock disclosed via table RLS';
 perform pg_temp.assert_catalog(true);
 insert into public.solar_quotes(id,user_id,payload) values ('00000000-0000-0000-0000-000000414181',auth.uid(),'{"customer":"initial"}');
 update public.solar_quotes set revision=2,payload='{"customer":"edited"}' where id='00000000-0000-0000-0000-000000414181' and revision=1;
 assert exists(select from public.solar_quotes where id='00000000-0000-0000-0000-000000414181' and revision=2),'Full quote cannot edit own draft';
 assert not exists(select from public.solar_quotes where id='00000000-0000-0000-0000-000000414180'),'Other staff quote leaked';
 cert:=public.solar_warranty_verify(current_setting('test.qw.qr')::uuid);
 assert cert->>'customer'='ROLE-QW WHOLESALE' and cert::text!~'"cost"|"profit"','Existing QR certificate missing or leaks financial details';
 perform pg_temp.denied('select public.solar_warranty_manage(''get'',null,jsonb_build_object(''id'',current_setting(''test.qw.sale'')))');
 perform pg_temp.denied('select public.solar_sales_history()');
 perform pg_temp.denied('select public.solar_sales_history_by_user(auth.uid())');
 perform pg_temp.denied('select public.solar_sales_period()');
 perform pg_temp.denied('select public.solar_sales_period_by_user(auth.uid())');
 perform pg_temp.denied('select public.solar_receipt_delete_requests(''list'')');
 perform pg_temp.denied('select public.solar_receipt_delete_requests(''get'',null,''{"id":"00000000-0000-0000-0000-000000414150"}'')');
 perform pg_temp.denied('select public.solar_receipt_delete_requests(''context'',null,jsonb_build_object(''invoiceId'',current_setting(''test.qw.sale'')))');
 perform pg_temp.denied('select public.solar_receipt_delete_requests(''request'',gen_random_uuid(),jsonb_build_object(''invoiceId'',current_setting(''test.qw.sale''),''expectedToken'',current_setting(''test.qw.delete_token'')))');
 perform pg_temp.denied('select public.solar_receipt_delete_requests(''delete_direct'',gen_random_uuid(),jsonb_build_object(''invoiceId'',current_setting(''test.qw.sale''),''expectedToken'',current_setting(''test.qw.delete_token'')))');
 perform pg_temp.denied('select public.solar_sale_delete_preview(current_setting(''test.qw.sale'')::bigint)');
 perform pg_temp.denied('select public.solar_sale_delete(current_setting(''test.qw.sale'')::bigint,''old-token'')');
 perform pg_temp.denied('select public.solar_purchase_delete(-414103,0)');
 perform pg_temp.denied('select public.solar_invoice_save(gen_random_uuid(),current_setting(''test.qw.sale_payload'')::jsonb)');
 perform pg_temp.denied('select public.solar_invoice_save(gen_random_uuid(),current_setting(''test.qw.system_payload'')::jsonb)');
 perform pg_temp.denied('select public.solar_cash_workspace()');
 perform pg_temp.denied('select public.solar_cash_read_balances()');
 perform pg_temp.denied('select public.solar_profit_workspace(''overview'')');
 perform pg_temp.denied('select public.solar_fx(''state'')');
 perform pg_temp.denied('select public.solar_exchange_rate_get()');
end $$;
reset role;
update public.profiles set permissions=permissions||'{"tahseelFull":false}' where id=current_setting('test.qw.seller')::uuid;
set local role authenticated;
do $$declare saved jsonb; body jsonb;begin
 perform pg_temp.assert_catalog(false);
 body:='{"customer":"ROLE-QW quote","day":"15","night":"15","batteryCapacity":"15","panel":{"id":414101},"battery":{"id":414103},"inverter":{"id":414102}}';
 saved:=public.solar_limited_quote('save',body,'00000000-0000-0000-0000-000000414182');
 assert saved->>'id'='00000000-0000-0000-0000-000000414182' and saved::text!~'"cost"|"unitCost"|"materialsTotal"','Limited offer unavailable or exposed costing';
 assert exists(select from jsonb_array_elements(public.solar_limited_quote('list')) q where q->>'id'=saved->>'id');
 perform public.solar_limited_quote('delete','{}',(saved->>'id')::uuid,(saved->>'revision')::integer);
end $$;
reset role;
-- A single kind grant must stay usable while the other invoice stays private.
update public.profiles set permissions='{"sale":true}' where id=current_setting('test.qw.seller')::uuid;
set local role authenticated;
do $$declare r jsonb; text_id text:=current_setting('test.qw.sale');begin
 r:=public.solar_sales_history('ROLE-QW');
 assert r->>'count'='1' and r->'rows'->0->>'id'=text_id,'Legacy wholesale history included system sale or excluded own invoice';
 assert public.solar_sales_period_by_user(auth.uid(),'ROLE-QW')->'summary'->>'invoiceCount'='1','Wholesale period included a hidden category';
 assert not exists(select from public.transactions where id=current_setting('test.qw.system')::bigint),'System visible to wholesale-only seller';
 r:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',text_id));
 assert r->'directEligible'='true'::jsonb and r->'canRequest'='false'::jsonb,'Direct clean-invoice deletion was disabled by the independent request grant';
 perform public.solar_sale_delete_preview(text_id::bigint);
 perform pg_temp.denied('select public.solar_sale_delete_preview(current_setting(''test.qw.system'')::bigint)');
 perform pg_temp.denied('select public.solar_receipt_delete_requests(''list'')');
end $$;
reset role;
update public.profiles set permissions='{"system":true,"salesHistory":false}' where id=current_setting('test.qw.seller')::uuid;
set local role authenticated;
select pg_temp.denied('select public.solar_sales_history()');
select pg_temp.denied('select public.solar_sales_period()');
reset role;
update public.profiles set permissions='{"system":true,"deletionRequests":true,"salesHistory":true}' where id=current_setting('test.qw.seller')::uuid;
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_sales_history_by_user(auth.uid(),'ROLE-QW');
 assert r->>'count'='1' and r->'rows'->0->>'id'=current_setting('test.qw.system'),'System-only history exposed wholesale sale';
 assert public.solar_sales_period('ROLE-QW')->'summary'->>'invoiceCount'='1';
 perform public.solar_receipt_delete_requests('list');
 r:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',current_setting('test.qw.system')));
 assert r->'canRequest'='true'::jsonb,'Explicit request grant not honored';
 perform public.solar_sale_delete_preview(current_setting('test.qw.system')::bigint);
end $$;
reset role;
update public.profiles set permissions='{"salesHistory":true}' where id=current_setting('test.qw.seller')::uuid;
set local role authenticated;
do $$declare r jsonb; affected integer;begin
 r:=public.solar_sales_history('ROLE-QW');
 assert r->>'count'='2','Independent own history grant lost access';
 perform pg_temp.denied('select public.solar_invoice_save(gen_random_uuid(),current_setting(''test.qw.sale_payload'')::jsonb)');
 perform pg_temp.denied('select public.solar_receipt_delete_requests(''context'',null,jsonb_build_object(''invoiceId'',current_setting(''test.qw.sale'')))');
 update public.transaction_items set price=1 where transaction_id=current_setting('test.qw.sale')::bigint;
 get diagnostics affected=row_count;assert affected=0,'Archive-only grant allowed modifying invoice items';
end $$;
reset role;
update public.profiles set permissions='{"cash":true}' where id=current_setting('test.qw.seller')::uuid;
set local role authenticated;
do $$begin
 assert public.solar_cash_read_balances() is not null;
 assert public.solar_cash_workspace() is not null;
 assert exists(select from public.solar_cash_entries where owner_id=auth.uid()),'Cash permission cannot read own cash';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.qw.admin'),true);
do $$declare r jsonb;begin
 r:=public.solar_sales_history_by_user(current_setting('test.qw.seller')::uuid,'ROLE-QW');
 assert r->>'count'='2','Admin lost authorized invoice history';
 assert public.solar_exchange_rate_get() is not null;
 perform public.solar_receipt_delete_requests('list');
end $$;
reset role;
select 'PASS quote/warranty access, isolated historical data, individual grants, legitimate seller and finance workflows' as result;
rollback;
