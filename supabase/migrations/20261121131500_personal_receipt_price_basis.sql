-- A personal reference price belongs to the sale. The company's transaction
-- and transaction_items remain the accounting source for inventory and cash.
create table solar_private.personal_price_receipts (
 invoice_id bigint primary key references public.transactions(id) on delete cascade,
 source_user_id uuid not null,
 created_at timestamptz not null default statement_timestamp()
);
create table solar_private.personal_price_items (
 invoice_id bigint not null references solar_private.personal_price_receipts(invoice_id) on delete cascade,
 product_id bigint not null,
 reference_price numeric check (reference_price > 0),
 primary key (invoice_id, product_id)
);
alter table solar_private.personal_price_receipts enable row level security;
alter table solar_private.personal_price_items enable row level security;
revoke all on solar_private.personal_price_receipts, solar_private.personal_price_items from public, anon, authenticated;

create function solar_private.personal_price_enabled(person uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=person and p.active and not p.is_admin
  and p.user_type not in ('installer','warehouse') and p.permissions @> '{"profitUsesWholesalePrice":true}')
$$;
create function solar_private.viewer_uses_personal_prices() returns boolean
language sql stable security definer set search_path='' as $$ select solar_private.personal_price_enabled(auth.uid()) $$;

-- The material checkbox controls eligibility independently of global enforcement
-- of the wholesale selling floor. An absent or disabled reference uses the
-- invoice line's own historical cost for personal profit.
create function solar_private.personal_product_price(product_id bigint) returns numeric
language sql stable security invoker set search_path='' as $$
 select p.minimum_price from solar_private.wholesale_product_prices p
 where p.product_id=$1 and p.enabled and p.minimum_price>0
$$;
create function solar_private.personal_receipt_priced(invoice_id bigint) returns boolean
language sql stable security invoker set search_path='' as $$
 select exists(select 1 from solar_private.personal_price_receipts r where r.invoice_id=$1)
$$;
create function solar_private.personal_line_has_price(invoice_id bigint,product_id bigint) returns boolean
language sql stable security invoker set search_path='' as $$
 select exists(select 1 from solar_private.personal_price_items i where i.invoice_id=$1 and i.product_id=$2 and i.reference_price is not null)
$$;
create function solar_private.personal_line_cost(invoice_id bigint,product_id bigint,actual_cost numeric) returns numeric
language sql stable security invoker set search_path='' as $$
 select coalesce((select i.reference_price from solar_private.personal_price_items i where i.invoice_id=$1 and i.product_id=$2),$3)
$$;
create function solar_private.personal_material_cost(invoice_id bigint,actual_total numeric) returns numeric
language sql stable security invoker set search_path='' as $$
 select case when solar_private.personal_receipt_priced($1) then coalesce((
  select round(sum(i.qty*coalesce(s.reference_price,i.cost)),2)
  from public.transaction_items i left join solar_private.personal_price_items s
   on (s.invoice_id,s.product_id)=(i.transaction_id,i.product_id)
  where i.transaction_id=$1
 ),$2) else $2 end
$$;
revoke all on function solar_private.personal_price_enabled(uuid),solar_private.personal_product_price(bigint),
 solar_private.personal_receipt_priced(bigint),solar_private.personal_line_has_price(bigint,bigint),
 solar_private.personal_line_cost(bigint,bigint,numeric),solar_private.personal_material_cost(bigint,numeric),
 solar_private.viewer_uses_personal_prices() from public,anon,authenticated;
grant execute on function solar_private.viewer_uses_personal_prices() to authenticated;

create function solar_private.capture_personal_price_receipt() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if solar_private.personal_price_enabled(coalesce(new.created_by,new.cashbox_user_id)) then
  insert into solar_private.personal_price_receipts(invoice_id,source_user_id)
  values(new.id,coalesce(new.created_by,new.cashbox_user_id));
 end if;
 return null;
end$$;
create function solar_private.capture_personal_price_item() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 -- Invoice edits can replace every item row. The first decision for each
 -- product (including an absent reference) survives this delete/insert cycle.
 if solar_private.personal_receipt_priced(new.transaction_id) then
  insert into solar_private.personal_price_items(invoice_id,product_id,reference_price)
  values(new.transaction_id,new.product_id,solar_private.personal_product_price(new.product_id))
  on conflict(invoice_id,product_id) do nothing;
 end if;
 return null;
end$$;
revoke all on function solar_private.capture_personal_price_receipt(),solar_private.capture_personal_price_item() from public,anon,authenticated;
create trigger solar_capture_personal_price_receipt after insert on public.transactions
 for each row when(new.kind in ('sale','system')) execute function solar_private.capture_personal_price_receipt();
create trigger solar_capture_personal_price_item after insert or update of transaction_id, product_id on public.transaction_items
 for each row when(new.product_id is not null) execute function solar_private.capture_personal_price_item();

-- Keep the price basis in the same snapshot/transaction as the existing
-- employee wizard. Older clients omit this new flag when saving other grants.
do $wizard$
declare definition text:=pg_get_functiondef('public.solar_admin_user_wizard(uuid,text,uuid,jsonb)'::regprocedure);
 anchor constant text:=$a$  if scope is not null then$a$;
begin
 if md5(definition)<>'cb614fe9d8d296e5b3d2d04d8046a1ac' or strpos(definition,anchor)=0 then
  raise exception 'Review employee wizard before extending personal price-basis management';end if;
 execute replace(definition,anchor,$b$
  if role_name='user' and not (requested_grants ? 'profitUsesWholesalePrice')
     and target.permissions @> '{"profitUsesWholesalePrice":true}'::jsonb then
   requested_grants:=requested_grants||jsonb_build_object('profitUsesWholesalePrice',true);
  end if;
$b$||anchor);
end$wizard$;

create function solar_private.profit_basis_user_state() returns jsonb
language sql stable security invoker set search_path='' as $$
 with people as (
  select p.id,solar_private.user_name(p.display_name,p.username,p.honorific) as name,p.active,p.updated_at,
    coalesce(p.permissions @> '{"profitUsesWholesalePrice":true}',false) as enabled
  from public.profiles p where not p.is_admin and p.user_type not in ('installer','warehouse')
 )
 select jsonb_build_object('users',coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'active',active,'enabled',enabled)
    order by active desc,name,id),'[]'),
  'token',md5(coalesce(jsonb_agg(jsonb_build_array(id,enabled,active,updated_at) order by id),'[]')::text))
 from people
$$;
revoke all on function solar_private.profit_basis_user_state() from public,anon,authenticated;

create function solar_private.profit_basis_users(action text,request_id uuid,payload jsonb) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare actor uuid:=auth.uid(); current_state jsonb; previous solar_private.finance_requests;
 changes jsonb; num integer; unique_targets integer; before_values jsonb;
begin
 if action not in ('state','save') or action is null then raise exception 'طلب إعداد غير معروف' using errcode='22023';end if;
 if action='save' then perform pg_advisory_xact_lock(7311,1);end if;
 if solar_private.role_name() is distinct from 'admin' then raise exception 'تحديد أساس ربح المستخدمين للأدمن فقط' using errcode='42501';end if;
 current_state:=solar_private.profit_basis_user_state();
 if action='state' then return current_state;end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' then
  raise exception 'أعد فتح إعداد أساس الربح' using errcode='22023';end if;
 select f.* into previous from solar_private.finance_requests f where f.request_id=profit_basis_users.request_id;
 if found then
  if previous.actor_id<>actor or previous.action<>'personal_price_users' or previous.payload is distinct from payload then
   raise exception 'معرّف الحفظ مستخدم لطلب آخر' using errcode='PT409';end if;
  return current_state;
 end if;
 if payload->>'token' is distinct from current_state->>'token' then
  raise exception 'تغيّرت إعدادات المستخدمين. حدّث القائمة وراجع الاختيار.' using errcode='PT409';end if;
 changes:=payload->'changes';
 if jsonb_typeof(changes) is distinct from 'array' then raise exception 'اختر المستخدمين أولاً' using errcode='22023';end if;
 if jsonb_array_length(changes)=0 or exists(select from jsonb_array_elements(changes) c
  where jsonb_typeof(c) is distinct from 'object' or jsonb_typeof(c->'enabled') is distinct from 'boolean'
  or jsonb_typeof(c->'id') is distinct from 'string' or (c->>'id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
  raise exception 'تأكد من أسماء المستخدمين واختياراتهم' using errcode='22023';end if;
 select count(*),count(distinct id) into num,unique_targets from jsonb_to_recordset(changes)c(id uuid,enabled boolean);
 if num<>unique_targets then raise exception 'أحد المستخدمين مكرر' using errcode='22023';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'enabled',coalesce(p.permissions @> '{"profitUsesWholesalePrice":true}',false))
  order by p.id),'[]'::jsonb) into before_values from public.profiles p
 join jsonb_to_recordset(changes)c(id uuid,enabled boolean) on c.id=p.id
 where not p.is_admin and p.user_type not in ('installer','warehouse');
 if jsonb_array_length(before_values)<>num then raise exception 'اختر مستخدم مكتب من القائمة' using errcode='22023';end if;
 update public.profiles p set permissions=coalesce(p.permissions,'{}'::jsonb)||jsonb_build_object('profitUsesWholesalePrice',c.enabled),
  updated_at=clock_timestamp() from jsonb_to_recordset(changes)c(id uuid,enabled boolean)
 where p.id=c.id and (coalesce(p.permissions @> '{"profitUsesWholesalePrice":true}',false)) is distinct from c.enabled;
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response)
 values(request_id,actor,'personal_price_users',payload,jsonb_build_object('before',before_values,'after',changes));
 return solar_private.profit_basis_user_state();
end$$;
create function public.solar_profit_basis_users(action text default 'state',request_id uuid default null,payload jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select solar_private.profit_basis_users(action,request_id,payload)$$;
revoke all on function solar_private.profit_basis_users(text,uuid,jsonb),public.solar_profit_basis_users(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function solar_private.profit_basis_users(text,uuid,jsonb),public.solar_profit_basis_users(text,uuid,jsonb) to authenticated;

-- These two derived ledgers hold historical reference prices which cannot be
-- reconstructed from the latest price list when a reset backup is taken.
do $reset$
declare definition text;
begin
 definition:=pg_get_functiondef('solar_private.reset_snapshot()'::regprocedure);
 if strpos(definition,'''solar_private.invoice_profit_owners''')=0 then raise exception 'Unexpected reset snapshot';end if;
 execute replace(definition,'''solar_private.invoice_profit_owners''',
  '''solar_private.personal_price_receipts'',''solar_private.personal_price_items'',''solar_private.invoice_profit_owners''');
 definition:=pg_get_functiondef('solar_private.lock_reset_tables()'::regprocedure);
 if strpos(definition,'solar_private.invoice_profit_owners,solar_private.invoice_profit_owner_audit')=0 then raise exception 'Unexpected reset locks';end if;
 execute replace(definition,'solar_private.invoice_profit_owners,solar_private.invoice_profit_owner_audit',
  'solar_private.personal_price_receipts,solar_private.personal_price_items,solar_private.invoice_profit_owners,solar_private.invoice_profit_owner_audit');
end$reset$;
notify pgrst,'reload schema';
