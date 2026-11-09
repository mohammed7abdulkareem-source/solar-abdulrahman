-- Existing notification grants/RLS only. Run on an isolated local fixture.
\set ON_ERROR_STOP on
begin;
do $$begin
 if current_database()!~'^solar_[a-z0-9_]+_browser$' then raise exception 'Use an isolated local browser database';end if;
end$$;
insert into public.profiles(id,display_name,is_admin,user_type,active)values
('00000000-0000-0000-0000-000000310330','اختبار إشعارات المستخدم',false,'admin_staff',true),
('00000000-0000-0000-0000-000000310331','اختبار إشعارات الإدارة',true,'admin_staff',true);
insert into public.solar_notifications(id,user_id,event,title,body,created_at,read_at)values
('31033000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000310330','test','own unread','fixture',now()-interval'2 minutes',null),
('31033000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000310330','test','own already read','fixture',now()-interval'1 minute',now()-interval'30 seconds'),
('31033000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000310331','test','foreign unread','fixture',now(),null);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000310330',true);
do $$declare changed integer;begin
 assert(select count(*)from public.solar_notifications)=2,'A user can read another inbox';
 update public.solar_notifications set read_at=now() where user_id='00000000-0000-0000-0000-000000310330'and read_at is null
 and id in('31033000-0000-0000-0000-000000000001','31033000-0000-0000-0000-000000000003');
 get diagnostics changed=row_count;assert changed=1,'Own explicit-ID update failed';
 update public.solar_notifications set read_at=now() where user_id='00000000-0000-0000-0000-000000310331';
 get diagnostics changed=row_count;assert changed=0,'Cross-user update bypassed RLS';
 begin update public.solar_notifications set title='spoof'where id='31033000-0000-0000-0000-000000000001';raise exception 'Notification title was writable';exception when insufficient_privilege then null;end;
 begin update public.solar_notifications set user_id='00000000-0000-0000-0000-000000310331'where id='31033000-0000-0000-0000-000000000001';raise exception 'Notification owner was writable';exception when insufficient_privilege then null;end;
end$$;
reset role;
insert into public.solar_notifications(id,user_id,event,title,body)values('31033000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000310330','test','arrived after frozen selection','fixture');
set local role authenticated;
do $$declare changed integer;begin
 update public.solar_notifications set read_at=now()where user_id='00000000-0000-0000-0000-000000310330'and read_at is null
 and id in('31033000-0000-0000-0000-000000000001','31033000-0000-0000-0000-000000000002');
 get diagnostics changed=row_count;assert changed=0,'Repeated read update was not idempotent';
 assert(select read_at is null from public.solar_notifications where id='31033000-0000-0000-0000-000000000004'),'Later arrival was marked by old IDs';
 assert(select read_at=now()-interval'30 seconds'from public.solar_notifications where id='31033000-0000-0000-0000-000000000002'),'Historical read time changed';
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000310331',true);
do $$declare changed integer;begin
 assert(select count(*)from public.solar_notifications)=1,'Admin read another inbox';
 assert(select read_at is null from public.solar_notifications where id='31033000-0000-0000-0000-000000000003'),'Foreign unread was changed';
 update public.solar_notifications set read_at=now()where id='31033000-0000-0000-0000-000000000004';
 get diagnostics changed=row_count;assert changed=0,'Admin modified another inbox';
end$$;
reset role;
do $$begin raise notice 'PASS own-user notification read only, admin isolation, column grants, frozen IDs preserve later arrivals, and idempotent read timestamps';end$$;
rollback;
