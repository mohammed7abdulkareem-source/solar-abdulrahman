create extension if not exists pg_net;
create extension if not exists pg_cron;

create table public.solar_push_subscriptions(
 endpoint text primary key check(length(endpoint)<2048),
 user_id uuid not null references public.profiles(id) on delete cascade,
 p256dh text not null, auth_key text not null,
 updated_at timestamptz not null default now()
);
alter table public.solar_push_subscriptions enable row level security;
revoke all on public.solar_push_subscriptions from public,anon,authenticated;
grant select,delete on public.solar_push_subscriptions to authenticated;
grant all on public.solar_push_subscriptions to service_role;
create policy push_own_read on public.solar_push_subscriptions for select to authenticated using(user_id=(select auth.uid()));
create policy push_own_delete on public.solar_push_subscriptions for delete to authenticated using(user_id=(select auth.uid()));
create index solar_push_user on public.solar_push_subscriptions(user_id);

create table public.solar_notifications(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 job_id bigint references public.transactions(id) on delete cascade,
 event text not null check(event in ('assigned','completed','test')),
 title text not null, body text not null,
 created_at timestamptz not null default now(), read_at timestamptz
);
alter table public.solar_notifications enable row level security;
revoke all on public.solar_notifications from public,anon,authenticated;
grant select,update(read_at) on public.solar_notifications to authenticated;
grant all on public.solar_notifications to service_role;
create policy notification_own_read on public.solar_notifications for select to authenticated
 using(user_id=(select auth.uid()) and exists(select 1 from public.profiles where id=auth.uid() and active));
create policy notification_own_update on public.solar_notifications for update to authenticated
 using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create index solar_notification_user on public.solar_notifications(user_id,created_at desc);

create table solar_private.push_deliveries(
 id uuid primary key default gen_random_uuid(),
 notification_id uuid not null references public.solar_notifications(id) on delete cascade,
 endpoint text not null references public.solar_push_subscriptions(endpoint) on delete cascade,
 status text not null default 'pending' check(status in ('pending','sending','sent','failed')),
 attempts integer not null default 0,
 available_at timestamptz not null default now(), lease_until timestamptz,
 sent_at timestamptz, last_status integer,
 unique(notification_id,endpoint)
);
alter table solar_private.push_deliveries enable row level security;
revoke all on solar_private.push_deliveries from public,anon,authenticated;
create index solar_push_due on solar_private.push_deliveries(status,available_at);

create or replace function solar_private.wake_push() returns void
language plpgsql security definer set search_path='' as $$
declare secret text;
begin
 if not exists(select 1 from solar_private.push_deliveries d join public.solar_notifications n on n.id=d.notification_id
 where d.attempts<5 and n.created_at>now()-interval '1 day' and
 ((d.status='pending' and d.available_at<=now()) or (d.status='sending' and d.lease_until<now()))) then return; end if;
 select decrypted_secret into secret from vault.decrypted_secrets where name='solar_push_worker_token';
 if secret is null then return; end if;
 perform net.http_post(
 url:='https://afxxaafsuscwyjzrnagc.supabase.co/functions/v1/solar-push',
 headers:=jsonb_build_object('Content-Type','application/json','x-solar-push-token',secret),
 body:='{}'::jsonb,timeout_milliseconds:=15000);
exception when others then
 -- Network queue trouble must not undo a saved invoice. Cron retries the durable outbox.
 null;
end $$;
revoke all on function solar_private.wake_push() from public,anon,authenticated;

create or replace function solar_private.enqueue_notification(recipient uuid,job bigint,event_name text) returns void
language plpgsql security definer set search_path='' as $$
declare nid uuid; heading text; detail text;
begin
 if not exists(select 1 from public.profiles where id=recipient and active) then return; end if;
 heading:=case event_name when 'assigned' then 'مهمة تنصيب جديدة' when 'completed' then 'تم إكمال التنصيب' else 'إشعارات عبدالرحمن سولار مفعّلة' end;
 detail:=case event_name when 'assigned' then 'تم إسناد مهمة جديدة إليك. افتح البرنامج للاطلاع على الموعد والمواد.' when 'completed' then 'أرسل المهندس تقرير الإنجاز لفاتورتك. راجع التقرير والمصاريف لإغلاق الملف.' else 'وصل الإشعار التجريبي بنجاح إلى هذا الجهاز.' end;
 insert into public.solar_notifications(user_id,job_id,event,title,body) values(recipient,job,event_name,heading,detail) returning id into nid;
 insert into solar_private.push_deliveries(notification_id,endpoint)
 select nid,s.endpoint from public.solar_push_subscriptions s where s.user_id=recipient;
 perform solar_private.wake_push();
end $$;
revoke all on function solar_private.enqueue_notification(uuid,bigint,text) from public,anon,authenticated;

create or replace function solar_private.notify_installation() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.kind<>'system' then return new; end if;
 if new.installer_id is not null and new.installation_status in ('pending','in_progress') then
  if tg_op='INSERT' or old.installer_id is distinct from new.installer_id then
   if exists(select 1 from public.profiles where id=new.installer_id and active and user_type='installer') then
    perform solar_private.enqueue_notification(new.installer_id,new.id,'assigned');
   end if;
  end if;
 end if;
 if tg_op='UPDATE' and old.installation_status='in_progress' and new.installation_status='completed' and new.created_by is not null then
  perform solar_private.enqueue_notification(new.created_by,new.id,'completed');
 end if;
 return new;
end $$;
revoke all on function solar_private.notify_installation() from public,anon,authenticated;
create trigger solar_installation_notifications after insert or update on public.transactions
for each row execute function solar_private.notify_installation();

create or replace function solar_private.push_register(subscription jsonb) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); ep text:=subscription->>'endpoint'; p text:=subscription->'keys'->>'p256dh'; a text:=subscription->'keys'->>'auth';
begin
 if uid is null or not exists(select 1 from public.profiles where id=uid and active) then raise exception 'Active login required' using errcode='42501'; end if;
 if ep is null or length(ep)>2048 or ep !~ '^https://(fcm[.]googleapis[.]com|updates[.]push[.]services[.]mozilla[.]com|web[.]push[.]apple[.]com|[a-z0-9.-]+[.]notify[.]windows[.]com)/' then raise exception 'Unsupported push endpoint';end if;
 if p is null or p !~ '^[A-Za-z0-9_-]{87}$' or a is null or a !~ '^[A-Za-z0-9_-]{22}$' then raise exception 'Invalid subscription keys';end if;
 if (select count(*) from public.solar_push_subscriptions where user_id=uid and endpoint<>ep)>=10 then raise exception 'Device limit reached'; end if;
 insert into public.solar_push_subscriptions(endpoint,user_id,p256dh,auth_key) values(ep,uid,p,a)
 on conflict(endpoint) do update set user_id=excluded.user_id,p256dh=excluded.p256dh,auth_key=excluded.auth_key,updated_at=now();
end $$;
revoke all on function solar_private.push_register(jsonb) from public,anon;
grant execute on function solar_private.push_register(jsonb) to authenticated;
create or replace function public.solar_push_register(subscription jsonb) returns void language sql security invoker set search_path='' as $$ select solar_private.push_register(subscription) $$;
revoke all on function public.solar_push_register(jsonb) from public,anon;
grant execute on function public.solar_push_register(jsonb) to authenticated;

create or replace function solar_private.push_public_key() returns text language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and active) then raise exception 'Active login required' using errcode='42501';end if;
 return (select decrypted_secret from vault.decrypted_secrets where name='solar_push_vapid_public');
end $$;
revoke all on function solar_private.push_public_key() from public,anon;
grant execute on function solar_private.push_public_key() to authenticated;
create or replace function public.solar_push_public_key() returns text language sql security invoker set search_path='' as $$select solar_private.push_public_key()$$;
revoke all on function public.solar_push_public_key() from public,anon;
grant execute on function public.solar_push_public_key() to authenticated;

create or replace function solar_private.push_test() returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();
begin
 if uid is null or not exists(select 1 from public.profiles where id=uid and active) then raise exception 'Active login required' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtext(uid::text));
 if exists(select 1 from public.solar_notifications where user_id=uid and event='test' and created_at>now()-interval '1 minute') then raise exception 'Wait one minute before another test';end if;
 perform solar_private.enqueue_notification(uid,null,'test');
end $$;
revoke all on function solar_private.push_test() from public,anon;
grant execute on function solar_private.push_test() to authenticated;
create or replace function public.solar_push_test() returns void language sql security invoker set search_path='' as $$select solar_private.push_test()$$;
revoke all on function public.solar_push_test() from public,anon;
grant execute on function public.solar_push_test() to authenticated;

-- Worker RPCs are service-role only; secrets remain encrypted in Vault.
create or replace function public.solar_push_worker_config() returns jsonb language sql security definer set search_path='' as $$
 select jsonb_object_agg(name,decrypted_secret) from vault.decrypted_secrets where name in ('solar_push_worker_token','solar_push_vapid_public','solar_push_vapid_private')
$$;
revoke all on function public.solar_push_worker_config() from public,anon,authenticated;
grant execute on function public.solar_push_worker_config() to service_role;

create or replace function public.solar_push_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 with eligible as (
 select d.id from solar_private.push_deliveries d join public.solar_notifications n on n.id=d.notification_id
 join public.solar_push_subscriptions s on s.endpoint=d.endpoint and s.user_id=n.user_id
 join public.profiles p on p.id=n.user_id and p.active
 where d.attempts<5 and n.created_at>now()-interval '1 day' and ((d.status='pending' and d.available_at<=now()) or (d.status='sending' and d.lease_until<now()))
 order by d.available_at for update of d skip locked limit 20
 ), claimed as (
 update solar_private.push_deliveries d set status='sending',attempts=attempts+1,lease_until=now()+interval '2 minutes'
 from eligible e where d.id=e.id returning d.*
 )
 select coalesce(jsonb_agg(jsonb_build_object('deliveryId',d.id,'attempt',d.attempts,'endpoint',s.endpoint,'keys',jsonb_build_object('p256dh',s.p256dh,'auth',s.auth_key),'notification',jsonb_build_object('id',n.id,'userId',n.user_id,'jobId',n.job_id,'title',n.title,'body',n.body))),'[]'::jsonb)
 into result from claimed d join public.solar_notifications n on n.id=d.notification_id join public.solar_push_subscriptions s on s.endpoint=d.endpoint and s.user_id=n.user_id;
 return result;
end $$;
revoke all on function public.solar_push_claim() from public,anon,authenticated;
grant execute on function public.solar_push_claim() to service_role;

create or replace function public.solar_push_finish(delivery_id uuid,attempt_number integer,http_status integer) returns void language plpgsql security definer set search_path='' as $$
declare ep text;
begin
 update solar_private.push_deliveries set
 status=case when http_status between 200 and 299 then 'sent' when http_status in (400,404,410,422) or attempts>=5 then 'failed' else 'pending' end,
 sent_at=case when http_status between 200 and 299 then now() else null end,
 last_status=http_status,lease_until=null,available_at=now()+make_interval(secs=>least(3600,60*power(2,attempts)::integer))
 where id=delivery_id and attempts=attempt_number and status='sending' returning endpoint into ep;
 if ep is not null and http_status in (404,410) then delete from public.solar_push_subscriptions where endpoint=ep;end if;
end $$;
revoke all on function public.solar_push_finish(uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.solar_push_finish(uuid,integer,integer) to service_role;
select cron.schedule('solar-installation-push-retry','* * * * *','select solar_private.wake_push()');
