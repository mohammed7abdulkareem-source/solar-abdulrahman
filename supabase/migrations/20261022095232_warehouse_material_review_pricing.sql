-- Quantity-only requests stay outside posted inventory/accounts until a financial
-- user prices the complete wholesale amendment through the canonical invoice save.
create table solar_private.warehouse_price_edits(
 invoice_id bigint primary key references public.transactions(id) on delete cascade,
 lines jsonb not null check(jsonb_typeof(lines)='array'),base_token text not null,
 actor_id uuid not null references public.profiles(id),updated_at timestamptz not null default now()
);
alter table solar_private.warehouse_price_edits enable row level security;
revoke all on solar_private.warehouse_price_edits from public,anon,authenticated;
create table solar_private.warehouse_price_requests(
 request_id uuid primary key,actor_id uuid not null,invoice_id bigint not null,
 payload jsonb not null,result jsonb not null,created_at timestamptz not null default now()
);
alter table solar_private.warehouse_price_requests enable row level security;
revoke all on solar_private.warehouse_price_requests from public,anon,authenticated;

alter function solar_private.warehouse_token(bigint) rename to warehouse_token_v364;
create function solar_private.warehouse_token(invoice_id bigint) returns text language sql stable set search_path='' as $$
 select md5(solar_private.warehouse_token_v364(invoice_id)||coalesce((select to_jsonb(e)::text from solar_private.warehouse_price_edits e where e.invoice_id=warehouse_token.invoice_id),''))
$$;
revoke all on function solar_private.warehouse_token(bigint),solar_private.warehouse_token_v364(bigint) from public,anon,authenticated;

alter function solar_private.warehouse_orders(text,text,integer) rename to warehouse_orders_v364;
create function solar_private.warehouse_orders(search_text text default '',state text default 'pending',page_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;begin
 result:=solar_private.warehouse_orders_v364(search_text,state,page_offset);
 return jsonb_set(result,'{rows}',coalesce((select jsonb_agg(x.value||case when e.invoice_id is null then jsonb_build_object('pricingPending',false) else
 jsonb_build_object('pricingPending',true,'bookedItems',x.value->'items','items',e.lines,'token',solar_private.warehouse_token(e.invoice_id)) end order by x.ordinality)
 from jsonb_array_elements(result->'rows') with ordinality x(value,ordinality) left join solar_private.warehouse_price_edits e on e.invoice_id=(x.value->>'id')::bigint),'[]'));
end$$;
revoke all on function solar_private.warehouse_orders_v364(text,text,integer),solar_private.warehouse_orders(text,text,integer) from public,anon,authenticated;
grant execute on function solar_private.warehouse_orders(text,text,integer) to authenticated;

alter function solar_private.warehouse_action(bigint,text,text,jsonb,text) rename to warehouse_action_v364;
create function solar_private.warehouse_action(invoice_id bigint,expected_token text,action text,lines jsonb default null,note text default '') returns void
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare t public.transactions;entry jsonb;original public.transaction_items;product public.products;safe_lines jsonb:='[]';before_items jsonb;u uuid;
 needed numeric;held numeric;available numeric;pid bigint;
begin
 if auth.uid() is null or not solar_private.warehouse_allowed() then raise exception 'غير مسموح' using errcode='42501';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into t from public.transactions where id=invoice_id and kind in('sale','system') for update;
 if t.id is null or not solar_private.warehouse_access_allowed(auth.uid(),t.warehouse_id) or not solar_private.can_access_invoice(t.created_by,true) then raise exception 'الفاتورة غير متاحة' using errcode='42501';end if;
 if solar_private.warehouse_token(t.id) is distinct from expected_token then raise exception 'تغيّرت الفاتورة، حمّل أحدث نسخة قبل الحفظ' using errcode='PT409';end if;
 if action='ready' and exists(select 1 from solar_private.warehouse_price_edits e where e.invoice_id=t.id) then raise exception 'المواد الجديدة بانتظار تسعير الإدارة قبل إكمال التجهيز';end if;
 if action='save' and t.kind='sale' and exists(select 1 from jsonb_array_elements(lines) e where e->>'lineId' is null) then
  if t.installation_status in('in_progress','completed','closed') then raise exception 'بدأ تنفيذ الفاتورة؛ لا يمكن تعديل المواد';end if;
  if jsonb_typeof(lines) is distinct from 'array' or jsonb_array_length(lines) not between 1 and 300 or length(coalesce(note,''))>2000 then raise exception 'اختر فقرات صحيحة وملاحظة لا تتجاوز 2000 حرف';end if;
  if exists(select 1 from jsonb_array_elements(lines) e where jsonb_typeof(e->'qty') is distinct from 'number' or(e->>'qty')::numeric<=0 or(e->>'qty')::numeric>1000000 or(e->>'qty')::numeric<>round((e->>'qty')::numeric,3)) then raise exception 'الكميات غير صحيحة';end if;
  if (select count(*) from jsonb_array_elements(lines) e where e->>'lineId' is not null)<>(select count(distinct e->>'lineId') from jsonb_array_elements(lines) e where e->>'lineId' is not null) then raise exception 'فقرة مكررة';end if;
  for entry in select value from jsonb_array_elements(lines) loop
   select * into product from public.products where id=(entry->>'productId')::bigint;
   if product.id is null then raise exception 'المادة غير موجودة';end if;
   if entry->>'lineId' is not null then
    select * into original from public.transaction_items where id=(entry->>'lineId')::bigint and transaction_id=t.id;
    if original.id is null or original.product_id is distinct from product.id then raise exception 'فقرة لا تخص الوصل';end if;
   elsif (select count(*) from jsonb_array_elements(lines) e where e->>'productId'=entry->>'productId')>1 then raise exception 'المادة الجديدة مكررة؛ عدّل كميتها في فقرة واحدة';end if;
   safe_lines:=safe_lines||jsonb_build_array(jsonb_build_object('lineId',case when entry->>'lineId' is not null then original.id end,'productId',product.id,
    'name',case when entry->>'lineId' is not null then original.product_name else product.name end,'brand',case when entry->>'lineId' is not null then original.brand_name else(select name from public.brands where id=product.brand_id) end,
    'category',product.category,'qty',(entry->>'qty')::numeric,'pending',entry->>'lineId' is null));
  end loop;
  for pid in select distinct(x->>'productId')::bigint from jsonb_array_elements(safe_lines) x loop
   select sum((x->>'qty')::numeric) into needed from jsonb_array_elements(safe_lines) x where(x->>'productId')::bigint=pid;
   select coalesce(sum(i.qty),0) into held from public.transaction_items i where i.transaction_id=t.id and i.product_id=pid;
   select coalesce(s.qty,0) into available from solar_private.warehouse_stocks s where s.warehouse_id=t.warehouse_id and s.product_id=pid;
   if needed>coalesce(available,0)+held then raise exception 'الكمية المتوفرة لا تكفي في مخزن الفاتورة';end if;
  end loop;
  select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]') into before_items from public.transaction_items i where i.transaction_id=t.id;
  update public.transactions set warehouse_status='pending',warehouse_prepared_at=null,warehouse_prepared_by=null,warehouse_note=coalesce(note,''),warehouse_revision=warehouse_revision+1 where id=t.id;
  insert into solar_private.warehouse_price_edits(invoice_id,lines,base_token,actor_id) values(t.id,safe_lines,solar_private.warehouse_token_v364(t.id),auth.uid())
   on conflict on constraint warehouse_price_edits_pkey do update set lines=excluded.lines,base_token=excluded.base_token,actor_id=excluded.actor_id,updated_at=clock_timestamp();
  insert into solar_private.warehouse_audit(invoice_id,actor_id,action,before_items,after_items) values(t.id,auth.uid(),'price_requested',before_items,safe_lines);
  for u in select p.id from public.profiles p where p.active and p.user_type not in('warehouse','installer') and(p.id=t.created_by or p.is_admin) loop
   perform solar_private.warehouse_notice(u,t.id,'warehouse_edited');
  end loop;
 else
  perform solar_private.warehouse_action_v364(invoice_id,expected_token,action,lines,note);
  if action='save' then delete from solar_private.warehouse_price_edits e where e.invoice_id=t.id;end if;
 end if;
end$$;
revoke all on function solar_private.warehouse_action_v364(bigint,text,text,jsonb,text),solar_private.warehouse_action(bigint,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function solar_private.warehouse_action(bigint,text,text,jsonb,text) to authenticated;

create function solar_private.warehouse_pricing(action text,invoice_id bigint default null,expected_token text default null,prices jsonb default null,request_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare p public.profiles;t public.transactions;e solar_private.warehouse_price_edits;previous solar_private.warehouse_price_requests;
 payload jsonb:=jsonb_build_object('action',action,'invoiceId',invoice_id,'expectedToken',expected_token,'prices',prices);
 result jsonb;items jsonb;line jsonb;unit_price numeric;u uuid;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 if p.id is null or not(p.is_admin or coalesce(p.permissions->>'sale','false')='true') then raise exception 'تسعير المواد للإدارة فقط' using errcode='42501';end if;
 if action='list' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(jsonb_build_object('id',tx.id,'receiptNo',tx.receipt_no,'party',tx.party_name,'warehouseName',tx.warehouse_name,'count',jsonb_array_length(pe.lines),'date',pe.updated_at) order by pe.updated_at,tx.id)
   from solar_private.warehouse_price_edits pe join public.transactions tx on tx.id=pe.invoice_id where(p.is_admin or tx.created_by=p.id) and solar_private.warehouse_access_allowed(p.id,tx.warehouse_id)),'[]'));
 end if;
 if action not in('get','approve','cancel') then raise exception 'إجراء غير صحيح';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into t from public.transactions where id=invoice_id and kind='sale' for update;
 if t.id is null or not(p.is_admin or t.created_by=p.id) or not solar_private.warehouse_access_allowed(p.id,t.warehouse_id) then raise exception 'الفاتورة غير متاحة ضمن صلاحياتك' using errcode='42501';end if;
 if action in('approve','cancel') then
  if request_id is null then raise exception 'معرّف الطلب مطلوب';end if;
  select * into previous from solar_private.warehouse_price_requests r where r.request_id=warehouse_pricing.request_id;
  if previous.request_id is not null then
   if previous.actor_id<>p.id or previous.payload is distinct from payload then raise exception 'أعد تأكيد نفس الطلب السابق' using errcode='PT409';end if;
   return previous.result;
  end if;
 end if;
 select * into e from solar_private.warehouse_price_edits x where x.invoice_id=t.id for update;
 if e.invoice_id is null then raise exception 'لا توجد فقرات بانتظار التسعير';end if;
 if action='get' then
  select jsonb_agg(x.value||jsonb_build_object('price',i.price) order by x.ordinality) into items from jsonb_array_elements(e.lines) with ordinality x(value,ordinality)
   left join public.transaction_items i on i.id=(x.value->>'lineId')::bigint and i.transaction_id=t.id;
  return jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'party',t.party_name,'warehouseName',t.warehouse_name,'items',items,'token',solar_private.warehouse_token(t.id),'stale',e.base_token is distinct from solar_private.warehouse_token_v364(t.id),'total',t.total,'expenses',t.expenses);
 end if;
 if solar_private.warehouse_token(t.id) is distinct from expected_token then raise exception 'تغيّر طلب المواد؛ افتحه مجددًا' using errcode='PT409';end if;
 if action='approve' then
  if e.base_token is distinct from solar_private.warehouse_token_v364(t.id) then raise exception 'تغيّرت الفاتورة بعد طلب المواد؛ ألغِ الطلب وافتح تعديلًا جديدًا' using errcode='PT409';end if;
  if t.installation_status in('in_progress','completed','closed') then raise exception 'الفاتورة مقفلة للتعديل';end if;
  if jsonb_typeof(prices) is distinct from 'array' or jsonb_array_length(prices)<>(select count(*) from jsonb_array_elements(e.lines) x where x->>'lineId' is null)
   or(select count(*) from jsonb_array_elements(prices))<>(select count(distinct x->>'productId') from jsonb_array_elements(prices) x) then raise exception 'حدّد سعر كل مادة جديدة مرة واحدة';end if;
  items:='[]';
  for line in select value from jsonb_array_elements(e.lines) loop
   if line->>'lineId' is null then
    select(x->>'price')::numeric into unit_price from jsonb_array_elements(prices) x where x->>'productId'=line->>'productId' and jsonb_typeof(x->'price')='number';
    if unit_price is null or unit_price<=0 or unit_price>1000000000000 then raise exception 'أدخل سعر بيع موجب لكل مادة جديدة';end if;
   else select i.price into unit_price from public.transaction_items i where i.id=(line->>'lineId')::bigint and i.transaction_id=t.id;end if;
   if unit_price is null then raise exception 'تغيّرت إحدى الفقرات؛ افتح الطلب مجددًا' using errcode='PT409';end if;
   items:=items||jsonb_build_array(jsonb_build_object('id',(line->>'productId')::bigint,'qty',(line->>'qty')::numeric,'price',unit_price));
  end loop;
  result:=solar_private.invoice_save(request_id,jsonb_build_object('kind','sale','invoiceId',t.id,'expectedRevision',t.pricing_revision,'warehouseId',t.warehouse_id,
   'partyId',t.party_id,'party',t.party_name,'mode',case when t.cash then 'cash' else 'credit' end,'notes',coalesce(t.notes,''),'expenses',coalesce(t.expenses,0),
   'sourceCurrency','IQD','exchangeRate',1,'items',items));
  delete from solar_private.warehouse_price_edits x where x.invoice_id=t.id;
  result:=jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'total',result->'total','pricingPending',false);
 else
  delete from solar_private.warehouse_price_edits x where x.invoice_id=t.id;
  update public.transactions set warehouse_revision=warehouse_revision+1 where id=t.id;
  result:=jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'cancelled',true);
 end if;
 insert into solar_private.warehouse_price_requests(request_id,actor_id,invoice_id,payload,result) values(request_id,p.id,t.id,payload,result);
 for u in select person.id from public.profiles person where person.active and(person.user_type='warehouse' or(person.permissions->>'warehouse'='true' and(person.is_admin or person.id=t.created_by))) and solar_private.warehouse_access_allowed(person.id,t.warehouse_id) loop
  perform solar_private.warehouse_notice(u,t.id,'warehouse_reopened');
 end loop;
 perform solar_private.warehouse_notice(t.created_by,t.id,'warehouse_edited');
 return result;
end$$;
create function public.solar_warehouse_pricing(action text,invoice_id bigint default null,expected_token text default null,prices jsonb default null,request_id uuid default null) returns jsonb
language sql security invoker set search_path='' as $$select solar_private.warehouse_pricing(action,invoice_id,expected_token,prices,request_id)$$;
revoke all on function solar_private.warehouse_pricing(text,bigint,text,jsonb,uuid),public.solar_warehouse_pricing(text,bigint,text,jsonb,uuid) from public,anon;
grant execute on function solar_private.warehouse_pricing(text,bigint,text,jsonb,uuid),public.solar_warehouse_pricing(text,bigint,text,jsonb,uuid) to authenticated;

-- Refresh existing API wrappers after the implementation renames.
create or replace function public.solar_warehouse_orders(search_text text default '',state text default 'pending',page_offset integer default 0) returns jsonb
language sql security invoker set search_path='' as $$select solar_private.warehouse_orders(search_text,state,page_offset)$$;
create or replace function public.solar_warehouse_action(invoice_id bigint,expected_token text,action text,lines jsonb default null,note text default '') returns void
language sql security invoker set search_path='' as $$select solar_private.warehouse_action(invoice_id,expected_token,action,lines,note)$$;
