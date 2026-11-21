begin;
insert into public.profiles(id,display_name,is_admin,user_type,permissions,phone) values
 ('00000000-0000-0000-0000-000000412301','مهندس التقارير',false,'installer','{}','07704123001'),
 ('00000000-0000-0000-0000-000000412302','مسؤول المكتب الأول',false,'admin_staff','{"installations":true}','07704123002'),
 ('00000000-0000-0000-0000-000000412303','مسؤول المكتب المستلم',false,'admin_staff','{"installations":true}','07704123003'),
 ('00000000-0000-0000-0000-000000412304','إدارة التقارير',true,'admin_staff','{}','07704123004'),
 ('00000000-0000-0000-0000-000000412305','مكتب دون اعتماد',false,'admin_staff','{"system":true}','07704123005'),
 ('00000000-0000-0000-0000-000000412306','مهندس آخر',false,'installer','{}','07704123006');
insert into public.customers(id,name,customer_type,owner_id) values
 (-412301,'زبون اختبار دورة التقرير','system','00000000-0000-0000-0000-000000412302');
insert into public.transactions(id,kind,party_id,party_name,party_type,created_by,cashbox_user_id,installer_id,
 warehouse_id,warehouse_status,installation_status,total,cost,profit) values
 (-412301,'system',-412301,'زبون اختبار دورة التقرير','customer','00000000-0000-0000-0000-000000412302','00000000-0000-0000-0000-000000412302','00000000-0000-0000-0000-000000412301',1,'ready','pending',4000,900,3100),
 (-412302,'system',-412301,'زبون اختبار دورة التقرير','customer','00000000-0000-0000-0000-000000412305','00000000-0000-0000-0000-000000412305','00000000-0000-0000-0000-000000412301',1,'ready','pending',3000,900,2100);
select set_config('test.field.report','{"notes":"تم فحص المنظومة","checks":{"tested":true,"materials":true,"handover":true},"expenses":[{"description":"نقل","amount":60}]}',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412302',true);
set local role authenticated;
do $$begin
 assert not exists(select 1 from jsonb_array_elements(public.solar_installation_jobs()) j where j->>'id'='-412301' and (j->>'canCloseFile')::boolean);
 begin perform public.solar_installation_action(-412301,0,'close','{"amount":100}');raise exception 'closed before field work';exception when sqlstate 'PT409' then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412306',true);
 begin perform public.solar_installation_action(-412301,0,'start','{}');raise exception 'foreign engineer started';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412301',true);
 perform public.solar_installation_action(-412301,0,'start','{}');
 perform public.solar_installation_action(-412301,1,'complete',current_setting('test.field.report')::jsonb);
 begin perform public.solar_installation_action(-412301,1,'complete',current_setting('test.field.report')::jsonb);raise exception 'duplicated submission';exception when sqlstate 'PT409' then null;end;
end$$;
reset role;
do $$begin
 assert (select count(*)=1 from public.solar_notifications where event='completed' and job_id=-412301);
 assert exists(select 1 from public.solar_notifications where event='completed' and job_id=-412301 and user_id='00000000-0000-0000-0000-000000412302');
 assert not exists(select 1 from public.solar_cash_entries where job_id=-412301);
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412304',true);
insert into solar_private.customer_receipt_responsibility(transaction_id,customer_id,owner_id,assigned_by,request_id) values
 (-412301,-412301,'00000000-0000-0000-0000-000000412303','00000000-0000-0000-0000-000000412304',gen_random_uuid());
set local role authenticated;
do $$declare job jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412302',true);
 assert not exists(select 1 from public.solar_notifications where event='completed' and job_id=-412301);
 begin perform public.solar_installation_action(-412301,2,'return_report','{"notes":"تعليق"}');raise exception 'old reviewer returned';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412303',true);
 assert exists(select 1 from public.solar_notifications where event='completed' and job_id=-412301 and user_id=auth.uid());
 begin perform public.solar_installation_action(-412301,2,'return_report',jsonb_build_object('notes',chr(9)||chr(10)));raise exception 'missing correction note after newline';exception when invalid_parameter_value then null;end;
 select j into strict job from jsonb_array_elements(public.solar_installation_jobs()) j where j->>'id'='-412301';
 assert (job->>'canCloseFile')::boolean and (job->>'canReturnReport')::boolean and job#>>'{installationReview,status}'='submitted';
 assert job->>'responsibleId'=auth.uid()::text and job->>'installerPhone'='07704123001' and not (job->>'reviewerIsAdminTeam')::boolean;
 begin perform public.solar_installation_action(-412301,2,'return_report','{"notes":" "}');raise exception 'missing correction note';exception when invalid_parameter_value then null;end;
 perform public.solar_installation_action(-412301,2,'return_report','{"notes":"صحح عدد الألواح"}');
 begin perform public.solar_installation_action(-412301,3,'close','{"amount":60}');raise exception 'closed returned report without resubmission';exception when sqlstate 'PT409' then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412301',true);
 select j into strict job from jsonb_array_elements(public.solar_installation_jobs()) j where j->>'id'='-412301';
 assert job->>'installationStatus'='in_progress' and job#>>'{installationReview,notes}'='صحح عدد الألواح' and job#>>'{installationReview,status}'='returned';
 assert job->'installationReport'->>'submittedAt' is not null and not (job?'cost') and not (job?'installationExpenses');
 perform public.solar_installation_action(-412301,3,'complete',current_setting('test.field.report')::jsonb||'{"notes":"تصحيح العدد"}');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412303',true);
 perform public.solar_installation_action(-412301,4,'close','{"amount":100,"notes":"INTERNAL_REVIEW_ONLY"}');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412301',true);
 select j into strict job from jsonb_array_elements(public.solar_installation_jobs()) j where j->>'id'='-412301';
 assert job#>>'{installationReview,status}'='approved' and job#>>'{installationReview,actorId}'='00000000-0000-0000-0000-000000412303';
 assert job::text not like '%INTERNAL_REVIEW_ONLY%' and not (job?'total');
 assert (select count(*)=2 from public.solar_notifications where job_id=-412301 and user_id=auth.uid() and event='installation_updated' and (title like '%للتصحيح%' or title like '%أُغلق الملف%'));
 perform public.solar_installation_action(-412302,0,'start','{}');
 perform public.solar_installation_action(-412302,1,'complete',current_setting('test.field.report')::jsonb);
 select j into strict job from jsonb_array_elements(public.solar_installation_jobs()) j where j->>'id'='-412302';
 assert (job->>'reviewerIsAdminTeam')::boolean;
end$$;
reset role;
do $$begin
 assert exists(select 1 from public.solar_notifications where job_id=-412302 and event='completed' and user_id='00000000-0000-0000-0000-000000412304');
 assert not exists(select 1 from public.solar_notifications n join public.profiles p on p.id=n.user_id where n.job_id=-412302 and n.event='completed' and not p.is_admin);
 assert (select count(*)=2 from public.solar_notifications where job_id=-412301 and event='completed' and user_id='00000000-0000-0000-0000-000000412303');
 assert (select count(*)=4 from solar_private.installation_field_events where job_id=-412301);
 assert (select count(*)=1 and sum(delta)=-100 from public.solar_cash_entries where job_id=-412301 and owner_id='00000000-0000-0000-0000-000000412303');
 assert exists(select 1 from public.transactions where id=-412301 and profit=3000 and installation_status='closed' and created_by='00000000-0000-0000-0000-000000412302');
end$$;
rollback;
