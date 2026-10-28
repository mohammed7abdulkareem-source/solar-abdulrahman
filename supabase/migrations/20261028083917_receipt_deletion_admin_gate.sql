-- Only an active financial administrator can execute a receipt deletion.
-- Office users will submit requests; their requests have no accounting effect.
CREATE OR REPLACE FUNCTION solar_private.customer_payment_manage(action text, request_id uuid DEFAULT NULL::uuid, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
#variable_conflict use_variable
declare p public.profiles;t public.transactions;c public.customers;prior solar_private.finance_requests;
 rows jsonb;result jsonb;ledger jsonb;balance numeric;cash_before numeric;cash_after numeric;new_total numeric;amount numeric;token text;uid uuid;cid bigint;page_offset integer;search text;
begin
 if action='delete' and not exists(select 1 from public.profiles a where a.id=auth.uid() and a.active and a.is_admin and a.user_type not in('warehouse','installer'))then raise exception 'لا يمكن حذف الوصل قبل موافقة الإدارة' using errcode='42501';end if;
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'customerPayment','false')='true') then raise exception 'لا تملك صلاحية تسديد الجملة' using errcode='42501';end if;
 if action is null or action not in ('list','get','update','delete') or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب غير صحيح';end if;
 if action='list' then
  page_offset:=greatest(0,least(coalesce((payload->>'offset')::integer,0),1000000));search:=solar_private.customer_name_key(coalesce(payload->>'query',''));
  select coalesce(jsonb_agg(v.row order by v.created_at desc,v.id desc),'[]') into rows from (
   select tx.id,tx.created_at,jsonb_build_object('id',tx.id,'receiptNo',tx.receipt_no,'date',tx.created_at,'party',cu.name,'customerId',cu.id,'total',tx.total,'cash',tx.cash,'notes',tx.notes,'mode',tx.payment_mode,
    'cashOwnerName',coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'غير مخصص'),'canManage',p.is_admin or coalesce(tx.cashbox_user_id,tx.created_by)=p.id) row
   from public.transactions tx join solar_private.customer_movement_links() l on l.transaction_id=tx.id join public.customers cu on cu.id=l.customer_id left join public.profiles o on o.id=coalesce(tx.cashbox_user_id,tx.created_by)
   where tx.kind='customer_payment' and cu.customer_type='wholesale' and coalesce(tx.payment_mode,'') not in ('opening_balance','account_reconciliation')
    and (p.is_admin or cu.owner_id=p.id) and (payload->>'customerId' is null or cu.id=(payload->>'customerId')::bigint)
    and (search='' or strpos(solar_private.customer_name_key(cu.name||coalesce(tx.notes,'')||coalesce(tx.receipt_no::text,tx.id::text)),search)>0)
   order by tx.created_at desc,tx.id desc limit 51 offset page_offset
  ) v;
  return jsonb_build_object('rows',rows,'offset',page_offset);
 end if;
 if action in ('update','delete') then
  if request_id is null then raise exception 'رقم طلب الحفظ مطلوب';end if;
  perform pg_advisory_xact_lock(7311,1);
  select * into prior from solar_private.finance_requests r where r.request_id=customer_payment_manage.request_id;
  if found then
   if prior.actor_id=p.id and prior.action='customer_payment_'||action and prior.payload=payload then return prior.response;end if;
   raise exception 'طلب مكرر ببيانات مختلفة' using errcode='PT409';
  end if;
 end if;
 select * into t from public.transactions where id=(payload->>'id')::bigint for update;
 if t.id is null or t.kind<>'customer_payment' or coalesce(t.payment_mode,'') in ('opening_balance','account_reconciliation') then raise exception 'التسديد غير موجود أو هو رصيد افتتاحي؛ حدّث القائمة' using errcode='PT409';end if;
 select l.customer_id into cid from solar_private.customer_movement_links() l where l.transaction_id=t.id;
 select * into c from public.customers where id=cid and customer_type='wholesale';
 uid:=coalesce(t.cashbox_user_id,t.created_by);
 if c.id is null or (not p.is_admin and (c.owner_id is distinct from p.id or uid is distinct from p.id)) then raise exception 'تعديل وحذف هذا الوصل متاح لصاحب القاصة أو الأدمن فقط' using errcode='42501';end if;
 if uid is null or t.cash_currency<>'IQD' or t.fx_accounted or t.system_invoice_id is not null or t.finance_request_id is not null or not((t.cash and t.total>0) or(not t.cash and t.total<0)) then raise exception 'هذا الوصل يحتاج مراجعة مالية مستقلة';end if;
 ledger:=solar_private.customer_ledger(c.id);select coalesce(sum((x->>'effect')::numeric),0) into balance from jsonb_array_elements(ledger) x;
 token:=md5(to_jsonb(t)::text||ledger::text);cash_before:=solar_private.cash_balance(uid);
 if action='get' then
  return jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'date',t.created_at,'party',c.name,'customerId',c.id,'total',t.total,'cash',t.cash,'mode',t.payment_mode,'notes',t.notes,'token',token,'balance',balance,'cashBalance',cash_before,'cashOwnerName',(select coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'') from public.profiles o where o.id=uid));
 end if;
 if payload->>'expectedToken' is distinct from token then raise exception 'تغير الوصل أو حساب العميل؛ افتح التعديل مجدداً' using errcode='PT409';end if;
 if action='update' then
  amount:=(payload->>'amount')::numeric;
  if amount is null or not(amount>0 and amount<=1000000000000) or amount::text in ('NaN','Infinity','-Infinity') or round(amount,2)<>amount or length(coalesce(payload->>'notes',''))>2000 then raise exception 'أدخل مبلغاً صحيحاً وملاحظات لا تتجاوز 2000 حرف';end if;
  new_total:=case when t.cash then amount else -amount end;
  if t.cash and new_total>t.total and balance+t.total-new_total<0 then raise exception 'المبلغ أكبر من الرصيد المتاح للتسديد';end if;
 else new_total:=0;end if;
 cash_after:=cash_before+case when t.cash then new_total-t.total else 0 end;
 if t.cash and cash_after<0 then raise exception 'رصيد قاصة صاحب الوصل لا يكفي لعكس هذا التسديد؛ أعد المبلغ للقاصة أولاً' using errcode='P0002';end if;
 if exists(select 1 from public.cash_ledger where transaction_id=t.id) or exists(select 1 from public.transaction_items where transaction_id=t.id) or exists(select 1 from public.solar_cash_entries where job_id=t.id) then raise exception 'الوصـل مرتبط بحركة أخرى ويحتاج مراجعة مستقلة';end if;
 if action='update' then
  update public.transactions set total=new_total,notes=coalesce(payload->>'notes','') where id=t.id;
 else delete from public.transactions where id=t.id;end if;
 insert into solar_private.receipt_change_audit(request_id,actor_id,transaction_id,action,before_row,after_row)
 values(request_id,p.id,t.id,'customer_payment_'||action,to_jsonb(t),(select to_jsonb(n) from public.transactions n where n.id=t.id));
 result:=jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'party',c.name,'total',new_total,'oldBalance',balance,'remaining',balance+t.total-new_total,'cashBefore',cash_before,'cashAfter',solar_private.cash_balance(uid),'action',action);
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response) values(request_id,p.id,'customer_payment_'||action,payload,result);
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
 if not exists(select 1 from public.profiles a where a.id=auth.uid() and a.active and a.is_admin and a.user_type not in('warehouse','installer'))then raise exception 'لا يمكن حذف الوصل قبل موافقة الإدارة' using errcode='42501';end if;
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

CREATE OR REPLACE FUNCTION solar_private.sale_delete(invoice_id bigint, expected_token text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t public.transactions;preview jsonb;line_data jsonb;archived jsonb;nid uuid;target uuid;
begin
 if not exists(select 1 from public.profiles a where a.id=auth.uid() and a.active and a.is_admin and a.user_type not in('warehouse','installer'))then raise exception 'لا يمكن حذف الوصل قبل موافقة الإدارة' using errcode='42501';end if;
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

CREATE OR REPLACE FUNCTION solar_private.supplier_payment_manage(action text, request_id uuid DEFAULT NULL::uuid, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
#variable_conflict use_variable
declare actor public.profiles;t public.transactions;s public.suppliers;e solar_private.supplier_fx_entries;w solar_private.wallet_fx_entries;prior solar_private.finance_requests;
 uid uuid;rows jsonb;ledger jsonb;wallet jsonb;balance numeric;cash_balance numeric;token text;search text;page_offset integer;amount numeric;rate numeric;new_id bigint;result jsonb;replacement jsonb;cancel_note text;notes_only boolean:=false;
begin
 if action='delete' and not exists(select 1 from public.profiles a where a.id=auth.uid() and a.active and a.is_admin and a.user_type not in('warehouse','installer'))then raise exception 'لا يمكن حذف الوصل قبل موافقة الإدارة' using errcode='42501';end if;
 select * into actor from public.profiles where id=auth.uid() and active;
 if actor.id is null or actor.user_type in('installer','warehouse') or not(actor.is_admin or coalesce(actor.permissions->>'supplierPayment','false')='true') then raise exception 'لا تملك صلاحية تسديد المورد' using errcode='42501';end if;
 if action is null or action not in('list','get','update','delete') or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب غير صحيح';end if;
 if action='list' then
  search:=solar_private.customer_name_key(coalesce(payload->>'query',''));page_offset:=greatest(0,least(coalesce((payload->>'offset')::integer,0),1000000));
  select coalesce(jsonb_agg(v.row order by v.created_at desc,v.id desc),'[]') into rows from(
   select tx.id,tx.created_at,jsonb_build_object('id',tx.id,'receiptNo',tx.receipt_no,'date',tx.created_at,'party',tx.party_name,'cash',tx.cash,'amount',abs(coalesce(tx.source_subtotal,tx.total)),'currency',tx.source_currency,'notes',tx.notes,'cashOwnerName',coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'غير مخصص')) row
   from public.transactions tx left join public.profiles o on o.id=coalesce(tx.cashbox_user_id,tx.created_by)
   where tx.kind='supplier_payment' and tx.supplier_payment_voided_at is null and(actor.is_admin or coalesce(tx.cashbox_user_id,tx.created_by)=actor.id)
    and(search='' or strpos(solar_private.customer_name_key(coalesce(tx.party_name,'')||coalesce(tx.notes,'')||coalesce(tx.receipt_no::text,tx.id::text)),search)>0)
   order by tx.created_at desc,tx.id desc limit 51 offset page_offset
  )v;return jsonb_build_object('rows',rows);
 end if;
 if action in('update','delete') then
  if request_id is null then raise exception 'رقم طلب الحفظ مطلوب';end if;
  perform pg_advisory_xact_lock(7311,1);
  select * into prior from solar_private.finance_requests f where f.request_id=supplier_payment_manage.request_id;
  if found then
   if prior.actor_id=actor.id and prior.action='supplier_payment_'||action and prior.payload=payload then return prior.response;end if;
   raise exception 'طلب مكرر ببيانات مختلفة' using errcode='PT409';
  end if;
 end if;
 select * into t from public.transactions where id=(payload->>'id')::bigint for update;
 if t.id is null or t.kind<>'supplier_payment' or t.supplier_payment_voided_at is not null then raise exception 'الوصل غير موجود أو ملغى؛ حدّث السجل' using errcode='PT409';end if;
 uid:=coalesce(t.cashbox_user_id,t.created_by);
 if uid is null or not(actor.is_admin or uid=actor.id) then raise exception 'هذا الوصل لصاحب القاصة أو الأدمن فقط' using errcode='42501';end if;
 if action in('update','delete') and t.profit_supplier_settlement_id is not null then raise exception 'هذه الإضافة مرتبطة بتسوية أرباح محفوظة؛ لا تعدّلها كوصل مورد مستقل' using errcode='42501';end if;
 select * into e from solar_private.supplier_fx_entries where transaction_id=t.id;
 select * into s from public.suppliers where id=e.supplier_id;
 if e.id is null or s.id is null then raise exception 'الوصـل غير مرتبط بحساب مورد؛ يحتاج مطابقة قبل التعديل';end if;
 if e.revision<>s.currency_revision or e.currency<>s.account_currency then raise exception 'الوصـل من عملة حساب سابقة؛ استخدم حركة تصحيح بعملة الحساب الحالية';end if;
 if not((t.cash and t.total>0) or(not t.cash and t.total<0)) or exists(select 1 from public.transaction_items where transaction_id=t.id) or exists(select 1 from public.cash_ledger where transaction_id=t.id) then raise exception 'نوع الوصل يحتاج مراجعة مستقلة';end if;
 select * into w from solar_private.wallet_fx_entries where transaction_id=t.id;
 if t.cash and t.cash_currency='USD' and w.id is null then raise exception 'قيد قاصة الدولار غير موجود لهذا الوصل';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'),coalesce(sum(x.delta),0) into ledger,balance from solar_private.supplier_fx_entries x where x.supplier_id=s.id and x.revision=s.currency_revision and(actor.is_admin or x.owner_id=actor.id);
 wallet:=solar_private.usd_wallet(uid);cash_balance:=case when t.cash_currency='USD' then(wallet->>'amount')::numeric else solar_private.cash_balance(uid) end;
 token:=md5(to_jsonb(t)::text||ledger::text||wallet::text||cash_balance::text);
 if action='get' then return jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'party',s.name,'cash',t.cash,'currency',t.source_currency,'amount',abs(coalesce(t.source_subtotal,t.total)),'rate',t.market_rate,'accountCurrency',s.account_currency,'accountAmount',-e.delta,'balance',balance,'cashCurrency',t.cash_currency,'cashAmount',case when t.cash then case when t.cash_currency='USD' then t.cash_amount else t.total end else 0 end,'cashBalance',cash_balance,'cashOwnerName',(select coalesce(solar_private.user_name(display_name,username,honorific),'مستخدم') from public.profiles where id=uid),'notes',t.notes,'token',token);end if;
 if payload->>'expectedToken' is distinct from token then raise exception 'تغيّر الوصل أو الرصيد؛ افتح العملية مجدداً' using errcode='PT409';end if;
 if length(coalesce(payload->>'notes',''))>2000 then raise exception 'الملاحظات طويلة';end if;
 if action='update' then
  amount:=(payload->>'amount')::numeric;
  if amount is null or not(amount>0 and amount<=1000000000000) or amount::text in('NaN','Infinity','-Infinity') or round(amount,2)<>amount then raise exception 'أدخل مبلغاً صحيحاً أكبر من صفر وبحد أقصى منزلتين';end if;
  rate:=solar_private.fx_rate((payload->>'rate')::numeric,t.market_rate);
  new_id:=solar_private.next_transaction_id();
 end if;
 notes_only:=action='update' and amount=abs(coalesce(t.source_subtotal,t.total)) and rate=t.market_rate;
 if notes_only then
  perform set_config('solar.fx_context',jsonb_build_object('marketRate',t.market_rate,'accountRevision',s.currency_revision,'cashCurrency',t.cash_currency)::text,true);
  update public.transactions set notes=coalesce(payload->>'notes','') where id=t.id;
  perform set_config('solar.fx_context','',true);
  replacement:=solar_private.supplier_payment_get(t.id);
 else
 cancel_note:=case action when 'update' then 'إلغاء أثر الوصل للتعديل #' else 'إلغاء تسديد مورد #' end||coalesce(t.receipt_no::text,t.id::text)||' · '||solar_private.user_name(actor.display_name,actor.username,actor.honorific);
 insert into solar_private.supplier_fx_entries(supplier_id,owner_id,currency,revision,delta,book_delta,gain,rate,note,correction_for)
 values(e.supplier_id,e.owner_id,e.currency,e.revision,-e.delta,-e.book_delta,-e.gain,e.rate,cancel_note,t.id);
 if t.cash then
  insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,gain,entry_type,note)
  values(uid,t.cash_currency,case when t.cash_currency='USD' then -w.delta else t.total end,case when t.cash_currency='USD' then -w.book_delta else t.total end,t.market_rate,case when t.cash_currency='USD' then -w.gain else 0 end,'supplier_payment_refund',cancel_note);
 end if;
 update public.transactions set supplier_payment_voided_at=now(),supplier_payment_replaced_by=new_id where id=t.id;
 if action='update' then
  perform set_config('solar.fx_context',jsonb_build_object('marketRate',rate,'accountRevision',s.currency_revision,'cashCurrency',t.cash_currency)::text,true);
  insert into public.transactions(id,kind,party_type,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,notes,source_currency,exchange_rate,source_subtotal)
  values(new_id,'supplier_payment','supplier',s.id,s.name,round(amount*case when t.source_currency='USD' then rate else 1 end,2)*case when t.cash then 1 else -1 end,t.cash,t.payment_mode,t.created_by,uid,coalesce(payload->>'notes',''),t.source_currency,case when t.source_currency='USD' then rate else 1 end,amount*case when t.cash then 1 else -1 end);
  perform set_config('solar.fx_context','',true);
  replacement:=solar_private.supplier_payment_get(new_id);
 end if;
 end if;
 result:=jsonb_build_object('id',t.id,'action',action,'notesOnly',notes_only,'replacement',replacement,'party',s.name,'accountCurrency',s.account_currency,'balance',(select coalesce(sum(x.delta),0) from solar_private.supplier_fx_entries x where x.supplier_id=s.id and x.revision=s.currency_revision and(actor.is_admin or x.owner_id=actor.id)),'cashCurrency',t.cash_currency,'cashBalance',case when t.cash_currency='USD' then(solar_private.usd_wallet(uid)->>'amount')::numeric else solar_private.cash_balance(uid) end);
 insert into solar_private.receipt_change_audit(request_id,actor_id,transaction_id,action,before_row,after_row) values(request_id,actor.id,t.id,'supplier_payment_'||action,jsonb_build_object('transaction',to_jsonb(t),'accountEntry',to_jsonb(e),'walletEntry',to_jsonb(w)),result);
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response) values(request_id,actor.id,'supplier_payment_'||action,payload,result);
 return result;
end $function$;
