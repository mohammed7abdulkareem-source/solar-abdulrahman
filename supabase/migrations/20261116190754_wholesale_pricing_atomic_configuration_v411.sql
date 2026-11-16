-- V4.1.1: save the enabled state and user scope as one atomic operation.
-- pg-safeupdate remains enabled; only obsolete memberships are deleted.
-- Existing invoices, permissions, prices and financial history are untouched.
do $$begin
 if md5(pg_get_functiondef('solar_private.wholesale_pricing(text,uuid,jsonb)'::regprocedure))
  is distinct from '362562b065aded5dcb3ae38c1b27c624'then
  raise exception 'Wholesale V4.1 scope baseline changed';
 end if;
end$$;

CREATE OR REPLACE FUNCTION solar_private.wholesale_pricing(action text DEFAULT 'state'::text, request_id uuid DEFAULT NULL::uuid, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
#variable_conflict use_variable
declare actor public.profiles;c solar_private.wholesale_pricing_control;prior solar_private.finance_requests;t public.transactions;
 result jsonb;scope jsonb;entry jsonb;ids uuid[]:='{}';old_ids uuid[];mode text;expected numeric;changed boolean;before_value jsonb;
 recipient uuid;nid uuid;notified_count integer:=0;body text;target_enabled boolean;
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
 if action not in('scope','configure')then
  -- Old uncertain toggle retries retain their original acknowledgement. A new
  -- legacy toggle cannot enable a saved empty selection from the new UI.
  if action='toggle'and payload->'enabled'='true'::jsonb then
   select * into actor from public.profiles where id=auth.uid()and active and user_type not in('warehouse','installer');
   if actor.id is null or not(actor.is_admin or coalesce(actor.permissions->>'wholesalePricingManage','false')='true')then
    raise exception 'تعديل أسعار الجملة يحتاج صلاحية الإدارة'using errcode='42501';
   end if;
   perform pg_advisory_xact_lock(7311,1);
   if not exists(select 1 from solar_private.finance_requests f where f.request_id=wholesale_pricing.request_id)
    and exists(select 1 from solar_private.wholesale_pricing_control where id and scope_configured and scope_mode='selected')
    and not exists(select 1 from solar_private.wholesale_pricing_users)then
    raise exception 'اختر مستخدمًا واحدًا على الأقل قبل تفعيل أسعار الجملة'using errcode='22023';
   end if;
  end if;
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
  if prior.actor_id=actor.id and prior.action=('wholesale_pricing_'||action)and prior.payload=payload then
   -- Immutable acknowledgement plus a CURRENT protected state avoids restoring
   -- stale user targets/privileges during a delayed request retry.
   return solar_private.wholesale_pricing_state()||jsonb_build_object('changedCount',prior.response->'changedCount','notifiedCount',prior.response->'notifiedCount');
  end if;
  raise exception 'طلب مكرر ببيانات مختلفة'using errcode='PT409';
 end if;
 if action='configure'then
  if jsonb_typeof(payload->'enabled')is distinct from'boolean'then raise exception 'حالة تطبيق الأسعار غير صحيحة'using errcode='22023';end if;
  target_enabled:=(payload->>'enabled')::boolean;
 end if;
 mode:=payload->>'mode';
 if mode is null or mode not in('all','selected')or jsonb_typeof(payload->'userIds')is distinct from'array'
  or jsonb_typeof(payload->'expectedRevision')is distinct from'number' or jsonb_array_length(payload->'userIds')>500 then
  raise exception 'اختر نطاقًا ومستخدمين صحيحين'using errcode='22023';end if;
 expected:=(payload->>'expectedRevision')::numeric;
 if expected<0 or expected::text in('NaN','Infinity','-Infinity')or trunc(expected)<>expected then raise exception 'إصدار التسعير غير صحيح'using errcode='22023';end if;
 if (mode='selected'and jsonb_array_length(payload->'userIds')=0 and(action='scope'or target_enabled))or(mode='all'and jsonb_array_length(payload->'userIds')<>0)then
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
 if action='scope'then target_enabled:=c.enabled;end if;
 select coalesce(array_agg(user_id order by user_id),'{}')into old_ids from solar_private.wholesale_pricing_users;
 changed:=not c.scope_configured or c.enabled is distinct from target_enabled or c.scope_mode is distinct from mode or old_ids is distinct from ids;
 if changed then
  before_value:=jsonb_build_object('enabled',c.enabled,'scopeMode',c.scope_mode,'scopeConfigured',c.scope_configured,'userIds',to_jsonb(old_ids),'revision',c.revision);
  -- Target only removed memberships. Besides satisfying pg-safeupdate, this
  -- preserves the original selection time/actor of every unchanged member.
  delete from solar_private.wholesale_pricing_users u where not(u.user_id=any(ids));
  insert into solar_private.wholesale_pricing_users(user_id,selected_by)
   select id,actor.id from unnest(ids)id on conflict(user_id)do nothing;
  update solar_private.wholesale_pricing_control set enabled=target_enabled,scope_mode=mode,scope_configured=true,revision=revision+1,updated_at=now(),updated_by=actor.id where id;
  insert into solar_private.wholesale_pricing_audit(request_id,actor_id,action,before_value,after_value)
  values(request_id,actor.id,action,before_value,jsonb_build_object('enabled',target_enabled,'scopeMode',mode,'scopeConfigured',true,'userIds',to_jsonb(ids),'revision',c.revision+1));
  for recipient in select p.id from public.profiles p where p.active and p.user_type not in('warehouse','installer')and(p.is_admin or p.permissions->>'sale'='true'or p.permissions->>'wholesalePricingManage'='true')loop
   scope:=solar_private.wholesale_scope_effective(recipient,recipient);
   body:=case scope->>'reason'
    when'disabled'then'تم حفظ إعدادات المستخدمين. تطبيق أسعار الجملة متوقف حاليًا.'
    when'outside_scope'then'حسابك غير مشمول حاليًا بالأسعار الإلزامية للجملة؛ يمكنك البيع بسعر تختاره.'
    else'حسابك مشمول بالأسعار الإلزامية للجملة؛ أسعار المواد المحددة حد أدنى ويمكن البيع بسعر أعلى.'end;
   insert into public.solar_notifications(user_id,event,title,body)values(recipient,
    case when(scope->>'effectiveEnforced')::boolean then'operation_paused'else'operation_resumed'end,case when action='configure'then'تحديث إعدادات أسعار بيع الجملة'else'تحديث نطاق أسعار بيع الجملة'end,body)returning id into nid;
   insert into solar_private.push_deliveries(notification_id,endpoint)select nid,s.endpoint from public.solar_push_subscriptions s where s.user_id=recipient;
   notified_count:=notified_count+1;
  end loop;
  if notified_count>0 then perform solar_private.wake_push();end if;
 end if;
 result:=solar_private.wholesale_pricing_state()||jsonb_build_object('changedCount',case when changed then 1 else 0 end,'notifiedCount',notified_count);
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response)values(request_id,actor.id,'wholesale_pricing_'||action,payload,result);
 return result;
end$function$

;
notify pgrst,'reload schema';
