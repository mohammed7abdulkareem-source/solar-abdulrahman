-- V4.1.7 disposable LOCAL browser database only. Never run on production.
begin;
insert into profiles(id,display_name,username,is_admin,user_type,active,permissions)values
('00000000-0000-0000-0000-000000417501','مدير مطابقة القاصات V417','qa417admin',true,'admin_staff',true,'{}'),
('00000000-0000-0000-0000-000000417502','إداري بصلاحيات قديمة V417','qa417legacy',false,'admin_staff',true,'{"cash":true,"cashAdminTools":true,"cashDeposit":true,"cashExpense":true,"cashExchange":true,"cashTransferSend":true,"financeReceive":true}'),
('00000000-0000-0000-0000-000000417503','موظف العمليات اليومية V417','qa417staff',false,'admin_staff',true,'{"cash":true,"cashExpense":true,"cashExchange":true,"cashTransferSend":true,"financeReceive":true}'),
('00000000-0000-0000-0000-000000417504','مسؤول مخزن بعلم قديم V417','qa417warehouse',true,'warehouse',true,'{"cash":true,"cashAdminTools":true}'),
('00000000-0000-0000-0000-000000417505','مهندس بعلم قديم V417','qa417installer',true,'installer',true,'{"cash":true,"cashAdminTools":true}'),
('00000000-0000-0000-0000-000000417506','مدير موقوف V417','qa417inactive',true,'admin_staff',false,'{"cash":true,"cashAdminTools":true}'),
('00000000-0000-0000-0000-000000417507','مدير تسحب صلاحيته V417','qa417demote',true,'admin_staff',true,'{"cash":true,"cashAdminTools":true,"cashExpense":true}');
update profiles set phone='0770417500'||right(id::text,1) where id between '00000000-0000-0000-0000-000000417501' and '00000000-0000-0000-0000-000000417507';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000417501',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000417501","mode":"deposit","currency":"IQD","amount":100000,"note":"تمويل اختبار محلي V417"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000417501","mode":"deposit","currency":"USD","amount":25,"rate":1660,"note":"تمويل دولار محلي V417"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000417502","mode":"deposit","currency":"IQD","amount":20000,"note":"تمويل اختبار محلي V417"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000417502","mode":"deposit","currency":"USD","amount":5,"rate":1660,"note":"تمويل دولار محلي V417"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000417503","mode":"deposit","currency":"IQD","amount":15000,"note":"تمويل اختبار محلي V417"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000417507","mode":"deposit","currency":"IQD","amount":8000,"note":"تمويل اختبار محلي V417"}');
commit;
