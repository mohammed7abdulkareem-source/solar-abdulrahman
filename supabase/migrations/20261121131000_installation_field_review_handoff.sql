-- A field report follows the installation receipt through submission, correction
-- and review. Keep its history separate from financial approval notes and cash.
create table solar_private.installation_field_events (
 job_id bigint not null references public.transactions(id) on delete cascade,
 revision bigint not null,
 status text not null check(status in ('submitted','returned','approved','reopened')),
 actor_id uuid not null,
 actor_name text not null,
 happened_at timestamptz not null default statement_timestamp(),
 return_note text,
 field_report jsonb,
 primary key(job_id,revision)
);
alter table solar_private.installation_field_events enable row level security;
revoke all on table solar_private.installation_field_events from public,anon,authenticated;

create function solar_private.installation_reviewer_enabled(person uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=person and p.active and p.user_type not in ('warehouse','installer')
     and (p.is_admin or p.permissions @> '{"installations":true}'))
$$;
revoke all on function solar_private.installation_reviewer_enabled(uuid) from public,anon,authenticated;

create function solar_private.installation_field_notice(person uuid,job public.transactions,event_name text,heading text) returns void
language plpgsql security definer set search_path='' as $$
declare nid uuid;
begin
 if person is null or person=auth.uid() or not solar_private.notification_recipient_allowed(person,job.id) then return;end if;
 insert into public.solar_notifications(user_id,job_id,event,title,body)
 values(person,job.id,event_name,heading,'وصل #'||job.receipt_no||' · '||coalesce(job.party_name,'منظومة'))
 returning id into nid;
 insert into solar_private.push_deliveries(notification_id,endpoint)
  select nid,s.endpoint from public.solar_push_subscriptions s where s.user_id=person;
 perform solar_private.wake_push();
end$$;
revoke all on function solar_private.installation_field_notice(uuid,public.transactions,text,text) from public,anon,authenticated;

create function solar_private.installation_request_review(job public.transactions,heading text) returns void
language plpgsql security definer set search_path='' as $$
declare owner uuid:=solar_private.receipt_responsible(job.id,job.created_by); target uuid;
begin
 if solar_private.installation_reviewer_enabled(owner) then
  perform solar_private.installation_field_notice(owner,job,'completed',heading);
 else
  for target in select p.id from public.profiles p where p.active and p.is_admin and p.user_type not in ('warehouse','installer') loop
   perform solar_private.installation_field_notice(target,job,'completed',heading);
  end loop;
 end if;
end$$;
revoke all on function solar_private.installation_request_review(public.transactions,text) from public,anon,authenticated;

create function solar_private.record_installation_field_action(job_id bigint,action text,return_note text) returns void
language plpgsql security definer set search_path='' as $$
declare job public.transactions; person public.profiles; state text;
begin
 select * into strict job from public.transactions t where t.id=job_id;
 select * into strict person from public.profiles p where p.id=auth.uid() and p.active;
 state:=case action when 'complete' then 'submitted' when 'return_report' then 'returned'
     when 'close' then 'approved' when 'reopen' then 'reopened' end;
 insert into solar_private.installation_field_events(job_id,revision,status,actor_id,actor_name,return_note,field_report)
 values(job.id,job.installation_revision,state,person.id,coalesce(solar_private.user_name(person.display_name,person.username,person.honorific),'مستخدم'),
 case when state='returned' then btrim(return_note) end,
 case when state in ('submitted','returned') then job.installation_report end);
 if state='submitted' then
  perform solar_private.installation_request_review(job,'أرسل مهندس التنصيب تقرير الإنجاز للمراجعة');
 else
  perform solar_private.installation_field_notice(job.installer_id,job,'installation_updated',case state
   when 'returned' then 'أُعيد تقرير التنصيب للتصحيح'
   when 'approved' then 'اعتُمد التنصيب وأُغلق الملف'
   when 'reopened' then 'أُعيد فتح ملف التنصيب للمراجعة' end);
 end if;
end$$;
revoke all on function solar_private.record_installation_field_action(bigint,text,text) from public,anon,authenticated;

-- A reviewer looking at an already submitted file receives a handoff when the
-- admin moves this specific receipt, including older submitted reports.
create function solar_private.installation_notice_after_handoff() returns trigger
language plpgsql security definer set search_path='' as $$
declare job public.transactions;
begin
 if tg_op='UPDATE' and new.owner_id=old.owner_id then return new;end if;
 select * into job from public.transactions t where t.id=new.transaction_id and t.kind='system'
    and t.installation_status='completed' and nullif(t.installation_report->>'submittedAt','') is not null;
 if found then perform solar_private.installation_request_review(job,'انتقلت إليك مراجعة تقرير التنصيب');end if;
 return new;
end$$;
revoke all on function solar_private.installation_notice_after_handoff() from public,anon,authenticated;
create trigger solar_installation_review_handoff after insert or update of owner_id
 on solar_private.customer_receipt_responsibility for each row execute function solar_private.installation_notice_after_handoff();

do $migration$
declare original text; definition text; legacy regprocedure:=to_regprocedure('solar_private.notify_installation()');
begin
 original:=pg_get_functiondef('solar_private.installation_action(bigint,bigint,text,jsonb)'::regprocedure);
 definition:=replace(original,$find$action not in ('close','reopen','clear_expenses')$find$,$put$action not in ('close','reopen','clear_expenses','return_report')$put$);
 definition:=replace(definition,$find$elsif action='close' then$find$,$put$elsif action='return_report' then
  if j.installation_status<>'completed' or j.installer_id is null or nullif(j.installation_report->>'submittedAt','') is null then
   raise exception 'لا يوجد تقرير مرسل يمكن إعادته للمهندس' using errcode='PT409';end if;
  if not exists(select 1 from public.profiles e where e.id=j.installer_id and e.active and e.user_type='installer') then
   raise exception 'المهندس المسند غير متاح للتصحيح' using errcode='PT409';end if;
  if jsonb_typeof(payload->'notes') is distinct from 'string' or length(btrim(payload->>'notes')) not between 1 and 4000 then
   raise exception 'اكتب سبب إعادة التقرير للمهندس' using errcode='22023';end if;
  update public.transactions set installation_status='in_progress',installation_completed_at=null,
    installation_revision=installation_revision+1 where id=j.id;
 elsif action='close' then
  if j.installer_id is not null and j.installation_status in ('pending','in_progress') then
   raise exception 'بانتظار إرسال تقرير المهندس قبل اعتماد المصاريف وإغلاق الملف' using errcode='PT409';end if;$put$);
 definition:=replace(definition,$find$end $function$$find$,$put$
 if action in ('complete','return_report','close','reopen') then
  perform solar_private.record_installation_field_action(j.id,action,payload->>'notes');
 end if;
end $function$$put$);
 if strpos(definition,'record_installation_field_action(j.id,action')=0 or strpos(definition,'لا يوجد تقرير مرسل')=0 or
    strpos(definition,'action not in (''close'',''reopen'',''clear_expenses'',''return_report'')')=0 then raise exception 'Unexpected installation workflow';end if;
 execute definition;

 -- Leave appointment changes and initial engineer assignment on their original
 -- notification paths. Report/decision messages now originate at the action.
 if legacy is not null then
  original:=pg_get_functiondef(legacy);
  definition:=replace(original,$find$perform solar_private.enqueue_notification(new.created_by,new.id,'completed');$find$,'null;');
  if definition=original then raise exception 'Unexpected legacy submission trigger';end if;
  execute definition;
 end if;
 original:=pg_get_functiondef('solar_private.installation_sync_notice()'::regprocedure);
 definition:=replace(original,$find$if new.installer_id=old.installer_id then$find$,$put$
 if (old.installation_status,new.installation_status) in (('in_progress','completed'),('completed','in_progress'),('closed','completed'))
    or (old.installation_status<>'closed' and new.installation_status='closed') then return new;end if;
 if new.installer_id=old.installer_id then$put$);
 if definition=original then raise exception 'Unexpected installation update notifications';end if;
 execute definition;

 original:=pg_get_functiondef('solar_private.installation_jobs()'::regprocedure);
 definition:=replace(original,$find$'creatorId',t.created_by,$find$,$put$
 'reviewerIsAdminTeam',not solar_private.installation_reviewer_enabled(manager.id),
 'installerPhone',(select e.phone from public.profiles e where e.id=t.installer_id),
 'installationReview',(select jsonb_build_object('status',f.status,'actorId',f.actor_id,'actorName',f.actor_name,
   'at',f.happened_at,'notes',f.return_note) from solar_private.installation_field_events f
   where f.job_id=t.id order by f.revision desc limit 1),
 'canCloseFile',solar_private.can_close_installation(coalesce(custody.owner_id,t.created_by)) and t.warehouse_status='ready'
     and (t.installation_status='completed' or (t.installer_id is null and t.installation_status in ('pending','in_progress'))),
 'canReturnReport',solar_private.can_close_installation(coalesce(custody.owner_id,t.created_by))
     and t.installation_status='completed' and nullif(t.installation_report->>'submittedAt','') is not null
     and exists(select 1 from public.profiles e where e.id=t.installer_id and e.active and e.user_type='installer'),
 'creatorId',t.created_by,$put$);
 if definition=original then raise exception 'Unexpected installation jobs projection';end if;
 execute definition;
end
$migration$;

-- A queued push or an old inbox entry must not ask a former responsible seller
-- to review a report that now belongs to another user.
create function solar_private.field_review_notice_allowed(recipient uuid,job_id bigint) returns boolean
language sql stable security definer set search_path='' as $$
 select exists (
  select 1 from public.transactions t
  join public.profiles p on p.id=recipient and p.active and p.user_type not in ('warehouse','installer')
  left join solar_private.customer_receipt_responsibility h on h.transaction_id=t.id
  where t.id=job_id and t.kind='system'
   and case when solar_private.installation_reviewer_enabled(coalesce(h.owner_id,t.created_by))
      then p.id=coalesce(h.owner_id,t.created_by) else p.is_admin end
 )
$$;
revoke all on function solar_private.field_review_notice_allowed(uuid,bigint) from public,anon,authenticated;
create function solar_private.own_field_review_notice(job_id bigint) returns boolean
language sql stable security definer set search_path='' as $$
 select solar_private.field_review_notice_allowed(auth.uid(),job_id)
$$;
revoke all on function solar_private.own_field_review_notice(bigint) from public,anon;
grant execute on function solar_private.own_field_review_notice(bigint) to authenticated;
create policy solar_current_field_reviewer on public.solar_notifications as restrictive for select to authenticated
 using (event<>'completed' or solar_private.own_field_review_notice(job_id));
do $push$
declare definition text:=pg_get_functiondef('public.solar_push_claim()'::regprocedure);
 anchor constant text:='join public.profiles p on p.id=n.user_id and p.active';
begin
 if strpos(definition,anchor)=0 then raise exception 'Unexpected push claim';end if;
 execute replace(definition,anchor,anchor||' and (n.event<>''completed'' or solar_private.field_review_notice_allowed(n.user_id,n.job_id))');
end
$push$;
