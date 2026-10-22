-- One six-hour booking per engineer. Existing invoices and appointments are retained.
create index installation_engineer_calendar_idx on public.transactions(installer_id,install_date)
 where kind='system' and install_date is not null and install_time is not null;

create function solar_private.installation_slot(day date,at_time time) returns tstzrange language sql stable set search_path='' as $$
 select tstzrange((day+at_time) at time zone 'Asia/Baghdad',((day+at_time) at time zone 'Asia/Baghdad')+interval '6 hours','[)')
$$;
revoke all on function solar_private.installation_slot(date,time) from public,anon,authenticated;

create function solar_private.installation_booking_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare busy_slot tstzrange;begin
 if new.kind<>'system' then return new;end if;
 if tg_op='UPDATE' and(new.installer_id,new.install_date,new.install_time) is not distinct from(old.installer_id,old.install_date,old.install_time) then return new;end if;
 if (new.install_date is null)<>(new.install_time is null) then raise exception 'حدد يوم وساعة موعد التنصيب معًا' using errcode='22023';end if;
 if new.install_date is null then return new;end if;
 if new.installer_id is null or not exists(select 1 from public.profiles p where p.id=new.installer_id and p.active and p.user_type='installer') then raise exception 'اختر مهندس تنصيب فعّال للموعد' using errcode='22023';end if;
 if new.install_time>=time '24:00' then raise exception 'ساعة الموعد غير صحيحة' using errcode='22023';end if;
 -- The same lock is already taken by invoice and installation writes. Two users
 -- cannot both commit an overlapping booking after an availability read.
 perform pg_advisory_xact_lock(7311,1);
 select solar_private.installation_slot(t.install_date,t.install_time) into busy_slot from public.transactions t
 where t.kind='system' and t.id<>new.id and t.installer_id=new.installer_id and t.install_date between new.install_date-1 and new.install_date+1
 and t.install_time is not null and solar_private.installation_slot(t.install_date,t.install_time)&&solar_private.installation_slot(new.install_date,new.install_time)
 order by t.install_date,t.install_time,t.id limit 1;
 if busy_slot is not null then raise exception 'موعد المهندس محجوز من % إلى %؛ اختر وقتًا لا يتداخل مع الحجز',
  to_char(lower(busy_slot) at time zone 'Asia/Baghdad','YYYY/MM/DD HH24:MI'),to_char(upper(busy_slot) at time zone 'Asia/Baghdad','YYYY/MM/DD HH24:MI') using errcode='PT409';end if;
 return new;
end$$;
revoke all on function solar_private.installation_booking_guard() from public,anon,authenticated;
create trigger solar_installation_booking_guard before insert or update of installer_id,install_date,install_time on public.transactions
 for each row execute function solar_private.installation_booking_guard();

create function solar_private.installation_schedule(date_from date,date_to date,installer_id uuid default null,exclude_invoice_id bigint default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_variable
declare p public.profiles;excluded public.transactions;begin
 select * into p from public.profiles where id=auth.uid() and active and user_type<>'warehouse';
 if p.id is null or not(p.user_type='installer' or p.is_admin or coalesce(p.permissions->>'system','false')='true' or coalesce(p.permissions->>'installations','false')='true' or coalesce(p.permissions->>'installationsAll','false')='true') then raise exception 'لا تملك صلاحية جدول التنصيبات' using errcode='42501';end if;
 if date_from is null or date_to is null or date_to<date_from or date_to-date_from>30 then raise exception 'اختر فترة لا تتجاوز 31 يومًا' using errcode='22023';end if;
 if p.user_type='installer' and installer_id is not null and installer_id<>p.id then raise exception 'جدول المهندس يخص مهامه فقط' using errcode='42501';end if;
 if exclude_invoice_id is not null then
  select * into excluded from public.transactions t where t.id=exclude_invoice_id and t.kind='system';
  if excluded.id is null or not(case when p.user_type='installer' then excluded.installer_id=p.id else p.is_admin or excluded.created_by=p.id end) then raise exception 'الفاتورة غير متاحة' using errcode='42501';end if;
 end if;
 return jsonb_build_object('durationHours',6,'from',date_from,'to',date_to,
  'engineers',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'name',coalesce(e.display_name,e.username)) order by coalesce(e.display_name,e.username),e.id)
   from public.profiles e where e.active and e.user_type='installer' and(p.user_type<>'installer' or e.id=p.id)),'[]'),
  'slots',coalesce((select jsonb_agg(jsonb_build_object('installerId',t.installer_id,'start',lower(solar_private.installation_slot(t.install_date,t.install_time)),
    'end',upper(solar_private.installation_slot(t.install_date,t.install_time)),'own',case when p.user_type='installer' then t.installer_id=p.id else p.is_admin or t.created_by=p.id end)
    ||case when(case when p.user_type='installer' then t.installer_id=p.id else p.is_admin or t.created_by=p.id end) then
     jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'party',t.party_name,'status',t.installation_status,'creatorName',(select coalesce(c.display_name,c.username) from public.profiles c where c.id=t.created_by)) else '{}'::jsonb end
    order by t.install_date,t.install_time,t.id)
   from public.transactions t where t.kind='system' and t.installer_id is not null and t.install_date between date_from-1 and date_to and t.install_time is not null
   and(t.installation_status is not null) and(exclude_invoice_id is null or t.id<>exclude_invoice_id)
   and(installer_id is null or t.installer_id=installer_id) and(p.user_type<>'installer' or t.installer_id=p.id)
   and solar_private.installation_slot(t.install_date,t.install_time)&&tstzrange(date_from::timestamp at time zone 'Asia/Baghdad',(date_to+1)::timestamp at time zone 'Asia/Baghdad','[)')),'[]'));
end$$;
create function public.solar_installation_schedule(date_from date,date_to date,installer_id uuid default null,exclude_invoice_id bigint default null) returns jsonb
language sql stable security invoker set search_path='' as $$select solar_private.installation_schedule(date_from,date_to,installer_id,exclude_invoice_id)$$;
revoke all on function solar_private.installation_schedule(date,date,uuid,bigint),public.solar_installation_schedule(date,date,uuid,bigint) from public,anon;
grant execute on function solar_private.installation_schedule(date,date,uuid,bigint),public.solar_installation_schedule(date,date,uuid,bigint) to authenticated;

-- Assigned engineers see the responsible invoice author without gaining access
-- to sales, other engineers' jobs, or any financial invoice fields.
do $$declare definition text;needle text:='''installDate'',t.install_date';begin
 definition:=pg_get_functiondef('solar_private.installation_jobs()'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected installation jobs contract';end if;
 execute replace(definition,needle,'''creatorId'',t.created_by,''creatorName'',(select coalesce(c.display_name,c.username) from public.profiles c where c.id=t.created_by),''creatorPhone'',(select c.phone from public.profiles c where c.id=t.created_by),''installDate'',t.install_date');
end$$;

do $$declare expression text;begin
 select pg_get_expr(conbin,conrelid) into expression from pg_constraint where conrelid='public.solar_notifications'::regclass and conname='solar_notifications_event_check';
 if expression is null then raise exception 'Notification event contract missing';end if;
 alter table public.solar_notifications drop constraint solar_notifications_event_check;
 execute 'alter table public.solar_notifications add constraint solar_notifications_event_check check(('||expression||') or event=''installation_updated'')';
end$$;
create function solar_private.installation_update_notice(recipient uuid,invoice public.transactions) returns void
language plpgsql security definer set search_path='' as $$
declare nid uuid;heading text;begin
 if recipient is null or recipient=auth.uid() or not solar_private.notification_recipient_allowed(recipient,invoice.id) then return;end if;
 heading:=case invoice.installation_status when 'closed' then 'تم إنهاء التنصيب وإغلاق الملف' when 'completed' then 'تم تحديث الملف إلى مراجعة التقرير' when 'in_progress' then 'بدأ تنفيذ التنصيب' else 'تم تحديث موعد ومهمة التنصيب' end;
 insert into public.solar_notifications(user_id,job_id,event,title,body) values(recipient,invoice.id,'installation_updated',heading,'وصل #'||invoice.receipt_no||' • '||coalesce(invoice.party_name,'منظومة')) returning id into nid;
 insert into solar_private.push_deliveries(notification_id,endpoint) select nid,endpoint from public.solar_push_subscriptions where user_id=recipient;
 perform solar_private.wake_push();
end$$;
revoke all on function solar_private.installation_update_notice(uuid,public.transactions) from public,anon,authenticated;
create function solar_private.installation_sync_notice() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.kind<>'system' then return new;end if;
 if(new.installation_status,new.install_date,new.install_time) is not distinct from(old.installation_status,old.install_date,old.install_time) then return new;end if;
 if new.installer_id=old.installer_id then perform solar_private.installation_update_notice(new.installer_id,new);end if;
 if new.installation_status='in_progress' or(new.install_date,new.install_time) is distinct from(old.install_date,old.install_time) then perform solar_private.installation_update_notice(new.created_by,new);end if;
 return new;
end$$;
revoke all on function solar_private.installation_sync_notice() from public,anon,authenticated;
create trigger solar_installation_sync_notice after update of installation_status,install_date,install_time on public.transactions
 for each row execute function solar_private.installation_sync_notice();
