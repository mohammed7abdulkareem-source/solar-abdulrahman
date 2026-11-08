-- Synthetic fixtures for a disposable local browser database only.
\set ON_ERROR_STOP on
begin;
do $$begin
 if current_database() !~ '^solar_[a-z0-9_]+_browser$' then raise exception 'Use a disposable local browser database';end if;
end$$;
insert into profiles(id,display_name,is_admin,user_type,permissions,phone)values
('00000000-0000-0000-0000-000000040001','مستخدم وضوح التقارير',false,'admin_staff','{"purchase":true,"sale":true,"stock":true,"stockMovement":true,"cash":true,"profit":true,"customerStatement":true,"supplierStatement":true,"exchangeRateEdit":true}','07700400001');
insert into suppliers(id,name,account_currency)values(-400001,'مورد وضوح التفاصيل والأسعار','IQD');
insert into customers(id,name,customer_type,owner_id,phone)values(-400001,'عميل وضوح التقارير','wholesale','00000000-0000-0000-0000-000000040001','07700400002');
insert into products(id,code,name,qty,cost,category)values(-400001,'CLARITY-400','لوح شمسي عالي الكفاءة 600W / FULLMAX – وصف تفصيلي طويل للمادة',50,100000,'ألواح');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003920',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000040001","mode":"deposit","currency":"IQD","amount":123456789.12,"note":"رصيد افتتاحي تجريبي لقراءة المبالغ الكبيرة"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000040001","mode":"deposit","currency":"USD","amount":12345.67,"rate":1500,"note":"دولار تجريبي مستقل عن رصيد الدينار"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000040001","mode":"expense","currency":"IQD","amount":35000,"note":"مصروف تشغيل تجريبي – بيان طويل يوضح سبب الصرف والجهة المستلمة وتفاصيل العملية"}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000040001',true);
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","mode":"credit","partyId":-400001,"party":"مورد وضوح التفاصيل والأسعار","warehouseId":1,"sourceCurrency":"IQD","expenses":25000,"notes":"شراء تجريبي: النقل والتنزيل ضمن الكلفة المثبتة للمادة","items":[{"id":-400001,"qty":10,"price":125000}]}');
do $$declare n integer;begin
 for n in 1..12 loop
  perform public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','sale','mode','credit','partyId',-400001,'party','عميل وضوح التقارير','warehouseId',1,
   'notes','حركة تجريبية رقم '||n||' – بيان تفصيلي طويل لاختبار وضوح السطر والأرقام في كشف الحساب ومعاينة PDF',
   'items',jsonb_build_array(jsonb_build_object('id',-400001,'qty',1,'price',175000+n*100))));
 end loop;
end$$;
set constraints all immediate;
commit;
