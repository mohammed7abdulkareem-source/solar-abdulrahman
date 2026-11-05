-- Disposable local database only. Never load into a hosted project.
\set ON_ERROR_STOP on
begin;
do $$begin
 if current_database() !~ '^solar_[a-z0-9_]+_browser$' then raise exception 'Browser fixtures require a disposable local browser database';end if;
end$$;
insert into profiles(id,display_name,is_admin,user_type,permissions,phone) values
('00000000-0000-0000-0000-000000039901','مدير إلغاء شراء المتصفح',true,'admin_staff','{}','07700399001'),
('00000000-0000-0000-0000-000000039902','صاحب شراء المتصفح',false,'admin_staff','{"purchase":true,"sale":true,"cash":true,"stock":true,"supplierStatement":true,"supplierBalances":true}','07700399002');
insert into suppliers(id,name,account_currency) values(-399101,'مورد اختبار إلغاء الشراء','IQD');
insert into customers(id,name,customer_type,owner_id) values(-399101,'عميل اختبار إلغاء الشراء','wholesale','00000000-0000-0000-0000-000000039902');
insert into products(id,code,name,qty,cost) values
(-399101,'BROWSER-VOID-399-A','انفيرتر إلغاء مع حركة لاحقة',10,1000),
(-399102,'BROWSER-VOID-399-B','انفيرتر إلغاء نقدي',10,1000),
(-399103,'BROWSER-VOID-399-C','انفيرتر نقص الإلغاء',0,0);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000039901',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000039902","mode":"deposit","currency":"IQD","amount":100000,"note":"رصيد اختبار معزول"}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000039902',true);
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","mode":"credit","partyId":-399101,"party":"مورد اختبار إلغاء الشراء","warehouseId":1,"sourceCurrency":"IQD","notes":"browser-v399-first","items":[{"id":-399101,"qty":2,"price":2000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","mode":"credit","partyId":-399101,"party":"مورد اختبار إلغاء الشراء","warehouseId":1,"sourceCurrency":"IQD","notes":"browser-v399-later","items":[{"id":-399101,"qty":3,"price":3000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"credit","partyId":-399101,"party":"عميل اختبار إلغاء الشراء","warehouseId":1,"notes":"browser-v399-sale","items":[{"id":-399101,"qty":2,"price":5000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","mode":"cash","partyId":-399101,"party":"مورد اختبار إلغاء الشراء","warehouseId":1,"sourceCurrency":"IQD","notes":"browser-v399-cash","items":[{"id":-399102,"qty":1,"price":1000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"credit","partyId":-399101,"party":"عميل اختبار إلغاء الشراء","warehouseId":1,"notes":"browser-v399-cash-sale","items":[{"id":-399102,"qty":1,"price":5000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","mode":"credit","partyId":-399101,"party":"مورد اختبار إلغاء الشراء","warehouseId":1,"sourceCurrency":"IQD","notes":"browser-v399-short","items":[{"id":-399103,"qty":2,"price":1000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"credit","partyId":-399101,"party":"عميل اختبار إلغاء الشراء","warehouseId":1,"notes":"browser-v399-short-sale","items":[{"id":-399103,"qty":1,"price":5000}]}');
set constraints all immediate;
commit;
