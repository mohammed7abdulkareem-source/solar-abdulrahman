-- Transfer creation reserves stock at its source. Only source preparation posts it to the destination.
alter table solar_private.warehouse_access
 add column transfer_from_primary boolean not null default false,
 add column transfer_to_primary boolean not null default false,
 add column transfer_other boolean not null default false;
update solar_private.warehouse_access set transfer_from_primary=can_transfer,transfer_to_primary=can_transfer,transfer_other=can_transfer;
alter table solar_private.warehouse_stocks add column reserved_qty numeric not null default 0 check(reserved_qty>=0);
alter table solar_private.stock_transfers drop constraint stock_transfers_status_check;
alter table solar_private.stock_transfers add constraint stock_transfers_status_check check(status in('pending','posted','cancelled','reversed'));
alter table solar_private.stock_transfers alter column status set default 'pending';
alter table solar_private.stock_transfers add column revision bigint not null default 0,
 add column prepared_at timestamptz,add column prepared_by uuid references public.profiles(id) on delete set null,
 add column prepared_name text,add column cancelled_at timestamptz,
 add column cancelled_by uuid references public.profiles(id) on delete set null,add column cancellation_note text;
-- Historical transfers were already completed; their quantities and cost snapshots remain untouched.
update solar_private.stock_transfers set prepared_at=created_at,prepared_name=actor_name where status in('posted','reversed');
create index stock_transfers_prepared_by_idx on solar_private.stock_transfers(prepared_by);
create index stock_transfers_cancelled_by_idx on solar_private.stock_transfers(cancelled_by);
create index stock_transfers_pending_source_idx on solar_private.stock_transfers(from_id,created_at desc) where status='pending';
alter table public.solar_notifications add column stock_transfer_id uuid references solar_private.stock_transfers(id) on delete cascade;
create index solar_notifications_stock_transfer_idx on public.solar_notifications(stock_transfer_id);
do $$declare original text;begin
 select pg_get_expr(conbin,conrelid) into original from pg_constraint where conrelid='public.solar_notifications'::regclass and conname='solar_notifications_event_check';
 if original is null then raise exception 'Notification event constraint missing';end if;
 alter table public.solar_notifications drop constraint solar_notifications_event_check;
 execute 'alter table public.solar_notifications add constraint solar_notifications_event_check check(('||original||') or event in(''stock_transfer_pending'',''stock_transfer_prepared'',''stock_transfer_cancelled'',''stock_transfer_reversed''))';
end$$;

create function solar_private.transfer_direction_allowed(person uuid,source bigint,destination bigint) returns boolean language sql stable security definer set search_path='' as $$
 select source<>destination and solar_private.warehouse_access_allowed(person,source) and solar_private.warehouse_access_allowed(person,destination)
 and exists(select 1 from public.profiles p where p.id=person and p.active and p.user_type<>'installer' and
 ((p.is_admin and p.user_type<>'warehouse') or exists(select 1 from solar_private.warehouse_access a where a.user_id=p.id and
 case when source=solar_private.primary_warehouse() then a.transfer_from_primary when destination=solar_private.primary_warehouse() then a.transfer_to_primary else a.transfer_other end)))
$$;
create function solar_private.can_prepare_transfer(person uuid,source bigint) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=person and p.active and
 ((p.is_admin and p.user_type not in('installer','warehouse')) or(p.user_type='warehouse' and solar_private.warehouse_access_allowed(p.id,source))))
$$;
create function solar_private.can_view_transfer(person uuid,transfer_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from solar_private.stock_transfers t join public.profiles p on p.id=person and p.active and p.user_type<>'installer' where t.id=transfer_id and
 ((p.is_admin and p.user_type<>'warehouse') or
 (p.user_type='warehouse' and solar_private.warehouse_access_allowed(p.id,t.from_id)) or
 (p.user_type<>'warehouse' and t.actor_id=p.id and(solar_private.warehouse_access_allowed(p.id,t.from_id) or solar_private.warehouse_access_allowed(p.id,t.to_id)))))
$$;
create function solar_private.transfer_notice_allowed(transfer_id uuid) returns boolean language sql stable security definer set search_path='' as $$select solar_private.can_view_transfer(auth.uid(),transfer_id)$$;
revoke all on function solar_private.transfer_direction_allowed(uuid,bigint,bigint),solar_private.can_prepare_transfer(uuid,bigint),solar_private.can_view_transfer(uuid,uuid),solar_private.transfer_notice_allowed(uuid) from public,anon,authenticated;
grant execute on function solar_private.transfer_notice_allowed(uuid) to authenticated;
create policy solar_notification_stock_transfer_scope on public.solar_notifications as restrictive for select to authenticated using(stock_transfer_id is null or solar_private.transfer_notice_allowed(stock_transfer_id));

create function solar_private.stock_transfer_notice(recipient uuid,transfer_id uuid,event_name text) returns void language plpgsql security definer set search_path='' as $$
declare t solar_private.stock_transfers;nid uuid;heading text;begin
 if not solar_private.can_view_transfer(recipient,transfer_id) then return;end if;
 select * into t from solar_private.stock_transfers where id=transfer_id;
 if event_name='stock_transfer_pending' and not solar_private.can_prepare_transfer(recipient,t.from_id) then return;end if;
 heading:=case event_name when 'stock_transfer_pending' then 'طلب نقل جديد بانتظار تجهيز مخزن المصدر' when 'stock_transfer_prepared' then 'تم تجهيز النقل وإضافة المواد لمخزن الاستلام' when 'stock_transfer_cancelled' then 'تم إلغاء طلب النقل وإرجاع الكميات المحجوزة' else 'تم عكس نقل المواد' end;
 insert into public.solar_notifications(user_id,stock_transfer_id,event,title,body) values(recipient,t.id,event_name,heading,'نقل #'||t.receipt_no||' • من '||t.from_name||' إلى '||t.to_name) returning id into nid;
 insert into solar_private.push_deliveries(notification_id,endpoint) select nid,endpoint from public.solar_push_subscriptions where user_id=recipient;
 perform solar_private.wake_push();
end$$;
create function solar_private.transfer_json(transfer_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare t solar_private.stock_transfers;p public.profiles;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or not solar_private.can_view_transfer(p.id,transfer_id) then raise exception 'طلب النقل غير متاح' using errcode='42501';end if;
 select * into t from solar_private.stock_transfers where id=transfer_id;
 return jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'fromId',t.from_id,'toId',t.to_id,'fromName',t.from_name,'toName',t.to_name,'date',t.created_at,'actor',t.actor_name,'note',t.note,'status',t.status,'revision',t.revision,
 'preparedAt',t.prepared_at,'preparedBy',t.prepared_name,'cancelledAt',t.cancelled_at,'cancellationNote',t.cancellation_note,'reversedAt',t.reversed_at,
 'canPrepare',t.status='pending' and solar_private.can_prepare_transfer(p.id,t.from_id),
 'canCancel',t.status='pending' and(p.is_admin and p.user_type<>'warehouse' or t.actor_id=p.id),
 'canReverse',t.status='posted' and p.is_admin and p.user_type<>'warehouse',
 'items',case when p.user_type='warehouse' then(select jsonb_agg(i-'unitCost'-'costBasis') from jsonb_array_elements(t.items) i) else t.items end);
end$$;

alter function solar_private.inventory(text,uuid,jsonb) rename to inventory_v350;
revoke all on function solar_private.inventory_v350(text,uuid,jsonb) from public,anon,authenticated;
create function solar_private.inventory(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare person public.profiles;location bigint;destination bigint;t solar_private.stock_transfers;entry jsonb;material public.products;
 result jsonb;old_request solar_private.inventory_requests;items jsonb:='[]';amount numeric;rev bigint;u record;
 target public.profiles;access_before jsonb;ids bigint[];dirs jsonb;from_primary boolean;to_primary boolean;between_other boolean;
 q text;stage text;begin
 select * into person from public.profiles where id=auth.uid() and active and user_type<>'installer';
 if person.id is null then raise exception 'غير مسموح' using errcode='42501';end if;
 location:=nullif(payload->>'warehouseId','')::bigint;
 if action in('context','stock') then
  result:=solar_private.inventory_v350(action,request_id,payload);
  dirs:=case when person.is_admin and person.user_type<>'warehouse' then '{"fromPrimary":true,"toPrimary":true,"other":true}'::jsonb else
    coalesce((select jsonb_build_object('fromPrimary',transfer_from_primary,'toPrimary',transfer_to_primary,'other',transfer_other) from solar_private.warehouse_access where user_id=person.id),'{"fromPrimary":false,"toPrimary":false,"other":false}') end;
  return result||jsonb_build_object('transferDirections',dirs,'canTransfer',(dirs->>'fromPrimary')::boolean or(dirs->>'toPrimary')::boolean or(dirs->>'other')::boolean,
   'canPrepareTransfers',person.user_type='warehouse' or person.is_admin,'pendingTransferCount',(select count(*) from solar_private.stock_transfers where status='pending' and solar_private.can_prepare_transfer(person.id,from_id)));
 elsif action='manage' then
  result:=solar_private.inventory_v350(action,request_id,payload);
  return jsonb_set(result,'{users}',coalesce((select jsonb_agg(x.value||jsonb_build_object('transferDirections',jsonb_build_object('fromPrimary',coalesce(a.transfer_from_primary,false),'toPrimary',coalesce(a.transfer_to_primary,false),'other',coalesce(a.transfer_other,false)))) from jsonb_array_elements(result->'users') x(value) left join solar_private.warehouse_access a on a.user_id=(x.value->>'id')::uuid),'[]'));
 elsif action in('transfers','transfer_queue','transfer_get') then
  if not(person.is_admin or person.user_type='warehouse' or person.permissions->>'stock'='true' or person.permissions->>'warehouse'='true' or person.permissions->>'stockMovement'='true') then raise exception 'غير مسموح' using errcode='42501';end if;
  if location is not null and not solar_private.warehouse_access_allowed(person.id,location) then raise exception 'لا تملك صلاحية هذا المخزن' using errcode='42501';end if;
  if action='transfer_get' then return solar_private.transfer_json((payload->>'id')::uuid);end if;
  if action='transfers' then return(select coalesce(jsonb_agg(solar_private.transfer_json(r.id) order by r.created_at desc),'[]') from(select id,created_at from solar_private.stock_transfers where solar_private.can_view_transfer(person.id,id) and(location is null or location in(from_id,to_id)) and(payload->>'id' is null or id=(payload->>'id')::uuid) order by created_at desc limit 200) r);end if;
  if person.user_type<>'warehouse' and not person.is_admin then raise exception 'التجهيز لمسؤول مخزن المصدر أو الإدارة' using errcode='42501';end if;
  q:=coalesce(payload->>'search','');stage:=coalesce(payload->>'state','pending');
  if stage not in('','pending','posted','cancelled','reversed') or length(q)>200 then raise exception 'تصفية طلبات النقل غير صحيحة';end if;
  with matched as materialized(select s.* from solar_private.stock_transfers s where solar_private.can_prepare_transfer(person.id,s.from_id) and(location is null or s.from_id=location)
   and(payload->>'id' is null or s.id=(payload->>'id')::uuid) and(q='' or strpos(solar_private.customer_name_key(s.receipt_no::text||' '||s.actor_name||' '||s.from_name||' '||s.to_name),solar_private.customer_name_key(q))>0)),
  filtered as(select * from matched where stage='' or status=stage),paged as(select * from filtered order by created_at desc limit 30 offset greatest(0,least(coalesce((payload->>'offset')::integer,0),1000000)))
  select jsonb_build_object('count',(select count(*) from filtered),'statusCounts',jsonb_build_object('pending',(select count(*) from matched where status='pending'),'posted',(select count(*) from matched where status='posted'),'all',(select count(*) from matched)),
   'rows',coalesce((select jsonb_agg(solar_private.transfer_json(id) order by created_at desc) from paged),'[]')) into result;return result;
 end if;
 if action not in('transfer','prepare_transfer','cancel_transfer','reverse_transfer','access_save') then
  if action='warehouse_save' and payload->>'active'='false' then
   if not person.is_admin or person.user_type='warehouse' then raise exception 'للإدارة فقط' using errcode='42501';end if;
   perform pg_advisory_xact_lock(7311,1);
   if exists(select 1 from solar_private.stock_transfers where status='pending' and(payload->>'id')::bigint in(from_id,to_id)) then raise exception 'أكمل أو ألغِ طلبات النقل المرتبطة بالمخزن قبل إيقافه';end if;
  end if;
  return solar_private.inventory_v350(action,request_id,payload);
 end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب غير صحيح';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into old_request from solar_private.inventory_requests where id=request_id;
 if old_request.id is not null then
  if old_request.actor_id<>person.id or old_request.action<>action or old_request.payload<>payload then raise exception 'طلب مكرر ببيانات مختلفة' using errcode='PT409';end if;return old_request.result;
 end if;
 if action='access_save' then
  if not person.is_admin or person.user_type='warehouse' then raise exception 'للإدارة فقط' using errcode='42501';end if;
  select * into target from public.profiles where id=(payload->>'userId')::uuid and active and not is_admin and user_type<>'installer';
  if target.id is null then raise exception 'اختر مستخدماً فعالاً أو مسؤول مخزن';end if;
  select to_jsonb(a) into access_before from solar_private.warehouse_access a where user_id=target.id for update;
  if coalesce((access_before->>'revision')::bigint,0) is distinct from (payload->>'revision')::bigint then raise exception 'تغيرت صلاحيات المستخدم؛ حدّث الصفحة' using errcode='PT409';end if;
  select coalesce(array_agg(distinct value::text::bigint),'{}') into ids from jsonb_array_elements(coalesce(payload->'ids','[]'));
  if exists(select 1 from unnest(ids) i where not exists(select 1 from solar_private.warehouses where id=i and active)) then raise exception 'اختر مخازن فعالة';end if;
  if payload ? 'transferDirections' then
   dirs:=payload->'transferDirections';
   if jsonb_typeof(dirs) is distinct from 'object' then raise exception 'حدد اتجاهات النقل';end if;
   from_primary:=coalesce((dirs->>'fromPrimary')::boolean,false);to_primary:=coalesce((dirs->>'toPrimary')::boolean,false);between_other:=coalesce((dirs->>'other')::boolean,false);
  elsif coalesce((payload->>'canTransfer')::boolean,false) then
   if not coalesce((access_before->>'can_transfer')::boolean,false) then raise exception 'حدّث البرنامج لتحديد اتجاهات النقل المسموحة';end if;
   from_primary:=(access_before->>'transfer_from_primary')::boolean;to_primary:=(access_before->>'transfer_to_primary')::boolean;between_other:=(access_before->>'transfer_other')::boolean;
  else from_primary:=false;to_primary:=false;between_other:=false;end if;
  insert into solar_private.warehouse_access(user_id,all_warehouses,warehouse_ids,can_transfer,transfer_from_primary,transfer_to_primary,transfer_other,revision,updated_by)
   values(target.id,coalesce((payload->>'all')::boolean,false),ids,from_primary or to_primary or between_other,from_primary,to_primary,between_other,1,person.id)
   on conflict(user_id) do update set all_warehouses=excluded.all_warehouses,warehouse_ids=excluded.warehouse_ids,can_transfer=excluded.can_transfer,transfer_from_primary=excluded.transfer_from_primary,transfer_to_primary=excluded.transfer_to_primary,transfer_other=excluded.transfer_other,revision=solar_private.warehouse_access.revision+1,updated_by=person.id,updated_at=now();
  select to_jsonb(a) into result from solar_private.warehouse_access a where user_id=target.id;
  insert into solar_private.warehouse_access_audit(actor_id,user_id,before_value,after_value) values(person.id,target.id,access_before,result);
  if target.user_type<>'warehouse' and(from_primary or to_primary or between_other) then update public.profiles set permissions=coalesce(permissions,'{}'::jsonb)||'{"stock":true}' where id=target.id;end if;
  update solar_private.push_deliveries d set status='failed',last_status=403 from public.solar_notifications n where d.notification_id=n.id and n.user_id=target.id and d.status='pending' and
   ((n.stock_transfer_id is not null and not solar_private.can_view_transfer(target.id,n.stock_transfer_id)) or(n.job_id is not null and not solar_private.notification_recipient_allowed(target.id,n.job_id)));
 elsif action='transfer' then
  location:=(payload->>'fromId')::bigint;destination:=(payload->>'toId')::bigint;
  if location is null or destination is null or not solar_private.transfer_direction_allowed(person.id,location,destination) then raise exception 'اتجاه النقل أو أحد المخزنين غير مسموح لهذا المستخدم' using errcode='42501';end if;
  if(select count(*) from solar_private.warehouses where id in(location,destination) and active)<>2 then raise exception 'اختر مخازن فعالة';end if;
  if jsonb_typeof(payload->'items') is distinct from 'array' or jsonb_array_length(payload->'items') not between 1 and 300 or length(coalesce(payload->>'note',''))>2000 then raise exception 'أضف مواد النقل بصورة صحيحة';end if;
  if(select count(*) from jsonb_array_elements(payload->'items'))<>(select count(distinct value->>'productId') from jsonb_array_elements(payload->'items')) then raise exception 'مادة مكررة';end if;
  perform 1 from public.products where id in(select (value->>'productId')::bigint from jsonb_array_elements(payload->'items')) order by id for update;
  for entry in select value from jsonb_array_elements(payload->'items') loop
   select * into material from public.products where id=(entry->>'productId')::bigint;
   amount:=(entry->>'qty')::numeric;
   if material.id is null or amount is null or amount::text in('NaN','Infinity','-Infinity') or not(amount>0 and amount<=1000000000) or amount<>round(amount,3) then raise exception 'أدخل كميات صحيحة';end if;
   select revision into rev from solar_private.warehouse_stocks where warehouse_id=location and product_id=material.id;
   if coalesce(rev,0) is distinct from(entry->>'revision')::bigint then raise exception 'تغير رصيد المادة؛ حدّث الكميات قبل النقل' using errcode='PT409';end if;
   perform solar_private.change_warehouse_stock(location,material.id,-amount);
   update solar_private.warehouse_stocks set reserved_qty=reserved_qty+amount where warehouse_id=location and product_id=material.id;
   update public.products set costing_revision=costing_revision+1 where id=material.id;
   items:=items||jsonb_build_array(jsonb_build_object('productId',material.id,'code',material.code,'name',material.name,'brand',(select name from public.brands where id=material.brand_id),'category',material.category,'qty',amount,'unitCost',material.cost,'costBasis',material.cost_basis));
  end loop;
  insert into solar_private.stock_transfers(id,from_id,to_id,from_name,to_name,items,note,actor_id,actor_name,status)
   values(request_id,location,destination,(select name from solar_private.warehouses where id=location),(select name from solar_private.warehouses where id=destination),items,coalesce(payload->>'note',''),person.id,coalesce(person.display_name,person.username),'pending') returning * into t;
  for u in select id from public.profiles where active and user_type='warehouse' and solar_private.can_prepare_transfer(id,t.from_id) loop perform solar_private.stock_transfer_notice(u.id,t.id,'stock_transfer_pending');end loop;
  result:=jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'status',t.status,'revision',t.revision);
 else
  select * into t from solar_private.stock_transfers where id=(payload->>'id')::uuid for update;
  if t.id is null or not solar_private.can_view_transfer(person.id,t.id) then raise exception 'طلب النقل غير متاح' using errcode='42501';end if;
  if t.revision is distinct from(payload->>'expectedRevision')::bigint then raise exception 'تغير طلب النقل؛ حدّث الصفحة' using errcode='PT409';end if;
  if action='prepare_transfer' and not solar_private.can_prepare_transfer(person.id,t.from_id) then raise exception 'تأكيد التجهيز لمسؤول مخزن المصدر فقط' using errcode='42501';end if;
  if action='cancel_transfer' and not((person.is_admin and person.user_type<>'warehouse') or t.actor_id=person.id) then raise exception 'إلغاء الطلب لصاحبه أو الإدارة' using errcode='42501';end if;
  if action='reverse_transfer' and not(person.is_admin and person.user_type<>'warehouse') then raise exception 'عكس النقل للإدارة فقط' using errcode='42501';end if;
  if(action in('prepare_transfer','cancel_transfer') and t.status<>'pending') or(action='reverse_transfer' and t.status<>'posted') then raise exception 'طلب النقل مجهز أو ملغى؛ حدّث الحالة' using errcode='PT409';end if;
  perform 1 from public.products where id in(select (value->>'productId')::bigint from jsonb_array_elements(t.items)) order by id for update;
  for entry in select value from jsonb_array_elements(t.items) loop
   amount:=(entry->>'qty')::numeric;
   if not exists(select 1 from public.products where id=(entry->>'productId')::bigint) then raise exception 'إحدى المواد لم تعد موجودة';end if;
   if action='reverse_transfer' then
    perform solar_private.change_warehouse_stock(t.to_id,(entry->>'productId')::bigint,-amount);
    perform solar_private.change_warehouse_stock(t.from_id,(entry->>'productId')::bigint,amount);
   else
    update solar_private.warehouse_stocks set reserved_qty=reserved_qty-amount,revision=revision+1 where warehouse_id=t.from_id and product_id=(entry->>'productId')::bigint and reserved_qty>=amount;
    if not found then raise exception 'حجز المادة غير مطابق؛ لم يتم الحفظ' using errcode='23514';end if;
    perform solar_private.change_warehouse_stock(case when action='prepare_transfer' then t.to_id else t.from_id end,(entry->>'productId')::bigint,amount);
   end if;
   update public.products set costing_revision=costing_revision+1 where id=(entry->>'productId')::bigint;
  end loop;
  if action='prepare_transfer' then
   update solar_private.stock_transfers set status='posted',revision=revision+1,prepared_at=now(),prepared_by=person.id,prepared_name=coalesce(person.display_name,person.username) where id=t.id;
   perform solar_private.stock_transfer_notice(t.actor_id,t.id,'stock_transfer_prepared');
  elsif action='cancel_transfer' then
   update solar_private.stock_transfers set status='cancelled',revision=revision+1,cancelled_at=now(),cancelled_by=person.id,cancellation_note=left(coalesce(payload->>'note','إلغاء طلب النقل قبل التجهيز'),2000) where id=t.id;
   for u in select id from public.profiles where active and user_type='warehouse' and solar_private.can_prepare_transfer(id,t.from_id) loop perform solar_private.stock_transfer_notice(u.id,t.id,'stock_transfer_cancelled');end loop;
   if person.id<>t.actor_id then perform solar_private.stock_transfer_notice(t.actor_id,t.id,'stock_transfer_cancelled');end if;
  else
   update solar_private.stock_transfers set status='reversed',revision=revision+1,reversed_at=now(),reversed_by=person.id where id=t.id;
   perform solar_private.stock_transfer_notice(t.actor_id,t.id,'stock_transfer_reversed');
  end if;
  select jsonb_build_object('id',id,'receiptNo',receipt_no,'status',status,'revision',revision) into result from solar_private.stock_transfers where id=t.id;
 end if;
 insert into solar_private.inventory_requests(id,actor_id,action,payload,result) values(request_id,person.id,action,payload,result);
 return result;
end$$;
create or replace function public.solar_inventory(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select solar_private.inventory(action,request_id,payload)$$;
revoke all on function public.solar_inventory(text,uuid,jsonb),solar_private.inventory(text,uuid,jsonb) from public,anon;
grant execute on function public.solar_inventory(text,uuid,jsonb),solar_private.inventory(text,uuid,jsonb) to authenticated;
revoke all on function solar_private.stock_transfer_notice(uuid,uuid,text),solar_private.transfer_json(uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION solar_private.inventory_consistency()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare material bigint;actual numeric;expected numeric;begin
 if tg_table_name='products' then material:=new.id;else material:=coalesce(new.product_id,old.product_id);end if;
 select qty into expected from public.products where id=material;
 if not found then return null;end if;
 select coalesce(sum(qty+reserved_qty),0) into actual from solar_private.warehouse_stocks where product_id=material;
 if actual<>expected then raise exception 'رصيد المخازن لا يطابق الرصيد الكلي؛ لم تُحفظ العملية' using errcode='23514';end if;
 if exists(select 1 from solar_private.warehouse_stocks s where s.product_id=material and s.reserved_qty<>(
  select coalesce(sum((i.value->>'qty')::numeric),0) from solar_private.stock_transfers t cross join lateral jsonb_array_elements(t.items) i(value) where t.status='pending' and t.from_id=s.warehouse_id and(i.value->>'productId')::bigint=material
 )) then raise exception 'الكميات المحجوزة لا تطابق طلبات النقل؛ لم تُحفظ العملية' using errcode='23514';end if;
 return null;
end$function$;

CREATE OR REPLACE FUNCTION solar_private.inventory_catalog(location bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles;begin
 select * into p from public.profiles where id=auth.uid() and active and user_type<>'installer';
 if p.id is null then raise exception 'غير مسموح' using errcode='42501';end if;
 if location is not null and not solar_private.warehouse_access_allowed(p.id,location) then raise exception 'لا تملك صلاحية هذا المخزن' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'code',m.code,'name',m.name,'brand',b.name,'brand_id',m.brand_id,'brands',jsonb_build_object('name',b.name),'category',m.category,
 'reservedQty',coalesce((select sum(s.reserved_qty) from solar_private.warehouse_stocks s where s.product_id=m.id and(location is null or s.warehouse_id=location) and solar_private.warehouse_access_allowed(p.id,s.warehouse_id)),0),
 'bookQty',coalesce((select sum(s.qty+s.reserved_qty) from solar_private.warehouse_stocks s where s.product_id=m.id and(location is null or s.warehouse_id=location) and solar_private.warehouse_access_allowed(p.id,s.warehouse_id)),0),
 'stockRevision',coalesce((select revision from solar_private.warehouse_stocks where product_id=m.id and warehouse_id=location),0),'qty',coalesce((select sum(s.qty) from solar_private.warehouse_stocks s where s.product_id=m.id and(location is null or s.warehouse_id=location) and solar_private.warehouse_access_allowed(p.id,s.warehouse_id)),0))||
 case when p.user_type='warehouse' then '{}'::jsonb else jsonb_build_object('cost',m.cost,'cost_basis',m.cost_basis,'costing_revision',m.costing_revision,'companyQty',case when solar_private.can_read_global_stock() then m.qty end) end order by m.name,m.id),'[]') from public.products m left join public.brands b on b.id=m.brand_id);
end$function$;

CREATE OR REPLACE FUNCTION solar_private.inventory_movements(location bigint, product_filter bigint, customer_filter text, date_from date, date_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;begin
 if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.user_type<>'installer' and(p.is_admin or p.user_type='warehouse' or p.permissions->>'stockMovement'='true' or p.permissions->>'warehouse'='true')) then raise exception 'غير مسموح' using errcode='42501';end if;
 if location is not null and not solar_private.warehouse_access_allowed(auth.uid(),location) then raise exception 'لا تملك صلاحية هذا المخزن' using errcode='42501';end if;
 with movements as(
  select 'line:'||i.id id,i.product_id,i.product_name,i.brand_name,i.category,t.id invoice_id,t.receipt_no,t.kind,t.party_name,t.created_at,t.created_by movement_owner,
   case when t.kind='purchase' then i.qty else -i.qty end delta,t.warehouse_id,''::text note
  from public.transaction_items i join public.transactions t on t.id=i.transaction_id where t.kind in('purchase','sale','system')
  union all
  select 'adjustment:'||a.id,a.product_id,p.name,b.name,p.category,a.id,a.id,'stock_adjustment','',a.created_at,a.actor_id,a.actual_qty-a.old_qty,a.warehouse_id,a.note||' | السابق: '||a.old_qty||' | الفعلي: '||a.actual_qty from solar_private.stock_adjustments a join public.products p on p.id=a.product_id left join public.brands b on b.id=p.brand_id
  union all
  select 'transfer-source:'||t.id||':'||line.ordinality,(line.value->>'productId')::bigint,line.value->>'name',line.value->>'brand',line.value->>'category',t.receipt_no,t.receipt_no,
   case when t.status='pending' then 'transfer_reserved' else 'transfer_out' end,t.to_name,t.created_at,t.actor_id,-(line.value->>'qty')::numeric,t.from_id,t.note
  from solar_private.stock_transfers t cross join lateral jsonb_array_elements(t.items) with ordinality line(value,ordinality)
  where solar_private.role_name()<>'warehouse' or solar_private.warehouse_access_allowed(auth.uid(),t.from_id)
  union all
  select 'transfer-destination:'||t.id||':'||line.ordinality,(line.value->>'productId')::bigint,line.value->>'name',line.value->>'brand',line.value->>'category',t.receipt_no,t.receipt_no,'transfer_in',t.from_name,coalesce(t.prepared_at,t.created_at),t.actor_id,(line.value->>'qty')::numeric,t.to_id,t.note
  from solar_private.stock_transfers t cross join lateral jsonb_array_elements(t.items) with ordinality line(value,ordinality)
  where t.status in('posted','reversed') and(solar_private.role_name()<>'warehouse' or solar_private.warehouse_access_allowed(auth.uid(),t.from_id))
  union all
  select 'transfer-cancelled:'||t.id||':'||line.ordinality,(line.value->>'productId')::bigint,line.value->>'name',line.value->>'brand',line.value->>'category',t.receipt_no,t.receipt_no,'transfer_cancelled',t.to_name,t.cancelled_at,t.actor_id,(line.value->>'qty')::numeric,t.from_id,'إلغاء حجز: '||coalesce(t.cancellation_note,'')
  from solar_private.stock_transfers t cross join lateral jsonb_array_elements(t.items) with ordinality line(value,ordinality)
  where t.status='cancelled' and(solar_private.role_name()<>'warehouse' or solar_private.warehouse_access_allowed(auth.uid(),t.from_id))
  union all
  select 'transfer-reversal:'||t.id||':'||d.direction||':'||line.ordinality,(line.value->>'productId')::bigint,line.value->>'name',line.value->>'brand',line.value->>'category',t.receipt_no,t.receipt_no,case when d.direction=1 then 'transfer_return_in' else 'transfer_return_out' end,
   case when d.direction=1 then t.to_name else t.from_name end,t.reversed_at,t.actor_id,(line.value->>'qty')::numeric*d.direction,case when d.direction=1 then t.from_id else t.to_id end,'عكس نقل: '||t.note
  from solar_private.stock_transfers t cross join lateral jsonb_array_elements(t.items) with ordinality line(value,ordinality) cross join (values(1),(-1)) d(direction) where t.status='reversed' and(solar_private.role_name()<>'warehouse' or solar_private.warehouse_access_allowed(auth.uid(),t.from_id))
 ), balances as(
  select m.*,w.name warehouse_name,coalesce(s.qty,0)-sum(delta) over(partition by m.warehouse_id,m.product_id)+sum(delta) over(partition by m.warehouse_id,m.product_id order by m.created_at,m.invoice_id,m.id rows unbounded preceding) balance
  from movements m join solar_private.warehouses w on w.id=m.warehouse_id left join solar_private.warehouse_stocks s on s.warehouse_id=m.warehouse_id and s.product_id=m.product_id
  where solar_private.warehouse_access_allowed(auth.uid(),m.warehouse_id) and(location is null or m.warehouse_id=location)
 ) select coalesce(jsonb_agg(jsonb_build_object('id',id,'productId',product_id,'name',product_name,'brand',brand_name,'category',category,'receiptNo',receipt_no,'kind',kind,'party',party_name,'date',created_at,'note',note,'inQty',greatest(delta,0),'outQty',greatest(-delta,0),'balance',balance,'warehouseId',warehouse_id,'warehouseName',warehouse_name) order by created_at,invoice_id,id),'[]') into result from balances
 where (solar_private.role_name() in('admin','warehouse') or movement_owner=auth.uid()) and(product_filter is null or product_id=product_filter)
 and(coalesce(customer_filter,'')='' or(kind in('sale','system') and strpos(lower(coalesce(party_name,'')),lower(customer_filter))>0))
 and(date_from is null or created_at>=(date_from::timestamp at time zone 'Asia/Baghdad')) and(date_to is null or created_at<((date_to+1)::timestamp at time zone 'Asia/Baghdad'));
 return result;
end$function$;

CREATE OR REPLACE FUNCTION public.solar_push_claim()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 with eligible as (
 select d.id from solar_private.push_deliveries d join public.solar_notifications n on n.id=d.notification_id
 join public.solar_push_subscriptions s on s.endpoint=d.endpoint and s.user_id=n.user_id
 join public.profiles p on p.id=n.user_id and p.active
 where(n.stock_transfer_id is null or solar_private.can_view_transfer(n.user_id,n.stock_transfer_id)) and(n.job_id is null or solar_private.notification_recipient_allowed(n.user_id,n.job_id)) and d.attempts<5 and n.created_at>now()-interval '1 day' and ((d.status='pending' and d.available_at<=now()) or (d.status='sending' and d.lease_until<now()))
 order by d.available_at for update of d skip locked limit 20
 ), claimed as (
 update solar_private.push_deliveries d set status='sending',attempts=attempts+1,lease_until=now()+interval '2 minutes'
 from eligible e where d.id=e.id returning d.*
 )
 select coalesce(jsonb_agg(jsonb_build_object('deliveryId',d.id,'attempt',d.attempts,'endpoint',s.endpoint,'keys',jsonb_build_object('p256dh',s.p256dh,'auth',s.auth_key),'notification',jsonb_build_object('id',n.id,'userId',n.user_id,'jobId',n.job_id,'event',n.event,'invoiceKind',(select t.kind from public.transactions t where t.id=n.job_id),'stockTransferId',n.stock_transfer_id,'transferId',n.transfer_id,'title',n.title,'body',n.body))),'[]'::jsonb)
 into result from claimed d join public.solar_notifications n on n.id=d.notification_id join public.solar_push_subscriptions s on s.endpoint=d.endpoint and s.user_id=n.user_id;
 return result;
end $function$;

revoke all on function public.solar_push_claim() from public,anon,authenticated;grant execute on function public.solar_push_claim() to service_role;

notify pgrst,'reload schema';
