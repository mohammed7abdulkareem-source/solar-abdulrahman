-- The personal material basis applies to the profit beneficiary's ledger.
-- Inventory valuation and the company's consolidated report use posted costs.
create function solar_private.receipt_profit_on_basis(t public.transactions, personal boolean)
returns numeric language plpgsql stable security invoker set search_path='' as $$
declare booked_profit numeric;booked_cost numeric;
begin
 if t.kind='system' or t.fx_pricing then
  booked_profit:=t.profit;
 else
  select coalesce(sum(i.qty*i.cost),0) into booked_cost from public.transaction_items i where i.transaction_id=t.id;
  booked_profit:=coalesce(t.subtotal,t.total)-booked_cost;
 end if;
 if personal and solar_private.personal_receipt_priced(t.id) then
  booked_cost:=coalesce(booked_cost,t.cost,0);
  booked_profit:=booked_profit+booked_cost-solar_private.personal_material_cost(t.id,booked_cost);
 end if;
 return booked_profit;
end $$;
revoke all on function solar_private.receipt_profit_on_basis(public.transactions,boolean) from public,anon,authenticated;

create function solar_private.receipt_has_hidden_cost(receipt_id bigint, viewer uuid)
returns boolean language sql stable security invoker set search_path='' as $$
 select case when not solar_private.personal_price_enabled(viewer) then false
  when not solar_private.personal_receipt_priced(receipt_id) then true
  else exists(select 1 from public.transaction_items i where i.transaction_id=receipt_id
    and not solar_private.personal_line_has_price(receipt_id,i.product_id)) end
$$;
revoke all on function solar_private.receipt_has_hidden_cost(bigint,uuid) from public,anon,authenticated;

-- Share the existing checkpoints, deductions, distributions and manual balance
-- adjustments between the two views. Only the receipt-specific profit differs.
do $migration$
declare src text; prior text;
begin
 src:=pg_get_functiondef('solar_private.profit_rows(uuid)'::regprocedure);
 if md5(src)<>'5a6563dd2ce76681158203a88ed953d5' then raise exception 'Unexpected profit ledger revision';end if;
 src:=replace(src,'FUNCTION solar_private.profit_rows(uid uuid)','FUNCTION solar_private.profit_rows_on_basis(uid uuid, personal boolean)');
 prior:=$old$when t.kind='system' then t.profit when t.kind='sale' then case when t.fx_pricing then t.profit else coalesce(t.subtotal,t.total)-coalesce((select sum(i.qty*i.cost) from public.transaction_items i where i.transaction_id=t.id),0) end$old$;
 if strpos(src,prior)=0 then raise exception 'Missing posted profit source';end if;
 execute replace(src,prior,$new$when t.kind in('sale','system') then solar_private.receipt_profit_on_basis(t,personal)$new$);

 src:=pg_get_functiondef('solar_private.retained_profit(uuid)'::regprocedure);
 if md5(src)<>'ca298aeac9884445146cb854b06d1c48' then raise exception 'Unexpected retained profit revision';end if;
 src:=replace(src,'FUNCTION solar_private.retained_profit(uid uuid)','FUNCTION solar_private.retained_profit_on_basis(uid uuid, personal boolean)');
 prior:=$old$case when t.kind='system' then t.profit when t.fx_pricing then t.profit else coalesce(t.subtotal,t.total)-coalesce((select sum(i.qty*i.cost) from public.transaction_items i where i.transaction_id=t.id),0) end$old$;
 if strpos(src,prior)=0 then raise exception 'Missing retained profit source';end if;
 execute replace(src,prior,'solar_private.receipt_profit_on_basis(t,personal)');

 src:=pg_get_functiondef('solar_private.profit_balance(jsonb)'::regprocedure);
 if md5(src)<>'3ecd00989149deee6560977521231dca' then raise exception 'Unexpected profit balance revision';end if;
 src:=replace(src,'solar_private.profit_rows(o.id)','solar_private.profit_rows_on_basis(o.id,not all_owners)');
 src:=replace(src,'solar_private.retained_profit(id)','solar_private.retained_profit_on_basis(id,not all_owners)');
 -- Finance snapshots stay byte-compatible. Only the administrator's display model
 -- needs the scoped material figure when comparing individual and company results.
 prior:=$old$select o.id owner_id,x.value row_data from owners o$old$;
 src:=replace(src,prior,$new$select o.id owner_id,x.value||case when actor.is_admin and not all_owners
   and x.value->>'kind' in('sale','system') and x.value->>'key' ~ '^tx:-?[0-9]+$' and not (x.value->>'deleted')::boolean
   then (select case when solar_private.personal_receipt_priced(t.id) then jsonb_build_object(
      'personalMaterialCost',solar_private.personal_material_cost(t.id,t.cost),
      'companyReceiptProfit',round(solar_private.receipt_profit_on_basis(t,false),2)) else '{}'::jsonb end
      from public.transactions t where t.id=substr(x.value->>'key',4)::bigint)
   else '{}'::jsonb end row_data from owners o$new$);
 src:=replace(src,' ) into result;', $new$ )||case when actor.is_admin and not all_owners then
   (select jsonb_build_object('comparison',jsonb_build_object(
    'companyEarned',coalesce(sum(coalesce(row_data->>'companyReceiptProfit',row_data->>'value')::numeric),0),
    'personalEarned',coalesce(sum((row_data->>'value')::numeric),0)))
    from period_rows where row_data->>'kind'<>'external_adjustment')
   else '{}'::jsonb end into result;$new$);
 execute src;
end $migration$;
revoke all on function solar_private.profit_rows_on_basis(uuid,boolean),solar_private.retained_profit_on_basis(uuid,boolean) from public,anon,authenticated;
create or replace function solar_private.profit_rows(uid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select solar_private.profit_rows_on_basis(uid,true)
$$;
create or replace function solar_private.retained_profit(uid uuid) returns numeric language sql stable security definer set search_path='' as $$
 select solar_private.retained_profit_on_basis(uid,true)
$$;

-- An existing receipt keeps its historical accounting basis when the setting
-- changes. A restricted viewer receives no fallback or historical purchase price.
do $migration$
declare src text;
begin
 src:=pg_get_functiondef('solar_private.profit_detail(text,uuid)'::regprocedure);
 if md5(src)<>'ce5a434280f771532f8ffdbb20fcb52d' then raise exception 'Unexpected profit detail revision';end if;
 src:=replace(src,'FUNCTION solar_private.profit_detail(source_key text, owner_id uuid DEFAULT NULL::uuid)',
  'FUNCTION solar_private.profit_detail_on_basis(source_key text, owner_id uuid, personal boolean)');
 src:=replace(src,'materials_cost numeric;sales numeric;', 'materials_cost numeric;sales numeric;hide_actual boolean;hide_total boolean;');
 src:=replace(src,' uid:=coalesce(owner_id,p.id);',$new$
 if not personal and not p.is_admin then raise exception 'أرباح الشركة متاحة للأدمن فقط' using errcode='42501';end if;
 hide_actual:=not p.is_admin and solar_private.personal_price_enabled(p.id);
 uid:=coalesce(owner_id,p.id);$new$);
 src:=replace(src,'solar_private.profit_rows(uid)','solar_private.profit_rows_on_basis(uid,personal)');
 src:=replace(src,$old$'unitCost',i.cost,'lineCost',i.qty*i.cost$old$,$new$'unitCost',shown.unit_cost,'lineCost',i.qty*shown.unit_cost$new$);
 src:=replace(src,'i.qty*(i.price-i.cost)','i.qty*(i.price-shown.unit_cost)');
 src:=replace(src,'m.id=i.product_id where i.transaction_id=t.id;', $new$m.id=i.product_id
    cross join lateral (select case when hide_actual and not solar_private.personal_line_has_price(t.id,i.product_id) then null
      when personal then solar_private.personal_line_cost(t.id,i.product_id,i.cost) else i.cost end unit_cost) shown
    where i.transaction_id=t.id;$new$);
 src:=replace(src,'    sales:=case when', $new$    if personal then materials_cost:=solar_private.personal_material_cost(t.id,materials_cost);end if;
    hide_total:=hide_actual and solar_private.receipt_has_hidden_cost(t.id,p.id);
    sales:=case when$new$);
 src:=replace(src,$old$'materialsCost',materials_cost,$old$,$new$'materialsCost',case when not hide_total then materials_cost end,
     'personalBasis',personal and solar_private.personal_receipt_priced(t.id),'costHidden',hide_total,$new$);
 src:=replace(src,$old$'grossProfit',sales-materials_cost,$old$,$new$'grossProfit',case when not hide_total then sales-materials_cost end,$new$);
 src:=replace(src,$old$'profitAdjustment',(movement->>'value')::numeric-(sales-materials_cost)$old$,$new$'profitAdjustment',case when not hide_total then (movement->>'value')::numeric-(sales-materials_cost)$new$);
 src:=replace(src,$old$coalesce(t.expenses,0) end,'items',lines);$old$,$new$coalesce(t.expenses,0) end end,'items',lines);$new$);
 src:=replace(src,$old$   invoice:=solar_private.receipt_contact_json$old$,$new$   if t.kind in('sale','system') and not p.is_admin and (hide_actual or solar_private.personal_receipt_priced(t.id)) then
    return jsonb_build_object('movement',solar_private.profit_read_projection(movement),'invoice',null,'breakdown',breakdown);
   end if;
   invoice:=solar_private.receipt_contact_json$new$);
 execute src;

 -- Compute forecasts on the same basis as final approval. Cash receipts/expenses and
 -- the author attribution remain tied to their own records.
 src:=pg_get_functiondef('solar_private.pending_systems_v385(uuid,date,date)'::regprocedure);
 if md5(src)<>'a289e421cad0034440bbc0f3e89ae4fb' then raise exception 'Unexpected open system source';end if;
 src:=replace(src,'t.total,t.cost,coalesce(t.expenses,0) invoice_expenses',$new$t.total,b.material_cost cost,
   b.hide_total, b.personal_basis,coalesce(t.expenses,0) invoice_expenses$new$);
 src:=replace(src,'round(t.total-t.cost-coalesce(t.expenses','round(t.total-b.material_cost-coalesce(t.expenses');
 src:=replace(src,'  from eligible t'||chr(10)||' ), unallocated', $new$  from eligible t cross join lateral (
   select case when p.is_admin and owner_id is null then t.cost else solar_private.personal_material_cost(t.id,t.cost) end material_cost,
    (not p.is_admin and solar_private.receipt_has_hidden_cost(t.id,p.id)) hide_total,
    (not(p.is_admin and owner_id is null) and solar_private.personal_receipt_priced(t.id)) personal_basis
  ) b
 ), unallocated$new$);
 src:=replace(src,$old$'materialCost',cost,'invoiceExpenses'$old$,$new$'materialCost',case when not hide_total then cost end,'personalBasis',personal_basis,'costHidden',hide_total,'invoiceExpenses'$new$);
 execute src;
 src:=pg_get_functiondef('solar_private.pending_systems(uuid,date,date)'::regprocedure);
 if md5(src)<>'e66659af88b800fac8397ddeead0a26e' then raise exception 'Unexpected delegated open system source';end if;
 src:=replace(src,'t.installation_status,t.total,t.cost,',$new$t.installation_status,t.total,solar_private.personal_material_cost(t.id,t.cost) cost,
    (not p.is_admin and solar_private.receipt_has_hidden_cost(t.id,p.id)) hide_total,solar_private.personal_receipt_priced(t.id) personal_basis,$new$);
 src:=replace(src,$old$'materialCost',cost,$old$,$new$'materialCost',case when not hide_total then cost end,'personalBasis',personal_basis,'costHidden',hide_total,$new$);
 execute src;
end $migration$;

revoke all on function solar_private.profit_detail_on_basis(text,uuid,boolean) from public,anon,authenticated;
create or replace function solar_private.profit_detail(source_key text,owner_id uuid default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select solar_private.profit_detail_on_basis(source_key,owner_id,true)
$$;
create function solar_private.company_profit_detail(source_key text,owner_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select solar_private.profit_detail_on_basis(source_key,owner_id,false)
$$;
create function public.solar_company_profit_detail(source_key text,owner_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select solar_private.company_profit_detail(source_key,owner_id)
$$;
revoke all on function solar_private.company_profit_detail(text,uuid),public.solar_company_profit_detail(text,uuid) from public,anon,authenticated;
grant execute on function solar_private.company_profit_detail(text,uuid),public.solar_company_profit_detail(text,uuid) to authenticated;
notify pgrst,'reload schema';
