-- Preserve verified historical snapshots and original header precision.
do $$declare f record;begin
 for f in select*from(values
  ('solar_private.apply_purchase_derived_cost(uuid)','7a5756877e554a162d1eb8cbc1cb9d53'),
  ('solar_private.purchase_correction_ledger_plan(transactions,jsonb)','89bfd2f4957b040f79699702f749e945'),
  ('solar_private.purchase_correction_plan(jsonb,boolean)','6e4789637cc463ae69bc1c33c839e58d'),
  ('solar_private.purchase_material_history(transactions,bigint)','ab61ab01c4ba8597e6cc1b3d1b0b0fb8'),
  ('solar_private.purchase_material_replay(jsonb,jsonb,bigint,jsonb)','a41be0795ebbc2fd4d587dd8b1c0a576'))expected(signature,hash)loop
 if md5(pg_get_functiondef(f.signature::regprocedure))<>f.hash then raise exception 'Purchase correction function changed: %',f.signature;end if;
 end loop;end$$;
-- Pure numeric replay. It does not read or write customer/cash/settlement data.
create or replace function solar_private.purchase_material_replay(seed jsonb, events jsonb, target_id bigint, replacement jsonb default null)
returns jsonb language plpgsql immutable set search_path='' as $$
declare e jsonb;state jsonb;states jsonb:=coalesce(seed->'states','{}');snapshots jsonb:='{}';
 q numeric:=(seed->>'qty')::numeric;c numeric:=(seed->>'cost')::numeric;
 usd numeric:=(seed->'parts'->>'usd')::numeric;iqd numeric:=(seed->'parts'->>'iqd')::numeric;
 previous_qty numeric;new_qty numeric;delta numeric;price numeric;landed numeric;unit_usd numeric;unit_iqd numeric;
 book numeric;uv numeric;iv numeric;next_q numeric;financial numeric;old_book numeric;old_usd numeric;old_iqd numeric;
 sale_rate numeric;currency text;rate numeric;expenses numeric;source_sum numeric;k text;key text;basis jsonb;
begin
 for e in select value from jsonb_array_elements(events) loop
  key:=e->>'invoiceId';k:=e->>'kind';state:=coalesce(states->key,'{}');previous_qty:=coalesce((state->>'qty')::numeric,0);
  if (e->>'invoiceId')::bigint=target_id and replacement is not null then e:=e||replacement;end if;
  new_qty:=case when e->>'action'='delete' then 0 else coalesce((e->>'qty')::numeric,0) end;
  if k='purchase' then
   price:=coalesce((e->>'price')::numeric,0);currency:=coalesce(e->>'currency','IQD');rate:=coalesce((e->>'rate')::numeric,1);
   expenses:=coalesce((e->>'expenses')::numeric,0);source_sum:=coalesce((e->>'sourceTotal')::numeric,0);
   landed:=round(price*rate+case when source_sum>0 then expenses*price/source_sum else 0 end,6);
   unit_usd:=case when currency='USD' then price else 0 end;
   unit_iqd:=case when currency='USD' then greatest(0,landed-price*rate) else landed end;
   if previous_qty=0 then
    snapshots:=jsonb_set(snapshots,array[key],jsonb_build_object('qty',q,'cost',c,'basis',jsonb_build_object('method','purchase-replay','unitCost',c,'currencyComponents',jsonb_build_object('usd',usd,'iqd',iqd))),true);
   end if;
   next_q:=q+new_qty-previous_qty;
   book:=q*c+new_qty*landed-previous_qty*coalesce((state->>'book')::numeric,0);
   uv:=q*usd+new_qty*unit_usd-previous_qty*coalesce((state->'parts'->>'usd')::numeric,0);
   iv:=q*iqd+new_qty*unit_iqd-previous_qty*coalesce((state->'parts'->>'iqd')::numeric,0);
   if next_q<0 or book< -greatest(.0001,(q+previous_qty+new_qty)*.0000005) or uv<-.00001 or iv< -greatest(.0001,(q+previous_qty+new_qty)*.0000005) then
    raise exception 'التعديل يجعل كمية المادة أو كلفتها غير صحيحة عند حركة شراء لاحقة؛ راجع الكمية المصححة.' using errcode='PT409';
   end if;
   if next_q=0 and (abs(book)>greatest(.0001,(q+previous_qty+new_qty)*.0000005) or abs(uv)>.00001 or abs(iv)>greatest(.0001,(q+previous_qty+new_qty)*.0000005)) then
    raise exception 'تعذر مطابقة كلفة المادة عند نفاد المخزون؛ يلزم مراجعة تسلسل حركاتها.' using errcode='PT409';
   end if;
   if next_q>0 then
    c:=round(greatest(0,book)/next_q,6);usd:=greatest(0,uv)/next_q;iqd:=greatest(0,iv)/next_q;
   elsif e->>'action'='delete' and previous_qty>0 and snapshots?key then
    -- Existing cancellation restores the quote before this purchase when the
    -- stock pool becomes empty. Use the replayed snapshot so an earlier
    -- corrected purchase changes only its own remembered quote and sales.
    c:=(snapshots->key->>'cost')::numeric;
    usd:=(snapshots->key->'basis'->'currencyComponents'->>'usd')::numeric;
    iqd:=(snapshots->key->'basis'->'currencyComponents'->>'iqd')::numeric;
   end if;
   q:=next_q;
   states:=jsonb_set(states,array[key],jsonb_build_object('kind',k,'qty',new_qty,'book',landed,'cost',landed,'parts',jsonb_build_object('usd',unit_usd,'iqd',unit_iqd)),true);
  elsif k in('sale','system') then
   delta:=new_qty-previous_qty;
   old_book:=coalesce((state->>'book')::numeric,c);old_usd:=coalesce((state->'parts'->>'usd')::numeric,usd);old_iqd:=coalesce((state->'parts'->>'iqd')::numeric,iqd);
   if new_qty>0 and previous_qty=0 then
    sale_rate:=(e->>'valuationRate')::numeric;
    financial:=case when sale_rate is null then c else round(usd*sale_rate+iqd,6) end;
    old_book:=c;old_usd:=usd;old_iqd:=iqd;
   else financial:=coalesce((state->>'cost')::numeric,c);sale_rate:=(state->>'valuationRate')::numeric;end if;
   if delta>q then raise exception 'الكمية المصححة لا تكفي لحركة بيع لاحقة للمادة؛ خفّض التعديل أو صحّح كمية البيع المرتبطة أولًا.' using errcode='PT409';end if;
   next_q:=q-delta;
   if delta>0 then
    if previous_qty>0 then
     old_book:=(previous_qty*old_book+delta*c)/new_qty;
     old_usd:=(previous_qty*old_usd+delta*usd)/new_qty;
     old_iqd:=(previous_qty*old_iqd+delta*iqd)/new_qty;
    end if;
    -- A sale consumes the current weighted mix. Six-place procurement cost
    -- stays independent of the historical sale-time FX valuation quote.
   elsif delta<0 and next_q>0 then
    c:=round((q*c-delta*old_book)/next_q,6);
    usd:=(q*usd-delta*old_usd)/next_q;iqd:=(q*iqd-delta*old_iqd)/next_q;
   end if;
   q:=next_q;
   basis:=coalesce(state->'basis',e->'savedBasis','{}')||jsonb_build_object('bookUnitCost',old_book,'currencyComponents',jsonb_build_object('usd',old_usd,'iqd',old_iqd),'valuationUnitCost',financial,'valuationRate',sale_rate);
   states:=jsonb_set(states,array[key],jsonb_build_object('kind',k,'qty',new_qty,'book',old_book,'cost',financial,'parts',jsonb_build_object('usd',old_usd,'iqd',old_iqd),'valuationRate',sale_rate,'basis',basis),true);
  else raise exception 'نوع حركة المادة غير مدعوم لإعادة احتساب الكلفة' using errcode='PT409';end if;
 end loop;
 return jsonb_build_object('qty',q,'cost',c,'parts',jsonb_build_object('usd',usd,'iqd',iqd),'states',states,'snapshots',snapshots);
end$$;
revoke all on function solar_private.purchase_material_replay(jsonb,jsonb,bigint,jsonb) from public,anon,authenticated;


create or replace function solar_private.purchase_material_history(target public.transactions, material_id bigint)
returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare snap jsonb;seed jsonb;events jsonb:='[]';states jsonb:='{}';doc record;r record;line jsonb;first_line jsonb;before_line jsonb;
 anchor timestamptz;event_at timestamptz;first_payload jsonb;first_at timestamptz;rate numeric;parts jsonb;qty numeric;basis jsonb;first_event jsonb;anchor_items jsonb;anchor_line jsonb;anchor_config jsonb;full_before jsonb;before_at timestamptz;anchor_qty numeric;anchor_has_snapshot boolean;anchor_unit numeric;anchor_usd numeric;anchor_iqd numeric;anchor_source numeric;anchor_rate numeric;anchor_expenses numeric;
begin
 select value into snap from jsonb_array_elements(target.purchase_stock) where(value->>'id')::bigint=material_id;
 if snap is null then raise exception 'لا تتوفر لقطة مخزون المادة السابقة لهذا الشراء؛ يلزم مراجعة الوصل القديم قبل تصحيحه.' using errcode='PT409';end if;
 with requests as(
  select r.created_at,r.request_id,coalesce((r.payload->>'expectedRevision')::bigint,-1)revision,
   exists(select 1 from jsonb_array_elements(r.payload->'items')i where(i->>'id')::bigint=material_id)present
  from solar_private.invoice_requests r where(r.result->>'id')::bigint=target.id
 ),transitions as(select *,lag(present,1,false)over(order by created_at,revision,request_id)previous from requests)
 select max(created_at)into anchor from transitions where present and not previous;
 anchor:=coalesce(anchor,target.created_at);
 parts:=solar_private.inventory_currency_parts(material_id,snap->'basis',(snap->>'cost')::numeric);
 seed:=jsonb_build_object('qty',(snap->>'qty')::numeric,'cost',(snap->>'cost')::numeric,'parts',parts);
 if exists(select 1 from solar_private.stock_adjustments where product_id=material_id and created_at>=anchor) then
  raise exception 'لهذه المادة جرد مخزون لاحق؛ تعذر إثبات تسلسل الكلفة دون تغيير نتيجة الجرد، راجع الإدارة.' using errcode='PT409';end if;
 for doc in
  with documents as(
   select t.id,to_jsonb(t) header,coalesce((select jsonb_agg(to_jsonb(i) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]') items,null::timestamptz deleted_at
   from public.transactions t where t.kind in('purchase','sale','system')
   union all select d.invoice_id,d.invoice,d.items,d.deleted_at from solar_private.deleted_sales d where d.invoice->>'kind' in('purchase','sale','system')
  )select * from documents d where
   exists(select 1 from jsonb_array_elements(d.items)i where(i->>'product_id')::bigint=material_id)
   or exists(select 1 from solar_private.invoice_requests r,jsonb_array_elements(r.payload->'items')i where(r.result->>'id')::bigint=d.id and(i->>'id')::bigint=material_id)
   or exists(select 1 from solar_private.warehouse_audit a,jsonb_array_elements(a.before_items||a.after_items)i where a.invoice_id=d.id and(i->>'product_id')::bigint=material_id)
  order by (d.header->>'created_at')::timestamptz,d.id
 loop
  first_payload:=null;first_at:=null;line:=null;before_line:=null;
  select r.payload,r.created_at into first_payload,first_at from solar_private.invoice_requests r where(r.result->>'id')::bigint=doc.id and r.payload->>'invoiceId' is null order by r.created_at,r.request_id limit 1;
  first_at:=coalesce(first_at,(doc.header->>'created_at')::timestamptz);
  if doc.id=target.id then first_at:=anchor;end if;
  select i into line from jsonb_array_elements(doc.items)i where(i->>'product_id')::bigint=material_id;
  select i into before_line from solar_private.warehouse_audit a,jsonb_array_elements(a.before_items)i where a.invoice_id=doc.id and(i->>'product_id')::bigint=material_id order by a.created_at,a.id limit 1;
  basis:=coalesce(before_line->'cost_basis',line->'cost_basis','{}');rate:=(basis->>'valuationRate')::numeric;
  if doc.id=target.id then
   first_payload:=jsonb_build_object('sourceCurrency',target.source_currency,'exchangeRate',target.exchange_rate,'expenses',target.expenses,'sourceSubtotal',target.source_subtotal);
   first_line:=jsonb_build_object('qty',(line->>'qty')::numeric,'price',coalesce((line->>'source_price')::numeric,(line->>'price')::numeric));
  elsif first_payload is not null then
   select i into first_line from jsonb_array_elements(first_payload->'items')i where(i->>'id')::bigint=material_id;
  else
   first_payload:=jsonb_build_object('sourceCurrency',doc.header->'source_currency','exchangeRate',doc.header->'exchange_rate','expenses',doc.header->'expenses','sourceSubtotal',doc.header->'source_subtotal');
   first_line:=jsonb_build_object('qty',line->'qty','price',coalesce((line->>'source_price')::numeric,(line->>'price')::numeric));
  end if;
  if doc.id<>target.id and exists(select 1 from solar_private.purchase_corrections c where c.invoice_id=doc.id) then
   -- An earlier correction already established this receipt's effective
   -- historical contribution. Replaying its obsolete requests would undo it.
   first_payload:=jsonb_build_object('sourceCurrency',doc.header->'source_currency','exchangeRate',doc.header->'exchange_rate','expenses',doc.header->'expenses','sourceSubtotal',doc.header->'source_subtotal');
   first_line:=jsonb_build_object('qty',line->'qty','price',coalesce((line->>'source_price')::numeric,(line->>'price')::numeric));
   if doc.deleted_at is not null and exists(select 1 from solar_private.purchase_corrections c where c.invoice_id=doc.id and c.plan->>'action'='delete')then first_line:=first_line||jsonb_build_object('qty',0);end if;
  end if;
  if first_at<anchor or(first_at=anchor and doc.id<target.id) then
   if doc.deleted_at is not null and doc.deleted_at<anchor then continue;end if;
   if doc.header->>'kind'='purchase'and doc.deleted_at is not null and exists(select 1 from solar_private.purchase_corrections c where c.invoice_id=doc.id and c.plan->>'action'='delete')then continue;end if;
   -- Establish membership at the material's anchor from a COMPLETE saved
   -- invoice snapshot. Absence is zero, never today's later-added line.
   anchor_items:=null;anchor_config:=null;anchor_line:=null;full_before:=null;before_at:=null;
   select x.items,x.config into anchor_items,anchor_config from(
    select r.payload->'items'items,r.payload config,r.created_at at,1 priority,coalesce((r.payload->>'expectedRevision')::bigint,-1)ordering
    from solar_private.invoice_requests r where(r.result->>'id')::bigint=doc.id and r.created_at<anchor
    union all select a.after_items,null,a.created_at,2,a.id from solar_private.warehouse_audit a where a.invoice_id=doc.id and a.created_at<anchor and a.action in('save','ready','reopen')
   )x order by x.at desc,x.priority desc,x.ordering desc limit 1;
   anchor_has_snapshot:=anchor_items is not null;
   if anchor_has_snapshot then
    select i into anchor_line from jsonb_array_elements(anchor_items)i where coalesce((i->>'product_id')::bigint,(i->>'id')::bigint)=material_id;
    anchor_qty:=coalesce((anchor_line->>'qty')::numeric,0);
   else anchor_qty:=null;end if;
   select a.before_items,a.created_at into full_before,before_at from solar_private.warehouse_audit a where a.invoice_id=doc.id and a.created_at>=anchor order by a.created_at,a.id limit 1;
   select i into before_line from jsonb_array_elements(full_before)i where(i->>'product_id')::bigint=material_id;
   if not anchor_has_snapshot then
    if full_before is null and exists(select 1 from solar_private.invoice_requests r where(r.result->>'id')::bigint=doc.id and r.payload->>'invoiceId'is not null and r.created_at>=anchor)then raise exception 'لا توجد لقطة كاملة تثبت مواد الفاتورة قبل التعديل.'using errcode='PT409';end if;
    if full_before is not null then anchor_qty:=coalesce((before_line->>'qty')::numeric,0);
    else anchor_qty:=coalesce((line->>'qty')::numeric,0);end if;
   end if;
   if anchor_qty>0 then
    if doc.header->>'kind'='purchase' then
     anchor_line:=coalesce(anchor_line,line);anchor_config:=coalesce(anchor_config,jsonb_build_object('sourceCurrency',doc.header->'source_currency','exchangeRate',doc.header->'exchange_rate','expenses',doc.header->'expenses','sourceSubtotal',doc.header->'source_subtotal'));
     anchor_rate:=coalesce((anchor_config->>'exchangeRate')::numeric,1);anchor_expenses:=coalesce((anchor_config->>'expenses')::numeric,0);
     anchor_source:=coalesce((anchor_config->>'sourceSubtotal')::numeric,(select sum((i->>'qty')::numeric*(i->>'price')::numeric)from jsonb_array_elements(anchor_config->'items')i),0);
     anchor_unit:=coalesce((anchor_line->>'source_price')::numeric,(anchor_line->>'price')::numeric);
     anchor_usd:=case when anchor_config->>'sourceCurrency'='USD'then anchor_unit else 0 end;
     anchor_unit:=round(anchor_unit*anchor_rate+case when anchor_source>0 then anchor_expenses*anchor_unit/anchor_source else 0 end,6);
     anchor_iqd:=case when anchor_config->>'sourceCurrency'='USD'then greatest(0,anchor_unit-anchor_usd*anchor_rate)else anchor_unit end;
     basis:=coalesce(anchor_line->'cost_basis','{}');parts:=jsonb_build_object('usd',anchor_usd,'iqd',anchor_iqd);
     states:=jsonb_set(states,array[doc.id::text],jsonb_build_object('kind','purchase','qty',anchor_qty,'cost',anchor_unit,'book',anchor_unit,'parts',parts,'basis',basis),true);
    else
     -- The earliest later warehouse before-image is authoritative only if no
     -- earlier request changed this material's quantity. Notes/other lines do
     -- not invalidate it or the saved current quote.
     if full_before is not null and coalesce((before_line->>'qty')::numeric,0)=anchor_qty and not exists(
      select 1 from solar_private.invoice_requests r where(r.result->>'id')::bigint=doc.id and r.payload->>'invoiceId'is not null and r.created_at>=anchor and r.created_at<before_at and
       coalesce((select(i->>'qty')::numeric from jsonb_array_elements(r.payload->'items')i where(i->>'id')::bigint=material_id),0)<>anchor_qty
     )then anchor_line:=before_line;
     elsif anchor_line->'cost_basis'is not null then null;
     elsif line is not null and(anchor_has_snapshot or full_before is not null)and(line->>'qty')::numeric>0 and(line->>'qty')::numeric<=anchor_qty and not exists(
      with changes as(
       select r.created_at at,1 priority,coalesce((r.payload->>'expectedRevision')::bigint,0)ordering,
        coalesce((select(i->>'qty')::numeric from jsonb_array_elements(r.payload->'items')i where(i->>'id')::bigint=material_id),0)q
       from solar_private.invoice_requests r where(r.result->>'id')::bigint=doc.id and r.payload->>'invoiceId'is not null and r.created_at>=anchor
       union all select a.created_at,2,a.id,coalesce((select(i->>'qty')::numeric from jsonb_array_elements(a.after_items)i where(i->>'product_id')::bigint=material_id),0)
       from solar_private.warehouse_audit a where a.invoice_id=doc.id and a.created_at>=anchor and a.action in('save','ready','reopen')
      ),sequence as(select q,lag(q,1,anchor_qty)over(order by at,priority,ordering)previous from changes)
      select 1 from sequence where q>previous
     )then anchor_line:=line; -- Decreases preserve the existing return-cost basis.

     else raise exception 'تعديل كمية قديم لهذه المادة لا يملك لقطة كلفة كافية؛ تعذر إثبات التسلسل بأمان.'using errcode='PT409';end if;
     basis:=coalesce(anchor_line->'cost_basis','{}');anchor_unit:=coalesce((basis->>'bookUnitCost')::numeric,(anchor_line->>'cost')::numeric);
     if anchor_unit is null then raise exception 'لقطة كلفة المادة قبل التعديل غير مكتملة.'using errcode='PT409';end if;
     parts:=solar_private.inventory_currency_parts(material_id,basis,anchor_unit);
     states:=jsonb_set(states,array[doc.id::text],jsonb_build_object('kind',doc.header->>'kind','qty',anchor_qty,'cost',(anchor_line->>'cost')::numeric,'book',anchor_unit,'parts',parts,'basis',basis,'valuationRate',basis->'valuationRate'),true);
    end if;
   end if;
  else
   first_event:=jsonb_build_object('invoiceId',doc.id,'kind',doc.header->>'kind','action','save','at',first_at,'sequence',0,'qty',coalesce((first_line->>'qty')::numeric,0),'price',coalesce((first_line->>'price')::numeric,0),'currency',coalesce(first_payload->>'sourceCurrency','IQD'),'rate',coalesce((first_payload->>'exchangeRate')::numeric,1),'expenses',coalesce((first_payload->>'expenses')::numeric,0),'sourceTotal',coalesce((first_payload->>'sourceSubtotal')::numeric,(select sum((i->>'qty')::numeric*(i->>'price')::numeric) from jsonb_array_elements(first_payload->'items')i),0),'valuationRate',rate,'savedBasis',basis);
   events:=events||jsonb_build_array(first_event);
  end if;
  if doc.id<>target.id and not exists(select 1 from solar_private.purchase_corrections c where c.invoice_id=doc.id) then
   if exists(select 1 from solar_private.invoice_requests r where(r.result->>'id')::bigint=doc.id and r.payload->>'invoiceId'is not null and r.created_at>=anchor group by r.created_at,coalesce(r.payload->>'expectedRevision','')having count(distinct jsonb_build_object('items',r.payload->'items','sourceCurrency',r.payload->'sourceCurrency','exchangeRate',r.payload->'exchangeRate','expenses',r.payload->'expenses')::text)>1)then
    raise exception 'تعذر تحديد ترتيب تعديلات متزامنة للمادة؛ لم يُحفظ التصحيح.'using errcode='PT409';end if;
   for r in select * from solar_private.invoice_requests r where(r.result->>'id')::bigint=doc.id and r.payload->>'invoiceId' is not null and r.created_at>=anchor order by r.created_at,r.request_id loop
    select i into first_line from jsonb_array_elements(r.payload->'items')i where(i->>'id')::bigint=material_id;
    events:=events||jsonb_build_array(jsonb_build_object('invoiceId',doc.id,'kind',doc.header->>'kind','action','save','at',r.created_at,'sequence',1,'orderKey',coalesce((r.payload->>'expectedRevision')::bigint,0),'qty',coalesce((first_line->>'qty')::numeric,0),'price',coalesce((first_line->>'price')::numeric,0),'currency',coalesce(r.payload->>'sourceCurrency','IQD'),'rate',coalesce((r.payload->>'exchangeRate')::numeric,1),'expenses',coalesce((r.payload->>'expenses')::numeric,0),'sourceTotal',(select coalesce(sum((i->>'qty')::numeric*(i->>'price')::numeric),0) from jsonb_array_elements(r.payload->'items')i),'valuationRate',rate,'savedBasis',basis));
   end loop;
  end if;
  for r in select * from solar_private.warehouse_audit a where a.invoice_id=doc.id and a.created_at>=anchor and a.action='save' order by a.created_at,a.id loop
   select i into first_line from jsonb_array_elements(r.after_items)i where(i->>'product_id')::bigint=material_id;
   events:=events||jsonb_build_array(jsonb_build_object('invoiceId',doc.id,'kind',doc.header->>'kind','action','save','at',r.created_at,'sequence',2,'orderKey',r.id,'qty',coalesce((first_line->>'qty')::numeric,0),'valuationRate',coalesce(first_line->'cost_basis'->'valuationRate',to_jsonb(rate)),'savedBasis',coalesce(first_line->'cost_basis',basis)));
  end loop;
  if doc.deleted_at is not null and doc.deleted_at>=anchor then
   events:=events||jsonb_build_array(jsonb_build_object('invoiceId',doc.id,'kind',doc.header->>'kind','action','delete','at',doc.deleted_at,'sequence',3));
  end if;
 end loop;
 select coalesce(jsonb_agg(e order by(e->>'at')::timestamptz,(e->>'invoiceId')::bigint,(e->>'sequence')::integer,coalesce((e->>'orderKey')::bigint,0)),'[]') into events from jsonb_array_elements(events)e;
 return jsonb_build_object('seed',seed||jsonb_build_object('states',states),'events',events);
end$$;
revoke all on function solar_private.purchase_material_history(public.transactions,bigint) from public,anon,authenticated;


-- Compatibility only: retain either proven historical exact header totals or
-- the current two-decimal representation. No tolerance/offset forgiveness.
create or replace function solar_private.purchase_derived_totals(invoice public.transactions,original_item_cost numeric,corrected_item_cost numeric)
returns jsonb language plpgsql immutable set search_path='' as $function$
declare corrected_cost numeric;corrected_profit numeric;precision_mode text;original_profit numeric;
begin
 if invoice.kind not in('sale','system')or original_item_cost is null or corrected_item_cost is null
  or original_item_cost<0 or corrected_item_cost<0
  or original_item_cost::text in('NaN','Infinity','-Infinity')or corrected_item_cost::text in('NaN','Infinity','-Infinity')then
  raise exception 'إجماليات كلفة فاتورة مرتبطة لا تطابق موادها؛ لم يُحفظ التصحيح، راجع الفاتورة أولًا.'using errcode='PT409';
 end if;
 -- If both representations match, retain today's canonical two-decimal mode.
 if invoice.cost=round(original_item_cost,2)then precision_mode:='rounded';corrected_cost:=round(corrected_item_cost,2);
 elsif invoice.cost=original_item_cost then precision_mode:='exact';corrected_cost:=corrected_item_cost;
 else raise exception 'إجماليات كلفة فاتورة مرتبطة لا تطابق موادها؛ لم يُحفظ التصحيح، راجع الفاتورة أولًا.'using errcode='PT409';end if;
 original_profit:=coalesce(invoice.total,0)-invoice.cost-coalesce(invoice.expenses,0)-case when invoice.kind='system'then coalesce(invoice.installation_expenses,0)else 0 end;
 if invoice.profit is distinct from original_profit then
  raise exception 'إجماليات كلفة فاتورة مرتبطة لا تطابق موادها؛ لم يُحفظ التصحيح، راجع الفاتورة أولًا.'using errcode='PT409';end if;
 corrected_profit:=invoice.profit+invoice.cost-corrected_cost;
 return jsonb_build_object('cost',corrected_cost,'profit',corrected_profit,'mode',precision_mode);
end $function$;
revoke all on function solar_private.purchase_derived_totals(public.transactions,numeric,numeric)from public,anon,authenticated;

do $patch$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('solar_private.purchase_correction_plan(jsonb,boolean)'::regprocedure);
 needle:='affected_id bigint;token text;locked boolean;';
 if strpos(definition,needle)=0 then raise exception 'Review purchase plan precision declarations';end if;
 definition:=replace(definition,needle,needle||'old_item_cost numeric;header_totals jsonb;');
 needle:=$old$  if invoice.cost is distinct from(select round(sum(i.qty*i.cost),2)from public.transaction_items i where i.transaction_id=invoice.id)
   or invoice.profit is distinct from(invoice.total-invoice.cost-invoice.expenses-case when invoice.kind='system'then coalesce(invoice.installation_expenses,0)else 0 end)then
   raise exception 'إجماليات كلفة فاتورة مرتبطة لا تطابق موادها؛ لم يُحفظ التصحيح، راجع الفاتورة أولًا.'using errcode='PT409';end if;
  select round(sum(i.qty*coalesce((a->'after'->>'cost')::numeric,i.cost)),2) into new_cost from public.transaction_items i left join lateral(select value a from jsonb_array_elements(affected_lines)where(value->>'itemId')::bigint=i.id)a on true where i.transaction_id=invoice.id;
  new_profit:=invoice.total-new_cost-case when invoice.kind='system' or not coalesce(invoice.expenses_on_customer,true) then invoice.expenses else invoice.expenses end;
  -- Customer-paid wholesale expenses are included in total and removed once.
  if invoice.kind='sale' and not coalesce(invoice.expenses_on_customer,true) then new_profit:=invoice.total-new_cost-invoice.expenses;end if;
  if invoice.kind='system' then new_profit:=new_profit-coalesce(invoice.installation_expenses,0);end if;$old$;
 if strpos(definition,needle)=0 then raise exception 'Review purchase plan header aggregate contract';end if;
 definition:=replace(definition,needle,$new$  select coalesce(sum(i.qty*i.cost),0),coalesce(sum(i.qty*coalesce((a->'after'->>'cost')::numeric,i.cost)),0) into old_item_cost,new_cost from public.transaction_items i left join lateral(select value a from jsonb_array_elements(affected_lines)where(value->>'itemId')::bigint=i.id)a on true where i.transaction_id=invoice.id;
  header_totals:=solar_private.purchase_derived_totals(invoice,old_item_cost,new_cost);
  new_cost:=(header_totals->>'cost')::numeric;new_profit:=(header_totals->>'profit')::numeric;$new$);
 execute definition;
 definition:=pg_get_functiondef('solar_private.apply_purchase_derived_cost(uuid)'::regprocedure);
 needle:='calculated_cost numeric;';
 if strpos(definition,needle)=0 then raise exception 'Review derived cost precision declarations';end if;
 definition:=replace(definition,needle,needle||'original_item_cost numeric;header_totals jsonb;');
 needle:=$old$  select round(coalesce(sum(qty*cost),0),2)into calculated_cost from public.transaction_items where transaction_id=t.id;
  if new_cost is null or new_cost::text in('NaN','Infinity','-Infinity')or new_cost<0 or new_cost is distinct from calculated_cost
   or new_profit is null or new_profit::text in('NaN','Infinity','-Infinity')or new_profit is distinct from round(coalesce(t.total,0)-new_cost-coalesce(t.expenses,0)-case when t.kind='system'then coalesce(t.installation_expenses,0)else 0 end,2)then raise exception 'إجمالي كلفة وربح البيع لا يطابقان المواد المصححة'using errcode='22023';end if;$old$;
 if strpos(definition,needle)=0 then raise exception 'Review derived cost header aggregate contract';end if;
 definition:=replace(definition,needle,$new$  select coalesce(sum(x.qty*x.cost),0),coalesce(sum(x.qty*coalesce((a->'before'->>'cost')::numeric,x.cost)),0)into calculated_cost,original_item_cost
  from public.transaction_items x left join lateral(select value a from jsonb_array_elements(audited_plan->'affectedLines')where(value->>'itemId')::bigint=x.id)a on true where x.transaction_id=t.id;
  header_totals:=solar_private.purchase_derived_totals(t,original_item_cost,calculated_cost);
  if new_cost is null or new_cost::text in('NaN','Infinity','-Infinity')or new_cost<0 or new_cost is distinct from(header_totals->>'cost')::numeric
   or new_profit is null or new_profit::text in('NaN','Infinity','-Infinity')or new_profit is distinct from(header_totals->>'profit')::numeric then raise exception 'إجمالي كلفة وربح البيع لا يطابقان المواد المصححة'using errcode='22023';end if;$new$);
 execute definition;
end $patch$;


-- Identify the known account conversion barrier before the generic legacy
-- format check. No currency history or financial posting is inferred.
do $$declare definition text;needle text;begin
 definition:=pg_get_functiondef('solar_private.purchase_correction_ledger_plan(public.transactions,jsonb)'::regprocedure);
 needle:=$old$BEGIN
 IF t.id IS NULL OR t.kind<>'purchase' OR NOT t.fx_pricing$old$;
 if strpos(definition,needle)=0 then raise exception 'Purchase ledger eligibility contract changed';end if;
 execute replace(definition,needle,$new$BEGIN
 IF t.id IS NOT NULL AND t.kind='purchase' AND EXISTS(SELECT 1 FROM public.suppliers current_supplier WHERE current_supplier.id=t.party_id AND(current_supplier.currency_revision IS DISTINCT FROM t.account_revision OR current_supplier.account_currency IS DISTINCT FROM t.account_currency))THEN
  RAISE EXCEPTION 'تغيرت عملة حساب المورد بعد هذا الشراء؛ يلزم مراجعة حسابه بالعملة الحالية قبل تعديل الوصل.'USING ERRCODE='PT409';END IF;
 IF t.id IS NULL OR t.kind<>'purchase' OR NOT t.fx_pricing$new$);
end$$;

NOTIFY pgrst,'reload schema';
