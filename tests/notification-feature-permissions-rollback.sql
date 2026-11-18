-- Verify changes to the same user's permissions against already queued, unread notices.
\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,display_name,user_type,permissions) values
('00000000-0000-0000-0000-000000411481','Notice scope fixture','admin_staff','{"tahseel":true,"tahseelFull":true,"salesDeleteOwn":true}');
insert into public.solar_notifications(user_id,event,title,body)
select '00000000-0000-0000-0000-000000411481'::uuid,event,title,'fixture notice'
from (values('test','test'),('admin_message','announcement'),('profit_decided','private finance'),
 ('cash_accepted','private cash'),('warehouse_new','private warehouse'),('receipt_delete_decided','private request'),
 ('operation_resumed','تم استئناف الشراء'),('operation_paused','تحديث إعدادات أسعار بيع الجملة')) t(event,title);
insert into public.solar_push_subscriptions(endpoint,user_id,p256dh,auth_key) values
 ('https://fcm.googleapis.com/fixture-notice-scope','00000000-0000-0000-0000-000000411481','fixture','fixture');
insert into solar_private.push_deliveries(notification_id,endpoint) select id,'https://fcm.googleapis.com/fixture-notice-scope'
from public.solar_notifications where user_id='00000000-0000-0000-0000-000000411481';

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411481',true);
do $$ declare changed int; begin
 assert (select count(*) from public.solar_notifications where read_at is null)=2,'Only test and announcement should be visible';
 update public.solar_notifications set read_at=now() where user_id=auth.uid();
 get diagnostics changed=row_count;
 assert changed=2,'Mark all read must exclude hidden events';
end $$;
reset role;
do $$ declare notices jsonb; begin
 select coalesce(jsonb_agg(q->'notification'->>'event' order by q->'notification'->>'event'),'[]') into notices
 from jsonb_array_elements(public.solar_push_claim()) q where q->>'endpoint'='https://fcm.googleapis.com/fixture-notice-scope';
 assert notices='["admin_message","test"]'::jsonb,'Pending deliveries leaked hidden events';
end $$;

update public.profiles set permissions='{"sale":true,"cashTransferSend":true}' where id='00000000-0000-0000-0000-000000411481';
set local role authenticated;
do $$ begin
 assert (select count(*) from public.solar_notifications where read_at is null)=3,'New sale and transfer permissions should expose only their rows';
 assert not exists(select from public.solar_notifications where title='تم استئناف الشراء' or event='receipt_delete_decided'),'Unrelated purchase or deletion notice leaked';
end $$;
reset role;
update public.profiles set permissions='{"tahseel":true,"salesDeleteOwn":true}' where id='00000000-0000-0000-0000-000000411481';
set local role authenticated;
do $$ begin
 assert not exists(select from public.solar_notifications where read_at is null),'Permission revocation must hide the old count immediately';
end $$;
rollback;
