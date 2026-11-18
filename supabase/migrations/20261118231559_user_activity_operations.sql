-- The permission-checked activity RPC invokes this helper with the selected
-- user and inclusive Baghdad business dates. Never return warehouse line
-- snapshots: they can carry amounts, historical costs and customer details.
create function solar_private.user_activity_operations(uid uuid, date_from date, date_to date)
returns jsonb language sql stable security invoker set search_path='' as $$
 with bounds as (
  select coalesce(date_from::timestamp at time zone 'Asia/Baghdad','-infinity'::timestamptz) as first_at,
         coalesce((date_to+1)::timestamp at time zone 'Asia/Baghdad','infinity'::timestamptz) as until_at
 ), receipts as (
  select t.id,t.kind,t.receipt_no,t.warehouse_name,t.warehouse_prepared_by,t.warehouse_prepared_at,
         t.installer_id,t.install_date,t.install_time,t.installation_started_at,t.installation_completed_at,
         t.installation_closed_at,t.installation_report->>'submittedBy' as report_author,false as archived
  from public.transactions t where t.kind in ('sale','system')
  union all
  select d.invoice_id,t.kind,t.receipt_no,t.warehouse_name,t.warehouse_prepared_by,t.warehouse_prepared_at,
         t.installer_id,t.install_date,t.install_time,t.installation_started_at,t.installation_completed_at,
         t.installation_closed_at,t.installation_report->>'submittedBy',true
  from solar_private.deleted_sales d
  cross join lateral jsonb_to_record(d.invoice) as t(
   kind text,receipt_no bigint,warehouse_name text,warehouse_prepared_by uuid,warehouse_prepared_at timestamptz,
   installer_id uuid,install_date date,install_time time,installation_started_at timestamptz,
   installation_completed_at timestamptz,installation_closed_at timestamptz,installation_report jsonb
  )
  where d.invoice->>'kind' in ('sale','system')
 ), warehouse_events as (
  select 'warehouse:'||a.id as event_key,
         case a.action when 'ready' then 'warehouse_ready' when 'save' then 'warehouse_edit' else 'warehouse_reopen' end as kind,
         a.created_at as at,r.receipt_no,r.warehouse_name,r.kind as receipt_kind,r.archived
  from solar_private.warehouse_audit a left join receipts r on r.id=a.invoice_id cross join bounds b
  where a.actor_id=uid and a.action in ('ready','save','reopen') and a.created_at>=b.first_at and a.created_at<b.until_at
  union all
  -- Imports/older receipts can retain a preparer and date without an audit
  -- event. A modern ready transition writes both at the same instant.
  select 'prepared:'||r.id,'warehouse_ready',r.warehouse_prepared_at,r.receipt_no,r.warehouse_name,r.kind,r.archived
  from receipts r cross join bounds b
  where r.warehouse_prepared_by=uid and r.warehouse_prepared_at>=b.first_at and r.warehouse_prepared_at<b.until_at
   and not exists (select 1 from solar_private.warehouse_audit a where a.invoice_id=r.id
       and a.actor_id=uid and a.action='ready' and a.created_at=r.warehouse_prepared_at)
  union all
  select 'transfer:'||t.id,'transfer_prepared',t.prepared_at,t.receipt_no,
         concat_ws(' ← ',t.from_name,t.to_name),null::text,false
  from solar_private.stock_transfers t cross join bounds b
  where t.prepared_by=uid and t.prepared_at>=b.first_at and t.prepared_at<b.until_at
 ), installation_events as (
  -- Scheduled means a booking on the engineer's calendar; the invoice's
  -- creation time does not say when an assignment was made.
  select 'appointment:'||r.id as event_key,'installation_scheduled' as kind,
         (r.install_date+coalesce(r.install_time,time '00:00')) at time zone 'Asia/Baghdad' as at,
         r.receipt_no,r.warehouse_name,r.kind as receipt_kind,r.archived
  from receipts r where r.kind='system' and r.installer_id=uid and not r.archived and r.install_date is not null
   and (date_from is null or r.install_date>=date_from) and (date_to is null or r.install_date<=date_to)
  union all
  select event.kind||':'||r.id,event.kind,event.at,r.receipt_no,r.warehouse_name,r.kind,r.archived
  from receipts r cross join bounds b
  cross join lateral (values
    ('installation_started',r.installation_started_at),
    ('installation_completed',r.installation_completed_at),
    ('installation_closed',r.installation_closed_at)
  ) event(kind,at)
  -- A seller can reassign a job while editing the invoice. A successful
  -- saved invoice gives the assignee at that stage; use the report signer
  -- for completion and the receipt's engineer for legacy unedited jobs.
  left join lateral (
   select q.payload->>'installerId' as engineer
   from solar_private.invoice_requests q
   where q.result->>'id'=r.id::text and q.payload->>'kind'='system'
    and q.payload->>'installerId' is not null and q.created_at<=event.at
   order by q.created_at desc,coalesce((q.payload->>'expectedRevision')::bigint,-1) desc,q.request_id desc limit 1
  ) assignment on true
  where r.kind='system' and event.at>=b.first_at and event.at<b.until_at
   and coalesce(case when event.kind='installation_completed' then nullif(r.report_author,'') end,
                assignment.engineer,r.installer_id::text)=uid::text
 ), events as (
  select * from warehouse_events union all select * from installation_events
 ), recent as (
  select * from events order by at desc,event_key desc limit 25
 )
 select jsonb_build_object(
  'warehouse',jsonb_build_object(
   'prepared',count(*) filter (where kind='warehouse_ready'),
   'preparedWholesale',count(*) filter (where kind='warehouse_ready' and receipt_kind='sale'),
   'preparedSystems',count(*) filter (where kind='warehouse_ready' and receipt_kind='system'),
   'edited',count(*) filter (where kind='warehouse_edit'),
   'reopened',count(*) filter (where kind='warehouse_reopen'),
   'transfersPrepared',count(*) filter (where kind='transfer_prepared')),
  'installer',jsonb_build_object(
   'scheduled',count(*) filter (where kind='installation_scheduled'),
   'started',count(*) filter (where kind='installation_started'),
   'completed',count(*) filter (where kind='installation_completed'),
   'closed',count(*) filter (where kind='installation_closed')),
  'recent',coalesce((select jsonb_agg(jsonb_build_object(
   'id',event_key,'kind',kind,'at',at,'receiptNo',receipt_no,'warehouseName',warehouse_name,
   'archived',coalesce(archived,false),'label',case kind
    when 'warehouse_ready' then 'تجهيز وصل'
    when 'warehouse_edit' then 'تعديل مواد التجهيز'
    when 'warehouse_reopen' then 'إعادة فتح التجهيز'
    when 'transfer_prepared' then 'تجهيز نقل مخزني'
    when 'installation_scheduled' then 'موعد تنصيب'
    when 'installation_started' then 'بدء التنصيب'
    when 'installation_completed' then 'إنجاز التنصيب ورفع التقرير'
    when 'installation_closed' then 'إغلاق ملف التنصيب من الإدارة'
   end) order by at desc,event_key desc) from recent),'[]'::jsonb)
 ) from events
$$;
revoke all on function solar_private.user_activity_operations(uuid,date,date) from public,anon,authenticated;
