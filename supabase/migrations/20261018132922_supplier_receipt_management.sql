-- Cancel a supplier receipt by reversing its original postings today.
-- Later purchases, rates, wallet costs and realised gains stay frozen.
alter table public.transactions add column supplier_payment_voided_at timestamptz,add column supplier_payment_replaced_by bigint;
alter table solar_private.supplier_fx_entries add column correction_for bigint unique;
create function solar_private.supplier_receipt_guard() returns trigger language plpgsql set search_path='' as $$begin
 if current_user in('anon','authenticated') and (new.supplier_payment_voided_at is not null or new.supplier_payment_replaced_by is not null) then raise exception 'استخدم سجل تسديدات المورد' using errcode='42501';end if;
 if tg_op='UPDATE' and old.supplier_payment_voided_at is not null and new is distinct from old then raise exception 'هذا الوصل ملغى؛ افتح الوصل البديل من السجل' using errcode='40001';end if;
 return new;
end $$;
create trigger solar_supplier_receipt_guard before insert or update on public.transactions for each row execute function solar_private.supplier_receipt_guard();
revoke all on function solar_private.supplier_receipt_guard() from public,anon,authenticated;
create function solar_private.supplier_payment_manage(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
#variable_conflict use_variable
declare actor public.profiles;t public.transactions;s public.suppliers;e solar_private.supplier_fx_entries;w solar_private.wallet_fx_entries;prior solar_private.finance_requests;
 uid uuid;rows jsonb;ledger jsonb;wallet jsonb;balance numeric;cash_balance numeric;token text;search text;page_offset integer;amount numeric;rate numeric;new_id bigint;result jsonb;replacement jsonb;cancel_note text;notes_only boolean:=false;
begin
 select * into actor from public.profiles where id=auth.uid() and active;
 if actor.id is null or actor.user_type in('installer','warehouse') or not(actor.is_admin or coalesce(actor.permissions->>'supplierPayment','false')='true') then raise exception 'لا تملك صلاحية تسديد المورد' using errcode='42501';end if;
 if action is null or action not in('list','get','update','delete') or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب غير صحيح';end if;
 if action='list' then
  search:=solar_private.customer_name_key(coalesce(payload->>'query',''));page_offset:=greatest(0,least(coalesce((payload->>'offset')::integer,0),1000000));
  select coalesce(jsonb_agg(v.row order by v.created_at desc,v.id desc),'[]') into rows from(
   select tx.id,tx.created_at,jsonb_build_object('id',tx.id,'receiptNo',tx.receipt_no,'date',tx.created_at,'party',tx.party_name,'cash',tx.cash,'amount',abs(coalesce(tx.source_subtotal,tx.total)),'currency',tx.source_currency,'notes',tx.notes,'cashOwnerName',coalesce(o.display_name,o.username,'غير مخصص')) row
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
   raise exception 'طلب مكرر ببيانات مختلفة' using errcode='40001';
  end if;
 end if;
 select * into t from public.transactions where id=(payload->>'id')::bigint for update;
 if t.id is null or t.kind<>'supplier_payment' or t.supplier_payment_voided_at is not null then raise exception 'الوصل غير موجود أو ملغى؛ حدّث السجل' using errcode='40001';end if;
 uid:=coalesce(t.cashbox_user_id,t.created_by);
 if uid is null or not(actor.is_admin or uid=actor.id) then raise exception 'هذا الوصل لصاحب القاصة أو الأدمن فقط' using errcode='42501';end if;
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
 if action='get' then return jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'party',s.name,'cash',t.cash,'currency',t.source_currency,'amount',abs(coalesce(t.source_subtotal,t.total)),'rate',t.market_rate,'accountCurrency',s.account_currency,'accountAmount',-e.delta,'balance',balance,'cashCurrency',t.cash_currency,'cashAmount',case when t.cash then case when t.cash_currency='USD' then t.cash_amount else t.total end else 0 end,'cashBalance',cash_balance,'cashOwnerName',(select coalesce(display_name,username,'مستخدم') from public.profiles where id=uid),'notes',t.notes,'token',token);end if;
 if payload->>'expectedToken' is distinct from token then raise exception 'تغيّر الوصل أو الرصيد؛ افتح العملية مجدداً' using errcode='40001';end if;
 if length(coalesce(payload->>'notes',''))>2000 then raise exception 'الملاحظات طويلة';end if;
 if action='update' then
  amount:=(payload->>'amount')::numeric;
  if amount is null or not(amount>0 and amount<=1000000000000) or amount::text in('NaN','Infinity','-Infinity') or round(amount,2)<>amount then raise exception 'أدخل مبلغاً صحيحاً أكبر من صفر وبحد أقصى منزلتين';end if;
  rate:=solar_private.fx_rate((payload->>'rate')::numeric,t.market_rate);
  new_id:=greatest((extract(epoch from clock_timestamp())*1000)::bigint,coalesce((select max(id)+1 from public.transactions),1));
 end if;
 notes_only:=action='update' and amount=abs(coalesce(t.source_subtotal,t.total)) and rate=t.market_rate;
 if notes_only then
  perform set_config('solar.fx_context',jsonb_build_object('marketRate',t.market_rate,'accountRevision',s.currency_revision,'cashCurrency',t.cash_currency)::text,true);
  update public.transactions set notes=coalesce(payload->>'notes','') where id=t.id;
  perform set_config('solar.fx_context','',true);
  replacement:=solar_private.supplier_payment_get(t.id);
 else
 cancel_note:=case action when 'update' then 'إلغاء أثر الوصل للتعديل #' else 'إلغاء تسديد مورد #' end||coalesce(t.receipt_no::text,t.id::text)||' · '||coalesce(actor.display_name,actor.username);
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
end $$;
create function public.solar_supplier_payment_manage(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select solar_private.supplier_payment_manage(action,request_id,payload)$$;
revoke all on function solar_private.supplier_payment_manage(text,uuid,jsonb),public.solar_supplier_payment_manage(text,uuid,jsonb) from public,anon;
grant execute on function solar_private.supplier_payment_manage(text,uuid,jsonb),public.solar_supplier_payment_manage(text,uuid,jsonb) to authenticated;
-- Prevent replaying or reopening an obsolete original receipt through older clients.
do $$declare def text;needle text;begin
 select pg_get_functiondef('solar_private.supplier_payment_get(bigint)'::regprocedure) into def;
 needle:='if t.id is null or';if strpos(def,needle)=0 then raise exception 'Review supplier receipt reader';end if;
 execute replace(def,needle,'if t.id is null or t.supplier_payment_voided_at is not null or');
 select pg_get_functiondef('solar_private.fx(text,uuid,jsonb)'::regprocedure) into def;
 needle:='then return prior.response;end if;';if strpos(def,needle)=0 then raise exception 'Review FX replay';end if;
 execute replace(def,needle,'then if action=''payment'' and exists(select 1 from public.transactions x where x.id=(prior.response->>''id'')::bigint and (x.supplier_payment_voided_at is not null or exists(select 1 from solar_private.receipt_change_audit a where a.transaction_id=x.id and a.action=''supplier_payment_update''))) then raise exception ''الوصل ملغى أو معدّل؛ حدّث سجل التسديدات'' using errcode=''40001'';end if;return prior.response;end if;');
 select pg_get_functiondef('solar_private.supplier_fx_balances(date)'::regprocedure) into def;
 needle:='and x.cash and e.delta<0';if strpos(def,needle)=0 then raise exception 'Review last supplier payment';end if;
 execute replace(def,needle,'and x.cash and (x.supplier_payment_voided_at is null or (x.supplier_payment_voided_at at time zone ''Asia/Baghdad'')::date>as_of) and e.delta<0');
end $$;
-- Cancelling only marks the original document; its postings remain immutable.
do $$declare def text;needle text;begin
 select pg_get_functiondef('solar_private.fx_prepare()'::regprocedure) into def;
 needle:=E'begin\n if coalesce';
 if strpos(def,needle)=0 then raise exception 'Review FX metadata path';end if;
 execute replace(def,needle,E'begin\n if tg_op=''UPDATE'' and new.supplier_payment_voided_at is not null and new.supplier_payment_voided_at is distinct from old.supplier_payment_voided_at and (to_jsonb(new)-''supplier_payment_voided_at''-''supplier_payment_replaced_by'')=(to_jsonb(old)-''supplier_payment_voided_at''-''supplier_payment_replaced_by'') then return new;end if;\n if coalesce');
end $$;
