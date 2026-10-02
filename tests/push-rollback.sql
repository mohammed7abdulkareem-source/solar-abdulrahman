begin;
select set_config('solar_test.engineer',(select id::text from public.profiles where active and user_type='installer' order by created_at limit 1),true);
select set_config('solar_test.admin',(select id::text from public.profiles where active and is_admin and user_type<>'installer' limit 1),true);
select set_config('solar_test.staff',(select id::text from public.profiles where active and not is_admin and user_type='admin_staff' order by created_at limit 1),true);
insert into public.solar_push_subscriptions(endpoint,user_id,p256dh,auth_key) values
('https://fcm.googleapis.com/fcm/send/solar-rollback-engineer',current_setting('solar_test.engineer')::uuid,repeat('A',87),repeat('B',22)),
('https://fcm.googleapis.com/fcm/send/solar-rollback-staff',current_setting('solar_test.staff')::uuid,repeat('A',87),repeat('B',22));
insert into public.transactions(id,kind,created_by,cashbox_user_id,installer_id,installation_status)
values(-920001,'system',current_setting('solar_test.staff')::uuid,current_setting('solar_test.admin')::uuid,current_setting('solar_test.engineer')::uuid,'pending');
do $$ begin
 if (select count(*) from public.solar_notifications where job_id=-920001 and event='assigned' and user_id=current_setting('solar_test.engineer')::uuid)<>1 then raise exception 'FAIL assignment routing';end if;
 if (select count(*) from solar_private.push_deliveries d join public.solar_notifications n on n.id=d.notification_id where n.job_id=-920001)<>1 then raise exception 'FAIL assignment outbox';end if;
end $$;
update public.transactions set notes='unchanged stage' where id=-920001;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('solar_test.engineer'),true);
do $$ begin
 if (select count(*) from public.solar_notifications where job_id=-920001)<>1 then raise exception 'FAIL duplicate assignment';end if;
 begin perform public.solar_push_worker_config();raise exception 'FAIL worker secrets readable';exception when insufficient_privilege then null;end;
 begin perform public.solar_push_claim();raise exception 'FAIL worker claim exposed';exception when insufficient_privilege then null;end;
 begin perform public.solar_push_register('{"endpoint":"https://127.0.0.1/internal","keys":{"p256dh":"x","auth":"x"}}');raise exception 'FAIL invalid endpoint registered';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 perform public.solar_installation_action(-920001,0,'start');
 perform public.solar_installation_action(-920001,1,'complete','{"notes":"Test completion","checks":{"materials":true,"tested":true,"handover":true},"expenses":[]}');
 if (select count(*) from public.solar_notifications where job_id=-920001)<>1 then raise exception 'FAIL engineer can see creator notification';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('solar_test.staff'),true);
do $$ begin
 if (select count(*) from public.solar_notifications where job_id=-920001 and event='completed')<>1 then raise exception 'FAIL completion must target creator not cashbox owner';end if;
 update public.solar_notifications set read_at=now() where job_id=-920001;
 begin update public.solar_notifications set title='spoof' where job_id=-920001;raise exception 'FAIL notification text writable';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('solar_test.admin'),true);
do $$ begin
 if exists(select 1 from public.solar_notifications where job_id=-920001) then raise exception 'FAIL cash owner got creator notification';end if;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.solar_notifications where job_id=-920001)<>2 then raise exception 'FAIL unexpected event count';end if;
 if (select count(*) from solar_private.push_deliveries d join public.solar_notifications n on n.id=d.notification_id where n.job_id=-920001)<>2 then raise exception 'FAIL completion outbox';end if;
end $$;
set local role service_role;
do $$ declare jobs jsonb; d jsonb; begin
 jobs:=public.solar_push_claim();
 if (select count(*) from jsonb_array_elements(jobs) j where (j->'notification'->>'jobId')::bigint=-920001)<>2 then raise exception 'FAIL worker claim';end if;
 if jsonb_array_length(public.solar_push_claim())<>0 then raise exception 'FAIL duplicate concurrent claim';end if;
 for d in select value from jsonb_array_elements(jobs) loop
 perform public.solar_push_finish((d->>'deliveryId')::uuid,(d->>'attempt')::integer,429);
 end loop;
end $$;
reset role;
do $$ begin
 if (select count(*) from solar_private.push_deliveries d join public.solar_notifications n on n.id=d.notification_id where n.job_id=-920001 and d.status='pending' and d.available_at>now())<>2 then raise exception 'FAIL retry backoff';end if;
end $$;
select 'PASS: assignment to engineer, completion to invoice creator, no duplicates, private inbox, protected secrets, endpoint validation, leased worker claims and retry backoff' as verification;
rollback;
