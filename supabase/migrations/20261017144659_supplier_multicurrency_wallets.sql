-- IQD remains the inventory/profit base. Supplier denomination, physical cash
-- and the daily conversion rate are independent, immutable posting snapshots.
alter table public.suppliers add column account_currency text not null default 'IQD' check(account_currency in ('IQD','USD')),
 add column currency_revision bigint not null default 0;
alter table public.transactions add column account_currency text not null default 'IQD' check(account_currency in ('IQD','USD')),
 add column account_amount numeric not null default 0,
 add column account_revision bigint not null default 0,
 add column market_rate numeric not null default 1 check(market_rate>0 and market_rate<=1000000),
 add column cash_currency text not null default 'IQD' check(cash_currency in ('IQD','USD')),
 add column cash_amount numeric not null default 0,
 add column fx_accounted boolean not null default false;
create table solar_private.supplier_fx_entries(
 id bigint generated always as identity primary key,
 supplier_id bigint not null references public.suppliers(id),owner_id uuid references public.profiles(id),
 transaction_id bigint unique references public.transactions(id),currency text not null check(currency in ('IQD','USD')),
 revision bigint not null,delta numeric not null,book_delta numeric not null,gain numeric not null default 0,
 rate numeric not null,note text not null default '',created_at timestamptz not null default now()
);
create index supplier_fx_account on solar_private.supplier_fx_entries(supplier_id,revision,id);
create index supplier_fx_owner on solar_private.supplier_fx_entries(owner_id,created_at);
create table solar_private.wallet_fx_entries(
 id bigint generated always as identity primary key,owner_id uuid not null references public.profiles(id),
 transaction_id bigint unique references public.transactions(id),currency text not null check(currency in ('IQD','USD')),
 delta numeric not null,book_delta numeric not null,rate numeric not null,gain numeric not null default 0,
 entry_type text not null,note text not null default '',created_at timestamptz not null default now()
);
create index wallet_fx_owner on solar_private.wallet_fx_entries(owner_id,currency,id);
create table solar_private.fx_requests(request_id uuid primary key,actor_id uuid not null references public.profiles(id),
 action text not null,payload jsonb not null,response jsonb not null,before_row jsonb,created_at timestamptz not null default now());
alter table solar_private.supplier_fx_entries enable row level security;
alter table solar_private.wallet_fx_entries enable row level security;
alter table solar_private.fx_requests enable row level security;
revoke all on solar_private.supplier_fx_entries,solar_private.wallet_fx_entries,solar_private.fx_requests from public,anon,authenticated;

-- Preserve all old figures as IQD. Deleted explicit IDs are never reassigned by name.
insert into solar_private.supplier_fx_entries(supplier_id,owner_id,transaction_id,currency,revision,delta,book_delta,rate,created_at)
select s.id,coalesce(t.cashbox_user_id,t.created_by),t.id,'IQD',0,
 case when t.kind='supplier_payment' then -t.total when t.cash then 0 else t.total end,
 case when t.kind='supplier_payment' then -t.total when t.cash then 0 else t.total end,case when t.source_currency='USD' then t.exchange_rate else 1 end,t.created_at
from public.transactions t join public.suppliers s on t.party_id=s.id or(t.party_id is null
 and solar_private.customer_name_key(t.party_name)=solar_private.customer_name_key(s.name)
 and (select count(*) from public.suppliers z where solar_private.customer_name_key(z.name)=solar_private.customer_name_key(s.name))=1)
where t.kind in ('purchase','supplier_payment');
update public.transactions set account_amount=total,market_rate=case when source_currency='USD' then exchange_rate else 1 end,cash_amount=case when cash then total else 0 end where kind in ('purchase','supplier_payment');

create or replace function solar_private.cash_balance(uid uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce((select sum(case when t.kind in ('purchase','supplier_payment','cash_expense','profit_distribution') then -t.total else t.total end)
 from public.transactions t where t.cash and t.cash_currency='IQD' and coalesce(t.cashbox_user_id,t.created_by)=uid),0)
 +coalesce((select sum(e.delta) from public.solar_cash_entries e where e.owner_id=uid),0)
 +coalesce((select sum(e.delta) from solar_private.wallet_fx_entries e where e.owner_id=uid and e.currency='IQD'),0)
$$;
create function solar_private.usd_wallet(uid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('amount',coalesce(sum(delta),0),'book',coalesce(sum(book_delta),0)) from solar_private.wallet_fx_entries where owner_id=uid and currency='USD'
$$;
create function solar_private.fx_rate(input_rate numeric,old_rate numeric default null) returns numeric language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;r numeric;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') then raise exception 'غير مسموح' using errcode='42501';end if;
 select rate into r from solar_private.exchange_settings where id;
 if input_rate is null or input_rate<=0 or input_rate>1000000 or input_rate::text='NaN' then raise exception 'حدد سعر صرف صحيحاً';end if;
 if not(p.is_admin or coalesce(p.permissions->>'exchangeRateEdit','false')='true') and input_rate is distinct from r and input_rate is distinct from old_rate then raise exception 'تغيير الصرف يحتاج صلاحية الإدارة' using errcode='42501';end if;
 return input_rate;
end $$;

-- Raw writes cannot set protected snapshots, change a foreign account or alter
-- the financial content of a foreign posting through an older application.
create function solar_private.fx_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('anon','authenticated') then
  if tg_table_name='suppliers' then
   if (tg_op='INSERT' and (new.account_currency<>'IQD' or new.currency_revision<>0)) or
    (tg_op='UPDATE' and (new.account_currency,new.currency_revision) is distinct from (old.account_currency,old.currency_revision)) then raise exception 'استخدم إعداد عملة المورد' using errcode='42501';end if;
  else
   if tg_op='DELETE' then
    if old.fx_accounted then raise exception 'استخدم الإجراء المالي المحمي' using errcode='42501';end if;
   elsif new.fx_accounted or new.cash_currency<>'IQD' or new.account_currency<>'IQD' or
    (tg_op='INSERT' and (new.market_rate<>1 or new.account_amount<>0 or new.account_revision<>0 or new.cash_amount<>0)) or
    (tg_op='UPDATE' and (old.fx_accounted or (new.market_rate,new.account_amount,new.account_revision,new.cash_amount) is distinct from (old.market_rate,old.account_amount,old.account_revision,old.cash_amount))) then raise exception 'استخدم الإجراء المالي المحمي' using errcode='42501';end if;
  end if;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
create trigger solar_fx_guard before insert or update or delete on public.transactions for each row execute function solar_private.fx_guard();
create trigger solar_fx_supplier_guard before insert or update on public.suppliers for each row execute function solar_private.fx_guard();

create function solar_private.fx_prepare() returns trigger language plpgsql security definer set search_path='' as $$
declare ctx jsonb:=coalesce(nullif(current_setting('solar.fx_context',true),'')::jsonb,'{}');s public.suppliers;
 prior solar_private.supplier_fx_entries;w solar_private.wallet_fx_entries;r numeric;wallet jsonb;refund numeric:=0;
begin
 if coalesce(case when tg_op='DELETE' then old.kind else new.kind end,'') not in ('purchase','supplier_payment') then
  if tg_op='DELETE' then return old;end if;return new;
 end if;
 perform pg_advisory_xact_lock(7311,1);
 if tg_op<>'DELETE' then
  select * into s from public.suppliers where id=new.party_id;
  if s.id is null and new.party_id is null then
   select * into s from public.suppliers where solar_private.customer_name_key(name)=solar_private.customer_name_key(new.party_name)
    and (select count(*) from public.suppliers z where solar_private.customer_name_key(z.name)=solar_private.customer_name_key(new.party_name))=1;
  end if;
  if s.id is null and ctx<>'{}' then raise exception 'اختر المورد المسجّل قبل حفظ الشراء';end if;
  if s.id is not null then
   if ctx<>'{}' then
    if (ctx->>'accountRevision')::bigint is distinct from s.currency_revision then raise exception 'تغيرت عملة المورد؛ حدّث البيانات قبل الحفظ' using errcode='40001';end if;
    r:=solar_private.fx_rate((ctx->>'marketRate')::numeric,case when tg_op='UPDATE' then old.market_rate end);
    if new.kind='purchase' and new.source_currency='USD' and new.exchange_rate<>r then raise exception 'صرف كلفة الشراء يجب أن يطابق الصرف المثبت للحساب';end if;
    new.fx_accounted:=true;new.party_id:=s.id;new.account_currency:=s.account_currency;new.account_revision:=s.currency_revision;new.market_rate:=r;
    new.account_amount:=case when s.account_currency='USD' then round(new.total/r,2) else new.total end;
    new.cash_currency:=case when new.cash then coalesce(ctx->>'cashCurrency','IQD') else 'IQD' end;
    if new.cash_currency not in ('USD','IQD') then raise exception 'عملة التسديد غير صحيحة';end if;
    new.cash_amount:=case when not new.cash then 0 when new.cash_currency='USD' then round(new.total/r,2) else new.total end;
    if new.source_currency='USD' and new.kind='supplier_payment' and new.cash then new.cash_amount:=new.source_subtotal;end if;
    if new.source_currency='USD' and s.account_currency='USD' then
     new.account_amount:=case when new.kind='supplier_payment' then new.source_subtotal else round(new.source_subtotal+new.expenses/r,2) end;
    end if;
    if new.total<>0 and new.account_amount=0 then raise exception 'المبلغ المحوّل أصغر من أصغر وحدة لعملة الحساب';end if;
   elsif s.account_currency<>'IQD' or s.currency_revision<>0 or (tg_op='UPDATE' and old.fx_accounted) then
    raise exception 'حدّث البرنامج لاستخدام عملة حساب المورد';
   else new.account_amount:=new.total;new.cash_amount:=case when new.cash then new.total else 0 end;
   end if;
  end if;
  if tg_op='UPDATE' and old.cash and new.cash and new.cash_currency is distinct from old.cash_currency then raise exception 'عملة القاصة لوصل محفوظ ثابتة؛ سجّل تصحيحاً مستقلاً';end if;
  if tg_op='UPDATE' and (new.party_id,new.total,new.cash,new.payment_mode,new.account_currency,new.account_amount,new.account_revision,new.market_rate,new.cash_currency,new.cash_amount)
   is not distinct from (old.party_id,old.total,old.cash,old.payment_mode,old.account_currency,old.account_amount,old.account_revision,old.market_rate,old.cash_currency,old.cash_amount) then return new;end if;
 end if;
 if tg_op<>'INSERT' then
  select * into prior from solar_private.supplier_fx_entries where transaction_id=old.id;
  if prior.id is not null and exists(select 1 from solar_private.supplier_fx_entries e where e.supplier_id=prior.supplier_id and e.id>prior.id) then raise exception 'لهذا الوصل حركات مورد لاحقة؛ سجّل حركة تصحيح مستقلة لحفظ تسلسل الحساب';end if;
  select * into w from solar_private.wallet_fx_entries where transaction_id=old.id;
  if w.id is not null and exists(select 1 from solar_private.wallet_fx_entries e where e.owner_id=w.owner_id and e.currency='USD' and e.id>w.id) then raise exception 'لهذا الوصل حركات دولار لاحقة؛ لا يمكن إعادة تسعير القاصة';end if;
  if old.cash and old.cash_currency='IQD' then refund:=old.total;end if;
  delete from solar_private.supplier_fx_entries where transaction_id=old.id;
  delete from solar_private.wallet_fx_entries where transaction_id=old.id;
 end if;
 if tg_op='DELETE' then return old;end if;
 if new.cash then
  if new.cash_currency='USD' then
   wallet:=solar_private.usd_wallet(coalesce(new.cashbox_user_id,new.created_by));
   if new.cash_amount>(wallet->>'amount')::numeric then raise exception 'رصيد الدولار في قاصة صاحب الوصل لا يكفي' using errcode='P0002';end if;
  elsif new.total>solar_private.cash_balance(coalesce(new.cashbox_user_id,new.created_by))+refund then raise exception 'رصيد الدينار في قاصة صاحب الوصل لا يكفي' using errcode='P0002';end if;
 end if;
 return new;
end $$;
create trigger solar_fx_prepare before insert or update or delete on public.transactions for each row execute function solar_private.fx_prepare();

create function solar_private.fx_post() returns trigger language plpgsql security definer set search_path='' as $$
declare b numeric;v numeric;d numeric;m numeric;bd numeric;matched numeric;uid uuid;wallet jsonb;cashbook numeric;sid bigint;
begin
 if new.kind not in ('purchase','supplier_payment') then return new;end if;
 if exists(select 1 from solar_private.supplier_fx_entries where transaction_id=new.id) then return new;end if;
 uid:=coalesce(new.cashbox_user_id,new.created_by);sid:=new.party_id;
 if sid is null then select id into sid from public.suppliers where solar_private.customer_name_key(name)=solar_private.customer_name_key(new.party_name) and(select count(*) from public.suppliers s where solar_private.customer_name_key(s.name)=solar_private.customer_name_key(new.party_name))=1;end if;
 cashbook:=new.total;
 if new.cash and new.cash_currency='USD' then
  wallet:=solar_private.usd_wallet(uid);
  cashbook:=case when new.cash_amount=(wallet->>'amount')::numeric then (wallet->>'book')::numeric else round(new.cash_amount*(wallet->>'book')::numeric/nullif((wallet->>'amount')::numeric,0),2) end;
  insert into solar_private.wallet_fx_entries(owner_id,transaction_id,currency,delta,book_delta,rate,gain,entry_type,created_at)
   values(uid,new.id,'USD',-new.cash_amount,-cashbook,new.market_rate,case when new.kind='purchase' then new.total-cashbook else 0 end,'supplier_cash',new.created_at);
 end if;
 if sid is null then return new;end if;
 d:=case when new.kind='supplier_payment' then -new.account_amount when new.cash then 0 else new.account_amount end;
 m:=case when new.kind='supplier_payment' then case when new.cash then -cashbook else -new.total end when new.cash then 0 else new.total end;
 select coalesce(sum(delta),0),coalesce(sum(book_delta),0) into b,v from solar_private.supplier_fx_entries where supplier_id=sid and revision=new.account_revision;
 bd:=m;
 if b*d<0 then
  matched:=least(abs(b),abs(d));
  bd:=round(sign(d)*(matched*abs(v/b)+greatest(abs(d)-abs(b),0)*abs(m/d)),2);
 end if;
 insert into solar_private.supplier_fx_entries(supplier_id,owner_id,transaction_id,currency,revision,delta,book_delta,gain,rate,created_at)
 values(sid,uid,new.id,new.account_currency,new.account_revision,d,bd,m-bd,new.market_rate,new.created_at);
 return new;
end $$;
create trigger solar_fx_post after insert or update on public.transactions for each row execute function solar_private.fx_post();

-- Retain the tested stock/weighted-cost implementation, replacing only its
-- IQD-only cash gate; the posting trigger checks the actual physical currency.
do $$declare def text;needle text;begin
 select pg_get_functiondef('solar_private.invoice_save(uuid,jsonb)'::regprocedure) into def;
 needle:='if cash and kind=''purchase'' and';
 if strpos(def,needle)=0 then raise exception 'Review invoice cash integration';end if;
 def:=replace(def,needle,'if cash and kind=''purchase'' and coalesce(payload->>''cashCurrency'',''IQD'')=''IQD'' and');
 def:=replace(def,'old_invoice.cash then old_invoice.total','old_invoice.cash and old_invoice.cash_currency=''IQD'' then old_invoice.total');
 execute def;
end $$;
alter function solar_private.invoice_save(uuid,jsonb) rename to invoice_save_v333;
do $$declare def text;begin
 select pg_get_functiondef('solar_private.invoice_save_v333(uuid,jsonb)'::regprocedure) into def;
 execute replace(def,'invoice_save.request_id','invoice_save_v333.request_id');
end $$;
revoke all on function solar_private.invoice_save_v333(uuid,jsonb) from public,anon,authenticated;
create function solar_private.invoice_save(request_id uuid,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 if payload->>'kind'='purchase' then
  perform set_config('solar.fx_context',case when payload ? 'marketRate' then payload::text else '{}' end,true);
 end if;
 result:=solar_private.invoice_save_v333(request_id,payload);
 perform set_config('solar.fx_context','',true);return result;
end $$;
revoke all on function solar_private.invoice_save(uuid,jsonb) from public,anon;
grant execute on function solar_private.invoice_save(uuid,jsonb) to authenticated;

create function solar_private.fx(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
#variable_conflict use_variable
declare p public.profiles;s public.suppliers;t public.transactions;prior solar_private.fx_requests;result jsonb;
 rows jsonb;before_row jsonb;uid uuid;sid bigint;tid bigint;r numeric;amt numeric;cur text;mode text;
 b numeric;v numeric;wd numeric;wb numeric;gain numeric:=0;revision bigint;owner record;token text;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') then raise exception 'غير مسموح' using errcode='42501';end if;
 if action='state' then
  return jsonb_build_object(
   'walletEntries',(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from solar_private.wallet_fx_entries e where p.is_admin or e.owner_id=p.id),
   'accountEntries',(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from solar_private.supplier_fx_entries e where p.is_admin or e.owner_id=p.id));
 end if;
 if action in ('account','statement','currency') then
  if not(p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true' or coalesce(p.permissions->>'supplierStatement','false')='true' or coalesce(p.permissions->>'purchase','false')='true') then raise exception 'لا تملك صلاحية حساب المورد' using errcode='42501';end if;
  sid:=(payload->>'supplierId')::bigint;select * into s from public.suppliers where id=sid;
  if s.id is null then raise exception 'المورد غير موجود';end if;
  uid:=p.id;
  if payload->>'paymentId' is not null then
   select * into t from public.transactions where id=(payload->>'paymentId')::bigint and kind='supplier_payment';
   if t.id is null or (p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id) is distinct from true then raise exception 'لا تملك صلاحية الوصل' using errcode='42501';end if;
   uid:=coalesce(t.cashbox_user_id,t.created_by);
  end if;
  select coalesce(sum(delta),0),coalesce(sum(book_delta),0) into b,v from solar_private.supplier_fx_entries e where supplier_id=sid and e.revision=s.currency_revision and(p.is_admin or owner_id=p.id);
  select md5(coalesce(jsonb_agg(to_jsonb(e) order by e.id),'[]')::text) into token from solar_private.supplier_fx_entries e where supplier_id=sid;
  result:=jsonb_build_object('supplierId',sid,'currency',s.account_currency,'revision',s.currency_revision,'balance',b,'bookBalance',v,'token',token,
   'cashBalance',solar_private.cash_balance(uid),'usdWallet',solar_private.usd_wallet(uid),'cashOwnerName',(select coalesce(display_name,username,'مستخدم') from public.profiles where id=uid));
  if action='account' then return result;end if;
  if action='statement' then
   if not(p.is_admin or coalesce(p.permissions->>'supplierStatement','false')='true') then raise exception 'لا تملك صلاحية الكشف' using errcode='42501';end if;
   select coalesce(jsonb_agg(to_jsonb(e)||jsonb_build_object('transaction',to_jsonb(x),'items',
    (select coalesce(jsonb_agg(to_jsonb(i)),'[]') from public.transaction_items i where i.transaction_id=x.id)) order by e.id),'[]') into rows
   from solar_private.supplier_fx_entries e left join public.transactions x on x.id=e.transaction_id where e.supplier_id=sid and(p.is_admin or e.owner_id=p.id);
   return result||jsonb_build_object('name',s.name,'rows',rows);
  end if;
 end if;
 if action not in ('currency','payment','wallet') then raise exception 'إجراء غير معروف';end if;
 perform pg_advisory_xact_lock(7311,1);
 if request_id is null then raise exception 'رقم طلب الحفظ مطلوب';end if;
 select * into prior from solar_private.fx_requests q where q.request_id=fx.request_id;
 if found then
  if prior.actor_id=p.id and prior.action=action and prior.payload=payload then return prior.response;end if;
  raise exception 'طلب مكرر ببيانات مختلفة' using errcode='40001';
 end if;
 if length(coalesce(payload->>'note',''))>2000 then raise exception 'الملاحظة طويلة';end if;
 if action='currency' then
  if not p.is_admin then raise exception 'عملة حساب المورد من صلاحيات المدير' using errcode='42501';end if;
  -- Account read above is repeated under the posting lock to reject stale previews.
  select * into s from public.suppliers where id=sid for update;
  select md5(coalesce(jsonb_agg(to_jsonb(e) order by e.id),'[]')::text) into token from solar_private.supplier_fx_entries e where supplier_id=sid;
  if (payload->>'expectedRevision')::bigint is distinct from s.currency_revision or payload->>'expectedToken' is distinct from token then raise exception 'تغير الحساب؛ راجع التحويل مجدداً' using errcode='40001';end if;
  cur:=payload->>'currency';if cur is null or cur not in ('IQD','USD') or cur=s.account_currency then raise exception 'اختر عملة حساب مختلفة';end if;
  if length(trim(coalesce(payload->>'note','')))=0 then raise exception 'اكتب سبب تغيير عملة الحساب';end if;
  r:=solar_private.fx_rate((payload->>'rate')::numeric);
  before_row:=to_jsonb(s)||jsonb_build_object('account',result);
  for owner in select owner_id,sum(delta) amount,sum(book_delta) book from solar_private.supplier_fx_entries e where supplier_id=sid and e.revision=s.currency_revision group by owner_id loop
   if owner.amount<>0 or owner.book<>0 then
    if cur='USD' and owner.amount<>0 and round(owner.amount/r,2)=0 then raise exception 'الرصيد أصغر من سنت؛ عالج فرق التقريب قبل تغيير العملة';end if;
    insert into solar_private.supplier_fx_entries(supplier_id,owner_id,currency,revision,delta,book_delta,rate,note) values
     (sid,owner.owner_id,s.account_currency,s.currency_revision,-owner.amount,-owner.book,r,'إقفال العملة السابقة');
    insert into solar_private.supplier_fx_entries(supplier_id,owner_id,currency,revision,delta,book_delta,rate,note) values
     (sid,owner.owner_id,cur,s.currency_revision+1,case when cur='USD' then round(owner.amount/r,2) else round(owner.amount*r,2) end,owner.book,r,'تحويل رصيد باتفاق جديد · '||coalesce(payload->>'note',''));
   end if;
  end loop;
  update public.suppliers set account_currency=cur,currency_revision=currency_revision+1 where id=sid;
  result:=jsonb_build_object('currency',cur,'revision',s.currency_revision+1,'ok',true);
 elsif action='wallet' then
  if not(p.is_admin or coalesce(p.permissions->>'cash','false')='true') then raise exception 'لا تملك صلاحية القاصة' using errcode='42501';end if;
  uid:=coalesce(nullif(payload->>'ownerId','')::uuid,p.id);
  if uid<>p.id and not p.is_admin then raise exception 'لا تملك صلاحية هذه القاصة' using errcode='42501';end if;
  if not exists(select 1 from public.profiles where id=uid and active and user_type not in ('installer','warehouse')) then raise exception 'صاحب القاصة غير متاح';end if;
  amt:=(payload->>'amount')::numeric;mode:=payload->>'mode';r:=solar_private.fx_rate((payload->>'rate')::numeric);
  if amt is null or not(amt>0 and amt<=1000000000) or round(amt,2)<>amt or length(trim(coalesce(payload->>'note','')))=0 then raise exception 'أدخل مبلغ دولار صحيحاً وبيان الحركة';end if;
  if mode in ('deposit','withdraw') and not p.is_admin then raise exception 'إضافة أو سحب رأس مال الدولار للمدير فقط' using errcode='42501';end if;
  if mode not in ('deposit','withdraw','buy_usd','sell_usd') or mode is null then raise exception 'اختر نوع الحركة';end if;
  select coalesce(sum(delta),0),coalesce(sum(book_delta),0) into wd,wb from solar_private.wallet_fx_entries where owner_id=uid and currency='USD';
  before_row:=jsonb_build_object('owner',uid,'usd',wd,'book',wb,'iqd',solar_private.cash_balance(uid));
  if mode in ('withdraw','sell_usd') then
   if amt>wd then raise exception 'رصيد الدولار لا يكفي' using errcode='P0002';end if;
   v:=case when amt=wd then wb else round(amt*wb/nullif(wd,0),2) end;
  else v:=round(amt*r,2);end if;
  if mode='buy_usd' and v>solar_private.cash_balance(uid) then raise exception 'رصيد الدينار لا يكفي لشراء الدولار' using errcode='P0002';end if;
  if mode='sell_usd' then gain:=round(amt*r,2)-v;end if;
  insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,gain,entry_type,note) values
   (uid,'USD',case when mode in ('withdraw','sell_usd') then -amt else amt end,case when mode in ('withdraw','sell_usd') then -v else v end,r,gain,mode,payload->>'note');
  if mode in ('buy_usd','sell_usd') then
   insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,entry_type,note) values
    (uid,'IQD',case when mode='buy_usd' then -round(amt*r,2) else round(amt*r,2) end,case when mode='buy_usd' then -round(amt*r,2) else round(amt*r,2) end,r,mode,payload->>'note');
  end if;
  result:=jsonb_build_object('ok',true,'usdWallet',solar_private.usd_wallet(uid),'cashBalance',solar_private.cash_balance(uid));
 else
  if not(p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true') then raise exception 'لا تملك صلاحية تسديد المورد' using errcode='42501';end if;
  sid:=(payload->>'supplierId')::bigint;select * into s from public.suppliers where id=sid;
  if s.id is null then raise exception 'المورد غير موجود';end if;
  tid:=(payload->>'paymentId')::bigint;amt:=(payload->>'amount')::numeric;cur:=payload->>'currency';mode:=payload->>'mode';
  if tid is null or abs(tid)>9007199254740991 or amt is null or not(amt>0 and amt<=1000000000000) or round(amt,2)<>amt or cur is null or cur not in ('IQD','USD') or mode is null or mode not in ('cash','charge_extra_expense','charge_old_balance','charge_other') then raise exception 'أدخل مبلغاً وعملة ونوع حركة صحيحين';end if;
  if mode<>'cash' and length(trim(coalesce(payload->>'note','')))=0 then raise exception 'اكتب سبب الإضافة';end if;
  select * into t from public.transactions where id=tid for update;
  uid:=p.id;
  if t.id is not null then
   if t.kind<>'supplier_payment' or (p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id) is distinct from true then raise exception 'لا تملك صلاحية الوصل' using errcode='42501';end if;
   if payload->>'expectedToken' is distinct from md5(to_jsonb(t)::text) then raise exception 'تغير الوصل؛ افتحه مجدداً' using errcode='40001';end if;
   if t.cash is distinct from (mode='cash') then raise exception 'لا يمكن تغيير اتجاه الوصل';end if;
   before_row:=to_jsonb(t);uid:=coalesce(t.cashbox_user_id,t.created_by);
  elsif payload->>'expectedToken' is not null then raise exception 'تغير الوصل؛ افتحه مجدداً' using errcode='40001';end if;
  r:=solar_private.fx_rate((payload->>'rate')::numeric,t.market_rate);
  perform set_config('solar.fx_context',jsonb_build_object('marketRate',r,'accountRevision',payload->'accountRevision','cashCurrency',cur)::text,true);
  v:=round(amt*case when cur='USD' then r else 1 end,2)*case when mode='cash' then 1 else -1 end;
  if t.id is null then
   insert into public.transactions(id,kind,party_type,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,notes,source_currency,exchange_rate,source_subtotal)
    values(tid,'supplier_payment','supplier',sid,s.name,v,mode='cash',mode,p.id,uid,payload->>'note',cur,case when cur='USD' then r else 1 end,amt*case when mode='cash' then 1 else -1 end);
  else
   update public.transactions set party_type='supplier',party_id=sid,party_name=s.name,total=v,cash=mode='cash',payment_mode=mode,notes=payload->>'note',source_currency=cur,exchange_rate=case when cur='USD' then r else 1 end,source_subtotal=amt*case when mode='cash' then 1 else -1 end where id=tid;
  end if;
  perform set_config('solar.fx_context','',true);
  result:=solar_private.supplier_payment_get(tid);
 end if;
 insert into solar_private.fx_requests(request_id,actor_id,action,payload,response,before_row) values(request_id,p.id,action,payload,result,before_row);
 return result;
end $$;

-- Return snapshots on the existing authorized receipt endpoint as well.
create or replace function solar_private.supplier_payment_get(payment_id bigint) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;t public.transactions;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true' or coalesce(p.permissions->>'supplierStatement','false')='true') then raise exception 'لا تملك صلاحية الوصل' using errcode='42501';end if;
 select * into t from public.transactions where id=payment_id and kind='supplier_payment';
 if t.id is null or (p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id) is distinct from true then raise exception 'لا تملك صلاحية الوصل' using errcode='42501';end if;
 return jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'supplierId',t.party_id,'party',t.party_name,'total',t.total,'cash',t.cash,'mode',t.payment_mode,'notes',t.notes,'date',t.created_at,'token',md5(to_jsonb(t)::text),
 'sourceCurrency',t.source_currency,'sourceSubtotal',coalesce(t.source_subtotal,t.total),'exchangeRate',t.exchange_rate,'marketRate',t.market_rate,'accountCurrency',t.account_currency,'accountAmount',t.account_amount,'accountRevision',t.account_revision,'cashCurrency',t.cash_currency,'cashAmount',t.cash_amount,'fxAccounted',t.fx_accounted);
end $$;
revoke all on function solar_private.usd_wallet(uuid),solar_private.fx_rate(numeric,numeric),solar_private.fx_guard(),solar_private.fx_prepare(),solar_private.fx_post(),solar_private.fx(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function solar_private.fx(text,uuid,jsonb) to authenticated;
create function public.solar_fx(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select solar_private.fx(action,request_id,payload)$$;
revoke all on function public.solar_fx(text,uuid,jsonb) from public,anon;
grant execute on function public.solar_fx(text,uuid,jsonb) to authenticated;

-- Older IQD-only forms must fail clearly on a denominated/converted account.
do $$declare def text;needle text:='if s.id is null then';begin
 select pg_get_functiondef('solar_private.supplier_account(bigint,bigint)'::regprocedure) into def;
 if strpos(def,needle)=0 then raise exception 'Review legacy supplier account integration';end if;
 execute replace(def,needle,'if s.id is not null and (s.account_currency<>''IQD'' or s.currency_revision<>0) then raise exception ''تم تفعيل عملة حساب المورد؛ حدّث البرنامج لاستخدام الحساب الصحيح'';end if; '||needle);
end $$;

-- Supplier reports must use the denomination ledger, never total IQD as USD.
do $$declare def text;needle text:=E'begin\n';replacement text;begin
 select pg_get_functiondef('solar_private.party_balances(text,date)'::regprocedure) into def;
 execute replace(def,'solar_private.party_balances(', 'solar_private.party_balances_legacy_iqd(');
 execute 'revoke all on function solar_private.party_balances_legacy_iqd(text,date) from public,anon,authenticated';
 replacement:=$code$begin
 if report_kind='suppliers' then return solar_private.supplier_fx_balances(as_of);end if;
$code$;
 execute overlay(def placing replacement from strpos(def,needle) for length(needle));
end $$;
create function solar_private.supplier_fx_balances(as_of date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;rows jsonb;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'supplierBalances','false')='true') then raise exception 'لا تملك صلاحية أرصدة الموردين' using errcode='42501';end if;
 if as_of is null or as_of>(now() at time zone 'Asia/Baghdad')::date then raise exception 'اختر تاريخاً صحيحاً';end if;
 with dated as(select * from solar_private.supplier_fx_entries e where (e.created_at at time zone 'Asia/Baghdad')::date<=as_of),
 current_revision as(select supplier_id,max(revision) revision from dated group by supplier_id),
 totals as(select e.supplier_id,e.currency,sum(e.delta) balance,sum(e.book_delta) book_balance from dated e join current_revision r using(supplier_id,revision) where p.is_admin or e.owner_id=p.id group by e.supplier_id,e.currency)
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'phone',s.phone,'currency',coalesce(t.currency,s.account_currency),'balance',coalesce(t.balance,0),'book_balance',coalesce(t.book_balance,0),
 'last_payment',last_pay.amount,'last_payment_at',last_pay.created_at)),'[]') into rows
 from public.suppliers s left join totals t on t.supplier_id=s.id left join lateral(
  select -e.delta amount,e.created_at from dated e join current_revision r using(supplier_id,revision) join public.transactions x on x.id=e.transaction_id
  where e.supplier_id=s.id and x.kind='supplier_payment' and x.cash and e.delta<0 and(p.is_admin or e.owner_id=p.id) order by e.id desc limit 1) last_pay on true;
 return jsonb_build_object('rows',rows,'as_of',as_of,'scope',case when p.is_admin then 'جميع المستخدمين' else 'حركات قاصتي' end,'unresolved_rows',solar_private.party_balances_legacy_iqd('suppliers',as_of)->'unresolved_rows');
end $$;
revoke all on function solar_private.supplier_fx_balances(date) from public,anon,authenticated;

-- Include the new ledgers in the existing reset snapshot/locking and clear them
-- only after that existing password-confirmed backup workflow has succeeded.
do $$declare def text;begin
 if to_regprocedure('solar_private.reset_snapshot()') is not null then
  select pg_get_functiondef('solar_private.reset_snapshot()'::regprocedure) into def;
  execute replace(def,'''solar_private.receipt_counters''','''solar_private.supplier_fx_entries'',''solar_private.wallet_fx_entries'',''solar_private.fx_requests'',''solar_private.receipt_counters''');
  select pg_get_functiondef('solar_private.lock_reset_tables()'::regprocedure) into def;
  execute replace(def,'solar_private.receipt_counters','solar_private.supplier_fx_entries,solar_private.wallet_fx_entries,solar_private.fx_requests,solar_private.receipt_counters');
  select pg_get_functiondef('public.solar_execute_reset(uuid,uuid,text)'::regprocedure) into def;
  if strpos(lower(def),'delete from public.transactions')=0 then raise exception 'Review reset ledger integration';end if;
  execute replace(def,'delete from public.transactions','delete from solar_private.supplier_fx_entries; delete from solar_private.wallet_fx_entries; delete from solar_private.fx_requests; delete from public.transactions');
 end if;
end $$;
notify pgrst,'reload schema';
