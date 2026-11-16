-- V4.1.1: material type is category, not a product code mislabeled as model.
-- New payloads snapshot category; legacy payloads may retain model privately.
-- Only nonfinancial category metadata is added to exactly matched old notices.
do $$begin
 if md5(pg_get_functiondef('solar_private.notify_wholesale_prices(bigint[])'::regprocedure))is distinct from'd34bda509ba4511d0fe251714a555ab8'
 or md5(pg_get_functiondef('solar_private.publish_purchase_notice(bigint,boolean)'::regprocedure))is distinct from'0a83567ac1ffcd1ac44d8a56f55d48e4'
 then raise exception 'Unexpected material notification category baseline';end if;
end$$;

-- Keep legacy model-only, additive category+model, and new category-only items
-- readable while continuing to reject financial fields in purchase details.
alter table public.solar_notifications drop constraint solar_notification_details_shape;
alter table public.solar_notifications add constraint solar_notification_details_shape check(
 details is null or(jsonb_typeof(details)='object' and details->>'type'=event and jsonb_typeof(details->'items')='array' and
 ((event='purchase_received'and warehouse_id is not null and details-array['type','items']='{}'::jsonb and
 not jsonb_path_exists(details,'$.items[*].keyvalue() ? (@.key != "name" && @.key != "model" && @.key != "category" && @.key != "brand" && @.key != "qty")'))
 or(event='wholesale_prices_updated'and details->>'currency'='IQD'and details-array['type','currency','items']='{}'::jsonb and
 not jsonb_path_exists(details,'$.items[*].keyvalue() ? (@.key != "name" && @.key != "model" && @.key != "category" && @.key != "brand" && @.key != "minPrice" && @.key != "enabled")')))));

create or replace function solar_private.notify_wholesale_prices(changed_ids bigint[])returns integer
language plpgsql security definer set search_path=''as $$
declare entries jsonb;notice_details jsonb;recipient_count integer;begin
 select jsonb_agg(jsonb_build_object('name',p.name,'category',coalesce(p.category,''),'brand',coalesce(b.name,''),'minPrice',s.minimum_price,'enabled',s.enabled)order by p.name,p.id)
 into entries from solar_private.wholesale_product_prices s join public.products p on p.id=s.product_id left join public.brands b on b.id=p.brand_id where p.id=any(changed_ids);
 if entries is null then return 0;end if;
 notice_details:=jsonb_build_object('type','wholesale_prices_updated','currency','IQD','items',entries);
 with notices as(
  insert into public.solar_notifications(user_id,event,title,body,details)
  select p.id,'wholesale_prices_updated','تحديث أسعار بيع الجملة','تم تحديث أسعار بيع الجملة لـ '||jsonb_array_length(entries)::text||' مادة. افتح الإشعار لمراجعة الأسعار الجديدة.',notice_details
  from public.profiles p where solar_private.material_notice_recipient_allowed(p.id,'wholesale_prices_updated',null)returning id,user_id
 ), deliveries as(
  insert into solar_private.push_deliveries(notification_id,endpoint)select n.id,s.endpoint from notices n join public.solar_push_subscriptions s on s.user_id=n.user_id
 )select count(*)into recipient_count from notices;
 if recipient_count>0 then perform solar_private.wake_push();end if;
 return recipient_count;
end$$;
revoke all on function solar_private.notify_wholesale_prices(bigint[])from public,anon,authenticated;

create or replace function solar_private.publish_purchase_notice(invoice_id bigint,finalize_canonical boolean default false)returns void
language plpgsql security definer set search_path=''as $$
declare source solar_private.purchase_notice_sources;entries jsonb;notice_details jsonb;recipient uuid;nid uuid;heading text:='دخول مواد جديدة';summary text;begin
 select * into source from solar_private.purchase_notice_sources s where s.invoice_id=publish_purchase_notice.invoice_id for update;
 if source.invoice_id is null or(source.canonical and(not finalize_canonical or source.notified_at is not null))then return;end if;
 if not exists(select 1 from public.transactions t where t.id=invoice_id and t.kind='purchase')then return;end if;
 select jsonb_agg(jsonb_build_object('name',coalesce(i.product_name,p.name,'مادة'),'category',coalesce(nullif(i.category,''),p.category,''),'brand',coalesce(nullif(i.brand_name,''),b.name,''),'qty',i.qty)order by i.id)
 into entries from public.transaction_items i left join public.products p on p.id=i.product_id left join public.brands b on b.id=p.brand_id where i.transaction_id=invoice_id and i.qty>0;
 if entries is null then return;end if;
 notice_details:=jsonb_build_object('type','purchase_received','items',entries);
 if notice_details is not distinct from source.details then return;end if;
 summary:='تم استلام '||jsonb_array_length(entries)::text||' مادة. افتح الإشعار لمراجعة الأسماء والأنواع والبراندات والكميات.';
 if source.notified_at is null then
  for recipient in select p.id from public.profiles p where solar_private.material_notice_recipient_allowed(p.id,'purchase_received',source.warehouse_id)loop
   insert into public.solar_notifications(user_id,event,title,body,details,warehouse_id)values(recipient,'purchase_received',heading,summary,notice_details,source.warehouse_id)returning id into nid;
   insert into solar_private.purchase_notice_recipients(invoice_id,user_id,notification_id)values(source.invoice_id,recipient,nid);
   insert into solar_private.push_deliveries(notification_id,endpoint)select nid,s.endpoint from public.solar_push_subscriptions s where s.user_id=recipient;
  end loop;
  perform solar_private.wake_push();
 else
  update public.solar_notifications n set details=notice_details,body=summary
  from solar_private.purchase_notice_recipients r where r.invoice_id=source.invoice_id and r.notification_id=n.id;
 end if;
 update solar_private.purchase_notice_sources s set details=notice_details,notified_at=coalesce(s.notified_at,now())where s.invoice_id=source.invoice_id;
end$$;
revoke all on function solar_private.publish_purchase_notice(bigint,boolean)from public,anon,authenticated;
-- Match the saved code, name and brand, and independently require exactly one
-- result even on a legacy database without code uniqueness. Reused/renamed or
-- ambiguous codes never attach a different material's type. No fuzzy matching.
with candidates as(
 select n.id,jsonb_set(n.details,'{items}',jsonb_agg(
  case when not(j.item?'category')and nullif(btrim(matched.category),'')is not null
   then j.item||jsonb_build_object('category',matched.category)else j.item end order by j.ordinality))as details
 from public.solar_notifications n
 cross join lateral jsonb_array_elements(n.details->'items')with ordinality as j(item,ordinality)
 left join lateral(
  select min(p.category)as category from public.products p left join public.brands b on b.id=p.brand_id
  where p.code=j.item->>'model'and nullif(btrim(j.item->>'model'),'')is not null
   and p.name=j.item->>'name'and coalesce(b.name,'')=coalesce(j.item->>'brand','')
  having count(*)=1
 )matched on true
 where n.event in('purchase_received','wholesale_prices_updated')and jsonb_typeof(n.details->'items')='array'
 group by n.id,n.details
)
update public.solar_notifications n set details=c.details from candidates c
 where n.id=c.id and n.event in('purchase_received','wholesale_prices_updated')and n.details is distinct from c.details;

-- Existing recipient scopes, grants, delivery queues, read state and timestamps
-- are unchanged. Do not resend a notice or modify any financial document.
notify pgrst,'reload schema';
