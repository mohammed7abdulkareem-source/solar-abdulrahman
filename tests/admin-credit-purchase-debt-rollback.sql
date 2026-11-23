-- Disposable local DB. Exercise the actual purchase, preview and delete RPCs.
\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,display_name,is_admin,user_type,active,permissions,phone) values
 ('00000000-0000-0000-0000-000000413310','مدير اختبار المشتريات',true,'admin_staff',true,'{}','07700413310'),
 ('00000000-0000-0000-0000-000000413311','مستخدم اختبار المشتريات',false,'admin_staff',true,'{"purchase":true,"deletionRequests":true,"supplierStatement":true}','07700413311');
insert into public.suppliers(id,name,account_currency) values
 (-413311,'مورد أول لاختبار الدين','IQD'),(-413312,'مورد ثان لاختبار الدين','IQD'),
 (-413313,'ABDULRAHMAN','IQD');
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
  'marketRate',(public.solar_exchange_rate_get()->>'rate')::numeric,'accountRevision',0,'expenses',0,'items',jsonb_build_array(jsonb_build_object('id',-413311,'qty',2,'price',1000)));
 protected jsonb:=body||'{"partyId":-413313,"party":"ABDULRAHMAN"}'::jsonb;
 result jsonb; candidate jsonb; plan jsonb; context jsonb; snapshot jsonb;
 ordinary_id bigint; mode text;
begin
 foreach mode in array array['cash','credit'] loop
  begin
   perform public.solar_invoice_save(gen_random_uuid(),protected||jsonb_build_object('mode',mode));
   raise exception 'Staff could save % purchase against protected supplier',mode;
  exception when insufficient_privilege then null;end;
 end loop;
 -- All historical stock and accounting effects for ordinary purchases retain
 -- the prior staff correction and cancellation workflow.
 foreach mode in array array['cash','credit'] loop
  result:=public.solar_invoice_save(gen_random_uuid(),body||jsonb_build_object('mode',mode));
  ordinary_id:=(result->>'id')::bigint;
  candidate:=jsonb_set(body,'{items,0,price}','1200')||jsonb_build_object('mode',mode,'invoiceId',ordinary_id,'expectedRevision',result->'pricingRevision');
  plan:=public.solar_purchase_correction_preview(candidate);
  assert (plan->>'canApply')::boolean,plan::text;
  result:=public.solar_invoice_save(gen_random_uuid(),candidate||jsonb_build_object('purchaseCorrectionToken',plan->'token'));
  snapshot:=pg_temp.purchase_effect(ordinary_id);
  assert (snapshot#>>'{0,total}')::numeric=2400;
  if mode='credit' then assert (snapshot#>>'{0,account_amount}')::numeric=2400;end if;

  candidate:=candidate||jsonb_build_object('expectedRevision',result->'pricingRevision','partyId',-413313,'party','ABDULRAHMAN');
  begin
   plan:=public.solar_purchase_correction_preview(candidate);
   assert not(plan->>'canApply')::boolean,'Staff correction allows moving a purchase to protected supplier';
  exception when insufficient_privilege then null;end;
  begin
   perform public.solar_invoice_save(gen_random_uuid(),candidate||jsonb_build_object('purchaseCorrectionToken',plan->'token'));
   raise exception 'Staff reassigned a purchase to protected supplier';
  exception when insufficient_privilege then null;end;
  assert pg_temp.purchase_effect(ordinary_id)=snapshot;
  context:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',ordinary_id));
  assert (context->>'directEligible')::boolean;
  perform public.solar_receipt_delete_requests('delete_direct',gen_random_uuid(),jsonb_build_object('invoiceId',ordinary_id,'expectedToken',context->>'token'));
  assert pg_temp.purchase_effect(ordinary_id)->0='null'::jsonb;
 end loop;

 perform set_config('fixture.protected_payload',protected::text,true);
end
$$;
reset role;
-- A real historical purchase was created by the now-demoted employee.
update public.profiles set is_admin=true where id='00000000-0000-0000-0000-000000413311';
set local role authenticated;
do $$
declare result jsonb;
begin
 result:=public.solar_invoice_save(gen_random_uuid(),current_setting('fixture.protected_payload')::jsonb);
 perform set_config('fixture.protected_id',result->>'id',true);
 perform set_config('fixture.protected_revision',result->>'pricingRevision',true);
end $$;
reset role;
update public.profiles set is_admin=false where id='00000000-0000-0000-0000-000000413311';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413311',true);
do $$
declare
 i bigint:=current_setting('fixture.protected_id')::bigint;
 candidate jsonb:=jsonb_build_object('kind','purchase','mode','credit','partyId',-413311,'party','مورد أول لاختبار الدين',
  'warehouseId',current_setting('test.debt.warehouse')::bigint,'sourceCurrency','IQD','cashCurrency','IQD','exchangeRate',1,
  'marketRate',(public.solar_exchange_rate_get()->>'rate')::numeric,'accountRevision',0,'expenses',0,'invoiceId',i,'expectedRevision',current_setting('fixture.protected_revision')::bigint,
  'items',jsonb_build_array(jsonb_build_object('id',-413311,'qty',2,'price',1000)));
 snapshot jsonb:=pg_temp.purchase_effect(i);
 plan jsonb; context jsonb; result jsonb;
begin
 begin
  plan:=public.solar_purchase_correction_preview(candidate);
  assert not(plan->>'canApply')::boolean,'Staff preview allows removing the protected supplier';
 exception when insufficient_privilege then null;end;
 begin
  perform public.solar_invoice_save(gen_random_uuid(),candidate||jsonb_build_object('purchaseCorrectionToken',plan->'token'));
  raise exception 'Staff reassigned protected purchase to ordinary supplier';
 exception when insufficient_privilege then null;end;
 begin
  context:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',i));
  assert not coalesce((context->>'directEligible')::boolean,false) and not coalesce((context->>'canRequest')::boolean,false);
 exception when insufficient_privilege then null;end;
 assert pg_temp.purchase_effect(i)=snapshot;

 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413310',true);
 candidate:=jsonb_set(candidate||'{"partyId":-413313,"party":"ABDULRAHMAN"}'::jsonb,'{items,0,price}','1100');
 plan:=public.solar_purchase_correction_preview(candidate);
 assert (plan->>'canApply')::boolean,plan::text;
 result:=public.solar_invoice_save(gen_random_uuid(),candidate||jsonb_build_object('purchaseCorrectionToken',plan->'token'));
 assert (pg_temp.purchase_effect(i)#>>'{0,account_amount}')::numeric=2200;
 context:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',i));
 assert (context->>'directEligible')::boolean;
 perform public.solar_receipt_delete_requests('delete_direct',gen_random_uuid(),jsonb_build_object('invoiceId',i,'expectedToken',context->>'token'));
 assert pg_temp.purchase_effect(i)->0='null'::jsonb;
end
$$;
rollback;
