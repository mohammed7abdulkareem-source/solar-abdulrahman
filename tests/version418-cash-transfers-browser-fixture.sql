-- V4.1.8 synthetic LOCAL browser database only. Never execute against production.
begin;
insert into profiles(id,display_name,username,is_admin,user_type,active,phone,permissions) values
('00000000-0000-0000-0000-000000418501','مدير الصندوق العام V418','qa418admin',true,'admin_staff',true,'07704185001','{}'),
('00000000-0000-0000-0000-000000418502','سفيان عبدالرحمن مسؤول مبيعات المنظومات والمشاريع الطويلة V418','qa418sender',false,'admin_staff',true,'07704185002','{"cash":true,"cashAdminTools":true,"cashDeposit":true,"cashExpense":true,"cashTransferSend":true,"financeReceive":true}'),
('00000000-0000-0000-0000-000000418503','محمد أحمد مسؤول استلام الأموال والحسابات المالية V418','qa418recipient',false,'admin_staff',true,'07704185003','{"cash":true,"cashExpense":true,"cashTransferSend":true,"financeReceive":true}'),
('00000000-0000-0000-0000-000000418504','عبدالرحمن مرسل التحويلات الأخرى V418','qa418other_sender',false,'admin_staff',true,'07704185004','{"cash":true,"cashExpense":true,"cashTransferSend":true,"financeReceive":true}'),
('00000000-0000-0000-0000-000000418505','حسين فائق مستلم التحويلات الأخرى V418','qa418other_recipient',false,'admin_staff',true,'07704185005','{"cash":true,"cashExpense":true,"cashTransferSend":true,"financeReceive":true}'),
('00000000-0000-0000-0000-000000418506','قاصة التسليم المباشر بالدينار والدولار V418','qa418source',false,'admin_staff',true,'07704185006','{"cash":true,"financeReceive":true}'),
('00000000-0000-0000-0000-000000418507','قاصة بدون رصيد V418','qa418zero',false,'admin_staff',true,'07704185007','{"cash":true,"financeReceive":true}'),
('00000000-0000-0000-0000-000000418508','مخزن بصلاحية استلام قديمة V418','qa418warehouse',false,'warehouse',true,'07704185008','{"cash":true,"financeReceive":true}'),
('00000000-0000-0000-0000-000000418509','مستخدم استلام موقوف V418','qa418inactive',false,'admin_staff',false,'07704185009','{"cash":true,"financeReceive":true}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418501',true);
select public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',id,'mode','deposit','currency','IQD','amount',amount,'note','تمويل اختبار تحويلات V418')) from (values
('00000000-0000-0000-0000-000000418501',5000000),('00000000-0000-0000-0000-000000418502',2000000000),('00000000-0000-0000-0000-000000418503',1000),('00000000-0000-0000-0000-000000418504',2000000),('00000000-0000-0000-0000-000000418506',1250000)) f(id,amount);
select public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',id,'mode','deposit','currency','USD','amount',amount,'rate',1660,'note','تمويل دولار تحويلات V418')) from (values
('00000000-0000-0000-0000-000000418501',123.45),('00000000-0000-0000-0000-000000418506',250.5)) f(id,amount);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418502',true);
select public.solar_cash_transfer_send('00000000-0000-0000-0000-000000418601','00000000-0000-0000-0000-000000418503',1234567890,25000,'نقل الطلبات V418','معلق كبير إلى محمد V418');
select public.solar_cash_transfer_send('00000000-0000-0000-0000-000000418602','00000000-0000-0000-0000-000000418505',120000,7000,'نقل يبقى بعد الإلغاء V418','معلق قابل للإلغاء V418');
select public.solar_cash_transfer_send('00000000-0000-0000-0000-000000418605','00000000-0000-0000-0000-000000418503',50000,1000,'مصروف تحويل مستلم V418','تحويل مستلم سابق V418');
select public.solar_cash_transfer_send('00000000-0000-0000-0000-000000418606','00000000-0000-0000-0000-000000418503',60000,2000,'مصروف تحويل ملغى V418','تحويل ملغى سابق V418');
select public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000418606','cancelled');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418503',true);
select public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000418605','accepted');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418504',true);
select public.solar_cash_transfer_send('00000000-0000-0000-0000-000000418603','00000000-0000-0000-0000-000000418502',400000,0,'','وارد إلى سفيان V418');
select public.solar_cash_transfer_send('00000000-0000-0000-0000-000000418604','00000000-0000-0000-0000-000000418505',300000,0,'','تحويل خاص بالمستخدمين الآخرين V418');
commit;
