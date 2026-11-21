-- A handoff of an already closed file changes operational access. Expense
-- differences still post to the actual payer, and the original seller remains.
begin;
insert into profiles(id,display_name,is_admin,user_type,permissions,phone) values
 ('00000000-0000-0000-0000-000000412201','موظف الوصل',false,'admin_staff','{"installations":true,"system":true}','07704122001'),
 ('00000000-0000-0000-0000-000000412202','مستلم الوصل',false,'admin_staff','{"installations":true}','07704122002'),
 ('00000000-0000-0000-0000-000000412203','مهندس الوصل',false,'installer','{}','07704122003'),
 ('00000000-0000-0000-0000-000000412204','مدير التوزيع',true,'admin_staff','{}','07704122004');
insert into customers(id,name,customer_type,owner_id) values
 (-412211,'عميل اختبار مسؤول التنصيب','system','00000000-0000-0000-0000-000000412201');
insert into transactions(id,kind,party_id,party_name,party_type,created_by,cashbox_user_id,installer_id,warehouse_id,warehouse_status,
 installation_status,total,cost,profit,install_date,install_time) values
 (-412211,'system',-412211,'عميل اختبار مسؤول التنصيب','customer','00000000-0000-0000-0000-000000412201','00000000-0000-0000-0000-000000412201',
 '00000000-0000-0000-0000-000000412203',1,'ready','completed',1000,300,700,'2037-11-21','09:00'),
 (-412212,'system',-412211,'عميل اختبار مسؤول التنصيب','customer','00000000-0000-0000-0000-000000412201','00000000-0000-0000-0000-000000412201',
 '00000000-0000-0000-0000-000000412203',1,'ready','pending',1000,300,700,'2037-11-22','09:00');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412201',true);
set local role authenticated;
select public.solar_installation_action(-412211,0,'close','{"amount":200}');
reset role;
update public.customers set owner_id='00000000-0000-0000-0000-000000412202' where id=-412211;
insert into solar_private.customer_receipt_responsibility(transaction_id,customer_id,owner_id,assigned_by,request_id) values
 (-412211,-412211,'00000000-0000-0000-0000-000000412202','00000000-0000-0000-0000-000000412204',gen_random_uuid());
set local role authenticated;
do $$declare jobs jsonb; begin
 jobs:=public.solar_installation_jobs();
 assert not exists(select 1 from jsonb_array_elements(jobs) j where j->>'id'='-412211');
 assert exists(select 1 from jsonb_array_elements(jobs) j where j->>'id'='-412212' and (j->>'canManage')::boolean);
 begin perform public.solar_installation_action(-412211,1,'reopen','{}');raise exception 'Former manager reopened reassigned file';exception when insufficient_privilege then null;end;
end$$;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412202',true);
do $$declare job jsonb; schedule jsonb;begin
 select x into job from jsonb_array_elements(public.solar_installation_jobs()) x where x->>'id'='-412211';
 assert job->>'installationStatus'='closed' and job->>'creatorId'='00000000-0000-0000-0000-000000412201' and
  job->>'responsibleId'=auth.uid()::text and job->>'responsiblePhone'='07704122002' and (job->>'canManage')::boolean;
 assert not exists(select 1 from jsonb_array_elements(public.solar_installation_jobs()) j where j->>'id'='-412212');
 schedule:=public.solar_installation_schedule('2037-11-21','2037-11-22','00000000-0000-0000-0000-000000412203');
 assert exists(select 1 from jsonb_array_elements(schedule->'slots') s where s->>'id'='-412211' and s->>'own'='true' and s->>'responsibleName'='مستلم الوصل');
 assert exists(select 1 from jsonb_array_elements(schedule->'slots') s where s->>'own'='false' and not s?'party' and not s?'id');
 begin perform public.solar_installation_action(-412212,0,'close','{"amount":3}');raise exception 'Managed unselected file';exception when insufficient_privilege then null;end;
 perform public.solar_installation_action(-412211,1,'reopen','{}');
 perform public.solar_installation_action(-412211,2,'close','{"amount":250}');
 begin perform public.solar_installation_action(-412211,2,'close','{"amount":250}');raise exception 'Replayed stale expense revision';exception when sqlstate 'PT409' then null;end;
end$$;
reset role;
do $$ begin
 assert (select sum(delta) from public.solar_cash_entries where job_id=-412211 and owner_id='00000000-0000-0000-0000-000000412201')=-200;
 assert (select sum(delta) from public.solar_cash_entries where job_id=-412211 and owner_id='00000000-0000-0000-0000-000000412202')=-50;
 assert (select count(*)=2 from public.solar_cash_entries where job_id=-412211);
 assert (select count(*)=1 from public.solar_notifications where job_id=-412211 and event='installation_closed' and user_id='00000000-0000-0000-0000-000000412202');
 assert (select count(*)=1 from public.solar_notifications where job_id=-412211 and event='installation_closed' and user_id='00000000-0000-0000-0000-000000412201');
 assert exists(select 1 from transactions where id=-412211 and profit=450 and installation_expenses=250 and installation_status='closed'
  and created_by='00000000-0000-0000-0000-000000412201' and cashbox_user_id=created_by and installer_id='00000000-0000-0000-0000-000000412203');
end$$;
set local role authenticated;
select public.solar_installation_action(-412211,3,'reopen','{}');
select public.solar_installation_action(-412211,4,'clear_expenses','{}');
reset role;
do $$begin
 assert not exists(select 1 from public.solar_cash_entries where job_id=-412211 group by owner_id having sum(delta)<>0);
 assert (select count(*)=2 from public.solar_cash_entries where job_id=-412211 and entry_type='installation_refund' and actor_id='00000000-0000-0000-0000-000000412202');
end$$;
update profiles set permissions='{"system":true}' where id='00000000-0000-0000-0000-000000412202';
set local role authenticated;
do $$begin
 assert exists(select 1 from jsonb_array_elements(public.solar_installation_jobs()) j where j->>'id'='-412211' and j->>'canManage'='false' and not j?'cost');
 begin perform public.solar_installation_action(-412211,5,'close','{"amount":31}');raise exception 'Ignored loss of closing permission';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412203',true);
 assert exists(select 1 from jsonb_array_elements(public.solar_installation_jobs()) j where j->>'id'='-412211' and j->>'responsibleName'='مستلم الوصل' and not j?'cost');
end$$;
rollback;
