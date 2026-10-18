-- Local-only warehouse fixture. No external push wake-up or worker execution.
create table public.solar_push_subscriptions(endpoint text primary key,user_id uuid not null references public.profiles(id),p256dh text not null,auth_key text not null,updated_at timestamptz default now());
alter table public.solar_push_subscriptions enable row level security;
grant select,delete on public.solar_push_subscriptions to authenticated;
create policy push_own_read on public.solar_push_subscriptions for select to authenticated using(user_id=auth.uid());
create table solar_private.push_deliveries(id uuid primary key default gen_random_uuid(),notification_id uuid not null references public.solar_notifications(id) on delete cascade,endpoint text not null references public.solar_push_subscriptions(endpoint) on delete cascade,status text not null default 'pending',attempts integer not null default 0,available_at timestamptz not null default now(),lease_until timestamptz,sent_at timestamptz,last_status integer,unique(notification_id,endpoint));
alter table solar_private.push_deliveries enable row level security;
create table solar_private.warehouse_audit(id bigint generated always as identity primary key,invoice_id bigint not null,actor_id uuid not null,action text not null,before_items jsonb not null,after_items jsonb not null,created_at timestamptz default now());
alter table solar_private.warehouse_audit enable row level security;
alter table public.solar_notifications drop constraint solar_notifications_event_check;
alter table public.solar_notifications add constraint solar_notifications_event_check check(event in('assigned','completed','test','cash_received','cash_accepted','cash_rejected','cash_cancelled','invoice_deleted','warehouse_new','warehouse_reopened','warehouse_ready','warehouse_edited','profit_requested','profit_decided'));
create or replace function solar_private.wake_push() returns void language sql as $$select$$;
revoke all on function solar_private.wake_push() from public,anon,authenticated;
CREATE OR REPLACE FUNCTION solar_private.warehouse_items_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 update public.transactions set warehouse_status='pending',warehouse_prepared_at=null,warehouse_prepared_by=null,warehouse_revision=warehouse_revision+1
 where id=coalesce(new.transaction_id,old.transaction_id) and kind in ('sale','system') and warehouse_status='ready';
 return null;
end $function$
;

CREATE OR REPLACE FUNCTION solar_private.warehouse_action(invoice_id bigint, expected_token text, action text, lines jsonb DEFAULT NULL::jsonb, note text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j public.transactions; before_items jsonb; after_items jsonb; entry jsonb; oldline public.transaction_items; prod public.products;
 newqty numeric; oldqty numeric; newtotal numeric; newcost numeric; wanted jsonb; id_value bigint;
begin
 if auth.uid() is null or not solar_private.warehouse_allowed() then raise exception 'Not permitted' using errcode='42501';end if;
 if action not in ('save','ready','reopen') then raise exception 'Invalid action';end if;
 select * into j from public.transactions where id=invoice_id and kind in ('sale','system') for update;
 if j.id is null then raise exception 'الفاتورة غير متاحة' using errcode='42501';end if;
 if solar_private.warehouse_token(j.id) is distinct from expected_token then raise exception 'تغيّرت الفاتورة، حدّث الصفحة وحاول مجدداً' using errcode='40001';end if;
 if length(coalesce(note,''))>2000 then raise exception 'الملاحظات طويلة';end if;
 select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]'::jsonb) into before_items from public.transaction_items i where transaction_id=j.id;
 if action='save' then
  if j.installation_status in ('in_progress','completed','closed') then raise exception 'بدأ تنفيذ المنظومة؛ راجع الإداري قبل تعديل موادها';end if;
  if jsonb_typeof(lines) is distinct from 'array' or jsonb_array_length(lines)=0 or jsonb_array_length(lines)>300 then raise exception 'أضف مادة واحدة على الأقل';end if;
  if exists(select 1 from jsonb_array_elements(lines) e where jsonb_typeof(e->'qty') is distinct from 'number' or (e->>'qty')::numeric<=0 or (e->>'qty')::numeric>1000000 or (e->>'qty')::numeric<>round((e->>'qty')::numeric,3)) then raise exception 'الكميات غير صحيحة';end if;
  if (select count(*) from jsonb_array_elements(lines) e where e->>'lineId' is not null)<>(select count(distinct e->>'lineId') from jsonb_array_elements(lines) e where e->>'lineId' is not null) then raise exception 'مادة مكررة';end if;
  -- Lock the union of old/new products in a stable order.
  perform 1 from public.products p where p.id in (select i.product_id from public.transaction_items i where i.transaction_id=j.id union select (e->>'productId')::bigint from jsonb_array_elements(lines) e) order by p.id for update;
  for entry in select value from jsonb_array_elements(lines) loop
   if entry->>'lineId' is not null then
    select * into oldline from public.transaction_items where id=(entry->>'lineId')::bigint and transaction_id=j.id;
    if oldline.id is null or oldline.product_id is distinct from (entry->>'productId')::bigint then raise exception 'مادة لا تخص هذه الفاتورة';end if;
   else
    if j.kind<>'system' then raise exception 'إضافة مادة جملة جديدة تحتاج الإداري لتحديد سعر البيع';end if;
    if not exists(select 1 from public.products where id=(entry->>'productId')::bigint) then raise exception 'المادة غير موجودة';end if;
   end if;
  end loop;
  for id_value in select product_id from public.transaction_items where transaction_id=j.id union select (e->>'productId')::bigint from jsonb_array_elements(lines) e loop
   select coalesce(sum(qty),0) into oldqty from public.transaction_items where transaction_id=j.id and product_id=id_value;
   select coalesce(sum((e->>'qty')::numeric),0) into newqty from jsonb_array_elements(lines) e where (e->>'productId')::bigint=id_value;
   update public.products set qty=qty+oldqty-newqty,updated_at=now() where id=id_value and qty+oldqty-newqty>=0;
   if not found then raise exception 'الكمية المتوفرة لا تكفي أو المادة غير متاحة';end if;
  end loop;
  delete from public.transaction_items i where transaction_id=j.id and not exists(select 1 from jsonb_array_elements(lines) e where (e->>'lineId')::bigint=i.id);
  for entry in select value from jsonb_array_elements(lines) loop
   if entry->>'lineId' is not null then update public.transaction_items set qty=(entry->>'qty')::numeric where id=(entry->>'lineId')::bigint and transaction_id=j.id;
   else
    select * into prod from public.products where id=(entry->>'productId')::bigint;
    insert into public.transaction_items(transaction_id,product_id,product_name,brand_name,category,qty,price,cost)
    values(j.id,prod.id,prod.name,(select name from public.brands where id=prod.brand_id),prod.category,(entry->>'qty')::numeric,0,prod.cost);
   end if;
  end loop;
  select coalesce(sum(qty*price),0),coalesce(sum(qty*cost),0) into newtotal,newcost from public.transaction_items where transaction_id=j.id;
  update public.transactions set subtotal=case when kind='sale' then newtotal else subtotal end,total=case when kind='sale' then newtotal+coalesce(expenses,0) else total end,
  cost=newcost,profit=case when kind='sale' then newtotal-newcost-coalesce(installation_expenses,0) else total-newcost-coalesce(expenses,0)-coalesce(installation_expenses,0) end,
  warehouse_status='pending',warehouse_prepared_at=null,warehouse_prepared_by=null,warehouse_note=coalesce(note,''),warehouse_revision=warehouse_revision+1 where id=j.id;
  perform solar_private.warehouse_notice(j.created_by,j.id,'warehouse_edited');
 elsif action='ready' then
  if j.warehouse_status<>'pending' then raise exception 'الفاتورة مجهزة مسبقاً';end if;
  if not exists(select 1 from public.transaction_items where transaction_id=j.id) then raise exception 'الفاتورة بدون مواد';end if;
  update public.transactions set warehouse_status='ready',warehouse_prepared_at=now(),warehouse_prepared_by=auth.uid(),warehouse_note=coalesce(note,''),warehouse_revision=warehouse_revision+1 where id=j.id;
 else
  if j.installation_status in ('in_progress','completed','closed') then raise exception 'بدأ تنفيذ المنظومة؛ لا يمكن إعادة التجهيز الآن';end if;
  if j.warehouse_status<>'ready' then raise exception 'الفاتورة بانتظار التجهيز أصلاً';end if;
  update public.transactions set warehouse_status='pending',warehouse_prepared_at=null,warehouse_prepared_by=null,warehouse_revision=warehouse_revision+1 where id=j.id;
 end if;
 select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]'::jsonb) into after_items from public.transaction_items i where transaction_id=j.id;
 insert into solar_private.warehouse_audit(invoice_id,actor_id,action,before_items,after_items) values(j.id,auth.uid(),action,before_items,after_items);
end $function$
;

CREATE OR REPLACE FUNCTION solar_private.warehouse_notify()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u record; event_name text;
begin
 if new.kind not in ('sale','system') then return new;end if;
 if tg_op='INSERT' then event_name:='warehouse_new';
 elsif old.warehouse_status='ready' and new.warehouse_status='pending' then event_name:='warehouse_reopened';
 elsif old.warehouse_status='pending' and new.warehouse_status='ready' then
  perform solar_private.warehouse_notice(new.created_by,new.id,'warehouse_ready');return new;
 else return new;end if;
 for u in select id from public.profiles where active and user_type<>'installer' and (user_type='warehouse' or permissions->>'warehouse'='true') loop
  perform solar_private.warehouse_notice(u.id,new.id,event_name);
 end loop;
 return new;
end $function$
;

CREATE OR REPLACE FUNCTION solar_private.normalize_warehouse_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if new.user_type='warehouse' then new.is_admin:=false; new.permissions:='{"warehouse":true,"stock":true,"stockMovement":true}'::jsonb; end if;
 return new;
end $function$
;

CREATE OR REPLACE FUNCTION solar_private.warehouse_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if current_user in ('authenticated','anon') then
  if tg_op='INSERT' and (new.warehouse_status<>'pending' or new.warehouse_revision<>0 or new.warehouse_prepared_at is not null or new.warehouse_prepared_by is not null or new.warehouse_note<>'') then raise exception 'Use warehouse workflow' using errcode='42501';end if;
  if tg_op='UPDATE' and (new.warehouse_status,new.warehouse_revision,new.warehouse_prepared_at,new.warehouse_prepared_by,new.warehouse_note) is distinct from (old.warehouse_status,old.warehouse_revision,old.warehouse_prepared_at,old.warehouse_prepared_by,old.warehouse_note) then raise exception 'Use warehouse workflow' using errcode='42501';end if;
 end if;
 return new;
end $function$
;

CREATE OR REPLACE FUNCTION solar_private.warehouse_allowed()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.user_type<>'installer'
 and (p.user_type='warehouse' or p.is_admin or p.permissions->>'warehouse'='true'))
$function$
;

CREATE OR REPLACE FUNCTION solar_private.warehouse_token(invoice_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select md5(to_jsonb(t)::text||coalesce((select jsonb_agg(to_jsonb(i) order by i.id)::text from public.transaction_items i where i.transaction_id=t.id),'[]')) from public.transactions t where t.id=invoice_id
$function$
;

CREATE OR REPLACE FUNCTION solar_private.warehouse_notice(recipient uuid, invoice_id bigint, event_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare nid uuid; heading text; detail text;
begin
 if not exists(select 1 from public.profiles where id=recipient and active) then return;end if;
 heading:=case event_name when 'warehouse_ready' then 'تم تجهيز الفاتورة' when 'warehouse_edited' then 'تعديل مواد الفاتورة من المخزن' when 'warehouse_reopened' then 'الفاتورة تحتاج تجهيزاً من جديد' else 'فاتورة جديدة للتجهيز' end;
 select 'وصل #'||t.receipt_no||' • '||coalesce(t.party_name,'زبون نقدي') into detail from public.transactions t where id=invoice_id;
 insert into public.solar_notifications(user_id,job_id,event,title,body) values(recipient,invoice_id,event_name,heading,detail) returning id into nid;
 insert into solar_private.push_deliveries(notification_id,endpoint) select nid,endpoint from public.solar_push_subscriptions where user_id=recipient;
 perform solar_private.wake_push();
end $function$
;

CREATE OR REPLACE FUNCTION solar_private.stock_quantities()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.user_type<>'installer' and (p.user_type='warehouse' or p.is_admin or p.permissions->>'stock'='true' or p.permissions->>'stockMovement'='true' or p.permissions->>'warehouse'='true')) then raise exception 'Not permitted' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name,'brand',b.name,'category',p.category,'qty',p.qty) order by p.name,p.id),'[]'::jsonb) from public.products p left join public.brands b on b.id=p.brand_id);
end $function$
;

CREATE OR REPLACE FUNCTION solar_private.installation_jobs()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles; result jsonb;
begin
 if solar_private.role_name()='warehouse' then raise exception 'Not permitted' using errcode='42501';end if;
 select * into p from public.profiles where id=auth.uid() and active=true;
 if p.id is null then raise exception 'Active login required' using errcode='42501'; end if;
 if p.user_type<>'installer' and not p.is_admin and not (coalesce(p.permissions->>'installations','false')='true' or coalesce(p.permissions->>'installationsAll','false')='true' or coalesce(p.permissions->>'system','false')='true') then return '[]'::jsonb; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
 'id',t.id,'receiptNo',t.receipt_no,'kind','system','party',t.party_name,'installerId',t.installer_id,
 'installerName',(select coalesce(x.display_name,x.username) from public.profiles x where x.id=t.installer_id),
 'installDate',t.install_date,'installTime',t.install_time,'customerPhone',t.customer_phone,'customerAddress',t.customer_address,
 'installationStatus',t.installation_status,'installationStartedAt',t.installation_started_at,
 'installationCompletedAt',t.installation_completed_at,'installationClosedAt',t.installation_closed_at,
 'installationRevision',t.installation_revision,'installationReport',t.installation_report,
 'canManage',solar_private.can_close_installation(t.created_by),
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.product_name,'brand',i.brand_name,'qty',i.qty) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]'::jsonb)
 ) || case when solar_private.can_close_installation(t.created_by) then
 jsonb_build_object('cost',t.cost,'expenses',t.expenses,'total',t.total,'installationExpenses',t.installation_expenses,'installationExpenseNotes',t.installation_expense_notes)
 else '{}'::jsonb end order by t.install_date nulls last,t.install_time nulls last,t.id),'[]'::jsonb) into result
 from public.transactions t where t.kind='system' and t.installation_status<>'none' and
 (case when p.user_type='installer' then t.installer_id=p.id else p.is_admin or coalesce(p.permissions->>'installationsAll','false')='true' or t.created_by=p.id end);
 return result;
end $function$
;

CREATE OR REPLACE FUNCTION solar_private.role_name()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select case when p.user_type='installer' then 'installer' when p.user_type='warehouse' then 'warehouse' when p.is_admin then 'admin' else 'staff' end
 from public.profiles p where p.id=auth.uid() and p.active
$function$
;

CREATE OR REPLACE FUNCTION solar_private.guard_installation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if current_user in ('authenticated','anon') then
  if tg_op='INSERT' and new.kind='system' then
   if new.installation_status is distinct from 'pending' or new.installation_revision<>0 or new.installation_report<>'{}'::jsonb or coalesce(new.installation_expenses,0)<>0 or new.installation_completed_at is not null or new.installation_closed_at is not null or new.installation_started_at is not null then raise exception 'Invalid initial installation state'; end if;
  elsif tg_op='UPDATE' and (old.kind='system' or new.kind='system') then
   if (new.kind,new.installation_status,new.installation_revision,new.installation_report,new.installation_expenses,new.installation_expense_notes,new.installation_started_at,new.installation_completed_at,new.installation_closed_at) is distinct from (old.kind,old.installation_status,old.installation_revision,old.installation_report,old.installation_expenses,old.installation_expense_notes,old.installation_started_at,old.installation_completed_at,old.installation_closed_at) then raise exception 'Use installation workflow'; end if;
  end if;
 end if;
 return new;
end $function$
;

CREATE OR REPLACE FUNCTION solar_private.can_close_installation(owner_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.active
 and p.user_type<>'installer' and (p.is_admin or p.permissions->>'installationsAll'='true'
 or (p.permissions->>'installations'='true' and owner_id=p.id)))
$function$
;

CREATE OR REPLACE FUNCTION solar_private.installation_action(job_id bigint, expected_revision bigint, action text, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles; j public.transactions; amount numeric; e jsonb; report jsonb;
begin
 if solar_private.role_name()='warehouse' then raise exception 'Not permitted' using errcode='42501';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into p from public.profiles where id=auth.uid() and active=true;
 if p.id is null then raise exception 'Active login required' using errcode='42501'; end if;
 select * into j from public.transactions where id=job_id and kind='system' for update;
 if j.id is null then raise exception 'Job unavailable' using errcode='42501'; end if;
 if p.user_type='installer' then
  if j.installer_id is distinct from p.id or action not in ('start','complete') then raise exception 'Not permitted' using errcode='42501'; end if;
 else
  if not (solar_private.can_close_installation(j.created_by)) or action not in ('close','reopen') then raise exception 'Not permitted' using errcode='42501'; end if;
 end if;
 if expected_revision is distinct from j.installation_revision then raise exception 'Job changed; refresh and retry' using errcode='40001'; end if;
 if action='start' then
  if j.installation_status<>'pending' then raise exception 'Invalid stage'; end if;
  update public.transactions set installation_status='in_progress',installation_started_at=now(),installation_revision=installation_revision+1 where id=j.id;
 elsif action='complete' then
  if j.installation_status<>'in_progress' then raise exception 'Start the installation first'; end if;
  if jsonb_typeof(payload) is distinct from 'object' or length(trim(coalesce(payload->>'notes','')))=0 or length(payload->>'notes')>4000 then raise exception 'Completion report required'; end if;
  if payload->'checks'->>'materials' is distinct from 'true' or payload->'checks'->>'tested' is distinct from 'true' or payload->'checks'->>'handover' is distinct from 'true' then raise exception 'Complete the checklist'; end if;
  if jsonb_typeof(payload->'expenses') is distinct from 'array' then raise exception 'Invalid expenses'; end if;
  if jsonb_array_length(payload->'expenses')>50 then raise exception 'Too many expense lines'; end if;
  amount:=0;
  for e in select value from jsonb_array_elements(payload->'expenses') loop
   if jsonb_typeof(e->'amount') is distinct from 'number' or (e->>'amount')::numeric<=0 or (e->>'amount')::numeric>1000000000 or length(trim(coalesce(e->>'description','')))=0 or length(e->>'description')>500 then raise exception 'Invalid expense line'; end if;
   amount:=amount+(e->>'amount')::numeric;
  end loop;
  report:=jsonb_build_object('notes',trim(payload->>'notes'),'checks',payload->'checks','expenses',payload->'expenses','expenseTotal',amount,'submittedAt',now(),'submittedBy',p.id);
  update public.transactions set installation_status='completed',installation_completed_at=now(),installation_report=report,installation_revision=installation_revision+1 where id=j.id;
 elsif action='close' then
  if j.installation_status<>'completed' then raise exception 'Engineer report required before closing'; end if;
  if jsonb_typeof(payload->'amount') is distinct from 'number' then raise exception 'Invalid approved expenses'; end if;
  amount:=(payload->>'amount')::numeric;
  if amount<0 or amount>1000000000 then raise exception 'Invalid approved expenses'; end if;
  if length(coalesce(payload->>'notes',''))>4000 then raise exception 'Notes too long'; end if;
  perform solar_private.post_installation_cash(j.id,amount,p.id);
  update public.transactions set installation_status='closed',installation_closed_at=now(),installation_expenses=amount,installation_expense_notes=payload->>'notes',profit=coalesce(total,0)-coalesce(cost,0)-coalesce(expenses,0)-amount,installation_revision=installation_revision+1 where id=j.id;
 elsif action='reopen' then
  if j.installation_status<>'closed' then raise exception 'Only closed files can reopen'; end if;
  update public.transactions set installation_status='completed',installation_closed_at=null,installation_revision=installation_revision+1 where id=j.id;
 else raise exception 'Invalid action'; end if;
end $function$
;

CREATE OR REPLACE FUNCTION solar_private.post_installation_cash(job_id bigint, approved numeric, actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare paid numeric; difference numeric; refund numeric; allocation record;
begin
 if actor is distinct from auth.uid() then raise exception 'Not permitted' using errcode='42501';end if;
 select -coalesce(sum(delta),0) into paid from public.solar_cash_entries e where e.job_id=post_installation_cash.job_id;
 difference:=approved-paid;
 if difference>0 then
  if solar_private.cash_balance(actor)<difference then raise exception 'Insufficient cash' using errcode='P0002';end if;
  insert into public.solar_cash_entries(owner_id,delta,entry_type,job_id,actor_id,notes) values(actor,-difference,'installation_payout',job_id,actor,'مصاريف تنصيب ملف #'||job_id::text);
 elsif difference<0 then
  refund:=-difference;
  for allocation in select owner_id,-sum(delta) as amount,max(created_at) as last_at from public.solar_cash_entries e where e.job_id=post_installation_cash.job_id group by owner_id having sum(delta)<0 order by max(created_at) desc,owner_id loop
   insert into public.solar_cash_entries(owner_id,delta,entry_type,job_id,actor_id,notes) values(allocation.owner_id,least(refund,allocation.amount),'installation_refund',job_id,actor,'استرجاع فرق مصاريف ملف #'||job_id::text);
   refund:=refund-least(refund,allocation.amount);exit when refund=0;
  end loop;
 end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.solar_warehouse_action(invoice_id bigint, expected_token text, action text, lines jsonb DEFAULT NULL::jsonb, note text DEFAULT ''::text)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.warehouse_action(invoice_id,expected_token,action,lines,note)$function$
;

CREATE OR REPLACE FUNCTION public.solar_stock_quantities()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.stock_quantities()$function$
;

CREATE OR REPLACE FUNCTION public.solar_installation_jobs()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select solar_private.installation_jobs() $function$
;

CREATE OR REPLACE FUNCTION public.solar_installation_action(job_id bigint, expected_revision bigint, action text, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select solar_private.installation_action(job_id,expected_revision,action,payload) $function$
;
CREATE OR REPLACE FUNCTION public.solar_push_claim()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 with eligible as (
 select d.id from solar_private.push_deliveries d join public.solar_notifications n on n.id=d.notification_id
 join public.solar_push_subscriptions s on s.endpoint=d.endpoint and s.user_id=n.user_id
 join public.profiles p on p.id=n.user_id and p.active
 where d.attempts<5 and n.created_at>now()-interval '1 day' and ((d.status='pending' and d.available_at<=now()) or (d.status='sending' and d.lease_until<now()))
 order by d.available_at for update of d skip locked limit 20
 ), claimed as (
 update solar_private.push_deliveries d set status='sending',attempts=attempts+1,lease_until=now()+interval '2 minutes'
 from eligible e where d.id=e.id returning d.*
 )
 select coalesce(jsonb_agg(jsonb_build_object('deliveryId',d.id,'attempt',d.attempts,'endpoint',s.endpoint,'keys',jsonb_build_object('p256dh',s.p256dh,'auth',s.auth_key),'notification',jsonb_build_object('id',n.id,'userId',n.user_id,'jobId',n.job_id,'event',n.event,'transferId',n.transfer_id,'title',n.title,'body',n.body))),'[]'::jsonb)
 into result from claimed d join public.solar_notifications n on n.id=d.notification_id join public.solar_push_subscriptions s on s.endpoint=d.endpoint and s.user_id=n.user_id;
 return result;
end $function$
;
revoke all on function public.solar_push_claim() from public,anon,authenticated;
drop trigger if exists solar_warehouse_profile on public.profiles;
create trigger solar_warehouse_profile before insert or update on public.profiles for each row execute function solar_private.normalize_warehouse_profile();
drop trigger if exists solar_warehouse_notify on public.transactions;
create trigger solar_warehouse_notify after insert or update on public.transactions for each row execute function solar_private.warehouse_notify();
drop trigger if exists solar_warehouse_items_changed on public.transaction_items;
create trigger solar_warehouse_items_changed after insert or update or delete on public.transaction_items for each row execute function solar_private.warehouse_items_changed();
grant execute on function public.solar_warehouse_action(bigint,text,text,jsonb,text),public.solar_stock_quantities(),public.solar_installation_jobs(),public.solar_installation_action(bigint,bigint,text,jsonb) to authenticated;


create or replace function public.solar_warehouse_orders(search_text text default '',state text default 'pending',page_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select solar_private.warehouse_orders(search_text,state,page_offset)$$;
revoke all on function public.solar_warehouse_orders(text,text,integer) from public,anon;
grant execute on function public.solar_warehouse_orders(text,text,integer) to authenticated;
