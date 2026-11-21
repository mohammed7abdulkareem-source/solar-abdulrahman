-- Raw REST reads cannot project columns differently by viewer. Preserve existing
-- permissive policies for ordinary users and serve selected users via scoped RPCs.
create policy personal_cost_product_read on public.products as restrictive for select to authenticated
 using (not (select solar_private.viewer_uses_personal_prices()));
create policy personal_cost_receipt_read on public.transactions as restrictive for select to authenticated
 using (kind not in ('sale','system','purchase') or not (select solar_private.viewer_uses_personal_prices()));
create policy personal_cost_line_read on public.transaction_items as restrictive for select to authenticated
 using (not (select solar_private.viewer_uses_personal_prices()));

-- Keep existing access checks, warehouse quantities and numeric valuation for
-- the company's ledger. Only the returned catalog/receipt document changes.
do $migration$
declare patch record; def text;
begin
 for patch in select * from (values
  ('solar_private.inventory_catalog(bigint)',
   $old$then '{}'::jsonb else jsonb_build_object('cost',solar_private.current_unit_cost$old$,
   $new$then '{}'::jsonb when (select solar_private.viewer_uses_personal_prices()) then
    jsonb_build_object('personalPriceBasis',true,'cost',solar_private.personal_product_price(m.id),
     'costing_revision',m.costing_revision,'companyQty',case when solar_private.can_read_global_stock() then m.qty end)
    else jsonb_build_object('cost',solar_private.current_unit_cost$new$),
  ('solar_private.inventory(text,uuid,jsonb)',
   $old$then jsonb_build_object('cost',solar_private.current_unit_cost(m.id,m.cost_basis,m.cost)) else '{}'::jsonb end$old$,
   $new$then case when (select solar_private.viewer_uses_personal_prices())
    then jsonb_build_object('cost',solar_private.personal_product_price(m.id),'personalPriceBasis',true)
    else jsonb_build_object('cost',solar_private.current_unit_cost(m.id,m.cost_basis,m.cost)) end else '{}'::jsonb end$new$),
  ('solar_private.wholesale_pricing_state_v410_notices()',
   $old$'cost',item->'cost','minPrice'$old$,
   $new$'cost',item->'cost','personalPriceBasis',coalesce(item->'personalPriceBasis','false'::jsonb),'minPrice'$new$),
  ('solar_private.quick_search(text,text)',
   $old$case when financial then solar_private.current_unit_cost(m.id,m.cost_basis,m.cost) end cost$old$,
   $new$case when financial then case when (select solar_private.viewer_uses_personal_prices())
     then solar_private.personal_product_price(m.id) else solar_private.current_unit_cost(m.id,m.cost_basis,m.cost) end end cost$new$),
  ('solar_private.quick_search(text,text)',
   $old$'cost',cost,'lastSale',last_sale$old$,
   $new$'cost',cost,'personalPriceBasis',(select solar_private.viewer_uses_personal_prices()),'lastSale',last_sale$new$),
  ('solar_private.quick_search(text,text)',
   $old$(t.kind='sale' or i.price>0)$old$,
   $new$(t.kind='sale' or (i.price>0 and not (select solar_private.viewer_uses_personal_prices())))$new$),
  ('solar_private.transfer_json(uuid)',
   $old$'items',case when p.user_type='warehouse' then$old$,
   $new$'items',case when p.user_type='warehouse' or solar_private.viewer_uses_personal_prices() then$new$),
  ('solar_private.material_movement_report(jsonb)',
   $old$when t.id is not null and solar_private.can_access_invoice$old$,
   $new$when t.id is not null and (t.kind<>'purchase' or not (select solar_private.viewer_uses_personal_prices())) and solar_private.can_access_invoice$new$),
  ('solar_private.material_movement_report(jsonb)',
   $old$when st.id is not null and(actor.is_admin or st.actor_id=actor.id)then$old$,
   $new$when st.id is not null and not (select solar_private.viewer_uses_personal_prices()) and(actor.is_admin or st.actor_id=actor.id)then$new$),
  ('solar_private.capital_snapshot(boolean)',
   $old$jsonb_build_object('cost',v->'bookCost')$old$,
   $new$jsonb_build_object('cost',case when v->'personalPriceBasis'='true'::jsonb then v->'cost' else v->'bookCost' end)$new$),
  ('solar_private.supplier_entry_read_projection(jsonb)',
   $old$if tid is null or solar_private.invoice_read_allowed(tid) then return row_data;end if;$old$,
   $new$if tid is null or (solar_private.invoice_read_allowed(tid) and not (
     solar_private.viewer_uses_personal_prices() and (jsonb_typeof(row_data->'archivedPurchase')='object'
       or exists(select 1 from public.transactions x where x.id=tid and x.kind='purchase')) is true))
    then return row_data;end if;$new$),
  ('public.solar_purchase_correction_preview(jsonb)',
   $old$plan:=solar_private.purchase_correction_plan(payload);$old$,
   $new$if solar_private.viewer_uses_personal_prices() then raise exception 'مراجعة كلفة الشراء تتطلب صلاحية الكلفة الفعلية' using errcode='42501';end if;
   plan:=solar_private.purchase_correction_plan(payload);$new$),
  ('solar_private.purchase_save_v419(uuid,jsonb)',
   $old$perform pg_advisory_xact_lock(7311,1);$old$,
   $new$if solar_private.viewer_uses_personal_prices() then raise exception 'تعديل كلفة الشراء يتطلب صلاحية الكلفة الفعلية' using errcode='42501';end if;
   perform pg_advisory_xact_lock(7311,1);$new$)
 ) as changes(target,before,after) loop
  def:=pg_get_functiondef(patch.target::regprocedure);
  if strpos(def,patch.before)=0 then raise exception 'Review personal cost projection for %',patch.target;end if;
  execute replace(def,patch.before,patch.after);
 end loop;
end
$migration$;
