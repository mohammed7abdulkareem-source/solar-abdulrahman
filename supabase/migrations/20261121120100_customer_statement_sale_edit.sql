-- The customer copy omits historical costs and edit revisions. Request them only
-- for one movement authorized for both the statement and the original sale writer.
create function public.solar_statement_sale_for_edit(customer_id bigint,movement_id bigint)
returns jsonb language sql stable security invoker set search_path='' as $$
 with document as materialized (
  select public.solar_customer_movement(customer_id,movement_id) as entry
 )
 select (document.entry->'invoice') || jsonb_build_object(
  'party_id',c.id,'party_name',c.name,'created_by',t.created_by,'cashbox_user_id',t.cashbox_user_id,
  'pricing_revision',t.pricing_revision,'installation_revision',t.installation_revision,'warranty_revision',t.warranty_revision,
  'source_currency',t.source_currency,'exchange_rate',t.exchange_rate,'market_rate',t.market_rate,'cash_currency',t.cash_currency,
  'warehouse_id',t.warehouse_id,'installer_id',t.installer_id,'installation_status',t.installation_status,
  'installation_expenses',t.installation_expenses,'system_min_profit_percent',t.system_min_profit_percent,'system_pricing_revision',t.system_pricing_revision,
  'items',(select jsonb_agg(jsonb_build_object('product_id',i.product_id,'product_name',i.product_name,
          'brand_name',i.brand_name,'category',i.category,'qty',i.qty,'price',i.price,'cost',i.cost) order by i.id)
           from public.transaction_items i where i.transaction_id=t.id)
 ) from document join public.transactions t on t.id=movement_id and t.kind in('sale','system')
 join public.customers c on c.id=customer_id
 where document.entry->>'type'='invoice' and (document.entry->'invoice'->>'id')::bigint=t.id
 and (solar_private.role_name()='admin' or (t.created_by=auth.uid() and solar_private.receipt_feature(solar_private.office_features(),t.kind,true)))
$$;
revoke all on function public.solar_statement_sale_for_edit(bigint,bigint) from public,anon;
grant execute on function public.solar_statement_sale_for_edit(bigint,bigint) to authenticated;

-- Older releases resolve a customer by name. Exact selections
-- must still match that user's authorized customer, even when names are shared.
do $$declare
 definition text:=pg_get_functiondef('solar_private.invoice_save_v333(uuid,jsonb)'::regprocedure);
 previous text:=$old$select c.id into party_id from public.customers c where c.name=payload->>'party' and (p.is_admin or c.owner_id=p.id) order by c.id limit 1;$old$;
 replacement text:=$new$select c.id into party_id from public.customers c where c.name=payload->>'party'
    and (p.is_admin or c.owner_id=p.id) and (payload->>'saleCustomerId' is null or c.id=(payload->>'saleCustomerId')::bigint)
    order by c.id limit 1;$new$;
begin
 if strpos(definition,previous)=0 then raise exception 'Sale customer lookup has changed';end if;
 execute replace(definition,previous,replacement);
end $$;
