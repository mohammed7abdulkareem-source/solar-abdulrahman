-- V4.1.3: purchase-arrival notices identify their receiving warehouse.
-- No receipt, stock, price, account, recipient, read-state or delivery changes.
do $$begin
 if md5(pg_get_functiondef('solar_private.publish_purchase_notice(bigint,boolean)'::regprocedure))is distinct from'ba9871d4de27182af7856e29ff6fc67e'
 or(select md5(pg_get_constraintdef(oid))from pg_constraint where conrelid='public.solar_notifications'::regclass and conname='solar_notification_details_shape')is distinct from'73227c2cd5ef17d1fca2b92db3ab6009'
 then raise exception 'Unexpected purchase warehouse notice baseline';end if;
end$$;

-- The optional field keeps legacy notices readable; every new emitted notice
-- supplies a nonempty name bounded by the existing warehouse-name limit.
alter table public.solar_notifications drop constraint solar_notification_details_shape;
alter table public.solar_notifications add constraint solar_notification_details_shape check(
 details is null or(jsonb_typeof(details)='object' and details->>'type'=event and jsonb_typeof(details->'items')='array' and
 ((event='purchase_received'and warehouse_id is not null and details-array['type','items','warehouseName']='{}'::jsonb and
 (not(details?'warehouseName')or(jsonb_typeof(details->'warehouseName')='string'and length(btrim(details->>'warehouseName'))between 1 and 100))and
 not jsonb_path_exists(details,'$.items[*].keyvalue() ? (@.key != "name" && @.key != "model" && @.key != "category" && @.key != "brand" && @.key != "qty")'))
 or(event='wholesale_prices_updated'and details->>'currency'='IQD'and details-array['type','currency','items']='{}'::jsonb and
 not jsonb_path_exists(details,'$.items[*].keyvalue() ? (@.key != "name" && @.key != "model" && @.key != "category" && @.key != "brand" && @.key != "minPrice" && @.key != "enabled")')))));

-- Retain the immutable receipt warehouse snapshot for a linked source. Only
-- private notice metadata changes, so a later legacy line append reuses the
-- same warehouse label even if the warehouse itself has since been renamed.
with names as(
 select s.invoice_id,coalesce(case when length(btrim(t.warehouse_name))between 1 and 100 then btrim(t.warehouse_name)end,btrim(w.name))warehouse_name
 from solar_private.purchase_notice_sources s join solar_private.warehouses w on w.id=s.warehouse_id
 left join public.transactions t on t.id=s.invoice_id and t.kind='purchase'and t.warehouse_id=s.warehouse_id
 where jsonb_typeof(s.details)='object'and not(s.details?'warehouseName')
)
update solar_private.purchase_notice_sources s set details=s.details||jsonb_build_object('warehouseName',n.warehouse_name)
 from names n where s.invoice_id=n.invoice_id;

-- Existing notifications are enriched only by their trusted warehouse_id.
-- Linked receipts retain their saved name; notices whose receipt was deleted
-- or is no longer linked fall back to that exact warehouse's current name.
-- Other details, title/body, timestamps/read_at and queues remain byte-identical.
with names as(
 select n.id,coalesce(nullif(btrim(s.details->>'warehouseName'),''),btrim(w.name))warehouse_name
 from public.solar_notifications n join solar_private.warehouses w on w.id=n.warehouse_id
 left join solar_private.purchase_notice_recipients r on r.notification_id=n.id
 left join solar_private.purchase_notice_sources s on s.invoice_id=r.invoice_id and s.warehouse_id=n.warehouse_id
 where n.event='purchase_received'and jsonb_typeof(n.details)='object'and not(n.details?'warehouseName')
)
update public.solar_notifications n set details=n.details||jsonb_build_object('warehouseName',s.warehouse_name)
 from names s where n.id=s.id;

create or replace function solar_private.publish_purchase_notice(invoice_id bigint,finalize_canonical boolean default false)returns void
language plpgsql security definer set search_path=''as $$
declare source solar_private.purchase_notice_sources;entries jsonb;notice_details jsonb;recipient uuid;nid uuid;
 heading text:='دخول مواد جديدة';summary text;warehouse_label text;begin
 select * into source from solar_private.purchase_notice_sources s where s.invoice_id=publish_purchase_notice.invoice_id for update;
 if source.invoice_id is null or(source.canonical and(not finalize_canonical or source.notified_at is not null))then return;end if;
 if not exists(select 1 from public.transactions t where t.id=invoice_id and t.kind='purchase')then return;end if;
 select coalesce(
  case when jsonb_typeof(source.details->'warehouseName')='string'and length(btrim(source.details->>'warehouseName'))between 1 and 100 then btrim(source.details->>'warehouseName')end,
  case when length(btrim(t.warehouse_name))between 1 and 100 then btrim(t.warehouse_name)end,btrim(w.name))
 into warehouse_label from solar_private.warehouses w
 left join public.transactions t on t.id=invoice_id and t.kind='purchase'and t.warehouse_id=source.warehouse_id
 where w.id=source.warehouse_id;
 select jsonb_agg(jsonb_build_object('name',coalesce(i.product_name,p.name,'مادة'),'category',coalesce(nullif(i.category,''),p.category,''),'brand',coalesce(nullif(i.brand_name,''),b.name,''),'qty',i.qty)order by i.id)
 into entries from public.transaction_items i left join public.products p on p.id=i.product_id left join public.brands b on b.id=p.brand_id where i.transaction_id=invoice_id and i.qty>0;
 if entries is null then return;end if;
 notice_details:=jsonb_build_object('type','purchase_received','items',entries,'warehouseName',warehouse_label);
 if notice_details is not distinct from source.details then return;end if;
 summary:='تم استلام '||jsonb_array_length(entries)::text||' مادة إلى المخزن: '||warehouse_label||'. افتح الإشعار لمراجعة الأسماء والأنواع والبراندات والكميات.';
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
notify pgrst,'reload schema';
