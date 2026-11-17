-- V4.1.6 supplemental fixture; disposable LOCAL database only.
-- Requires version415-material-picker-browser-fixture.sql (or a clone containing it).
-- Use canonical invoice writes; only these synthetic timestamps are backdated
-- to exercise a historical negative balance without permitting negative stock.
begin;
insert into products(id,code,name,qty,cost,brand_id,category) values
(-415601,'V416-FRACTION','سلك توصيل اختبار الكسور والرصيد التاريخي السالب',0,1000,-415501,'كهربائيات');
insert into suppliers(id,name,account_currency)values(-415601,'مورد فحص الجدول المختصر','IQD');
insert into customers(id,name,customer_type,owner_id)values(-415601,'عميل فحص الجدول المختصر','wholesale','00000000-0000-0000-0000-000000415502');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000415502',true);
do $$declare r jsonb;i integer;main bigint:=solar_private.primary_warehouse();begin
 r:=public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','purchase','warehouseId',main,'party','مورد فحص الجدول المختصر','partyId',-415601,'mode','credit','sourceCurrency','IQD','exchangeRate',1,'marketRate',1660,'accountRevision',0,'notes','بداية توريد المادة لكشف الكميات الكسرية','items','[{"id":-415601,"qty":3.25,"price":1000}]'::jsonb));
 r:=public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','sale','warehouseId',main,'party','عميل فحص الجدول المختصر','partyId',-415601,'mode','credit','notes','فاتورة اختبار تاريخية مع بيان كامل: '||repeat('يرجى مطابقة الكمية مع أمر التسليم والمخزن المعني. ',9)||'نهاية ملاحظة الجدول V416','items','[{"id":-415601,"qty":1.5,"price":2000}]'::jsonb));
 update transactions set created_at='2026-11-09T09:00:00+03' where id=(r->>'id')::bigint;
 for i in 1..35 loop
  r:=public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','purchase','warehouseId',main,'party','مورد فحص الجدول المختصر','partyId',-415601,'mode','credit','sourceCurrency','IQD','exchangeRate',1,'marketRate',1660,'accountRevision',0,'notes','حركة كسرية رقم '||i,'items','[{"id":-415601,"qty":0.125,"price":1000}]'::jsonb));
 end loop;
end$$;
-- Keep a complete long stock note available to collapsed-row and PDF detail tests.
update solar_private.stock_adjustments set note='ملاحظة حركة الجدول V416: '||repeat('يجب مطابقة الرصيد المحفوظ مع مستند المخزن دون تغيير الكميات. ',8)||'نهاية ملاحظة الجدول V416' where product_id=-415501;
commit;
