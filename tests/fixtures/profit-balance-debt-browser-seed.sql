-- Dedicated local browser fixture only. Never run against a production database.
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions)values
('00000000-0000-0000-0000-000000003910','مدير اختبار الأرباح',true,'admin_staff','07700003910','{}'),
('00000000-0000-0000-0000-000000003911','سفيان الاختبار',false,'admin_staff','07700003911','{"cash":true,"profit":true,"profitSettlement":true,"customerDebts":true,"customers":true,"customerStatement":true}'),
('00000000-0000-0000-0000-000000003912','المستخدم الآخر',false,'admin_staff','07700003912','{"profit":true,"customerDebts":true,"customerStatement":true}'),
('00000000-0000-0000-0000-000000003915','قائمة مدينين فقط',false,'admin_staff','07700003915','{"customerDebts":true}'),
('00000000-0000-0000-0000-000000003916','كشف حساب فقط',false,'admin_staff','07700003916','{"customerDebts":true,"customerStatement":true}');
insert into suppliers(id,name,account_currency)values(-391001,'مورد اختبار الأرباح','IQD');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003910',true);
select public.solar_customer_save('create',gen_random_uuid(),'{"id":-391011,"name":"شركة ديون الاختبار","phone":"07712343911","customerType":"system","ownerId":"00000000-0000-0000-0000-000000003911","openingBalance":6667000}');
select public.solar_customer_save('create',gen_random_uuid(),'{"id":-391012,"name":"زبون جملة الاختبار","phone":"07712343912","customerType":"wholesale","ownerId":"00000000-0000-0000-0000-000000003911","openingBalance":200000}');
select public.solar_customer_save('create',gen_random_uuid(),'{"id":-391015,"name":"زبون قائمة فقط","phone":"07712343915","customerType":"system","ownerId":"00000000-0000-0000-0000-000000003915","openingBalance":300000}');
select public.solar_customer_save('create',gen_random_uuid(),'{"id":-391016,"name":"زبون كشف حساب فقط","phone":"07712343916","customerType":"system","ownerId":"00000000-0000-0000-0000-000000003916","openingBalance":400000}');
reset role;
insert into transactions(id,kind,party_id,party_name,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id,created_at)values
(-391001,'sale',-391011,'شركة ديون الاختبار',10000000,10000000,7535136.32,true,false,'credit','00000000-0000-0000-0000-000000003911','00000000-0000-0000-0000-000000003911',now()-interval '2 days'),
(-391002,'sale',null,'مبيعات المستخدم الآخر',1000000,1000000,1000000,true,false,'credit','00000000-0000-0000-0000-000000003912','00000000-0000-0000-0000-000000003912',now()-interval '2 days');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003911',true);
do $$declare r jsonb;c jsonb;s jsonb;begin
 c:=public.solar_profit_workspace('overview');r:=public.solar_profit_workspace('request',gen_random_uuid(),jsonb_build_object('expectedToken',c->>'token'));
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003910',true);
 c:=public.solar_profit_workspace('overview');select value into s from jsonb_array_elements(c->'suppliers')where(value->>'id')::bigint=-391001;
 select value into r from jsonb_array_elements(c->'requests')where value->>'id'=r->>'id';
 perform public.solar_profit_workspace('approve',gen_random_uuid(),jsonb_build_object('id',r->>'id','expectedToken',r->>'token','share',3768000,'collectionConfirmed',true,'settlementModel','owner_debit_supplier_charge','supplierId',-391001,'supplierToken',s->>'token','supplierRate',s->'rate'));
end$$;
commit;
