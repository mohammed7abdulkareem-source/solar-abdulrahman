-- GoTrue writes app_metadata after its initial auth.users INSERT. The Edge
-- preflight already runs in a separate committed transaction before that INSERT.
create table solar_private.staff_provision_intents (
 user_id uuid primary key,
 actor_id uuid not null,
 request_hash text not null,
 username text not null,
 display_name text not null,
 phone text,
 honorific text,
 initial_token text
);
alter table solar_private.staff_provision_intents enable row level security;
revoke all on solar_private.staff_provision_intents from public, anon, authenticated;

create function solar_private.staff_provision_reserve(actor uuid, uid uuid, input jsonb)
returns void language plpgsql set search_path='' as $$
declare
 reservation solar_private.staff_provision_intents;
 signature text := md5(input::text);
begin
 if input->'creating' is distinct from 'true'::jsonb
   or coalesce(input->>'username','') !~ '^[a-z0-9_.-]{2,30}$'
   or length(trim(coalesce(input->>'display_name',''))) not between 1 and 150
   or (input ? 'phone' and coalesce(input->>'phone','') !~ '^\+?[0-9]{7,15}$')
   or length(coalesce(input->>'honorific',''))>50 or coalesce(input->>'honorific','')~'[<>[:cntrl:]]' then
  raise exception 'تحقق من بيانات إنشاء الحساب' using errcode='22023';
 end if;
 select * into reservation from solar_private.staff_provision_intents where user_id=uid;
 if reservation.user_id is not null then
  if reservation.actor_id<>actor or reservation.request_hash<>signature then
   raise exception 'رقم الطلب مستخدم لعملية مختلفة' using errcode='PT409';
  end if;
  return;
 end if;

 -- A pre-migration interrupted create can resume only for its original
 -- trusted Auth identity. A later administrator's successful edit wins.
 if exists(select 1 from public.profiles where id=uid) then
  if exists(select 1 from solar_private.staff_admin_requests where target_id=uid)
     or not exists(select 1 from pg_catalog.pg_attribute where attrelid=to_regclass('auth.users') and attname='raw_app_meta_data' and not attisdropped) then
   raise exception 'الحساب موجود. افتحه من قائمة المستخدمين.' using errcode='PT409';
  end if;
  if not exists(select 1 from auth.users a where a.id=uid and a.raw_app_meta_data->>'solar_wizard_request'=uid::text
     and a.raw_app_meta_data->>'solar_wizard_actor'=actor::text and a.raw_app_meta_data->>'solar_wizard_credential'=input->>'credentialTag'
     and coalesce(a.raw_app_meta_data->>'solar_wizard_ready','false')='false') then
   raise exception 'الحساب موجود. افتحه من قائمة المستخدمين.' using errcode='PT409';
  end if;
 end if;
 insert into solar_private.staff_provision_intents(user_id,actor_id,request_hash,username,display_name,phone,honorific,initial_token)
 values(uid,actor,signature,input->>'username',trim(input->>'display_name'),input->>'phone',input->>'honorific',solar_private.staff_wizard_user(uid)->>'token');
end$$;

create function solar_private.staff_provision_bootstrap() returns trigger
language plpgsql security definer set search_path='' as $$
declare reservation solar_private.staff_provision_intents;
begin
 select * into reservation from solar_private.staff_provision_intents where user_id=new.id;
 if reservation.user_id is null then return new; end if;
 if tg_when='BEFORE' then
  new.active:=false;
  new.is_admin:=false;
  new.user_type:='admin_staff';
  new.permissions:='{}'::jsonb;
  new.username:=reservation.username;
  new.display_name:=reservation.display_name;
  new.phone:=reservation.phone;
  new.honorific:=coalesce(reservation.honorific,'');
 else
  -- Missing scope defaults to the primary warehouse. An actual empty scope is
  -- part of the initial inactive account, even if the caller never comes back.
  insert into solar_private.warehouse_access(user_id,all_warehouses,warehouse_ids,can_transfer,updated_by)
  values(new.id,false,'{}',false,reservation.actor_id);
  update solar_private.staff_provision_intents set initial_token=solar_private.staff_wizard_user(new.id)->>'token'
  where user_id=new.id;
 end if;
 return new;
end$$;
create trigger solar_staff_wizard_reserved_profile before insert on public.profiles
 for each row execute function solar_private.staff_provision_bootstrap();
create trigger solar_staff_wizard_reserved_scope after insert on public.profiles
 for each row execute function solar_private.staff_provision_bootstrap();
revoke all on function solar_private.staff_provision_reserve(uuid,uuid,jsonb),solar_private.staff_provision_bootstrap()
 from public, anon, authenticated;

-- Keep the deployed service-only RPC, grants, v10 Edge contract and other
-- admin actions. Reserve only after its existing admin and tombstone checks.
do $patch$
declare
 original text;
 updated text;
begin
 original:=pg_get_functiondef('public.solar_admin_user_wizard(uuid,text,uuid,jsonb)'::regprocedure);
 updated:=replace(original,$old$if action not in('directory','check_create') then perform pg_advisory_xact_lock$old$,
                          $new$if action<>'directory' then perform pg_advisory_xact_lock$new$);
 if updated=original then raise exception 'Missing wizard lock anchor'; end if;
 original:=updated;
 updated:=replace(original,$old$return jsonb_build_object('staged',prior.request_id is not null);$old$,
  $new$if prior.request_id is null then perform solar_private.staff_provision_reserve(actor.id,uid,payload); end if;
  return jsonb_build_object('staged',prior.request_id is not null);$new$);
 if updated=original then raise exception 'Missing wizard preflight anchor'; end if;
 original:=updated;
 updated:=replace(original,$old$if action='save_details' then
  if payload->>'username'$old$,
  $new$if action='save_details' then
  if creating and (exists(select 1 from solar_private.staff_provision_intents i where i.user_id=uid
       and (i.actor_id<>actor.id or i.request_hash<>md5(payload::text) or i.initial_token is distinct from current_profile->>'token'))
     or exists(select 1 from solar_private.staff_admin_requests r where r.target_id=uid)) then
   raise exception 'تغير الحساب بعد إنشائه. افتحه من قائمة المستخدمين.' using errcode='PT409';
  end if;
  if payload->>'username'$new$);
 if updated=original then raise exception 'Missing wizard initial save anchor'; end if;
 execute updated;
 original:=pg_get_functiondef('solar_private.staff_has_history(uuid)'::regprocedure);
 updated:=replace(original,$old$c.relname not in('profiles','staff_admin_requests',$old$,
                          $new$c.relname not in('profiles','staff_provision_intents','staff_admin_requests',$new$);
 if updated=original then raise exception 'Missing account history exclusion anchor'; end if;
 execute updated;
end$patch$;
