-- Only use with a disposable, local browser database.
\set ON_ERROR_STOP on
begin;
do $$begin
 if current_database() !~ '^solar_[a-z0-9_]+_browser$' then raise exception 'Use a disposable local browser database';end if;
end$$;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions)values
('00000000-0000-0000-0000-000000004100','مدير اختبار رصيد التسليم',true,'admin_staff','07700004100','{}'),
('00000000-0000-0000-0000-000000004101','القاصة الدافعة الأولى',false,'admin_staff','07700004101','{"cash":true}'),
('00000000-0000-0000-0000-000000004102','القاصة الدافعة الثانية',false,'admin_staff','07700004102','{"cash":true}'),
('00000000-0000-0000-0000-000000004103','قاصة مستلم كامل المبلغ',false,'admin_staff','07700004103','{"cash":true}'),
('00000000-0000-0000-0000-000000004104','قاصة رصيد صفر',false,'admin_staff','07700004104','{"cash":true}'),
('00000000-0000-0000-0000-000000004105','قاصة رصيد سالب',false,'admin_staff','07700004105','{"cash":true}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000004100',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000004101","mode":"deposit","currency":"IQD","amount":1250000,"note":"اختبار رصيد التسليم – دينار المصدر الأول"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000004101","mode":"deposit","currency":"USD","amount":250.5,"rate":1500,"note":"اختبار رصيد التسليم – دولار المصدر الأول"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000004102","mode":"deposit","currency":"IQD","amount":750000,"note":"اختبار رصيد التسليم – دينار المصدر الثاني"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000004102","mode":"deposit","currency":"USD","amount":100.25,"rate":1500,"note":"اختبار رصيد التسليم – دولار المصدر الثاني"}');
select public.solar_cash_record(action=>'transfer',request_id=>gen_random_uuid(),payload=>'{"senderId":"00000000-0000-0000-0000-000000004105","recipientId":"00000000-0000-0000-0000-000000004100","currency":"IQD","amount":50000,"note":"تهيئة رصيد سالب من تسليم دينار وفق الآلية الحالية"}');
set constraints all immediate;
commit;
