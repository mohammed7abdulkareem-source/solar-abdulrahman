-- The receipt date remains the date of the original purchase. Its added line
-- enters the material report after stock already received or sold in between.
\set ON_ERROR_STOP on
load 'safeupdate';
begin;
insert into public.profiles(id, display_name, is_admin, user_type, active, permissions)
values ('00000000-0000-0000-0000-000000411093','فحص تاريخ الإضافة',true,'admin_staff',true,'{}');
insert into public.suppliers(id,name,account_currency)
values (-411093,'مورد فحص تاريخ الإضافة','IQD');
insert into public.customers(id,name,customer_type,owner_id)
values (-411093,'زبون فحص تاريخ الإضافة','wholesale','00000000-0000-0000-0000-000000411093');
insert into public.products(id,code,name,qty,cost)
values (-411093,'ADDED-LINE-ORIGINAL','الصنف الأصلي',0,0),
       (-411094,'ADDED-LINE-NEW','الصنف المضاف',0,0);
update solar_private.wholesale_pricing_control set enabled=false where id;
update solar_private.operation_controls set sale_paused=false,purchase_paused=false where id;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411093',true);

create function pg_temp.movement_line(material bigint, quantity numeric, price numeric) returns jsonb
language sql as $$
  select jsonb_build_object('id',material,'qty',quantity,'price',price)
$$;

create function pg_temp.movement_purchase_body(lines jsonb) returns jsonb
language sql as $$
  select jsonb_build_object(
    'kind','purchase','mode','credit','partyId',-411093,'party','مورد فحص تاريخ الإضافة',
    'warehouseId',solar_private.primary_warehouse(),'sourceCurrency','IQD','exchangeRate',1,
    'marketRate',1000,'accountRevision',0,'cashCurrency','IQD','items',lines)
$$;

create function pg_temp.movement_document(payload jsonb, effective_at timestamptz) returns bigint
language plpgsql as $$
declare
  nonce uuid := gen_random_uuid();
  header public.transactions;
  response jsonb;
  previous_context text := coalesce(current_setting('solar.fx_context',true),'');
begin
  response := public.solar_invoice_save(nonce,payload);
  select * into strict header from public.transactions where id=(response->>'id')::bigint;
  if header.kind='purchase' then
    perform set_config('solar.fx_context',jsonb_build_object('accountRevision',header.account_revision,
      'marketRate',header.market_rate,'cashCurrency',header.cash_currency)::text,true);
  end if;
  update public.transactions set created_at=effective_at where id=header.id;
  perform set_config('solar.fx_context',previous_context,true);
  update solar_private.invoice_requests set created_at=effective_at where request_id=nonce;
  return header.id;
end $$;

do $test$
declare
  warehouse bigint := solar_private.primary_warehouse();
  receipt_at timestamptz := now()-interval '3 days';
  report_options jsonb := jsonb_build_object('productId',-411094,'warehouseId',warehouse);
  original_line jsonb := pg_temp.movement_line(-411093,2,50);
  added_line jsonb := pg_temp.movement_line(-411094,2,200);
  receipt bigint;
  other_purchase bigint;
  sale bigint;
  report jsonb;
  body jsonb;
  plan jsonb;
  old_lines jsonb;
  corrected jsonb;
  inclusion_time timestamptz;
begin
  receipt := pg_temp.movement_document(pg_temp.movement_purchase_body(jsonb_build_array(original_line)),receipt_at);
  other_purchase := pg_temp.movement_document(
    pg_temp.movement_purchase_body(jsonb_build_array(pg_temp.movement_line(-411094,5,100))),now()-interval '2 days');
  -- Same timestamp as the correction, just as for two operations in one
  -- transaction. Its invoice ID is later than the original receipt's ID.
  sale := pg_temp.movement_document(jsonb_build_object('kind','sale','mode','credit',
    'partyId',-411093,'party','زبون فحص تاريخ الإضافة','warehouseId',warehouse,
    'items',jsonb_build_array(pg_temp.movement_line(-411094,1,300))),now());
  report := public.solar_inventory('material_report',null,report_options);
  old_lines := report->'rows';
  assert jsonb_array_length(old_lines)=2 and (old_lines->1->>'balance')::numeric=4;

  body := pg_temp.movement_purchase_body(jsonb_build_array(original_line,added_line))
    ||jsonb_build_object('invoiceId',receipt,'expectedRevision',(
      select pricing_revision from public.transactions where id=receipt));
  plan := public.solar_purchase_correction_preview(body);
  assert (plan->>'canApply')::boolean,coalesce(plan->>'blockedReason','Preview unavailable');
  perform public.solar_invoice_save(gen_random_uuid(),body||jsonb_build_object('purchaseCorrectionToken',plan->>'token'));

  report := public.solar_inventory('material_report',null,report_options);
  corrected := report->'rows';
  select (snapshot->>'addedAt')::timestamptz into strict inclusion_time
  from public.transactions t cross join lateral jsonb_array_elements(t.purchase_stock) snapshot
  where t.id=receipt and (snapshot->>'id')::bigint=-411094;
  assert inclusion_time>receipt_at and jsonb_array_length(corrected)=3;
  assert corrected->0=old_lines->0 and corrected->1=old_lines->1,
    'The new receipt line changed an earlier movement or running balance';
  assert (corrected->2->>'invoiceId')::bigint=receipt
     and (corrected->2->>'date')::timestamptz=inclusion_time
     and (corrected->2->>'inQty')::numeric=2 and (corrected->2->>'balance')::numeric=6
     and (report->>'currentQty')::numeric=6,'Added line date, order, or balance is wrong';
  report := public.solar_inventory('material_report',null,
    report_options || jsonb_build_object('to',(inclusion_time at time zone 'Asia/Baghdad')::date-1));
  assert jsonb_array_length(report->'rows')=1 and (report->'rows'->0->>'invoiceId')::bigint=other_purchase,
    'A later addition is included in the closed date range';
  report := public.solar_inventory('material_report',null,
    jsonb_build_object('productId',-411093,'warehouseId',warehouse));
  assert (report->'rows'->0->>'date')::timestamptz=receipt_at
    and (report->'rows'->0->>'balance')::numeric=2,'The original line was moved to the correction date';
end $test$;
rollback;
\echo 'Added material ledger date and running balance PASS'
