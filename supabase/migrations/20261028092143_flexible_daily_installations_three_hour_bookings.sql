-- A fixed appointment reserves three hours. Unscheduled and overdue work
-- remains in each day's actionable queue until installation is completed.
-- Derive the daily queue without rewriting original appointment or financial records.
CREATE OR REPLACE FUNCTION solar_private.installation_slot(day date, at_time time without time zone)
 RETURNS tstzrange
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select tstzrange((day+at_time) at time zone 'Asia/Baghdad',((day+at_time) at time zone 'Asia/Baghdad')+interval '3 hours','[)')
$function$;

CREATE OR REPLACE FUNCTION solar_private.installation_schedule(date_from date, date_to date, installer_id uuid DEFAULT NULL::uuid, exclude_invoice_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_variable
declare p public.profiles;excluded public.transactions;begin
 select * into p from public.profiles where id=auth.uid() and active and user_type<>'warehouse';
 if p.id is null or not(p.user_type='installer' or p.is_admin or coalesce(p.permissions->>'system','false')='true' or coalesce(p.permissions->>'installations','false')='true' or coalesce(p.permissions->>'installationsAll','false')='true') then raise exception 'لا تملك صلاحية جدول التنصيبات' using errcode='42501';end if;
 if date_from is null or date_to is null or date_to<date_from or date_to-date_from>30 then raise exception 'اختر فترة لا تتجاوز 31 يومًا' using errcode='22023';end if;
 if p.user_type='installer' and installer_id is not null and installer_id<>p.id then raise exception 'جدول المهندس يخص مهامه فقط' using errcode='42501';end if;
 if exclude_invoice_id is not null then
  select * into excluded from public.transactions t where t.id=exclude_invoice_id and t.kind='system';
  if excluded.id is null or not(case when p.user_type='installer' then excluded.installer_id=p.id else p.is_admin or excluded.created_by=p.id end) then raise exception 'الفاتورة غير متاحة' using errcode='42501';end if;
 end if;
 return jsonb_build_object('durationHours',3,'from',date_from,'to',date_to,
  'engineers',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'name',solar_private.user_name(e.display_name,e.username,e.honorific)) order by solar_private.user_name(e.display_name,e.username,e.honorific),e.id)
   from public.profiles e where e.active and e.user_type='installer' and(p.user_type<>'installer' or e.id=p.id)),'[]'),
  'backlog',coalesce((select jsonb_agg(jsonb_build_object('installerId',t.installer_id,
   'installerName',(select solar_private.user_name(e.display_name,e.username,e.honorific)from public.profiles e where e.id=t.installer_id),
   'installDate',t.install_date,'installTime',t.install_time,'createdDay',(t.created_at at time zone 'Asia/Baghdad')::date,
   'installationStatus',t.installation_status,'own',case when p.user_type='installer'then t.installer_id=p.id else p.is_admin or t.created_by=p.id end)
   ||case when(case when p.user_type='installer'then t.installer_id=p.id else p.is_admin or t.created_by=p.id end)then
    jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'party',t.party_name,'creatorName',(select solar_private.user_name(c.display_name,c.username,c.honorific)from public.profiles c where c.id=t.created_by))else '{}'::jsonb end
   order by t.install_date nulls first,t.created_at,t.id)
   from public.transactions t where t.kind='system'and t.installation_status in('pending','in_progress')
   and(t.install_date is null or t.install_time is null or t.install_date<date_to)
   and(t.created_at at time zone 'Asia/Baghdad')::date<=date_to
   and(exclude_invoice_id is null or t.id<>exclude_invoice_id)
   and(installer_id is null or t.installer_id=installer_id)and(p.user_type<>'installer'or t.installer_id=p.id)),'[]'),
  'slots',coalesce((select jsonb_agg(jsonb_build_object('installerId',t.installer_id,'start',lower(solar_private.installation_slot(t.install_date,t.install_time)),
    'end',upper(solar_private.installation_slot(t.install_date,t.install_time)),'own',case when p.user_type='installer' then t.installer_id=p.id else p.is_admin or t.created_by=p.id end)
    ||case when(case when p.user_type='installer' then t.installer_id=p.id else p.is_admin or t.created_by=p.id end) then
     jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'party',t.party_name,'status',t.installation_status,'creatorName',(select solar_private.user_name(c.display_name,c.username,c.honorific) from public.profiles c where c.id=t.created_by)) else '{}'::jsonb end
    order by t.install_date,t.install_time,t.id)
   from public.transactions t where t.kind='system' and t.installer_id is not null and t.install_date between date_from-1 and date_to and t.install_time is not null
   and(t.installation_status is not null) and(exclude_invoice_id is null or t.id<>exclude_invoice_id)
   and(installer_id is null or t.installer_id=installer_id) and(p.user_type<>'installer' or t.installer_id=p.id)
   and solar_private.installation_slot(t.install_date,t.install_time)&&tstzrange(date_from::timestamp at time zone 'Asia/Baghdad',(date_to+1)::timestamp at time zone 'Asia/Baghdad','[)')),'[]'));
end$function$;
