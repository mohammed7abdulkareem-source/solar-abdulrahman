-- Existing customers and opening entries are retained. Future duplicates are
-- blocked under the same transaction lock used by customer/invoice writes.
alter table public.customers add column customer_revision bigint not null default 0;
create function solar_private.customer_name_key(value text) returns text language sql immutable parallel safe set search_path='' as $$
 select regexp_replace(translate(lower(normalize(coalesce(value,''),NFKC)),
 'أإآٱى٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','ااااي01234567890123456789'),'[[:space:]ً-ٰٟـ​‌‍‎‏﻿]','','g')
$$;
create function solar_private.customer_phone_key(value text) returns text language plpgsql immutable parallel safe set search_path='' as $$
declare digits text;begin
 digits:=regexp_replace(translate(coalesce(value,''),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789'),'[^0-9]','','g');
 if left(digits,2)='00' then digits:=substr(digits,3);end if;
 if left(digits,4)='9640' then digits:='964'||substr(digits,5);end if;
 if digits~'^07[0-9]{9}$' then digits:='964'||substr(digits,2);elsif digits~'^7[0-9]{9}$' then digits:='964'||digits;end if;
 return case when length(digits)>=7 then digits else '' end;
end $$;
create index solar_customer_name_lookup on public.customers(solar_private.customer_name_key(name));
create index solar_customer_phone_lookup on public.customers(solar_private.customer_phone_key(phone));

create table solar_private.customer_changes(
 request_id uuid primary key, actor_id uuid not null, action text not null,
 customer_id bigint not null, payload jsonb not null, before_customer jsonb,
 after_customer jsonb, before_opening numeric not null, after_opening numeric not null,
 before_entries jsonb not null default '[]'::jsonb, result jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table solar_private.customer_changes enable row level security;
revoke all on solar_private.customer_changes from public,anon,authenticated;

create function solar_private.customer_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare p public.profiles; nk text; pk text; check_name boolean; check_phone boolean;
begin
 perform pg_advisory_xact_lock(7311,1);
 if current_setting('role',true) in ('authenticated','anon') then
  select * into p from public.profiles where id=auth.uid() and active;
  if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'customers','false')='true') then raise exception 'لا تملك صلاحية إدارة الزبائن' using errcode='42501';end if;
  if not p.is_admin then
   if tg_op<>'INSERT' and old.owner_id is distinct from p.id then raise exception 'لا تملك صلاحية هذا الزبون' using errcode='42501';end if;
   if tg_op<>'DELETE' and new.owner_id is distinct from p.id then raise exception 'تغيير المستخدم المسؤول للأدمن فقط' using errcode='42501';end if;
  end if;
 end if;
 if tg_op='DELETE' then
  if exists(select 1 from public.transactions t where t.kind in ('sale','system','customer_payment','system_payment') and (t.party_id=old.id or (t.party_id is null and t.party_name=old.name))) then raise exception 'للزبون حركات حساب محفوظة؛ لا يمكن حذفه';end if;
  return old;
 end if;
 new.name:=regexp_replace(trim(new.name),'[[:space:]]+',' ','g');new.phone:=trim(coalesce(new.phone,''));
 nk:=solar_private.customer_name_key(new.name);pk:=solar_private.customer_phone_key(new.phone);
 if length(nk)<2 or length(new.name)>150 or length(new.phone)>40 then raise exception 'أدخل اسم زبون ورقم هاتف صحيحين';end if;
 check_name:=tg_op='INSERT';check_phone:=tg_op='INSERT';
 if tg_op='UPDATE' then
  check_name:=nk is distinct from solar_private.customer_name_key(old.name);
  check_phone:=pk is distinct from solar_private.customer_phone_key(old.phone);
  new.customer_revision:=old.customer_revision+1;
 end if;
 if check_name and exists(select 1 from public.customers c where c.id<>new.id and solar_private.customer_name_key(c.name)=nk) then raise exception 'اسم الزبون مسجل مسبقاً. ابحث عنه وافتح حسابه بدلاً من إضافته مرة ثانية.' using errcode='23505';end if;
 if check_phone and pk<>'' and exists(select 1 from public.customers c where c.id<>new.id and solar_private.customer_phone_key(c.phone)=pk) then raise exception 'رقم الهاتف مسجل لزبون موجود. افتح حسابه بدلاً من تكراره.' using errcode='23505';end if;
 return new;
end $$;
create trigger solar_customer_guard before insert or update or delete on public.customers for each row execute function solar_private.customer_guard();

create function solar_private.customer_get(customer_id bigint) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; c public.customers; rows jsonb; opening numeric; balance numeric;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 select * into c from public.customers where id=customer_id;
 if p.id is null or p.user_type in ('installer','warehouse') or c.id is null or not(p.is_admin or (coalesce(p.permissions->>'customers','false')='true' and coalesce(c.owner_id=p.id,false))) then raise exception 'لا تملك صلاحية هذا الزبون' using errcode='42501';end if;
 rows:=solar_private.customer_ledger(c.id);
 select coalesce(sum((v->>'effect')::numeric) filter(where v->>'mode'='opening_balance'),0),coalesce(sum((v->>'effect')::numeric),0) into opening,balance from jsonb_array_elements(rows) v;
 return jsonb_build_object('id',c.id,'name',c.name,'phone',coalesce(c.phone,''),'customerType',c.customer_type,'ownerId',c.owner_id,
 'ownerName',(select coalesce(x.display_name,x.username) from public.profiles x where x.id=c.owner_id),'openingBalance',opening,'balance',balance,
 'openingCount',(select count(*) from jsonb_array_elements(rows) v where v->>'mode'='opening_balance'),'rows',rows,'createdAt',c.created_at,
 'token',md5(to_jsonb(c)::text||rows::text),'revision',c.customer_revision);
end $$;
create function solar_private.customer_directory() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; result jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'customers','false')='true') then raise exception 'لا تملك صلاحية الزبائن' using errcode='42501';end if;
 select coalesce(jsonb_agg(solar_private.customer_get(c.id)-'rows'-'token' order by c.created_at desc,c.id desc),'[]'::jsonb) into result
 from public.customers c where c.active and (p.is_admin or c.owner_id=p.id);
 return result;
end $$;
create function solar_private.customer_check(customer_name text,phone text,exclude_id bigint default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; result jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'customers','false')='true') then raise exception 'لا تملك صلاحية الزبائن' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('reason',case when solar_private.customer_name_key(c.name)=solar_private.customer_name_key(customer_name) then 'name' else 'phone' end,
 'id',case when p.is_admin or c.owner_id=p.id then c.id end,'name',case when p.is_admin or c.owner_id=p.id then c.name end)), '[]'::jsonb) into result
 from public.customers c where c.id is distinct from exclude_id and
 ((solar_private.customer_name_key(customer_name)<>'' and solar_private.customer_name_key(c.name)=solar_private.customer_name_key(customer_name)) or
 (solar_private.customer_phone_key(customer_check.phone)<>'' and solar_private.customer_phone_key(c.phone)=solar_private.customer_phone_key(customer_check.phone)));
 return result;
end $$;

create function solar_private.customer_save(action text,request_id uuid,payload jsonb) returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare p public.profiles; c public.customers; prior solar_private.customer_changes; result jsonb; before_record jsonb; entries jsonb;
 rows jsonb; before_opening numeric:=0; target numeric; difference numeric; opening_id bigint; owner uuid; new_name text; movement_id bigint;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'customers','false')='true') then raise exception 'لا تملك صلاحية إدارة الزبائن' using errcode='42501';end if;
 if request_id is null or action is null or action not in ('create','update','delete') or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب غير صحيح';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into prior from solar_private.customer_changes x where x.request_id=customer_save.request_id;
 if prior.request_id is not null then
  if prior.actor_id<>p.id or prior.action<>action or prior.payload is distinct from payload then raise exception 'طلب مكرر ببيانات مختلفة' using errcode='40001';end if;
  if action<>'delete' and not exists(select 1 from public.customers x where x.id=prior.customer_id) then raise exception 'تغيرت البيانات؛ حدّث الصفحة' using errcode='40001';end if;
  return prior.result;
 end if;
 if action='create' then
  if payload->>'customerType' is null or payload->>'customerType' not in ('system','wholesale') then raise exception 'اختر نوع الزبون';end if;
  perform solar_private.reconcile('create_customer',request_id,payload);
  select * into c from public.customers where id=(payload->>'id')::bigint;
  before_record:=null;entries:='[]'::jsonb;target:=coalesce((payload->>'openingBalance')::numeric,0);
 else
  select * into c from public.customers where id=(payload->>'id')::bigint for update;
  if c.id is null or not(p.is_admin or coalesce(c.owner_id=p.id,false)) then raise exception 'لا تملك صلاحية هذا الزبون' using errcode='42501';end if;
  before_record:=solar_private.customer_get(c.id);
  if before_record->>'token' is distinct from payload->>'token' then raise exception 'تغير حساب الزبون أو بياناته. حدّث البيانات وافتح التعديل مجدداً.' using errcode='40001';end if;
  before_opening:=(before_record->>'openingBalance')::numeric;
  rows:=before_record->'rows';
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at,t.id),'[]'::jsonb) into entries from public.transactions t where t.id in (select (v->>'id')::bigint from jsonb_array_elements(rows) v where v->>'mode'='opening_balance');
  if action='delete' then
   if jsonb_array_length(rows)>0 then raise exception 'للزبون حركات حساب محفوظة؛ لا يمكن حذفه';end if;
   delete from public.customers where id=c.id;target:=0;result:=jsonb_build_object('id',c.id,'deleted',true);
  else
   target:=coalesce((payload->>'openingBalance')::numeric,0);
   if target::text in ('NaN','Infinity','-Infinity') or not(target between -1000000000000000 and 1000000000000000) or round(target,2)<>target then raise exception 'أدخل رصيداً افتتاحياً صحيحاً';end if;
   owner:=case when p.is_admin then coalesce(nullif(payload->>'ownerId','')::uuid,c.owner_id,p.id) else p.id end;
   if not exists(select 1 from public.profiles where id=owner and active and user_type not in ('installer','warehouse')) then raise exception 'اختر مستخدماً مسؤولاً فعالاً';end if;
   if payload->>'customerType' is null or payload->>'customerType' not in ('system','wholesale') then raise exception 'اختر نوع الزبون';end if;
   new_name:=regexp_replace(trim(payload->>'name'),'[[:space:]]+',' ','g');
   if new_name is distinct from c.name then
    if (select count(*) from public.customers x where x.name=c.name)>1 and exists(select 1 from public.transactions t where t.party_id is null and t.party_name=c.name and t.kind in ('sale','system','customer_payment','system_payment')) then raise exception 'يوجد اسم قديم متكرر بحركات غير محددة؛ راجع الإدارة قبل تغيير الاسم';end if;
    -- Attach unambiguous legacy entries before a rename; keep their creator,
    -- cash owner, amounts and dates unchanged.
    update public.transactions t set party_id=c.id,party_type='customer',party_name=new_name where t.kind in ('sale','system','customer_payment','system_payment') and
    (t.party_id=c.id or(t.party_id is null and t.party_name=c.name and(select count(*) from public.customers x where x.name=c.name)=1));
   end if;
   update public.customers set name=new_name,phone=coalesce(payload->>'phone',''),customer_type=payload->>'customerType',owner_id=owner where id=c.id;
   difference:=target-before_opening;
   if difference<>0 then
    select t.id into opening_id from public.transactions t where t.id in(select (v->>'id')::bigint from jsonb_array_elements(rows) v where v->>'mode'='opening_balance') order by t.created_at desc,t.id desc limit 1 for update;
    if opening_id is not null then
     update public.transactions set total=total-difference,notes='رصيد افتتاحي — تم تعديله مع حفظ سجل التغيير' where id=opening_id;
    else
     movement_id:=floor(extract(epoch from clock_timestamp())*1000000)::bigint;
     while exists(select 1 from public.transactions t where t.id=movement_id) loop movement_id:=movement_id+1;end loop;
     insert into public.transactions(id,kind,party_type,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,notes,created_at)
     values(movement_id,case when payload->>'customerType'='system' then 'system_payment' else 'customer_payment' end,'customer',c.id,new_name,-target,false,'opening_balance',p.id,p.id,'رصيد افتتاحي — أضيف من تعديل الزبون',c.created_at);
    end if;
   end if;
  end if;
 end if;
 if action<>'delete' then result:=solar_private.customer_get(c.id);end if;
 insert into solar_private.customer_changes(request_id,actor_id,action,customer_id,payload,before_customer,after_customer,before_opening,after_opening,before_entries,result)
 values(request_id,p.id,action,c.id,payload,before_record,case when action<>'delete' then result end,before_opening,target,entries,result);
 return result;
end $$;

create function public.solar_customer_directory() returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.customer_directory()$$;
create function public.solar_customer_get(customer_id bigint) returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.customer_get(customer_id)$$;
create function public.solar_customer_check(customer_name text,phone text,exclude_id bigint default null) returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.customer_check(customer_name,phone,exclude_id)$$;
create function public.solar_customer_save(action text,request_id uuid,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select solar_private.customer_save(action,request_id,payload)$$;
revoke all on function solar_private.customer_get(bigint),solar_private.customer_directory(),solar_private.customer_check(text,text,bigint),solar_private.customer_save(text,uuid,jsonb) from public,anon;
grant execute on function solar_private.customer_get(bigint),solar_private.customer_directory(),solar_private.customer_check(text,text,bigint),solar_private.customer_save(text,uuid,jsonb) to authenticated;
revoke all on function public.solar_customer_get(bigint),public.solar_customer_directory(),public.solar_customer_check(text,text,bigint),public.solar_customer_save(text,uuid,jsonb) from public,anon;
grant execute on function public.solar_customer_get(bigint),public.solar_customer_directory(),public.solar_customer_check(text,text,bigint),public.solar_customer_save(text,uuid,jsonb) to authenticated;
revoke all on function solar_private.customer_guard() from public,anon,authenticated;
revoke all on function solar_private.customer_name_key(text),solar_private.customer_phone_key(text) from public,anon;
grant execute on function solar_private.customer_name_key(text),solar_private.customer_phone_key(text) to authenticated;

-- Audit is included in protected backups and retained across a work-data reset.
do $$declare definition text;begin
 if to_regprocedure('solar_private.reset_snapshot()') is not null then
  select pg_get_functiondef('solar_private.reset_snapshot()'::regprocedure) into definition;
  definition:=replace(definition,'''solar_private.stock_adjustments''','''solar_private.customer_changes'',''solar_private.stock_adjustments''');execute definition;
 end if;
end $$;
