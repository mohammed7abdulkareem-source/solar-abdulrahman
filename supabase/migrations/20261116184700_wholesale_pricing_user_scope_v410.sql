-- A first explicit scope save makes this page authoritative for future price
-- decisions. Until then the existing admin/free-pricing behavior is preserved.
-- No profiles, historical receipts, quantities, costs or balances are rewritten.
do $$declare f record;begin
 for f in select * from(values
  ('solar_private.wholesale_pricing(text,uuid,jsonb)','860b7bc72a4ea0600be0aa8ac722bb21'),
  ('solar_private.wholesale_pricing_state()','882f4baa86d52089d9228b54a2aed801'),
  ('solar_private.assert_wholesale_pricing(bigint,bigint)','65d406ea0af91e1870c7ed464c5414ec')
 )x(signature,hash)loop
  if md5(pg_get_functiondef(f.signature::regprocedure))is distinct from f.hash then
   raise exception 'Wholesale scope baseline changed: %',f.signature;
  end if;
 end loop;
end$$;

alter table solar_private.wholesale_pricing_control add column scope_mode text not null default 'all' check(scope_mode in('all','selected')),
 add column scope_configured boolean not null default false;
create table solar_private.wholesale_pricing_users(
 user_id uuid primary key references public.profiles(id)on delete cascade,
 selected_at timestamptz not null default now(),selected_by uuid references public.profiles(id)on delete set null
);
alter table solar_private.wholesale_pricing_users enable row level security;
revoke all on solar_private.wholesale_pricing_users from public,anon,authenticated;

create function solar_private.wholesale_scope_effective(subject_id uuid,actor_id uuid)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare c solar_private.wholesale_pricing_control;actor public.profiles;applies boolean;legacy_override boolean;can_override boolean;reason text;begin
 select * into c from solar_private.wholesale_pricing_control where id;
 select * into actor from public.profiles where id=actor_id and active and user_type not in('warehouse','installer');
 legacy_override:=actor.id is not null and(actor.is_admin or coalesce(actor.permissions->>'wholesaleFreePricing','false')='true');
 -- An unidentified legacy owner cannot evade a selected-user policy by becoming
 -- NULL. Accepted historical economics are exempt before this helper is called.
 applies:=not c.scope_configured or c.scope_mode='all' or subject_id is null
  or exists(select 1 from solar_private.wholesale_pricing_users u where u.user_id=subject_id);
 can_override:=not c.scope_configured and legacy_override;
 reason:=case when not c.enabled then'disabled'when not applies then'outside_scope'when can_override then'override'else'required'end;
 return jsonb_build_object('scopeMode',c.scope_mode,'scopeConfigured',c.scope_configured,'appliesToSubject',applies,
  'canOverride',can_override,'legacyCanOverride',legacy_override,'effectiveEnforced',c.enabled and applies and not can_override,'reason',reason);
end$$;
revoke all on function solar_private.wholesale_scope_effective(uuid,uuid)from public,anon,authenticated;

alter function solar_private.wholesale_pricing_state()rename to wholesale_pricing_state_v410_notices;
revoke all on function solar_private.wholesale_pricing_state_v410_notices()from public,anon,authenticated;
create function solar_private.wholesale_pricing_state()returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare result jsonb;scope jsonb;users jsonb;selected_ids jsonb;begin
 result:=solar_private.wholesale_pricing_state_v410_notices();
 scope:=solar_private.wholesale_scope_effective(auth.uid(),auth.uid());
 result:=result||scope||jsonb_build_object('appliesToCurrentUser',scope->'appliesToSubject','pricingSubjectId',auth.uid(),
  'pricingSubjectName',(select solar_private.user_name(display_name,username,honorific)from public.profiles where id=auth.uid()));
 if coalesce((result->>'canManage')::boolean,false)then
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',solar_private.user_name(p.display_name,p.username,p.honorific),
   'isAdmin',p.is_admin,'selected',u.user_id is not null,'appliesToScope',rule->'appliesToSubject',
   'canOverride',rule->'canOverride','legacyCanOverride',rule->'legacyCanOverride','effectiveEnforced',rule->'effectiveEnforced','reason',rule->>'reason')order by solar_private.user_name(p.display_name,p.username,p.honorific),p.id),'[]'),
   coalesce(jsonb_agg(p.id order by p.id)filter(where u.user_id is not null),'[]') into users,selected_ids
  from public.profiles p left join solar_private.wholesale_pricing_users u on u.user_id=p.id
  cross join lateral(select solar_private.wholesale_scope_effective(p.id,p.id)rule)s
  where p.active and p.user_type not in('warehouse','installer')and(p.is_admin or coalesce(p.permissions->>'sale','false')='true');
  result:=result||jsonb_build_object('eligibleUsers',users,'selectedUserIds',selected_ids);
 end if;
 return result;
end$$;
revoke all on function solar_private.wholesale_pricing_state()from public,anon,authenticated;

-- A saved sale cannot be reassigned to an unselected user to evade its
-- owner's policy. New authorized on-behalf creation remains unchanged.
create function solar_private.guard_wholesale_scope_owner()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if old.kind='sale'and new.created_by is distinct from old.created_by then
  perform pg_advisory_xact_lock(7311,1);
  if exists(select 1 from solar_private.wholesale_pricing_control where id and scope_configured)then
   raise exception 'صاحب فاتورة الجملة المحفوظ ثابت؛ نقل الأرباح يتم من الإجراء المخصص'using errcode='42501';
  end if;
 end if;return new;
end$$;
revoke all on function solar_private.guard_wholesale_scope_owner()from public,anon,authenticated;
create trigger solar_wholesale_scope_owner before update of created_by on public.transactions for each row execute function solar_private.guard_wholesale_scope_owner();

-- Canonical invoice saves and every deferred row guard share the same rule.
-- This deliberately uses the receipt OWNER, not the actor editing/preparing it.
do $$declare definition text;needle text;begin
 definition:=pg_get_functiondef('solar_private.assert_wholesale_pricing(bigint,bigint)'::regprocedure);
 needle:='signature jsonb;gross numeric;';
 if strpos(definition,needle)=0 then raise exception 'Wholesale guard declarations changed';end if;
 definition:=replace(definition,needle,'scope jsonb;signature jsonb;gross numeric;');
 needle:=$n$override_allowed:=actor.id is not null and actor.user_type not in('warehouse','installer')and(actor.is_admin or coalesce(actor.permissions->>'wholesaleFreePricing','false')='true');$n$;
 if strpos(definition,needle)=0 then raise exception 'Wholesale override guard changed';end if;
 definition:=replace(definition,needle,$n$scope:=solar_private.wholesale_scope_effective(invoice.created_by,auth.uid());override_allowed:=(scope->>'canOverride')::boolean;$n$);
 definition:=replace(definition,'if control.enabled and expected_revision is not null and control.revision is distinct from expected_revision then',
  'if expected_revision is not null and control.revision is distinct from expected_revision then');
 definition:=replace(definition,'if control.enabled and not override_allowed then','if (scope->>''effectiveEnforced'')::boolean then');
 execute definition;
end$$;

alter function solar_private.wholesale_pricing(text,uuid,jsonb)rename to wholesale_pricing_v410_notices;
revoke all on function solar_private.wholesale_pricing_v410_notices(text,uuid,jsonb)from public,anon,authenticated;
-- Preserve the renamed PL/pgSQL block's parameter qualification.
do $$declare definition text;begin
 definition:=replace(pg_get_functiondef('solar_private.wholesale_pricing_v410_notices(text,uuid,jsonb)'::regprocedure),
  'wholesale_pricing.request_id','wholesale_pricing_v410_notices.request_id');
 definition:=replace(definition,$old$'تم تفعيل الحد الأدنى للمواد المحددة في بيع الجملة. الأسعار الأعلى مسموحة، وتبقى صلاحية البيع الحر مستقلة.'$old$,$new$ case when control.scope_configured then'تم تفعيل الحد الأدنى للمواد المحددة في بيع الجملة. الأسعار الأعلى مسموحة، ويُطبّق الإلزام بحسب نطاق المستخدمين المحفوظ واختيار هذا النطاق هو المعتمد.'else'تم تفعيل الحد الأدنى للمواد المحددة في بيع الجملة. الأسعار الأعلى مسموحة، وتبقى صلاحية البيع الحر مستقلة.'end $new$);
 execute definition;
end$$;
create function solar_private.wholesale_pricing(action text default 'state',request_id uuid default null,payload jsonb default '{}')returns jsonb
language plpgsql security definer set search_path=''set lock_timeout='5s'as $$
#variable_conflict use_variable
declare actor public.profiles;c solar_private.wholesale_pricing_control;prior solar_private.finance_requests;t public.transactions;
 result jsonb;scope jsonb;entry jsonb;ids uuid[]:='{}';old_ids uuid[];mode text;expected numeric;changed boolean;before_value jsonb;
 recipient uuid;nid uuid;notified_count integer:=0;body text;
begin
 if action is null or jsonb_typeof(payload)is distinct from'object'then raise exception 'طلب تسعير غير صحيح'using errcode='22023';end if;
 if action='state'then
  result:=solar_private.wholesale_pricing_state();
  if nullif(payload->>'invoiceId','')is not null then
   select * into t from public.transactions where id=(payload->>'invoiceId')::bigint and kind='sale';
   if t.id is null or not solar_private.can_access_invoice(t.created_by,false)then raise exception 'وصل الجملة غير متاح ضمن صلاحياتك'using errcode='42501';end if;
   scope:=solar_private.wholesale_scope_effective(t.created_by,auth.uid());
   result:=result||scope||jsonb_build_object('pricingSubjectId',t.created_by,
    'pricingSubjectName',(select solar_private.user_name(display_name,username,honorific)from public.profiles where id=t.created_by));
  end if;
  return result;
 end if;
 if action<>'scope'then
  result:=solar_private.wholesale_pricing_v410_notices(action,request_id,payload);
  return result||solar_private.wholesale_pricing_state();
 end if;
 select * into actor from public.profiles where id=auth.uid()and active and user_type not in('warehouse','installer');
 if actor.id is null or not(actor.is_admin or coalesce(actor.permissions->>'wholesalePricingManage','false')='true')then
  raise exception 'تحديد المستخدمين يحتاج صلاحية إدارة أسعار الجملة'using errcode='42501';end if;
 if request_id is null then raise exception 'معرّف الحفظ مطلوب'using errcode='22023';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into prior from solar_private.finance_requests f where f.request_id=wholesale_pricing.request_id;
 if found then
  if prior.actor_id=actor.id and prior.action='wholesale_pricing_scope'and prior.payload=payload then
   -- Immutable acknowledgement plus a CURRENT protected state avoids restoring
   -- stale user targets/privileges during a delayed request retry.
   return solar_private.wholesale_pricing_state()||jsonb_build_object('changedCount',prior.response->'changedCount','notifiedCount',prior.response->'notifiedCount');
  end if;
  raise exception 'طلب مكرر ببيانات مختلفة'using errcode='PT409';
 end if;
 mode:=payload->>'mode';
 if mode is null or mode not in('all','selected')or jsonb_typeof(payload->'userIds')is distinct from'array'
  or jsonb_typeof(payload->'expectedRevision')is distinct from'number' or jsonb_array_length(payload->'userIds')>500 then
  raise exception 'اختر نطاقًا ومستخدمين صحيحين'using errcode='22023';end if;
 expected:=(payload->>'expectedRevision')::numeric;
 if expected<0 or expected::text in('NaN','Infinity','-Infinity')or trunc(expected)<>expected then raise exception 'إصدار التسعير غير صحيح'using errcode='22023';end if;
 if (mode='selected'and jsonb_array_length(payload->'userIds')=0)or(mode='all'and jsonb_array_length(payload->'userIds')<>0)then
  raise exception 'اختر مستخدمًا واحدًا على الأقل للنطاق المحدد، أو اختر الجميع دون قائمة'using errcode='22023';end if;
 for entry in select value from jsonb_array_elements(payload->'userIds')loop
  if jsonb_typeof(entry)is distinct from'string'or(entry#>>'{}')!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'then
   raise exception 'أحد معرّفات المستخدمين غير صحيح'using errcode='22023';end if;
  ids:=array_append(ids,(entry#>>'{}')::uuid);
 end loop;
 if cardinality(ids)<>(select count(distinct id)from unnest(ids)id)then raise exception 'المستخدم مكرر في النطاق'using errcode='22023';end if;
 select coalesce(array_agg(id order by id),'{}')into ids from unnest(ids)id;
 if exists(select 1 from unnest(ids)target where not exists(select 1 from public.profiles p where p.id=target and p.active and p.user_type not in('warehouse','installer')and(p.is_admin or coalesce(p.permissions->>'sale','false')='true')))then
  raise exception 'اختر فقط مستخدمي بيع الجملة الفعالين'using errcode='PT409';end if;
 select * into c from solar_private.wholesale_pricing_control where id for update;
 if c.revision is distinct from expected::bigint then raise exception 'تغيّر نطاق أو أسعار الجملة؛ حدّث الصفحة وأعد التأكيد'using errcode='PT409';end if;
 select coalesce(array_agg(user_id order by user_id),'{}')into old_ids from solar_private.wholesale_pricing_users;
 changed:=not c.scope_configured or c.scope_mode is distinct from mode or old_ids is distinct from ids;
 if changed then
  before_value:=jsonb_build_object('scopeMode',c.scope_mode,'scopeConfigured',c.scope_configured,'userIds',to_jsonb(old_ids),'revision',c.revision);
  delete from solar_private.wholesale_pricing_users;
  insert into solar_private.wholesale_pricing_users(user_id,selected_by)select id,actor.id from unnest(ids)id;
  update solar_private.wholesale_pricing_control set scope_mode=mode,scope_configured=true,revision=revision+1,updated_at=now(),updated_by=actor.id where id;
  insert into solar_private.wholesale_pricing_audit(request_id,actor_id,action,before_value,after_value)
  values(request_id,actor.id,'scope',before_value,jsonb_build_object('scopeMode',mode,'scopeConfigured',true,'userIds',to_jsonb(ids),'revision',c.revision+1));
  for recipient in select p.id from public.profiles p where p.active and p.user_type not in('warehouse','installer')and(p.is_admin or p.permissions->>'sale'='true'or p.permissions->>'wholesalePricingManage'='true')loop
   scope:=solar_private.wholesale_scope_effective(recipient,recipient);
   body:=case scope->>'reason'
    when'disabled'then'تم حفظ نطاق المستخدمين. تطبيق أسعار الجملة متوقف حاليًا.'
    when'outside_scope'then'حسابك غير مشمول حاليًا بالأسعار الإلزامية للجملة؛ يمكنك البيع بسعر تختاره.'
    else'حسابك مشمول بالأسعار الإلزامية للجملة؛ أسعار المواد المحددة حد أدنى ويمكن البيع بسعر أعلى.'end;
   insert into public.solar_notifications(user_id,event,title,body)values(recipient,
    case when(scope->>'effectiveEnforced')::boolean then'operation_paused'else'operation_resumed'end,'تحديث نطاق أسعار بيع الجملة',body)returning id into nid;
   insert into solar_private.push_deliveries(notification_id,endpoint)select nid,s.endpoint from public.solar_push_subscriptions s where s.user_id=recipient;
   notified_count:=notified_count+1;
  end loop;
  if notified_count>0 then perform solar_private.wake_push();end if;
 end if;
 result:=solar_private.wholesale_pricing_state()||jsonb_build_object('changedCount',case when changed then 1 else 0 end,'notifiedCount',notified_count);
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response)values(request_id,actor.id,'wholesale_pricing_scope',payload,result);
 return result;
end$$;
revoke all on function solar_private.wholesale_pricing(text,uuid,jsonb)from public,anon;
grant execute on function solar_private.wholesale_pricing(text,uuid,jsonb)to authenticated;
create or replace function public.solar_wholesale_pricing(action text default 'state',request_id uuid default null,payload jsonb default '{}')returns jsonb
language sql security invoker set search_path=''as $$select solar_private.wholesale_pricing(action,request_id,payload)$$;
notify pgrst,'reload schema';
