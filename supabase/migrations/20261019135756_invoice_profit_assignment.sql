-- Attribute the profit without changing invoice authorship, customer debt, cash, or fixed costs.
create table solar_private.invoice_profit_owners(
 invoice_id bigint primary key references public.transactions(id) on delete cascade,
 owner_id uuid not null references public.profiles(id),revision bigint not null default 1,
 updated_by uuid references public.profiles(id) on delete set null,updated_at timestamptz not null default now()
);
create index invoice_profit_owners_owner_idx on solar_private.invoice_profit_owners(owner_id);
create index invoice_profit_owners_actor_idx on solar_private.invoice_profit_owners(updated_by);
create table solar_private.invoice_profit_owner_audit(
 id uuid primary key default gen_random_uuid(),request_id uuid not null,
 invoice_id bigint not null references public.transactions(id) on delete cascade,
 before_owner uuid references public.profiles(id) on delete set null,after_owner uuid references public.profiles(id) on delete set null,
 actor_id uuid references public.profiles(id) on delete set null,profit numeric not null,note text not null default '',created_at timestamptz not null default now(),
 unique(request_id,invoice_id)
);
create index invoice_profit_audit_invoice_idx on solar_private.invoice_profit_owner_audit(invoice_id);
create index invoice_profit_audit_before_idx on solar_private.invoice_profit_owner_audit(before_owner);
create index invoice_profit_audit_after_idx on solar_private.invoice_profit_owner_audit(after_owner);
create index invoice_profit_audit_actor_idx on solar_private.invoice_profit_owner_audit(actor_id);
alter table solar_private.invoice_profit_owners enable row level security;
alter table solar_private.invoice_profit_owner_audit enable row level security;
create policy profit_owners_admin_read on solar_private.invoice_profit_owners for select to authenticated using((select solar_private.role_name())='admin');
create policy profit_owners_audit_admin_read on solar_private.invoice_profit_owner_audit for select to authenticated using((select solar_private.role_name())='admin');
revoke all on solar_private.invoice_profit_owners,solar_private.invoice_profit_owner_audit from public,anon,authenticated;

-- Update only the sale ownership predicate; expenses, cash and withdrawals keep their actual owner.
do $$declare def text;needle text;begin
 select pg_get_functiondef('solar_private.profit_rows(uuid)'::regprocedure) into def;
 needle:='coalesce(t.cashbox_user_id,t.created_by)=uid and t.profit_settlement_id is null';
 if strpos(def,needle)=0 then raise exception 'Review profit sources before attribution';end if;
 def:=replace(def,needle,'(case when t.kind in(''sale'',''system'') then coalesce((select a.owner_id from solar_private.invoice_profit_owners a where a.invoice_id=t.id),t.cashbox_user_id,t.created_by) else coalesce(t.cashbox_user_id,t.created_by) end)=uid and t.profit_settlement_id is null');
 needle:='coalesce(t.party_name,t.notes,''حركة أرباح'') label';
 if strpos(def,needle)=0 then raise exception 'Review profit detail labels';end if;
 def:=replace(def,needle,'case when coalesce(t.created_by,t.cashbox_user_id)<>uid then ''ربح فاتورة محوّل من الإدارة'' else coalesce(t.party_name,t.notes,''حركة أرباح'') end label');
 execute def;
 select pg_get_functiondef('solar_private.retained_profit(uuid)'::regprocedure) into def;
 needle:='(t.kind=''sale'' or(t.kind=''system'' and t.installation_status=''closed'')) and coalesce(t.cashbox_user_id,t.created_by)=uid';
 if strpos(def,needle)=0 then raise exception 'Review retained-profit ownership';end if;
 execute replace(def,needle,'(t.kind=''sale'' or(t.kind=''system'' and t.installation_status=''closed'')) and coalesce((select a.owner_id from solar_private.invoice_profit_owners a where a.invoice_id=t.id),t.cashbox_user_id,t.created_by)=uid');
end$$;

create function solar_private.profit_transfer(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
#variable_conflict use_variable
declare p public.profiles;target public.profiles;ids bigint[];inv public.transactions;item jsonb;owner uuid;rev bigint;rows jsonb:='[]';amount numeric;total numeric:=0;token text;prior solar_private.finance_requests;result jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active and is_admin and user_type not in('warehouse','installer');
 if p.id is null then raise exception 'تحويل الأرباح للإدارة فقط' using errcode='42501';end if;
 if action='list' then return jsonb_build_object('assignments',(select coalesce(jsonb_agg(jsonb_build_object('invoiceId',a.invoice_id,'ownerId',a.owner_id,'revision',a.revision)),'[]') from solar_private.invoice_profit_owners a));end if;
 if action is null or action not in('preview','apply') or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب غير صحيح';end if;
 if action='apply' then
  if request_id is null then raise exception 'رقم الطلب مطلوب';end if;
  perform pg_advisory_xact_lock(7311,1);
  select * into prior from solar_private.finance_requests f where f.request_id=profit_transfer.request_id;
  if prior.request_id is not null then
   if prior.actor_id<>p.id or prior.action<>'profit_transfer' or prior.payload<>payload then raise exception 'طلب مكرر ببيانات مختلفة' using errcode='PT409';end if;
   return prior.response;
  end if;
 end if;
 if jsonb_typeof(payload->'invoiceIds') is distinct from 'array' or jsonb_array_length(payload->'invoiceIds') not between 1 and 100 then raise exception 'اختر من فاتورة إلى 100 فاتورة';end if;
 select array_agg(distinct value::text::bigint order by value::text::bigint) into ids from jsonb_array_elements(payload->'invoiceIds');
 select * into target from public.profiles where id=(payload->>'ownerId')::uuid and active and user_type not in('installer','warehouse');
 if target.id is null then raise exception 'اختر مستخدماً فعالاً لاستلام الربح';end if;
 if length(coalesce(payload->>'note',''))>1000 then raise exception 'الملاحظة طويلة';end if;
 for inv in select * from public.transactions where id=any(ids) order by id for update loop
  if inv.kind not in('sale','system') or(inv.kind='system' and inv.installation_status<>'closed') then raise exception 'يُحوّل ربح البيع أو المنظومة المغلقة فقط';end if;
  select a.owner_id,a.revision into owner,rev from solar_private.invoice_profit_owners a where a.invoice_id=inv.id;
  owner:=coalesce(owner,inv.cashbox_user_id,inv.created_by);rev:=coalesce(rev,0);
  if owner is null or owner=target.id then raise exception 'اختر مستخدماً آخر؛ إحدى الفواتير مسجّلة له بالفعل';end if;
  if exists(select 1 from solar_private.profit_checkpoints c where c.source_key='tx:'||inv.id) then raise exception 'ربح الفاتورة #% تمت تسويته سابقاً ولا يمكن نقله',inv.receipt_no;end if;
  if exists(select 1 from solar_private.profit_settlements s where s.status='pending' and exists(select 1 from jsonb_array_elements(s.snapshot)x where x->>'key'='tx:'||inv.id)) then raise exception 'الفاتورة #% ضمن طلب تسوية معلّق؛ احسم الطلب قبل التحويل',inv.receipt_no;end if;
  select value into item from jsonb_array_elements(solar_private.profit_rows(owner)) where value->>'key'='tx:'||inv.id;
  if item is null then raise exception 'ربح إحدى الفواتير غير متاح';end if;
  amount:=(item->>'value')::numeric;total:=total+amount;
  rows:=rows||jsonb_build_array(jsonb_build_object('invoiceId',inv.id,'receiptNo',inv.receipt_no,'party',inv.party_name,'date',inv.created_at,'ownerId',owner,'ownerName',(select coalesce(display_name,username) from public.profiles where id=owner),'targetName',coalesce(target.display_name,target.username),'profit',amount,'revision',rev));
 end loop;
 if jsonb_array_length(rows)<>cardinality(ids) then raise exception 'إحدى الفواتير لم تعد موجودة';end if;
 if exists(select 1 from(select (x->>'ownerId')::uuid owner_id,sum((x->>'profit')::numeric) value from jsonb_array_elements(rows)x group by 1) amounts where amounts.value>solar_private.retained_profit(amounts.owner_id) and exists(select 1 from public.transactions t where t.kind='profit_distribution' and coalesce(t.cashbox_user_id,t.created_by)=amounts.owner_id)) then raise exception 'جزء من أرباح صاحب الفواتير سُحب سابقاً؛ لا يمكن تحويل مبلغ مسحوب';end if;
 token:=md5(jsonb_build_object('rows',rows,'target',target.id)::text);
 result:=jsonb_build_object('rows',rows,'total',total,'ownerId',target.id,'ownerName',coalesce(target.display_name,target.username),'token',token);
 if action='preview' then return result;end if;
 if payload->>'expectedToken' is distinct from token then raise exception 'تغيّرت الفواتير أو أرباحها؛ اعرض المعاينة مجدداً' using errcode='PT409';end if;
 for item in select value from jsonb_array_elements(rows) loop
  insert into solar_private.invoice_profit_owners(invoice_id,owner_id,updated_by) values((item->>'invoiceId')::bigint,target.id,p.id)
  on conflict(invoice_id) do update set owner_id=excluded.owner_id,revision=solar_private.invoice_profit_owners.revision+1,updated_by=p.id,updated_at=now();
  insert into solar_private.invoice_profit_owner_audit(request_id,invoice_id,before_owner,after_owner,actor_id,profit,note) values(request_id,(item->>'invoiceId')::bigint,(item->>'ownerId')::uuid,target.id,p.id,(item->>'profit')::numeric,coalesce(payload->>'note',''));
 end loop;
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response) values(request_id,p.id,'profit_transfer',payload,result);
 return result;
end$$;
create function public.solar_profit_transfer(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select solar_private.profit_transfer(action,request_id,payload)$$;
revoke all on function solar_private.profit_transfer(text,uuid,jsonb),public.solar_profit_transfer(text,uuid,jsonb) from public,anon;
grant execute on function solar_private.profit_transfer(text,uuid,jsonb),public.solar_profit_transfer(text,uuid,jsonb) to authenticated;

-- New profit recipients see the attributed amount, not another user's invoice.
do $$declare def text;needle text;begin
 select pg_get_functiondef('solar_private.profit_detail(text,uuid)'::regprocedure) into def;
 needle:='then raise exception ''الوصل يخص مستخدماً آخر'' using errcode=''42501'';end if;';
 if strpos(def,needle)=0 then raise exception 'Review transfer recipient isolation';end if;
 execute replace(def,needle,'then return jsonb_build_object(''movement'',movement,''invoice'',null,''transferred'',true);end if;');
 select pg_get_functiondef('solar_private.reset_snapshot()'::regprocedure) into def;
 if strpos(def,'''solar_private.inventory_requests''')=0 then raise exception 'Review reset snapshot';end if;
 execute replace(def,'''solar_private.inventory_requests''','''solar_private.invoice_profit_owners'',''solar_private.invoice_profit_owner_audit'',''solar_private.inventory_requests''');
 select pg_get_functiondef('solar_private.lock_reset_tables()'::regprocedure) into def;
 if strpos(def,'solar_private.inventory_requests in share row exclusive mode')=0 then raise exception 'Review reset locks';end if;
 execute replace(def,'solar_private.inventory_requests in share row exclusive mode','solar_private.inventory_requests,solar_private.invoice_profit_owners,solar_private.invoice_profit_owner_audit in share row exclusive mode');
end$$;
