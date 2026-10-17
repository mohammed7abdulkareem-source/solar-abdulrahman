-- Physical money is kept in its own currency; IQD is only the carrying-value
-- and profit base. All manual movements are appended through an atomic RPC.
alter table public.transactions add column cash_purpose text check(cash_purpose in ('income','expense','capital','withdrawal'));
create table solar_private.finance_requests(request_id uuid primary key,actor_id uuid not null references public.profiles(id),
 action text not null,payload jsonb not null,response jsonb not null,created_at timestamptz not null default now());
alter table public.transactions add column finance_request_id uuid references solar_private.finance_requests(request_id) deferrable initially deferred;
alter table solar_private.wallet_fx_entries add column finance_request_id uuid references solar_private.finance_requests(request_id) deferrable initially deferred;
alter table solar_private.finance_requests enable row level security;
revoke all on solar_private.finance_requests from public,anon,authenticated;

create function solar_private.cash_movements() returns table(id text,owner_id uuid,currency text,delta numeric,book_delta numeric,
 kind text,party text,note text,receipt_no bigint,rate numeric,source_currency text,source_amount numeric,created_at timestamptz,request_id uuid)
language sql stable set search_path='' as $$
 select 'tx:'||t.id,coalesce(t.cashbox_user_id,t.created_by),t.cash_currency,
  (case when t.kind in ('purchase','supplier_payment','cash_expense','profit_distribution') then -1 else 1 end)*case when t.cash_currency='USD' then t.cash_amount else t.total end,
  case when t.cash_currency='USD' then coalesce(w.book_delta,0) else(case when t.kind in ('purchase','supplier_payment','cash_expense','profit_distribution') then -t.total else t.total end) end,
  case t.cash_purpose when 'capital' then 'capital_deposit' when 'withdrawal' then 'capital_withdraw' when 'expense' then 'expense' else t.kind end,coalesce(t.party_name,''),coalesce(t.notes,''),t.receipt_no,t.market_rate,t.source_currency,coalesce(t.source_subtotal,t.total),t.created_at,t.finance_request_id
 from public.transactions t left join solar_private.wallet_fx_entries w on w.transaction_id=t.id where t.cash
 union all select 'entry:'||e.id,e.owner_id,'IQD',e.delta,e.delta,e.entry_type,'',e.notes,null,1,'IQD',abs(e.delta),e.created_at,null::uuid from public.solar_cash_entries e
 union all select 'fx:'||e.id,e.owner_id,e.currency,e.delta,e.book_delta,e.entry_type,'',e.note,(fr.response->>'receiptNo')::bigint,e.rate,e.currency,abs(e.delta),e.created_at,e.finance_request_id from solar_private.wallet_fx_entries e left join solar_private.finance_requests fr on fr.request_id=e.finance_request_id where e.transaction_id is null
$$;
revoke all on function solar_private.cash_movements() from public,anon,authenticated;

create function solar_private.retained_profit(uid uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce((select sum(case when t.kind='system' then t.profit when t.fx_pricing then t.profit else coalesce(t.subtotal,t.total)-coalesce((select sum(i.qty*i.cost) from public.transaction_items i where i.transaction_id=t.id),0) end)
 from public.transactions t where (t.kind='sale' or(t.kind='system' and t.installation_status='closed')) and coalesce(t.cashbox_user_id,t.created_by)=uid),0)
 -coalesce((select sum(t.total) from public.transactions t where coalesce(t.cashbox_user_id,t.created_by)=uid and(t.kind in ('profit_expense','profit_distribution') or t.cash_purpose='expense')),0)
 -coalesce((select sum(abs(e.delta)) from public.solar_cash_entries e where e.owner_id=uid and e.entry_type='handover_expense'),0)
 +coalesce((select sum(e.gain) from solar_private.supplier_fx_entries e where e.owner_id=uid),0)
 +coalesce((select sum(e.gain) from solar_private.wallet_fx_entries e where e.owner_id=uid),0)
$$;
revoke all on function solar_private.retained_profit(uuid) from public,anon,authenticated;

create function solar_private.cash_workspace(payload jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_variable
declare p public.profiles;uid uuid;cur text;direction text;q text;start_at timestamptz;end_at timestamptz;off integer;lim integer;result jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'cash','false')='true') then raise exception 'لا تملك صلاحية الصندوق' using errcode='42501';end if;
 uid:=nullif(payload->>'ownerId','')::uuid;
 if not p.is_admin then if uid is not null and uid<>p.id then raise exception 'لا تملك صلاحية هذه القاصة' using errcode='42501';end if;uid:=p.id;end if;
 cur:=coalesce(payload->>'currency','all');direction:=coalesce(payload->>'direction','all');q:=lower(trim(coalesce(payload->>'query','')));
 if cur not in ('all','IQD','USD') or direction not in ('all','in','out') or length(q)>200 then raise exception 'تصفية غير صحيحة';end if;
 start_at:=coalesce(nullif(payload->>'from','')::date::timestamp at time zone 'Asia/Baghdad','-infinity');
 end_at:=coalesce((nullif(payload->>'to','')::date+1)::timestamp at time zone 'Asia/Baghdad','infinity');
 if start_at>=end_at then raise exception 'فترة التاريخ غير صحيحة';end if;
 off:=greatest(0,least(coalesce((payload->>'offset')::integer,0),1000000));lim:=greatest(1,least(coalesce((payload->>'limit')::integer,50),5000));
 with scoped as materialized(select m.* from solar_private.cash_movements() m where uid is null or m.owner_id=uid),
 ranked as(select m.*,sum(delta) over(partition by currency order by created_at,id rows unbounded preceding) balance from scoped m),
 filtered as(select m.* from ranked m where m.created_at>=start_at and m.created_at<end_at and(cur='all' or m.currency=cur) and(direction='all' or (direction='in' and m.delta>0) or(direction='out' and m.delta<0)) and(q='' or lower(m.party||' '||m.note||' '||coalesce(m.receipt_no::text,'')) like '%'||q||'%')),
 page as(select * from filtered order by created_at desc,id desc limit lim offset off)
 select jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('ownerName',coalesce(o.display_name,o.username,'قيد التسليم')) order by x.created_at desc,x.id desc),'[]') from page x left join public.profiles o on o.id=x.owner_id),
 'count',(select count(*) from filtered),'summary',jsonb_build_object(
 'IQD',(select coalesce(sum(delta),0) from scoped where currency='IQD'),'USD',(select coalesce(sum(delta),0) from scoped where currency='USD'),
 'usdBook',(select coalesce(sum(book_delta),0) from scoped where currency='USD'),'transit',(select coalesce(sum(delta),0) from scoped where kind='transfer_transit'),
 'periodIQDIn',(select coalesce(sum(delta),0) from filtered where currency='IQD' and delta>0),'periodIQDOut',(select coalesce(sum(-delta),0) from filtered where currency='IQD' and delta<0),
 'periodUSDIn',(select coalesce(sum(delta),0) from filtered where currency='USD' and delta>0),'periodUSDOut',(select coalesce(sum(-delta),0) from filtered where currency='USD' and delta<0)),
 'ownerId',uid,'ownerName',case when uid is null then 'جميع القاصات' else(select coalesce(display_name,username,'مستخدم') from public.profiles where id=uid) end,
 'owners',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'name',coalesce(o.display_name,o.username,'مستخدم')) order by o.display_name),'[]') from public.profiles o where o.active and o.user_type not in ('installer','warehouse') and(p.is_admin or o.id=p.id)),
 'retainedProfit',case when p.is_admin and uid is not null then solar_private.retained_profit(uid) end,'offset',off,'limit',lim) into result;
 return result;
end $$;

create function solar_private.cash_save(request_id uuid,payload jsonb) returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
#variable_conflict use_variable
declare p public.profiles;prior solar_private.finance_requests;uid uuid;cur text;mode text;purpose text;amount numeric;r numeric;value_iqd numeric;wallet jsonb;book numeric;gain numeric:=0;before_iqd numeric;before_usd numeric;new_id bigint;t public.transactions;result jsonb;wallet_start bigint;number bigint;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'cash','false')='true') then raise exception 'لا تملك صلاحية الصندوق' using errcode='42501';end if;
 if request_id is null then raise exception 'رقم طلب الحفظ مطلوب';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into prior from solar_private.finance_requests x where x.request_id=cash_save.request_id;
 if found then if prior.actor_id=p.id and prior.action='cash' and prior.payload=payload then return prior.response;end if;raise exception 'طلب مكرر ببيانات مختلفة' using errcode='40001';end if;
 uid:=nullif(payload->>'ownerId','')::uuid;
 if uid is null or (not p.is_admin and uid<>p.id) or not exists(select 1 from public.profiles where id=uid and active and user_type not in ('installer','warehouse')) then raise exception 'اختر قاصة مسموحة لتسجيل الحركة' using errcode='42501';end if;
 mode:=payload->>'mode';cur:=payload->>'currency';amount:=(payload->>'amount')::numeric;
 if mode is null or mode not in ('deposit','expense','capital_deposit','capital_withdraw','buy_usd','sell_usd','distribution') or cur is null or cur not in ('IQD','USD') or amount is null or not(amount>0 and amount<=1000000000000) or round(amount,2)<>amount or length(trim(coalesce(payload->>'note','')))=0 or length(payload->>'note')>2000 then raise exception 'أدخل نوع الحركة والمبلغ والعملة والبيان بصورة صحيحة';end if;
 if mode in ('capital_deposit','capital_withdraw','distribution') and not p.is_admin then raise exception 'هذه الحركة للمدير فقط' using errcode='42501';end if;
 if cur='USD' and mode='deposit' and not p.is_admin then raise exception 'إضافة رصيد دولار للمدير فقط؛ استخدم الصرافة لشراء الدولار' using errcode='42501';end if;
 before_iqd:=solar_private.cash_balance(uid);wallet:=solar_private.usd_wallet(uid);before_usd:=(wallet->>'amount')::numeric;
 if mode in ('buy_usd','sell_usd') then
  if cur<>'USD' then raise exception 'مبلغ الصرافة يكتب بالدولار';end if;
  select coalesce(max(id),0) into wallet_start from solar_private.wallet_fx_entries;
  result:=solar_private.fx('wallet',request_id,jsonb_build_object('ownerId',uid,'mode',mode,'amount',amount,'rate',payload->'rate','note',payload->>'note'));
  update solar_private.wallet_fx_entries set finance_request_id=request_id where id>wallet_start and owner_id=uid;
  insert into solar_private.receipt_counters(kind,last_number) values('cash_exchange',1) on conflict(kind) do update set last_number=solar_private.receipt_counters.last_number+1 returning last_number into number;
  result:=result||jsonb_build_object('receiptNo',number,'date',now());
 else
  r:=case when cur='USD' then solar_private.fx_rate((payload->>'rate')::numeric) else 1 end;value_iqd:=round(amount*r,2);
  if mode='distribution' then
   if cur<>'IQD' or amount>greatest(0,solar_private.retained_profit(uid)) then raise exception 'التوزيع أكبر من الأرباح الفعلية المتاحة أو بعملة غير مسموحة';end if;
  end if;
  if mode in ('expense','capital_withdraw','distribution') then
   if(cur='IQD' and amount>before_iqd) or(cur='USD' and amount>before_usd) then raise exception 'رصيد العملة المختارة في هذه القاصة لا يكفي' using errcode='P0002';end if;
   book:=case when cur='IQD' then amount when amount=before_usd then(wallet->>'book')::numeric else round(amount*(wallet->>'book')::numeric/nullif(before_usd,0),2) end;
   if cur='USD' and mode='expense' then gain:=value_iqd-book;end if;
  else book:=value_iqd;end if;
  purpose:=case mode when 'expense' then 'expense' when 'capital_withdraw' then 'withdrawal' when 'capital_deposit' then 'capital' else 'income' end;
  new_id:=greatest((extract(epoch from clock_timestamp())*1000)::bigint,coalesce((select max(id)+1 from public.transactions),1));
  insert into public.transactions(id,kind,total,cash,created_by,cashbox_user_id,notes,cash_currency,cash_amount,source_currency,source_subtotal,exchange_rate,market_rate,fx_accounted,capital_effect,cash_purpose,finance_request_id)
  values(new_id,case when mode='distribution' then 'profit_distribution' when mode in ('expense','capital_withdraw') then 'cash_expense' else 'cash_income' end,value_iqd,true,p.id,uid,payload->>'note',cur,amount,cur,amount,r,r,true,mode in ('capital_deposit','capital_withdraw'),purpose,request_id) returning * into t;
  if cur='USD' then
   insert into solar_private.wallet_fx_entries(owner_id,transaction_id,currency,delta,book_delta,rate,gain,entry_type,note,finance_request_id) values
    (uid,t.id,'USD',case when mode in ('expense','capital_withdraw') then -amount else amount end,case when mode in ('expense','capital_withdraw') then -book else book end,r,gain,mode,payload->>'note',request_id);
  end if;
  result:=jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'date',t.created_at);
 end if;
 result:=result||jsonb_build_object('requestId',request_id,'mode',mode,'currency',cur,'amount',amount,'note',payload->>'note','ownerId',uid,'ownerName',(select coalesce(display_name,username,'مستخدم') from public.profiles where id=uid),
 'beforeIQD',before_iqd,'beforeUSD',before_usd,'afterIQD',solar_private.cash_balance(uid),'afterUSD',(solar_private.usd_wallet(uid)->>'amount')::numeric,'rate',case when cur='USD' then(payload->>'rate')::numeric else 1 end);
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response) values(request_id,p.id,'cash',payload,result);return result;
end $$;

create function solar_private.finance_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('authenticated','anon') then
  if (tg_op<>'INSERT' and old.kind in ('cash_income','cash_expense','profit_distribution','customer_payment')) or(tg_op<>'DELETE' and new.kind in ('cash_income','cash_expense','profit_distribution','customer_payment')) then raise exception 'استخدم شاشة الصندوق أو التسديد المحمية' using errcode='42501';end if;
  if tg_op<>'DELETE' and(new.finance_request_id is not null or(tg_op='UPDATE' and old.finance_request_id is not null)) then raise exception 'استخدم إجراء القاصة المحمي' using errcode='42501';end if;
  if tg_op<>'DELETE' and(new.cash_purpose is not null or(tg_op='UPDATE' and old.cash_purpose is not null)) then raise exception 'استخدم إجراء القاصة المحمي' using errcode='42501';end if;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
create trigger solar_finance_guard before insert or update or delete on public.transactions for each row execute function solar_private.finance_guard();
revoke all on function solar_private.finance_guard() from public,anon,authenticated;

create function public.solar_cash_workspace(payload jsonb default '{}') returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.cash_workspace(payload)$$;
create function public.solar_cash_save(request_id uuid,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select solar_private.cash_save(request_id,payload)$$;
revoke all on function solar_private.cash_workspace(jsonb),solar_private.cash_save(uuid,jsonb),public.solar_cash_workspace(jsonb),public.solar_cash_save(uuid,jsonb) from public,anon;
grant execute on function solar_private.cash_workspace(jsonb),solar_private.cash_save(uuid,jsonb),public.solar_cash_workspace(jsonb),public.solar_cash_save(uuid,jsonb) to authenticated;
create function solar_private.cash_receipt(request_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;r solar_private.finance_requests;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'cash','false')='true') then raise exception 'غير مسموح' using errcode='42501';end if;
 select * into r from solar_private.finance_requests x where x.request_id=cash_receipt.request_id and x.action='cash';
 if r.request_id is null or(p.is_admin or r.response->>'ownerId'=p.id::text) is distinct from true then raise exception 'لا تملك صلاحية هذا الوصل' using errcode='42501';end if;
 return r.response;
end $$;
create function public.solar_cash_receipt(request_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.cash_receipt(request_id)$$;
revoke all on function solar_private.cash_receipt(uuid),public.solar_cash_receipt(uuid) from public,anon;
grant execute on function solar_private.cash_receipt(uuid),public.solar_cash_receipt(uuid) to authenticated;

create function solar_private.supplier_directory() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;result jsonb;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'suppliers','false')='true') then raise exception 'لا تملك صلاحية الموردين' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('balance',coalesce(a.balance,0),'book_balance',coalesce(a.book,0),'token',md5(to_jsonb(s)::text)) order by s.name),'[]') into result
 from public.suppliers s left join lateral(select sum(delta) balance,sum(book_delta) book from solar_private.supplier_fx_entries e where e.supplier_id=s.id and e.revision=s.currency_revision and(p.is_admin or e.owner_id=p.id)) a on true;
 return result;
end $$;
create function solar_private.supplier_save(request_id uuid,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare p public.profiles;s public.suppliers;prior solar_private.finance_requests;new_id bigint;cur text;name_key text;result jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'suppliers','false')='true') then raise exception 'لا تملك صلاحية الموردين' using errcode='42501';end if;
 if request_id is null or length(trim(coalesce(payload->>'name','')))<2 or length(payload->>'name')>160 or length(coalesce(payload->>'phone',''))>40 then raise exception 'أدخل اسم المورد ورقم الهاتف بصورة صحيحة';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into prior from solar_private.finance_requests x where x.request_id=supplier_save.request_id;
 if found then if prior.actor_id=p.id and prior.action='supplier' and prior.payload=payload then return prior.response;end if;raise exception 'طلب مكرر ببيانات مختلفة' using errcode='40001';end if;
 name_key:=solar_private.customer_name_key(payload->>'name');
 if exists(select 1 from public.suppliers x where solar_private.customer_name_key(x.name)=name_key and x.id is distinct from nullif(payload->>'id','')::bigint) then raise exception 'هذا المورد مسجل مسبقاً؛ افتح حسابه الموجود';end if;
 if payload->>'id' is not null then
  select * into s from public.suppliers where id=(payload->>'id')::bigint for update;
  if s.id is null or payload->>'token' is distinct from md5(to_jsonb(s)::text) then raise exception 'تغير المورد؛ حدّث البيانات' using errcode='40001';end if;
  if coalesce(payload->>'currency',s.account_currency)<>s.account_currency then raise exception 'تغيير عملة حساب قائم يتم عبر مراجعة تحويل الرصيد';end if;
  update public.suppliers set name=trim(payload->>'name'),phone=nullif(trim(payload->>'phone'),'') where id=s.id returning * into s;
 else
  cur:=payload->>'currency';if cur is null or cur not in ('USD','IQD') then raise exception 'اختر عملة حساب المورد المتفق عليها';end if;
  new_id:=greatest((extract(epoch from clock_timestamp())*1000)::bigint,coalesce((select max(id)+1 from public.suppliers),1));
  insert into public.suppliers(id,name,phone,account_currency) values(new_id,trim(payload->>'name'),nullif(trim(payload->>'phone'),''),cur) returning * into s;
 end if;
 result:=jsonb_build_object('id',s.id,'currency',s.account_currency,'name',s.name);
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response) values(request_id,p.id,'supplier',payload,result);return result;
end $$;
create function public.solar_supplier_directory() returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.supplier_directory()$$;
create function public.solar_supplier_save(request_id uuid,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select solar_private.supplier_save(request_id,payload)$$;
revoke all on function solar_private.supplier_directory(),solar_private.supplier_save(uuid,jsonb),public.solar_supplier_directory(),public.solar_supplier_save(uuid,jsonb) from public,anon;
grant execute on function solar_private.supplier_directory(),solar_private.supplier_save(uuid,jsonb),public.solar_supplier_directory(),public.solar_supplier_save(uuid,jsonb) to authenticated;

-- Wholesale receipts use the same full-account rule as the repaired system
-- receipts: an opening balance is receivable without a saved sales invoice.
create function solar_private.customer_payment_context(customer_id bigint default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;c public.customers;rows jsonb;balance numeric;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'customerPayment','false')='true') then raise exception 'لا تملك صلاحية تسديد الجملة' using errcode='42501';end if;
 if customer_id is null then
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'phone',a.phone,'customer_type',a.customer_type,'owner_name',coalesce(o.display_name,o.username,'غير مخصص')) order by a.name),'[]') into rows from public.customers a left join public.profiles o on o.id=a.owner_id where a.active and a.customer_type='wholesale' and(p.is_admin or a.owner_id=p.id);
  return jsonb_build_object('customers',rows);
 end if;
 select * into c from public.customers where id=customer_id and active and customer_type='wholesale';
 if c.id is null or(p.is_admin or c.owner_id=p.id) is distinct from true then raise exception 'اختر عميل جملة ضمن صلاحياتك' using errcode='42501';end if;
 rows:=solar_private.customer_ledger(c.id);select coalesce(sum((x->>'effect')::numeric),0) into balance from jsonb_array_elements(rows) x;
 return jsonb_build_object('id',c.id,'name',c.name,'balance',balance,'systems','[]'::jsonb,'token',md5(to_jsonb(c)::text||rows::text),'cashBalance',solar_private.cash_balance(p.id),'cashOwnerName',coalesce(p.display_name,p.username,'المستلم'));
end $$;
create function solar_private.customer_payment_save(request_id uuid,payload jsonb) returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
#variable_conflict use_variable
declare p public.profiles;prior solar_private.finance_requests;a jsonb;t public.transactions;amount numeric;mode text;new_id bigint;result jsonb;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'customerPayment','false')='true') then raise exception 'لا تملك صلاحية تسديد الجملة' using errcode='42501';end if;
 if request_id is null then raise exception 'رقم طلب الحفظ مطلوب';end if;perform pg_advisory_xact_lock(7311,1);
 select * into prior from solar_private.finance_requests x where x.request_id=customer_payment_save.request_id;
 if found then if prior.actor_id=p.id and prior.action='customer_payment' and prior.payload=payload then return prior.response;end if;raise exception 'طلب مكرر ببيانات مختلفة' using errcode='40001';end if;
 amount:=(payload->>'amount')::numeric;mode:=payload->>'mode';
 if amount is null or not(amount>0 and amount<=1000000000000) or round(amount,2)<>amount or mode is null or mode not in ('payment','charge_extra_expense','charge_old_balance','charge_other') or length(coalesce(payload->>'notes',''))>2000 or payload->>'invoiceId' is not null then raise exception 'بيانات الحركة غير صحيحة';end if;
 if mode<>'payment' and length(trim(coalesce(payload->>'notes','')))=0 then raise exception 'اكتب سبب الإضافة';end if;
 a:=solar_private.customer_payment_context((payload->>'customerId')::bigint);
 if a->>'id' is null then raise exception 'اختر العميل';end if;
 if payload->>'expectedToken' is distinct from a->>'token' then raise exception 'تغير الحساب؛ راجع الرصيد الجديد' using errcode='40001';end if;
 if mode='payment' and amount>greatest(0,(a->>'balance')::numeric) then raise exception 'المبلغ أكبر من الرصيد المتبقي';end if;
 new_id:=greatest((extract(epoch from clock_timestamp())*1000)::bigint,coalesce((select max(id)+1 from public.transactions),1));
 insert into public.transactions(id,kind,party_id,party_type,party_name,total,cash,payment_mode,notes,created_by,cashbox_user_id) values(new_id,'customer_payment',(a->>'id')::bigint,'customer',a->>'name',case when mode='payment' then amount else -amount end,mode='payment',mode,payload->>'notes',p.id,p.id) returning * into t;
 result:=jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'date',t.created_at,'kind',t.kind,'party',t.party_name,'total',t.total,'mode',mode,'cash',t.cash,'notes',t.notes,'oldBalance',(a->>'balance')::numeric,'remaining',(a->>'balance')::numeric-t.total,'cashOwnerName',a->>'cashOwnerName','cashBefore',(a->>'cashBalance')::numeric,'cashAfter',solar_private.cash_balance(p.id));
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response) values(request_id,p.id,'customer_payment',payload,result);return result;
end $$;
create function public.solar_customer_payment_context(customer_id bigint default null) returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.customer_payment_context(customer_id)$$;
create function public.solar_customer_payment_save(request_id uuid,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select solar_private.customer_payment_save(request_id,payload)$$;
revoke all on function solar_private.customer_payment_context(bigint),solar_private.customer_payment_save(uuid,jsonb),public.solar_customer_payment_context(bigint),public.solar_customer_payment_save(uuid,jsonb) from public,anon;
grant execute on function solar_private.customer_payment_context(bigint),solar_private.customer_payment_save(uuid,jsonb),public.solar_customer_payment_context(bigint),public.solar_customer_payment_save(uuid,jsonb) to authenticated;

do $$declare def text;begin
 if to_regprocedure('solar_private.reset_snapshot()') is not null then
  select pg_get_functiondef('solar_private.reset_snapshot()'::regprocedure) into def;execute replace(def,'''solar_private.receipt_counters''','''solar_private.finance_requests'',''solar_private.receipt_counters''');
  select pg_get_functiondef('solar_private.lock_reset_tables()'::regprocedure) into def;execute replace(def,'solar_private.receipt_counters','solar_private.finance_requests,solar_private.receipt_counters');
  select pg_get_functiondef('public.solar_execute_reset(uuid,uuid,text)'::regprocedure) into def;execute replace(def,'delete from public.transactions','delete from solar_private.finance_requests; delete from public.transactions');
 end if;
end $$;
notify pgrst,'reload schema';
