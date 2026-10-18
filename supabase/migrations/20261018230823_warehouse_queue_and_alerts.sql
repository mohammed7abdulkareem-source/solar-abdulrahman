-- Preserve preparation history; expose separate queue totals without financial data.
create or replace function solar_private.warehouse_orders(search_text text default '',state text default 'pending',page_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;q text:=coalesce(search_text,'');stage text:=coalesce(state,'pending');begin
 if auth.uid() is null or not solar_private.warehouse_allowed() then raise exception 'Not permitted' using errcode='42501';end if;
 if stage not in('','pending','ready') or length(q)>200 then raise exception 'تصفية التجهيز غير صحيحة';end if;
 with matched as materialized(
  select t.* from public.transactions t where t.kind in('sale','system') and(q='' or q='@id:'||t.id::text or strpos(solar_private.customer_name_key(coalesce(t.party_name,'')||' '||t.receipt_no::text),solar_private.customer_name_key(q))>0)
 ), filtered as(select * from matched where stage='' or warehouse_status=stage),
 paged as(select * from filtered order by created_at desc,id desc limit 30 offset greatest(0,least(coalesce(page_offset,0),1000000)))
 select jsonb_build_object('count',(select count(*) from filtered),'statusCounts',jsonb_build_object('pending',(select count(*) from matched where warehouse_status='pending'),'ready',(select count(*) from matched where warehouse_status='ready'),'all',(select count(*) from matched)),
 'rows',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'kind',t.kind,'party',t.party_name,'phone',t.customer_phone,'address',t.customer_address,'date',t.created_at,'status',t.warehouse_status,
 'preparedAt',t.warehouse_prepared_at,'preparedBy',(select coalesce(display_name,username) from public.profiles where id=t.warehouse_prepared_by),'note',t.warehouse_note,'token',solar_private.warehouse_token(t.id),'canEdit',t.installation_status not in('in_progress','completed','closed'),
 'items',coalesce((select jsonb_agg(jsonb_build_object('lineId',i.id,'productId',i.product_id,'name',i.product_name,'brand',i.brand_name,'category',i.category,'qty',i.qty) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]')) order by t.created_at desc,t.id desc) from paged t),'[]')) into result;
 return result;
end $$;
-- Cards receive preparation state without querying other users' prices or balances.
create function solar_private.warehouse_statuses(invoice_ids bigint[]) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;result jsonb;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type='installer' then raise exception 'Not permitted' using errcode='42501';end if;
 if coalesce(cardinality(invoice_ids),0)>500 then raise exception 'اطلب حالة 500 فاتورة كحد أقصى';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'status',t.warehouse_status,'preparedAt',t.warehouse_prepared_at,'revision',t.warehouse_revision)),'[]') into result from public.transactions t
 where t.id=any(invoice_ids) and t.kind in('sale','system') and(p.is_admin or solar_private.warehouse_allowed() or coalesce(t.cashbox_user_id,t.created_by)=p.id or(t.kind='system' and p.permissions->>'installationsAll'='true'));
 return result;
end $$;
create function public.solar_warehouse_statuses(invoice_ids bigint[]) returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.warehouse_statuses(invoice_ids)$$;
revoke all on function solar_private.warehouse_statuses(bigint[]),public.solar_warehouse_statuses(bigint[]) from public,anon;
grant execute on function solar_private.warehouse_statuses(bigint[]),public.solar_warehouse_statuses(bigint[]) to authenticated;
-- Use the same lock order as invoice, cash and stock operations.
do $$declare def text;needle text;begin
 select pg_get_functiondef('solar_private.warehouse_action(bigint,text,text,jsonb,text)'::regprocedure) into def;
 needle:='select * into j from public.transactions where id=invoice_id';
 if strpos(def,needle)=0 then raise exception 'Review warehouse action locking';end if;
 def:=replace(def,needle,'perform pg_advisory_xact_lock(7311,1); '||needle);
 execute def;
end $$;
notify pgrst,'reload schema';
-- New system invoices carry no provisional expenses; the office approves the
-- complete amount only after stock is prepared. Historical amounts are retained.
do $$declare def text;needle text;begin
 select pg_get_functiondef('solar_private.invoice_save_v333(uuid,jsonb)'::regprocedure) into def;
 needle:='expenses:=coalesce((payload->>''expenses'')::numeric,0);';
 if strpos(def,needle)=0 then raise exception 'Review system expense integration';end if;
 def:=replace(def,needle,needle||' if kind=''system'' and nullif(payload->>''invoiceId'','''') is null and expenses<>0 then raise exception ''مصاريف التنصيب تعتمد كاملة بعد التجهيز عند إغلاق الملف'';end if;');execute def;
 select pg_get_functiondef('solar_private.installation_jobs()'::regprocedure) into def;
 needle:='''installationRevision'',t.installation_revision';
 if strpos(def,needle)=0 then raise exception 'Review installation job response';end if;
 def:=replace(def,needle,'''warehouseStatus'',t.warehouse_status,''warehouseRevision'',t.warehouse_revision,'||needle);execute def;
 select pg_get_functiondef('solar_private.installation_action(bigint,bigint,text,jsonb)'::regprocedure) into def;
 needle:='if action=''start'' then';
 if strpos(def,needle)=0 then raise exception 'Review installation stages';end if;
 def:=replace(def,needle,'if action in(''start'',''complete'',''close'') and j.warehouse_status<>''ready'' then raise exception ''يجب تجهيز مواد المنظومة قبل اعتماد المصاريف وإغلاق الملف أو بدء التنصيب'';end if; '||needle);
 needle:='if j.installation_status<>''completed'' then raise exception ''Engineer report required before closing''; end if;';
 if strpos(def,needle)=0 then raise exception 'Review office closing condition';end if;
 def:=replace(def,needle,'if j.installation_status not in(''pending'',''in_progress'',''completed'') then raise exception ''الملف مغلق مسبقاً؛ افتحه للمراجعة قبل تعديل المصاريف'';end if;');
 needle:='if amount<0 or amount>1000000000 then';
 def:=replace(def,needle,'if amount::text in(''NaN'',''Infinity'',''-Infinity'') or round(amount,2)<>amount or amount<0 or amount>1000000000 then');
 execute def;
end $$;
-- Warehouse notifications carry a direct return-to-office message for systems.
create or replace function solar_private.warehouse_notice(recipient uuid,invoice_id bigint,event_name text) returns void
language plpgsql security definer set search_path='' as $$
declare nid uuid;heading text;detail text;invoice public.transactions;begin
 if not exists(select 1 from public.profiles where id=recipient and active) then return;end if;
 select * into invoice from public.transactions where id=invoice_id;
 if invoice.id is null then return;end if;
 heading:=case event_name when 'warehouse_ready' then case when invoice.kind='system' then 'المنظومة جاهزة لاعتماد المصاريف والغلق' else 'تم تجهيز الفاتورة' end when 'warehouse_edited' then 'تعديل مواد الفاتورة من المخزن' when 'warehouse_reopened' then 'الفاتورة تحتاج تجهيزاً من جديد' when 'installation_closed' then 'تم اعتماد المصاريف وإغلاق ملف المنظومة' else 'فاتورة جديدة بانتظار التجهيز' end;
 detail:='وصل #'||invoice.receipt_no||' • '||coalesce(invoice.party_name,'زبون نقدي');
 insert into public.solar_notifications(user_id,job_id,event,title,body) values(recipient,invoice_id,event_name,heading,detail) returning id into nid;
 insert into solar_private.push_deliveries(notification_id,endpoint) select nid,endpoint from public.solar_push_subscriptions where user_id=recipient;
 perform solar_private.wake_push();
end $$;
create or replace function solar_private.warehouse_notify() returns trigger language plpgsql security definer set search_path='' as $$
declare u record;event_name text;begin
 if new.kind not in('sale','system') then return new;end if;
 if tg_op='INSERT' then event_name:='warehouse_new';
 elsif old.warehouse_status='ready' and new.warehouse_status='pending' then event_name:='warehouse_reopened';
 elsif old.warehouse_status='pending' and new.warehouse_status='ready' then
  for u in select id from public.profiles where active and user_type not in('installer','warehouse') and(id=new.created_by or(new.kind='system' and is_admin)) loop
   perform solar_private.warehouse_notice(u.id,new.id,'warehouse_ready');
  end loop;return new;
 elsif new.kind='system' and old.installation_status<>'closed' and new.installation_status='closed' then
  perform solar_private.warehouse_notice(new.created_by,new.id,'installation_closed');return new;
 else return new;end if;
 for u in select id from public.profiles where active and user_type<>'installer' and(user_type='warehouse' or permissions->>'warehouse'='true') loop
  perform solar_private.warehouse_notice(u.id,new.id,event_name);
 end loop;return new;
end $$;
-- Include the invoice kind so a background push opens the proper office screen.
do $$declare def text;needle text;old_check text;begin
 select pg_get_expr(conbin,conrelid) into old_check from pg_constraint where conrelid='public.solar_notifications'::regclass and conname='solar_notifications_event_check';
 if old_check is null then raise exception 'Notification constraint missing';end if;
 alter table public.solar_notifications drop constraint solar_notifications_event_check;
 execute 'alter table public.solar_notifications add constraint solar_notifications_event_check check(('||old_check||') or event=''installation_closed'')';
 select pg_get_functiondef('public.solar_push_claim()'::regprocedure) into def;
 needle:='''event'',n.event';
 if strpos(def,needle)=0 then raise exception 'Review push event response';end if;
 def:=replace(def,needle,needle||',''invoiceKind'',(select t.kind from public.transactions t where t.id=n.job_id)');execute def;
end $$;
