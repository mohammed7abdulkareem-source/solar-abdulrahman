-- A read-only material report built on the existing authorized stock ledger.
-- No stock, valuation, invoice, reservation, permission or historical row changes.
create function solar_private.material_movement_report(payload jsonb)returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor public.profiles;material bigint;location bigint;date_from date;date_to date;priced boolean;can_price boolean;history jsonb;result jsonb;
begin
 select * into actor from public.profiles where id=auth.uid() and active;
 if actor.id is null or actor.user_type='installer' or not(actor.is_admin or actor.user_type='warehouse' or actor.permissions->>'stockMovement'='true' or actor.permissions->>'warehouse'='true')then raise exception 'لا تملك صلاحية حركة المواد'using errcode='42501';end if;
 if jsonb_typeof(payload)is distinct from'object'then raise exception 'طلب غير صحيح';end if;
 material:=nullif(payload->>'productId','')::bigint;location:=nullif(payload->>'warehouseId','')::bigint;
 date_from:=nullif(payload->>'from','')::date;date_to:=nullif(payload->>'to','')::date;
 if material is null or date_from>date_to then raise exception 'اختر المادة وفترة صحيحة';end if;
 can_price:=actor.user_type not in('warehouse','installer')and(actor.is_admin or actor.permissions->>'sale'='true' or actor.permissions->>'system'='true' or actor.permissions->>'purchase'='true' or actor.permissions->>'salesHistory'='true');
 can_price:=coalesce(can_price,false);priced:=coalesce(payload->>'withPrices','false')='true';
 if priced and not can_price then raise exception 'لا تملك صلاحية عرض الأسعار'using errcode='42501';end if;
 -- The original function checks warehouse access and own-only movement scope.
 -- It calculates running balances BEFORE applying date/customer/owner filters.
 history:=solar_private.inventory_movements(location,material,'',null,null);
 if not exists(select 1 from public.products where id=material)then raise exception 'المادة غير موجودة';end if;
 with base as materialized(select x.value row_data,x.ordinality seq from jsonb_array_elements(history)with ordinality x),
 period_rows as materialized(
  select * from base where(date_from is null or(row_data->>'date')::timestamptz>=date_from::timestamp at time zone'Asia/Baghdad')
   and(date_to is null or(row_data->>'date')::timestamptz<(date_to+1)::timestamp at time zone'Asia/Baghdad')
 ),details as(
  select r.seq,r.row_data||jsonb_build_object('code',p.code,'invoiceId',t.id,
   'createdByName',case when c.id is not null then solar_private.user_name(c.display_name,c.username,c.honorific)end,
   'preparedByName',case when prep.id is not null then solar_private.user_name(prep.display_name,prep.username,prep.honorific)end,
   'preparedAt',coalesce(t.warehouse_prepared_at,st.prepared_at),'preparationStatus',coalesce(t.warehouse_status,st.status),
   'executedByName',case when ex.id is not null then solar_private.user_name(ex.display_name,ex.username,ex.honorific)end)||
   case when priced then jsonb_build_object('pricing',case
    when t.id is not null and solar_private.can_access_invoice(coalesce(t.created_by,t.cashbox_user_id),false)and
     (actor.is_admin or(t.kind='purchase'and actor.permissions->>'purchase'='true')or(t.kind='sale'and(actor.permissions->>'sale'='true'or actor.permissions->>'salesHistory'='true'))or(t.kind='system'and(actor.permissions->>'system'='true'or actor.permissions->>'salesHistory'='true')))then
      case when t.kind='system'then jsonb_build_object('kind','system_total','currency','IQD')
      else jsonb_build_object('kind',case when t.kind='purchase'then'purchase'else'sale'end,'currency','IQD','unitPrice',i.price,'lineTotal',round(i.price*i.qty,2))end
    when st.id is not null and(actor.is_admin or st.actor_id=actor.id)then
     jsonb_build_object('kind','transfer_cost','currency','IQD','unitPrice',(st.items->((split_part(r.row_data->>'id',':',case when r.row_data->>'id'like'transfer-reversal:%'then 4 else 3 end))::integer-1)->>'unitCost')::numeric,
      'lineTotal',round((st.items->((split_part(r.row_data->>'id',':',case when r.row_data->>'id'like'transfer-reversal:%'then 4 else 3 end))::integer-1)->>'unitCost')::numeric*greatest((r.row_data->>'inQty')::numeric,(r.row_data->>'outQty')::numeric),2))
    else null end)else'{}'::jsonb end enriched
  from period_rows r join public.products p on p.id=material
  left join public.transaction_items i on i.id=case when r.row_data->>'id'like'line:%'then split_part(r.row_data->>'id',':',2)::bigint end
  left join public.transactions t on t.id=i.transaction_id
  left join solar_private.stock_transfers st on st.id=case when r.row_data->>'id'like'transfer-%'then split_part(r.row_data->>'id',':',2)::uuid end
  left join solar_private.stock_adjustments a on a.id=case when r.row_data->>'id'like'adjustment:%'then split_part(r.row_data->>'id',':',2)::bigint end
  left join public.profiles c on c.id=coalesce(t.created_by,st.actor_id,a.actor_id)
  left join public.profiles prep on prep.id=coalesce(t.warehouse_prepared_by,st.prepared_by)
  left join public.profiles ex on ex.id=case when r.row_data->>'kind'like'transfer_return_%'then st.reversed_by when r.row_data->>'kind'='transfer_cancelled'then st.cancelled_by when r.row_data->>'kind'='transfer_in'then st.prepared_by else coalesce(t.created_by,st.actor_id,a.actor_id)end
 ),locations as(
  select w.id,w.name,coalesce(s.qty,0)qty from solar_private.warehouses w left join solar_private.warehouse_stocks s on s.warehouse_id=w.id and s.product_id=material
  where solar_private.warehouse_access_allowed(actor.id,w.id)and(location is null or w.id=location)
 )select jsonb_build_object('product',(select jsonb_build_object('id',p.id,'code',p.code,'name',p.name,'brand',b.name,'category',p.category)from public.products p left join public.brands b on b.id=p.brand_id where p.id=material),
  'from',date_from,'to',date_to,'withPrices',priced,'canShowPrices',can_price,'scope',case when solar_private.role_name()in('admin','warehouse')then'all'else'own'end,
  'currentQty',(select coalesce(sum(qty),0)from locations),
  'rows',(select coalesce(jsonb_agg(enriched order by seq),'[]')from details),
  'warehouses',(select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'name',l.name,'currentQty',l.qty,
   'inQty',(select coalesce(sum((row_data->>'inQty')::numeric),0)from period_rows where(row_data->>'warehouseId')::bigint=l.id),
   'outQty',(select coalesce(sum((row_data->>'outQty')::numeric),0)from period_rows where(row_data->>'warehouseId')::bigint=l.id),
   'beforeFirst',(select(row_data->>'balance')::numeric-(row_data->>'inQty')::numeric+(row_data->>'outQty')::numeric from period_rows where(row_data->>'warehouseId')::bigint=l.id order by seq limit 1),
   'afterLast',(select(row_data->>'balance')::numeric from period_rows where(row_data->>'warehouseId')::bigint=l.id order by seq desc limit 1))order by l.id),'[]')from locations l)
 )into result;
 return result;
end $$;
revoke all on function solar_private.material_movement_report(jsonb)from public,anon,authenticated;
do $$declare definition text;anchor text;begin
 definition:=pg_get_functiondef('solar_private.inventory(text,uuid,jsonb)'::regprocedure);
 anchor:=' if action in(''context'',''stock'') then';
 if strpos(definition,anchor)=0 then raise exception 'Review material report dispatch anchor';end if;
 execute replace(definition,anchor,' if action=''material_report''then return solar_private.material_movement_report(payload);end if;'||E'\n'||anchor);
end $$;
notify pgrst,'reload schema';
