insert into public.profiles(id,display_name,is_admin,permissions,user_type) values
 ('00000000-0000-0000-0000-000000003330','المدير التجريبي',true,'{}','admin_staff'),
 ('00000000-0000-0000-0000-000000003331','مبيعات أحمد',false,'{"customerDebts":true,"customerStatement":true}','admin_staff'),
 ('00000000-0000-0000-0000-000000003332','مبيعات سيف',false,'{"customerDebts":true,"customerStatement":true}','admin_staff');
insert into public.customers(id,name,phone,customer_type,owner_id) values
 (-333001,'أحمد علي','07701234567','wholesale','00000000-0000-0000-0000-000000003331'),
 (-333002,'سيف حسن','07801234567','system','00000000-0000-0000-0000-000000003331'),
 (-333003,'محمد كريم','07901234567','wholesale','00000000-0000-0000-0000-000000003332');
insert into public.customers(id,name,phone,customer_type,owner_id)
 select -334000-n,'عميل تجريبي '||n,'',case when n%3=0 then 'wholesale' else 'system' end,
 case when n%2=0 then '00000000-0000-0000-0000-000000003331'::uuid else '00000000-0000-0000-0000-000000003332'::uuid end from generate_series(1,28) n;
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_at,created_by,cashbox_user_id) values
 (-333001,'customer_payment',-333001,'أحمد علي',-2000000,false,'opening_balance','2026-10-01 10:00Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331'),
 (-333002,'sale',-333001,'اسم سابق',500000,false,'credit','2026-10-02 10:00Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331'),
 (-333003,'customer_payment',-333001,'أحمد علي',500000,true,'payment','2026-10-03 10:00Z','00000000-0000-0000-0000-000000003330','00000000-0000-0000-0000-000000003330'),
 (-333004,'sale',null,'احمدعلي',50000,false,'credit','2026-10-04 10:00Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331'),
 (-333005,'system_payment',-333002,'سيف حسن',-3000000,false,'opening_balance','2026-10-01 10:00Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331'),
 (-333006,'system_payment',-333002,'سيف حسن',1000000,true,'payment','2026-10-04 21:30Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331'),
 (-333007,'customer_payment',-333003,'محمد كريم',-4000000,false,'opening_balance','2026-10-01 10:00Z','00000000-0000-0000-0000-000000003332','00000000-0000-0000-0000-000000003332'),
 (-333008,'customer_payment',-399999,'أحمد علي',-2000,false,'opening_balance','2026-10-01 10:00Z','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331');
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_at,created_by,cashbox_user_id)
 select -334000-n,case when c.customer_type='system' then 'system_payment' else 'customer_payment' end,c.id,c.name,-100000-n*1000,false,'opening_balance','2026-10-01 10:00Z',c.owner_id,c.owner_id
 from generate_series(1,28) n join public.customers c on c.id=-334000-n;
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_at,created_by,cashbox_user_id,notes)
 select -335000-n,'customer_payment',-333001,'أحمد علي',1000,true,'payment','2026-10-05 10:00Z'::timestamptz+n*interval '1 minute','00000000-0000-0000-0000-000000003331','00000000-0000-0000-0000-000000003331','تسديد تجريبي محفوظ بحركة مستقلة '||n from generate_series(1,30) n;
