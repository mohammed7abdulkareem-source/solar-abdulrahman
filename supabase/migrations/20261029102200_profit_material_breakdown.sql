-- A profit recipient may inspect the materials behind their attributed profit,
-- without receiving the original customer's account, contact or payment data.
create or replace function solar_private.profit_detail(source_key text,owner_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;uid uuid;movement jsonb;t public.transactions;invoice jsonb;breakdown jsonb;lines jsonb;materials_cost numeric;sales numeric;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 if p.id is null or not(p.is_admin or p.permissions->>'profit'='true' or p.permissions->>'profitSettlement'='true') then raise exception 'لا تملك صلاحية الأرباح' using errcode='42501';end if;
 uid:=coalesce(owner_id,p.id);
 if not p.is_admin and uid<>p.id then raise exception 'يمكنك مشاهدة وصولات أرباحك فقط' using errcode='42501';end if;
 select value into movement from jsonb_array_elements(solar_private.profit_rows(uid)) where value->>'key'=source_key;
 if movement is null then raise exception 'الحركة غير متاحة ضمن هذا الحساب' using errcode='42501';end if;
 if source_key ~ '^tx:-?[0-9]+$' and not coalesce((movement->>'deleted')::boolean,false) then
  select * into t from public.transactions where id=substr(source_key,4)::bigint;
  if t.id is not null then
   if t.kind in('sale','system') then
    select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'productId',i.product_id,'code',m.code,'name',i.product_name,
     'brand',solar_private.current_product_brand(i.product_id,i.brand_name),'category',i.category,'qty',i.qty,'unitCost',i.cost,'lineCost',i.qty*i.cost,
     'unitPrice',case when t.kind='sale' then i.price end,'lineSales',case when t.kind='sale' then i.qty*i.price end,
     'lineProfit',case when t.kind='sale' then i.qty*(i.price-i.cost) end) order by i.id),'[]'),coalesce(sum(i.qty*i.cost),0)
    into lines,materials_cost from public.transaction_items i left join public.products m on m.id=i.product_id where i.transaction_id=t.id;
    sales:=case when t.kind='sale' then coalesce(t.subtotal,t.total) else t.total end;
    breakdown:=jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'kind',t.kind,'party',t.party_name,'date',t.created_at,'warehouseName',t.warehouse_name,
     'creatorName',(select solar_private.user_name(display_name,username,honorific) from public.profiles where id=t.created_by),
     'total',t.total,'sales',sales,'materialsCost',materials_cost,'invoiceExpenses',coalesce(t.expenses,0),'installationExpenses',coalesce(t.installation_expenses,0),
     'grossProfit',sales-materials_cost,'netProfit',(movement->>'value')::numeric,'profitAdjustment',(movement->>'value')::numeric-(sales-materials_cost),'items',lines);
   end if;
   if not p.is_admin and coalesce(t.created_by,t.cashbox_user_id)<>p.id then return jsonb_build_object('movement',movement,'invoice',null,'transferred',true,'breakdown',breakdown);end if;
   invoice:=solar_private.receipt_contact_json(to_jsonb(t)||jsonb_build_object('items',coalesce((select jsonb_agg((to_jsonb(i)||jsonb_build_object('brand_name',solar_private.current_product_brand(i.product_id,i.brand_name))) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]'),
    'installerName',(select solar_private.user_name(display_name,username,honorific) from public.profiles where id=t.installer_id)),'transaction');
  end if;
 end if;
 return jsonb_build_object('movement',movement,'invoice',invoice,'breakdown',breakdown);
end$$;
notify pgrst,'reload schema';
