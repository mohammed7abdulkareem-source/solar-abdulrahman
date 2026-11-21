-- Changes responsibility for an existing account under the same lock and
-- optimistic token as the customer editor. Historical documents keep their IDs.
create function solar_private.customer_transfer_targets() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare choices jsonb;
begin
 if solar_private.role_name() is distinct from 'admin' then
  raise exception 'نقل مسؤولية العميل متاح للأدمن فقط' using errcode='42501';
 end if;
 with eligible as (
  select p.id,coalesce(solar_private.user_name(p.display_name,p.username,p.honorific),'مستخدم') as label,
         nullif(btrim(p.username),'') as username
   from public.profiles p where p.active and p.user_type not in ('warehouse','installer')
 ), counted as (
  select e.*,count(*) over(partition by solar_private.customer_name_key(label)) as same_label,
         count(*) over(partition by solar_private.customer_name_key(label),lower(username)) as same_login
   from eligible e
 ), choices_by_id as (
  select id,case when same_label=1 then label
                 when username is not null and same_login=1 then label||' · @'||username
                 else label||' · '||id::text end as name
   from counted
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name,id),'[]'::jsonb)
  into choices from choices_by_id;
 return choices;
end $$;
create function public.solar_customer_transfer_targets() returns jsonb
language sql stable security invoker set search_path='' as $$select solar_private.customer_transfer_targets()$$;
revoke all on function solar_private.customer_transfer_targets(),public.solar_customer_transfer_targets() from public,anon,authenticated;
grant execute on function solar_private.customer_transfer_targets(),public.solar_customer_transfer_targets() to authenticated;

do $migration$
declare definition text;
begin
 definition:=pg_get_functiondef('solar_private.customer_save(text,uuid,jsonb)'::regprocedure);
 if md5(definition)<>'bef5a174a32fca71007fc4e15da8d300' then raise exception 'Review current customer writer before adding owner transfer'; end if;
 definition:=replace(definition, 'action not in (''create'',''update'',''delete'',''rename'')',
  'action not in (''create'',''update'',''delete'',''rename'',''transfer_owner'')');
 definition:=replace(definition, ' perform pg_advisory_xact_lock(7311,1);', $step$
 perform pg_advisory_xact_lock(7311,1);
 if action='transfer_owner' then
  perform 1 from public.profiles where id=auth.uid() and active and is_admin and user_type not in ('warehouse','installer') for share;
  if not found then raise exception 'نقل مسؤولية العميل متاح للأدمن فقط' using errcode='42501'; end if;
 end if;$step$);
 -- A former manager cannot replay a saved customer snapshot after handoff.
 definition:=replace(definition,'if action=''rename'' and not exists (','if action<>''delete'' and not exists (');
 definition:=replace(definition,'  return prior.result;', $step$
  if action='transfer_owner' and prior.result->>'ownerId' is distinct from
   (select x.owner_id::text from public.customers x where x.id=prior.customer_id) then
   raise exception 'تغيّر المستخدم المسؤول بعد هذه العملية. حدّث الكشف لرؤية المسؤول الحالي.' using errcode='PT409';
  end if;
  return prior.result;$step$);
 definition:=replace(definition,'  if action=''rename'' then', $step$
  if action='transfer_owner' then
   owner:=nullif(payload->>'ownerId','')::uuid;
   select jsonb_build_object('id',c.id,'name',c.name,'ownerId',u.id,
          'ownerName',coalesce(solar_private.user_name(u.display_name,u.username,u.honorific),'مستخدم'))
    into result
    from public.profiles u where u.id=owner and u.active and u.user_type not in ('warehouse','installer') for share of u;
   if not found then raise exception 'اختر مستخدماً مسؤولاً فعالاً' using errcode='22023'; end if;
   if c.owner_id=owner then raise exception 'هذا المستخدم مسؤول عن العميل حالياً' using errcode='22023'; end if;
   update public.customers set owner_id=owner where id=c.id;
   insert into solar_private.customer_changes(request_id,actor_id,action,customer_id,payload,before_customer,after_customer,before_opening,after_opening,result)
    values(request_id,p.id,action,c.id,payload,
     jsonb_build_object('id',c.id,'name',c.name,'ownerId',c.owner_id,'ownerName',before_record->>'ownerName'),
     result,before_opening,before_opening,result);
   return result;
  end if;
  if action='rename' then$step$);
 -- A legacy full edit must retain an omitted opening amount. Raw opening IDs
 -- are needed for private bookkeeping, even when receipt details are redacted.
 definition:=replace(definition,'  rows:=before_record->''rows'';', '  rows:=solar_private.customer_ledger(c.id);');
 definition:=replace(definition,'   target:=coalesce((payload->>''openingBalance'')::numeric,0);', $step$
   if not p.is_admin and payload ? 'ownerId' and nullif(payload->>'ownerId','')::uuid is distinct from p.id then
    raise exception 'نقل مسؤولية العميل متاح للأدمن فقط' using errcode='42501';
   end if;
   target:=case when payload ? 'openingBalance' then coalesce((payload->>'openingBalance')::numeric,0) else before_opening end;$step$);
 -- Correct the aggregate opening without rewriting another user's private
 -- opening entry. Where no editable opening exists, post only the difference.
 definition:=replace(definition,
  'from jsonb_array_elements(rows) v where v->>''mode''=''opening_balance'') order by t.created_at desc,t.id desc limit 1 for update;',
  'from jsonb_array_elements(rows) v where v->>''mode''=''opening_balance'') and (p.is_admin or t.created_by=p.id) order by t.created_at desc,t.id desc limit 1 for update;');
 definition:=replace(definition,'''customer'',c.id,new_name,-target,false,''opening_balance''',
  '''customer'',c.id,new_name,-difference,false,''opening_balance''');
 -- The normal full edit has the same eligibility rule as the transfer control.
 definition:=replace(definition,'where id=owner and active and user_type not in (''installer'',''warehouse'')) then', 'where id=owner and active and user_type not in (''installer'',''warehouse'') for share) then');
 execute definition;

 definition:=pg_get_functiondef('solar_private.reconcile(text,uuid,jsonb)'::regprocedure);
 if md5(definition)<>'b12cc7ca95fe89ce83e3ee161d15b3f0' then raise exception 'Review current reconciliation writer before changing customer replay scope'; end if;
 execute replace(definition,'  return prior.result;', $step$
  if action in ('create_customer','customer_balance') and not p.is_admin and not exists (
   select 1 from public.customers x where x.id=(prior.result->>'customerId')::bigint and x.owner_id=p.id
  ) then raise exception 'لا تملك صلاحية هذا العميل' using errcode='42501'; end if;
  return prior.result;$step$);

 -- A pure owner change must preserve imported names and phones verbatim.
 definition:=pg_get_functiondef('solar_private.customer_guard()'::regprocedure);
 if md5(definition)<>'5cf02542f02232586b1000a30f1232ec' then raise exception 'Review current customer validation before owner transfers'; end if;
 execute replace(definition,' if tg_op=''DELETE'' then', $step$
 if tg_op='UPDATE' and new.owner_id is distinct from old.owner_id
    and (to_jsonb(new)-'owner_id')=(to_jsonb(old)-'owner_id') then
  new.customer_revision:=old.customer_revision+1;
  return new;
 end if;
 if tg_op='DELETE' then$step$);
end $migration$;

-- Raw updates carry no transfer request ID or before/after audit. Both the
-- established customer editor and transfer RPC run as protected writers.
create function solar_private.customer_owner_write_guard() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if current_user in ('anon','authenticated') then
  raise exception 'انقل مسؤولية العميل من شاشة إدارة العميل' using errcode='42501';
 end if;
 return new;
end $$;
revoke all on function solar_private.customer_owner_write_guard() from public,anon,authenticated;
create trigger solar_customer_owner_write_guard before update of owner_id on public.customers
for each row when (old.owner_id is distinct from new.owner_id)
execute function solar_private.customer_owner_write_guard();
notify pgrst,'reload schema';
