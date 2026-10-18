-- Settlement closes a reviewed profit snapshot, never the source invoices.
create table solar_private.profit_settlements(
 id uuid primary key, owner_id uuid not null references public.profiles(id),
 date_from date, date_to date not null, snapshot jsonb not null, profit numeric not null check(profit>0),
 status text not null default 'pending' check(status in('pending','approved','rejected','cancelled')),
 note text not null default '', created_at timestamptz not null default now(),
 decided_at timestamptz, decided_by uuid references public.profiles(id), decision_note text,
 share numeric, cash_owner_id uuid references public.profiles(id), receipt jsonb,
 check(date_from is null or date_from<=date_to),
 check(status<>'approved' or(share>0 and share<=profit and receipt is not null))
);
create unique index profit_one_pending on solar_private.profit_settlements(owner_id) where status='pending';
create index profit_settlements_owner on solar_private.profit_settlements(owner_id,created_at desc);
create table solar_private.profit_checkpoints(
 owner_id uuid not null references public.profiles(id), source_key text not null,
 value numeric not null, row_data jsonb not null,
 settlement_id uuid not null references solar_private.profit_settlements(id),
 primary key(owner_id,source_key)
);
alter table solar_private.profit_settlements enable row level security;
alter table solar_private.profit_checkpoints enable row level security;
revoke all on solar_private.profit_settlements,solar_private.profit_checkpoints from public,anon,authenticated;
alter table public.transactions add column profit_settlement_id uuid references solar_private.profit_settlements(id);
create unique index profit_settlement_expense_once on public.transactions(profit_settlement_id) where profit_settlement_id is not null;
create function solar_private.profit_expense_guard() returns trigger language plpgsql set search_path='' as $$begin
 if current_user in('authenticated','anon') and(new.profit_settlement_id is not null or(tg_op='UPDATE' and old.profit_settlement_id is not null)) then raise exception 'استخدم تسوية الأرباح المحمية' using errcode='42501';end if;
 return new;
end $$;
create trigger solar_profit_expense_guard before insert or update on public.transactions for each row execute function solar_private.profit_expense_guard();
revoke all on function solar_private.profit_expense_guard() from public,anon,authenticated;
create function solar_private.profit_rows(uid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with sources as(
 select 'tx:'||t.id source_key,t.created_at date,t.kind,coalesce(t.party_name,t.notes,'حركة أرباح') label,t.receipt_no,
 round(case when t.kind='system' then t.profit when t.kind='sale' then case when t.fx_pricing then t.profit else coalesce(t.subtotal,t.total)-coalesce((select sum(i.qty*i.cost) from public.transaction_items i where i.transaction_id=t.id),0) end else -t.total end,2) value
 from public.transactions t where coalesce(t.cashbox_user_id,t.created_by)=uid and t.profit_settlement_id is null
 and(t.kind='sale' or(t.kind='system' and t.installation_status='closed') or t.kind='profit_expense' or t.cash_purpose='expense')
 union all select 'entry:'||e.id,e.created_at,e.entry_type,coalesce(e.notes,'مصروف تسليم القاصة'),null,-abs(e.delta) from public.solar_cash_entries e where e.owner_id=uid and e.entry_type='handover_expense'
 union all select 'supplierfx:'||e.id,e.created_at,'fx_gain',coalesce(e.note,'فرق صرف مورد'),null,e.gain from solar_private.supplier_fx_entries e where e.owner_id=uid and e.gain<>0
 union all select 'walletfx:'||e.id,e.created_at,'fx_gain',coalesce(e.note,'فرق صرف قاصة'),null,e.gain from solar_private.wallet_fx_entries e where e.owner_id=uid and e.gain<>0
 ), rows as(
 select coalesce(s.source_key,c.source_key) key,coalesce(s.date,(c.row_data->>'date')::timestamptz) date,
 coalesce(s.kind,c.row_data->>'kind') kind,coalesce(s.label,c.row_data->>'label') label,
 coalesce(s.receipt_no,(c.row_data->>'receiptNo')::bigint) receipt_no,
 coalesce(s.value,0) value,coalesce(c.value,0) settled,s.source_key is null deleted
 from sources s full join(select * from solar_private.profit_checkpoints where owner_id=uid)c using(source_key)
 ) select coalesce(jsonb_agg(jsonb_build_object('key',key,'date',date,'kind',kind,'label',label,'receiptNo',receipt_no,'value',value,'settled',settled,'available',value-settled,'deleted',deleted) order by date,key),'[]') from rows
$$;
revoke all on function solar_private.profit_rows(uuid) from public,anon,authenticated;
create function solar_private.profit_snapshot(uid uuid,date_from date,date_to date) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(r order by r->>'date',r->>'key'),'[]') from jsonb_array_elements(solar_private.profit_rows(uid)) r
 where(date_from is null or(r->>'date')::timestamptz at time zone 'Asia/Baghdad'>=date_from::timestamp)
 and(r->>'date')::timestamptz at time zone 'Asia/Baghdad'<(date_to+1)::timestamp
$$;
revoke all on function solar_private.profit_snapshot(uuid,date,date) from public,anon,authenticated;
create function solar_private.profit_workspace(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
#variable_conflict use_variable
declare p public.profiles;r solar_private.profit_settlements;prior solar_private.finance_requests;uid uuid;start_date date;end_date date;
 snapshot jsonb;rows jsonb;result jsonb;amount numeric;total numeric;token text;cash jsonb;cash_owner uuid;expense_id bigint;item jsonb;reason text;
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
  select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('ownerName',coalesce(o.display_name,o.username),'decidedByName',coalesce(d.display_name,d.username),'token',md5(to_jsonb(s)::text)) order by s.created_at desc),'[]') into rows
  from solar_private.profit_settlements s join public.profiles o on o.id=s.owner_id left join public.profiles d on d.id=s.decided_by
  where (p.is_admin or s.owner_id=p.id) and(s.status='pending' or s.id in(select q.id from solar_private.profit_settlements q where(p.is_admin or q.owner_id=p.id) order by q.created_at desc limit 100));
  return jsonb_build_object('rows',snapshot,'available',total,'token',token,'from',start_date,'to',end_date,'ownerId',uid,
   'ownerName',(select coalesce(display_name,username) from public.profiles where id=uid),'canRequest',p.is_admin or p.permissions->>'profitSettlement'='true','requests',rows,
   'cashOwners',case when p.is_admin then(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'name',coalesce(o.display_name,o.username),'balance',solar_private.cash_balance(o.id)) order by o.display_name),'[]') from public.profiles o where o.active and o.user_type not in('installer','warehouse')) else '[]'::jsonb end);
 elsif action='request' then
  if not(p.is_admin or coalesce(p.permissions->>'profitSettlement','false')='true') then raise exception 'لا تملك صلاحية طلب تسوية الأرباح' using errcode='42501';end if;
  if payload->>'expectedToken' is distinct from token then raise exception 'تغيّرت الأرباح؛ حدّث الكشف قبل الطلب' using errcode='40001';end if;
  if total<=0 then raise exception 'لا توجد أرباح موجبة غير مسوّاة ضمن الفترة';end if;
  if exists(select 1 from solar_private.profit_settlements where owner_id=uid and status='pending') then raise exception 'لديك طلب قيد المراجعة؛ انتظر القرار أو ألغِ الطلب السابق';end if;
  if length(coalesce(payload->>'note',''))>2000 then raise exception 'الملاحظة طويلة';end if;
  insert into solar_private.profit_settlements(id,owner_id,date_from,date_to,snapshot,profit,note) values(request_id,uid,start_date,end_date,snapshot,total,coalesce(payload->>'note','')) returning * into r;
  insert into public.solar_notifications(user_id,event,title,body) select o.id,'profit_requested','طلب تسوية أرباح',coalesce(p.display_name,p.username)||' · أرباح مطلوب تسويتها: '||total::text||' د.ع' from public.profiles o where o.active and o.is_admin and o.user_type not in('installer','warehouse');
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
   amount:=(payload->>'share')::numeric;cash_owner:=nullif(payload->>'cashOwnerId','')::uuid;
   if amount is null or not(amount>0 and amount<=r.profit and amount<=1000000000000) or amount::text in('NaN','Infinity','-Infinity') or round(amount)<>amount then raise exception 'حدد حصة موجبة بالدينار لا تتجاوز ربح الطلب';end if;
   cash:=solar_private.cash_save(gen_random_uuid(),jsonb_build_object('ownerId',cash_owner,'mode','expense','currency','IQD','amount',amount,'note','حصة أرباح '||(select coalesce(display_name,username) from public.profiles where id=r.owner_id)||' · تسوية '||r.id::text||case when reason='' then '' else ' · '||reason end));
   expense_id:=(cash->>'id')::bigint;
   update public.transactions set profit_settlement_id=r.id where id=expense_id;
   for item in select * from jsonb_array_elements(r.snapshot) loop
    insert into solar_private.profit_checkpoints(owner_id,source_key,value,row_data,settlement_id) values(r.owner_id,item->>'key',(item->>'value')::numeric,item,r.id)
    on conflict(owner_id,source_key) do update set value=excluded.value,row_data=excluded.row_data,settlement_id=excluded.settlement_id;
   end loop;
   update solar_private.profit_settlements set status='approved',decided_at=now(),decided_by=p.id,decision_note=reason,share=amount,cash_owner_id=cash_owner,receipt=cash where id=r.id returning * into r;
  else
   if action='reject' and reason='' then raise exception 'اكتب سبب رفض الطلب';end if;
   update solar_private.profit_settlements set status=case action when 'cancel' then 'cancelled' else 'rejected' end,decided_at=now(),decided_by=p.id,decision_note=reason where id=r.id returning * into r;
  end if;
  insert into public.solar_notifications(user_id,event,title,body) values(r.owner_id,'profit_decided',case r.status when 'approved' then 'تمت تسوية أرباحك وصرف حصتك' when 'rejected' then 'تم رفض طلب تسوية الأرباح' else 'تم إلغاء طلب تسوية الأرباح' end,case when r.status='approved' then 'حصتك المصروفة: '||r.share::text||' د.ع · كشف الفترة محفوظ في سجل التسويات' else reason end);
 end if;
 result:=to_jsonb(r);
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response) values(request_id,p.id,'profit_'||action,payload,result);
 return result;
end $$;
create function public.solar_profit_workspace(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select solar_private.profit_workspace(action,request_id,payload)$$;
revoke all on function solar_private.profit_workspace(text,uuid,jsonb),public.solar_profit_workspace(text,uuid,jsonb) from public,anon;
grant execute on function solar_private.profit_workspace(text,uuid,jsonb),public.solar_profit_workspace(text,uuid,jsonb) to authenticated;
-- Preserve all existing notification event kinds as the application evolves.
do $$declare old_check text;begin
 select pg_get_expr(conbin,conrelid) into old_check from pg_constraint where conrelid='public.solar_notifications'::regclass and conname='solar_notifications_event_check';
 if old_check is null then raise exception 'notification event constraint missing';end if;
 alter table public.solar_notifications drop constraint solar_notifications_event_check;
 execute 'alter table public.solar_notifications add constraint solar_notifications_event_check check(('||old_check||') or event in(''profit_requested'',''profit_decided''))';
end $$;
notify pgrst,'reload schema';
