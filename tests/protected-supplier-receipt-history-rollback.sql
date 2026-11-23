-- Local fixtures for pre-existing requests and pre-FK purchase/payment archives.
\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,display_name,is_admin,user_type,active,permissions,phone) values
 ('00000000-0000-0000-0000-000000413401','قارئ اختباري',false,'admin_staff',true,'{"purchase":true,"deletionRequests":true,"supplierStatement":true,"supplierPayment":true}','07700413401'),
 ('00000000-0000-0000-0000-000000413402','أدمن اختباري',true,'admin_staff',true,'{}','07700413402');

insert into solar_private.deleted_sales(invoice_id,invoice,items) values
 (-413401,'{"kind":"purchase","party_name":" ABDULRAHMAN ","created_by":"00000000-0000-0000-0000-000000413401"}','[]');
insert into solar_private.receipt_delete_requests(id,invoice_id,kind,owner_id,requested_by,request_token,snapshot,submission) values
 ('00000000-0000-0000-0000-000000413411',-413411,'supplier_payment','00000000-0000-0000-0000-000000413401','00000000-0000-0000-0000-000000413401','token',
  '{"kind":"supplier_payment","party":"ABDULRAHMAN","invoice":{"kind":"supplier_payment","party_name":"ABDULRAHMAN"}}','{}'),
 ('00000000-0000-0000-0000-000000413412',-413412,'purchase','00000000-0000-0000-0000-000000413401','00000000-0000-0000-0000-000000413401','token',
  '{"kind":"purchase","party":"مورّد عادي"}','{}');

insert into public.solar_notifications(user_id,event,title,body,delete_request_id)
 select owner_id,'receipt_delete_decided','قرار','تحديث على طلب الحذف',id from solar_private.receipt_delete_requests
 where id in ('00000000-0000-0000-0000-000000413411','00000000-0000-0000-0000-000000413412');

insert into solar_private.receipt_delete_executions(request_id,invoice_id,actor_id,mode,submission,snapshot,execution_txid,completed_at,result)
 values('00000000-0000-0000-0000-000000413413',-413413,'00000000-0000-0000-0000-000000413401','direct',
  '{"invoiceId":-413413}','{"kind":"purchase","party":"Abdulrahman"}',txid_current(),now(),'{"status":"deleted"}');
insert into solar_private.invoice_requests(request_id,user_id,payload,result) values
 ('00000000-0000-0000-0000-000000413414','00000000-0000-0000-0000-000000413401',
  '{"kind":"purchase","party":"مورّد عادي"}','{"id":-413401,"total":1000}');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413401',true);
set local role authenticated;
do $$
declare rows jsonb; action text; body jsonb:='{"kind":"purchase","party":"مورّد عادي"}';
begin
 rows:=public.solar_receipt_delete_requests('list',null,'{}')->'rows';
 assert not exists(select 1 from jsonb_array_elements(rows) x where x->>'invoiceId'='-413411');
 assert exists(select 1 from jsonb_array_elements(rows) x where x->>'invoiceId'='-413412');
 assert not exists(select 1 from public.solar_notifications where delete_request_id='00000000-0000-0000-0000-000000413411');
 assert exists(select 1 from public.solar_notifications where delete_request_id='00000000-0000-0000-0000-000000413412');
 foreach action in array array['get','request','cancel','approve','reject'] loop
  begin perform public.solar_receipt_delete_requests(action,'00000000-0000-0000-0000-000000413411','{}');
   raise exception 'Staff accessed a protected pending request via %',action;
  exception when insufficient_privilege then null;end;
 end loop;
 begin perform public.solar_receipt_delete_requests('delete_direct','00000000-0000-0000-0000-000000413413','{"invoiceId":-413413}');
  raise exception 'Staff replayed a historical protected deletion';
 exception when insufficient_privilege then null;end;
 begin perform public.solar_receipt_delete_requests('context',null,'{"invoiceId":-413401}');
  raise exception 'Staff inspected a protected archived purchase';
 exception when insufficient_privilege then null;end;
 begin perform public.solar_invoice_attempt_resolve('00000000-0000-0000-0000-000000413414',body);
  raise exception 'Staff resolved an ordinary request moved to the protected supplier';
 exception when insufficient_privilege then null;end;
 begin perform public.solar_invoice_save('00000000-0000-0000-0000-000000413414',body);
  raise exception 'Staff replayed an ordinary request moved to the protected supplier';
 exception when insufficient_privilege then null;end;
 begin perform public.solar_purchase_correction_preview(body||'{"invoiceId":-413401}');
  raise exception 'Staff previewed a protected archived invoice';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413402',true);
 rows:=public.solar_receipt_delete_requests('list',null,'{}')->'rows';
 assert exists(select 1 from jsonb_array_elements(rows) x where x->>'invoiceId'='-413411');
 assert public.solar_receipt_delete_requests('get','00000000-0000-0000-0000-000000413411','{}')#>>'{snapshot,party}'='ABDULRAHMAN';
end$$;
rollback;
