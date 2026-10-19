-- LOCAL TEST DATABASE ONLY: synthetic identities and Auth/JWT adapter for real PostgREST browser tests.
-- Never apply this fixture to a hosted/production database. Apply the V3.50 migration first.
create or replace function auth.uid() returns uuid language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
grant usage on schema public,auth to authenticated,anon;
grant select on all tables in schema public to authenticated;
grant execute on function auth.uid() to authenticated,anon;
insert into profiles(id,display_name,username,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000003500','Multi Admin','multi_admin',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003501','Multi Seller','multi_seller',false,'admin_staff','{"sale":true,"system":true,"purchase":true,"stock":true,"stockAdjust":true,"stockMovement":true,"products":true,"salesHistory":true,"warehouse":true}'),
('00000000-0000-0000-0000-000000003502','Main preparer','main_preparer',false,'warehouse','{}'),
('00000000-0000-0000-0000-000000003503','Sayada preparer','sayada_preparer',false,'warehouse','{}'),
('00000000-0000-0000-0000-000000003505','Engineer','engineer',false,'installer','{}');
insert into brands(id,name) values(-350001,'MAGIC');
insert into products(id,code,name,brand_id,category,qty,cost) values(-350001,'350001','بطارية 10KW',-350001,'بطارية',20,100000),(-350002,'350002','محولة 6KW',-350001,'انفيرتر',8,250000);
insert into customers(id,name,phone,customer_type,owner_id) values(-350001,'زبون تجريبي جملة','07700000350','wholesale','00000000-0000-0000-0000-000000003500'),(-350002,'زبون منظومة','07700000351','system','00000000-0000-0000-0000-000000003500');
insert into suppliers(id,name,account_currency) values(-350001,'مورد الدولار','USD');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003500',false);
select public.solar_inventory('access_save',gen_random_uuid(),jsonb_build_object('userId','00000000-0000-0000-0000-000000003503','all',false,'ids',jsonb_build_array((select id from solar_private.warehouses where code='SAYADA')),'revision',0));
create function public.solar_staff_directory() returns jsonb language sql stable security definer set search_path='' as $$select jsonb_agg(jsonb_build_object('id',id,'display_name',display_name,'username',username,'user_type',user_type)) from public.profiles where active and solar_private.role_name() in('admin','staff')$$;
revoke all on function public.solar_staff_directory() from public,anon;grant execute on function public.solar_staff_directory() to authenticated;
