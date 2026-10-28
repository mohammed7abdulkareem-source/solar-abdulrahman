-- Keep dated payouts and their refunds after a receipt is voided. A cash entry
-- refers to exactly one live or archived installation; its owner never changes.
alter table public.solar_cash_entries add column deleted_job_id bigint
 references solar_private.deleted_sales(invoice_id) on delete cascade;
alter table public.solar_cash_entries drop constraint if exists solar_cash_entries_check1;
alter table public.solar_cash_entries add constraint solar_cash_entries_check1
 check((entry_type in('installation_payout','installation_refund'))=(coalesce(job_id,deleted_job_id) is not null));
alter table public.solar_cash_entries add constraint solar_cash_entries_single_job
 check(num_nonnulls(job_id,deleted_job_id)<=1);
create index solar_entries_deleted_job on public.solar_cash_entries(deleted_job_id);

CREATE OR REPLACE FUNCTION solar_private.can_delete_sale(owner_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.user_type not in('installer','warehouse')
 and(p.is_admin or p.id=owner_id))
$function$;

CREATE OR REPLACE FUNCTION solar_private.cash_movements()
 RETURNS TABLE(id text, owner_id uuid, currency text, delta numeric, book_delta numeric, kind text, party text, note text, receipt_no bigint, rate numeric, source_currency text, source_amount numeric, created_at timestamp with time zone, request_id uuid)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select 'tx:'||t.id,coalesce(t.cashbox_user_id,t.created_by),t.cash_currency,
  (case when t.kind in ('purchase','supplier_payment','cash_expense','profit_distribution') then -1 else 1 end)*case when t.cash_currency='USD' then t.cash_amount else t.total end,
  case when t.cash_currency='USD' then coalesce(w.book_delta,0) else(case when t.kind in ('purchase','supplier_payment','cash_expense','profit_distribution') then -t.total else t.total end) end,
  case t.cash_purpose when 'external_profit' then 'external_profit' when 'capital' then 'capital_deposit' when 'withdrawal' then 'capital_withdraw' when 'expense' then 'expense' else t.kind end,coalesce(t.party_name,''),coalesce(t.notes,''),t.receipt_no,t.market_rate,t.source_currency,coalesce(t.source_subtotal,t.total),t.created_at,t.finance_request_id
 from public.transactions t left join solar_private.wallet_fx_entries w on w.transaction_id=t.id where t.cash
 union all select 'entry:'||e.id,e.owner_id,'IQD',e.delta,e.delta,e.entry_type,coalesce(j.party_name,''),e.notes,j.receipt_no,1,'IQD',abs(e.delta),e.created_at,null::uuid from public.solar_cash_entries e left join lateral(select live.* from public.transactions live where live.id=e.job_id union all select (jsonb_populate_record(null::public.transactions,ds.invoice)).* from solar_private.deleted_sales ds where ds.invoice_id=e.deleted_job_id)j on true
 union all select 'fx:'||e.id,e.owner_id,e.currency,e.delta,e.book_delta,e.entry_type,'',e.note,(fr.response->>'receiptNo')::bigint,e.rate,e.currency,abs(e.delta),e.created_at,e.finance_request_id from solar_private.wallet_fx_entries e left join solar_private.finance_requests fr on fr.request_id=e.finance_request_id where e.transaction_id is null
$function$;

CREATE OR REPLACE FUNCTION solar_private.cash_statement(owner_id uuid, date_from date, date_to date, currency_filter text DEFAULT 'all'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '15s'
AS $function$
declare p public.profiles;uid uuid;start_at timestamptz;end_at timestamptz;result jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('installer','warehouse');
 if p.id is null or not coalesce(solar_private.cash_allowed('view'),false) then raise exception 'لا تملك صلاحية الصندوق' using errcode='42501';end if;
 uid:=cash_statement.owner_id;
 if not p.is_admin then
  if uid is not null and uid<>p.id then raise exception 'يمكنك مشاهدة كشف قاصتك فقط' using errcode='42501';end if;
  uid:=p.id;
 end if;
 if uid is not null and not exists(select 1 from public.profiles o where o.id=uid and o.user_type not in('installer','warehouse')) then raise exception 'القاصة غير متاحة' using errcode='22023';end if;
 if date_from is null or date_to is null or date_from>date_to or not isfinite(date_from) or not isfinite(date_to) or currency_filter is null or currency_filter not in('all','IQD','USD') then raise exception 'اختر فترة وعملة صحيحة للكشف' using errcode='22023';end if;
 start_at:=date_from::timestamp at time zone 'Asia/Baghdad';end_at:=(date_to+1)::timestamp at time zone 'Asia/Baghdad';
 with movements as materialized(
  select m.* from solar_private.cash_movements() m where (uid is null or m.owner_id=uid) and(currency_filter='all' or m.currency=currency_filter) and m.created_at<end_at
 ), owners as(
  select o.id from public.profiles o where (uid is null or o.id=uid) and o.user_type not in('installer','warehouse') and(o.active or exists(select 1 from movements m where m.owner_id=o.id))
  union select m.owner_id from movements m
 ), currencies as(select c from (values('IQD'),('USD')) v(c) where currency_filter='all' or c=currency_filter),
 ranked as materialized(
  select m.*,sum(m.delta) over(partition by m.owner_id,m.currency order by m.created_at,m.id rows unbounded preceding) balance from movements m
 ), period_rows as materialized(
  select m.*,coalesce(solar_private.user_name(a.display_name,a.username,a.honorific),'غير محدد') actor_name,coalesce(t.warehouse_name,j.warehouse_name) warehouse_name,
   coalesce(t.payment_mode,j.payment_mode) payment_mode,e.deleted_job_id is not null invoice_deleted,case when e.deleted_job_id is not null then 0 else j.installation_expenses end current_expenses,case when e.deleted_job_id is not null then 0 else paid.net end current_paid,
   case when coalesce(e.job_id,e.deleted_job_id) is not null then j.receipt_no end job_receipt,
   solar_private.user_name(sender.display_name,sender.username,sender.honorific) sender_name,solar_private.user_name(recipient.display_name,recipient.username,recipient.honorific) recipient_name,
   h.amount transfer_amount,h.expense transfer_expense,h.expense_note,h.notes transfer_note,h.status transfer_status,
   case when m.kind='cash_reconcile' then solar_private.cash_reconciliation_info(m.request_id,m.owner_id) end reconciliation
  from ranked m
  left join public.transactions t on m.id='tx:'||t.id
  left join public.solar_cash_entries e on m.id='entry:'||e.id
  left join lateral(select live.* from public.transactions live where live.id=e.job_id union all select (jsonb_populate_record(null::public.transactions,ds.invoice)).* from solar_private.deleted_sales ds where ds.invoice_id=e.deleted_job_id)j on true left join(select job_id,-sum(delta)net from public.solar_cash_entries where job_id is not null group by job_id)paid on paid.job_id=e.job_id
  left join solar_private.finance_requests f on f.request_id=m.request_id
  left join public.profiles a on a.id=coalesce(t.created_by,e.actor_id,f.actor_id)
  left join solar_private.cash_transfers h on h.id=e.transfer_id
  left join public.profiles sender on sender.id=h.sender_id
  left join public.profiles recipient on recipient.id=h.recipient_id
  where m.created_at>=start_at
 ), ledgers as(
  select o.id,c.c currency,coalesce(solar_private.user_name(pf.display_name,pf.username,pf.honorific),'قيد التسليم') owner_name,
   coalesce(sum(m.delta) filter(where m.created_at<start_at),0) opening,
   coalesce(sum(m.delta) filter(where m.created_at>=start_at and m.delta>0),0) incoming,
   coalesce(sum(-m.delta) filter(where m.created_at>=start_at and m.delta<0),0) outgoing,
   coalesce(sum(m.delta),0) closing,
   (select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at,r.id),'[]') from period_rows r where r.owner_id is not distinct from o.id and r.currency=c.c) rows
  from owners o cross join currencies c left join public.profiles pf on pf.id=o.id
  left join movements m on m.owner_id is not distinct from o.id and m.currency=c.c
  group by o.id,c.c,pf.display_name,pf.username,pf.honorific
 )
 select jsonb_build_object('asOf',statement_timestamp(),'from',date_from,'to',date_to,'ownerId',uid,
  'ownerName',case when uid is null then 'جميع القاصات' else(select coalesce(solar_private.user_name(display_name,username,honorific),'مستخدم') from public.profiles where id=uid) end,
  'count',(select count(*) from period_rows),
  'ledgers',coalesce(jsonb_agg(jsonb_build_object('ownerId',id,'ownerName',owner_name,'currency',currency,'opening',opening,'incoming',incoming,'outgoing',outgoing,'closing',closing,'rows',rows) order by owner_name,id,currency),'[]'))
 into result from ledgers;
 return result;
end$function$;

CREATE OR REPLACE FUNCTION solar_private.cash_movement_detail(movement_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles;m record;t public.transactions;entry public.solar_cash_entries;
 handover solar_private.cash_transfers;fr solar_private.finance_requests;actor uuid;actor_name text;actor_phone text;
 balance_after numeric;document jsonb;items jsonb:='[]';transfer_info jsonb;exchange_info jsonb;reconciliation jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 if p.id is null or not solar_private.cash_allowed('view') then raise exception 'لا تملك صلاحية الصندوق' using errcode='42501';end if;
 if movement_id is null or length(movement_id)>100 then raise exception 'الحركة غير متاحة' using errcode='42501';end if;
 select x.*,coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'قيد التسليم') owner_name into m
 from solar_private.cash_movements() x left join public.profiles o on o.id=x.owner_id
 where x.id=movement_id and(p.is_admin or x.owner_id=p.id);
 if not found then raise exception 'الحركة غير متاحة ضمن صلاحياتك' using errcode='42501';end if;
 select coalesce(sum(x.delta),0) into balance_after from solar_private.cash_movements() x
 where x.owner_id is not distinct from m.owner_id and x.currency=m.currency and(x.created_at,x.id)<=(m.created_at,m.id);
 if m.request_id is not null then select * into fr from solar_private.finance_requests f where f.request_id=m.request_id;actor:=fr.actor_id;end if;
 if m.id like 'tx:%' then
  select * into t from public.transactions where id=split_part(m.id,':',2)::bigint;actor:=t.created_by;
  document:=jsonb_build_object('kind',t.kind,'receiptNo',t.receipt_no,'paymentMode',t.payment_mode,'warehouse',t.warehouse_name);
  select coalesce(jsonb_agg(jsonb_build_object('name',i.product_name,'brand',solar_private.current_product_brand(i.product_id,i.brand_name),'category',i.category,
   'qty',i.qty,'price',i.price,'total',round(i.qty*i.price,2)) order by i.id),'[]') into items from public.transaction_items i where i.transaction_id=t.id;
 elsif m.id like 'entry:%' then
  select * into entry from public.solar_cash_entries where id=split_part(m.id,':',2)::uuid;actor:=entry.actor_id;
  if entry.transfer_id is not null then
   select * into handover from solar_private.cash_transfers where id=entry.transfer_id;
   transfer_info:=jsonb_build_object('sender',(select solar_private.user_name(display_name,username,honorific) from public.profiles where id=handover.sender_id),
    'recipient',(select solar_private.user_name(display_name,username,honorific) from public.profiles where id=handover.recipient_id),'amount',handover.amount,
    'expense',handover.expense,'expenseNote',handover.expense_note,'note',handover.notes,'status',handover.status,'decidedAt',handover.decided_at,
    'decidedBy',(select solar_private.user_name(display_name,username,honorific) from public.profiles where id=handover.decided_by));
  elsif entry.job_id is not null then
   select * into t from public.transactions where id=entry.job_id;
   document:=jsonb_build_object('kind',t.kind,'receiptNo',t.receipt_no,'warehouse',t.warehouse_name);
  elsif entry.deleted_job_id is not null then
   select (jsonb_populate_record(null::public.transactions,d.invoice)).* into t from solar_private.deleted_sales d where d.invoice_id=entry.deleted_job_id;
   document:=jsonb_build_object('kind',t.kind,'receiptNo',t.receipt_no,'warehouse',t.warehouse_name,'deleted',true);
  end if;
 end if;
 select solar_private.user_name(display_name,username,honorific),phone into actor_name,actor_phone from public.profiles where id=actor;
 if m.kind='cash_reconcile' then
  reconciliation:=solar_private.cash_reconciliation_info(m.request_id,m.owner_id);
  -- The saved reconciliation is authoritative even for legacy rows sharing a timestamp.
  if reconciliation is not null then balance_after:=(reconciliation->>('after'||m.currency))::numeric;end if;
 end if;
 if fr.payload->>'mode' in('buy_usd','sell_usd') and fr.response->>'ownerId'=m.owner_id::text then
  exchange_info:=jsonb_build_object('mode',fr.payload->>'mode','amount',fr.response->'amount','rate',fr.response->'rate',
   'beforeIQD',fr.response->'beforeIQD','afterIQD',fr.response->'afterIQD','beforeUSD',fr.response->'beforeUSD','afterUSD',fr.response->'afterUSD');
 end if;
 return jsonb_build_object('id',m.id,'ownerId',m.owner_id,'ownerName',m.owner_name,'currency',m.currency,'kind',m.kind,
  'date',m.created_at,'receiptNo',m.receipt_no,'delta',m.delta,'amount',abs(m.delta),'before',balance_after-m.delta,'after',balance_after,
  'party',m.party,'note',m.note,'sourceCurrency',m.source_currency,'sourceAmount',m.source_amount,'rate',m.rate,
  'actorName',actor_name,'actorPhone',actor_phone,'document',document,'items',items,'transfer',transfer_info,
  'reconciliation',reconciliation,'exchange',exchange_info);
end$function$;

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
 and(p.is_admin or t.created_by=p.id)
   and(coalesce(sale_kind,'')='' or t.kind=sale_kind)
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
end $function$;

CREATE OR REPLACE FUNCTION solar_private.sales_period(search_text text DEFAULT ''::text, sale_kind text DEFAULT ''::text, date_from date DEFAULT NULL::date, date_to date DEFAULT NULL::date, job_status text DEFAULT ''::text, owner_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
declare p public.profiles;result jsonb;show_remaining boolean;selected_user uuid;begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('installer','warehouse');
 if p.id is null then raise exception 'لا تملك صلاحية مبيعات الفترة' using errcode='42501';end if;
 if length(coalesce(search_text,''))>200 or coalesce(sale_kind,'') not in('','sale','system') or coalesce(job_status,'') not in('','none','pending','in_progress','completed','closed') or(date_from is not null and date_to is not null and date_from>date_to) then raise exception 'اختر فترة ونوع مبيعات صحيحين' using errcode='22023';end if;
 if owner_id is not null and not p.is_admin and owner_id<>p.id then raise exception 'يمكنك مشاهدة مبيعاتك فقط' using errcode='42501';end if;
 selected_user:=case when p.is_admin then owner_id else p.id end;
 if selected_user is not null and not exists(select 1 from public.profiles u where u.id=selected_user)then raise exception 'المستخدم غير متاح' using errcode='22023';end if;
 show_remaining:=p.is_admin or coalesce(p.permissions->>'stock','false')='true' or coalesce(p.permissions->>'stockMovement','false')='true' or coalesce(p.permissions->>'warehouse','false')='true' or coalesce(p.permissions->>'sale','false')='true' or coalesce(p.permissions->>'system','false')='true' or coalesce(p.permissions->>'purchase','false')='true';
 with permitted as materialized(
  select t.id,t.kind,t.created_at from public.transactions t where t.kind in('sale','system') and(selected_user is null or t.created_by=selected_user)
   and(p.is_admin or t.created_by=p.id)
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
end$function$;

CREATE OR REPLACE FUNCTION solar_private.sale_delete_data(invoice_id bigint)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
declare t public.transactions;line_data jsonb;cash_data jsonb;payments jsonb;refunds jsonb;blocked text;paid numeric;
begin
 select * into t from public.transactions where id=invoice_id and kind in('sale','system');
 if t.id is null or not solar_private.can_delete_sale(t.created_by) then raise exception 'Not permitted' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]')into line_data from public.transaction_items i where i.transaction_id=t.id;
 select coalesce(jsonb_agg(to_jsonb(e) order by e.id),'[]'),-coalesce(sum(e.delta),0)into cash_data,paid from public.solar_cash_entries e where e.job_id=t.id;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]')into payments from public.transactions x where x.system_invoice_id=t.id;
 select coalesce(jsonb_agg(jsonb_build_object('ownerId',r.owner_id,'name',solar_private.user_name(p.display_name,p.username,p.honorific),'amount',r.amount)order by r.owner_id),'[]')
 into refunds from(select e.owner_id,-sum(e.delta) amount from public.solar_cash_entries e where e.job_id=t.id group by e.owner_id having sum(e.delta)<0)r left join public.profiles p on p.id=r.owner_id;
 if t.profit_settlement_id is not null or t.profit_supplier_settlement_id is not null or exists(select 1 from solar_private.profit_checkpoints c where c.source_key='tx:'||t.id and c.value<>0)then
  blocked:='لا يمكن حذف وصل دخلت أرباحه في تسوية؛ راجع الإدارة لمعالجة التسوية أولًا.';
 elsif paid<0 or exists(select 1 from public.solar_cash_entries e where e.job_id=t.id group by e.owner_id having sum(e.delta)>0)then
  blocked:='لا يمكن حذف الوصل لوجود استرجاع مصاريف غير متوازن؛ راجع الإدارة أولًا.';
 elsif exists(select 1 from public.transaction_items i where i.transaction_id=t.id and(i.product_id is null or i.qty is null or i.qty<=0))then
  blocked:='لا يمكن حذف الفاتورة لوجود مادة محذوفة أو كمية غير صحيحة؛ راجع المواد أولًا.';
 end if;
 return jsonb_build_object('receiptNo',t.receipt_no,'token',md5(to_jsonb(t)::text||line_data::text||cash_data::text||payments::text),
  'party',t.party_name,'total',t.total,'kind',t.kind,'blockedReason',blocked,'expenseRefund',paid,'expenseRefunds',refunds,
  'retainedPayments',jsonb_array_length(payments));
end $function$;

CREATE OR REPLACE FUNCTION solar_private.sale_delete(invoice_id bigint,expected_token text)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
declare t public.transactions;preview jsonb;line_data jsonb;archived jsonb;nid uuid;target uuid;
begin
 if solar_private.role_name()='warehouse' then raise exception 'Not permitted' using errcode='42501';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into t from public.transactions where id=invoice_id and kind in('sale','system')for update;
 if t.id is null then
  select invoice into archived from solar_private.deleted_sales d where d.invoice_id=sale_delete.invoice_id;
  if archived is not null and solar_private.can_delete_sale((archived->>'created_by')::uuid)then return;end if;
  raise exception 'Not permitted' using errcode='42501';
 end if;
 preview:=solar_private.sale_delete_data(t.id);
 if preview->>'token' is distinct from expected_token then raise exception 'Invoice changed' using errcode='PT409';end if;
 if preview->>'blockedReason' is not null then raise exception '%',preview->>'blockedReason';end if;
 select coalesce(jsonb_agg(to_jsonb(i)order by i.id),'[]')into line_data from public.transaction_items i where i.transaction_id=t.id;
 insert into solar_private.deleted_sales(invoice_id,invoice,items,deleted_by)
 values(t.id,to_jsonb(t)||jsonb_build_object('_cashEntriesBeforeDeletion',
  (select coalesce(jsonb_agg(to_jsonb(e)order by e.id),'[]')from public.solar_cash_entries e where e.job_id=t.id),
  '_linkedPayments',(select coalesce(jsonb_agg(to_jsonb(x)order by x.id),'[]')from public.transactions x where x.system_invoice_id=t.id)),line_data,auth.uid());
 -- Refund original payers before detaching the balanced entries for the audit.
 perform solar_private.post_installation_cash(t.id,0,auth.uid());
 if exists(select 1 from public.solar_cash_entries e where e.job_id=t.id group by e.owner_id having sum(e.delta)<>0)then
  raise exception 'تعذر موازنة مصاريف الوصل؛ لم يتم الحذف';
 end if;
 update public.solar_cash_entries set deleted_job_id=t.id,job_id=null where job_id=t.id;
 -- Collections stay in the same customer's account and the same cashier's box.
 update public.transactions set system_invoice_id=null where system_invoice_id=t.id;
 update public.products p set qty=coalesce(p.qty,0)+x.qty from(select i.product_id,sum(i.qty)qty from public.transaction_items i where i.transaction_id=t.id group by i.product_id)x where p.id=x.product_id;
 delete from public.cash_ledger where transaction_id=t.id;
 delete from public.transactions where id=t.id;
 for target in select distinct x from unnest(array[t.installer_id,t.created_by])x where x is not null and x<>auth.uid()loop
  if exists(select 1 from public.profiles p where p.id=target and p.active)then
   insert into public.solar_notifications(user_id,event,title,body)values(target,'invoice_deleted','تم حذف فاتورة مرتبطة بك','تم حذف الفاتورة #'||t.receipt_no::text||' وإلغاء تكليف التنصيب المرتبط بها إن وجد.')returning id into nid;
   insert into solar_private.push_deliveries(notification_id,endpoint)select nid,s.endpoint from public.solar_push_subscriptions s where s.user_id=target;
  end if;
 end loop;
 perform solar_private.wake_push();
end $function$;

notify pgrst,'reload schema';
