-- Disposable local DB. Exercise the actual purchase, preview and delete RPCs.
\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,display_name,is_admin,user_type,active,permissions,phone) values
 ('00000000-0000-0000-0000-000000413310','مدير اختبار المشتريات',true,'admin_staff',true,'{}','07700413310'),
 ('00000000-0000-0000-0000-000000413311','مستخدم اختبار المشتريات',false,'admin_staff',true,'{"purchase":true,"deletionRequests":true,"supplierStatement":true}','07700413311');
insert into public.suppliers(id,name,account_currency) values
 (-413311,'مورد أول لاختبار الدين','IQD'),(-413312,'مورد ثان لاختبار الدين','IQD'),
 (-413313,'مورد اختبار الدين بالدولار','USD');
insert into public.products(id,code,name,qty,cost)values(-413311,'4133-DEBT','مادة اختبار الدين',0,0);
insert into public.solar_cash_entries(owner_id,actor_id,delta,entry_type)
 values('00000000-0000-0000-0000-000000413311','00000000-0000-0000-0000-000000413310',100000,'transfer_in');
update solar_private.operation_controls set purchase_paused=false where id;

-- Read committed effects independent of the user's statement view.
create function pg_temp.purchase_effect(i bigint) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_array(
  (select to_jsonb(t) from public.transactions t where t.id=i),
  (select jsonb_agg(to_jsonb(x) order by x.id) from solar_private.supplier_fx_entries x where x.transaction_id=i),
  (select jsonb_agg(to_jsonb(x) order by x.id) from public.transaction_items x where x.transaction_id=i),
  (select jsonb_agg(to_jsonb(x) order by x.warehouse_id) from solar_private.warehouse_stocks x where x.product_id=-413311))
$$;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413311',true);
select set_config('test.debt.warehouse',solar_private.primary_warehouse()::text,true);
set local role authenticated;
do $$
declare
 body jsonb:=jsonb_build_object('kind','purchase','mode','credit','partyId',-413311,'party','مورد أول لاختبار الدين',
  'warehouseId',current_setting('test.debt.warehouse')::bigint,'sourceCurrency','IQD','cashCurrency','IQD','exchangeRate',1,
  'marketRate',1500,'accountRevision',0,'expenses',0,'items',jsonb_build_array(jsonb_build_object('id',-413311,'qty',2,'price',1000)));
 result jsonb; correction jsonb; candidate jsonb; plan jsonb; context jsonb; snapshot jsonb; i bigint; cash_id bigint;
begin
 -- Cash creation and cancellation still have no supplier liability.
 result:=public.solar_invoice_save(gen_random_uuid(),body||'{"mode":"cash"}'); cash_id:=(result->>'id')::bigint;
 context:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',cash_id));
 assert(context->>'directEligible')::boolean;
 -- A previously posted cash purchase cannot be turned into a supplier debt through legacy editing.
 candidate:=body||jsonb_build_object('invoiceId',cash_id,'expectedRevision',result->'pricingRevision');
 plan:=public.solar_purchase_correction_preview(candidate);
 assert not(plan->>'canApply')::boolean;
 begin
  perform public.solar_invoice_save(gen_random_uuid(),candidate);
  raise exception 'Staff changed a posted cash receipt to credit';
 exception when sqlstate 'P0001' then if sqlerrm not like '%طريقة دفع%' then raise;end if;
           when insufficient_privilege then null;
 end;
 perform public.solar_receipt_delete_requests('delete_direct',gen_random_uuid(),jsonb_build_object('invoiceId',cash_id,'expectedToken',context->>'token'));

 result:=public.solar_invoice_save(gen_random_uuid(),body); i:=(result->>'id')::bigint;
 correction:=body||jsonb_build_object('invoiceId',i,'expectedRevision',result->'pricingRevision','notes','تصحيح ملاحظة');
 plan:=public.solar_purchase_correction_preview(correction); assert(plan->>'canApply')::boolean,plan::text;
 result:=public.solar_invoice_save(gen_random_uuid(),correction);
 assert pg_temp.purchase_effect(i)#>>'{0,notes}'='تصحيح ملاحظة';
 correction:=correction||jsonb_build_object('expectedRevision',result->'pricingRevision');
 snapshot:=pg_temp.purchase_effect(i);
 assert (snapshot#>>'{0,total}')::numeric=2000;
 assert (snapshot#>>'{0,account_amount}')::numeric=2000;
 assert jsonb_array_length(snapshot->1)=1;
 -- Change value or reassign the same debt to another supplier.
 foreach candidate in array array[
  jsonb_set(correction,'{items,0,price}','1200'),
  correction||jsonb_build_object('partyId',-413312,'party','مورد ثان لاختبار الدين')
 ] loop
  plan:=public.solar_purchase_correction_preview(candidate);
  assert not(plan->>'canApply')::boolean and plan->>'blockedReason' is not null,plan::text;
  begin perform public.solar_invoice_save(gen_random_uuid(),candidate||jsonb_build_object('purchaseCorrectionToken',plan->'token'));
   raise exception 'Staff changed supplier debt';
  exception when insufficient_privilege then null;end;
  assert pg_temp.purchase_effect(i)=snapshot;
 end loop;
 context:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',i));
 assert not(context->>'directEligible')::boolean and context->>'directBlockedReason' is not null;
 begin
  perform public.solar_receipt_delete_requests('delete_direct',gen_random_uuid(),jsonb_build_object('invoiceId',i,'expectedToken',context->>'token'));
  raise exception 'Staff deleted a posted supplier debt';
 exception when sqlstate 'PT409' or insufficient_privilege then null;end;
 assert pg_temp.purchase_effect(i)=snapshot;

 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413310',true);
 candidate:=jsonb_set(correction,'{items,0,price}','1200');
 plan:=public.solar_purchase_correction_preview(candidate); assert(plan->>'canApply')::boolean,plan::text;
 result:=public.solar_invoice_save(gen_random_uuid(),candidate||jsonb_build_object('purchaseCorrectionToken',plan->'token'));
 assert (pg_temp.purchase_effect(i)#>>'{0,account_amount}')::numeric=2400;
 context:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',i));
 assert(context->>'directEligible')::boolean;
 perform public.solar_receipt_delete_requests('delete_direct',gen_random_uuid(),jsonb_build_object('invoiceId',i,'expectedToken',context->>'token'));
 assert pg_temp.purchase_effect(i)->0='null'::jsonb;

 -- A staff deletion request is advisory until an actual administrator approves.
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413311',true);
 result:=public.solar_invoice_save(gen_random_uuid(),body); i:=(result->>'id')::bigint;
 snapshot:=pg_temp.purchase_effect(i);
 context:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',i));
 assert(context->>'canRequest')::boolean;
 result:=public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',i,'expectedToken',context->>'token'));
 assert result->>'status'='pending' and pg_temp.purchase_effect(i)=snapshot;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413310',true);
 context:=public.solar_receipt_delete_requests('get',(result->>'id')::uuid);
 result:=public.solar_receipt_delete_requests('approve',(result->>'id')::uuid,jsonb_build_object('expectedToken',context->>'reviewToken'));
 assert result->>'status'='approved' and pg_temp.purchase_effect(i)->0='null'::jsonb;

 -- Changing only the IQD carrying value still requires admin when USD cents round to the same amount.
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413311',true);
 body:=jsonb_set(body,'{items,0,price}','6000')||jsonb_build_object('partyId',-413313,'party','مورد اختبار الدين بالدولار');
 result:=public.solar_invoice_save(gen_random_uuid(),body); i:=(result->>'id')::bigint;
 snapshot:=pg_temp.purchase_effect(i);
 assert (snapshot#>>'{0,account_amount}')::numeric=8 and (snapshot#>>'{0,total}')::numeric=12000;
 candidate:=body||jsonb_build_object('invoiceId',i,'expectedRevision',result->'pricingRevision','expenses',1);
 plan:=public.solar_purchase_correction_preview(candidate);
 assert (plan#>>'{after,accountAmount}')::numeric=8 and (plan#>>'{after,total}')::numeric=12001;
 assert not(plan->>'canApply')::boolean;
 begin perform public.solar_invoice_save(gen_random_uuid(),candidate||jsonb_build_object('purchaseCorrectionToken',plan->'token'));
  raise exception 'Staff changed supplier book value without changing rounded USD balance';
 exception when insufficient_privilege then null;end;
 assert pg_temp.purchase_effect(i)=snapshot;
end
$$;
rollback;
