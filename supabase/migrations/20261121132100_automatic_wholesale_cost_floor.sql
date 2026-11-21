-- A checked price is an explicit override. An unchecked or absent price follows
-- the current IQD valuation, including the acquisition currency composition.
create table solar_private.wholesale_floor_token_key (
 singleton boolean primary key default true check(singleton),
 secret uuid not null default gen_random_uuid()
);
alter table solar_private.wholesale_floor_token_key enable row level security;
revoke all on solar_private.wholesale_floor_token_key from public,anon,authenticated;
insert into solar_private.wholesale_floor_token_key(singleton) values(true);

-- Only internal sale/status functions may read this unredacted snapshot. The
-- per-product token lets a seller detect a changed private floor without
-- disclosing its amount or providing a guessable digest of the amount.
create function solar_private.wholesale_floor_snapshot(product_ids bigint[]) returns jsonb
language sql stable security definer set search_path='' as $$
 with quotes as materialized (
  select p.id,r.minimum_price,coalesce(r.enabled,false) as enabled,coalesce(r.revision,0) as revision,
   case when r.enabled and r.minimum_price>0 then 'configured' else 'cost' end as source,
   case when r.enabled and r.minimum_price>0 then r.minimum_price
        else solar_private.current_unit_cost(p.id,p.cost_basis,p.cost) end as floor
  from public.products p left join solar_private.wholesale_product_prices r on r.product_id=p.id
  where p.id=any(product_ids)
 )
 select coalesce(jsonb_object_agg(q.id,jsonb_build_object(
  'productId',q.id,'minPrice',q.minimum_price,'enabled',q.enabled,'revision',q.revision,
  'floorSource',q.source,'effectiveMinPrice',q.floor,'floorToken',
  encode(sha256(convert_to(concat_ws('|',q.id,q.source,trim_scale(q.floor),k.secret),'UTF8')),'hex')
 )),'{}'::jsonb)
 from quotes q cross join solar_private.wholesale_floor_token_key k
$$;
revoke all on function solar_private.wholesale_floor_snapshot(bigint[]) from public,anon,authenticated;

do $migration$
declare definition text:=pg_get_functiondef('solar_private.wholesale_pricing_state_v410_notices()'::regprocedure);
begin
 if md5(definition)<>'05243a5227619f9471f32ccb3ddc55b4' then raise exception 'Review wholesale pricing state before adding live floors';end if;
 definition:=replace(definition,'catalog jsonb;begin','catalog jsonb; floors jsonb; private_cost boolean;begin');
 definition:=replace(definition,'catalog:=solar_private.inventory_catalog(null);',$new$
 catalog:=solar_private.inventory_catalog(null);
 private_cost:=solar_private.viewer_uses_personal_prices();
 floors:=solar_private.wholesale_floor_snapshot(array(select (v->>'id')::bigint from jsonb_array_elements(catalog)v));$new$);
 definition:=replace(definition,$old$'updatedAt',price.updated_at,$old$,$new$
   'floorSource',floors->(item->>'id')->'floorSource',
   'effectiveMinPrice',case when private_cost and floors->(item->>'id')->>'floorSource'='cost' then null else floors->(item->>'id')->'effectiveMinPrice' end,
   'floorToken',floors->(item->>'id')->'floorToken','updatedAt',price.updated_at,$new$);
 execute definition;
end $migration$;

-- The ordinary invoice writer supplies the pre-posting valuation. Warehouse
-- and deferred checks can resolve it themselves. An accepted unchanged
-- economic signature always retains its original approval and floor audit.
create function solar_private.check_wholesale_floor(invoice_id bigint,expected_revision bigint,
 prepared_floors jsonb,expected_tokens jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare
 invoice public.transactions; actor public.profiles; control solar_private.wholesale_pricing_control;
 accepted solar_private.wholesale_invoice_pricing; scope jsonb; signature jsonb; floors jsonb; audit_floors jsonb;
 gross numeric; net numeric; factor numeric; line record; enforced boolean:=false; private_cost boolean;
begin
 select * into invoice from public.transactions t where t.id=invoice_id and t.kind='sale';
 if invoice.id is null then return;end if;
 perform pg_advisory_xact_lock(7311,1);
 signature:=solar_private.wholesale_economic_signature(invoice_id);
 select * into accepted from solar_private.wholesale_invoice_pricing p where p.invoice_id=check_wholesale_floor.invoice_id for update;
 if accepted.invoice_id is not null and accepted.accepted_signature=signature then return;end if;
 if invoice.source_currency is distinct from 'IQD' or invoice.exchange_rate is distinct from 1 then
  raise exception 'بيع الجملة محفوظ بالدينار العراقي؛ بيانات العملة أو الصرف غير صحيحة' using errcode='PT422';end if;
 select * into control from solar_private.wholesale_pricing_control where id;
 select * into actor from public.profiles where id=auth.uid() and active;
 scope:=solar_private.wholesale_scope_effective(invoice.created_by,auth.uid());
 if expected_revision is not null and control.revision is distinct from expected_revision then
  raise exception 'تغيّرت أسعار بيع الجملة؛ حدّث الأسعار وأعد الحفظ' using errcode='PT409';end if;
 floors:=coalesce(prepared_floors,solar_private.wholesale_floor_snapshot(array(
  select distinct i.product_id from public.transaction_items i where i.transaction_id=invoice_id)));
 if (scope->>'effectiveEnforced')::boolean then
  if actor.id is null then raise exception 'تعذر تأكيد صلاحية التسعير؛ أعد تسجيل الدخول' using errcode='42501';end if;
  private_cost:=solar_private.viewer_uses_personal_prices();
  if exists(select 1 from public.transaction_items i where i.transaction_id=invoice_id
    and (i.product_id is null or not floors ? i.product_id::text)) then
   raise exception 'اختر مواد مسجلة حتى يمكن التحقق من أسعار بيع الجملة' using errcode='PT422';end if;
  if expected_tokens is not null and (jsonb_typeof(expected_tokens) is distinct from 'object' or exists(
    select 1 from public.transaction_items i where i.transaction_id=invoice_id
    and expected_tokens->>i.product_id::text is distinct from floors->i.product_id::text->>'floorToken')) then
   raise exception 'تغيّر الحد الأدنى لمواد الوصل؛ حدّث الأسعار وأعد الحفظ' using errcode='PT409';end if;
  select round(coalesce(sum(i.qty*i.price),0),2) into gross from public.transaction_items i where i.transaction_id=invoice_id;
  net:=least(coalesce(invoice.subtotal,invoice.total-case when coalesce(invoice.expenses_on_customer,true) then coalesce(invoice.expenses,0) else 0 end),
             invoice.total-case when coalesce(invoice.expenses_on_customer,true) then coalesce(invoice.expenses,0) else 0 end);
  if net is null or net::text in('NaN','Infinity','-Infinity') or gross::text in('NaN','Infinity','-Infinity') then
   raise exception 'مبلغ بيع الجملة غير صحيح' using errcode='PT422';end if;
  factor:=case when gross>0 then least(1,net/gross) when net<0 then 0 else 1 end;
  for line in select i.product_name,i.price,i.qty,floors->i.product_id::text->>'floorSource' as source,
    (floors->i.product_id::text->>'effectiveMinPrice')::numeric as minimum_price
    from public.transaction_items i where i.transaction_id=invoice_id loop
   enforced:=true;
   if line.qty is null or line.qty<=0 or line.price is null or line.price<0 or line.price::text in('NaN','Infinity','-Infinity')
      or line.qty::text in('NaN','Infinity','-Infinity') then
    raise exception 'كمية أو سعر غير صحيح في مواد بيع الجملة' using errcode='PT422';end if;
   if line.minimum_price is null or line.minimum_price<0 or line.minimum_price::text in('NaN','Infinity','-Infinity') then
    raise exception 'تعذر تحديد سعر هذه المادة؛ راجع مسؤول التسعير' using errcode='PT422';end if;
   if line.price*factor<line.minimum_price then
    if actor.user_type in('warehouse','installer') or (private_cost and line.source='cost') then
     raise exception 'تحتاج مواد وصل الجملة إلى مراجعة التسعير من المسؤول' using errcode='PT422';end if;
    raise exception 'سعر مادة % بعد الخصم أقل من الحد الأدنى المسموح: % د.ع',line.product_name,line.minimum_price using errcode='PT422';
   end if;
  end loop;
 end if;
 select coalesce(jsonb_agg(v-'floorToken' order by (v->>'productId')::bigint),'[]') into audit_floors from jsonb_each(floors) q(k,v);
 insert into solar_private.wholesale_invoice_pricing(invoice_id,accepted_signature,policy_revision,prices_snapshot,enforced,override_used,actor_id,accepted_at)
 values(invoice_id,signature,control.revision,audit_floors,enforced,control.enabled and (scope->>'canOverride')::boolean,actor.id,now())
 on conflict on constraint wholesale_invoice_pricing_pkey do update set accepted_signature=excluded.accepted_signature,
 policy_revision=excluded.policy_revision,prices_snapshot=excluded.prices_snapshot,enforced=excluded.enforced,
 override_used=excluded.override_used,actor_id=excluded.actor_id,accepted_at=excluded.accepted_at;
end$$;
revoke all on function solar_private.check_wholesale_floor(bigint,bigint,jsonb,jsonb) from public,anon,authenticated;

do $migration$
declare definition text:=pg_get_functiondef('solar_private.invoice_save(uuid,jsonb)'::regprocedure);
begin
 if md5(definition)<>'65f07afde7e7608b52722a5eba5523c6' or
    md5(pg_get_functiondef('solar_private.assert_wholesale_pricing(bigint,bigint)'::regprocedure))<>'375cc7f1bdcc1acaac40c780bfc40c03' then
  raise exception 'Review invoice writer and wholesale guards before adding pre-posting floor quotes';end if;
 definition:=replace(definition,'declare invoice_result jsonb;','declare invoice_result jsonb; wholesale_floors jsonb;');
 definition:=replace(definition,'before_stock:=solar_private.valuation_stock_snapshot(ids);',$new$
  before_stock:=solar_private.valuation_stock_snapshot(ids);
  if payload->>'kind'='sale' then
   wholesale_floors:=solar_private.wholesale_floor_snapshot(array(select distinct (v->>'id')::bigint from jsonb_array_elements(payload->'items')v));
  end if;$new$);
 definition:=replace(definition,$old$solar_private.assert_wholesale_pricing((invoice_result->>'id')::bigint,nullif(payload->>'wholesalePricingRevision','')::bigint)$old$,
  $new$solar_private.check_wholesale_floor((invoice_result->>'id')::bigint,nullif(payload->>'wholesalePricingRevision','')::bigint,wholesale_floors,payload->'wholesaleFloorTokens')$new$);
 execute definition;
end $migration$;

create or replace function solar_private.assert_wholesale_pricing(invoice_id bigint,expected_revision bigint default null)
returns void language sql security definer set search_path='' as $$
 select solar_private.check_wholesale_floor(invoice_id,expected_revision,null,null)
$$;
