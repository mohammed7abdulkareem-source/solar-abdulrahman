-- The Edge function owns Auth credentials. SQL commits editable profile fields,
-- warehouse assignments and the final activation decision under one lock.
create table solar_private.staff_admin_requests(
 request_id uuid primary key, actor_id uuid not null, target_id uuid not null, action text not null,
 payload jsonb not null, response jsonb not null, created_at timestamptz not null default clock_timestamp()
);
alter table solar_private.staff_admin_requests enable row level security;
revoke all on solar_private.staff_admin_requests from public,anon,authenticated;
create index staff_admin_requests_target on solar_private.staff_admin_requests(target_id,created_at desc);
create function solar_private.staff_wizard_user(uid uuid) returns jsonb
language sql stable set search_path='' as $$
 with user_data as (
  select jsonb_build_object('id',p.id,'username',p.username,'display_name',p.display_name,'honorific',p.honorific,
   'phone',p.phone,'user_type',p.user_type,'is_admin',p.is_admin,'active',p.active,'permissions',p.permissions,'created_at',p.created_at,
   'warehouse',jsonb_build_object('all',coalesce(a.all_warehouses,false),'ids',to_jsonb(coalesce(a.warehouse_ids,array[solar_private.primary_warehouse()])),
     'transferDirections',jsonb_build_object('fromPrimary',coalesce(a.transfer_from_primary,false),'toPrimary',coalesce(a.transfer_to_primary,false),'other',coalesce(a.transfer_other,false)))) data,
   coalesce(a.revision,0) scope_revision,p.updated_at
  from public.profiles p left join solar_private.warehouse_access a on a.user_id=p.id where p.id=uid
 ) select data||jsonb_build_object('token',md5(jsonb_build_array(data,scope_revision,updated_at)::text)) from user_data
$$;

-- Legacy ledgers also store historical ownership inside transaction snapshots.
-- Treat any matching operational record as grounds to retain the identity.
create function solar_private.staff_has_history(uid uuid) returns boolean
language plpgsql stable set search_path='' as $$
declare src record;found_reference boolean;
begin
 if exists(select 1 from solar_private.staff_admin_requests r where r.actor_id=uid) then return true;end if;
 for src in
  select n.nspname,c.relname,string_agg(case when a.atttypid='uuid'::regtype then format('%I=$1',a.attname)
     else format('strpos(%I::text,$1::text)>0',a.attname) end,' or ') conditions
  from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  join pg_catalog.pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
  where n.nspname in('public','solar_private') and c.relkind in('r','p') and a.atttypid in('uuid'::regtype,'jsonb'::regtype,'json'::regtype)
   and c.relname not in('profiles','staff_admin_requests','solar_notifications','solar_push_subscriptions','push_deliveries','purchase_notice_recipients',
     'warehouse_access','warehouse_access_audit','wholesale_pricing_users','section_layouts','user_section_layouts')
  group by n.nspname,c.relname order by case c.relname when 'transactions' then 0 when 'customers' then 1 else 2 end
 loop
  execute format('select exists(select 1 from %I.%I where %s)',src.nspname,src.relname,src.conditions) into found_reference using uid;
  if found_reference then return true;end if;
 end loop;
 return false;
end$$;

create function solar_private.staff_wizard_delete_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare intent jsonb;
begin
 select response into intent from solar_private.staff_admin_requests
 where target_id=old.id and action='remove' order by created_at desc limit 1;
 if intent is not null and(old.active or intent->>'mode'<>'candidate' or old.updated_at is distinct from (intent->>'updatedAt')::timestamptz
     or solar_private.staff_has_history(old.id)) then
  raise exception 'الحساب مرتبط بسجل سابق أو تغير منذ طلب الحذف' using errcode='23503';
 end if;
 return old;
end$$;
create trigger solar_staff_wizard_preserve_history before delete on public.profiles
 for each row execute function solar_private.staff_wizard_delete_guard();

-- Never provision a second identity with an already removed UUID. This also
-- closes the interval between checking a create retry and GoTrue's INSERT.
create function solar_private.staff_wizard_reuse_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from solar_private.staff_admin_requests r where r.target_id=new.id and r.action='remove') then
  raise exception 'لا يمكن إعادة إنشاء حساب محذوف بنفس المعرّف' using errcode='PT409';end if;
 -- The standard Auth insert trigger creates an active profile. A wizard
 -- account is inactive from that very INSERT, even before its first Edge save.
 if exists(select 1 from pg_catalog.pg_attribute a where a.attrelid=to_regclass('auth.users') and a.attname='raw_app_meta_data' and not a.attisdropped) then
  if exists(select 1 from auth.users a where a.id=new.id and a.raw_app_meta_data->>'solar_wizard_request'=new.id::text
     and a.raw_app_meta_data ? 'solar_wizard_actor') then
   new.active:=false;new.is_admin:=false;new.user_type:='admin_staff';new.permissions:='{}'::jsonb;
  end if;
 end if;
 return new;
end$$;
create trigger solar_staff_wizard_no_reuse before insert on public.profiles for each row execute function solar_private.staff_wizard_reuse_guard();

create function public.solar_admin_user_wizard(actor_id uuid,action text,request_id uuid default null,payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='6s' as $$
#variable_conflict use_variable
declare actor public.profiles;target public.profiles;prior solar_private.staff_admin_requests;uid uuid;creating boolean;previous jsonb;
 before_scope solar_private.warehouse_access;scope jsonb;dirs jsonb;locations bigint[];role_name text;new_active boolean;
 result jsonb;current_profile jsonb;requested_grants jsonb;scope_changed boolean;visible_scope jsonb;
begin
 if action not in('directory','check_create','save_details','finalize','remove') or action is null or jsonb_typeof(payload) is distinct from 'object' then raise exception 'عملية إدارة غير معروفة' using errcode='22023';end if;
 if action not in('directory','check_create') then perform pg_advisory_xact_lock(7311,1);end if;
 select * into actor from public.profiles p where p.id=actor_id and p.active and p.is_admin and p.user_type not in('warehouse','installer');
 if actor.id is null then raise exception 'إدارة المستخدمين للأدمن الفعال فقط' using errcode='42501';end if;
 if action='directory' then
  return jsonb_build_object('users',coalesce((select jsonb_agg(solar_private.staff_wizard_user(p.id) order by p.created_at,p.id) from public.profiles p),'[]'::jsonb),
   'warehouses',coalesce((select jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,'active',w.active,'isPrimary',w.is_primary)
    order by w.is_primary desc,w.name,w.id) from solar_private.warehouses w),'[]'::jsonb));
 end if;
 uid:=nullif(payload->>'user_id','')::uuid;
 if request_id is null or uid is null or payload ?|array['password','pass','access_token'] then raise exception 'بيانات الطلب غير صحيحة' using errcode='22023';end if;
 select * into prior from solar_private.staff_admin_requests r where r.request_id=solar_admin_user_wizard.request_id;
 if action='check_create' then
  if uid<>request_id or exists(select 1 from solar_private.staff_admin_requests r where r.target_id=uid and r.action='remove') then
   raise exception 'هذه المحاولة تخص حساباً محذوفاً أو موقوفاً' using errcode='PT409';end if;
  if prior.request_id is not null and (prior.actor_id<>actor_id or prior.action<>'save_details' or prior.target_id<>uid or prior.payload<>payload
    or not exists(select 1 from public.profiles p where p.id=uid)) then
   raise exception 'انتهت محاولة إنشاء هذا الحساب' using errcode='PT409';end if;
  return jsonb_build_object('staged',prior.request_id is not null);
 end if;
 if prior.request_id is not null then
  if prior.actor_id<>actor_id or prior.target_id<>uid or prior.action<>action or prior.payload<>payload then raise exception 'رقم الطلب مستخدم لعملية مختلفة' using errcode='PT409';end if;
  if action<>'remove' and (not exists(select 1 from public.profiles p where p.id=uid) or exists(
    select 1 from solar_private.staff_admin_requests r where r.target_id=uid and r.action='remove' and r.created_at>prior.created_at)) then
   raise exception 'هذا الحساب محذوف أو موقوف' using errcode='PT409';end if;
  return prior.response;
 end if;
 select * into target from public.profiles p where p.id=uid for update;
 if target.id is null then raise exception 'حساب المستخدم غير موجود' using errcode='P0002';end if;
 current_profile:=solar_private.staff_wizard_user(uid);
 creating:=action='save_details' and payload->'creating'='true'::jsonb and uid=request_id;
 if not coalesce(creating,false) and payload->>'token' is distinct from current_profile->>'token' then
  raise exception 'تغيرت بيانات المستخدم أو صلاحياته. حدّث القائمة وأعد المراجعة.' using errcode='PT409';
 end if;

 if action='save_details' then
  if payload->>'username' is null or payload->>'username' !~ '^[a-z0-9_.-]{2,30}$' or length(trim(coalesce(payload->>'display_name',''))) not between 1 and 150
   or (payload ? 'phone' and coalesce(payload->>'phone','') !~ '^\+?[0-9]{7,15}$')
   or length(coalesce(payload->>'honorific',''))>50 or coalesce(payload->>'honorific','')~'[<>[:cntrl:]]' then
   raise exception 'تحقق من اسم المستخدم والاسم والهاتف والكنية' using errcode='22023';
  end if;
  update public.profiles set username=payload->>'username',display_name=trim(payload->>'display_name'),
   honorific=case when payload?'honorific' then coalesce(payload->>'honorific','') else target.honorific end,
   phone=case when payload?'phone' then payload->>'phone' else target.phone end,
   active=case when creating then false else target.active end, is_admin=case when creating then false else target.is_admin end,
   permissions=case when creating then '{}'::jsonb else target.permissions end,
   user_type=case when creating then 'admin_staff' else target.user_type end, updated_at=clock_timestamp()
  where id=uid;
  if creating then
   insert into solar_private.warehouse_access(user_id,all_warehouses,warehouse_ids,can_transfer,updated_by) values(uid,false,'{}',false,actor.id)
   on conflict(user_id) do update set all_warehouses=false,warehouse_ids='{}',can_transfer=false,transfer_from_primary=false,transfer_to_primary=false,transfer_other=false,revision=solar_private.warehouse_access.revision+1,updated_by=actor.id;
  end if;
  result:=jsonb_build_object('user',solar_private.staff_wizard_user(uid));
 elsif action='finalize' then
  role_name:=payload->>'role';new_active:=(payload->>'active')::boolean;requested_grants:=payload->'permissions';scope:=nullif(payload->'warehouse','null'::jsonb);
  if role_name is null or role_name not in('user','admin','installer','warehouse') or jsonb_typeof(payload->'active') is distinct from 'boolean'
   or jsonb_typeof(requested_grants) is distinct from 'object' then raise exception 'الدور أو الصلاحيات غير صحيحة' using errcode='22023';end if;
  if uid=actor.id and(not new_active or role_name<>'admin') then raise exception 'لا يمكن تعطيل حسابك أو إزالة دوره الإداري من هنا' using errcode='42501';end if;
  if exists(select 1 from jsonb_each(requested_grants) e where jsonb_typeof(e.value)<>'boolean' and (target.permissions->e.key) is distinct from e.value) then raise exception 'قيمة الصلاحية غير صالحة' using errcode='22023';end if;
  if scope is not null then
   dirs:=scope->'transferDirections';
   if jsonb_typeof(scope) is distinct from 'object' or jsonb_typeof(scope->'ids') is distinct from 'array' or jsonb_typeof(scope->'all') is distinct from 'boolean'
    or jsonb_typeof(dirs) is distinct from 'object' or exists(select 1 from unnest(array['fromPrimary','toPrimary','other']) k where jsonb_typeof(dirs->k) is distinct from 'boolean') then raise exception 'اختر مخازن واتجاهات نقل صحيحة' using errcode='22023';end if;
   select coalesce(array_agg(distinct v::bigint order by v::bigint),'{}'::bigint[]) into locations from jsonb_array_elements_text(scope->'ids') v;
   select * into before_scope from solar_private.warehouse_access a where a.user_id=uid for update;
   if exists(select 1 from unnest(locations) i where not exists(select 1 from solar_private.warehouses w where w.id=i and(w.active or i=any(coalesce(before_scope.warehouse_ids,'{}'::bigint[]))))) then raise exception 'اختر مخازن فعالة' using errcode='22023';end if;
   visible_scope:=jsonb_build_object('all',scope->'all','ids',to_jsonb(locations),'transferDirections',jsonb_build_object('fromPrimary',dirs->'fromPrimary','toPrimary',dirs->'toPrimary','other',dirs->'other'));
   scope_changed:=visible_scope is distinct from current_profile->'warehouse';
   if scope_changed then
    insert into solar_private.warehouse_access(user_id,all_warehouses,warehouse_ids,can_transfer,transfer_from_primary,transfer_to_primary,transfer_other,revision,updated_by)
    values(uid,(scope->>'all')::boolean,locations,(dirs->>'fromPrimary')::boolean or(dirs->>'toPrimary')::boolean or(dirs->>'other')::boolean,
     (dirs->>'fromPrimary')::boolean,(dirs->>'toPrimary')::boolean,(dirs->>'other')::boolean,1,actor.id)
    on conflict(user_id)do update set all_warehouses=excluded.all_warehouses,warehouse_ids=excluded.warehouse_ids,can_transfer=excluded.can_transfer,
     transfer_from_primary=excluded.transfer_from_primary,transfer_to_primary=excluded.transfer_to_primary,transfer_other=excluded.transfer_other,
     revision=solar_private.warehouse_access.revision+1,updated_by=actor.id,updated_at=clock_timestamp();
    insert into solar_private.warehouse_access_audit(actor_id,user_id,before_value,after_value)
     select actor.id,uid,to_jsonb(before_scope),to_jsonb(a) from solar_private.warehouse_access a where a.user_id=uid;
   end if;
  end if;
  update public.profiles set is_admin=role_name='admin',user_type=case when role_name='user' then 'admin_staff' else role_name end,
   active=new_active,permissions=case role_name when 'admin' then '{"all":true}'::jsonb
    when 'installer' then jsonb_build_object('installations',true,'layoutCustomize',requested_grants->'layoutCustomize'='true'::jsonb)
    when 'warehouse' then jsonb_build_object('warehouse',true,'stock',true,'stockMovement',true,'layoutCustomize',requested_grants->'layoutCustomize'='true'::jsonb)
    else requested_grants-'all' end,updated_at=clock_timestamp() where id=uid;
  result:=jsonb_build_object('user',solar_private.staff_wizard_user(uid));
 else
  if uid=actor.id then raise exception 'لا يمكن حذف حسابك' using errcode='42501';end if;
  update public.profiles set active=false,updated_at=clock_timestamp() where id=uid returning * into target;
  result:=jsonb_build_object('mode',case when solar_private.staff_has_history(uid) then 'archived' else 'candidate' end,'updatedAt',target.updated_at);
 end if;
 insert into solar_private.staff_admin_requests(request_id,actor_id,target_id,action,payload,response) values(request_id,actor.id,uid,action,payload,result);
 return result;
end$$;
revoke all on function solar_private.staff_wizard_user(uuid),solar_private.staff_has_history(uuid),solar_private.staff_wizard_delete_guard(),solar_private.staff_wizard_reuse_guard(), public.solar_admin_user_wizard(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.solar_admin_user_wizard(uuid,text,uuid,jsonb) to service_role;
-- Warehouse direction settings remain dormant when a staff role loses stock access.
create or replace function solar_private.transfer_direction_allowed(person uuid,source bigint,destination bigint)
returns boolean language sql stable security definer set search_path='' as $$
 select source<>destination and solar_private.warehouse_access_allowed(person,source) and solar_private.warehouse_access_allowed(person,destination)
 and exists(select 1 from public.profiles p where p.id=person and p.active and p.user_type<>'installer' and
 ((p.is_admin and p.user_type<>'warehouse') or ((p.user_type='warehouse' or solar_private.any_feature(p.permissions,'stock','stockMovement','warehouse')) and
 exists(select 1 from solar_private.warehouse_access a where a.user_id=p.id and
 case when source=solar_private.primary_warehouse() then a.transfer_from_primary when destination=solar_private.primary_warehouse() then a.transfer_to_primary else a.transfer_other end))))
$$;
notify pgrst,'reload schema';
