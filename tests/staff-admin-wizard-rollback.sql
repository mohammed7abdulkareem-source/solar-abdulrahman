-- Isolated database fixture. All accounts and mutations in this test roll back.
\set ON_ERROR_STOP on
begin;
do $$
declare actor uuid:=gen_random_uuid();target uuid:=gen_random_uuid();fresh uuid:=gen_random_uuid();
 input jsonb;settings jsonb;reply jsonb;user_data jsonb;location bigint:=solar_private.primary_warehouse();r uuid;
begin
 assert not has_function_privilege('authenticated','public.solar_admin_user_wizard(uuid,text,uuid,jsonb)','execute');
 assert not has_function_privilege('anon','public.solar_admin_user_wizard(uuid,text,uuid,jsonb)','execute');
 assert has_function_privilege('service_role','public.solar_admin_user_wizard(uuid,text,uuid,jsonb)','execute');
 insert into public.profiles(id,is_admin,active,user_type,display_name) values(actor,true,true,'admin','Wizard admin');
 input:=jsonb_build_object('creating',true,'user_id',target,'username','wizard_qa_staged','display_name','مستخدم للاختبار','phone','07700000000');
 assert public.solar_admin_user_wizard(actor,'check_create',target,input)='{"staged":false}';
 insert into public.profiles(id,is_admin,active,user_type,display_name)values(target,false,true,'admin_staff','Bootstrap');
 reply:=public.solar_admin_user_wizard(actor,'save_details',target,input);
 assert (reply#>>'{user,active}')::boolean=false and reply#>'{user,warehouse,ids}'='[]'::jsonb and not solar_private.warehouse_access_allowed(target,location);
 assert public.solar_admin_user_wizard(actor,'check_create',target,input)='{"staged":true}';
 assert public.solar_admin_user_wizard(actor,'save_details',target,input)=reply;
 settings:=jsonb_build_object('user_id',target,'token',reply#>>'{user,token}','role','user','active',true,'permissions','{"tahseel":true,"warranty":true}'::jsonb,
   'warehouse',jsonb_build_object('all',false,'ids',jsonb_build_array(location),'transferDirections',jsonb_build_object('fromPrimary',true,'toPrimary',false,'other',false)));
 r:=gen_random_uuid();reply:=public.solar_admin_user_wizard(actor,'finalize',r,settings);
 assert (reply#>>'{user,active}')::boolean and (reply#>>'{user,permissions,tahseel}')::boolean and reply#>'{user,warehouse,ids}'=jsonb_build_array(location);
 assert coalesce(reply#>>'{user,permissions,stock}','false')='false';
 assert public.solar_admin_user_wizard(actor,'finalize',r,settings)=reply;
 begin perform public.solar_admin_user_wizard(actor,'finalize',gen_random_uuid(),settings);raise exception 'Stale role update succeeded';exception when sqlstate 'PT409' then null;end;
 begin perform public.solar_admin_user_wizard(target,'directory');raise exception 'Staff accepted as admin';exception when insufficient_privilege then null;end;
 user_data:=solar_private.staff_wizard_user(actor);
 begin perform public.solar_admin_user_wizard(actor,'finalize',gen_random_uuid(),settings||jsonb_build_object('user_id',actor,'token',user_data->>'token','role','user'));raise exception 'Self demotion succeeded';exception when insufficient_privilege then null;end;
 begin perform public.solar_admin_user_wizard(actor,'remove',gen_random_uuid(),jsonb_build_object('user_id',actor,'token',user_data->>'token'));raise exception 'Self-removal succeeded';exception when insufficient_privilege then null;end;
 reply:=public.solar_admin_user_wizard(actor,'remove',gen_random_uuid(),jsonb_build_object('user_id',target,'token',reply#>>'{user,token}'));
 assert reply->>'mode'='candidate',reply;
 delete from public.profiles where id=target;
 begin perform public.solar_admin_user_wizard(actor,'check_create',target,input);raise exception 'Deleted account returned to provisioning';exception when sqlstate 'PT409' then null;end;
 begin perform public.solar_admin_user_wizard(actor,'save_details',target,input);raise exception 'Deleted creation replay accepted';exception when sqlstate 'PT409' then null;end;
 begin insert into public.profiles(id) values(target);raise exception 'Deleted identity UUID reused';exception when sqlstate 'PT409' then null;end;
 insert into public.profiles(id,is_admin,active,user_type,display_name)values(fresh,false,true,'admin_staff','مصروف سابق');
 insert into public.transactions(id,kind,party_name,created_by,cashbox_user_id,total)values(-88411267,'sale','الزبون',fresh,fresh,12000);
 reply:=public.solar_admin_user_wizard(actor,'remove',gen_random_uuid(),jsonb_build_object('user_id',fresh,'token',solar_private.staff_wizard_user(fresh)->>'token'));
 assert reply->>'mode'='archived' and exists(select 1 from public.profiles p where p.id=fresh and not p.active);
 begin delete from public.profiles where id=fresh;raise exception 'Historical identity erased';exception when foreign_key_violation then null;end;
 assert (select t.created_by=fresh and t.total=12000 from public.transactions t where t.id=-88411267);
end$$;
-- Simulate the Edge caller disappearing after Auth inserted the profile and
-- before the first save_details call. A different admin resumes by user ID.
do $$
declare
 creator uuid:=gen_random_uuid(); reviewer uuid:=gen_random_uuid(); pending uuid:=gen_random_uuid();
 input jsonb; snapshot jsonb; saved jsonb;
begin
 assert not has_table_privilege('authenticated','solar_private.staff_provision_intents','insert');
 assert not has_function_privilege('authenticated','solar_private.staff_provision_reserve(uuid,uuid,jsonb)','execute');
 insert into public.profiles(id,active,is_admin,user_type,display_name)
 values(creator,true,true,'admin','Creator'),(reviewer,true,true,'admin','Reviewer');
 input:=jsonb_build_object('user_id',pending,'creating',true,'username','wizard_qa_resume','display_name','مستخدم جديد','phone','07700000000');
 perform public.solar_admin_user_wizard(creator,'check_create',pending,input);
 begin
  perform public.solar_admin_user_wizard(reviewer,'check_create',pending,input);
  raise exception 'Reservation reassigned to a different creator';
 exception when sqlstate 'PT409' then null; end;
 begin
  perform public.solar_admin_user_wizard(creator,'check_create',pending,input||'{"username":"changed"}'::jsonb);
  raise exception 'Reservation details overwritten';
 exception when sqlstate 'PT409' then null; end;
 insert into public.profiles(id,active,is_admin,user_type,display_name) values(pending,true,false,'admin_staff','Bootstrap');
 select u into snapshot from jsonb_array_elements(public.solar_admin_user_wizard(reviewer,'directory')->'users') u where u->>'id'=pending::text;
 assert snapshot->>'username'='wizard_qa_resume' and snapshot->>'display_name'='مستخدم جديد' and snapshot->>'phone'='07700000000';
 assert snapshot->'active'='false'::jsonb and snapshot->'is_admin'='false'::jsonb and snapshot#>'{warehouse,ids}'='[]'::jsonb;
 assert not solar_private.warehouse_access_allowed(pending,solar_private.primary_warehouse());
 assert not exists(select 1 from solar_private.staff_admin_requests where target_id=pending);
 saved:=public.solar_admin_user_wizard(reviewer,'finalize',gen_random_uuid(),
   jsonb_build_object('user_id',pending,'token',snapshot->>'token','active',true,'role','user','permissions','{"warranty":true}'::jsonb));
 begin
  perform public.solar_admin_user_wizard(creator,'save_details',pending,input);
  raise exception 'Delayed initial save overwrote the reviewed account';
 exception when sqlstate 'PT409' then null; end;
 assert solar_private.staff_wizard_user(pending)=saved->'user' and saved#>'{user,active}'='true'::jsonb and saved#>'{user,permissions,warranty}'='true'::jsonb;
end$$;
rollback;
\echo PASS inactive bootstrap, interrupted cross-admin review, permissions and warehouses, stale rejection, historical-account archive and removal retry.
