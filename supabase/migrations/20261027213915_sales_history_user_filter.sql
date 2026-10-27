-- Filter before paging and aggregation. Existing public RPC names keep their
-- original arguments, so older clients retain their current authorized scope.
CREATE OR REPLACE FUNCTION solar_private.sales_history(search_text text DEFAULT ''::text, sale_kind text DEFAULT ''::text, date_from date DEFAULT NULL::date, date_to date DEFAULT NULL::date, job_status text DEFAULT ''::text, page_offset integer DEFAULT 0, owner_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles; result jsonb;selected_user uuid;
begin
 if solar_private.role_name()='warehouse' then raise exception 'Not permitted' using errcode='42501';end if;
 select * into p from public.profiles where id=auth.uid() and active=true;
 if p.id is null or p.user_type='installer' then raise exception 'Not permitted' using errcode='42501'; end if;
 if owner_id is not null and not p.is_admin and owner_id<>p.id then raise exception 'يمكنك مشاهدة مبيعاتك فقط' using errcode='42501';end if;
 selected_user:=case when p.is_admin then owner_id else p.id end;
 if selected_user is not null and not exists(select 1 from public.profiles u where u.id=selected_user)then raise exception 'المستخدم غير متاح' using errcode='22023';end if;
 with permitted as (
 select t.* from public.transactions t where t.kind in ('sale','system') and(selected_user is null or t.created_by=selected_user)
 and (p.is_admin or(t.created_by=p.id and(
  p.permissions->>'salesHistory'='true' or p.permissions->>'salesDeleteOwn'='true' or
  (t.kind='sale' and p.permissions->>'sale'='true') or
  (t.kind='system' and(p.permissions->>'system'='true' or p.permissions->>'installations'='true')))))
 and (coalesce(sale_kind,'')='' or t.kind=sale_kind)
 and (coalesce(search_text,'')='' or strpos(lower(coalesce(t.party_name,'')||' '||t.receipt_no::text),lower(search_text))>0)
 and (date_from is null or t.created_at >= (date_from::timestamp at time zone 'Asia/Baghdad'))
 and (date_to is null or t.created_at < ((date_to+1)::timestamp at time zone 'Asia/Baghdad'))
 and (coalesce(job_status,'')='' or (t.kind='system' and t.installation_status=job_status))
 ), page_rows as (select * from permitted order by created_at desc,id desc limit 30 offset greatest(coalesce(page_offset,0),0))
 select jsonb_build_object('ownerId',selected_user,'ownerName',case when selected_user is null then 'جميع المستخدمين' else(select coalesce(solar_private.user_name(u.display_name,u.username,u.honorific),'مستخدم') from public.profiles u where u.id=selected_user)end,
 'users',case when p.is_admin then(select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'name',coalesce(solar_private.user_name(u.display_name,u.username,u.honorific),'مستخدم'),'active',u.active)order by u.display_name,u.id),'[]') from public.profiles u where (u.active and u.user_type not in('installer','warehouse')) or exists(select 1 from public.transactions s where s.created_by=u.id and s.kind in('sale','system'))) else jsonb_build_array(jsonb_build_object('id',p.id,'name',coalesce(solar_private.user_name(p.display_name,p.username,p.honorific),'مستخدم'),'active',p.active))end,'count',(select count(*) from permitted),'rows',coalesce((
 select jsonb_agg(to_jsonb(t)||jsonb_build_object(
 'canDelete',solar_private.can_delete_sale(t.created_by),
 'creatorName',(select solar_private.user_name(x.display_name,x.username,x.honorific) from public.profiles x where x.id=t.created_by),
 'installerName',(select solar_private.user_name(x.display_name,x.username,x.honorific) from public.profiles x where x.id=t.installer_id),
 'items',coalesce((select jsonb_agg((to_jsonb(i)||jsonb_build_object('brand_name',solar_private.current_product_brand(i.product_id,i.brand_name))) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]'::jsonb)
 ) order by t.created_at desc,t.id desc) from page_rows t),'[]'::jsonb)) into result;
 return result;
end $function$
;
CREATE OR REPLACE FUNCTION solar_private.sales_period(search_text text DEFAULT ''::text, sale_kind text DEFAULT ''::text, date_from date DEFAULT NULL::date, date_to date DEFAULT NULL::date, job_status text DEFAULT ''::text, owner_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
declare p public.profiles;result jsonb;show_remaining boolean;selected_user uuid;begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('installer','warehouse');
 if p.id is null or not(p.is_admin or coalesce(p.permissions->>'salesHistory','false')='true' or coalesce(p.permissions->>'salesDeleteOwn','false')='true' or coalesce(p.permissions->>'sale','false')='true' or coalesce(p.permissions->>'system','false')='true' or coalesce(p.permissions->>'installations','false')='true') then raise exception 'لا تملك صلاحية مبيعات الفترة' using errcode='42501';end if;
 if length(coalesce(search_text,''))>200 or coalesce(sale_kind,'') not in('','sale','system') or coalesce(job_status,'') not in('','none','pending','in_progress','completed','closed') or(date_from is not null and date_to is not null and date_from>date_to) then raise exception 'اختر فترة ونوع مبيعات صحيحين' using errcode='22023';end if;
 if owner_id is not null and not p.is_admin and owner_id<>p.id then raise exception 'يمكنك مشاهدة مبيعاتك فقط' using errcode='42501';end if;
 selected_user:=case when p.is_admin then owner_id else p.id end;
 if selected_user is not null and not exists(select 1 from public.profiles u where u.id=selected_user)then raise exception 'المستخدم غير متاح' using errcode='22023';end if;
 show_remaining:=p.is_admin or coalesce(p.permissions->>'stock','false')='true' or coalesce(p.permissions->>'stockMovement','false')='true' or coalesce(p.permissions->>'warehouse','false')='true' or coalesce(p.permissions->>'sale','false')='true' or coalesce(p.permissions->>'system','false')='true' or coalesce(p.permissions->>'purchase','false')='true';
 with permitted as materialized(
  select t.id,t.kind,t.created_at from public.transactions t where t.kind in('sale','system') and(selected_user is null or t.created_by=selected_user)
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
 select jsonb_build_object('asOf',statement_timestamp(),'scope',case when p.is_admin and selected_user is null then 'company' else 'own' end,'ownerId',selected_user,'ownerName',case when selected_user is null then 'جميع المستخدمين' else(select coalesce(solar_private.user_name(u.display_name,u.username,u.honorific),'مستخدم') from public.profiles u where u.id=selected_user)end,
 'users',case when p.is_admin then(select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'name',coalesce(solar_private.user_name(u.display_name,u.username,u.honorific),'مستخدم'),'active',u.active)order by u.display_name,u.id),'[]') from public.profiles u where (u.active and u.user_type not in('installer','warehouse')) or exists(select 1 from public.transactions s where s.created_by=u.id and s.kind in('sale','system'))) else jsonb_build_array(jsonb_build_object('id',p.id,'name',coalesce(solar_private.user_name(p.display_name,p.username,p.honorific),'مستخدم'),'active',p.active))end,'from',date_from,'to',date_to,'kind',coalesce(sale_kind,''),'status',coalesce(job_status,''),'search',coalesce(search_text,''),'canViewRemaining',show_remaining,
  'summary',jsonb_build_object('invoiceCount',(select count(*) from permitted),'materialCount',(select count(*) from material_rows),'quantitySold',(select coalesce(sum(quantity_sold),0) from material_rows)),
  'rows',coalesce((select jsonb_agg(jsonb_build_object('key',material_key,'productId',product_id,'code',code,'name',name,'brand',solar_private.current_product_brand(product_id,coalesce(brand,'')),'category',coalesce(category,''),'quantitySold',quantity_sold,'remainingQty',remaining_qty)
   order by case when translate(code,'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789')~'^[0-9]+$' then translate(code,'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789')::numeric end nulls last,code,name,material_key::text) from material_rows),'[]')) into result;
 return result;
end$function$
;
CREATE OR REPLACE FUNCTION public.solar_sales_history(search_text text DEFAULT ''::text, sale_kind text DEFAULT ''::text, date_from date DEFAULT NULL::date, date_to date DEFAULT NULL::date, job_status text DEFAULT ''::text, page_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select solar_private.receipt_contact_json(solar_private.sales_history(search_text,sale_kind,date_from,date_to,job_status,page_offset,null),'rows')$function$
;
CREATE OR REPLACE FUNCTION public.solar_sales_period(search_text text DEFAULT ''::text, sale_kind text DEFAULT ''::text, date_from date DEFAULT NULL::date, date_to date DEFAULT NULL::date, job_status text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$select solar_private.sales_period(search_text,sale_kind,date_from,date_to,job_status,null)$function$
;
drop function solar_private.sales_history(text,text,date,date,text,integer);
drop function solar_private.sales_period(text,text,date,date,text);

create function public.solar_sales_history_by_user(owner_id uuid,search_text text default '',sale_kind text default '',date_from date default null,date_to date default null,job_status text default '',page_offset integer default 0)returns jsonb
language sql stable security invoker set search_path='' as $$
 select solar_private.receipt_contact_json(solar_private.sales_history(search_text,sale_kind,date_from,date_to,job_status,page_offset,owner_id),'rows')
$$;
create function public.solar_sales_period_by_user(owner_id uuid,search_text text default '',sale_kind text default '',date_from date default null,date_to date default null,job_status text default '')returns jsonb
language sql stable security invoker set search_path='' as $$
 select solar_private.sales_period(search_text,sale_kind,date_from,date_to,job_status,owner_id)
$$;
revoke all on function solar_private.sales_history(text,text,date,date,text,integer,uuid),solar_private.sales_period(text,text,date,date,text,uuid),public.solar_sales_history_by_user(uuid,text,text,date,date,text,integer),public.solar_sales_period_by_user(uuid,text,text,date,date,text)from public,anon;
grant execute on function solar_private.sales_history(text,text,date,date,text,integer,uuid),solar_private.sales_period(text,text,date,date,text,uuid),public.solar_sales_history_by_user(uuid,text,text,date,date,text,integer),public.solar_sales_period_by_user(uuid,text,text,date,date,text)to authenticated;
notify pgrst,'reload schema';
