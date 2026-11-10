-- Refuse to patch an unreviewed invoice posting definition.
do $$begin
 if md5(pg_get_functiondef('solar_private.invoice_save(uuid,jsonb)'::regprocedure))is distinct from'2b36e76e0ac2ed2dd6fc5f28585f40c5'then
  raise exception 'invoice_save changed; review the live wholesale pricing integration before applying this migration';
 end if;
end $$;

-- Wholesale price floors are opt-in. This migration creates private policy and
-- validation metadata only; it never changes a historical invoice or its costs.
create table solar_private.wholesale_pricing_control(
 id boolean primary key default true check(id),enabled boolean not null default false,
 revision bigint not null default 0,updated_at timestamptz,updated_by uuid references public.profiles(id) on delete set null
);
insert into solar_private.wholesale_pricing_control(id)values(true);
create table solar_private.wholesale_product_prices(
 product_id bigint primary key references public.products(id) on delete cascade,
 minimum_price numeric,enabled boolean not null default false,revision bigint not null default 0,
 updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id) on delete set null,
 check(minimum_price is null or(minimum_price::text not in('NaN','Infinity','-Infinity')and minimum_price>=0 and minimum_price<=1000000000000 and round(minimum_price,2)=minimum_price)),
 check(not enabled or(minimum_price is not null and minimum_price>0))
);
create table solar_private.wholesale_pricing_audit(
 id bigint generated always as identity primary key,request_id uuid not null,actor_id uuid not null,
 action text not null,product_id bigint,before_value jsonb,after_value jsonb not null,created_at timestamptz not null default now()
);
create table solar_private.wholesale_invoice_pricing(
 invoice_id bigint primary key references public.transactions(id) on delete cascade,
 accepted_signature jsonb not null,policy_revision bigint not null default 0,
 prices_snapshot jsonb not null default '[]',enforced boolean not null default false,
 override_used boolean not null default false,actor_id uuid,accepted_at timestamptz not null default now()
);
alter table solar_private.wholesale_pricing_control enable row level security;
alter table solar_private.wholesale_product_prices enable row level security;
alter table solar_private.wholesale_pricing_audit enable row level security;
alter table solar_private.wholesale_invoice_pricing enable row level security;
revoke all on solar_private.wholesale_pricing_control,solar_private.wholesale_product_prices,solar_private.wholesale_pricing_audit,solar_private.wholesale_invoice_pricing from public,anon,authenticated;

create function solar_private.wholesale_economic_signature(invoice_id bigint)returns jsonb
language sql stable security definer set search_path=''as $$
 select jsonb_build_object('kind',t.kind,'currency',t.source_currency,'exchangeRate',t.exchange_rate,
  'net',least(coalesce(t.subtotal,t.total-coalesce(t.expenses,0)),t.total-coalesce(t.expenses,0)),
  'items',coalesce((select jsonb_agg(jsonb_build_object('productId',i.product_id,'qty',i.qty,'price',i.price)order by i.product_id,i.qty,i.price)
   from public.transaction_items i where i.transaction_id=t.id),'[]'::jsonb))
 from public.transactions t where t.id=invoice_id and t.kind='sale'
$$;
revoke all on function solar_private.wholesale_economic_signature(bigint)from public,anon,authenticated;
-- Derived baseline permits notes/party/payment updates without applying a new
-- policy retroactively, even when a legacy save recreates identical item rows.
insert into solar_private.wholesale_invoice_pricing(invoice_id,accepted_signature,actor_id)
select t.id,solar_private.wholesale_economic_signature(t.id),t.created_by from public.transactions t where t.kind='sale';

create function solar_private.wholesale_pricing_state()returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare actor public.profiles;control solar_private.wholesale_pricing_control;catalog jsonb;begin
 select * into actor from public.profiles where id=auth.uid()and active and user_type not in('warehouse','installer');
 if actor.id is null or not(actor.is_admin or coalesce(actor.permissions->>'sale','false')='true' or coalesce(actor.permissions->>'wholesalePricingManage','false')='true')then
  raise exception 'لا تملك صلاحية الاطلاع على أسعار بيع الجملة'using errcode='42501';end if;
 select * into control from solar_private.wholesale_pricing_control where id;
 -- Reuse the existing catalog's warehouse scope and cost visibility unchanged.
 catalog:=solar_private.inventory_catalog(null);
 return jsonb_build_object('enabled',control.enabled,'revision',control.revision,'updatedAt',control.updated_at,
  'updatedByName',(select solar_private.user_name(p.display_name,p.username,p.honorific)from public.profiles p where p.id=control.updated_by),
  'currency','IQD','canManage',actor.is_admin or coalesce(actor.permissions->>'wholesalePricingManage','false')='true',
  'canOverride',actor.is_admin or coalesce(actor.permissions->>'wholesaleFreePricing','false')='true',
  'products',(select coalesce(jsonb_agg(jsonb_build_object('id',(item->>'id')::bigint,'code',item->>'code','name',item->>'name','brand',item->>'brand',
   'category',item->>'category','qty',item->'qty','cost',item->'cost','minPrice',price.minimum_price,'enabled',coalesce(price.enabled,false),'revision',coalesce(price.revision,0),
   'updatedAt',price.updated_at,'updatedByName',(select solar_private.user_name(p.display_name,p.username,p.honorific)from public.profiles p where p.id=price.updated_by))order by item->>'name',(item->>'id')::bigint),'[]')
   from jsonb_array_elements(catalog)item left join solar_private.wholesale_product_prices price on price.product_id=(item->>'id')::bigint));
end $$;
revoke all on function solar_private.wholesale_pricing_state()from public,anon,authenticated;

create function solar_private.wholesale_pricing(action text default 'state',request_id uuid default null,payload jsonb default '{}')returns jsonb
language plpgsql security definer set search_path=''set lock_timeout='5s'as $$
#variable_conflict use_variable
declare actor public.profiles;prior solar_private.finance_requests;control solar_private.wholesale_pricing_control;old_price solar_private.wholesale_product_prices;
 entry jsonb;minimum numeric;checked boolean;target_product_id bigint;expected bigint;changed boolean:=false;result jsonb;next_enabled boolean;
begin
 select * into actor from public.profiles where id=auth.uid()and active and user_type not in('warehouse','installer');
 if actor.id is null then raise exception 'الدخول بحساب فعال مطلوب'using errcode='42501';end if;
 if action='state'then return solar_private.wholesale_pricing_state();end if;
 if action not in('save','toggle')or action is null or jsonb_typeof(payload)is distinct from'object' or request_id is null then raise exception 'طلب تسعير غير صحيح'using errcode='22023';end if;
 if not(actor.is_admin or coalesce(actor.permissions->>'wholesalePricingManage','false')='true')then raise exception 'تعديل أسعار بيع الجملة يحتاج صلاحية إدارة الأسعار'using errcode='42501';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into prior from solar_private.finance_requests f where f.request_id=wholesale_pricing.request_id;
 if found then
  if prior.actor_id=actor.id and prior.action='wholesale_pricing_'||action and prior.payload=payload then return prior.response;end if;
  raise exception 'طلب مكرر ببيانات مختلفة'using errcode='PT409';
 end if;
 select * into control from solar_private.wholesale_pricing_control where id for update;
 if action='toggle'then
  if jsonb_typeof(payload->'enabled')is distinct from'boolean' or jsonb_typeof(payload->'expectedRevision')is distinct from'number' then raise exception 'حدد حالة أسعار بيع الجملة'using errcode='22023';end if;
  if (payload->>'expectedRevision')::numeric<0 or trunc((payload->>'expectedRevision')::numeric)<>(payload->>'expectedRevision')::numeric then raise exception 'إصدار التسعير غير صحيح'using errcode='22023';end if;
  if control.revision is distinct from(payload->>'expectedRevision')::bigint then raise exception 'تغيّرت أسعار الجملة؛ حدّث الصفحة وأعد التأكيد'using errcode='PT409';end if;
  next_enabled:=(payload->>'enabled')::boolean;
  if next_enabled is distinct from control.enabled then
   update solar_private.wholesale_pricing_control set enabled=next_enabled,revision=revision+1,updated_at=now(),updated_by=actor.id where id;
   insert into solar_private.wholesale_pricing_audit(request_id,actor_id,action,before_value,after_value)
   values(request_id,actor.id,'toggle',to_jsonb(control),jsonb_build_object('enabled',next_enabled,'revision',control.revision+1));
   with notices as(
    insert into public.solar_notifications(user_id,event,title,body)
    select p.id,case when next_enabled then'operation_paused'else'operation_resumed'end,
     case when next_enabled then'تفعيل الحد الأدنى لأسعار بيع الجملة'else'إيقاف الحد الأدنى لأسعار بيع الجملة'end,
     'المستخدم: '||solar_private.user_name(actor.display_name,actor.username,actor.honorific)||'. '||case when next_enabled then'تم تفعيل الحد الأدنى للمواد المحددة في بيع الجملة. الأسعار الأعلى مسموحة، وتبقى صلاحية البيع الحر مستقلة.'else'تم إيقاف تطبيق الحد الأدنى لبيع الجملة مع الاحتفاظ بالأسعار والمواد المحددة.'end
    from public.profiles p where p.active and p.user_type not in('warehouse','installer')and(p.is_admin or coalesce(p.permissions->>'sale','false')='true' or coalesce(p.permissions->>'wholesalePricingManage','false')='true')returning id,user_id
   )insert into solar_private.push_deliveries(notification_id,endpoint)select n.id,s.endpoint from notices n join public.solar_push_subscriptions s on s.user_id=n.user_id;
   perform solar_private.wake_push();
  end if;
 else
  if jsonb_typeof(payload->'items')is distinct from'array'or jsonb_array_length(payload->'items')not between 1 and 100 then raise exception 'حدد من مادة إلى 100 مادة للحفظ'using errcode='22023';end if;
  if exists(select 1 from jsonb_array_elements(payload->'items')x group by x->'productId' having count(*)>1)then raise exception 'المادة مكررة في طلب التسعير'using errcode='22023';end if;
  for entry in select value from jsonb_array_elements(payload->'items')order by value->>'productId' loop
   if jsonb_typeof(entry)is distinct from'object' or jsonb_typeof(entry->'productId')is distinct from'number' or jsonb_typeof(entry->'enabled')is distinct from'boolean' or jsonb_typeof(entry->'expectedRevision')is distinct from'number' or not(entry?'minPrice')or jsonb_typeof(entry->'minPrice')not in('number','null')then raise exception 'بيانات سعر المادة غير صحيحة'using errcode='22023';end if;
   if trunc((entry->>'productId')::numeric)<>(entry->>'productId')::numeric or(entry->>'expectedRevision')::numeric<0 or trunc((entry->>'expectedRevision')::numeric)<>(entry->>'expectedRevision')::numeric then raise exception 'رقم المادة أو إصدار السعر غير صحيح'using errcode='22023';end if;
   target_product_id:=(entry->>'productId')::bigint;expected:=(entry->>'expectedRevision')::bigint;minimum:=(entry->>'minPrice')::numeric;checked:=(entry->>'enabled')::boolean;
   if not exists(select 1 from public.products p where p.id=target_product_id)then raise exception 'إحدى المواد غير موجودة؛ حدّث القائمة'using errcode='PT409';end if;
   if minimum is not null and(minimum::text in('NaN','Infinity','-Infinity')or minimum<0 or minimum>1e12 or round(minimum,2)<>minimum)then raise exception 'أدخل حدًا أدنى صحيحًا بمرتبتين عشريتين كحد أقصى'using errcode='PT422';end if;
   if checked and(minimum is null or minimum<=0)then raise exception 'حدد سعرًا موجبًا قبل تفعيل الحد الأدنى للمادة'using errcode='PT422';end if;
   select * into old_price from solar_private.wholesale_product_prices p where p.product_id=target_product_id for update;
   if coalesce(old_price.revision,0) is distinct from expected then raise exception 'تغيّر سعر إحدى المواد؛ حدّث القائمة وأعد المحاولة'using errcode='PT409';end if;
   if(old_price.minimum_price,coalesce(old_price.enabled,false))is distinct from(minimum,checked)then
    insert into solar_private.wholesale_product_prices(product_id,minimum_price,enabled,revision,updated_at,updated_by)values(target_product_id,minimum,checked,coalesce(old_price.revision,0)+1,now(),actor.id)
    on conflict on constraint wholesale_product_prices_pkey do update set minimum_price=excluded.minimum_price,enabled=excluded.enabled,revision=excluded.revision,updated_at=excluded.updated_at,updated_by=excluded.updated_by;
    insert into solar_private.wholesale_pricing_audit(request_id,actor_id,action,product_id,before_value,after_value)
    values(request_id,actor.id,'product',target_product_id,case when old_price.product_id is null then null else to_jsonb(old_price)end,jsonb_build_object('minPrice',minimum,'enabled',checked,'revision',coalesce(old_price.revision,0)+1));
    changed:=true;
   end if;
  end loop;
  if changed then update solar_private.wholesale_pricing_control set revision=revision+1,updated_at=now(),updated_by=actor.id where id;end if;
 end if;
 result:=solar_private.wholesale_pricing_state();
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response)values(request_id,actor.id,'wholesale_pricing_'||action,payload,result);
 return result;
end $$;
create function public.solar_wholesale_pricing(action text default 'state',request_id uuid default null,payload jsonb default '{}')returns jsonb
language sql security invoker set search_path=''as $$select solar_private.wholesale_pricing(action,request_id,payload)$$;
revoke all on function solar_private.wholesale_pricing(text,uuid,jsonb),public.solar_wholesale_pricing(text,uuid,jsonb)from public,anon;
grant execute on function solar_private.wholesale_pricing(text,uuid,jsonb),public.solar_wholesale_pricing(text,uuid,jsonb)to authenticated;

create function solar_private.assert_wholesale_pricing(invoice_id bigint,expected_revision bigint default null)returns void
language plpgsql security definer set search_path=''as $$
declare invoice public.transactions;actor public.profiles;control solar_private.wholesale_pricing_control;accepted solar_private.wholesale_invoice_pricing;
 signature jsonb;gross numeric;net numeric;factor numeric;line record;enforced boolean:=false;override_allowed boolean:=false;floors jsonb:='[]';
begin
 select * into invoice from public.transactions t where t.id=invoice_id and t.kind='sale';
 if invoice.id is null then return;end if;
 perform pg_advisory_xact_lock(7311,1);
 signature:=solar_private.wholesale_economic_signature(invoice_id);
 select * into accepted from solar_private.wholesale_invoice_pricing p where p.invoice_id=assert_wholesale_pricing.invoice_id for update;
 if accepted.invoice_id is not null and accepted.accepted_signature=signature then return;end if;
 if invoice.source_currency is distinct from'IQD'or invoice.exchange_rate is distinct from 1 then raise exception 'بيع الجملة محفوظ بالدينار العراقي؛ بيانات العملة أو الصرف غير صحيحة'using errcode='PT422';end if;
 select * into control from solar_private.wholesale_pricing_control where id;
 select * into actor from public.profiles where id=auth.uid()and active;
 override_allowed:=actor.id is not null and actor.user_type not in('warehouse','installer')and(actor.is_admin or coalesce(actor.permissions->>'wholesaleFreePricing','false')='true');
 if control.enabled and expected_revision is not null and control.revision is distinct from expected_revision then raise exception 'تغيّرت أسعار بيع الجملة؛ حدّث الأسعار وأعد الحفظ'using errcode='PT409';end if;
 if control.enabled and not override_allowed then
  if actor.id is null then raise exception 'تعذر تأكيد صلاحية التسعير؛ أعد تسجيل الدخول'using errcode='42501';end if;
  if exists(select 1 from public.transaction_items i where i.transaction_id=invoice_id and(i.product_id is null or not exists(select 1 from public.products p where p.id=i.product_id)))then raise exception 'اختر مواد مسجلة حتى يمكن التحقق من أسعار بيع الجملة'using errcode='PT422';end if;
  if exists(select 1 from public.transaction_items i where i.transaction_id=invoice_id and(i.qty<=0 or i.price<0 or i.qty::text in('NaN','Infinity','-Infinity')or i.price::text in('NaN','Infinity','-Infinity')))then raise exception 'كمية أو سعر غير صحيح في مواد بيع الجملة'using errcode='PT422';end if;
  select round(coalesce(sum(i.qty*i.price),0),2)into gross from public.transaction_items i where i.transaction_id=invoice_id;
  net:=least(coalesce(invoice.subtotal,invoice.total-coalesce(invoice.expenses,0)),invoice.total-coalesce(invoice.expenses,0));
  if net is null or net::text in('NaN','Infinity','-Infinity')or gross::text in('NaN','Infinity','-Infinity')then raise exception 'مبلغ بيع الجملة غير صحيح'using errcode='PT422';end if;
  factor:=case when gross>0 then least(1,net/gross)when net<0 then 0 else 1 end;
  for line in select i.product_id,i.product_name,i.price,i.qty,p.minimum_price,p.revision from public.transaction_items i join solar_private.wholesale_product_prices p on p.product_id=i.product_id and p.enabled where i.transaction_id=invoice_id loop
   enforced:=true;
   if line.price is null or line.price::text in('NaN','Infinity','-Infinity')or line.qty::text in('NaN','Infinity','-Infinity')or line.qty<=0 or line.price*factor<line.minimum_price then
    if actor.user_type in('warehouse','installer')then raise exception 'تحتاج مواد وصل الجملة إلى مراجعة التسعير من المسؤول'using errcode='PT422';end if;
    raise exception 'سعر مادة % بعد الخصم أقل من الحد الأدنى المسموح: % د.ع',line.product_name,line.minimum_price using errcode='PT422';
   end if;
  end loop;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('productId',p.product_id,'minPrice',p.minimum_price,'enabled',p.enabled,'revision',p.revision)order by p.product_id),'[]')into floors
 from solar_private.wholesale_product_prices p where p.product_id in(select i.product_id from public.transaction_items i where i.transaction_id=invoice_id);
 insert into solar_private.wholesale_invoice_pricing(invoice_id,accepted_signature,policy_revision,prices_snapshot,enforced,override_used,actor_id,accepted_at)
 values(invoice_id,signature,control.revision,floors,enforced,control.enabled and override_allowed,actor.id,now())
 on conflict on constraint wholesale_invoice_pricing_pkey do update set accepted_signature=excluded.accepted_signature,policy_revision=excluded.policy_revision,prices_snapshot=excluded.prices_snapshot,enforced=excluded.enforced,override_used=excluded.override_used,actor_id=excluded.actor_id,accepted_at=excluded.accepted_at;
end $$;
revoke all on function solar_private.assert_wholesale_pricing(bigint,bigint)from public,anon,authenticated;

create function solar_private.guard_wholesale_pricing()returns trigger
language plpgsql security definer set search_path=''as $$
begin
 if tg_table_name='transactions'then
  perform solar_private.assert_wholesale_pricing(new.id);
 elsif tg_op='DELETE'then perform solar_private.assert_wholesale_pricing(old.transaction_id);
 else
  perform solar_private.assert_wholesale_pricing(new.transaction_id);
  if tg_op='UPDATE'and old.transaction_id<>new.transaction_id then perform solar_private.assert_wholesale_pricing(old.transaction_id);end if;
 end if;
 return null;
end $$;
revoke all on function solar_private.guard_wholesale_pricing()from public,anon,authenticated;
create constraint trigger solar_wholesale_pricing_check after insert or update on public.transactions deferrable initially deferred for each row when(new.kind='sale')execute function solar_private.guard_wholesale_pricing();
create constraint trigger solar_wholesale_item_pricing_check after insert or update or delete on public.transaction_items deferrable initially deferred for each row execute function solar_private.guard_wholesale_pricing();

-- Canonical invoice saves validate before returning a receipt. Deferred guards
-- also cover legacy/direct table paths and protected warehouse amendments.
do $$declare definition text;anchor text;begin
 definition:=pg_get_functiondef('solar_private.invoice_save(uuid,jsonb)'::regprocedure);
 anchor:=' return invoice_result;';
 if strpos(definition,anchor)=0 then raise exception 'Review invoice_save wholesale validation anchor';end if;
 execute replace(definition,anchor,$insert$
 if not cached and payload->>'kind'='sale'then
  perform solar_private.assert_wholesale_pricing((invoice_result->>'id')::bigint,nullif(payload->>'wholesalePricingRevision','')::bigint);
 end if;
$insert$||anchor);
end $$;
notify pgrst,'reload schema';
