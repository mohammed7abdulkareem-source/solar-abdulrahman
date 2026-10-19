-- Profit requests are independent of cash balances. An approval atomically
-- debits the request owner's IQD cashbox and adds the remainder to a supplier debt.
-- Existing approved settlements and financial amounts are left untouched.
alter table solar_private.profit_settlements
 add column settlement_model text,
 add column supplier_id bigint references public.suppliers(id) on delete set null,
 add column supplier_amount_iqd numeric,
 add column supplier_currency text check(supplier_currency in('IQD','USD')),
 add column supplier_amount numeric,
 add column supplier_rate numeric,
 add column supplier_receipt jsonb;
alter table public.transactions add column profit_supplier_settlement_id uuid references solar_private.profit_settlements(id),add column profit_supplier_owner_id uuid references public.profiles(id);
create index profit_supplier_owner_idx on public.transactions(profit_supplier_owner_id) where profit_supplier_owner_id is not null;
create unique index profit_supplier_allocation_once on public.transactions(profit_supplier_settlement_id) where profit_supplier_settlement_id is not null;
create index profit_settlements_supplier on solar_private.profit_settlements(supplier_id) where supplier_id is not null;
create function solar_private.profit_supplier_accounts() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'currency',s.account_currency,'revision',s.currency_revision,'balance',b.amount,'bookBalance',b.book,
  'rate',case when s.account_currency='USD' then (select rate from solar_private.exchange_settings where id) else 1 end,
  'token',md5(jsonb_build_object('supplier',to_jsonb(s),'balance',b.amount,'book',b.book)::text)) order by s.name),'[]')
 from public.suppliers s cross join lateral(select coalesce(sum(delta),0) amount,coalesce(sum(book_delta),0) book from solar_private.supplier_fx_entries where supplier_id=s.id and revision=s.currency_revision)b
 where s.active and exists(select 1 from public.profiles where id=auth.uid() and active and is_admin and user_type not in('installer','warehouse'))
$$;
revoke all on function solar_private.profit_supplier_accounts() from public,anon,authenticated;
create or replace function solar_private.profit_expense_guard() returns trigger language plpgsql set search_path='' as $$begin
 if current_user in('authenticated','anon') and(new.profit_settlement_id is not null or new.profit_supplier_settlement_id is not null or new.profit_supplier_owner_id is not null or(tg_op='UPDATE' and(old.profit_settlement_id is not null or old.profit_supplier_settlement_id is not null))) then raise exception 'استخدم تسوية الأرباح المحمية' using errcode='42501';end if;
 return new;
end $$;
-- Use the durable outbox for mobile push as well as the in-app inbox.
create function solar_private.profit_notice(recipient uuid,event_name text,heading text,detail text) returns void language plpgsql security definer set search_path='' as $$
declare nid uuid;begin
 if not exists(select 1 from public.profiles where id=recipient and active and user_type not in('installer','warehouse')) then return;end if;
 insert into public.solar_notifications(user_id,event,title,body) values(recipient,event_name,heading,detail) returning id into nid;
 insert into solar_private.push_deliveries(notification_id,endpoint) select nid,endpoint from public.solar_push_subscriptions where user_id=recipient;
end$$;
revoke all on function solar_private.profit_notice(uuid,text,text,text) from public,anon,authenticated;
create or replace function solar_private.profit_workspace(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
#variable_conflict use_variable
declare p public.profiles;r solar_private.profit_settlements;prior solar_private.finance_requests;uid uuid;start_date date;end_date date;
 snapshot jsonb;rows jsonb;result jsonb;amount numeric;total numeric;token text;cash jsonb;cash_owner uuid;expense_id bigint;item jsonb;reason text;supplier public.suppliers;destination jsonb;remainder numeric;addition jsonb;rate numeric;before_cash numeric;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'profit','false')='true' or coalesce(p.permissions->>'profitSettlement','false')='true') then raise exception 'لا تملك صلاحية الأرباح' using errcode='42501';end if;
 if action is null or action not in('overview','request','approve','reject','cancel') or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب غير صحيح';end if;
 uid:=coalesce(nullif(payload->>'ownerId','')::uuid,p.id);
 if not p.is_admin and uid<>p.id then raise exception 'يمكنك مشاهدة أرباحك فقط' using errcode='42501';end if;
 if action='overview' or action='request' then
  if not exists(select 1 from public.profiles where id=uid and user_type not in('installer','warehouse')) then raise exception 'المستخدم غير موجود';end if;
  start_date:=nullif(payload->>'from','')::date;end_date:=coalesce(nullif(payload->>'to','')::date,(now() at time zone 'Asia/Baghdad')::date);
  if start_date>end_date or end_date>(now() at time zone 'Asia/Baghdad')::date then raise exception 'اختر فترة صحيحة حتى اليوم';end if;
 end if;
 if action<>'overview' then
  if request_id is null then raise exception 'رقم الطلب مطلوب';end if;
  perform pg_advisory_xact_lock(7311,1);
  select * into prior from solar_private.finance_requests f where f.request_id=profit_workspace.request_id;
  if found then
   if prior.actor_id=p.id and prior.action='profit_'||action and prior.payload=payload then return prior.response;end if;
   raise exception 'طلب مكرر ببيانات مختلفة' using errcode='40001';
  end if;
 end if;
 if action in('overview','request') then
  snapshot:=solar_private.profit_snapshot(uid,start_date,end_date);token:=md5(snapshot::text);
  select coalesce(sum((x->>'available')::numeric),0) into total from jsonb_array_elements(snapshot)x;
 end if;
 if action='overview' then
  select coalesce(jsonb_agg(to_jsonb(s)||case when not p.is_admin and s.supplier_receipt is not null then jsonb_build_object('supplier_receipt',null) else '{}'::jsonb end||jsonb_build_object('ownerName',coalesce(o.display_name,o.username),'decidedByName',coalesce(d.display_name,d.username),'token',md5(to_jsonb(s)::text)) order by s.created_at desc),'[]') into rows
  from solar_private.profit_settlements s join public.profiles o on o.id=s.owner_id left join public.profiles d on d.id=s.decided_by
  where (p.is_admin or s.owner_id=p.id) and(s.status='pending' or s.id in(select q.id from solar_private.profit_settlements q where(p.is_admin or q.owner_id=p.id) order by q.created_at desc limit 100));
  return jsonb_build_object('rows',snapshot,'available',total,'token',token,'from',start_date,'to',end_date,'ownerId',uid,
   'ownerName',(select coalesce(display_name,username) from public.profiles where id=uid),'canRequest',p.is_admin or p.permissions->>'profitSettlement'='true','requests',rows,
   'settlementModel','owner_debit_supplier_charge','suppliers',case when p.is_admin then solar_private.profit_supplier_accounts() else '[]'::jsonb end,'cashOwners',case when p.is_admin then(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'name',coalesce(o.display_name,o.username),'balance',solar_private.cash_balance(o.id)) order by o.display_name),'[]') from public.profiles o where o.active and o.user_type not in('installer','warehouse')) else '[]'::jsonb end);
 elsif action='request' then
  if not(p.is_admin or coalesce(p.permissions->>'profitSettlement','false')='true') then raise exception 'لا تملك صلاحية طلب تسوية الأرباح' using errcode='42501';end if;
  if payload->>'expectedToken' is distinct from token then raise exception 'تغيّرت الأرباح؛ حدّث الكشف قبل الطلب' using errcode='40001';end if;
  if total<=0 then raise exception 'لا توجد أرباح موجبة غير مسوّاة ضمن الفترة';end if;
  if exists(select 1 from solar_private.profit_settlements where owner_id=uid and status='pending') then raise exception 'لديك طلب قيد المراجعة؛ انتظر القرار أو ألغِ الطلب السابق';end if;
  if length(coalesce(payload->>'note',''))>2000 then raise exception 'الملاحظة طويلة';end if;
  insert into solar_private.profit_settlements(id,owner_id,date_from,date_to,snapshot,profit,note) values(request_id,uid,start_date,end_date,snapshot,total,coalesce(payload->>'note','')) returning * into r;
  perform solar_private.profit_notice(o.id,'profit_requested','طلب تسوية أرباح',(select coalesce(display_name,username) from public.profiles where id=uid)||' · أرباح الفترة: '||total::text||' د.ع') from public.profiles o where o.active and o.is_admin and o.user_type not in('installer','warehouse');
 else
  select * into r from solar_private.profit_settlements where id=(payload->>'id')::uuid for update;
  if r.id is null or(not p.is_admin and r.owner_id<>p.id) then raise exception 'لا تملك صلاحية هذا الطلب' using errcode='42501';end if;
  if action in('approve','reject') and not p.is_admin then raise exception 'الموافقة والرفض للإدارة فقط' using errcode='42501';end if;
  if r.status<>'pending' then raise exception 'تم حسم الطلب سابقاً؛ حدّث القائمة' using errcode='40001';end if;
  if payload->>'expectedToken' is distinct from md5(to_jsonb(r)::text) then raise exception 'تغيّر الطلب؛ افتحه مجدداً' using errcode='40001';end if;
  reason:=trim(coalesce(payload->>'note',''));
  if length(reason)>2000 then raise exception 'الملاحظة طويلة';end if;
  if action='approve' then
   if coalesce(payload->>'collectionConfirmed','false')<>'true' then raise exception 'أكد مراجعة التحصيل قبل الصرف';end if;
   if not exists(select 1 from public.profiles where id=r.owner_id and active and user_type not in('installer','warehouse')) then raise exception 'المستخدم موقوف؛ راجع حسابه قبل التسوية';end if;
   -- New business after the request stays open for the next settlement.
   -- Every original source must still match the reviewed snapshot exactly.
   select coalesce(jsonb_agg(x order by x->>'date',x->>'key'),'[]') into snapshot
   from jsonb_array_elements(solar_private.profit_snapshot(r.owner_id,r.date_from,r.date_to))x
   where exists(select 1 from jsonb_array_elements(r.snapshot)y where y->>'key'=x->>'key');
   if snapshot is distinct from r.snapshot then raise exception 'تغيّرت أرباح الفترة بعد الطلب؛ ارفض الطلب ليصدر كشف وطلب جديدان' using errcode='40001';end if;
   if payload->>'settlementModel' is distinct from 'owner_debit_supplier_charge' then raise exception 'حدّث البرنامج لمراجعة توزيع الأرباح قبل الموافقة' using errcode='PT409';end if;
   amount:=(payload->>'share')::numeric;cash_owner:=r.owner_id;
   if nullif(payload->>'cashOwnerId','')::uuid is not null and (payload->>'cashOwnerId')::uuid<>r.owner_id then raise exception 'حصة المستخدم تخصم من قاصته حصراً' using errcode='42501';end if;
   if amount is null or not(amount>0 and amount<=r.profit and amount<=1000000000000) or amount::text in('NaN','Infinity','-Infinity') or round(amount)<>amount then raise exception 'حدد حصة موجبة بالدينار لا تتجاوز ربح الطلب';end if;
   remainder:=r.profit-amount;addition:=null;destination:=null;rate:=1;
   if remainder>0 then
    select * into supplier from public.suppliers where id=(payload->>'supplierId')::bigint and active for update;
    if supplier.id is null then raise exception 'اختر المورد الذي تضاف له بقية الأرباح';end if;
    select value into destination from jsonb_array_elements(solar_private.profit_supplier_accounts()) where (value->>'id')::bigint=supplier.id;
    if payload->>'supplierToken' is distinct from destination->>'token' then raise exception 'تغيّر حساب المورد؛ حدّث المعاينة قبل الموافقة' using errcode='PT409';end if;
    rate:=(destination->>'rate')::numeric;
    if supplier.account_currency='USD' and (payload->>'supplierRate')::numeric is distinct from rate then raise exception 'تغيّر سعر الصرف؛ راجع المعاينة مجددًا' using errcode='PT409';end if;
    if supplier.account_currency='USD' and round(remainder/rate,2)=0 then raise exception 'بقية الأرباح أصغر من سنت في حساب المورد؛ راجع حصة المستخدم';end if;
   end if;
   before_cash:=solar_private.cash_balance(cash_owner);expense_id:=solar_private.next_transaction_id();
   -- This is an approved profit entitlement debit, independent of cash on hand.
   -- Ordinary cash withdrawals retain their existing sufficient-balance checks.
   insert into public.transactions(id,kind,total,cash,created_by,cashbox_user_id,notes,cash_currency,cash_amount,source_currency,source_subtotal,exchange_rate,market_rate,fx_accounted,capital_effect,cash_purpose,finance_request_id,profit_settlement_id)
   values(expense_id,'cash_expense',amount,true,p.id,cash_owner,left('حصة أرباح '||(select coalesce(display_name,username) from public.profiles where id=r.owner_id)||' · تسوية '||r.id::text||case when reason='' then '' else ' · '||reason end,2000),'IQD',amount,'IQD',amount,1,1,true,false,'expense',request_id,r.id);
   cash:=jsonb_build_object('id',expense_id,'receiptNo',(select receipt_no from public.transactions where id=expense_id),'date',now(),'requestId',request_id,'mode','expense','currency','IQD','amount',amount,'ownerId',cash_owner,
    'ownerName',(select coalesce(display_name,username) from public.profiles where id=cash_owner),'beforeIQD',before_cash,'afterIQD',solar_private.cash_balance(cash_owner),'settlementModel','owner_debit_supplier_charge');
   if remainder>0 then
    addition:=solar_private.fx('payment',gen_random_uuid(),jsonb_build_object('paymentId',solar_private.next_transaction_id(),'supplierId',supplier.id,'amount',remainder,'currency','IQD','rate',rate,'accountRevision',supplier.currency_revision,'mode','charge_other',
     'note','إضافة بقية أرباح '||(select coalesce(display_name,username) from public.profiles where id=r.owner_id)||' · تسوية '||r.id::text));
    perform set_config('solar.fx_context',jsonb_build_object('marketRate',rate,'accountRevision',supplier.currency_revision,'cashCurrency','IQD')::text,true);
    update public.transactions set profit_supplier_settlement_id=r.id,profit_supplier_owner_id=r.owner_id where id=(addition->>'id')::bigint;
    perform set_config('solar.fx_context','',true);
   end if;
   for item in select * from jsonb_array_elements(r.snapshot) loop
    insert into solar_private.profit_checkpoints(owner_id,source_key,value,row_data,settlement_id) values(r.owner_id,item->>'key',(item->>'value')::numeric,item,r.id)
    on conflict(owner_id,source_key) do update set value=excluded.value,row_data=excluded.row_data,settlement_id=excluded.settlement_id;
   end loop;
   update solar_private.profit_settlements set status='approved',decided_at=now(),decided_by=p.id,decision_note=reason,share=amount,cash_owner_id=cash_owner,receipt=cash,settlement_model='owner_debit_supplier_charge',supplier_id=case when remainder>0 then supplier.id end,supplier_amount_iqd=remainder,supplier_currency=case when remainder>0 then supplier.account_currency end,supplier_amount=case when remainder>0 then abs((addition->>'accountAmount')::numeric) else 0 end,supplier_rate=rate,supplier_receipt=case when remainder>0 then jsonb_build_object('id',addition->'id','receiptNo',addition->'receiptNo','name',supplier.name,'currency',supplier.account_currency,'amount',abs((addition->>'accountAmount')::numeric),'beforeBalance',(destination->>'balance')::numeric,'afterBalance',(addition->'accountContext'->>'balance')::numeric,'amountIQD',remainder,'rate',rate) end where id=r.id returning * into r;
  else
   if action='reject' and reason='' then raise exception 'اكتب سبب رفض الطلب';end if;
   update solar_private.profit_settlements set status=case action when 'cancel' then 'cancelled' else 'rejected' end,decided_at=now(),decided_by=p.id,decision_note=reason where id=r.id returning * into r;
  end if;
  perform solar_private.profit_notice(r.owner_id,'profit_decided',case r.status when 'approved' then 'تمت تسوية أرباحك وتسجيل حصتك' when 'rejected' then 'تم رفض طلب تسوية الأرباح' else 'تم إلغاء طلب تسوية الأرباح' end,case when r.status='approved' then 'حصتك: '||r.share::text||' د.ع · رصيد قاصتك بعد التسوية: '||solar_private.cash_balance(r.owner_id)::text||' د.ع · كشف الفترة محفوظ' else reason end);
 end if;
 result:=to_jsonb(r);
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response) values(request_id,p.id,'profit_'||action,payload,result);
 return result;
end $$;

-- Linked supplier charges belong to the settlement; editing one independently
-- would leave its reviewed split and the supplier balance inconsistent.
do $protect$declare def text;needle text;begin
 def:=pg_get_functiondef('solar_private.fx(text,uuid,jsonb)'::regprocedure);
 needle:='  tid:=(payload->>''paymentId'')::bigint;';
 if strpos(def,needle)=0 then raise exception 'supplier payment guard anchor missing';end if;
 def:=replace(def,needle,needle||E'\n  if exists(select 1 from public.transactions where id=tid and profit_supplier_settlement_id is not null and(p.is_admin or coalesce(cashbox_user_id,created_by)=p.id)) then raise exception ''هذه الإضافة مرتبطة بتسوية أرباح محفوظة؛ لا تعدّلها كوصل مورد مستقل'' using errcode=''42501'';end if;');
 execute def;
 def:=pg_get_functiondef('solar_private.supplier_payment_manage(text,uuid,jsonb)'::regprocedure);
 needle:=' select * into e from solar_private.supplier_fx_entries where transaction_id=t.id;';
 if strpos(def,needle)=0 then raise exception 'supplier management guard anchor missing';end if;
 def:=replace(def,needle,E' if action in(''update'',''delete'') and t.profit_supplier_settlement_id is not null then raise exception ''هذه الإضافة مرتبطة بتسوية أرباح محفوظة؛ لا تعدّلها كوصل مورد مستقل'' using errcode=''42501'';end if;\n'||needle);
 execute def;
end $protect$;
notify pgrst,'reload schema';
-- The archive editor keeps original ownership, cashbox, warehouse, issue date,
-- account snapshot and warranty tokens. Installation costs remain in its workflow.
do $editor$declare def text;needle text;begin
 def:=pg_get_functiondef('solar_private.invoice_save_v333(uuid,jsonb)'::regprocedure);
 def:=replace(def,'>solar_private.cash_balance(owner_id) then','>greatest(0,solar_private.cash_balance(owner_id)) then');
 needle:='  if kind=''system'' then raise exception ''استخدم متابعة التنصيب لتعديل المنظومة'';end if;';
 if strpos(def,needle)=0 then raise exception 'system edit anchor missing';end if;
 def:=replace(def,'economic_change boolean:=true;','system_items_changed boolean:=false;economic_change boolean:=true;');
 def:=replace(def,needle,$patch$  if kind='system' then
   if old_invoice.installation_revision is distinct from (payload->>'expectedInstallationRevision')::bigint then raise exception 'تغيّر ملف التنصيب؛ افتح تعديل الفاتورة مجدداً' using errcode='PT409';end if;
   if expenses is distinct from coalesce(old_invoice.expenses,0) then raise exception 'المصاريف تعدّل من ملف التنصيب بعد مراجعتها';end if;
   system_items_changed:=(select coalesce(jsonb_agg(jsonb_build_array(i.product_id,i.qty) order by i.product_id),'[]') from public.transaction_items i where i.transaction_id=old_invoice.id)
    is distinct from(select jsonb_agg(jsonb_build_array((value->>'id')::bigint,(value->>'qty')::numeric) order by(value->>'id')::bigint) from jsonb_array_elements(payload->'items'));
  end if;$patch$);
 needle:='   notes=nullif(payload->>''notes'',''''),source_currency=currency';
 if strpos(def,needle)=0 then raise exception 'system fields anchor missing';end if;
 def:=replace(def,needle,$patch$   installer_id=case when kind='system' then(payload->>'installerId')::uuid else installer_id end,
   install_date=case when kind='system' then nullif(payload->>'installDate','')::date else install_date end,
   install_time=case when kind='system' then nullif(payload->>'installTime','')::time else install_time end,
   customer_address=case when kind='system' then payload->>'customerAddress' else customer_address end,
   customer_phone=case when kind='system' then payload->>'customerPhone' else customer_phone end,
   installation_status=case when kind='system' and system_items_changed and old_invoice.installation_status='closed' then 'completed' else installation_status end,
   installation_closed_at=case when kind='system' and system_items_changed then null else installation_closed_at end,
   installation_revision=case when kind='system' then old_invoice.installation_revision+1 else installation_revision end,
   notes=nullif(payload->>'notes',''),source_currency=currency$patch$);
 def:=replace(def,'when kind=''system'' then total-cost-expenses else 0 end,','when kind=''system'' then total-cost-expenses-coalesce(old_invoice.installation_expenses,0) else 0 end,');
 needle:=' if not(existing and kind=''purchase'' and not economic_change) then';
 if strpos(def,needle)=0 then raise exception 'system items anchor missing';end if;
 def:=replace(def,needle,needle||' if not(existing and kind=''system'' and not system_items_changed) then');
 needle:=' select * into invoice from public.transactions where id=invoice_id;';
 if strpos(def,needle)=0 then raise exception 'system items end anchor missing';end if;
 def:=replace(def,needle,' end if;'||E'\n'||needle);
 execute def;
 def:=pg_get_functiondef('solar_private.invoice_save(uuid,jsonb)'::regprocedure);
 def:=replace(def,'if payload->>''kind''=''sale'' and payload->>''invoiceId'' is not null','if payload->>''kind'' in(''sale'',''system'') and payload->>''invoiceId'' is not null');
 needle:='  if before_row.cash is distinct from after_row.cash then';
 if strpos(def,needle)=0 then raise exception 'invoice audit anchor missing';end if;
 def:=replace(def,needle,$patch$  if before_row.cash is not distinct from after_row.cash and not exists(select 1 from solar_private.receipt_change_audit a where a.request_id=invoice_save.request_id) then
   insert into solar_private.receipt_change_audit(request_id,actor_id,transaction_id,action,before_row,after_row) values(request_id,auth.uid(),before_row.id,'invoice_edit',to_jsonb(before_row),to_jsonb(after_row));
  end if;
$patch$||needle);
 execute def;
end $editor$;
notify pgrst,'reload schema';

-- Allocated supplier profits cannot be withdrawn a second time as retained profit.
do $retained$declare def text;needle text:=E'\n$function$';begin
 def:=pg_get_functiondef('solar_private.retained_profit(uuid)'::regprocedure);
 if strpos(def,needle)=0 then raise exception 'retained profit anchor missing';end if;
 def:=replace(def,needle,E'\n -coalesce((select sum(s.supplier_amount_iqd) from solar_private.profit_settlements s where s.owner_id=uid and s.status=''approved'' and s.settlement_model=''owner_debit_supplier_charge''),0)'||needle);execute def;
end $retained$;
