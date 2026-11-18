-- Keep V4.1.9 historical replay and its proofs for existing purchase lines.
-- Apply these changes only if its definition matches the installed version.
DO $patch_history$
DECLARE
 definition text := pg_get_functiondef('solar_private.purchase_material_history(public.transactions,bigint)'::regprocedure);
BEGIN
 if md5(definition) <> '9afa102ecc640b4bd4e1ca690cb7cdaf' then
  raise exception 'Review the installed purchase history before changing it';
 end if;
 definition:=replace(definition, $before$begin
 select value into snap$before$, $after$-- A purchase can receive a new line after the invoice was issued. A single
-- invoice therefore has a separate effective inventory date for each line.
 addition jsonb;
 target_order numeric;
 target_revision bigint;
 event_order numeric;
 event_revision bigint;
begin
 select value into snap$after$);
 definition:=replace(definition, $before$ anchor:=coalesce(anchor,target.created_at);$before$, $after$ anchor:=coalesce((snap->>'addedAt')::timestamptz,anchor,target.created_at);
 target_order:=coalesce((snap->>'addedAfterInvoiceId')::numeric + 0.5,target.id);
 target_revision:=case when snap ? 'addedByCorrection' then coalesce((snap->>'revision')::bigint,0) else 0 end;$after$);
 definition:=replace(definition, $before$  if doc.id=target.id then first_at:=anchor;end if;$before$, $after$  addition:=null;
  if doc.header->>'kind'='purchase' then
   select value into addition from jsonb_array_elements(doc.header->'purchase_stock')
   where (value->>'id')::bigint=material_id and value ? 'addedByCorrection';
  end if;
  if doc.id=target.id then first_at:=anchor;
  elsif addition is not null then first_at:=(addition->>'addedAt')::timestamptz;
  end if;
  event_order:=coalesce((addition->>'addedAfterInvoiceId')::numeric + 0.5,doc.id);
  event_revision:=coalesce((addition->>'revision')::bigint,0);$after$);
 definition:=replace(definition, $before$  if first_at<anchor or(first_at=anchor and doc.id<target.id) then$before$, $after$  if doc.id<>target.id and doc.header->>'kind'='purchase' then
   -- Removing a corrected line reverses its full effective contribution. A
   -- re-add gets a fresh marker, so neither the removed run nor the receipt's
   -- original issue date may add phantom stock to an earlier purchase replay.
   if (line is null and (
     exists(select 1 from solar_private.purchase_corrections c where c.invoice_id=doc.id)
     or (doc.deleted_at is null and jsonb_typeof(first_payload->'items')='array' and first_line is null)
   ))
    or (doc.deleted_at is not null and exists(select 1 from solar_private.purchase_corrections c where c.invoice_id=doc.id and c.plan->>'action'='delete')) then continue;end if;
  end if;
  if (first_at,event_order,event_revision,doc.id)<(anchor,target_order,target_revision,target.id) then
   -- This added purchase is already included in the target's opening stock.
   -- Its current corrected line replaces its original contribution in full.
   if addition is not null then continue;end if;$after$);
 definition:=replace(definition, $before$  from solar_private.invoice_requests r where(r.result->>'id')::bigint=doc.id and r.created_at<anchor$before$, $after$  from solar_private.invoice_requests r where(r.result->>'id')::bigint=doc.id
     and (r.created_at<anchor or (r.created_at=anchor and snap ? 'addedByCorrection'
          and r.payload->>'invoiceId' is null and doc.id<target_order))$after$);
 definition:=replace(definition, $before$   events:=events||jsonb_build_array(first_event);$before$, $after$   if addition is not null then
    first_event:=first_event||jsonb_build_object('documentOrder',event_order,'stockRevision',event_revision);
   end if;
   events:=events||jsonb_build_array(first_event);$after$);
 definition:=replace(definition, $before$(e->>'at')::timestamptz,(e->>'invoiceId')::bigint,(e->>'sequence')::integer,coalesce((e->>'orderKey')::bigint,0)$before$, $after$(e->>'at')::timestamptz,coalesce((e->>'documentOrder')::numeric,(e->>'invoiceId')::numeric),
  coalesce((e->>'stockRevision')::bigint,0),(e->>'invoiceId')::bigint,(e->>'sequence')::integer,coalesce((e->>'orderKey')::bigint,0)$after$);
 definition:=replace(definition, $before$if doc.id<>target.id and exists(select 1 from solar_private.purchase_corrections c where c.invoice_id=doc.id) then$before$, $after$if doc.id<>target.id and (addition is not null or exists(select 1 from solar_private.purchase_corrections c where c.invoice_id=doc.id)) then$after$);
 definition:=replace(definition, $before$if doc.id<>target.id and not exists(select 1 from solar_private.purchase_corrections c where c.invoice_id=doc.id) then$before$, $after$if doc.id<>target.id and addition is null and not exists(select 1 from solar_private.purchase_corrections c where c.invoice_id=doc.id) then$after$);
 EXECUTE definition;
END $patch_history$;

-- Unconsumed purchases can still use the ordinary invoice editor, including
-- edits to payment or supplier terms. Keep the same material receipt date in
-- that path and carry it forward when an existing snapshot is reconstructed.
do $pristine$
declare
 definition text := pg_get_functiondef('solar_private.invoice_save_v333(uuid,jsonb)'::regprocedure);
 snapshot_start text := 'snapshots:=snapshots||jsonb_build_array(jsonb_build_object(''id'',product.id,''qty'',product_qty';
begin
 if md5(definition) <> '2a174054253e2b6845f27d13c5e0de48' or strpos(definition,snapshot_start)=0 then
  raise exception 'Review the ordinary invoice snapshot builder before changing it';
 end if;
 definition := replace(definition,snapshot_start,$new$snapshots:=snapshots||jsonb_build_array(
      (case when existing and previous_qty=0 then jsonb_build_object(
         'addedByCorrection',request_id,'addedAt',now(),'revision',product.costing_revision,
         'addedAfterInvoiceId',(select max(x.id) from public.transactions x)
       ) when before_stock ? 'addedByCorrection' then jsonb_build_object(
         'addedByCorrection',before_stock->'addedByCorrection','addedAt',before_stock->'addedAt',
         'revision',before_stock->'revision','addedAfterInvoiceId',before_stock->'addedAfterInvoiceId'
       ) else '{}'::jsonb end)
      || jsonb_build_object('id',product.id,'qty',product_qty$new$);
 execute definition;
end $pristine$;

-- Extend the existing correction workflow. Capture a newly received line's
-- opening balance when it is attached to the purchase. Its historical unit
-- costs still come from the original receipt's currency and expense split.
do $migration$
declare
 definition text;
 blocked_addition text;
 history_lookup text;
 lock_point text;
 snapshot_point text;
 write_point text;
begin
 definition := pg_get_functiondef('solar_private.purchase_correction_plan(jsonb,boolean)'::regprocedure);
 if md5(definition) <> '39b1d3326b87d2e105dac56d83c0a7e3' then
  raise exception 'Review the installed purchase correction plan before changing it';
 end if;

 blocked_addition := $old$  if old_qty=0 then raise exception 'أضف المادة الجديدة بوصل شراء مستقل؛ هذا التصحيح يخص مواد الوصل الأصلية.' using errcode='PT409';end if;$old$;
 history_lookup := $old$  history:=solar_private.purchase_material_history(t,product.id);
  base:=solar_private.purchase_material_replay(history->'seed',history->'events',t.id,null);
  parts:=solar_private.inventory_currency_parts(product.id,product.cost_basis,product.cost);$old$;
 if strpos(definition,blocked_addition)=0 or strpos(definition,history_lookup)=0 then
  raise exception 'Cannot locate the existing purchase replay checks';
 end if;
 definition := replace(definition,blocked_addition,'');
 definition := replace(definition,history_lookup,$new$  parts := solar_private.inventory_currency_parts(product.id, product.cost_basis, product.cost);
  if old_qty = 0 then
   -- No units of this material were previously on this receipt. Blend just the
   -- new units into today's actual stock using the normal purchase replay.
   base := jsonb_build_object('qty', product.qty, 'cost', product.cost, 'parts', parts);
   history := jsonb_build_object(
    'seed', base,
    'events', jsonb_build_array(jsonb_build_object(
     'invoiceId', t.id, 'kind', 'purchase', 'action', 'save', 'qty', 0))
   );
  else
   history := solar_private.purchase_material_history(t, product.id);
   base := solar_private.purchase_material_replay(history->'seed', history->'events', t.id, null);
  end if;$new$);
 execute definition;

 definition := pg_get_functiondef('solar_private.purchase_save_v419(uuid,jsonb)'::regprocedure);
 if md5(definition) <> '5aca1e24c5de33b2366557da039bce84' then
  raise exception 'Review the installed purchase correction save before changing it';
 end if;
 lock_point := ' plan:=solar_private.purchase_correction_plan(payload);';
 snapshot_point := ' select round(coalesce(sum((i->>''qty'')::numeric*(i->>''landedCost'')::numeric),0),2) into total_cost';
 write_point := $old$ for line in select value from jsonb_array_elements(plan->'normalizedItems')loop
  update public.transaction_items set qty=$old$;
 if strpos(definition,lock_point)=0 or strpos(definition,snapshot_point)=0 or strpos(definition,write_point)=0 then
  raise exception 'Cannot locate the protected purchase save steps';
 end if;
 -- Stabilize the new product's opening stock before recomputing the preview.
 -- Ordinary receipt writers share the advisory lock. These row locks cover
 -- other authorized updates to the product record as well.
 definition := replace(definition,lock_point,$new$ if jsonb_typeof(payload->'items') = 'array' then
  perform 1 from public.products p
  where p.id in (
   select (v->>'id')::bigint from jsonb_array_elements(payload->'items') v
   union select i.product_id from public.transaction_items i where i.transaction_id=t.id
  )
  order by p.id for update;
 end if;
$new$ || lock_point);
 definition := replace(definition,snapshot_point,$new$ -- Keep a before-image for each newly included product. The marker survives
 -- later changes to this receipt and identifies its actual stock arrival.
 select next_snapshots || coalesce(jsonb_agg(jsonb_build_object(
   'id', (v->>'id')::bigint,
   'qty', (v->'before'->>'qty')::numeric,
   'cost', (v->'before'->>'cost')::numeric,
   'basis', (v->'before'->'basis') || jsonb_build_object('currencyComponents',
     solar_private.inventory_currency_parts((v->>'id')::bigint, v->'before'->'basis', (v->'before'->>'cost')::numeric)),
   'revision', (v->'before'->>'revision')::bigint,
   'afterRevision', -1,
   'addedByCorrection', request_id,
   'addedAt', now(),
   'addedAfterInvoiceId', (select max(x.id) from public.transactions x)
 ) order by (v->>'id')::bigint), '[]'::jsonb)
 into next_snapshots
 from jsonb_array_elements(plan->'items') v
 where not exists (
  select 1 from jsonb_array_elements(original_items) i
  where (i->>'product_id')::bigint = (v->>'id')::bigint
 );
$new$ || snapshot_point);
 definition := replace(definition,write_point,$new$ for line in select value from jsonb_array_elements(plan->'normalizedItems')loop
  if not exists (
   select 1 from jsonb_array_elements(original_items) i
   where (i->>'product_id')::bigint = (line->>'id')::bigint
  ) then
   -- The ordinary insert trigger posts the quantity to the receipt warehouse.
   insert into public.transaction_items(
    transaction_id, product_id, product_name, brand_name, category, qty,
    price, source_price, cost, landed_cost, cost_basis
   ) values (
    t.id, (line->>'id')::bigint, line->>'name', line->>'brand', line->>'category',
    (line->>'qty')::numeric, (line->>'price')::numeric, (line->>'sourcePrice')::numeric,
    (line->>'landedCost')::numeric, (line->>'landedCost')::numeric,
    jsonb_build_object('currency', t.source_currency, 'rate', t.exchange_rate,
                       'sourcePrice', (line->>'sourcePrice')::numeric, 'invoiceId', t.id)
   );
   continue;
  end if;
  update public.transaction_items set qty=$new$);
 execute definition;
end
$migration$;

-- A purchase keeps its receipt date. A line received in a later correction
-- enters the material ledger when the stock was actually received.
do $patch_movement$
declare
  definition text := pg_get_functiondef(
    'solar_private.inventory_movements(bigint,bigint,text,date,date)'::regprocedure
  );
begin
  if md5(definition) <> 'bf496f6efa195d3465ce26d630dd5f1f' then
    raise exception 'Review inventory movement changes before applying purchase line dates';
  end if;

  definition := replace(definition,
    'i.category,t.id invoice_id,t.receipt_no,t.kind,t.party_name,t.created_at,t.created_by movement_owner,',
    $line$i.category,
   coalesce((inclusion.snapshot->>'addedAfterInvoiceId')::numeric + 0.5, t.id::numeric) movement_order,
   t.receipt_no,t.kind,t.party_name,
   coalesce((inclusion.snapshot->>'addedAt')::timestamptz, t.created_at) created_at,
   t.created_by movement_owner,$line$);
  definition := replace(definition,
    'join public.transactions t on t.id=i.transaction_id where t.kind',
    $join$join public.transactions t on t.id=i.transaction_id
  left join lateral (
    select snapshot
    from jsonb_array_elements(t.purchase_stock) snapshot
    where t.kind = 'purchase'
      and snapshot ? 'addedByCorrection'
      and (snapshot->>'id')::bigint = i.product_id
    limit 1
  ) inclusion on true
  where t.kind$join$);
  definition := replace(definition, 'm.created_at,m.invoice_id,m.id',
    $order$m.created_at,m.movement_order,
      case when mod(m.movement_order,1) <> 0 then split_part(m.id,':',2)::bigint end,m.id$order$);
  definition := replace(definition, 'order by created_at,invoice_id,id',
    $order$order by created_at,movement_order,
      case when mod(movement_order,1) <> 0 then split_part(id,':',2)::bigint end,id$order$);
  execute definition;
end $patch_movement$;

notify pgrst, 'reload schema';
