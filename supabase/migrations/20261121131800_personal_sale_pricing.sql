-- Project the frozen user basis only at the authenticated operational boundary.
-- The stock, cash, VAT, and company profit journals retain the posted amounts.
create function solar_private.sale_financial_projection(t public.transactions,viewer uuid)
returns jsonb language sql stable set search_path='' as $$
 select case when solar_private.personal_price_enabled(viewer) or
   (solar_private.personal_receipt_priced(t.id) and not exists(select from public.profiles p where p.id=viewer and p.is_admin)) then
   jsonb_build_object('personalPriceBasis',true,'cost',case when not solar_private.receipt_has_hidden_cost(t.id,viewer)
     then solar_private.personal_material_cost(t.id,t.cost) end,
     'profit',solar_private.receipt_profit_on_basis(t,true))
 else jsonb_build_object('cost',t.cost,'profit',t.profit) end
$$;
revoke all on function solar_private.sale_financial_projection(public.transactions,uuid) from public,anon,authenticated;

do $patch$
declare definition text;before_text text;after_text text;
begin
 definition:=pg_get_functiondef('solar_private.assert_system_pricing(bigint)'::regprocedure);
 before_text:='round(coalesce(sum(i.qty*i.cost),0),2)';
 if strpos(definition,before_text)=0 or strpos(definition,'if invoice.total<minimum_price then')=0 then raise exception 'Unknown system pricing formula';end if;
 definition:=replace(definition,before_text,'round(solar_private.personal_material_cost(invoice.id,coalesce(sum(i.qty*i.cost),0)),2)');
 definition:=replace(definition,'if invoice.total<minimum_price then',$new$if invoice.total<minimum_price and solar_private.receipt_has_hidden_cost(invoice.id,auth.uid()) then
   raise exception 'سعر بيع المنظومة أقل من الحد المسموح بعد احتساب المصاريف' using errcode='PT422';end if;
 if invoice.total<minimum_price then$new$);
 execute definition;

 definition:=pg_get_functiondef('solar_private.invoice_save(uuid,jsonb)'::regprocedure);
 before_text:='return invoice_result;';
 after_text:=$new$
 if payload->>'kind'='purchase' and solar_private.personal_price_enabled(auth.uid()) then
  return jsonb_build_object('id',invoice_result->'id','receiptNo',invoice_result->'receiptNo','total',invoice_result->'total',
    'pricingRevision',invoice_result->'pricingRevision','warehouseId',invoice_result->'warehouseId','warehouseName',invoice_result->'warehouseName');
 end if;
 if payload->>'kind' in ('sale','system') then
  select * into after_row from public.transactions where id=(invoice_result->>'id')::bigint;
  if found then
   if solar_private.personal_price_enabled(auth.uid()) or solar_private.personal_receipt_priced(after_row.id) then
    return invoice_result || solar_private.sale_financial_projection(after_row,auth.uid());
   end if;
  elsif solar_private.personal_price_enabled(auth.uid()) then
   return invoice_result - 'cost' - 'profit';
  end if;
 end if;
 return invoice_result;$new$;
 if strpos(definition,before_text)=0 then raise exception 'Unknown invoice response';end if;
 execute replace(definition,before_text,after_text);

 definition:=pg_get_functiondef('solar_private.installation_jobs()'::regprocedure);
 before_text:='jsonb_build_object(''cost'',t.cost,''expenses'',t.expenses';
 if strpos(definition,before_text)=0 then raise exception 'Unknown installation financial projection';end if;
 execute replace(definition,before_text,
   'solar_private.sale_financial_projection(t,p.id) || jsonb_build_object(''expenses'',t.expenses');
end $patch$;

-- Personal quotes are prepared on the server, including for full-access users.
-- A direct read of a pre-existing full quote could reveal captured book costs.
create policy personal_quote_server_access on public.solar_quotes as restrictive for all to authenticated
 using(not (select solar_private.viewer_uses_personal_prices()))
 with check(not (select solar_private.viewer_uses_personal_prices()));
alter table public.solar_price_estimates enable row level security;
create policy personal_estimate_server_access on public.solar_price_estimates as restrictive for all to authenticated
 using(not (select solar_private.viewer_uses_personal_prices()))
 with check(not (select solar_private.viewer_uses_personal_prices()));

do $patch$
declare calculator regprocedure; definition text;
begin
 foreach calculator in array array['solar_private.prepare_limited_quote(jsonb)'::regprocedure,
                                  'solar_private.prepare_all_in_one_quote(jsonb)'::regprocedure] loop
  definition:=pg_get_functiondef(calculator);
  if strpos(definition,'select p.id,p.name,p.cost,p.category')=0 or strpos(definition,'total_cost*0.15')=0 or
     strpos(definition,'begin')=0 or strpos(definition,'''markupPercent'',''15''')=0 or strpos(definition,'''markupPercent'',15')=0 then
   raise exception 'Unknown quote calculation: %',calculator;
  end if;
  definition:=replace(definition,'begin',$new$  selected_basis boolean:=solar_private.viewer_uses_personal_prices();
  markup numeric:=15;
begin
 if selected_basis and exists(select from public.profiles p where p.id=auth.uid() and p.permissions @> '{"tahseelFull":true}') then
  markup:=solar_private.quote_number(coalesce(input->>'markupPercent','5'),1000);
  if markup is null then errors:=errors||jsonb_build_array('أدخل نسبة الربح من صفر إلى 1000٪');end if;
 end if;$new$);
  definition:=replace(definition,'select p.id,p.name,p.cost,p.category',
   'select p.id,p.name,case when selected_basis then coalesce(solar_private.personal_product_price(p.id),p.cost) else p.cost end as cost,p.category');
  definition:=replace(definition,'total_cost*0.15','total_cost*markup/100');
  definition:=replace(definition,'''markupPercent'',''15''','''markupPercent'',markup::text');
  definition:=replace(definition,'''markupPercent'',15','''markupPercent'',markup');
  execute definition;
 end loop;
end $patch$;

-- Earlier full-access drafts saved their own expenses without the later
-- expenseOverride key. Restore that choice for a selected full-access owner
-- when listing the draft, without returning its stored material cost.
do $patch$
declare definition text:=pg_get_functiondef('solar_private.limited_quote(text,jsonb,uuid,integer,integer)'::regprocedure);
 old_read constant text:='prepared:=solar_private.prepare_limited_quote(row.payload);';
begin
 if strpos(definition,old_read)=0 then raise exception 'Unknown quote draft reader';end if;
 execute replace(definition,old_read,$new$
   if solar_private.personal_price_enabled(me.id) and me.permissions @> '{"tahseelFull":true}'
      and not(row.payload?'expenseOverride') and row.payload?'perPanel' and row.payload?'expenses'
      and not exists (
       select from unnest(array['perPanel','crane','worker','programmer','delivery','electrical','commission']) f
       cross join lateral (select solar_private.quote_number(case when f='perPanel' then row.payload->>f else row.payload->'expenses'->>f end,1e10) amount) n
       where n.amount is null or round(n.amount,2)<>n.amount
      ) then
    row.payload:=row.payload||'{"expenseOverride":true}'::jsonb;
   end if;
   prepared:=solar_private.prepare_limited_quote(row.payload);$new$);
end $patch$;
