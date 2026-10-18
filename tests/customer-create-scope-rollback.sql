\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,display_name,is_admin,permissions,user_type,active) values
 ('00000000-0000-0000-0000-000000003410','مدير الاختبار',true,'{}','admin_staff',true),
 ('00000000-0000-0000-0000-000000003411','إضافة فقط',false,'{"customerCreate":true}','admin_staff',true),
 ('00000000-0000-0000-0000-000000003412','مستخدم آخر',false,'{"customers":true}','admin_staff',true),
 ('00000000-0000-0000-0000-000000003413','بدون صلاحية',false,'{}','admin_staff',true),
 ('00000000-0000-0000-0000-000000003414','مهندس',true,'{"customerCreate":true}','installer',true),
 ('00000000-0000-0000-0000-000000003415','مخزن',false,'{"customerCreate":true}','warehouse',true),
 ('00000000-0000-0000-0000-000000003416','متوقف',false,'{"customerCreate":true}','admin_staff',false);
insert into public.customers(id,name,customer_type,owner_id) values(-341010,'زبون المستخدم الآخر','system','00000000-0000-0000-0000-000000003412');
-- The local fixture normally runs without customer RLS. Mirror the production
-- permissive policy so the restrictive ownership policy is exercised for real.
alter table public.customers enable row level security;
create policy fixture_customer_active on public.customers for all to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active));
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003411',true);
do $$declare r jsonb;b jsonb;req uuid:=gen_random_uuid();begin
 b:='{"id":-341001,"name":"زبون الجملة الخاص","customerType":"wholesale","phone":"07701111101","ownerId":"00000000-0000-0000-0000-000000003412","openingBalance":2000000}';
 r:=public.solar_customer_save('create',req,b);
 if r->>'ownerId'<>'00000000-0000-0000-0000-000000003411' or(r->>'balance')::numeric<>2000000 then raise exception 'FAIL automatic owner or opening';end if;
 if public.solar_customer_save('create',req,b)<>r then raise exception 'FAIL create retry';end if;
 perform public.solar_customer_save('create',gen_random_uuid(),'{"id":-341002,"name":"زبون المفرد الخاص","customerType":"system"}');
 if jsonb_array_length(public.solar_customer_directory())<>2 then raise exception 'FAIL creator directory scope';end if;
 if(select count(*) from public.customers)<>2 then raise exception 'FAIL Data API exposed another customer';end if;
 if exists(select 1 from public.customers where id=-341010) then raise exception 'FAIL direct cross-owner read';end if;
 begin perform public.solar_customer_get(-341010);raise exception 'FAIL cross-owner get';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_save('update',gen_random_uuid(),jsonb_build_object('id',-341001,'token',r->>'token','name','تعديل غير مسموح','customerType','wholesale'));raise exception 'FAIL create-only update';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_save('delete',gen_random_uuid(),jsonb_build_object('id',-341002,'token',public.solar_customer_get(-341002)->>'token'));raise exception 'FAIL create-only delete';exception when insufficient_privilege then null;end;
 begin update public.customers set name='تعديل مباشر' where id=-341001;raise exception 'FAIL direct create-only update';exception when insufficient_privilege then null;end;
 begin delete from public.customers where id=-341002;raise exception 'FAIL direct create-only delete';exception when insufficient_privilege then null;end;
 begin insert into public.customers(id,name,customer_type,owner_id) values(-341003,'تعيين مستخدم آخر','system','00000000-0000-0000-0000-000000003412');raise exception 'FAIL direct forged owner';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_save('create',gen_random_uuid(),'{"id":-341004,"name":"زبون الجملة الخاص","customerType":"system"}');raise exception 'FAIL duplicate accepted';exception when unique_violation then null;end;
 if public.solar_customer_check('زبون المستخدم الآخر','',null)->0->>'name' is not null then raise exception 'FAIL duplicate check leaked name';end if;
end $$;
-- Removing create permission takes effect immediately, including retries.
reset role;
update public.profiles set permissions='{}' where id='00000000-0000-0000-0000-000000003411';
set local role authenticated;
do $$begin
 begin perform public.solar_customer_save('create',gen_random_uuid(),'{"id":-341005,"name":"بعد إلغاء الصلاحية","customerType":"system"}');raise exception 'FAIL revoked permission';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003412',true);
do $$declare r jsonb;begin
 if(select count(*) from public.customers)<>1 then raise exception 'FAIL other user Data API scope';end if;
 r:=public.solar_customer_get(-341010);
 perform public.solar_customer_save('update',gen_random_uuid(),jsonb_build_object('id',-341010,'token',r->>'token','name','زبون المستخدم الآخر المعدل','customerType','system','openingBalance',0));
 begin update public.customers set owner_id='00000000-0000-0000-0000-000000003411' where id=-341010;raise exception 'FAIL owner reassignment';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$declare uid text;begin
 foreach uid in array array['00000000-0000-0000-0000-000000003413','00000000-0000-0000-0000-000000003414','00000000-0000-0000-0000-000000003415','00000000-0000-0000-0000-000000003416'] loop
  perform set_config('request.jwt.claim.sub',uid,true);
  begin perform public.solar_customer_save('create',gen_random_uuid(),'{"id":-341006,"name":"دور غير مسموح","customerType":"system"}');raise exception 'FAIL role allowed: %',uid;exception when insufficient_privilege then null;end;
 end loop;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003410',true);
do $$begin
 if(select count(*) from public.customers)<>3 or jsonb_array_length(public.solar_customer_directory())<>3 then raise exception 'FAIL admin overview';end if;
end $$;
reset role;
do $$begin
 if(select count(*) from solar_private.customer_changes)<>3 then raise exception 'FAIL audited writes';end if;
 if has_function_privilege('anon','public.solar_customer_save(text,uuid,jsonb)','EXECUTE') then raise exception 'FAIL anon create permission';end if;
 raise notice 'PASS create-only wholesale/retail, fixed owner, actual RLS, management separation, duplicate privacy, replay, revocation and admin scope';
end $$;
rollback;
