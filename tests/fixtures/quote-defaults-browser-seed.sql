-- Add only synthetic test managers to an isolated local quotation database.
begin;
insert into profiles(id,display_name,user_type,is_admin,permissions,phone)values
('00000000-0000-0000-0000-000000003920','مدير مصاريف التحصيل','admin_staff',true,'{}','07700003920'),
('00000000-0000-0000-0000-000000003921','مخول مصاريف التحصيل','admin_staff',false,'{"system":true,"tahseel":true,"tahseelFull":true,"tahseelDefaults":true}','07700003921');
commit;
