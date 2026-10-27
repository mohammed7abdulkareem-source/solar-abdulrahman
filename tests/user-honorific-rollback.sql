begin;
insert into profiles(id,display_name,honorific,username,is_admin,user_type,permissions,phone)values
('00000000-0000-0000-0000-000000003795','مدير الكنية','الإداري','honorific_admin',true,'admin_staff','{}','07701234567'),
('00000000-0000-0000-0000-000000003796','سفيان','الحاج','honorific_staff',false,'admin_staff','{"system":true,"salesHistory":true,"installations":true,"cash":true}','07701234567'),
('00000000-0000-0000-0000-000000003797','صفاء','المهندس','honorific_engineer',false,'installer','{"installations":true}','07701234567');
insert into customers(id,name,customer_type,owner_id)values(-379501,'عميل اختبار الكنية','system','00000000-0000-0000-0000-000000003796');
insert into brands(id,name)values(-379501,'TEST BRAND');
insert into products(id,code,name,brand_id,category,qty,cost)values(-379501,'TITLE-379','بطارية اختبار الكنية',-379501,'بطارية',5,100000);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003796',true);
do $$declare r jsonb;d jsonb;changed integer;begin
 r:=public.solar_invoice_save('00000000-0000-0000-0000-000000037951','{"kind":"system","mode":"credit","party":"عميل اختبار الكنية","total":500000,"customerAddress":"بغداد","sourceCurrency":"IQD","exchangeRate":1,"expenses":0,"installerId":"00000000-0000-0000-0000-000000003797","items":[{"id":-379501,"qty":1,"price":0}],"warranty":{"enabled":true,"items":[{"id":-379501,"duration":5,"unit":"years"}],"maintenance":{"duration":0,"unit":"months"}}}');
 assert r->>'creatorName'='الحاج سفيان',r::text;
 d:=public.solar_warranty_verify((r->>'warrantyToken')::uuid);
 assert d->>'installer'='المهندس صفاء';
 assert d->'items'->0->>'brand'='TEST BRAND' and d->'items'->0->>'category'='بطارية';
 assert not(d->'maintenanceStatus'->>'covered')::boolean;
 perform set_config('test.honorific_invoice',r->>'id',true);
 begin update public.profiles set honorific='الأدمن' where id=auth.uid();get diagnostics changed=row_count;assert changed=0;exception when insufficient_privilege then null;end;
 d:=public.solar_receipt_contacts();assert exists(select 1 from jsonb_array_elements(d)x where x->>'creatorName'='الحاج سفيان');
end$$;
reset role;
select set_config('test.honorific_finances',(select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)order by id)from transactions t),'items',(select jsonb_agg(to_jsonb(i)order by id)from transaction_items i),'cash',(select jsonb_agg(to_jsonb(e)order by id)from solar_cash_entries e))::text)),true);
update profiles set honorific='الإداري' where id='00000000-0000-0000-0000-000000003796';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003795',true);
do $$declare d jsonb;begin
 d:=public.solar_staff_directory();assert exists(select 1 from jsonb_array_elements(d)x where x->>'id'='00000000-0000-0000-0000-000000003796' and x->>'display_name'='سفيان' and x->>'honorific'='الإداري');
 d:=public.solar_receipt_contacts();assert exists(select 1 from jsonb_array_elements(d)x where x->>'creatorName'='الإداري سفيان');
 d:=public.solar_cash_workspace('{"ownerId":"00000000-0000-0000-0000-000000003796"}');assert d->>'ownerName'='الإداري سفيان';
 d:=public.solar_cash_statement('00000000-0000-0000-0000-000000003796','2026-10-01','2026-10-31','all');assert d->>'ownerName'='الإداري سفيان';
 assert solar_private.user_name('المهندس صفاء','safaa','المهندس')='المهندس صفاء';
 assert solar_private.user_name('صفاء','safaa','')='صفاء';
end$$;
reset role;
do $$begin
 assert current_setting('test.honorific_finances')=(select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)order by id)from transactions t),'items',(select jsonb_agg(to_jsonb(i)order by id)from transaction_items i),'cash',(select jsonb_agg(to_jsonb(e)order by id)from solar_cash_entries e))::text));
 begin update profiles set honorific=repeat('ا',51) where id='00000000-0000-0000-0000-000000003796';raise exception 'Long title accepted';exception when check_violation then null;end;
 assert not has_function_privilege('anon','solar_private.user_name(text,text,text)','execute');
end$$;
rollback;
