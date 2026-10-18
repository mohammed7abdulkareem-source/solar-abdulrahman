-- Append-only admin corrections: no deletion of receipts, supplier debt or profit.
create function solar_private.cash_reconcile(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
#variable_conflict use_variable
declare actor public.profiles;prior solar_private.finance_requests;uid uuid;owners jsonb;rows jsonb;pending jsonb;token text;
 mode text;cur text;target numeric;r numeric;row jsonb;changes jsonb:='[]';before_iqd numeric;before_usd numeric;before_book numeric;after_iqd numeric;after_usd numeric;after_book numeric;number bigint;result jsonb;
begin
 select * into actor from public.profiles where id=auth.uid() and active and is_admin;
 if actor.id is null then raise exception 'تعديل وتصفير القاصات متاح للأدمن فقط' using errcode='42501';end if;
 if action is null or action not in ('context','apply') or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب غير صحيح';end if;
 if action='apply' then
  if request_id is null then raise exception 'رقم طلب التسوية مطلوب';end if;
  perform pg_advisory_xact_lock(7311,1);
  select * into prior from solar_private.finance_requests f where f.request_id=cash_reconcile.request_id;
  if found then
   if prior.actor_id=actor.id and prior.action='cash_reconcile' and prior.payload=payload then return prior.response;end if;
   raise exception 'طلب مكرر ببيانات مختلفة' using errcode='40001';
  end if;
 end if;
 uid:=nullif(payload->>'ownerId','')::uuid;
 if uid is not null and not exists(select 1 from public.profiles where id=uid) then raise exception 'القاصة غير موجودة';end if;
 with balances as(select m.owner_id,sum(m.delta) filter(where m.currency='IQD') iqd,sum(m.delta) filter(where m.currency='USD') usd,sum(m.book_delta) filter(where m.currency='USD') book from solar_private.cash_movements() m group by m.owner_id)
 select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'name',coalesce(u.display_name,u.username,'مستخدم'),'active',u.active,'IQD',coalesce(b.iqd,0),'USD',coalesce(b.usd,0),'usdBook',coalesce(b.book,0)) order by u.id),'[]') into owners from public.profiles u left join balances b on b.owner_id=u.id where u.user_type not in ('installer','warehouse') or b.owner_id is not null or u.id=uid;
 select coalesce(jsonb_agg(x order by x->>'id'),'[]') into rows from jsonb_array_elements(owners) x where uid is null or x->>'id'=uid::text;
 select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]') into pending from solar_private.cash_transfers t where t.status='pending' and(uid is null or uid in(t.sender_id,t.recipient_id));
 token:=md5(rows::text||pending::text);
 if action='context' then return jsonb_build_object('owners',owners,'rows',rows,'pendingCount',jsonb_array_length(pending),'token',token);end if;
 if payload->>'expectedToken' is distinct from token then raise exception 'تغيّر رصيد القاصة؛ حدّث الأرصدة وراجع التسوية من جديد' using errcode='40001';end if;
 if jsonb_array_length(pending)>0 then raise exception 'توجد عمليات تسليم قاصة معلّقة؛ احسم الاستلام أو الإلغاء قبل التسوية';end if;
 mode:=payload->>'mode';cur:=payload->>'currency';target:=(payload->>'target')::numeric;
 if mode is null or mode not in ('set','zero') or cur is null or cur not in ('IQD','USD','both') or (mode='set' and(uid is null or cur='both')) or (uid is null and(mode<>'zero' or cur<>'both')) then raise exception 'اختر قاصة وعملة للتعديل، أو تصفير الجميع';end if;
 if length(trim(coalesce(payload->>'note','')))<3 or length(payload->>'note')>2000 then raise exception 'اكتب سبب التسوية بوضوح';end if;
 if mode='zero' then target:=0;end if;
 if target is null or not(target>=0 and target<=1000000000000) or target::text in ('NaN','Infinity','-Infinity') or round(target,2)<>target then raise exception 'أدخل الرصيد الصحيح بصفر أو مبلغ موجب وبحد أقصى منزلتين';end if;
 for row in select x from jsonb_array_elements(rows) x loop
  before_iqd:=(row->>'IQD')::numeric;before_usd:=(row->>'USD')::numeric;before_book:=(row->>'usdBook')::numeric;
  after_iqd:=case when cur in('IQD','both') then target else before_iqd end;after_usd:=case when cur in('USD','both') then target else before_usd end;after_book:=before_book;r:=1;
  if cur in('USD','both') then
   if after_usd=0 then after_book:=0;
   elsif after_usd<before_usd and before_usd>0 then after_book:=round(before_book*after_usd/before_usd,2);
   elsif after_usd>before_usd then
    r:=solar_private.fx_rate((payload->>'rate')::numeric);
    after_book:=case when before_usd>0 then before_book+round((after_usd-before_usd)*r,2) else round(after_usd*r,2) end;
   end if;
  end if;
  if (after_iqd,after_usd,after_book) is not distinct from(before_iqd,before_usd,before_book) then continue;end if;
  if after_iqd<>before_iqd then insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,gain,entry_type,note,finance_request_id) values((row->>'id')::uuid,'IQD',after_iqd-before_iqd,after_iqd-before_iqd,1,0,'cash_reconcile',trim(payload->>'note'),request_id);end if;
  if after_usd<>before_usd or after_book<>before_book then insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,gain,entry_type,note,finance_request_id) values((row->>'id')::uuid,'USD',after_usd-before_usd,after_book-before_book,case when after_usd<>before_usd then abs((after_book-before_book)/(after_usd-before_usd)) else r end,0,'cash_reconcile',trim(payload->>'note'),request_id);end if;
  changes:=changes||jsonb_build_array(jsonb_build_object('ownerId',row->>'id','ownerName',row->>'name','beforeIQD',before_iqd,'afterIQD',after_iqd,'beforeUSD',before_usd,'afterUSD',after_usd,'beforeBook',before_book,'afterBook',after_book));
 end loop;
 if jsonb_array_length(changes)=0 then raise exception 'الأرصدة مطابقة بالفعل؛ لا توجد تسوية للحفظ';end if;
 insert into solar_private.receipt_counters(kind,last_number) values('cash_reconcile',1) on conflict(kind) do update set last_number=solar_private.receipt_counters.last_number+1 returning last_number into number;
 result:=jsonb_build_object('requestId',request_id,'receiptNo',number,'date',now(),'mode','cash_reconcile','rows',changes,'note',trim(payload->>'note'),'actorName',coalesce(actor.display_name,actor.username),'ownerName',case when uid is null then 'جميع القاصات' else rows->0->>'name' end);
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response) values(request_id,actor.id,'cash_reconcile',payload,result);
 return result;
end $$;
create function public.solar_cash_reconcile(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select solar_private.cash_reconcile(action,request_id,payload)$$;
revoke all on function solar_private.cash_reconcile(text,uuid,jsonb),public.solar_cash_reconcile(text,uuid,jsonb) from public,anon;
grant execute on function solar_private.cash_reconcile(text,uuid,jsonb),public.solar_cash_reconcile(text,uuid,jsonb) to authenticated;

-- Owners may read only their own rows of a multi-cashbox correction receipt.
create or replace function solar_private.cash_receipt(request_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;r solar_private.finance_requests;visible_rows jsonb;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'cash','false')='true') then raise exception 'غير مسموح' using errcode='42501';end if;
 select * into r from solar_private.finance_requests f where f.request_id=cash_receipt.request_id and f.action in('cash','cash_reconcile');
 if r.request_id is null then raise exception 'الوصل غير موجود' using errcode='42501';end if;
 if r.action='cash_reconcile' then
  select coalesce(jsonb_agg(x),'[]') into visible_rows from jsonb_array_elements(r.response->'rows') x where p.is_admin or x->>'ownerId'=p.id::text;
  if jsonb_array_length(visible_rows)=0 then raise exception 'لا تملك صلاحية هذا الوصل' using errcode='42501';end if;
  return r.response||jsonb_build_object('rows',visible_rows,'ownerName',case when p.is_admin then r.response->>'ownerName' else coalesce(p.display_name,p.username) end);
 end if;
 if(p.is_admin or r.response->>'ownerId'=p.id::text) is distinct from true then raise exception 'لا تملك صلاحية هذا الوصل' using errcode='42501';end if;
 return r.response;
end $$;
