-- The original reporting scope is still used for period totals, accounting and
-- older clients. Clients that display transferred receipts explicitly opt in.
do $migration$
declare definition text;
begin
 definition:=pg_get_functiondef('solar_private.sales_history(text,text,date,date,text,integer,uuid)'::regprocedure);
 if md5(definition)<>'7459a5d0dd66f271228b1a0e4a986526' then
  raise exception 'Review current sale archive before adding receipt responsibility';
 end if;
 definition:=replace(definition,'FUNCTION solar_private.sales_history(','FUNCTION solar_private.sales_work_history(');
 definition:=replace(definition,'owner_id uuid DEFAULT NULL::uuid)','owner_id uuid DEFAULT NULL::uuid, include_assigned boolean DEFAULT false)');
 definition:=replace(definition,
  $old$select t.* from public.transactions t where t.kind in ('sale','system') and(selected_user is null or t.created_by=selected_user)
 and(p.is_admin or (t.created_by=p.id and solar_private.history_feature(p.permissions,t.kind)))$old$,
  $new$select t.*,a.owner_id assigned_to from public.transactions t
  left join solar_private.customer_receipt_responsibility a on a.transaction_id=t.id
  where t.kind in ('sale','system')
   and(selected_user is null or t.created_by=selected_user or (include_assigned and not p.is_admin and a.owner_id=p.id))
   and(p.is_admin or solar_private.history_feature(p.permissions,t.kind))$new$);
 definition:=replace(definition,$old$jsonb_agg(to_jsonb(t)||jsonb_build_object($old$,
  $new$jsonb_agg((case when p.is_admin or t.created_by=p.id then to_jsonb(t)-'assigned_to' else
   jsonb_build_object('id',t.id,'kind',t.kind,'receipt_no',t.receipt_no,'created_at',t.created_at,
    'created_by',t.created_by,'party_name',t.party_name,'party_id',t.party_id,'total',t.total,
    'cash',t.cash,'payment_mode',t.payment_mode,'expenses_on_customer',t.expenses_on_customer,
    'expenses',case when t.kind='sale' and coalesce(t.expenses_on_customer,true) then t.expenses else 0 end,
    'warehouse_name',t.warehouse_name,'warehouse_status',t.warehouse_status,'warehouse_qr_token',t.warehouse_qr_token,
    'warranty',t.warranty,'customer_phone',t.customer_phone,'customer_address',t.customer_address,'install_date',t.install_date,
    'install_time',t.install_time,'installation_status',t.installation_status,'notes',t.notes)
   end)||jsonb_build_object(
   'operationalOwnerId',coalesce(t.assigned_to,t.created_by),
   'assignedReceipt',t.assigned_to=p.id and t.created_by is distinct from p.id,
   'issuerName',(select solar_private.user_name(x.display_name,x.username,x.honorific) from public.profiles x where x.id=t.created_by),$new$);
 definition:=replace(definition,$old$(to_jsonb(i)||jsonb_build_object('brand_name'$old$,
  $new$((case when p.is_admin or t.created_by=p.id then to_jsonb(i)
     else jsonb_build_object('id',i.id,'product_id',i.product_id,'product_name',i.product_name,
                             'category',i.category,'qty',i.qty,'price',case when t.kind='sale' then i.price end)
     end)||jsonb_build_object('brand_name'$new$);
 execute definition;
end $migration$;

-- Keep one implementation of the filters and pagination without changing the
-- results expected by callers that only expose historically issued receipts.
create or replace function solar_private.sales_history(search_text text default '',sale_kind text default '',date_from date default null,date_to date default null,job_status text default '',page_offset integer default 0,owner_id uuid default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select solar_private.sales_work_history(search_text,sale_kind,date_from,date_to,job_status,page_offset,owner_id,false)
$$;

create function public.solar_sales_history_by_user(owner_id uuid,search_text text,sale_kind text,date_from date,date_to date,job_status text,page_offset integer,include_assigned boolean)
returns jsonb language sql stable security invoker set search_path='' as $$
 select solar_private.receipt_contact_json(solar_private.sales_work_history(search_text,sale_kind,date_from,date_to,job_status,page_offset,owner_id,include_assigned),'rows')
$$;
revoke all on function solar_private.sales_work_history(text,text,date,date,text,integer,uuid,boolean),public.solar_sales_history_by_user(uuid,text,text,date,date,text,integer,boolean) from public,anon,authenticated;
grant execute on function solar_private.sales_work_history(text,text,date,date,text,integer,uuid,boolean),public.solar_sales_history_by_user(uuid,text,text,date,date,text,integer,boolean) to authenticated;
notify pgrst,'reload schema';
