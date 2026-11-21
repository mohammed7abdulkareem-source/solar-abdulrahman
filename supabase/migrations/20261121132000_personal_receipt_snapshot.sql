-- Scoped replacement for the shared snapshot's raw transaction and item reads.
-- Unrestricted clients continue to use their original RLS-protected tables.
create index personal_price_receipts_source on solar_private.personal_price_receipts(source_user_id,invoice_id);

-- A seller removed from the setting still sees the original basis of their
-- personal receipts. Other receipts use their regular permissions and costs.
create function solar_private.viewer_has_frozen_receipt(receipt bigint) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from solar_private.personal_price_receipts r join public.profiles p on p.id=r.source_user_id
  where r.invoice_id=$1 and r.source_user_id=auth.uid() and p.active and not p.is_admin and p.user_type not in ('installer','warehouse'))
$$;
revoke all on function solar_private.viewer_has_frozen_receipt(bigint) from public,anon;
grant execute on function solar_private.viewer_has_frozen_receipt(bigint) to authenticated;
alter policy personal_cost_receipt_read on public.transactions using
 (kind not in ('sale','system','purchase') or (not (select solar_private.viewer_uses_personal_prices()) and not solar_private.viewer_has_frozen_receipt(id)));
alter policy personal_cost_line_read on public.transaction_items using
 (not (select solar_private.viewer_uses_personal_prices()) and not solar_private.viewer_has_frozen_receipt(transaction_id));

-- Receipt-capable clients already read their contact card in the shared load.
-- Signal former participants there to avoid an extra scan for other staff.
do $migration$
declare definition text:=pg_get_functiondef('solar_private.receipt_contacts()'::regprocedure);
 old constant text:='''creatorPhone'',x.phone)';
begin
 if strpos(definition,old)=0 then raise exception 'Review receipt contact metadata before adding historical price marker';end if;
 execute replace(definition,old,$new$'creatorPhone',x.phone)||case when x.id=p.id and not p.is_admin and
    exists(select 1 from solar_private.personal_price_receipts r where r.source_user_id=p.id)
   then '{"hasPersonalReceipts":true}'::jsonb else '{}'::jsonb end$new$);
end $migration$;

create function solar_private.personal_receipt_snapshot(after_id bigint, kinds text[]) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor public.profiles; selected boolean:=solar_private.viewer_uses_personal_prices();
begin
 select * into actor from public.profiles where id=auth.uid();
 if actor.id is null or not actor.active or actor.is_admin or actor.user_type in ('installer','warehouse')
    or (not selected and not exists(select 1 from solar_private.personal_price_receipts r where r.source_user_id=actor.id)) then
  raise exception 'هذا الكشف مخصص لحسابات التسعير المحدد' using errcode='42501';
 end if;
 return (
  with page as materialized (
   select t.* from public.transactions t
   where t.created_by=actor.id and coalesce(t.cashbox_user_id,t.created_by)=actor.id
    and t.kind in ('sale','system','purchase') and t.kind=any(kinds)
    and (selected or solar_private.viewer_has_frozen_receipt(t.id))
    and solar_private.receipt_feature(actor.permissions,t.kind,false)
    and (after_id is null or t.id>after_id)
   order by t.id limit 200
  )
  select coalesce(jsonb_agg(jsonb_build_object('header',case when t.kind='purchase' then
     jsonb_build_object('id',t.id,'kind',t.kind,'receipt_no',t.receipt_no,'created_at',t.created_at,
     'created_by',t.created_by,'cashbox_user_id',t.cashbox_user_id,'warehouse_id',t.warehouse_id,'warehouse_name',t.warehouse_name,
     'party_id',t.party_id,'party_name',t.party_name,'cash',t.cash,'payment_mode',t.payment_mode,'pricing_revision',t.pricing_revision,
     'personalCostHidden',true)
    else solar_private.personal_archive_header(t.id,to_jsonb(h)) end,
   'items',(select coalesce(jsonb_agg(case when t.kind='purchase' then
      jsonb_build_object('id',i.id,'transaction_id',t.id,'product_id',i.product_id,'product_name',i.product_name,
       'brand_name',i.brand_name,'category',i.category,'qty',i.qty,'personalCostHidden',true)
     else solar_private.personal_archive_line(t.id,i.product_id,to_jsonb(line)) end order by i.id),'[]')
     from public.transaction_items i cross join lateral (
      select i.id,i.transaction_id,i.product_id,i.product_name,i.brand_name,i.category,i.qty,i.price
     ) line where i.transaction_id=t.id))
   order by t.id),'[]') from page t cross join lateral (
    select t.id,t.warehouse_id,t.warehouse_name,t.invoice_account,t.profit_settlement_id,t.profit_supplier_settlement_id,
       t.profit_supplier_owner_id,t.warehouse_qr_token,t.warehouse_status,t.warehouse_revision,t.warehouse_prepared_at,t.warranty,
       t.warranty_token,t.warranty_revision,t.cash_purpose,t.receipt_no,t.source_currency,t.exchange_rate,
       t.source_subtotal,t.fx_pricing,t.pricing_revision,t.system_min_profit_percent,t.system_pricing_revision,t.account_currency,
       t.account_amount,t.account_revision,t.market_rate,t.cash_currency,t.cash_amount,t.fx_accounted,
       t.system_invoice_id,t.kind,t.party_name,t.party_id,t.created_by,t.installer_id,
       t.install_date,t.install_time,t.customer_phone,t.customer_address,t.installation_status,t.installation_completed_at,
       t.installation_closed_at,t.installation_expenses,t.installation_expense_notes,t.cashbox_user_id,t.capital_effect,t.total,
       t.subtotal,t.expenses,t.expenses_on_customer,t.cost,t.profit,t.cash,
       t.notes,t.payment_mode,t.created_at
   ) h
 );
end $$;
revoke all on function solar_private.personal_receipt_snapshot(bigint,text[]) from public,anon;
grant execute on function solar_private.personal_receipt_snapshot(bigint,text[]) to authenticated;
create function public.solar_personal_receipt_snapshot(after_id bigint,kinds text[]) returns jsonb
language sql stable security invoker set search_path='' as $$
 select solar_private.personal_receipt_snapshot(after_id,kinds)
$$;
revoke all on function public.solar_personal_receipt_snapshot(bigint,text[]) from public,anon;
grant execute on function public.solar_personal_receipt_snapshot(bigint,text[]) to authenticated;
notify pgrst,'reload schema';
