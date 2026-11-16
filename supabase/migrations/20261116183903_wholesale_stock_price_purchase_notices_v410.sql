-- V4.1: structured, scoped operational notices; no financial repricing/backfill.
do $$begin
 if md5(pg_get_functiondef('solar_private.invoice_save(uuid,jsonb)'::regprocedure))<>'3c185bb37a1320b2afb0c6bd27af1525'
 or md5(pg_get_functiondef('solar_private.wholesale_pricing(text,uuid,jsonb)'::regprocedure))<>'702d1a024f931027697c07cdb96a8e1e'
 or md5(pg_get_functiondef('public.solar_push_claim()'::regprocedure))<>'272de651f01f774953a327c3dd949971'
 then raise exception 'Unexpected V4 notification integration baseline';end if;
end$$;

alter table public.solar_notifications add column details jsonb,add column warehouse_id bigint references solar_private.warehouses(id);
-- Extend the current event check without replacing/removing existing events.
do $$declare definition text;begin
 select pg_get_constraintdef(oid)into definition from pg_constraint where conrelid='public.solar_notifications'::regclass and conname='solar_notifications_event_check';
 if definition is null or left(definition,7)<>'CHECK ('then raise exception 'Unexpected notification event check';end if;
 alter table public.solar_notifications drop constraint solar_notifications_event_check;
 execute 'alter table public.solar_notifications add constraint solar_notifications_event_check check ('||substr(definition,8,length(definition)-8)||' or event in(''purchase_received'',''wholesale_prices_updated''))';
end$$;
alter table public.solar_notifications add constraint solar_notification_details_shape check(
 details is null or(jsonb_typeof(details)='object' and details->>'type'=event and jsonb_typeof(details->'items')='array' and
 ((event='purchase_received'and warehouse_id is not null and details-array['type','items']='{}'::jsonb and
 not jsonb_path_exists(details,'$.items[*].keyvalue() ? (@.key != "name" && @.key != "model" && @.key != "brand" && @.key != "qty")'))
 or(event='wholesale_prices_updated'and details->>'currency'='IQD'and details-array['type','currency','items']='{}'::jsonb and
 not jsonb_path_exists(details,'$.items[*].keyvalue() ? (@.key != "name" && @.key != "model" && @.key != "brand" && @.key != "minPrice" && @.key != "enabled")')))));

-- Re-evaluate current roles/warehouse access for inbox reads AND push delivery.
create function solar_private.material_notice_recipient_allowed(recipient uuid,notice_event text,location bigint)returns boolean
language sql stable security definer set search_path=''as $$
 select exists(select 1 from public.profiles p where p.id=recipient and p.active and p.user_type<>'installer'and
 ((notice_event='wholesale_prices_updated'and p.user_type<>'warehouse'and(p.is_admin or p.permissions->>'sale'='true'or p.permissions->>'wholesalePricingManage'='true'))
 or(notice_event='purchase_received'and solar_private.warehouse_access_allowed(p.id,location)and
 (p.is_admin or p.user_type='warehouse'or p.permissions->>'stock'='true'or p.permissions->>'sale'='true'or p.permissions->>'system'='true'or p.permissions->>'purchase'='true'or p.permissions->>'wholesalePricingManage'='true'))))
$$;
revoke all on function solar_private.material_notice_recipient_allowed(uuid,text,bigint)from public,anon,authenticated;
create function solar_private.material_notice_allowed(notice_event text,location bigint)returns boolean
language sql stable security definer set search_path=''as $$select solar_private.material_notice_recipient_allowed(auth.uid(),notice_event,location)$$;
revoke all on function solar_private.material_notice_allowed(text,bigint)from public,anon;
grant execute on function solar_private.material_notice_allowed(text,bigint)to authenticated;
create policy solar_notification_material_scope on public.solar_notifications as restrictive for select to authenticated
 using(event not in('purchase_received','wholesale_prices_updated')or solar_private.material_notice_allowed(event,warehouse_id));

create function solar_private.notify_wholesale_prices(changed_ids bigint[])returns integer
language plpgsql security definer set search_path=''as $$
declare entries jsonb;notice_details jsonb;recipient_count integer;begin
 select jsonb_agg(jsonb_build_object('name',p.name,'model',coalesce(p.code,''),'brand',coalesce(b.name,''),'minPrice',s.minimum_price,'enabled',s.enabled)order by p.name,p.id)
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

-- Mark NEW headers only. No historic purchases are enrolled in this workflow.
-- The deferred emitter sees canonical receipt lines after the atomic save. For
-- legacy header/line REST requests, later lines update the SAME notice without
-- another push. Canonical edits never emit or refresh a purchase-arrival notice.
create table solar_private.purchase_notice_sources(
 invoice_id bigint primary key references public.transactions(id)on delete cascade,
 warehouse_id bigint not null references solar_private.warehouses(id),
 canonical boolean not null,notified_at timestamptz,details jsonb
);
create table solar_private.purchase_notice_recipients(
 invoice_id bigint not null references solar_private.purchase_notice_sources(invoice_id)on delete cascade,
 user_id uuid not null references public.profiles(id),notification_id uuid not null references public.solar_notifications(id)on delete cascade,
 primary key(invoice_id,user_id),unique(notification_id)
);
alter table solar_private.purchase_notice_sources enable row level security;
alter table solar_private.purchase_notice_recipients enable row level security;
revoke all on solar_private.purchase_notice_sources,solar_private.purchase_notice_recipients from public,anon,authenticated;

create function solar_private.track_purchase_notice()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if new.kind='purchase'then
  insert into solar_private.purchase_notice_sources(invoice_id,warehouse_id,canonical)
  values(new.id,coalesce(new.warehouse_id,solar_private.primary_warehouse()),new.fx_pricing);
 end if;
 return new;
end$$;
revoke all on function solar_private.track_purchase_notice()from public,anon,authenticated;
create trigger solar_track_purchase_notice after insert on public.transactions for each row when(new.kind='purchase')execute function solar_private.track_purchase_notice();

create function solar_private.publish_purchase_notice(invoice_id bigint,finalize_canonical boolean default false)returns void
language plpgsql security definer set search_path=''as $$
declare source solar_private.purchase_notice_sources;entries jsonb;notice_details jsonb;recipient uuid;nid uuid;heading text:='دخول مواد جديدة';summary text;begin
 select * into source from solar_private.purchase_notice_sources s where s.invoice_id=publish_purchase_notice.invoice_id for update;
 if source.invoice_id is null or(source.canonical and(not finalize_canonical or source.notified_at is not null))then return;end if;
 if not exists(select 1 from public.transactions t where t.id=invoice_id and t.kind='purchase')then return;end if;
 select jsonb_agg(jsonb_build_object('name',coalesce(i.product_name,p.name,'مادة'),'model',coalesce(p.code,''),'brand',coalesce(nullif(i.brand_name,''),b.name,''),'qty',i.qty)order by i.id)
 into entries from public.transaction_items i left join public.products p on p.id=i.product_id left join public.brands b on b.id=p.brand_id where i.transaction_id=invoice_id and i.qty>0;
 if entries is null then return;end if;
 notice_details:=jsonb_build_object('type','purchase_received','items',entries);
 if notice_details is not distinct from source.details then return;end if;
 summary:='تم استلام '||jsonb_array_length(entries)::text||' مادة. افتح الإشعار لمراجعة الأسماء والموديلات والكميات.';
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
create function solar_private.emit_purchase_notice()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if tg_table_name='transactions'then perform solar_private.publish_purchase_notice(new.id);
 else perform solar_private.publish_purchase_notice(new.transaction_id);end if;
 return new;
end$$;
revoke all on function solar_private.emit_purchase_notice()from public,anon,authenticated;
create constraint trigger solar_purchase_notice_header after insert on public.transactions deferrable initially deferred for each row when(new.kind='purchase')execute function solar_private.emit_purchase_notice();
create constraint trigger solar_purchase_notice_items after insert or update on public.transaction_items deferrable initially deferred for each row execute function solar_private.emit_purchase_notice();

do $$declare definition text;begin
 definition:=pg_get_functiondef('solar_private.invoice_save(uuid,jsonb)'::regprocedure);
 if strpos(definition,' return invoice_result;')=0 then raise exception 'Unexpected purchase notice integration';end if;
 definition:=replace(definition,' return invoice_result;',' if not cached and payload->>''kind''=''purchase''and payload->>''invoiceId''is null then
  perform solar_private.publish_purchase_notice((invoice_result->>''id'')::bigint,true);
 end if;
 return invoice_result;');
 execute definition;
 definition:=pg_get_functiondef('solar_private.wholesale_pricing(text,uuid,jsonb)'::regprocedure);
 if strpos(definition,'next_enabled boolean;')=0 or strpos(definition,'    changed:=true;')=0 or strpos(definition,' result:=solar_private.wholesale_pricing_state();')=0 then raise exception 'Unexpected wholesale notice integration';end if;
 definition:=replace(definition,'next_enabled boolean;','next_enabled boolean;changed_ids bigint[]:=''{}'';changed_count integer:=0;notified_count integer:=0;');
 if strpos(definition,')insert into solar_private.push_deliveries(notification_id,endpoint)select n.id,s.endpoint from notices n join public.solar_push_subscriptions s on s.user_id=n.user_id;')=0 then raise exception 'Unexpected toggle notice counter';end if;
 definition:=replace(definition,')insert into solar_private.push_deliveries(notification_id,endpoint)select n.id,s.endpoint from notices n join public.solar_push_subscriptions s on s.user_id=n.user_id;',
 '), deliveries as(insert into solar_private.push_deliveries(notification_id,endpoint)select n.id,s.endpoint from notices n join public.solar_push_subscriptions s on s.user_id=n.user_id)select count(*)into notified_count from notices;
   changed_count:=1;');
 definition:=replace(definition,'    changed:=true;','    changed:=true;changed_ids:=array_append(changed_ids,target_product_id);');
 definition:=replace(definition,' result:=solar_private.wholesale_pricing_state();',' if action=''save''and changed then
  changed_count:=cardinality(changed_ids);notified_count:=solar_private.notify_wholesale_prices(changed_ids);
 end if;
 result:=solar_private.wholesale_pricing_state()||jsonb_build_object(''changedCount'',changed_count,''notifiedCount'',notified_count);');
 execute definition;
 definition:=pg_get_functiondef('public.solar_push_claim()'::regprocedure);
 if strpos(definition,' where(n.event<>''receipt_delete_decided''')=0 then raise exception 'Unexpected push scope integration';end if;
 definition:=replace(definition,' where(n.event<>''receipt_delete_decided''',' where(n.event not in(''purchase_received'',''wholesale_prices_updated'')or solar_private.material_notice_recipient_allowed(n.user_id,n.event,n.warehouse_id))and(n.event<>''receipt_delete_decided''');
 execute definition;
end$$;
-- Existing SELECT / UPDATE(read_at) grants remain intact. No permission to write
-- details, scope, body, event or recipients is granted to API users.
notify pgrst,'reload schema';
