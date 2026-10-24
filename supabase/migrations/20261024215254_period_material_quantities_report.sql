-- Material quantities from every matching saved sale, independent of archive
-- paging. Remaining quantities are current, scoped warehouse availability.
create function solar_private.sales_period(search_text text default '',sale_kind text default '',date_from date default null,date_to date default null,job_status text default '') returns jsonb
language plpgsql stable security definer set search_path='' set statement_timeout='10s' as $$
declare p public.profiles;result jsonb;show_remaining boolean;begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('installer','warehouse');
 if p.id is null or not(p.is_admin or coalesce(p.permissions->>'salesHistory','false')='true' or coalesce(p.permissions->>'salesDeleteOwn','false')='true' or coalesce(p.permissions->>'sale','false')='true' or coalesce(p.permissions->>'system','false')='true' or coalesce(p.permissions->>'installations','false')='true') then raise exception 'لا تملك صلاحية مبيعات الفترة' using errcode='42501';end if;
 if length(coalesce(search_text,''))>200 or coalesce(sale_kind,'') not in('','sale','system') or coalesce(job_status,'') not in('','none','pending','in_progress','completed','closed') or(date_from is not null and date_to is not null and date_from>date_to) then raise exception 'اختر فترة ونوع مبيعات صحيحين' using errcode='22023';end if;
 show_remaining:=p.is_admin or coalesce(p.permissions->>'stock','false')='true' or coalesce(p.permissions->>'stockMovement','false')='true' or coalesce(p.permissions->>'warehouse','false')='true' or coalesce(p.permissions->>'sale','false')='true' or coalesce(p.permissions->>'system','false')='true' or coalesce(p.permissions->>'purchase','false')='true';
 with permitted as materialized(
  select t.id,t.kind,t.created_at from public.transactions t where t.kind in('sale','system')
   and(p.is_admin or(t.created_by=p.id and(
    p.permissions->>'salesHistory'='true' or p.permissions->>'salesDeleteOwn'='true' or
    (t.kind='sale' and p.permissions->>'sale'='true') or(t.kind='system' and(p.permissions->>'system'='true' or p.permissions->>'installations'='true')))))
   and(coalesce(sale_kind,'')='' or t.kind=sale_kind)
   and(coalesce(search_text,'')='' or strpos(lower(coalesce(t.party_name,'')||' '||t.receipt_no::text),lower(search_text))>0)
   and(date_from is null or t.created_at>=(date_from::timestamp at time zone 'Asia/Baghdad'))
   and(date_to is null or t.created_at<((date_to+1)::timestamp at time zone 'Asia/Baghdad'))
   and(coalesce(job_status,'')='' or(t.kind='system' and t.installation_status=job_status))
 ), grouped as(
  select i.product_id,
   jsonb_build_array(i.product_id,case when i.product_id is null then jsonb_build_array(i.product_name,i.brand_name,i.category) end) material_key,
   (array_agg(i.product_name order by t.created_at desc,t.id desc,i.id desc))[1] name,
   (array_agg(i.brand_name order by t.created_at desc,t.id desc,i.id desc))[1] brand,
   (array_agg(i.category order by t.created_at desc,t.id desc,i.id desc))[1] category,sum(i.qty) quantity_sold
  from permitted t join public.transaction_items i on i.transaction_id=t.id where i.qty>0
  group by i.product_id,jsonb_build_array(i.product_id,case when i.product_id is null then jsonb_build_array(i.product_name,i.brand_name,i.category) end)
 ), material_rows as(
  select g.*,coalesce(m.code,'') code,
   case when show_remaining and m.id is not null then coalesce((select sum(w.qty) from solar_private.warehouse_stocks w where w.product_id=m.id and solar_private.warehouse_access_allowed(p.id,w.warehouse_id)),0) end remaining_qty
  from grouped g left join public.products m on m.id=g.product_id
 )
 select jsonb_build_object('asOf',statement_timestamp(),'scope',case when p.is_admin then 'company' else 'own' end,'from',date_from,'to',date_to,'kind',coalesce(sale_kind,''),'status',coalesce(job_status,''),'search',coalesce(search_text,''),'canViewRemaining',show_remaining,
  'summary',jsonb_build_object('invoiceCount',(select count(*) from permitted),'materialCount',(select count(*) from material_rows),'quantitySold',(select coalesce(sum(quantity_sold),0) from material_rows)),
  'rows',coalesce((select jsonb_agg(jsonb_build_object('key',material_key,'productId',product_id,'code',code,'name',name,'brand',coalesce(brand,''),'category',coalesce(category,''),'quantitySold',quantity_sold,'remainingQty',remaining_qty)
   order by case when translate(code,'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789')~'^[0-9]+$' then translate(code,'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789')::numeric end nulls last,code,name,material_key::text) from material_rows),'[]')) into result;
 return result;
end$$;
create function public.solar_sales_period(search_text text default '',sale_kind text default '',date_from date default null,date_to date default null,job_status text default '') returns jsonb
language sql stable security invoker set search_path='' as $$select solar_private.sales_period(search_text,sale_kind,date_from,date_to,job_status)$$;
revoke all on function solar_private.sales_period(text,text,date,date,text),public.solar_sales_period(text,text,date,date,text) from public,anon;
grant execute on function solar_private.sales_period(text,text,date,date,text),public.solar_sales_period(text,text,date,date,text) to authenticated;
notify pgrst,'reload schema';
