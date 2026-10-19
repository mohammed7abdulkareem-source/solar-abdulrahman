-- LOCAL TEST DATABASE ONLY: synthetic identities and Auth/JWT adapter for real PostgREST browser tests.
-- Never apply this fixture to a hosted/production database. Apply the V3.50 migration first.
create or replace function auth.uid() returns uuid language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
grant usage on schema public,auth to authenticated,anon;
grant select on all tables in schema public to authenticated;
grant execute on function auth.uid() to authenticated,anon;

insert into profiles(id,display_name,username,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000003530','Capital Admin','capital_admin',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003531','Capital Staff','capital_staff',false,'admin_staff','{"capital":true}'),
('00000000-0000-0000-0000-000000003532','Denied Staff','capital_denied',false,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003533','Warehouse','capital_warehouse',true,'warehouse','{"capital":true}');
insert into products(id,code,name,qty,cost) values(-353001,'CAPITAL','مخزون الكلفة',8906542,100);
insert into customers(id,name,customer_type,owner_id) values(-353001,'عميل الرصيد القديم','wholesale','00000000-0000-0000-0000-000000003530'),(-353002,'عميل السلفة','wholesale','00000000-0000-0000-0000-000000003531');
insert into suppliers(id,name) values(-353001,'ABDULRAHMAN CAPITAL'),(-353002,'مورد سلفة');
insert into transactions(id,kind,party_type,party_id,party_name,payment_mode,total,cash,created_by,notes) values
(-353001,'customer_payment','customer',-353001,'عميل الرصيد القديم','opening_balance',-156843000,false,'00000000-0000-0000-0000-000000003530','رصيد العملاء القديم'),
(-353002,'sale','customer',-353001,'عميل الرصيد القديم','credit',113025000,false,'00000000-0000-0000-0000-000000003530','صافي الحركات اللاحقة'),
(-353003,'supplier_payment','supplier',-353001,'ABDULRAHMAN CAPITAL','charge_old_balance',-188194000,false,'00000000-0000-0000-0000-000000003530','حساب الديون سابق'),
(-353004,'purchase','supplier',-353001,'ABDULRAHMAN CAPITAL','credit',1044049006.66,false,'00000000-0000-0000-0000-000000003530','شراء مستقل'),
(-353005,'cash_income',null,null,null,'cash',48089000,true,'00000000-0000-0000-0000-000000003530','رصيد نقدي');

update profiles set phone='07700003530';

create or replace function public.solar_staff_directory() returns jsonb language sql stable security definer set search_path='' as $$select jsonb_agg(jsonb_build_object('id',id,'display_name',display_name,'username',username,'user_type',user_type)) from public.profiles where active and solar_private.role_name() in('admin','staff')$$;
revoke all on function public.solar_staff_directory() from public,anon;grant execute on function public.solar_staff_directory() to authenticated;

notify pgrst,'reload schema';
