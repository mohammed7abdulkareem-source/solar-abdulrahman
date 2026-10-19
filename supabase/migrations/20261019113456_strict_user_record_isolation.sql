-- Staff capabilities never grant another user's records. Dedicated operational
-- roles retain redacted warehouse/assigned engineer views; admins retain oversight.
create function solar_private.can_access_invoice(owner_id uuid,warehouse_copy boolean default false) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and
 ((p.is_admin and p.user_type not in('installer','warehouse')) or
 (warehouse_copy and p.user_type='warehouse') or
 (p.user_type not in('installer','warehouse') and p.id=owner_id)))
$$;
revoke all on function solar_private.can_access_invoice(uuid,boolean) from public,anon;
grant execute on function solar_private.can_access_invoice(uuid,boolean) to authenticated;

create function solar_private.enforce_own_user_scope() returns trigger language plpgsql set search_path='' as $$
begin
 if not new.is_admin and new.user_type not in('installer','warehouse') then
  new.permissions:=(coalesce(new.permissions,'{}'::jsonb)-'all')||jsonb_build_object(
   'ownCustomers',true,'ownSales',true,'ownPayments',true,'ownProfit',true,
   'installations',coalesce(new.permissions->>'installations','false')='true' or coalesce(new.permissions->>'installationsAll','false')='true',
   'salesDeleteOwn',coalesce(new.permissions->>'salesDeleteOwn','false')='true' or coalesce(new.permissions->>'salesDeleteAll','false')='true',
   'installationsAll',false,'salesDeleteAll',false);
 end if;
 return new;
end $$;
revoke all on function solar_private.enforce_own_user_scope() from public,anon,authenticated;
create trigger solar_zz_own_user_scope before insert or update on public.profiles for each row execute function solar_private.enforce_own_user_scope();
update public.profiles set permissions=permissions where not is_admin and user_type not in('installer','warehouse');

-- Cash assigned by the administrator remains part of its recipient's box.
-- An invoice belonging to another creator cannot be read or changed through it.
create policy solar_invoice_creator_scope on public.transactions as restrictive for all to authenticated
using((select solar_private.role_name())='admin' or kind not in('sale','system','purchase') or created_by=(select auth.uid()))
with check((select solar_private.role_name())='admin' or kind not in('sale','system','purchase') or created_by=(select auth.uid()));
create index if not exists solar_transactions_creator_history on public.transactions(created_by,kind,created_at desc,id desc);

create or replace function solar_private.can_close_installation(owner_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.user_type not in('installer','warehouse')
 and(p.is_admin or(p.id=owner_id and p.permissions->>'installations'='true')))
$$;
create or replace function solar_private.can_delete_sale(owner_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.user_type not in('installer','warehouse')
 and(p.is_admin or(p.id=owner_id and p.permissions->>'salesDeleteOwn'='true')))
$$;


CREATE OR REPLACE FUNCTION solar_private.sales_history(search_text text DEFAULT ''::text, sale_kind text DEFAULT ''::text, date_from date DEFAULT NULL::date, date_to date DEFAULT NULL::date, job_status text DEFAULT ''::text, page_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles; result jsonb;
begin
 if solar_private.role_name()='warehouse' then raise exception 'Not permitted' using errcode='42501';end if;
 select * into p from public.profiles where id=auth.uid() and active=true;
 if p.id is null or p.user_type='installer' then raise exception 'Not permitted' using errcode='42501'; end if;
 with permitted as (
 select t.* from public.transactions t where t.kind in ('sale','system')
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
 select jsonb_build_object('count',(select count(*) from permitted),'rows',coalesce((
 select jsonb_agg(to_jsonb(t)||jsonb_build_object(
 'canDelete',solar_private.can_delete_sale(t.created_by),
 'creatorName',(select coalesce(x.display_name,x.username) from public.profiles x where x.id=t.created_by),
 'installerName',(select coalesce(x.display_name,x.username) from public.profiles x where x.id=t.installer_id),
 'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]'::jsonb)
 ) order by t.created_at desc,t.id desc) from page_rows t),'[]'::jsonb)) into result;
 return result;
end $function$;

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
 'warehouseStatus',t.warehouse_status,'warehouseRevision',t.warehouse_revision,'installationRevision',t.installation_revision,'installationReport',t.installation_report,
 'canManage',solar_private.can_close_installation(t.created_by),
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.product_name,'brand',i.brand_name,'qty',i.qty) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]'::jsonb)
 ) || case when solar_private.can_close_installation(t.created_by) then
 jsonb_build_object('cost',t.cost,'expenses',t.expenses,'total',t.total,'installationExpenses',t.installation_expenses,'installationExpenseNotes',t.installation_expense_notes)
 else '{}'::jsonb end order by t.install_date nulls last,t.install_time nulls last,t.id),'[]'::jsonb) into result
 from public.transactions t where t.kind='system' and t.installation_status<>'none' and
 (case when p.user_type='installer' then t.installer_id=p.id else p.is_admin or t.created_by=p.id end);
 return result;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.warehouse_orders(search_text text DEFAULT ''::text, state text DEFAULT 'pending'::text, page_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;q text:=coalesce(search_text,'');stage text:=coalesce(state,'pending');begin
 if auth.uid() is null or not solar_private.warehouse_allowed() then raise exception 'Not permitted' using errcode='42501';end if;
 if stage not in('','pending','ready') or length(q)>200 then raise exception 'تصفية التجهيز غير صحيحة';end if;
 with matched as materialized(
  select t.* from public.transactions t where t.kind in('sale','system') and((select solar_private.role_name()) in('admin','warehouse') or t.created_by=(select auth.uid())) and(q='' or q='@id:'||t.id::text or strpos(solar_private.customer_name_key(coalesce(t.party_name,'')||' '||t.receipt_no::text),solar_private.customer_name_key(q))>0)
 ), filtered as(select * from matched where stage='' or warehouse_status=stage),
 paged as(select * from filtered order by created_at desc,id desc limit 30 offset greatest(0,least(coalesce(page_offset,0),1000000)))
 select jsonb_build_object('count',(select count(*) from filtered),'statusCounts',jsonb_build_object('pending',(select count(*) from matched where warehouse_status='pending'),'ready',(select count(*) from matched where warehouse_status='ready'),'all',(select count(*) from matched)),
 'rows',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'kind',t.kind,'party',t.party_name,'phone',t.customer_phone,'address',t.customer_address,'date',t.created_at,'status',t.warehouse_status,
 'warranty',t.warranty,'warehouseQrToken',t.warehouse_qr_token,'preparedAt',t.warehouse_prepared_at,'preparedBy',(select coalesce(display_name,username) from public.profiles where id=t.warehouse_prepared_by),'note',t.warehouse_note,'token',solar_private.warehouse_token(t.id),'canEdit',t.installation_status not in('in_progress','completed','closed'),
 'items',coalesce((select jsonb_agg(jsonb_build_object('lineId',i.id,'productId',i.product_id,'name',i.product_name,'brand',i.brand_name,'category',i.category,'qty',i.qty) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]')) order by t.created_at desc,t.id desc) from paged t),'[]')) into result;
 return result;
end $function$;

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
 perform pg_advisory_xact_lock(7311,1); select * into j from public.transactions where id=invoice_id and kind in ('sale','system') for update;
 if j.id is null or not solar_private.can_access_invoice(j.created_by,true) then raise exception 'الفاتورة غير متاحة' using errcode='42501';end if;
 if solar_private.warehouse_token(j.id) is distinct from expected_token then raise exception 'تغيّرت الفاتورة، حدّث الصفحة وحاول مجدداً' using errcode='PT409';end if;
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
end $function$;

CREATE OR REPLACE FUNCTION solar_private.warehouse_statuses(invoice_ids bigint[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles;result jsonb;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type='installer' then raise exception 'Not permitted' using errcode='42501';end if;
 if coalesce(cardinality(invoice_ids),0)>500 then raise exception 'اطلب حالة 500 فاتورة كحد أقصى';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'status',t.warehouse_status,'preparedAt',t.warehouse_prepared_at,'revision',t.warehouse_revision)),'[]') into result from public.transactions t
 where t.id=any(invoice_ids) and t.kind in('sale','system') and(p.is_admin or p.user_type='warehouse' or t.created_by=p.id);
 return result;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.stock_movements(product_filter bigint DEFAULT NULL::bigint, customer_filter text DEFAULT ''::text, date_from date DEFAULT NULL::date, date_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.user_type<>'installer' and (p.user_type='warehouse' or p.is_admin or p.permissions->>'stockMovement'='true' or p.permissions->>'warehouse'='true')) then raise exception 'Not permitted' using errcode='42501';end if;
 with movements as (
  select 'line:'||i.id id,i.product_id,i.product_name,i.brand_name,i.category,t.id invoice_id,t.receipt_no,t.kind,t.party_name,t.created_at,t.created_by movement_owner,
  case when t.kind='purchase' then i.qty else -i.qty end delta,p.qty current_qty,''::text note
  from public.transaction_items i join public.transactions t on t.id=i.transaction_id join public.products p on p.id=i.product_id
  where t.kind in ('purchase','sale','system') and (product_filter is null or i.product_id=product_filter)
  union all
  select 'adjustment:'||a.id,a.product_id,p.name,b.name,p.category,a.id,a.id,'stock_adjustment','',a.created_at,a.actor_id,
   a.actual_qty-a.old_qty,p.qty,a.note||' | السابق: '||a.old_qty||' | الفعلي: '||a.actual_qty
  from solar_private.stock_adjustments a join public.products p on p.id=a.product_id left join public.brands b on b.id=p.brand_id
  where product_filter is null or a.product_id=product_filter
 ), balances as (
  select *,current_qty-sum(delta) over(partition by product_id)+sum(delta) over(partition by product_id order by created_at,invoice_id,id rows unbounded preceding) balance from movements
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'productId',product_id,'name',product_name,'brand',brand_name,'category',category,'receiptNo',receipt_no,'kind',kind,'party',party_name,'date',created_at,'note',note,'inQty',greatest(delta,0),'outQty',greatest(-delta,0),'balance',balance) order by created_at,invoice_id,id),'[]'::jsonb) into result from balances
 where ((select solar_private.role_name()) in('admin','warehouse') or movement_owner=(select auth.uid())) and (customer_filter='' or (kind in ('sale','system') and strpos(lower(coalesce(party_name,'')),lower(customer_filter))>0))
 and (date_from is null or created_at >= (date_from::timestamp at time zone 'Asia/Baghdad'))
 and (date_to is null or created_at < ((date_to+1)::timestamp at time zone 'Asia/Baghdad'));
 return result;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.invoice_save_v333(request_id uuid, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_variable
declare p public.profiles; old_invoice public.transactions; invoice public.transactions;
 cached solar_private.invoice_requests; product public.products; old_item public.transaction_items;
 line jsonb; computed jsonb:='[]'::jsonb; snapshots jsonb:='[]'::jsonb; before_stock jsonb;
 kind text; currency text; mode text; invoice_id bigint; item_id bigint; party_id bigint; owner_id uuid;
 rate numeric; default_rate numeric; source_sum numeric:=0; subtotal numeric:=0; expenses numeric; total numeric; cost numeric:=0;
 qty numeric; price numeric; unit_cost numeric; landed numeric; remaining_qty numeric; remaining_cost numeric;
 previous_qty numeric; previous_value numeric; next_qty numeric; next_cost numeric; product_qty numeric; product_cost numeric;
 new_basis jsonb; result jsonb; economic_change boolean:=true; existing boolean:=false; cash boolean;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') then raise exception 'لا توجد صلاحية لحفظ الفاتورة' using errcode='42501';end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب حفظ غير صحيح';end if;
 kind:=payload->>'kind';currency:=coalesce(payload->>'sourceCurrency','IQD');mode:=coalesce(payload->>'mode','cash');
 if kind not in ('purchase','sale','system') or not(p.is_admin or coalesce(p.permissions->>kind,'false')='true') then raise exception 'لا توجد صلاحية لهذا النوع من الفواتير' using errcode='42501';end if;
 if currency not in ('IQD','USD') or (kind<>'purchase' and currency<>'IQD') or mode not in ('cash','credit') then raise exception 'البيع بالدينار فقط؛ تحقق من العملة وطريقة الدفع';end if;
 if jsonb_typeof(payload->'items') is distinct from 'array' or jsonb_array_length(payload->'items') not between 1 and 500 then raise exception 'أضف مواد صحيحة للفاتورة';end if;
 if length(coalesce(payload->>'notes',''))>4000 then raise exception 'الملاحظات طويلة جداً';end if;
 expenses:=coalesce((payload->>'expenses')::numeric,0); if kind='system' and nullif(payload->>'invoiceId','') is null and expenses<>0 then raise exception 'مصاريف التنصيب تعتمد كاملة بعد التجهيز عند إغلاق الملف';end if;
 if expenses::text in ('NaN','Infinity','-Infinity') or expenses<0 or expenses>1000000000000 then raise exception 'مصاريف غير صحيحة بالدينار';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into cached from solar_private.invoice_requests r where r.request_id=invoice_save_v333.request_id;
 if cached.request_id is not null then
  if cached.user_id<>p.id or cached.payload is distinct from payload then raise exception 'معرّف الطلب مستخدم لبيانات أخرى' using errcode='42501';end if;
  if not exists(select 1 from public.transactions t where t.id=(cached.result->>'id')::bigint) then raise exception 'الفاتورة حذفت أو صفّرت؛ حدّث البيانات' using errcode='PT409';end if;
  return cached.result;
 end if;
 invoice_id:=nullif(payload->>'invoiceId','')::bigint;
 if invoice_id is not null then
  select * into old_invoice from public.transactions where id=invoice_id for update;
  if old_invoice.id is null or not solar_private.can_access_invoice(old_invoice.created_by,false) or old_invoice.kind<>kind or (not p.is_admin and coalesce(old_invoice.cashbox_user_id,old_invoice.created_by) is distinct from p.id) then raise exception 'الفاتورة غير متاحة لحسابك' using errcode='42501';end if;
  if old_invoice.pricing_revision is distinct from (payload->>'expectedRevision')::bigint then raise exception 'تغيرت الفاتورة؛ افتح التعديل مجدداً' using errcode='PT409';end if;
  if kind='system' then raise exception 'استخدم متابعة التنصيب لتعديل المنظومة';end if;
  if kind<>'sale' and old_invoice.cash is distinct from (mode='cash') then raise exception 'لا يمكن تغيير طريقة دفع الفاتورة المحفوظة';end if;
  existing:=true;owner_id:=coalesce(old_invoice.cashbox_user_id,old_invoice.created_by);
 else
  -- Integer ID allocation is serialized with the existing cash/stock lock.
  invoice_id:=greatest((extract(epoch from clock_timestamp())*1000)::bigint,coalesce((select max(t.id)+1 from public.transactions t),1));
  owner_id:=p.id;
 end if;
 if currency='USD' then
  rate:=(payload->>'exchangeRate')::numeric;
  if rate is null or rate::text in ('NaN','Infinity','-Infinity') or rate<=0 or rate>1000000 then raise exception 'سعر صرف غير صحيح';end if;
  select s.rate into default_rate from solar_private.exchange_settings s where s.id;
  if not(p.is_admin or coalesce(p.permissions->>'exchangeRateEdit','false')='true') and rate is distinct from default_rate
   and not(existing and old_invoice.source_currency='USD' and old_invoice.exchange_rate=rate) then raise exception 'تغيير صرف الفاتورة يحتاج صلاحية تعديل سعر الصرف' using errcode='42501';end if;
 else rate:=1;end if;
 if exists(select 1 from jsonb_array_elements(payload->'items') x group by x->>'id' having count(*)>1) then raise exception 'المادة مكررة في الفاتورة';end if;
 for line in select value from jsonb_array_elements(payload->'items') loop
  if jsonb_typeof(line) is distinct from 'object' or jsonb_typeof(line->'id') is distinct from 'number' or jsonb_typeof(line->'qty') is distinct from 'number' or jsonb_typeof(line->'price') is distinct from 'number' then raise exception 'مواد الفاتورة غير صحيحة';end if;
  qty:=(line->>'qty')::numeric;price:=(line->>'price')::numeric;
  if qty::text in ('NaN','Infinity','-Infinity') or price::text in ('NaN','Infinity','-Infinity') or qty<=0 or qty>100000000 or price<0 or price>1000000000000 then raise exception 'كمية أو سعر غير صحيح';end if;
  source_sum:=source_sum+qty*price;
 end loop;
 if source_sum=0 and expenses>0 and kind='purchase' then raise exception 'لا يمكن توزيع مصاريف على مواد مجموع أسعارها صفر';end if;
 subtotal:=round(source_sum*rate,2);total:=subtotal+expenses;
 if kind='system' then
  total:=(payload->>'total')::numeric;subtotal:=total;
  if total is null or total::text in ('NaN','Infinity','-Infinity') or total<=0 or total>1000000000000 then raise exception 'سعر بيع منظومة غير صحيح';end if;
  if coalesce(trim(payload->>'customerAddress'),'')='' or not exists(select 1 from public.profiles x where x.id=(payload->>'installerId')::uuid and x.active and x.user_type='installer') then raise exception 'اختر مهندساً فعالاً واكتب عنوان التنصيب';end if;
  if (nullif(payload->>'installDate','') is null) is distinct from (nullif(payload->>'installTime','') is null) then raise exception 'حدد يوم وساعة الموعد معاً';end if;
 end if;
 party_id:=null;
 if coalesce(payload->>'party','')<>'' then
  if kind='purchase' then
   select id into party_id from public.suppliers where name=payload->>'party' and active order by id limit 1;
  else
   select c.id into party_id from public.customers c where c.name=payload->>'party' and (p.is_admin or c.owner_id=p.id) order by c.id limit 1;
  end if;
  if party_id is null then raise exception 'اختر طرفاً موجوداً ضمن صلاحياتك' using errcode='42501';end if;
 elsif mode='credit' or kind='system' then raise exception 'اختر العميل أو المورد';end if;
 cash:=mode='cash' and kind<>'system';
 if cash and kind='purchase' and coalesce(payload->>'cashCurrency','IQD')='IQD' and (total-case when existing and old_invoice.cash and old_invoice.cash_currency='IQD' then old_invoice.total else 0 end)>solar_private.cash_balance(owner_id) then raise exception 'رصيد قاصة صاحب الفاتورة غير كافٍ' using errcode='P0002';end if;
 if existing and kind='sale' and (case when old_invoice.cash then old_invoice.total else 0 end)-(case when cash then total else 0 end)>solar_private.cash_balance(owner_id) then raise exception 'الرصيد لا يكفي لتخفيض البيع النقدي' using errcode='P0002';end if;
 if existing and kind='purchase' then
  economic_change:=old_invoice.source_currency<>currency or old_invoice.exchange_rate<>rate or old_invoice.expenses<>expenses or
   (select coalesce(jsonb_agg(jsonb_build_object('id',i.product_id,'qty',i.qty,'price',coalesce(i.source_price,i.price)) order by i.product_id),'[]'::jsonb) from public.transaction_items i where i.transaction_id=invoice_id)
   is distinct from (select jsonb_agg(jsonb_build_object('id',(x->>'id')::bigint,'qty',(x->>'qty')::numeric,'price',(x->>'price')::numeric) order by (x->>'id')::bigint) from jsonb_array_elements(payload->'items') x);
 end if;
 -- Lock affected products in ID order. No cost supplied by the client is used.
 for product in select x.* from public.products x where x.id in (
  select (v->>'id')::bigint from jsonb_array_elements(payload->'items') v
  union select i.product_id from public.transaction_items i where existing and i.transaction_id=invoice_id
 ) order by x.id for update loop
  previous_qty:=0;previous_value:=0;
  if existing then select coalesce(sum(i.qty),0),coalesce(sum(i.qty*case when old_invoice.kind='purchase' then case when i.landed_cost>0 then i.landed_cost else i.price end else i.cost end),0) into previous_qty,previous_value from public.transaction_items i where i.transaction_id=invoice_id and i.product_id=product.id;end if;
  product_qty:=product.qty;product_cost:=product.cost;new_basis:=null;before_stock:=null;
  if kind='purchase' then
   if existing and economic_change and previous_qty>0 then
    if old_invoice.fx_pricing then
     select v into before_stock from jsonb_array_elements(old_invoice.purchase_stock) v where (v->>'id')::bigint=product.id;
     if before_stock is null or product.costing_revision is distinct from (before_stock->>'afterRevision')::bigint then raise exception 'حدثت حركة على المادة بعد الشراء. لا يمكن تغيير كلفتها التاريخية؛ استخدم تسوية أو فاتورة تصحيح' using errcode='PT409';end if;
     product_qty:=(before_stock->>'qty')::numeric;product_cost:=(before_stock->>'cost')::numeric;
    else
     if exists(select 1 from public.transaction_items i join public.transactions t on t.id=i.transaction_id where i.product_id=product.id and t.id<>invoice_id and (t.created_at,t.id)>(old_invoice.created_at,old_invoice.id) and t.kind in ('purchase','sale','system')) then raise exception 'حدثت حركة لاحقة؛ لا يمكن إعادة احتساب كلفة شراء قديم' using errcode='PT409';end if;
     product_qty:=product.qty-previous_qty;
     if product_qty<0 then raise exception 'لا يمكن تعديل شراء استُهلكت كميته';end if;
     if product_qty>0 then product_cost:=(product.qty*product.cost-previous_value)/product_qty;end if;
     if product_cost<0 then raise exception 'تعذر استعادة الكلفة السابقة؛ استخدم تسوية محاسبية';end if;
    end if;
   end if;
  else product_qty:=product.qty+previous_qty;end if;
  select v into line from jsonb_array_elements(payload->'items') v where (v->>'id')::bigint=product.id;
  if existing and kind='sale' and previous_qty>0 and product.cost is distinct from previous_value/previous_qty and coalesce((line->>'qty')::numeric,0)<>previous_qty then raise exception 'تغيرت كلفة المخزون بعد البيع. عدّل السعر فقط أو سجّل فاتورة تصحيح للكميات' using errcode='PT409';end if;
  if line is null then
   if kind='purchase' then next_qty:=product_qty;next_cost:=product_cost;else next_qty:=product_qty;next_cost:=product.cost;end if;
  else
   qty:=(line->>'qty')::numeric;price:=(line->>'price')::numeric;
   if kind='purchase' then
    landed:=round(price*rate+case when source_sum>0 then expenses*price/source_sum else 0 end,6);
    unit_cost:=landed;
    new_basis:=jsonb_build_object('currency',currency,'rate',rate,'sourcePrice',price,'invoiceId',invoice_id);
    if not existing or economic_change then
     next_qty:=product_qty+qty;next_cost:=round((product_qty*product_cost+qty*landed)/next_qty,6);
     snapshots:=snapshots||jsonb_build_array(jsonb_build_object('id',product.id,'qty',product_qty,'cost',product_cost,'basis',case when before_stock is not null then before_stock->'basis' else product.cost_basis end,'afterRevision',product.costing_revision+case when (next_qty,next_cost) is distinct from (product.qty,product.cost) then 1 else 0 end));
    else next_qty:=product.qty;next_cost:=product.cost;end if;
   else
    if qty>product_qty then raise exception 'الكمية غير كافية للمادة: %',product.name;end if;
    select * into old_item from public.transaction_items i where existing and i.transaction_id=invoice_id and i.product_id=product.id order by i.id limit 1;
    unit_cost:=case when old_item.id is not null then old_item.cost else product.cost end;
    new_basis:=case when old_item.id is not null then old_item.cost_basis else product.cost_basis end;
    landed:=0;next_qty:=product_qty-qty;next_cost:=product.cost;
   end if;
   cost:=cost+qty*unit_cost;
   computed:=computed||jsonb_build_array(jsonb_build_object('id',product.id,'name',product.name,'brand',(select b.name from public.brands b where b.id=product.brand_id),'category',product.category,'qty',qty,'price',case when kind='system' then 0 else round(price*rate,6) end,'sourcePrice',case when kind='purchase' then price else null end,'cost',unit_cost,'landedCost',landed,'costBasis',new_basis));
  end if;
  if kind<>'purchase' or not existing or economic_change then
   update public.products set qty=next_qty,cost=next_cost,cost_basis=case when kind='purchase' then case when line is null and before_stock is not null then before_stock->'basis' else jsonb_build_object('method','weighted-average','lastPurchase',new_basis,'unitCost',next_cost) end else case when product.cost_basis='{}'::jsonb then jsonb_build_object('method','legacy-iqd','unitCost',next_cost) else product.cost_basis end end where id=product.id;
  end if;
 end loop;
 if jsonb_array_length(computed)<>jsonb_array_length(payload->'items') then raise exception 'إحدى المواد غير موجودة؛ حدّث البيانات';end if;
 cost:=round(cost,2);
 if existing then
  update public.transactions set party_name=nullif(payload->>'party',''),party_id=party_id,party_type=case when kind='purchase' then 'supplier' else 'customer' end,
   cash=cash,payment_mode=mode,subtotal=subtotal,total=total,expenses=expenses,cost=cost,profit=case when kind='sale' then subtotal-cost when kind='system' then total-cost-expenses else 0 end,
   notes=nullif(payload->>'notes',''),source_currency=currency,exchange_rate=rate,source_subtotal=source_sum,fx_pricing=true,
   purchase_stock=case when kind='purchase' and economic_change then snapshots else purchase_stock end where id=invoice_id returning * into invoice;
 else
  insert into public.transactions(id,kind,party_type,party_id,party_name,payment_mode,subtotal,expenses,total,cost,profit,notes,cash,created_by,cashbox_user_id,
   source_currency,exchange_rate,source_subtotal,fx_pricing,purchase_stock,installer_id,install_date,install_time,customer_address,customer_phone,installation_status)
  values(invoice_id,kind,case when kind='purchase' then 'supplier' else 'customer' end,party_id,nullif(payload->>'party',''),mode,subtotal,expenses,total,cost,
   case when kind='sale' then subtotal-cost when kind='system' then total-cost-expenses else 0 end,nullif(payload->>'notes',''),cash,p.id,owner_id,
   currency,rate,source_sum,true,snapshots,case when kind='system' then (payload->>'installerId')::uuid end,
   nullif(payload->>'installDate','')::date,nullif(payload->>'installTime','')::time,nullif(payload->>'customerAddress',''),nullif(payload->>'customerPhone',''),case when kind='system' then 'pending' else 'none' end)
  returning * into invoice;
 end if;
 if not(existing and kind='purchase' and not economic_change) then
  delete from public.transaction_items where transaction_id=invoice_id;
  for line in select value from jsonb_array_elements(computed) loop
   insert into public.transaction_items(transaction_id,product_id,product_name,brand_name,category,qty,price,cost,landed_cost,source_price,cost_basis)
   values(invoice_id,(line->>'id')::bigint,line->>'name',line->>'brand',line->>'category',(line->>'qty')::numeric,(line->>'price')::numeric,(line->>'cost')::numeric,(line->>'landedCost')::numeric,(line->>'sourcePrice')::numeric,line->'costBasis');
  end loop;
 end if;
 select * into invoice from public.transactions where id=invoice_id;
 result:=jsonb_build_object('id',invoice.id,'receiptNo',invoice.receipt_no,'pricingRevision',invoice.pricing_revision,'total',invoice.total,'cost',invoice.cost,'profit',invoice.profit,'invoiceAccount',invoice.invoice_account,'warehouseQrToken',invoice.warehouse_qr_token);
 if kind in ('sale','system') then if existing and payload ? 'warranty' and coalesce((payload->>'expectedWarrantyRevision')::bigint,-1)<>invoice.warranty_revision then raise exception 'تغيّر ضمان الفاتورة؛ افتح التعديل مجدداً' using errcode='PT409';end if;result:=result||solar_private.warranty_apply(invoice_id,payload->'warranty');end if; insert into solar_private.invoice_requests(request_id,user_id,payload,result) values(request_id,p.id,payload,result);
 return result;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.purchase_delete(invoice_id bigint, expected_revision bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles; t public.transactions; snapshot jsonb; product public.products;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'purchase','false')='true') then raise exception 'لا توجد صلاحية حذف الشراء' using errcode='42501';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into t from public.transactions where id=invoice_id and kind='purchase' for update;
 if t.id is null or not solar_private.can_access_invoice(t.created_by,false) or not t.fx_pricing or (not p.is_admin and coalesce(t.cashbox_user_id,t.created_by) is distinct from p.id) then raise exception 'الفاتورة غير متاحة' using errcode='42501';end if;
 if jsonb_array_length(t.purchase_stock)=0 or jsonb_array_length(t.purchase_stock)<>(select count(distinct i.product_id) from public.transaction_items i where i.transaction_id=t.id) then raise exception 'لا توجد كلفة سابقة موثقة لاستعادة هذه الفاتورة؛ استخدم تسوية محاسبية';end if;
 if t.pricing_revision is distinct from expected_revision then raise exception 'تغيرت الفاتورة؛ حدّث البيانات' using errcode='PT409';end if;
 for snapshot in select v from jsonb_array_elements(t.purchase_stock) v order by (v->>'id')::bigint loop
  select * into product from public.products where id=(snapshot->>'id')::bigint for update;
  if product.id is null or product.costing_revision is distinct from (snapshot->>'afterRevision')::bigint then raise exception 'حدثت حركة على المادة بعد الشراء؛ لا يمكن حذف كلفتها التاريخية' using errcode='PT409';end if;
  update public.products set qty=(snapshot->>'qty')::numeric,cost=(snapshot->>'cost')::numeric,cost_basis=snapshot->'basis' where id=product.id;
 end loop;
 -- Retain the original invoice and snapshots as an audit record.
 insert into solar_private.deleted_sales(invoice_id,invoice,items,deleted_by)
 select t.id,to_jsonb(t),coalesce(jsonb_agg(to_jsonb(i)),'[]'::jsonb),p.id from public.transaction_items i where i.transaction_id=t.id;
 delete from public.cash_ledger where transaction_id=t.id;
 delete from public.transactions where id=t.id;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.warranty_manage(action text, request_id uuid DEFAULT NULL::uuid, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
#variable_conflict use_variable
declare p public.profiles;t public.transactions;items jsonb;token text;prior solar_private.finance_requests;result jsonb;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in('installer','warehouse') then raise exception 'لا تملك صلاحية ضمان الفواتير' using errcode='42501';end if;
 if action is null or action not in('get','save') or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب غير صحيح';end if;
 if action='save' then
  if request_id is null then raise exception 'رقم طلب الحفظ مطلوب';end if;
  perform pg_advisory_xact_lock(7311,1);
  select * into prior from solar_private.finance_requests f where f.request_id=warranty_manage.request_id;
  if found then if prior.actor_id=p.id and prior.action='warranty' and prior.payload=payload then return prior.response;end if;raise exception 'طلب مكرر ببيانات مختلفة' using errcode='PT409';end if;
 end if;
 select * into t from public.transactions where id=(payload->>'id')::bigint;
 if t.id is null or not solar_private.can_access_invoice(t.created_by,false) or t.kind not in('sale','system') or not(p.is_admin or(coalesce(t.cashbox_user_id,t.created_by)=p.id and coalesce(p.permissions->>t.kind,'false')='true')) then raise exception 'هذه الفاتورة للإدارة أو صاحبها بصلاحية البيع' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',i.product_id,'name',i.product_name,'qty',i.qty) order by i.id),'[]') into items from public.transaction_items i where transaction_id=t.id;
 token:=md5(to_jsonb(t)::text||items::text);
 if action='get' then return jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'date',t.created_at,'party',t.party_name,'items',items,'warranty',t.warranty,'warrantyToken',t.warranty_token,'pricingRevision',t.pricing_revision,'warrantyRevision',t.warranty_revision,'expectedToken',token);end if;
 if payload->>'expectedToken' is distinct from token then raise exception 'تغيرت الفاتورة أو ضمانها؛ افتحها مجدداً' using errcode='PT409';end if;
 result:=solar_private.warranty_apply(t.id,payload->'warranty');
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response) values(request_id,p.id,'warranty',payload,result);
 return result;
end $function$;

-- Privileged notification writers check the recipient, not the actor/worker.
create function solar_private.notification_recipient_allowed(recipient uuid,invoice_id bigint) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=recipient and p.active and
 ((p.is_admin and p.user_type not in('installer','warehouse')) or
 exists(select 1 from public.transactions t where t.id=invoice_id and
  (p.user_type='warehouse' or(p.user_type='installer' and t.installer_id=p.id) or(p.user_type not in('installer','warehouse') and t.created_by=p.id))) or
 (p.user_type not in('installer','warehouse') and exists(select 1 from solar_private.deleted_sales d where d.invoice_id=notification_recipient_allowed.invoice_id and d.invoice->>'created_by'=p.id::text))))
$$;
revoke all on function solar_private.notification_recipient_allowed(uuid,bigint) from public,anon,authenticated;
create function solar_private.notification_job_allowed(invoice_id bigint) returns boolean
language sql stable security definer set search_path='' as $$select solar_private.notification_recipient_allowed(auth.uid(),invoice_id)$$;
revoke all on function solar_private.notification_job_allowed(bigint) from public,anon;
grant execute on function solar_private.notification_job_allowed(bigint) to authenticated;
create policy solar_notification_job_scope on public.solar_notifications as restrictive for select to authenticated
using(job_id is null or solar_private.notification_job_allowed(job_id));
-- Already queued notices for another staff member must never be sent later.
update solar_private.push_deliveries d set status='failed',last_status=403,lease_until=null
from public.solar_notifications n where n.id=d.notification_id and n.job_id is not null
and d.status in('pending','sending') and not solar_private.notification_recipient_allowed(n.user_id,n.job_id);


CREATE OR REPLACE FUNCTION solar_private.warehouse_notice(recipient uuid, invoice_id bigint, event_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare nid uuid;heading text;detail text;invoice public.transactions;begin
 if not exists(select 1 from public.profiles where id=recipient and active) then return;end if;
 select * into invoice from public.transactions where id=invoice_id;
 if invoice.id is null or not solar_private.notification_recipient_allowed(recipient,invoice.id) then return;end if;
 heading:=case event_name when 'warehouse_ready' then case when invoice.kind='system' then 'المنظومة جاهزة لاعتماد المصاريف والغلق' else 'تم تجهيز الفاتورة' end when 'warehouse_edited' then 'تعديل مواد الفاتورة من المخزن' when 'warehouse_reopened' then 'الفاتورة تحتاج تجهيزاً من جديد' when 'installation_closed' then 'تم اعتماد المصاريف وإغلاق ملف المنظومة' else 'فاتورة جديدة بانتظار التجهيز' end;
 detail:='وصل #'||invoice.receipt_no||' • '||coalesce(invoice.party_name,'زبون نقدي');
 insert into public.solar_notifications(user_id,job_id,event,title,body) values(recipient,invoice_id,event_name,heading,detail) returning id into nid;
 insert into solar_private.push_deliveries(notification_id,endpoint) select nid,endpoint from public.solar_push_subscriptions where user_id=recipient;
 perform solar_private.wake_push();
end $function$;

CREATE OR REPLACE FUNCTION solar_private.warehouse_notify()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 for u in select id from public.profiles where active and user_type<>'installer' and(user_type='warehouse' or(permissions->>'warehouse'='true' and(id=new.created_by or is_admin))) loop
  perform solar_private.warehouse_notice(u.id,new.id,event_name);
 end loop;return new;
end $function$;

notify pgrst,'reload schema';

-- The current admin screen uses the authenticated Edge Function. This obsolete
-- endpoint accepted a supplied administrator ID and must not enumerate users.
do $$begin
 if to_regprocedure('public.simple_admin_users(uuid)') is not null then
  revoke all on function public.simple_admin_users(uuid) from public,anon,authenticated;
 end if;
end $$;
