begin;
insert into public.profiles(id,display_name,is_admin,user_type,permissions,phone)values
('00000000-0000-0000-0000-000000399891','مالك الأرشيف',false,'admin_staff','{"supplierStatement":true,"cash":true}','07701234567'),
('00000000-0000-0000-0000-000000399892','مستخدم آخر',false,'admin_staff','{"supplierStatement":true,"cash":true}','07701234567');
insert into public.suppliers(id,name)values(-3998901,'مورد الأرشيف المعزول');
do $$declare se bigint;sr bigint;we bigint;wr bigint;data jsonb;row jsonb;cash_row record;before_hash text;after_hash text;begin
 insert into solar_private.supplier_fx_entries(supplier_id,owner_id,currency,revision,delta,book_delta,gain,rate)
 values(-3998901,'00000000-0000-0000-0000-000000399891','IQD',0,500000,500000,0,1500)returning id into se;
 insert into solar_private.supplier_fx_entries(supplier_id,owner_id,currency,revision,delta,book_delta,gain,rate,correction_for,note)
 values(-3998901,'00000000-0000-0000-0000-000000399891','IQD',0,-500000,-500000,0,1500,-3998901,'إلغاء شراء #399')returning id into sr;
 insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,gain,rate,entry_type)
 values('00000000-0000-0000-0000-000000399891','USD',-100,-150000,0,1500,'supplier_cash')returning id into we;
 insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,gain,rate,entry_type,note)
 values('00000000-0000-0000-0000-000000399891','USD',100,150000,0,1500,'purchase_refund','إلغاء شراء #399')returning id into wr;
 insert into solar_private.deleted_sales(invoice_id,invoice,items) values(-3998901,
 jsonb_build_object('id',-3998901,'kind','purchase','receipt_no',399,'party_name','مورد الأرشيف المعزول','notes','ملاحظة الوصل الأصلي','created_by','00000000-0000-0000-0000-000000399891',
 'purchaseCancellation',jsonb_build_object('supplierEntry',jsonb_build_object('id',se),'walletEntry',jsonb_build_object('id',we),'supplierReversalId',sr,'walletReversalId',wr,'privateSecret','not-for-client')),'[]');
 before_hash:=(select md5(jsonb_agg(to_jsonb(e)order by e.id)::text)from solar_private.supplier_fx_entries e where supplier_id=-3998901);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000399891',true);
 data:=solar_private.fx('statement',null,'{"supplierId":-3998901}');
 assert(data->>'balance')::numeric=0 and(data->>'bookBalance')::numeric=0;
 assert jsonb_array_length(data->'rows')=2;
 select value into row from jsonb_array_elements(data->'rows')where(value->>'id')::bigint=se;
 assert row->'transaction'='null'::jsonb and row->'items'='[]'::jsonb,'Archived invoice became an active invoice';
 assert row->'archivedPurchase'->>'receiptNo'='399' and row->'archivedPurchase'->>'entryRole'='original';
 assert row->>'note' like 'شراء ملغى #399%';
 assert not row->'archivedPurchase'?'purchaseCancellation' and position('privateSecret' in row::text)=0,'Private plan leaked';
 select value into row from jsonb_array_elements(data->'rows')where(value->>'id')::bigint=sr;
 assert row->'archivedPurchase'->>'entryRole'='reversal';
 select * into cash_row from solar_private.cash_movements()where id='fx:'||we;
 assert cash_row.kind='purchase_cancelled' and cash_row.party='مورد الأرشيف المعزول' and cash_row.receipt_no=399;
 assert cash_row.delta=-100 and cash_row.book_delta=-150000 and cash_row.note like '%ملاحظة الوصل الأصلي';
 select * into cash_row from solar_private.cash_movements()where id='fx:'||wr;
 assert cash_row.kind='purchase_refund' and cash_row.delta=100 and cash_row.book_delta=150000 and cash_row.receipt_no=399;
 after_hash:=(select md5(jsonb_agg(to_jsonb(e)order by e.id)::text)from solar_private.supplier_fx_entries e where supplier_id=-3998901);
 assert before_hash=after_hash,'Read-model integration mutated ledger';
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000399892',true);
 assert solar_private.purchase_archive_entry('supplier',se)is null and solar_private.purchase_archive_entry('wallet',we)is null;
 data:=solar_private.fx('statement',null,'{"supplierId":-3998901}');assert data->'rows'='[]'::jsonb,'Foreign archived entry leaked';
 assert not has_function_privilege('anon','solar_private.purchase_archive_entry(text,bigint)','execute');
 assert not has_function_privilege('authenticated','solar_private.purchase_archive_entry(text,bigint)','execute');
end$$;
\echo PASS archived supplier and USD cash receipt labels, no active invoices/private plans, unchanged balances and own-user scope
rollback;
