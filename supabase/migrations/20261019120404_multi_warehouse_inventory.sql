-- A location holds quantities; book cost remains the company's weighted average.
create table solar_private.warehouses (
 id bigint generated always as identity primary key,
 name text not null check(length(trim(name)) between 1 and 100),
 code text not null unique, is_primary boolean not null default false,
 active boolean not null default true, revision bigint not null default 0,
 created_at timestamptz not null default now()
);
create unique index warehouses_one_primary on solar_private.warehouses(is_primary) where is_primary;
create unique index warehouses_unique_name on solar_private.warehouses(lower(trim(name)));
insert into solar_private.warehouses(name,code,is_primary) values('المخزن الرئيسي','MAIN',true),('مخزن صيادة','SAYADA',false);
create table solar_private.warehouse_access (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 all_warehouses boolean not null default false, warehouse_ids bigint[] not null default '{}',
 can_transfer boolean not null default false, revision bigint not null default 0,
 updated_by uuid references public.profiles(id) on delete set null, updated_at timestamptz not null default now()
);
create index warehouse_access_updated_by_idx on solar_private.warehouse_access(updated_by);
create table solar_private.warehouse_stocks (
 warehouse_id bigint not null references solar_private.warehouses(id),
 product_id bigint not null references public.products(id) on delete cascade,
 qty numeric not null default 0 check(qty>=0 and qty<=1000000000000),
 revision bigint not null default 0, primary key(warehouse_id,product_id)
);
create index warehouse_stocks_product_idx on solar_private.warehouse_stocks(product_id);
create table solar_private.stock_transfers (
 id uuid primary key, receipt_no bigint generated always as identity unique,
 from_id bigint not null references solar_private.warehouses(id),
 to_id bigint not null references solar_private.warehouses(id),
 from_name text not null, to_name text not null, items jsonb not null,
 note text not null default '', actor_id uuid references public.profiles(id) on delete set null,
 actor_name text not null, created_at timestamptz not null default now(),
 status text not null default 'posted' check(status in('posted','reversed')),
 reversed_at timestamptz, reversed_by uuid references public.profiles(id) on delete set null,
 check(from_id<>to_id)
);
create index stock_transfers_date_idx on solar_private.stock_transfers(created_at desc);
create index stock_transfers_from_idx on solar_private.stock_transfers(from_id);
create index stock_transfers_to_idx on solar_private.stock_transfers(to_id);
create index stock_transfers_actor_idx on solar_private.stock_transfers(actor_id);
create index stock_transfers_reversed_by_idx on solar_private.stock_transfers(reversed_by);
create table solar_private.inventory_requests (
 id uuid primary key, actor_id uuid not null, action text not null, payload jsonb not null,
 result jsonb not null, created_at timestamptz not null default now()
);
create table solar_private.warehouse_access_audit (
 id bigint generated always as identity primary key, actor_id uuid not null,
 user_id uuid not null, before_value jsonb, after_value jsonb not null, created_at timestamptz not null default now()
);
alter table solar_private.warehouses enable row level security;
alter table solar_private.warehouse_access enable row level security;
alter table solar_private.warehouse_stocks enable row level security;
alter table solar_private.stock_transfers enable row level security;
alter table solar_private.inventory_requests enable row level security;
alter table solar_private.warehouse_access_audit enable row level security;
revoke all on solar_private.warehouses,solar_private.warehouse_access,solar_private.warehouse_stocks,solar_private.stock_transfers,solar_private.inventory_requests,solar_private.warehouse_access_audit from public,anon,authenticated;

create function solar_private.primary_warehouse() returns bigint language sql stable security definer set search_path='' as $$select id from solar_private.warehouses where is_primary$$;
create function solar_private.warehouse_access_allowed(person uuid, location bigint) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=person and p.active and p.user_type<>'installer' and
 ((p.is_admin and p.user_type<>'warehouse') or exists(select 1 from solar_private.warehouse_access a where a.user_id=p.id and(a.all_warehouses or location=any(a.warehouse_ids))) or
 (not exists(select 1 from solar_private.warehouse_access a where a.user_id=p.id) and location=solar_private.primary_warehouse())))
$$;
create function solar_private.can_read_global_stock() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.user_type not in('installer','warehouse') and
 (p.is_admin or exists(select 1 from solar_private.warehouse_access a where a.user_id=p.id and a.all_warehouses)))
$$;
revoke all on function solar_private.primary_warehouse(),solar_private.warehouse_access_allowed(uuid,bigint),solar_private.can_read_global_stock() from public,anon,authenticated;
grant execute on function solar_private.can_read_global_stock() to authenticated;
-- The raw table contains the company quantity. Scoped users obtain quantities via the protected catalog RPC.
create policy solar_products_location_scope on public.products as restrictive for select to authenticated using((select solar_private.can_read_global_stock()));

alter table public.transactions add column warehouse_id bigint references solar_private.warehouses(id), add column warehouse_name text;
create index transactions_warehouse_id_idx on public.transactions(warehouse_id);
create index transactions_warehouse_queue_idx on public.transactions(warehouse_id,warehouse_status,created_at desc) where kind in('sale','system');
alter table solar_private.stock_adjustments add column warehouse_id bigint not null default solar_private.primary_warehouse() references solar_private.warehouses(id);
-- Do not run the financial/update notification triggers for this metadata-only backfill.
do $$declare enabled text[]; name text;begin
 select array_agg(tgname) into enabled from pg_trigger where tgrelid='public.transactions'::regclass and not tgisinternal and tgenabled='O';
 foreach name in array enabled loop execute format('alter table public.transactions disable trigger %I',name);end loop;
 update public.transactions set warehouse_id=solar_private.primary_warehouse(),warehouse_name='المخزن الرئيسي' where kind in('sale','system','purchase');
 foreach name in array enabled loop execute format('alter table public.transactions enable trigger %I',name);end loop;
end$$;
create function solar_private.inventory_raw_product_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in('anon','authenticated') then raise exception 'استخدم تعريف المواد أو تسوية المخزون المحمية' using errcode='42501';end if;
 if tg_op='DELETE' then return old;end if;return new;
end$$;
create trigger solar_inventory_product_write before insert or update or delete on public.products for each row execute function solar_private.inventory_raw_product_guard();

create function solar_private.inventory(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare person public.profiles; location bigint; dest bigint; material public.products; entry jsonb; snapshots jsonb:='[]'; result jsonb; prior solar_private.inventory_requests;
 access_before jsonb; target_user public.profiles; ids bigint[]; w solar_private.warehouses; transfer solar_private.stock_transfers;
 amount numeric; available numeric; book_cost numeric; revision_value bigint; target numeric;
begin
 select * into person from public.profiles where id=auth.uid() and active and user_type<>'installer';
 if person.id is null then raise exception 'غير مسموح' using errcode='42501';end if;
 location:=nullif(payload->>'warehouseId','')::bigint;
 if action in('context','stock','catalog') then
  if action in('stock','context') and not(person.is_admin or person.user_type='warehouse' or person.permissions->>'stock'='true' or person.permissions->>'stockMovement'='true' or person.permissions->>'warehouse'='true' or person.permissions->>'sale'='true' or person.permissions->>'system'='true' or person.permissions->>'purchase'='true') then raise exception 'لا تملك صلاحية المخزون' using errcode='42501';end if;
  if action='catalog' then return solar_private.inventory_catalog(location);end if;
  if location is not null and not solar_private.warehouse_access_allowed(person.id,location) then raise exception 'لا تملك صلاحية هذا المخزن' using errcode='42501';end if;
  return jsonb_build_object('warehouses',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'code',code,'primary',is_primary,'active',active,'revision',revision) order by is_primary desc,id),'[]') from solar_private.warehouses where solar_private.warehouse_access_allowed(person.id,id)),
   'products',case when action='stock' then solar_private.inventory_catalog(location) else '[]'::jsonb end,
   'canTransfer',(person.is_admin and person.user_type<>'warehouse') or exists(select 1 from solar_private.warehouse_access where user_id=person.id and can_transfer),
   'canAdjust',person.user_type<>'warehouse' and(person.is_admin or person.permissions->>'stockAdjust'='true'),
   'canManage',person.is_admin and person.user_type<>'warehouse','showCost',person.user_type<>'warehouse');
 elsif action='orders' then
  if location is not null and not solar_private.warehouse_access_allowed(person.id,location) then raise exception 'لا تملك صلاحية هذا المخزن' using errcode='42501';end if;
  perform set_config('solar.warehouse_filter',coalesce(location::text,''),true);
  result:=solar_private.warehouse_orders(coalesce(payload->>'search',''),coalesce(payload->>'state','pending'),coalesce((payload->>'offset')::integer,0));
  perform set_config('solar.warehouse_filter','',true);return result;
 elsif action='movements' then
  return solar_private.inventory_movements(location,(payload->>'productId')::bigint,coalesce(payload->>'customer',''),nullif(payload->>'from','')::date,nullif(payload->>'to','')::date);
 elsif action='transfers' then
  if not(person.is_admin or person.user_type='warehouse' or person.permissions->>'stock'='true' or person.permissions->>'warehouse'='true' or person.permissions->>'stockMovement'='true') then raise exception 'غير مسموح' using errcode='42501';end if;
  if location is not null and not solar_private.warehouse_access_allowed(person.id,location) then raise exception 'لا تملك صلاحية هذا المخزن' using errcode='42501';end if;
  return (select coalesce(jsonb_agg(x.value order by x.created_at desc),'[]') from(
   select t.created_at,jsonb_build_object('id',id,'receiptNo',receipt_no,'fromId',from_id,'toId',to_id,'fromName',from_name,'toName',to_name,'date',created_at,'actor',actor_name,'note',note,'status',status,'reversedAt',reversed_at,
    'items',case when person.user_type='warehouse' then (select jsonb_agg(i-'unitCost'-'costBasis') from jsonb_array_elements(items) i) else items end) value from solar_private.stock_transfers t
    where(solar_private.warehouse_access_allowed(person.id,from_id) or solar_private.warehouse_access_allowed(person.id,to_id)) and(location is null or location in(from_id,to_id)) order by created_at desc limit 200) x);
 elsif action='manage' then
  if not(person.is_admin and person.user_type<>'warehouse') then raise exception 'للإدارة فقط' using errcode='42501';end if;
  return jsonb_build_object('warehouses',(select jsonb_agg(to_jsonb(location_row) order by location_row.is_primary desc,location_row.id) from solar_private.warehouses location_row),
   'users',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(p.display_name,p.username),'role',p.user_type,'all',coalesce(a.all_warehouses,false),'ids',coalesce(a.warehouse_ids,array[solar_private.primary_warehouse()]),'canTransfer',coalesce(a.can_transfer,false),'revision',coalesce(a.revision,0)) order by coalesce(p.display_name,p.username)),'[]') from public.profiles p left join solar_private.warehouse_access a on a.user_id=p.id where p.active and not p.is_admin and p.user_type<>'installer'));
 end if;
 if action not in('transfer','reverse_transfer','warehouse_save','access_save','catalog_save') or action is null or request_id is null then raise exception 'طلب مخزني غير صحيح';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into prior from solar_private.inventory_requests where id=request_id;
 if prior.id is not null then
  if prior.actor_id<>person.id or prior.action<>action or prior.payload<>payload then raise exception 'طلب مكرر ببيانات مختلفة' using errcode='PT409';end if;return prior.result;
 end if;
 if action='catalog_save' then
  if person.user_type='warehouse' or not(person.is_admin or person.permissions->>'products'='true') then raise exception 'لا تملك صلاحية تعريف المواد' using errcode='42501';end if;
  if jsonb_typeof(payload->'rows') is distinct from 'array' or jsonb_array_length(payload->'rows')>300 then raise exception 'بيانات المواد غير صحيحة';end if;
  for entry in select value from jsonb_array_elements(payload->'rows') loop
   if length(trim(coalesce(entry->>'name','')))=0 or length(trim(coalesce(entry->>'code','')))=0 or (entry->>'id')::bigint is null then raise exception 'أدخل اسم وكود المادة';end if;
   insert into public.products(id,code,name,brand_id,category,qty,cost) values((entry->>'id')::bigint,trim(entry->>'code'),trim(entry->>'name'),(entry->>'brand_id')::bigint,nullif(entry->>'category',''),0,0)
    on conflict(id) do update set code=excluded.code,name=excluded.name,brand_id=excluded.brand_id,category=excluded.category,updated_at=now();
  end loop;
  for entry in select value from jsonb_array_elements(coalesce(payload->'removed','[]')) loop
   select * into material from public.products where id=entry::text::bigint for update;
   if material.qty<>0 or exists(select 1 from public.transaction_items where product_id=material.id) then raise exception 'المادة لها رصيد أو وصولات؛ لا يمكن حذفها';end if;
   delete from public.products where id=material.id;
  end loop;result:='{}';
 elsif action in('warehouse_save','access_save') then
  if not(person.is_admin and person.user_type<>'warehouse') then raise exception 'للإدارة فقط' using errcode='42501';end if;
  if action='warehouse_save' then
   if length(trim(coalesce(payload->>'name','')))=0 or length(payload->>'name')>100 then raise exception 'أدخل اسم المخزن';end if;
   if payload->>'id' is null then
    insert into solar_private.warehouses(name,code) values(trim(payload->>'name'),'W-'||request_id::text) returning * into w;
   else
    select * into w from solar_private.warehouses where id=(payload->>'id')::bigint for update;
    if w.id is null then raise exception 'المخزن غير موجود';end if;
    if w.revision is distinct from (payload->>'revision')::bigint then raise exception 'تغيرت بيانات المخزن؛ حدّث الصفحة' using errcode='PT409';end if;
    if not coalesce((payload->>'active')::boolean,true) and(w.is_primary or exists(select 1 from solar_private.warehouse_stocks where warehouse_id=w.id and qty<>0) or exists(select 1 from public.transactions where warehouse_id=w.id and kind in('sale','system') and warehouse_status='pending')) then raise exception 'انقل الرصيد وأكمل الفواتير قبل إيقاف المخزن. لا يمكن إيقاف الرئيسي';end if;
    update solar_private.warehouses set name=trim(payload->>'name'),active=coalesce((payload->>'active')::boolean,true),revision=revision+1 where id=w.id returning * into w;
   end if;result:=to_jsonb(w);
  else
   select * into target_user from public.profiles where id=(payload->>'userId')::uuid and active and not is_admin and user_type<>'installer';
   if target_user.id is null then raise exception 'اختر مستخدماً فعالاً أو مسؤول مخزن';end if;
   select to_jsonb(a) into access_before from solar_private.warehouse_access a where user_id=target_user.id for update;
   if coalesce((access_before->>'revision')::bigint,0) is distinct from (payload->>'revision')::bigint then raise exception 'تغيرت صلاحيات المخازن؛ حدّث الصفحة' using errcode='PT409';end if;
   select coalesce(array_agg(distinct value::text::bigint),'{}') into ids from jsonb_array_elements(coalesce(payload->'ids','[]'));
   if exists(select 1 from unnest(ids) i where not exists(select 1 from solar_private.warehouses where id=i and active)) then raise exception 'اختر مخازن فعالة';end if;
   insert into solar_private.warehouse_access(user_id,all_warehouses,warehouse_ids,can_transfer,revision,updated_by) values(target_user.id,coalesce((payload->>'all')::boolean,false),ids,coalesce((payload->>'canTransfer')::boolean,false),1,person.id)
    on conflict(user_id) do update set all_warehouses=excluded.all_warehouses,warehouse_ids=excluded.warehouse_ids,can_transfer=excluded.can_transfer,revision=solar_private.warehouse_access.revision+1,updated_by=person.id,updated_at=now();
   select to_jsonb(a) into result from solar_private.warehouse_access a where user_id=target_user.id;
   insert into solar_private.warehouse_access_audit(actor_id,user_id,before_value,after_value) values(person.id,target_user.id,access_before,result);
   -- Invalidate already queued pushes outside the newly allowed locations.
   update solar_private.push_deliveries d set status='failed',last_status=403 from public.solar_notifications n join public.transactions t on t.id=n.job_id where d.notification_id=n.id and n.user_id=target_user.id and target_user.user_type='warehouse' and not solar_private.warehouse_access_allowed(target_user.id,t.warehouse_id) and d.status='pending';
  end if;
 elsif action='transfer' then
  location:=(payload->>'fromId')::bigint;dest:=(payload->>'toId')::bigint;
  if location is null or dest is null or location=dest then raise exception 'اختر مخزن المصدر والوجهة المختلفين';end if;
  if not((person.is_admin and person.user_type<>'warehouse') or exists(select 1 from solar_private.warehouse_access where user_id=person.id and can_transfer)) or not solar_private.warehouse_access_allowed(person.id,location) or not solar_private.warehouse_access_allowed(person.id,dest) then raise exception 'النقل يحتاج صلاحية المخزنين وصلاحية النقل' using errcode='42501';end if;
  if(select count(*) from solar_private.warehouses where id in(location,dest) and active)<>2 then raise exception 'اختر مخازن فعالة';end if;
  if jsonb_typeof(payload->'items') is distinct from 'array' or jsonb_array_length(payload->'items') not between 1 and 300 or length(coalesce(payload->>'note',''))>2000 then raise exception 'أضف مواد النقل بصورة صحيحة';end if;
  if(select count(*) from jsonb_array_elements(payload->'items'))<>(select count(distinct value->>'productId') from jsonb_array_elements(payload->'items')) then raise exception 'مادة مكررة في النقل';end if;
  perform 1 from public.products where id in(select (value->>'productId')::bigint from jsonb_array_elements(payload->'items')) order by id for update;
  for entry in select value from jsonb_array_elements(payload->'items') loop
   select * into material from public.products where id=(entry->>'productId')::bigint;
   amount:=(entry->>'qty')::numeric;
   if material.id is null or amount is null or not(amount>0 and amount<=1000000000) or amount<>round(amount,3) then raise exception 'أدخل كميات نقل صحيحة';end if;
   select coalesce(qty,0),revision into available,revision_value from solar_private.warehouse_stocks where warehouse_id=location and product_id=material.id;
   if coalesce(revision_value,0) is distinct from (entry->>'revision')::bigint then raise exception 'تغير رصيد مادة النقل؛ حدّث الرصيد وراجع الكميات' using errcode='PT409';end if;
   perform solar_private.change_warehouse_stock(location,material.id,-amount);perform solar_private.change_warehouse_stock(dest,material.id,amount);
   update public.products set costing_revision=costing_revision+1 where id=material.id;
   snapshots:=snapshots||jsonb_build_array(jsonb_build_object('productId',material.id,'code',material.code,'name',material.name,'brand',(select name from public.brands where id=material.brand_id),'category',material.category,'qty',amount,'unitCost',material.cost,'costBasis',material.cost_basis));
  end loop;
  insert into solar_private.stock_transfers(id,from_id,to_id,from_name,to_name,items,note,actor_id,actor_name) values(request_id,location,dest,(select name from solar_private.warehouses where id=location),(select name from solar_private.warehouses where id=dest),snapshots,coalesce(payload->>'note',''),person.id,coalesce(person.display_name,person.username)) returning * into transfer;
  result:=jsonb_build_object('id',transfer.id,'receiptNo',transfer.receipt_no);
 else
  if not(person.is_admin and person.user_type<>'warehouse') then raise exception 'إلغاء النقل للإدارة فقط' using errcode='42501';end if;
  select * into transfer from solar_private.stock_transfers where id=(payload->>'id')::uuid for update;
  if transfer.id is null or transfer.status<>'posted' then raise exception 'النقل غير موجود أو ملغى' using errcode='PT409';end if;
  perform 1 from public.products where id in(select (value->>'productId')::bigint from jsonb_array_elements(transfer.items)) order by id for update;
  for entry in select value from jsonb_array_elements(transfer.items) loop
   if not exists(select 1 from public.products where id=(entry->>'productId')::bigint) then raise exception 'لا يمكن إلغاء النقل بعد حذف إحدى مواده';end if;
   perform solar_private.change_warehouse_stock(transfer.to_id,(entry->>'productId')::bigint,-(entry->>'qty')::numeric);
   perform solar_private.change_warehouse_stock(transfer.from_id,(entry->>'productId')::bigint,(entry->>'qty')::numeric);
   update public.products set costing_revision=costing_revision+1 where id=(entry->>'productId')::bigint;
  end loop;
  update solar_private.stock_transfers set status='reversed',reversed_at=now(),reversed_by=person.id where id=transfer.id;
  result:=jsonb_build_object('id',transfer.id,'receiptNo',transfer.receipt_no,'status','reversed');
 end if;
 insert into solar_private.inventory_requests(id,actor_id,action,payload,result) values(request_id,person.id,action,payload,result);
 return result;
end$$;
create function public.solar_inventory(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select solar_private.inventory(action,request_id,payload)$$;
revoke all on function public.solar_inventory(text,uuid,jsonb),solar_private.inventory(text,uuid,jsonb) from public,anon;
grant execute on function public.solar_inventory(text,uuid,jsonb),solar_private.inventory(text,uuid,jsonb) to authenticated;
create index stock_adjustments_warehouse_idx on solar_private.stock_adjustments(warehouse_id);
update solar_private.stock_adjustments set warehouse_id=solar_private.primary_warehouse();
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) select solar_private.primary_warehouse(),id,qty from public.products;

create function solar_private.change_warehouse_stock(location bigint, material bigint, delta numeric) returns void language plpgsql security definer set search_path='' as $$
begin
 if material is null or delta=0 then return;end if;
 insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values(location,material,0) on conflict do nothing;
 update solar_private.warehouse_stocks set qty=qty+delta,revision=revision+1 where warehouse_id=location and product_id=material and qty+delta>=0;
 if not found then raise exception 'الكمية المتوفرة في المخزن المحدد لا تكفي. اختر مخزناً آخر أو انقل المادة إليه أولاً' using errcode='PT409';end if;
end$$;
create function solar_private.inventory_product_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
  insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values(solar_private.primary_warehouse(),new.id,new.qty);
  return new;
 end if;
 return old;
end$$;
create trigger solar_inventory_product_created after insert on public.products for each row execute function solar_private.inventory_product_guard();
create function solar_private.inventory_invoice_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare location bigint; item record;begin
 if current_setting('solar.reset_inventory',true)='true' then if tg_op='DELETE' then return old;end if;return new;end if;
 if tg_op='DELETE' then
  if old.kind in('sale','system','purchase') then
   for item in select product_id,sum(qty) qty from public.transaction_items where transaction_id=old.id group by product_id loop
    perform solar_private.change_warehouse_stock(old.warehouse_id,item.product_id,item.qty*case when old.kind='purchase' then -1 else 1 end);
   end loop;
  end if;return old;
 end if;
 if new.kind not in('sale','system','purchase') then
  if new.warehouse_id is not null then raise exception 'المخزن يخص فواتير المواد فقط';end if;return new;
 end if;
 if tg_op='UPDATE' then
  if new.warehouse_id is distinct from old.warehouse_id or new.warehouse_name is distinct from old.warehouse_name then raise exception 'مخزن الفاتورة المثبت لا يتغير بالتعديل؛ استخدم نقل المواد أو أعد إصدار الفاتورة' using errcode='42501';end if;
 else
  location:=coalesce(new.warehouse_id,nullif(current_setting('solar.warehouse_id',true),'')::bigint,solar_private.primary_warehouse());
  if auth.uid() is not null and not solar_private.warehouse_access_allowed(auth.uid(),location) then raise exception 'لا تملك صلاحية هذا المخزن' using errcode='42501';end if;
  select id,name into new.warehouse_id,new.warehouse_name from solar_private.warehouses where id=location and active;
  if new.warehouse_id is null then raise exception 'اختر مخزناً فعالاً';end if;
 end if;return new;
end$$;
create trigger solar_warehouse_location before insert or update or delete on public.transactions for each row execute function solar_private.inventory_invoice_guard();
create function solar_private.inventory_items_post() returns trigger language plpgsql security definer set search_path='' as $$
declare t public.transactions; old_delta numeric:=0;new_delta numeric:=0;begin
 if current_setting('solar.reset_inventory',true)='true' then if tg_op='DELETE' then return old;end if;return new;end if;
 if tg_op<>'INSERT' then
  select * into t from public.transactions where id=old.transaction_id;
  if t.kind in('purchase','sale','system') then old_delta:=old.qty*case when t.kind='purchase' then 1 else -1 end;end if;
 end if;
 if tg_op='UPDATE' and new.transaction_id=old.transaction_id and new.product_id=old.product_id then
  new_delta:=new.qty*case when t.kind='purchase' then 1 when t.kind in('sale','system') then -1 else 0 end;
  perform solar_private.change_warehouse_stock(t.warehouse_id,new.product_id,new_delta-old_delta);
 else
  if old_delta<>0 then perform solar_private.change_warehouse_stock(t.warehouse_id,old.product_id,-old_delta);end if;
  if tg_op<>'DELETE' then
   select * into t from public.transactions where id=new.transaction_id;
   if t.kind in('purchase','sale','system') then perform solar_private.change_warehouse_stock(t.warehouse_id,new.product_id,new.qty*case when t.kind='purchase' then 1 else -1 end);end if;
  end if;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end$$;
create trigger solar_inventory_items_post after insert or update or delete on public.transaction_items for each row execute function solar_private.inventory_items_post();
create function solar_private.inventory_consistency() returns trigger language plpgsql security definer set search_path='' as $$
declare material bigint;actual numeric;expected numeric;begin
 if tg_table_name='products' then material:=new.id;else material:=coalesce(new.product_id,old.product_id);end if;
 select qty into expected from public.products where id=material;
 if not found then return null;end if;
 select coalesce(sum(qty),0) into actual from solar_private.warehouse_stocks where product_id=material;
 if actual<>expected then raise exception 'رصيد المخازن لا يطابق الرصيد الكلي؛ لم تُحفظ العملية' using errcode='23514';end if;return null;
end$$;
create constraint trigger solar_inventory_total_check after insert or update or delete on solar_private.warehouse_stocks deferrable initially deferred for each row execute function solar_private.inventory_consistency();
create constraint trigger solar_product_total_check after insert or update on public.products deferrable initially deferred for each row execute function solar_private.inventory_consistency();

create function solar_private.inventory_catalog(location bigint default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;begin
 select * into p from public.profiles where id=auth.uid() and active and user_type<>'installer';
 if p.id is null then raise exception 'غير مسموح' using errcode='42501';end if;
 if location is not null and not solar_private.warehouse_access_allowed(p.id,location) then raise exception 'لا تملك صلاحية هذا المخزن' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'code',m.code,'name',m.name,'brand',b.name,'brand_id',m.brand_id,'brands',jsonb_build_object('name',b.name),'category',m.category,
 'stockRevision',coalesce((select revision from solar_private.warehouse_stocks where product_id=m.id and warehouse_id=location),0),'qty',coalesce((select sum(s.qty) from solar_private.warehouse_stocks s where s.product_id=m.id and(location is null or s.warehouse_id=location) and solar_private.warehouse_access_allowed(p.id,s.warehouse_id)),0))||
 case when p.user_type='warehouse' then '{}'::jsonb else jsonb_build_object('cost',m.cost,'cost_basis',m.cost_basis,'costing_revision',m.costing_revision,'companyQty',case when solar_private.can_read_global_stock() then m.qty end) end order by m.name,m.id),'[]') from public.products m left join public.brands b on b.id=m.brand_id);
end$$;

create function solar_private.inventory_movements(location bigint,product_filter bigint,customer_filter text,date_from date,date_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$
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
  select 'transfer:'||t.id||':'||d.direction||':'||line.ordinality,(line.value->>'productId')::bigint,line.value->>'name',line.value->>'brand',line.value->>'category',t.receipt_no,t.receipt_no,case when d.direction=1 then 'transfer_in' else 'transfer_out' end,
   case when d.direction=1 then t.from_name else t.to_name end,t.created_at,t.actor_id,(line.value->>'qty')::numeric*d.direction,case when d.direction=1 then t.to_id else t.from_id end,t.note
  from solar_private.stock_transfers t cross join lateral jsonb_array_elements(t.items) with ordinality line(value,ordinality) cross join (values(1),(-1)) d(direction)
  union all
  select 'transfer-reversal:'||t.id||':'||d.direction||':'||line.ordinality,(line.value->>'productId')::bigint,line.value->>'name',line.value->>'brand',line.value->>'category',t.receipt_no,t.receipt_no,case when d.direction=1 then 'transfer_return_in' else 'transfer_return_out' end,
   case when d.direction=1 then t.to_name else t.from_name end,t.reversed_at,t.reversed_by,(line.value->>'qty')::numeric*d.direction,case when d.direction=1 then t.from_id else t.to_id end,'إلغاء نقل: '||t.note
  from solar_private.stock_transfers t cross join lateral jsonb_array_elements(t.items) with ordinality line(value,ordinality) cross join (values(1),(-1)) d(direction) where t.status='reversed'
 ), balances as(
  select m.*,w.name warehouse_name,coalesce(s.qty,0)-sum(delta) over(partition by m.warehouse_id,m.product_id)+sum(delta) over(partition by m.warehouse_id,m.product_id order by m.created_at,m.invoice_id,m.id rows unbounded preceding) balance
  from movements m join solar_private.warehouses w on w.id=m.warehouse_id left join solar_private.warehouse_stocks s on s.warehouse_id=m.warehouse_id and s.product_id=m.product_id
  where solar_private.warehouse_access_allowed(auth.uid(),m.warehouse_id) and(location is null or m.warehouse_id=location)
 ) select coalesce(jsonb_agg(jsonb_build_object('id',id,'productId',product_id,'name',product_name,'brand',brand_name,'category',category,'receiptNo',receipt_no,'kind',kind,'party',party_name,'date',created_at,'note',note,'inQty',greatest(delta,0),'outQty',greatest(-delta,0),'balance',balance,'warehouseId',warehouse_id,'warehouseName',warehouse_name) order by created_at,invoice_id,id),'[]') into result from balances
 where (solar_private.role_name() in('admin','warehouse') or movement_owner=auth.uid()) and(product_filter is null or product_id=product_filter)
 and(coalesce(customer_filter,'')='' or(kind in('sale','system') and strpos(lower(coalesce(party_name,'')),lower(customer_filter))>0))
 and(date_from is null or created_at>=(date_from::timestamp at time zone 'Asia/Baghdad')) and(date_to is null or created_at<((date_to+1)::timestamp at time zone 'Asia/Baghdad'));
 return result;
end$$;

-- Integrations with the existing protected invoice and fulfillment flows.
CREATE OR REPLACE FUNCTION solar_private.invoice_save(request_id uuid, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;before_row public.transactions;after_row public.transactions;location bigint;begin
 perform pg_advisory_xact_lock(7311,1);
 if payload->>'invoiceId' is not null then
  select warehouse_id into location from public.transactions where id=(payload->>'invoiceId')::bigint;
  if payload->>'warehouseId' is not null and location is distinct from (payload->>'warehouseId')::bigint then raise exception 'لا يمكن تغيير مخزن الفاتورة المحفوظة' using errcode='42501';end if;
 else location:=coalesce(nullif(payload->>'warehouseId','')::bigint,solar_private.primary_warehouse());end if;
 if not solar_private.warehouse_access_allowed(auth.uid(),location) then raise exception 'لا تملك صلاحية مخزن الفاتورة' using errcode='42501';end if;
 perform set_config('solar.warehouse_id',location::text,true);
 if payload->>'kind'='sale' and payload->>'invoiceId' is not null then select * into before_row from public.transactions where id=(payload->>'invoiceId')::bigint;end if;
 if payload->>'kind'='purchase' then perform set_config('solar.fx_context',case when payload ? 'marketRate' then payload::text else '{}' end,true);end if;
 result:=solar_private.invoice_save_v333(request_id,payload);
 perform set_config('solar.fx_context','',true);perform set_config('solar.warehouse_id','',true);
 if before_row.id is not null then
  select * into after_row from public.transactions where id=before_row.id;
  if before_row.cash is distinct from after_row.cash then
   insert into solar_private.receipt_change_audit(request_id,actor_id,transaction_id,action,before_row,after_row) values(request_id,auth.uid(),before_row.id,'sale_payment_mode',to_jsonb(before_row),to_jsonb(after_row));
  end if;
 end if;
 return result;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.invoice_save_v333(request_id uuid, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_variable
declare p public.profiles; old_invoice public.transactions; invoice public.transactions;
 cached solar_private.invoice_requests; product public.products; old_item public.transaction_items;
 line jsonb; computed jsonb:='[]'::jsonb; snapshots jsonb:='[]'::jsonb; before_stock jsonb;
 kind text; currency text; mode text; invoice_id bigint; item_id bigint; party_id bigint; owner_id uuid;
 rate numeric; default_rate numeric; source_sum numeric:=0; subtotal numeric:=0; expenses numeric; total numeric; cost numeric:=0;
 qty numeric; price numeric; unit_cost numeric; landed numeric; remaining_qty numeric; remaining_cost numeric;
 previous_qty numeric; previous_value numeric; next_qty numeric; next_cost numeric; product_qty numeric; product_cost numeric;
 new_basis jsonb; result jsonb; economic_change boolean:=true; existing boolean:=false; cash boolean;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') then raise exception 'لا توجد صلاحية لحفظ الفاتورة' using errcode='42501';end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب حفظ غير صحيح';end if;
 kind:=payload->>'kind';currency:=coalesce(payload->>'sourceCurrency','IQD');mode:=coalesce(payload->>'mode','cash');
 if kind not in ('purchase','sale','system') or not(p.is_admin or coalesce(p.permissions->>kind,'false')='true') then raise exception 'لا توجد صلاحية لهذا النوع من الفواتير' using errcode='42501';end if;
 if currency not in ('IQD','USD') or (kind<>'purchase' and currency<>'IQD') or mode not in ('cash','credit') then raise exception 'البيع بالدينار فقط؛ تحقق من العملة وطريقة الدفع';end if;
 if jsonb_typeof(payload->'items') is distinct from 'array' or jsonb_array_length(payload->'items') not between 1 and 500 then raise exception 'أضف مواد صحيحة للفاتورة';end if;
 if length(coalesce(payload->>'notes',''))>4000 then raise exception 'الملاحظات طويلة جداً';end if;
 expenses:=coalesce((payload->>'expenses')::numeric,0); if kind='system' and nullif(payload->>'invoiceId','') is null and expenses<>0 then raise exception 'مصاريف التنصيب تعتمد كاملة بعد التجهيز عند إغلاق الملف';end if;
 if expenses::text in ('NaN','Infinity','-Infinity') or expenses<0 or expenses>1000000000000 then raise exception 'مصاريف غير صحيحة بالدينار';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into cached from solar_private.invoice_requests r where r.request_id=invoice_save_v333.request_id;
 if cached.request_id is not null then
  if cached.user_id<>p.id or cached.payload is distinct from payload then raise exception 'معرّف الطلب مستخدم لبيانات أخرى' using errcode='42501';end if;
  if not exists(select 1 from public.transactions t where t.id=(cached.result->>'id')::bigint) then raise exception 'الفاتورة حذفت أو صفّرت؛ حدّث البيانات' using errcode='PT409';end if;
  return cached.result;
 end if;
 invoice_id:=nullif(payload->>'invoiceId','')::bigint;
 if invoice_id is not null then
  select * into old_invoice from public.transactions where id=invoice_id for update;
  if old_invoice.id is null or not solar_private.can_access_invoice(old_invoice.created_by,false) or old_invoice.kind<>kind or (not p.is_admin and coalesce(old_invoice.cashbox_user_id,old_invoice.created_by) is distinct from p.id) then raise exception 'الفاتورة غير متاحة لحسابك' using errcode='42501';end if;
  if old_invoice.pricing_revision is distinct from (payload->>'expectedRevision')::bigint then raise exception 'تغيرت الفاتورة؛ افتح التعديل مجدداً' using errcode='PT409';end if;
  if kind='system' then raise exception 'استخدم متابعة التنصيب لتعديل المنظومة';end if;
  if kind<>'sale' and old_invoice.cash is distinct from (mode='cash') then raise exception 'لا يمكن تغيير طريقة دفع الفاتورة المحفوظة';end if;
  existing:=true;owner_id:=coalesce(old_invoice.cashbox_user_id,old_invoice.created_by);
 else
  -- Integer ID allocation is serialized with the existing cash/stock lock.
  invoice_id:=greatest((extract(epoch from clock_timestamp())*1000)::bigint,coalesce((select max(t.id)+1 from public.transactions t),1));
  owner_id:=p.id;
 end if;
 if currency='USD' then
  rate:=(payload->>'exchangeRate')::numeric;
  if rate is null or rate::text in ('NaN','Infinity','-Infinity') or rate<=0 or rate>1000000 then raise exception 'سعر صرف غير صحيح';end if;
  select s.rate into default_rate from solar_private.exchange_settings s where s.id;
  if not(p.is_admin or coalesce(p.permissions->>'exchangeRateEdit','false')='true') and rate is distinct from default_rate
   and not(existing and old_invoice.source_currency='USD' and old_invoice.exchange_rate=rate) then raise exception 'تغيير صرف الفاتورة يحتاج صلاحية تعديل سعر الصرف' using errcode='42501';end if;
 else rate:=1;end if;
 if exists(select 1 from jsonb_array_elements(payload->'items') x group by x->>'id' having count(*)>1) then raise exception 'المادة مكررة في الفاتورة';end if;
 for line in select value from jsonb_array_elements(payload->'items') loop
  if jsonb_typeof(line) is distinct from 'object' or jsonb_typeof(line->'id') is distinct from 'number' or jsonb_typeof(line->'qty') is distinct from 'number' or jsonb_typeof(line->'price') is distinct from 'number' then raise exception 'مواد الفاتورة غير صحيحة';end if;
  qty:=(line->>'qty')::numeric;price:=(line->>'price')::numeric;
  if qty::text in ('NaN','Infinity','-Infinity') or price::text in ('NaN','Infinity','-Infinity') or qty<=0 or qty>100000000 or price<0 or price>1000000000000 then raise exception 'كمية أو سعر غير صحيح';end if;
  source_sum:=source_sum+qty*price;
 end loop;
 if source_sum=0 and expenses>0 and kind='purchase' then raise exception 'لا يمكن توزيع مصاريف على مواد مجموع أسعارها صفر';end if;
 subtotal:=round(source_sum*rate,2);total:=subtotal+expenses;
 if kind='system' then
  total:=(payload->>'total')::numeric;subtotal:=total;
  if total is null or total::text in ('NaN','Infinity','-Infinity') or total<=0 or total>1000000000000 then raise exception 'سعر بيع منظومة غير صحيح';end if;
  if coalesce(trim(payload->>'customerAddress'),'')='' or not exists(select 1 from public.profiles x where x.id=(payload->>'installerId')::uuid and x.active and x.user_type='installer') then raise exception 'اختر مهندساً فعالاً واكتب عنوان التنصيب';end if;
  if (nullif(payload->>'installDate','') is null) is distinct from (nullif(payload->>'installTime','') is null) then raise exception 'حدد يوم وساعة الموعد معاً';end if;
 end if;
 party_id:=null;
 if coalesce(payload->>'party','')<>'' then
  if kind='purchase' then
   select id into party_id from public.suppliers where name=payload->>'party' and active order by id limit 1;
  else
   select c.id into party_id from public.customers c where c.name=payload->>'party' and (p.is_admin or c.owner_id=p.id) order by c.id limit 1;
  end if;
  if party_id is null then raise exception 'اختر طرفاً موجوداً ضمن صلاحياتك' using errcode='42501';end if;
 elsif mode='credit' or kind='system' then raise exception 'اختر العميل أو المورد';end if;
 cash:=mode='cash' and kind<>'system';
 if cash and kind='purchase' and coalesce(payload->>'cashCurrency','IQD')='IQD' and (total-case when existing and old_invoice.cash and old_invoice.cash_currency='IQD' then old_invoice.total else 0 end)>solar_private.cash_balance(owner_id) then raise exception 'رصيد قاصة صاحب الفاتورة غير كافٍ' using errcode='P0002';end if;
 if existing and kind='sale' and (case when old_invoice.cash then old_invoice.total else 0 end)-(case when cash then total else 0 end)>solar_private.cash_balance(owner_id) then raise exception 'الرصيد لا يكفي لتخفيض البيع النقدي' using errcode='P0002';end if;
 if existing and kind='purchase' then
  economic_change:=old_invoice.source_currency<>currency or old_invoice.exchange_rate<>rate or old_invoice.expenses<>expenses or
   (select coalesce(jsonb_agg(jsonb_build_object('id',i.product_id,'qty',i.qty,'price',coalesce(i.source_price,i.price)) order by i.product_id),'[]'::jsonb) from public.transaction_items i where i.transaction_id=invoice_id)
   is distinct from (select jsonb_agg(jsonb_build_object('id',(x->>'id')::bigint,'qty',(x->>'qty')::numeric,'price',(x->>'price')::numeric) order by (x->>'id')::bigint) from jsonb_array_elements(payload->'items') x);
 end if;
 -- Lock affected products in ID order. No cost supplied by the client is used.
 for product in select x.* from public.products x where x.id in (
  select (v->>'id')::bigint from jsonb_array_elements(payload->'items') v
  union select i.product_id from public.transaction_items i where existing and i.transaction_id=invoice_id
 ) order by x.id for update loop
  previous_qty:=0;previous_value:=0;
  if existing then select coalesce(sum(i.qty),0),coalesce(sum(i.qty*case when old_invoice.kind='purchase' then case when i.landed_cost>0 then i.landed_cost else i.price end else i.cost end),0) into previous_qty,previous_value from public.transaction_items i where i.transaction_id=invoice_id and i.product_id=product.id;end if;
  product_qty:=product.qty;product_cost:=product.cost;new_basis:=null;before_stock:=null;
  if kind='purchase' then
   if existing and economic_change and previous_qty>0 then
    if old_invoice.fx_pricing then
     select v into before_stock from jsonb_array_elements(old_invoice.purchase_stock) v where (v->>'id')::bigint=product.id;
     if before_stock is null or product.costing_revision is distinct from (before_stock->>'afterRevision')::bigint then raise exception 'حدثت حركة على المادة بعد الشراء. لا يمكن تغيير كلفتها التاريخية؛ استخدم تسوية أو فاتورة تصحيح' using errcode='PT409';end if;
     product_qty:=(before_stock->>'qty')::numeric;product_cost:=(before_stock->>'cost')::numeric;
    else
     if exists(select 1 from public.transaction_items i join public.transactions t on t.id=i.transaction_id where i.product_id=product.id and t.id<>invoice_id and (t.created_at,t.id)>(old_invoice.created_at,old_invoice.id) and t.kind in ('purchase','sale','system')) then raise exception 'حدثت حركة لاحقة؛ لا يمكن إعادة احتساب كلفة شراء قديم' using errcode='PT409';end if;
     product_qty:=product.qty-previous_qty;
     if product_qty<0 then raise exception 'لا يمكن تعديل شراء استُهلكت كميته';end if;
     if product_qty>0 then product_cost:=(product.qty*product.cost-previous_value)/product_qty;end if;
     if product_cost<0 then raise exception 'تعذر استعادة الكلفة السابقة؛ استخدم تسوية محاسبية';end if;
    end if;
   end if;
  else product_qty:=product.qty+previous_qty;end if;
  select v into line from jsonb_array_elements(payload->'items') v where (v->>'id')::bigint=product.id;
  if existing and kind='sale' and previous_qty>0 and product.cost is distinct from previous_value/previous_qty and coalesce((line->>'qty')::numeric,0)<>previous_qty then raise exception 'تغيرت كلفة المخزون بعد البيع. عدّل السعر فقط أو سجّل فاتورة تصحيح للكميات' using errcode='PT409';end if;
  if line is null then
   if kind='purchase' then next_qty:=product_qty;next_cost:=product_cost;else next_qty:=product_qty;next_cost:=product.cost;end if;
  else
   qty:=(line->>'qty')::numeric;price:=(line->>'price')::numeric;
   if kind='purchase' then
    landed:=round(price*rate+case when source_sum>0 then expenses*price/source_sum else 0 end,6);
    unit_cost:=landed;
    new_basis:=jsonb_build_object('currency',currency,'rate',rate,'sourcePrice',price,'invoiceId',invoice_id);
    if not existing or economic_change then
     next_qty:=product_qty+qty;next_cost:=round((product_qty*product_cost+qty*landed)/next_qty,6);
     snapshots:=snapshots||jsonb_build_array(jsonb_build_object('id',product.id,'qty',product_qty,'cost',product_cost,'basis',case when before_stock is not null then before_stock->'basis' else product.cost_basis end,'afterRevision',product.costing_revision+case when (next_qty,next_cost) is distinct from (product.qty,product.cost) then 1 else 0 end));
    else next_qty:=product.qty;next_cost:=product.cost;end if;
   else
    if qty>product_qty then raise exception 'الكمية غير كافية للمادة: %',product.name;end if;
    select * into old_item from public.transaction_items i where existing and i.transaction_id=invoice_id and i.product_id=product.id order by i.id limit 1;
    unit_cost:=case when old_item.id is not null then old_item.cost else product.cost end;
    new_basis:=case when old_item.id is not null then old_item.cost_basis else product.cost_basis end;
    landed:=0;next_qty:=product_qty-qty;next_cost:=product.cost;
   end if;
   cost:=cost+qty*unit_cost;
   computed:=computed||jsonb_build_array(jsonb_build_object('id',product.id,'name',product.name,'brand',(select b.name from public.brands b where b.id=product.brand_id),'category',product.category,'qty',qty,'price',case when kind='system' then 0 else round(price*rate,6) end,'sourcePrice',case when kind='purchase' then price else null end,'cost',unit_cost,'landedCost',landed,'costBasis',new_basis));
  end if;
  if kind<>'purchase' or not existing or economic_change then
   update public.products set qty=next_qty,cost=next_cost,cost_basis=case when kind='purchase' then case when line is null and before_stock is not null then before_stock->'basis' else jsonb_build_object('method','weighted-average','lastPurchase',new_basis,'unitCost',next_cost) end else case when product.cost_basis='{}'::jsonb then jsonb_build_object('method','legacy-iqd','unitCost',next_cost) else product.cost_basis end end where id=product.id;
  end if;
 end loop;
 if jsonb_array_length(computed)<>jsonb_array_length(payload->'items') then raise exception 'إحدى المواد غير موجودة؛ حدّث البيانات';end if;
 cost:=round(cost,2);
 if existing then
  update public.transactions set party_name=nullif(payload->>'party',''),party_id=party_id,party_type=case when kind='purchase' then 'supplier' else 'customer' end,
   cash=cash,payment_mode=mode,subtotal=subtotal,total=total,expenses=expenses,cost=cost,profit=case when kind='sale' then subtotal-cost when kind='system' then total-cost-expenses else 0 end,
   notes=nullif(payload->>'notes',''),source_currency=currency,exchange_rate=rate,source_subtotal=source_sum,fx_pricing=true,
   purchase_stock=case when kind='purchase' and economic_change then snapshots else purchase_stock end where id=invoice_id returning * into invoice;
 else
  insert into public.transactions(id,kind,party_type,party_id,party_name,payment_mode,subtotal,expenses,total,cost,profit,notes,cash,created_by,cashbox_user_id,
   source_currency,exchange_rate,source_subtotal,fx_pricing,purchase_stock,installer_id,install_date,install_time,customer_address,customer_phone,installation_status)
  values(invoice_id,kind,case when kind='purchase' then 'supplier' else 'customer' end,party_id,nullif(payload->>'party',''),mode,subtotal,expenses,total,cost,
   case when kind='sale' then subtotal-cost when kind='system' then total-cost-expenses else 0 end,nullif(payload->>'notes',''),cash,p.id,owner_id,
   currency,rate,source_sum,true,snapshots,case when kind='system' then (payload->>'installerId')::uuid end,
   nullif(payload->>'installDate','')::date,nullif(payload->>'installTime','')::time,nullif(payload->>'customerAddress',''),nullif(payload->>'customerPhone',''),case when kind='system' then 'pending' else 'none' end)
  returning * into invoice;
 end if;
 if not(existing and kind='purchase' and not economic_change) then
  delete from public.transaction_items where transaction_id=invoice_id;
  for line in select value from jsonb_array_elements(computed) loop
   insert into public.transaction_items(transaction_id,product_id,product_name,brand_name,category,qty,price,cost,landed_cost,source_price,cost_basis)
   values(invoice_id,(line->>'id')::bigint,line->>'name',line->>'brand',line->>'category',(line->>'qty')::numeric,(line->>'price')::numeric,(line->>'cost')::numeric,(line->>'landedCost')::numeric,(line->>'sourcePrice')::numeric,line->'costBasis');
  end loop;
 end if;
 select * into invoice from public.transactions where id=invoice_id;
 result:=jsonb_build_object('id',invoice.id,'receiptNo',invoice.receipt_no,'pricingRevision',invoice.pricing_revision,'total',invoice.total,'cost',invoice.cost,'profit',invoice.profit,'invoiceAccount',invoice.invoice_account,'warehouseQrToken',invoice.warehouse_qr_token,'warehouseId',invoice.warehouse_id,'warehouseName',invoice.warehouse_name);
 if kind in ('sale','system') then if existing and payload ? 'warranty' and coalesce((payload->>'expectedWarrantyRevision')::bigint,-1)<>invoice.warranty_revision then raise exception 'تغيّر ضمان الفاتورة؛ افتح التعديل مجدداً' using errcode='PT409';end if;result:=result||solar_private.warranty_apply(invoice_id,payload->'warranty');end if; insert into solar_private.invoice_requests(request_id,user_id,payload,result) values(request_id,p.id,payload,result);
 return result;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.warehouse_orders(search_text text DEFAULT ''::text, state text DEFAULT 'pending'::text, page_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;q text:=coalesce(search_text,'');stage text:=coalesce(state,'pending');begin
 if auth.uid() is null or not solar_private.warehouse_allowed() then raise exception 'Not permitted' using errcode='42501';end if;
 if stage not in('','pending','ready') or length(q)>200 then raise exception 'تصفية التجهيز غير صحيحة';end if;
 with matched as materialized(
  select t.* from public.transactions t where t.kind in('sale','system') and solar_private.warehouse_access_allowed(auth.uid(),t.warehouse_id) and(nullif(current_setting('solar.warehouse_filter',true),'') is null or t.warehouse_id=nullif(current_setting('solar.warehouse_filter',true),'')::bigint) and((select solar_private.role_name()) in('admin','warehouse') or t.created_by=(select auth.uid())) and(q='' or q='@id:'||t.id::text or strpos(solar_private.customer_name_key(coalesce(t.party_name,'')||' '||t.receipt_no::text),solar_private.customer_name_key(q))>0)
 ), filtered as(select * from matched where stage='' or warehouse_status=stage),
 paged as(select * from filtered order by created_at desc,id desc limit 30 offset greatest(0,least(coalesce(page_offset,0),1000000)))
 select jsonb_build_object('count',(select count(*) from filtered),'statusCounts',jsonb_build_object('pending',(select count(*) from matched where warehouse_status='pending'),'ready',(select count(*) from matched where warehouse_status='ready'),'all',(select count(*) from matched)),
 'rows',coalesce((select jsonb_agg(jsonb_build_object('warehouseId',t.warehouse_id,'warehouseName',t.warehouse_name,'id',t.id,'receiptNo',t.receipt_no,'kind',t.kind,'party',t.party_name,'phone',t.customer_phone,'address',t.customer_address,'date',t.created_at,'status',t.warehouse_status,
 'warranty',t.warranty,'warehouseQrToken',t.warehouse_qr_token,'preparedAt',t.warehouse_prepared_at,'preparedBy',(select coalesce(display_name,username) from public.profiles where id=t.warehouse_prepared_by),'note',t.warehouse_note,'token',solar_private.warehouse_token(t.id),'canEdit',t.installation_status not in('in_progress','completed','closed'),
 'items',coalesce((select jsonb_agg(jsonb_build_object('lineId',i.id,'productId',i.product_id,'name',i.product_name,'brand',i.brand_name,'category',i.category,'qty',i.qty) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]')) order by t.created_at desc,t.id desc) from paged t),'[]')) into result;
 return result;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.warehouse_action(invoice_id bigint, expected_token text, action text, lines jsonb DEFAULT NULL::jsonb, note text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j public.transactions; before_items jsonb; after_items jsonb; entry jsonb; oldline public.transaction_items; prod public.products;
 newqty numeric; oldqty numeric; newtotal numeric; newcost numeric; wanted jsonb; id_value bigint;
begin
 if auth.uid() is null or not solar_private.warehouse_allowed() then raise exception 'Not permitted' using errcode='42501';end if;
 if action not in ('save','ready','reopen') then raise exception 'Invalid action';end if;
 perform pg_advisory_xact_lock(7311,1); select * into j from public.transactions where id=invoice_id and kind in ('sale','system') for update;
 if j.id is null or not solar_private.warehouse_access_allowed(auth.uid(),j.warehouse_id) or not solar_private.can_access_invoice(j.created_by,true) then raise exception 'الفاتورة غير متاحة' using errcode='42501';end if;
 if solar_private.warehouse_token(j.id) is distinct from expected_token then raise exception 'تغيّرت الفاتورة، حدّث الصفحة وحاول مجدداً' using errcode='PT409';end if;
 if length(coalesce(note,''))>2000 then raise exception 'الملاحظات طويلة';end if;
 select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]'::jsonb) into before_items from public.transaction_items i where transaction_id=j.id;
 if action='save' then
  if j.installation_status in ('in_progress','completed','closed') then raise exception 'بدأ تنفيذ المنظومة؛ راجع الإداري قبل تعديل موادها';end if;
  if jsonb_typeof(lines) is distinct from 'array' or jsonb_array_length(lines)=0 or jsonb_array_length(lines)>300 then raise exception 'أضف مادة واحدة على الأقل';end if;
  if exists(select 1 from jsonb_array_elements(lines) e where jsonb_typeof(e->'qty') is distinct from 'number' or (e->>'qty')::numeric<=0 or (e->>'qty')::numeric>1000000 or (e->>'qty')::numeric<>round((e->>'qty')::numeric,3)) then raise exception 'الكميات غير صحيحة';end if;
  if (select count(*) from jsonb_array_elements(lines) e where e->>'lineId' is not null)<>(select count(distinct e->>'lineId') from jsonb_array_elements(lines) e where e->>'lineId' is not null) then raise exception 'مادة مكررة';end if;
  -- Lock the union of old/new products in a stable order.
  perform 1 from public.products p where p.id in (select i.product_id from public.transaction_items i where i.transaction_id=j.id union select (e->>'productId')::bigint from jsonb_array_elements(lines) e) order by p.id for update;
  for entry in select value from jsonb_array_elements(lines) loop
   if entry->>'lineId' is not null then
    select * into oldline from public.transaction_items where id=(entry->>'lineId')::bigint and transaction_id=j.id;
    if oldline.id is null or oldline.product_id is distinct from (entry->>'productId')::bigint then raise exception 'مادة لا تخص هذه الفاتورة';end if;
   else
    if j.kind<>'system' then raise exception 'إضافة مادة جملة جديدة تحتاج الإداري لتحديد سعر البيع';end if;
    if not exists(select 1 from public.products where id=(entry->>'productId')::bigint) then raise exception 'المادة غير موجودة';end if;
   end if;
  end loop;
  for id_value in select product_id from public.transaction_items where transaction_id=j.id union select (e->>'productId')::bigint from jsonb_array_elements(lines) e loop
   select coalesce(sum(qty),0) into oldqty from public.transaction_items where transaction_id=j.id and product_id=id_value;
   select coalesce(sum((e->>'qty')::numeric),0) into newqty from jsonb_array_elements(lines) e where (e->>'productId')::bigint=id_value;
   update public.products set qty=qty+oldqty-newqty,updated_at=now() where id=id_value and qty+oldqty-newqty>=0;
   if not found then raise exception 'الكمية المتوفرة لا تكفي أو المادة غير متاحة';end if;
  end loop;
  delete from public.transaction_items i where transaction_id=j.id and not exists(select 1 from jsonb_array_elements(lines) e where (e->>'lineId')::bigint=i.id);
  for entry in select value from jsonb_array_elements(lines) loop
   if entry->>'lineId' is not null then update public.transaction_items set qty=(entry->>'qty')::numeric where id=(entry->>'lineId')::bigint and transaction_id=j.id;
   else
    select * into prod from public.products where id=(entry->>'productId')::bigint;
    insert into public.transaction_items(transaction_id,product_id,product_name,brand_name,category,qty,price,cost)
    values(j.id,prod.id,prod.name,(select name from public.brands where id=prod.brand_id),prod.category,(entry->>'qty')::numeric,0,prod.cost);
   end if;
  end loop;
  select coalesce(sum(qty*price),0),coalesce(sum(qty*cost),0) into newtotal,newcost from public.transaction_items where transaction_id=j.id;
  update public.transactions set subtotal=case when kind='sale' then newtotal else subtotal end,total=case when kind='sale' then newtotal+coalesce(expenses,0) else total end,
  cost=newcost,profit=case when kind='sale' then newtotal-newcost-coalesce(installation_expenses,0) else total-newcost-coalesce(expenses,0)-coalesce(installation_expenses,0) end,
  warehouse_status='pending',warehouse_prepared_at=null,warehouse_prepared_by=null,warehouse_note=coalesce(note,''),warehouse_revision=warehouse_revision+1 where id=j.id;
  perform solar_private.warehouse_notice(j.created_by,j.id,'warehouse_edited');
 elsif action='ready' then
  if j.warehouse_status<>'pending' then raise exception 'الفاتورة مجهزة مسبقاً';end if;
  if not exists(select 1 from public.transaction_items where transaction_id=j.id) then raise exception 'الفاتورة بدون مواد';end if;
  update public.transactions set warehouse_status='ready',warehouse_prepared_at=now(),warehouse_prepared_by=auth.uid(),warehouse_note=coalesce(note,''),warehouse_revision=warehouse_revision+1 where id=j.id;
 else
  if j.installation_status in ('in_progress','completed','closed') then raise exception 'بدأ تنفيذ المنظومة؛ لا يمكن إعادة التجهيز الآن';end if;
  if j.warehouse_status<>'ready' then raise exception 'الفاتورة بانتظار التجهيز أصلاً';end if;
  update public.transactions set warehouse_status='pending',warehouse_prepared_at=null,warehouse_prepared_by=null,warehouse_revision=warehouse_revision+1 where id=j.id;
 end if;
 select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]'::jsonb) into after_items from public.transaction_items i where transaction_id=j.id;
 insert into solar_private.warehouse_audit(invoice_id,actor_id,action,before_items,after_items) values(j.id,auth.uid(),action,before_items,after_items);
end $function$;

CREATE OR REPLACE FUNCTION solar_private.warehouse_statuses(invoice_ids bigint[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles;result jsonb;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type='installer' then raise exception 'Not permitted' using errcode='42501';end if;
 if coalesce(cardinality(invoice_ids),0)>500 then raise exception 'اطلب حالة 500 فاتورة كحد أقصى';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'status',t.warehouse_status,'preparedAt',t.warehouse_prepared_at,'revision',t.warehouse_revision)),'[]') into result from public.transactions t
 where t.id=any(invoice_ids) and t.kind in('sale','system') and(p.is_admin or(p.user_type='warehouse' and solar_private.warehouse_access_allowed(p.id,t.warehouse_id)) or(p.user_type<>'warehouse' and t.created_by=p.id));
 return result;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.notification_recipient_allowed(recipient uuid, invoice_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.profiles p where p.id=recipient and p.active and
 ((p.is_admin and p.user_type not in('installer','warehouse')) or
 exists(select 1 from public.transactions t where t.id=invoice_id and
  ((p.user_type='warehouse' and solar_private.warehouse_access_allowed(p.id,t.warehouse_id)) or(p.user_type='installer' and t.installer_id=p.id) or(p.user_type not in('installer','warehouse') and t.created_by=p.id))) or
 (p.user_type not in('installer','warehouse') and exists(select 1 from solar_private.deleted_sales d where d.invoice_id=notification_recipient_allowed.invoice_id and d.invoice->>'created_by'=p.id::text))))
$function$;

CREATE OR REPLACE FUNCTION solar_private.reconcile(action text, request_id uuid, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare p public.profiles; c public.customers; product public.products; prior solar_private.reconciliation_requests;
 result jsonb; rows jsonb; old_balance numeric; target numeric; delta numeric; movement_id bigint; adjustment_id bigint; owner uuid;location bigint;local_qty numeric;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') then raise exception 'غير مسموح' using errcode='42501';end if;
 if request_id is null or payload is null or action not in ('create_customer','customer_balance','stock_balance') or action is null then raise exception 'طلب غير صحيح';end if;
 if not(p.is_admin or (action='create_customer' and (coalesce(p.permissions->>'customers','false')='true' or coalesce(p.permissions->>'customerCreate','false')='true')) or
 (action='customer_balance' and coalesce(p.permissions->>'customerReconcile','false')='true' and coalesce(p.permissions->>'customerStatement','false')='true') or
 (action='stock_balance' and coalesce(p.permissions->>'stockAdjust','false')='true')) then raise exception 'لا تملك صلاحية هذه العملية' using errcode='42501';end if;
 -- Same lock as invoices, cash writes and reset: avoid a reconciliation racing a sale.
 perform pg_advisory_xact_lock(7311,1);
 select * into prior from solar_private.reconciliation_requests where id=request_id;
 if prior.id is not null then
  if prior.actor_id<>p.id or prior.action<>action or prior.payload<>payload then raise exception 'طلب مكرر ببيانات مختلفة' using errcode='PT409';end if;
  return prior.result;
 end if;
 if action='stock_balance' then
  location:=coalesce((payload->>'warehouseId')::bigint,solar_private.primary_warehouse());
  if not solar_private.warehouse_access_allowed(p.id,location) then raise exception 'لا تملك صلاحية هذا المخزن' using errcode='42501';end if;
  if not exists(select 1 from solar_private.warehouses where id=location and active) then raise exception 'اختر مخزناً فعالاً';end if;
  select * into product from public.products where id=(payload->>'productId')::bigint for update;
  if product.id is null then raise exception 'المادة غير موجودة';end if;
  select coalesce((select qty from solar_private.warehouse_stocks where warehouse_id=location and product_id=product.id),0) into local_qty;
  target:=(payload->>'actual')::numeric;
  if target is null or not(target between 0 and 1000000000) or round(target,3)<>target then raise exception 'أدخل كمية فعلية صحيحة';end if;
  if local_qty is distinct from (payload->>'expected')::numeric then raise exception 'تغيّر رصيد المادة. حدّث الرصيد ثم راجع الجرد' using errcode='PT409';end if;
  if length(trim(coalesce(payload->>'note','')))=0 then raise exception 'اكتب سبب التسوية';end if;
  insert into solar_private.stock_adjustments(product_id,old_qty,actual_qty,note,actor_id,warehouse_id)
  values(product.id,local_qty,target,left(payload->>'note',2000),p.id,location) returning id into adjustment_id;
  perform solar_private.change_warehouse_stock(location,product.id,target-local_qty);
  update public.products set qty=qty+target-local_qty where id=product.id;
  result:=jsonb_build_object('id',adjustment_id,'warehouseId',location,'previous',local_qty,'actual',target,'delta',target-local_qty);
 else
  if action='create_customer' then
   if payload->>'customerType' is null or payload->>'customerType' not in ('system','wholesale') then raise exception 'اختر زبون جملة أو مفرد';end if;
   if length(trim(coalesce(payload->>'name','')))=0 or (payload->>'id')::bigint is null then raise exception 'اكتب اسم العميل';end if;
   owner:=case when p.is_admin then coalesce(nullif(payload->>'ownerId','')::uuid,p.id) else p.id end;
   if not exists(select 1 from public.profiles where id=owner and active and user_type not in ('installer','warehouse')) then raise exception 'اختر مستخدماً مسؤولاً فعالاً';end if;
   insert into public.customers(id,name,phone,customer_type,owner_id)
   values((payload->>'id')::bigint,trim(payload->>'name'),payload->>'phone',payload->>'customerType',owner) returning * into c;
   old_balance:=0;target:=coalesce((payload->>'openingBalance')::numeric,0);
  else
   select * into c from public.customers where id=(payload->>'customerId')::bigint for update;
   if c.id is null or not(p.is_admin or coalesce(c.owner_id=p.id,false)) then raise exception 'لا تملك صلاحية هذا العميل' using errcode='42501';end if;
   rows:=solar_private.customer_ledger(c.id);
   if md5(rows::text) is distinct from payload->>'token' then raise exception 'تغير حساب العميل. حدّث الكشف ثم راجع المطابقة' using errcode='PT409';end if;
   select coalesce(sum((r->>'effect')::numeric),0) into old_balance from jsonb_array_elements(rows) r;
   select coalesce((select qty from solar_private.warehouse_stocks where warehouse_id=location and product_id=product.id),0) into local_qty;
  target:=(payload->>'actual')::numeric;
   if length(trim(coalesce(payload->>'note','')))=0 then raise exception 'اكتب ملاحظة المطابقة';end if;
  end if;
  if target is null or not(target between -1000000000000000 and 1000000000000000) or round(target,2)<>target then raise exception 'أدخل رصيداً صحيحاً';end if;
  delta:=target-old_balance;
  if action='customer_balance' or payload->>'openingBalance' is not null then
   movement_id:=floor(extract(epoch from clock_timestamp())*1000000)::bigint;
   while exists(select 1 from public.transactions where id=movement_id) loop movement_id:=movement_id+1;end loop;
   insert into public.transactions(id,kind,party_type,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,notes,created_at)
   values(movement_id,case when c.customer_type='system' then 'system_payment' else 'customer_payment' end,'customer',c.id,c.name,-delta,false,
    case action when 'create_customer' then 'opening_balance' else 'account_reconciliation' end,p.id,p.id,
    case action when 'create_customer' then 'رصيد افتتاحي' else 'مطابقة حساب: '||left(payload->>'note',2000) end||
    ' | الرصيد السابق: '||old_balance||' | الرصيد المعتمد: '||target,clock_timestamp());
  end if;
  result:=jsonb_build_object('customerId',c.id,'previous',old_balance,'actual',target,'delta',delta,'movementId',movement_id);
 end if;
 insert into solar_private.reconciliation_requests(id,actor_id,action,payload,result) values(request_id,p.id,action,payload,result);
 return result;
end $function$;

create or replace function solar_private.stock_quantities() returns jsonb language sql stable security definer set search_path='' as $$select solar_private.inventory('stock',null,'{}')->'products'$$;
create or replace function solar_private.stock_movements(product_filter bigint default null,customer_filter text default '',date_from date default null,date_to date default null) returns jsonb language sql stable security definer set search_path='' as $$select solar_private.inventory_movements(null,product_filter,customer_filter,date_from,date_to)$$;

CREATE OR REPLACE FUNCTION solar_private.reset_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare name text; rows jsonb; result jsonb='{}';begin
 -- This same allowlist governs backup, fingerprinting and the explicit wipe below.
 foreach name in array array['public.brands','public.customers','public.suppliers','public.products',
 'public.transactions','public.transaction_items','public.cash_ledger','public.solar_cash_entries',
 'public.solar_notifications','public.solar_quotes','public.solar_price_estimates','public.solar_estimate_specs',
 'solar_private.warehouses','solar_private.warehouse_access','solar_private.warehouse_stocks','solar_private.stock_transfers','solar_private.inventory_requests','solar_private.customer_changes','solar_private.stock_adjustments','solar_private.reconciliation_requests','solar_private.cash_transfers','solar_private.supplier_payment_requests','solar_private.supplier_fx_entries','solar_private.wallet_fx_entries','solar_private.fx_requests','solar_private.system_payment_requests','solar_private.finance_requests','solar_private.receipt_counters'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from %s t',name) into rows;
  result=result||jsonb_build_object(name,rows);
 end loop;
 return result;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.lock_reset_tables()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 perform pg_advisory_xact_lock(7311,1);
 lock table public.brands,public.customers,public.suppliers,public.products,
 public.transactions,public.transaction_items,public.cash_ledger,public.solar_cash_entries,
 public.solar_notifications,public.solar_quotes,public.solar_price_estimates,public.solar_estimate_specs,
 solar_private.stock_adjustments,solar_private.reconciliation_requests,solar_private.cash_transfers,solar_private.supplier_payment_requests,solar_private.supplier_fx_entries,solar_private.wallet_fx_entries,solar_private.fx_requests,solar_private.system_payment_requests,solar_private.finance_requests,solar_private.receipt_counters
 , solar_private.warehouses,solar_private.warehouse_access,solar_private.warehouse_stocks,solar_private.stock_transfers,solar_private.inventory_requests in share row exclusive mode;
end $function$;

CREATE OR REPLACE FUNCTION public.solar_execute_reset(actor_id uuid, request_id uuid, confirmation text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
 SET statement_timeout TO '30s'
AS $function$
declare request solar_private.reset_requests; snapshot jsonb; name text;begin
 if confirmation is distinct from 'تصفير بيانات عبدالرحمن سولار' then raise exception 'اكتب عبارة التأكيد كاملة';end if;
 if not exists(select 1 from public.profiles p where p.id=actor_id and p.active and p.is_admin and p.user_type not in ('installer','warehouse')) then raise exception 'للأدمن فقط' using errcode='42501';end if;
 select * into request from solar_private.reset_requests r where r.id=request_id and r.actor_id=solar_execute_reset.actor_id for update;
 if request.id is null or request.consumed_at is not null or request.expires_at<now() then raise exception 'انتهت صلاحية الطلب؛ جهّز معاينة جديدة';end if;
 perform solar_private.lock_reset_tables();
 snapshot=solar_private.reset_snapshot();
 if md5(snapshot::text)<>request.fingerprint then raise exception 'تغيرت البيانات بعد المعاينة؛ جهّز نسخة احتياطية ومعاينة جديدة قبل التصفير' using errcode='PT409';end if;
 -- Prevent stale devices from resurrecting deleted operational/master rows.
 foreach name in array array['brands','customers','suppliers','products','transactions'] loop
  execute format('insert into solar_private.reset_record_ids(table_name,record_id) select %L,id from public.%I on conflict do nothing',name,name);
 end loop;
 perform set_config('solar.reset_inventory','true',true);
 delete from solar_private.stock_transfers;delete from solar_private.inventory_requests;
 delete from public.cash_ledger;
 delete from public.solar_cash_entries;
 delete from public.solar_notifications;
 delete from solar_private.cash_transfers;
 delete from solar_private.supplier_payment_requests;
 delete from solar_private.supplier_fx_entries; delete from solar_private.wallet_fx_entries; delete from solar_private.fx_requests; delete from solar_private.system_payment_requests; delete from solar_private.finance_requests; delete from public.transactions; -- cascades its invoice lines, without stock rewrite.
 delete from public.transaction_items;
 delete from public.solar_quotes;
 delete from public.solar_price_estimates;
 delete from public.solar_estimate_specs;
 delete from solar_private.stock_adjustments; delete from solar_private.reconciliation_requests; delete from public.products;
 delete from public.brands;
 delete from public.customers;
 delete from public.suppliers;
 delete from solar_private.receipt_counters;
 perform set_config('solar.reset_inventory','',true);
 update solar_private.reset_requests set consumed_at=now() where id=request.id;
 -- Users, permissions, notification devices, audit records and ALL backups survive.
 return jsonb_build_object('ok',true,'backupId',request.backup_id,'resetAt',now());
end $function$;

revoke all on function public.solar_execute_reset(uuid,uuid,text) from public,anon,authenticated;grant execute on function public.solar_execute_reset(uuid,uuid,text) to service_role;
revoke all on function solar_private.change_warehouse_stock(bigint,bigint,numeric),solar_private.inventory_catalog(bigint),solar_private.inventory_movements(bigint,bigint,text,date,date),solar_private.inventory_product_guard(),solar_private.inventory_invoice_guard(),solar_private.inventory_items_post(),solar_private.inventory_consistency(),solar_private.inventory_raw_product_guard() from public,anon,authenticated;
-- Keep the assigned engineer's existing scope and add only the fulfillment label.
do $$declare definition text;begin
 definition:=pg_get_functiondef('solar_private.installation_jobs()'::regprocedure);
 if strpos(definition,'''warehouseStatus'',t.warehouse_status')=0 then raise exception 'Unexpected installation jobs definition';end if;
 execute replace(definition,'''warehouseStatus'',t.warehouse_status','''warehouseId'',t.warehouse_id,''warehouseName'',t.warehouse_name,''warehouseStatus'',t.warehouse_status');
end$$;
revoke all on function solar_private.reset_snapshot(),solar_private.lock_reset_tables() from public,anon,authenticated;
notify pgrst,'reload schema';
