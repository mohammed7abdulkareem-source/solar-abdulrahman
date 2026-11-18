-- Validate every replaced accounting definition before installing this migration.
do $$declare f record;begin
 for f in select * from(values
  ('solar_private.cash_balance(uuid)','557205eb95eb0815be16bcc444c55f18'),
  ('solar_private.cash_movement_detail_v386(text)','b6c72d325a53dbab7a586ca8bcf80cb5'),
  ('solar_private.cash_movements()','2bea4150fbbf10829a5f037ecc9352f8'),
  ('solar_private.fx(text,uuid,jsonb)','46e71d44a59d77bfed31395d9f6b449e'),
  ('solar_private.fx_post()','cd7d7b8298f65fc80b81fff090479dea'),
  ('solar_private.fx_prepare()','d340b4228ec3490a7419fe7115bb9110'),
  ('solar_private.guard_system_pricing()','7037c68db21c88e66005b5154fe466e7'),
  ('solar_private.guard_wholesale_pricing()','045df14f90d9058d50f326d9c408ada5'),
  ('solar_private.inventory_currency_parts(bigint,jsonb,numeric,integer)','1f492b9c49d9b7f48986deaa812e4e98'),
  ('solar_private.invoice_save(uuid,jsonb)','f1b60e9a4ff6e89ca16cb77e043185e2'),
  ('solar_private.purchase_archive_entry(text,bigint)','823aade3199a1781257b208713cf5f05'),
  ('solar_private.purchase_delete(bigint,bigint)','a7b232aacc2046f925db3cd0d1fc3161'),
  ('solar_private.purchase_delete_plan(bigint)','8d44c4b12321e9cc8f7a5964f0ae5ec5'),
  ('solar_private.receipt_delete_context(bigint)','08fa6cadc912ef7f3de291fc3851ea3d'),
  ('solar_private.stamp_system_item_pricing()','35ced12ca4bf602d1f158abb3fd1b290'),
  ('solar_private.stamp_system_pricing()','ff10a32392183d4f6740b0d826f81660'),
  ('solar_private.warehouse_items_changed()','05af9eed14f4f4341052ad6366ef085e'))expected(signature,hash)loop
 if md5(pg_get_functiondef(f.signature::regprocedure))<>f.hash then raise exception 'Accounting function changed before migration: %',f.signature;end if;
 end loop;
end$$;

create table solar_private.purchase_originals(
 invoice_id bigint primary key, invoice jsonb not null, items jsonb not null,
 created_at timestamptz not null default now()
);
create table solar_private.purchase_corrections(
 request_id uuid primary key, invoice_id bigint not null, actor_id uuid not null,
 created_at timestamptz not null default now(), before_invoice jsonb not null,
 before_items jsonb not null, after_invoice jsonb, after_items jsonb,
 plan jsonb not null, ledger jsonb not null default '{}'
);
create index on solar_private.purchase_corrections(invoice_id,created_at);
create table solar_private.purchase_correction_execution(
 request_id uuid primary key references solar_private.purchase_corrections(request_id),
 invoice_id bigint not null, actor_id uuid not null, backend_txid bigint not null
);
alter table solar_private.purchase_originals enable row level security;
alter table solar_private.purchase_corrections enable row level security;
alter table solar_private.purchase_correction_execution enable row level security;
revoke all on solar_private.purchase_originals,solar_private.purchase_corrections,solar_private.purchase_correction_execution from public,anon,authenticated;


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
   if next_q>0 then c:=round(greatest(0,book)/next_q,6);usd:=greatest(0,uv)/next_q;iqd:=greatest(0,iv)/next_q;end if;
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
 anchor timestamptz;event_at timestamptz;first_payload jsonb;first_at timestamptz;rate numeric;parts jsonb;qty numeric;basis jsonb;first_event jsonb;
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
   before_line:=null;
   select i into before_line from solar_private.warehouse_audit a,jsonb_array_elements(a.before_items)i where a.invoice_id=doc.id and a.created_at>=anchor and(i->>'product_id')::bigint=material_id order by a.created_at,a.id limit 1;
   if exists(select 1 from solar_private.invoice_requests r where(r.result->>'id')::bigint=doc.id and r.payload->>'invoiceId' is not null and r.created_at>=anchor)
     and before_line is null then
    raise exception 'تعديل كمية قديم لهذه المادة لا يملك لقطة كلفة كافية؛ تعذر إثبات التسلسل بأمان.' using errcode='PT409';end if;
   if line is not null then
    basis:=coalesce(before_line->'cost_basis',line->'cost_basis','{}');
    if doc.header->>'kind'='purchase' then
     parts:=jsonb_build_object('usd',case when doc.header->>'source_currency'='USD' then coalesce((line->>'source_price')::numeric,(line->>'price')::numeric/(doc.header->>'exchange_rate')::numeric) else 0 end,
      'iqd',case when doc.header->>'source_currency'='USD' then greatest(0,(line->>'landed_cost')::numeric-coalesce((line->>'source_price')::numeric,(line->>'price')::numeric/(doc.header->>'exchange_rate')::numeric)*(doc.header->>'exchange_rate')::numeric) else coalesce(nullif((line->>'landed_cost')::numeric,0),(line->>'price')::numeric) end);
    else parts:=solar_private.inventory_currency_parts(material_id,basis,coalesce((basis->>'bookUnitCost')::numeric,(coalesce(before_line,line)->>'cost')::numeric));end if;
    states:=jsonb_set(states,array[doc.id::text],jsonb_build_object('kind',doc.header->>'kind','qty',(coalesce(before_line,line)->>'qty')::numeric,'cost',(coalesce(before_line,line)->>'cost')::numeric,'book',case when doc.header->>'kind'='purchase'then coalesce(nullif((line->>'landed_cost')::numeric,0),(line->>'price')::numeric)else coalesce((basis->>'bookUnitCost')::numeric,(coalesce(before_line,line)->>'cost')::numeric)end,'parts',parts,'basis',basis,'valuationRate',basis->'valuationRate'),true);
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


-- V4.1.9 append-only purchase account/cash correction helpers.
-- Prerequisite private tables are owned by the consolidated migration:
-- purchase_originals, purchase_corrections, purchase_correction_execution.
-- All mutation helpers are private; only the locked, authorized correction RPC invokes them.

CREATE OR REPLACE FUNCTION solar_private.purchase_correction_ledger_plan(t public.transactions, proposed jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE s public.suppliers; e solar_private.supplier_fx_entries; w solar_private.wallet_fx_entries;
 n numeric; expenses numeric; source_subtotal numeric; r numeric; account_amount numeric; cash_amount numeric;
 d numeric; m numeric; b numeric; v numeric; bd numeric; matched numeric; wallet jsonb;
 cash_delta numeric:=0; cash_book numeric:=0; cash_gain numeric:=0; assigned_amount numeric; assigned_book numeric;
 supplier_before jsonb; cash_before jsonb; token_data jsonb; existing_totals jsonb;
BEGIN
 IF t.id IS NULL OR t.kind<>'purchase' OR NOT t.fx_pricing
  OR (NOT t.fx_accounted AND (t.source_currency,t.account_currency,t.account_revision,t.cash_currency,t.exchange_rate,t.market_rate)
   IS DISTINCT FROM ('IQD'::text,'IQD'::text,0::bigint,'IQD'::text,1::numeric,1::numeric)) THEN
  RAISE EXCEPTION 'بيانات كلفة وحساب الشراء الأصلية غير مكتملة' USING ERRCODE='PT409'; END IF;
 IF NOT solar_private.can_access_invoice(t.created_by,false) OR (NOT solar_private.can_access_invoice(null,false) AND coalesce(t.cashbox_user_id,t.created_by) IS DISTINCT FROM auth.uid()) THEN RAISE EXCEPTION 'الفاتورة غير متاحة' USING ERRCODE='42501'; END IF;
 n:=(proposed->>'total')::numeric; expenses:=(proposed->>'expenses')::numeric; source_subtotal:=(proposed->>'sourceSubtotal')::numeric;
 IF n IS NULL OR expenses IS NULL OR source_subtotal IS NULL OR n<0 OR expenses<0 OR source_subtotal<0
  OR n::text IN('NaN','Infinity','-Infinity') OR expenses::text IN('NaN','Infinity','-Infinity') OR source_subtotal::text IN('NaN','Infinity','-Infinity') THEN
  RAISE EXCEPTION 'مبالغ تصحيح الشراء غير صحيحة' USING ERRCODE='PT422'; END IF;
 SELECT * INTO s FROM public.suppliers WHERE id=t.party_id;
 SELECT * INTO e FROM solar_private.supplier_fx_entries WHERE transaction_id=t.id;
 IF s.id IS NULL OR e.id IS NULL OR s.currency_revision IS DISTINCT FROM t.account_revision OR s.account_currency IS DISTINCT FROM t.account_currency
  OR e.owner_id IS DISTINCT FROM coalesce(t.cashbox_user_id,t.created_by) OR e.supplier_id IS DISTINCT FROM t.party_id OR e.currency IS DISTINCT FROM t.account_currency OR e.revision IS DISTINCT FROM t.account_revision THEN
  RAISE EXCEPTION 'تغيرت عملة حساب المورد أو لم يكتمل القيد الأصلي؛ راجع الحساب قبل تصحيح الوصل' USING ERRCODE='PT409'; END IF;
 existing_totals:=solar_private.purchase_correction_ledger_totals(t.id);
 IF (existing_totals->>'supplierDelta')::numeric IS DISTINCT FROM (CASE WHEN t.cash THEN 0 ELSE t.account_amount END)
  OR (t.cash AND t.cash_currency='IQD' AND (existing_totals->>'cashDelta')::numeric IS DISTINCT FROM -t.total) THEN
  RAISE EXCEPTION 'قيود الشراء والتصحيحات السابقة غير متوازنة' USING ERRCODE='PT409'; END IF;
 r:=t.market_rate;
 IF r IS NULL OR r<=0 OR r::text IN('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'صرف الشراء الأصلي غير صحيح' USING ERRCODE='PT409'; END IF;
 account_amount:=CASE WHEN t.account_currency='USD' THEN CASE WHEN t.source_currency='USD' THEN round(source_subtotal+expenses/r,2) ELSE round(n/r,2) END ELSE n END;
 cash_amount:=CASE WHEN NOT t.cash THEN 0 WHEN t.cash_currency='USD' THEN round(n/r,2) ELSE n END;
 IF n<>0 AND (account_amount=0 OR(t.cash AND cash_amount=0)) THEN RAISE EXCEPTION 'المبلغ أصغر من أصغر وحدة لعملة الحساب' USING ERRCODE='PT422'; END IF;
 SELECT coalesce(sum(x.delta),0),coalesce(sum(x.book_delta),0) INTO b,v FROM solar_private.supplier_fx_entries x WHERE x.supplier_id=t.party_id AND x.revision=t.account_revision;
 supplier_before:=jsonb_build_object('currency',t.account_currency,'balance',b,'book',v);
 d:=CASE WHEN t.cash THEN 0 ELSE account_amount-t.account_amount END;
 m:=CASE WHEN t.cash THEN 0 ELSE n-t.total END;
 -- A rounded zero account-quantity delta cannot revalue other outstanding
 -- debt/credit or leave orphan book at a settled zero balance.
 bd:=CASE WHEN d=0 THEN 0 ELSE m END;
 IF b*d<0 THEN matched:=least(abs(b),abs(d));bd:=round(sign(d)*(matched*abs(v/b)+greatest(abs(d)-abs(b),0)*abs(m/d)),2); END IF;
 IF t.cash THEN
  cash_delta:=CASE WHEN t.cash_currency='USD' THEN t.cash_amount-cash_amount ELSE t.total-n END;
  IF t.cash_currency='USD' THEN
   SELECT * INTO w FROM solar_private.wallet_fx_entries WHERE transaction_id=t.id;
   IF w.id IS NULL OR w.owner_id IS DISTINCT FROM coalesce(t.cashbox_user_id,t.created_by) OR w.currency<>'USD' THEN
    RAISE EXCEPTION 'قيد دولار الشراء الأصلي غير مكتمل' USING ERRCODE='PT409'; END IF;
   SELECT -coalesce(sum(x.delta),0),-coalesce(sum(x.book_delta),0) INTO assigned_amount,assigned_book
   FROM solar_private.wallet_fx_entries x WHERE x.id=w.id OR EXISTS(SELECT 1 FROM solar_private.purchase_corrections c WHERE c.invoice_id=t.id AND c.ledger->>'walletEntryId'=x.id::text);
   IF assigned_amount IS DISTINCT FROM t.cash_amount OR assigned_book<0 THEN RAISE EXCEPTION 'قيود تصحيح قاصة الشراء غير متوازنة' USING ERRCODE='PT409'; END IF;
   wallet:=solar_private.usd_wallet(coalesce(t.cashbox_user_id,t.created_by));
   cash_before:=jsonb_build_object('currency','USD','balance',(wallet->>'amount')::numeric,'book',(wallet->>'book')::numeric);
   IF cash_delta<0 THEN
    IF -cash_delta>(wallet->>'amount')::numeric THEN RAISE EXCEPTION 'رصيد الدولار في قاصة صاحب الوصل لا يكفي لفرق التصحيح' USING ERRCODE='P0002'; END IF;
    cash_book:=CASE WHEN -cash_delta=(wallet->>'amount')::numeric THEN -(wallet->>'book')::numeric ELSE round(cash_delta*(wallet->>'book')::numeric/nullif((wallet->>'amount')::numeric,0),2) END;
   ELSIF cash_delta>0 THEN
    IF cash_delta>assigned_amount THEN RAISE EXCEPTION 'فرق استرداد الشراء يتجاوز المبلغ المسجل' USING ERRCODE='PT409'; END IF;
    cash_book:=CASE WHEN cash_delta=assigned_amount THEN assigned_book ELSE round(cash_delta*assigned_book/nullif(assigned_amount,0),2) END;
   END IF;
   cash_gain:=n-t.total+cash_book;
  ELSE
   cash_before:=jsonb_build_object('currency','IQD','balance',solar_private.cash_balance(coalesce(t.cashbox_user_id,t.created_by)),'book',solar_private.cash_balance(coalesce(t.cashbox_user_id,t.created_by)));
   cash_book:=cash_delta;
  END IF;
 ELSE cash_before:=jsonb_build_object('currency',t.cash_currency,'balance',null,'book',null);
 END IF;
 token_data:=jsonb_build_object('invoiceId',t.id,'revision',t.pricing_revision,'supplierBefore',supplier_before,'cashBefore',cash_before,'total',n,'expenses',expenses,'sourceSubtotal',source_subtotal,'accountAmount',account_amount,'cashAmount',cash_amount);
 RETURN jsonb_build_object('before',jsonb_build_object('total',t.total,'accountAmount',t.account_amount,'cashAmount',t.cash_amount,'supplier',supplier_before,'cash',cash_before),
  'after',jsonb_build_object('total',n,'expenses',expenses,'sourceSubtotal',source_subtotal,'accountAmount',account_amount,'cashAmount',cash_amount,'supplier',supplier_before||jsonb_build_object('balance',b+d,'book',v+bd),'cash',cash_before||jsonb_build_object('balance',(cash_before->>'balance')::numeric+cash_delta,'book',(cash_before->>'book')::numeric+cash_book)),
  'supplierDelta',d,'supplierBookDelta',bd,'supplierGain',m-bd,'cashDelta',cash_delta,'cashBookDelta',cash_book,'cashGain',cash_gain,'fingerprint',md5(token_data::text));
END $fn$;
REVOKE ALL ON FUNCTION solar_private.purchase_correction_ledger_plan(public.transactions,jsonb) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION solar_private.purchase_correction_ledger_apply(request_id uuid, invoice_id bigint, proposed jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
#variable_conflict use_variable
DECLARE t public.transactions; c solar_private.purchase_corrections; plan jsonb; se_id bigint; we_id bigint; uid uuid; note text;
BEGIN
 PERFORM pg_advisory_xact_lock(7311,1);
 SELECT * INTO t FROM public.transactions WHERE id=invoice_id AND kind='purchase' FOR UPDATE;
 SELECT * INTO c FROM solar_private.purchase_corrections x WHERE x.request_id=request_id FOR UPDATE;
 IF t.id IS NULL OR c.request_id IS NULL OR c.invoice_id IS DISTINCT FROM t.id OR c.actor_id IS DISTINCT FROM auth.uid()
  OR c.before_invoice IS DISTINCT FROM to_jsonb(t) OR NOT solar_private.can_access_invoice(t.created_by,false) THEN
  RAISE EXCEPTION 'سياق تصحيح الشراء غير صالح' USING ERRCODE='42501'; END IF;
 IF coalesce(c.ledger,'{}'::jsonb)<>'{}'::jsonb THEN RAISE EXCEPTION 'تم ترحيل هذا التصحيح مسبقاً؛ أعد قراءة نتيجته' USING ERRCODE='PT409'; END IF;
 PERFORM 1 FROM public.suppliers WHERE id=t.party_id FOR UPDATE;
 plan:=solar_private.purchase_correction_ledger_plan(t,proposed);
 uid:=coalesce(t.cashbox_user_id,t.created_by);note:='تصحيح شراء #'||coalesce(t.receipt_no::text,t.id::text);
 IF (plan->>'supplierDelta')::numeric<>0 OR (plan->>'supplierBookDelta')::numeric<>0 OR (plan->>'supplierGain')::numeric<>0 THEN
  INSERT INTO solar_private.supplier_fx_entries(supplier_id,owner_id,currency,revision,delta,book_delta,gain,rate,note)
  VALUES(t.party_id,uid,t.account_currency,t.account_revision,(plan->>'supplierDelta')::numeric,(plan->>'supplierBookDelta')::numeric,(plan->>'supplierGain')::numeric,t.market_rate,note) RETURNING id INTO se_id;
 END IF;
 IF t.cash AND ((plan->>'cashDelta')::numeric<>0 OR (plan->>'cashBookDelta')::numeric<>0 OR (plan->>'cashGain')::numeric<>0) THEN
  INSERT INTO solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,gain,entry_type,note)
  VALUES(uid,t.cash_currency,(plan->>'cashDelta')::numeric,(plan->>'cashBookDelta')::numeric,t.market_rate,(plan->>'cashGain')::numeric,'purchase_correction',note) RETURNING id INTO we_id;
 END IF;
 plan:=plan||jsonb_build_object('supplierEntryId',se_id,'walletEntryId',we_id);
 UPDATE solar_private.purchase_corrections x SET ledger=plan WHERE x.request_id=request_id;
 INSERT INTO solar_private.purchase_correction_execution(request_id,invoice_id,actor_id,backend_txid) VALUES(request_id,invoice_id,auth.uid(),txid_current());
 RETURN plan;
END $fn$;
REVOKE ALL ON FUNCTION solar_private.purchase_correction_ledger_apply(uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION solar_private.purchase_correction_fx_update(old_row public.transactions,new_row public.transactions)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE c solar_private.purchase_corrections; a jsonb;
BEGIN
 SELECT audit.* INTO c FROM solar_private.purchase_correction_execution proof JOIN solar_private.purchase_corrections audit USING(request_id)
 WHERE proof.invoice_id=old_row.id AND proof.actor_id=auth.uid() AND proof.backend_txid=txid_current()
  AND audit.before_invoice=to_jsonb(old_row) AND audit.actor_id=auth.uid();
 IF c.request_id IS NULL THEN RETURN false; END IF;
 a:=c.ledger->'after';
 IF (new_row.party_id,new_row.party_name,new_row.created_by,new_row.cashbox_user_id,new_row.created_at,new_row.kind,new_row.cash,new_row.payment_mode,new_row.source_currency,new_row.exchange_rate,new_row.account_currency,new_row.account_revision,new_row.market_rate,new_row.cash_currency,new_row.warehouse_id,new_row.warehouse_name,new_row.fx_accounted,new_row.fx_pricing)
 IS DISTINCT FROM (old_row.party_id,old_row.party_name,old_row.created_by,old_row.cashbox_user_id,old_row.created_at,old_row.kind,old_row.cash,old_row.payment_mode,old_row.source_currency,old_row.exchange_rate,old_row.account_currency,old_row.account_revision,old_row.market_rate,old_row.cash_currency,old_row.warehouse_id,old_row.warehouse_name,old_row.fx_accounted,old_row.fx_pricing)
 OR (new_row.total,new_row.expenses,new_row.source_subtotal,new_row.account_amount,new_row.cash_amount)
 IS DISTINCT FROM ((a->>'total')::numeric,(a->>'expenses')::numeric,(a->>'sourceSubtotal')::numeric,(a->>'accountAmount')::numeric,(a->>'cashAmount')::numeric) THEN
 RAISE EXCEPTION 'تصحيح الشراء لا يغيّر المورد أو العملة أو القاصة أو المخزن الأصلي' USING ERRCODE='PT409'; END IF;
 RETURN true;
END $fn$;
REVOKE ALL ON FUNCTION solar_private.purchase_correction_fx_update(public.transactions,public.transactions) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION solar_private.purchase_correction_ledger_totals(invoice_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 WITH t AS(SELECT live.*,coalesce(o.invoice,to_jsonb(live)) original FROM public.transactions live LEFT JOIN solar_private.purchase_originals o ON o.invoice_id=live.id WHERE live.id=$1),
 se AS(SELECT x.* FROM solar_private.supplier_fx_entries x WHERE x.transaction_id=$1 OR EXISTS(SELECT 1 FROM solar_private.purchase_corrections c WHERE c.invoice_id=$1 AND c.ledger->>'supplierEntryId'=x.id::text)),
 we AS(SELECT x.delta,x.book_delta,x.gain FROM solar_private.wallet_fx_entries x WHERE x.transaction_id=$1 OR EXISTS(SELECT 1 FROM solar_private.purchase_corrections c WHERE c.invoice_id=$1 AND c.ledger->>'walletEntryId'=x.id::text)
 UNION ALL SELECT -(original->>'total')::numeric,-(original->>'total')::numeric,0 FROM t WHERE cash AND cash_currency='IQD')
 SELECT jsonb_build_object('supplierDelta',(SELECT coalesce(sum(delta),0)FROM se),'supplierBookDelta',(SELECT coalesce(sum(book_delta),0)FROM se),'supplierGain',(SELECT coalesce(sum(gain),0)FROM se),'cashDelta',(SELECT coalesce(sum(delta),0)FROM we),'cashBookDelta',(SELECT coalesce(sum(book_delta),0)FROM we),'cashGain',(SELECT coalesce(sum(gain),0)FROM we))
$fn$;
REVOKE ALL ON FUNCTION solar_private.purchase_correction_ledger_totals(bigint) FROM PUBLIC,anon,authenticated;

-- Preserve original dated projections; append correction movements separately.
CREATE OR REPLACE FUNCTION solar_private.fx_prepare()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx jsonb:=coalesce(nullif(current_setting('solar.fx_context',true),'')::jsonb,'{}');s public.suppliers;
 prior solar_private.supplier_fx_entries;w solar_private.wallet_fx_entries;r numeric;wallet jsonb;refund numeric:=0;
begin
 if tg_op='UPDATE' then
  if old.kind='purchase' and solar_private.purchase_correction_fx_update(old,new) then return new;end if;
 end if;
 if tg_op='UPDATE' and new.supplier_payment_voided_at is not null and new.supplier_payment_voided_at is distinct from old.supplier_payment_voided_at and (to_jsonb(new)-'supplier_payment_voided_at'-'supplier_payment_replaced_by')=(to_jsonb(old)-'supplier_payment_voided_at'-'supplier_payment_replaced_by') then return new;end if;
 if coalesce(case when tg_op='DELETE' then old.kind else new.kind end,'') not in ('purchase','supplier_payment') then
  if tg_op='DELETE' then return old;end if;return new;
 end if;
 perform pg_advisory_xact_lock(7311,1);
 if tg_op<>'DELETE' then
  select * into s from public.suppliers where id=new.party_id;
  if s.id is null and new.party_id is null then
   select * into s from public.suppliers where solar_private.customer_name_key(name)=solar_private.customer_name_key(new.party_name)
    and (select count(*) from public.suppliers z where solar_private.customer_name_key(z.name)=solar_private.customer_name_key(new.party_name))=1;
  end if;
  if s.id is null and ctx<>'{}' then raise exception 'اختر المورد المسجّل قبل حفظ الشراء';end if;
  if s.id is not null then
   if ctx<>'{}' then
    if (ctx->>'accountRevision')::bigint is distinct from s.currency_revision then raise exception 'تغيرت عملة المورد؛ حدّث البيانات قبل الحفظ' using errcode='PT409';end if;
    r:=solar_private.fx_rate((ctx->>'marketRate')::numeric,case when tg_op='UPDATE' then old.market_rate end);
    if new.kind='purchase' and new.source_currency='USD' and new.exchange_rate<>r then raise exception 'صرف كلفة الشراء يجب أن يطابق الصرف المثبت للحساب';end if;
    new.fx_accounted:=true;new.party_id:=s.id;new.account_currency:=s.account_currency;new.account_revision:=s.currency_revision;new.market_rate:=r;
    new.account_amount:=case when s.account_currency='USD' then round(new.total/r,2) else new.total end;
    new.cash_currency:=case when new.cash then coalesce(ctx->>'cashCurrency','IQD') else 'IQD' end;
    if new.cash_currency not in ('USD','IQD') then raise exception 'عملة التسديد غير صحيحة';end if;
    new.cash_amount:=case when not new.cash then 0 when new.cash_currency='USD' then round(new.total/r,2) else new.total end;
    if new.source_currency='USD' and new.kind='supplier_payment' and new.cash then new.cash_amount:=new.source_subtotal;end if;
    if new.source_currency='USD' and s.account_currency='USD' then
     new.account_amount:=case when new.kind='supplier_payment' then new.source_subtotal else round(new.source_subtotal+new.expenses/r,2) end;
    end if;
    if new.total<>0 and new.account_amount=0 then raise exception 'المبلغ المحوّل أصغر من أصغر وحدة لعملة الحساب';end if;
   elsif s.account_currency<>'IQD' or s.currency_revision<>0 or (tg_op='UPDATE' and old.fx_accounted) then
    raise exception 'حدّث البرنامج لاستخدام عملة حساب المورد';
   else new.account_amount:=new.total;new.cash_amount:=case when new.cash then new.total else 0 end;
   end if;
  end if;
  if tg_op='UPDATE' and old.cash and new.cash and new.cash_currency is distinct from old.cash_currency then raise exception 'عملة القاصة لوصل محفوظ ثابتة؛ سجّل تصحيحاً مستقلاً';end if;
  if tg_op='UPDATE' and (new.party_id,new.total,new.cash,new.payment_mode,new.account_currency,new.account_amount,new.account_revision,new.market_rate,new.cash_currency,new.cash_amount)
   is not distinct from (old.party_id,old.total,old.cash,old.payment_mode,old.account_currency,old.account_amount,old.account_revision,old.market_rate,old.cash_currency,old.cash_amount) then return new;end if;
 end if;
 if tg_op<>'INSERT' then
  select * into prior from solar_private.supplier_fx_entries where transaction_id=old.id;
  if prior.id is not null and exists(select 1 from solar_private.supplier_fx_entries e where e.supplier_id=prior.supplier_id and e.id>prior.id) then raise exception 'لهذا الوصل حركات مورد لاحقة؛ سجّل حركة تصحيح مستقلة لحفظ تسلسل الحساب';end if;
  select * into w from solar_private.wallet_fx_entries where transaction_id=old.id;
  if w.id is not null and exists(select 1 from solar_private.wallet_fx_entries e where e.owner_id=w.owner_id and e.currency='USD' and e.id>w.id) then raise exception 'لهذا الوصل حركات دولار لاحقة؛ لا يمكن إعادة تسعير القاصة';end if;
  if old.cash and old.cash_currency='IQD' then refund:=old.total;end if;
  delete from solar_private.supplier_fx_entries where transaction_id=old.id;
  delete from solar_private.wallet_fx_entries where transaction_id=old.id;
 end if;
 if tg_op='DELETE' then return old;end if;
 if new.cash then
  if new.cash_currency='USD' then
   wallet:=solar_private.usd_wallet(coalesce(new.cashbox_user_id,new.created_by));
   if new.cash_amount>(wallet->>'amount')::numeric then raise exception 'رصيد الدولار في قاصة صاحب الوصل لا يكفي' using errcode='P0002';end if;
  elsif new.kind<>'purchase' and new.total>solar_private.cash_balance(coalesce(new.cashbox_user_id,new.created_by))+refund then raise exception 'رصيد الدينار في قاصة صاحب الوصل لا يكفي' using errcode='P0002';end if;
 end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.fx_post()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare b numeric;v numeric;d numeric;m numeric;bd numeric;matched numeric;uid uuid;wallet jsonb;cashbook numeric;sid bigint;
begin
 if tg_op='UPDATE' then
  if old.kind='purchase' and solar_private.purchase_correction_fx_update(old,new) then return new;end if;
 end if;
 if new.kind not in ('purchase','supplier_payment') then return new;end if;
 if exists(select 1 from solar_private.supplier_fx_entries where transaction_id=new.id) then return new;end if;
 uid:=coalesce(new.cashbox_user_id,new.created_by);sid:=new.party_id;
 if sid is null then select id into sid from public.suppliers where solar_private.customer_name_key(name)=solar_private.customer_name_key(new.party_name) and(select count(*) from public.suppliers s where solar_private.customer_name_key(s.name)=solar_private.customer_name_key(new.party_name))=1;end if;
 cashbook:=new.total;
 if new.cash and new.cash_currency='USD' then
  wallet:=solar_private.usd_wallet(uid);
  cashbook:=case when new.cash_amount=(wallet->>'amount')::numeric then (wallet->>'book')::numeric else round(new.cash_amount*(wallet->>'book')::numeric/nullif((wallet->>'amount')::numeric,0),2) end;
  insert into solar_private.wallet_fx_entries(owner_id,transaction_id,currency,delta,book_delta,rate,gain,entry_type,created_at)
   values(uid,new.id,'USD',-new.cash_amount,-cashbook,new.market_rate,case when new.kind='purchase' then new.total-cashbook else 0 end,'supplier_cash',new.created_at);
 end if;
 if sid is null then return new;end if;
 d:=case when new.kind='supplier_payment' then -new.account_amount when new.cash then 0 else new.account_amount end;
 m:=case when new.kind='supplier_payment' then case when new.cash then -cashbook else -new.total end when new.cash then 0 else new.total end;
 select coalesce(sum(delta),0),coalesce(sum(book_delta),0) into b,v from solar_private.supplier_fx_entries where supplier_id=sid and revision=new.account_revision;
 bd:=m;
 if b*d<0 then
  matched:=least(abs(b),abs(d));
  bd:=round(sign(d)*(matched*abs(v/b)+greatest(abs(d)-abs(b),0)*abs(m/d)),2);
 end if;
 insert into solar_private.supplier_fx_entries(supplier_id,owner_id,transaction_id,currency,revision,delta,book_delta,gain,rate,created_at)
 values(sid,uid,new.id,new.account_currency,new.account_revision,d,bd,m-bd,new.market_rate,new.created_at);
 return new;
end $function$;

CREATE OR REPLACE FUNCTION solar_private.cash_balance(uid uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce((select sum(case when t.kind in ('purchase','supplier_payment','cash_expense','profit_distribution') then -coalesce((original.invoice->>'total')::numeric,t.total) else t.total end)
 from public.transactions t left join solar_private.purchase_originals original on original.invoice_id=t.id where t.cash and t.cash_currency='IQD' and coalesce(t.cashbox_user_id,t.created_by)=uid),0)
 +coalesce((select sum(e.delta) from public.solar_cash_entries e where e.owner_id=uid),0)
 +coalesce((select sum(e.delta) from solar_private.wallet_fx_entries e where e.owner_id=uid and e.currency='IQD'),0)
$function$;

CREATE OR REPLACE FUNCTION solar_private.cash_movements()
 RETURNS TABLE(id text, owner_id uuid, currency text, delta numeric, book_delta numeric, kind text, party text, note text, receipt_no bigint, rate numeric, source_currency text, source_amount numeric, created_at timestamp with time zone, request_id uuid)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select 'tx:'||t.id,coalesce(t.cashbox_user_id,t.created_by),t.cash_currency,
  (case when t.kind in ('purchase','supplier_payment','cash_expense','profit_distribution') then -1 else 1 end)*case when t.cash_currency='USD' then t.cash_amount else t.total end,
  case when t.cash_currency='USD' then coalesce(w.book_delta,0) else(case when t.kind in ('purchase','supplier_payment','cash_expense','profit_distribution') then -t.total else t.total end) end,
  case t.cash_purpose when 'external_profit' then 'external_profit' when 'capital' then 'capital_deposit' when 'withdrawal' then 'capital_withdraw' when 'expense' then 'expense' else t.kind end,coalesce(t.party_name,''),coalesce(t.notes,''),t.receipt_no,t.market_rate,t.source_currency,coalesce(t.source_subtotal,t.total),t.created_at,t.finance_request_id
 from public.transactions live left join solar_private.purchase_originals original on original.invoice_id=live.id cross join lateral jsonb_populate_record(null::public.transactions,coalesce(original.invoice,to_jsonb(live))) t left join solar_private.wallet_fx_entries w on w.transaction_id=t.id where t.cash
 union all select 'entry:'||e.id,e.owner_id,'IQD',e.delta,e.delta,e.entry_type,coalesce(j.party_name,''),e.notes,j.receipt_no,1,'IQD',abs(e.delta),e.created_at,null::uuid from public.solar_cash_entries e left join lateral(select live.* from public.transactions live where live.id=e.job_id union all select (jsonb_populate_record(null::public.transactions,ds.invoice)).* from solar_private.deleted_sales ds where ds.invoice_id=e.deleted_job_id)j on true
 union all select 'fx:'||e.id,e.owner_id,e.currency,e.delta,e.book_delta,
  case when ap.summary->>'entryRole'='original' then 'purchase_cancelled' else e.entry_type end,
  case when ap.summary is not null then coalesce(ap.summary->>'party','') when fr.action='admin_cash_transfer' then case when e.entry_type='admin_transfer_out' then 'إلى '||coalesce(fr.response->>'recipientName','') else 'من '||coalesce(fr.response->>'senderName','') end else '' end,
  case when ap.summary->>'entryRole'='original' then 'شراء ملغى #'||coalesce(ap.summary->>'receiptNo',ap.summary->>'id')||case when coalesce(ap.summary->>'notes','')<>'' then ' · '||(ap.summary->>'notes')else '' end else e.note end,
  coalesce((ap.summary->>'receiptNo')::bigint,(fr.response->>'receiptNo')::bigint),e.rate,e.currency,abs(e.delta),e.created_at,e.finance_request_id
  from solar_private.wallet_fx_entries e left join solar_private.finance_requests fr on fr.request_id=e.finance_request_id
  left join lateral(select solar_private.purchase_archive_entry('wallet',e.id)summary offset 0)ap on true
  where e.transaction_id is null
$function$;

CREATE OR REPLACE FUNCTION solar_private.purchase_archive_entry(entry_source text, entry_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor public.profiles;se solar_private.supplier_fx_entries;we solar_private.wallet_fx_entries;
 archived jsonb;cancelled_at timestamptz;entry_role text;
begin
 select * into actor from public.profiles where id=auth.uid() and active and user_type not in('installer','warehouse');
 if actor.id is null then return null;end if;
 if entry_source='supplier' then
  select * into se from solar_private.supplier_fx_entries where id=entry_id and transaction_id is null;
  if se.id is null or(not actor.is_admin and se.owner_id is distinct from actor.id)then return null;end if;
  if se.correction_for is not null then
   select d.invoice,d.deleted_at,'reversal' into archived,cancelled_at,entry_role
   from solar_private.deleted_sales d where d.invoice_id=se.correction_for and d.invoice->>'kind'='purchase'
    and d.invoice#>>'{purchaseCancellation,supplierReversalId}'=se.id::text;
  else
   select d.invoice,d.deleted_at,'original' into archived,cancelled_at,entry_role
   from solar_private.deleted_sales d where d.invoice->>'kind'='purchase' and d.invoice?'purchaseCancellation'
    and d.invoice#>>'{purchaseCancellation,supplierEntry,id}'=se.id::text;
  end if;
 elsif entry_source='wallet' then
  select * into we from solar_private.wallet_fx_entries where id=entry_id and transaction_id is null;
  if we.id is null or(not actor.is_admin and we.owner_id is distinct from actor.id)then return null;end if;
  select matched.invoice,matched.deleted_at,matched.entry_role into archived,cancelled_at,entry_role
  from(
   select d.invoice,d.deleted_at,'original'::text entry_role from solar_private.deleted_sales d
   where d.invoice->>'kind'='purchase' and d.invoice?'purchaseCancellation'
    and d.invoice#>>'{purchaseCancellation,walletEntry,id}'=we.id::text
   union all
   select d.invoice,d.deleted_at,'reversal'::text from solar_private.deleted_sales d
   where d.invoice->>'kind'='purchase' and d.invoice?'purchaseCancellation'
    and d.invoice#>>'{purchaseCancellation,walletReversalId}'=we.id::text
  )matched;
 else return null;end if;
 -- A detached correction is still linked to its receipt for visibility checks,
 -- including after cancellation; no unrestricted foreign receipt metadata.
 if archived is null then
  select coalesce(nullif(c.after_invoice,'{}'::jsonb),c.before_invoice),d.deleted_at,'correction'
  into archived,cancelled_at,entry_role
  from solar_private.purchase_corrections c left join solar_private.deleted_sales d on d.invoice_id=c.invoice_id
  where c.ledger->>case when entry_source='supplier' then 'supplierEntryId' else 'walletEntryId' end=entry_id::text;
 end if;
 if archived is null then return null;end if;
 return jsonb_build_object('id',archived->'id','receiptNo',archived->'receipt_no','party',archived->'party_name',
  'notes',archived->'notes','originalKind','purchase','cancelledAt',cancelled_at,'entryRole',entry_role);
end$function$;

-- CORE INTEGRATION: replace stock-cost residual branch below with replay deletion plan.
CREATE OR REPLACE FUNCTION solar_private.purchase_delete_plan(invoice_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor public.profiles;t public.transactions;p public.products;s public.suppliers;
 e solar_private.supplier_fx_entries;w solar_private.wallet_fx_entries;stock solar_private.warehouse_stocks;
 snap jsonb;totals jsonb;corrected boolean;line record;parts jsonb;next_basis jsonb;rows jsonb:='[]';
 next_qty numeric;next_cost numeric;book_value numeric;usd_value numeric;iqd_value numeric;tolerance numeric;
begin
 select * into actor from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 select * into t from public.transactions where id=invoice_id and kind='purchase';
 if actor.id is null or t.id is null or(not actor.is_admin and t.created_by is distinct from actor.id) then
  raise exception 'الفاتورة غير متاحة ضمن صلاحياتك' using errcode='42501';end if;
 if not t.fx_pricing or jsonb_array_length(t.purchase_stock)=0
  or jsonb_array_length(t.purchase_stock)<>(select count(distinct i.product_id) from public.transaction_items i where i.transaction_id=t.id)
  or exists(select 1 from public.transaction_items i where i.transaction_id=t.id and i.product_id is null) then
  raise exception 'كلفة الشراء الأصلية غير مكتملة؛ راجع الوصل قبل إلغائه' using errcode='PT409';end if;
 select * into e from solar_private.supplier_fx_entries where transaction_id=t.id;
 if e.id is not null then
  select * into s from public.suppliers where id=e.supplier_id;
  if s.id is null or s.currency_revision is distinct from e.revision or s.account_currency is distinct from e.currency then
   raise exception 'تغيرت عملة حساب المورد بعد هذا الشراء؛ يلزم تصحيح الحساب بالعملة الحالية قبل إلغاء الوصل' using errcode='PT409';end if;
 elsif t.fx_accounted then
  raise exception 'قيد حساب المورد غير مكتمل؛ راجع الوصل قبل إلغائه' using errcode='PT409';
 end if;
 totals:=solar_private.purchase_correction_ledger_totals(t.id);
 corrected:=exists(select 1 from solar_private.purchase_corrections c where c.invoice_id=t.id);
 select * into w from solar_private.wallet_fx_entries where transaction_id=t.id;
 if t.cash and t.cash_currency='USD' then
  if w.id is null or w.currency is distinct from 'USD' or w.owner_id is distinct from coalesce(t.cashbox_user_id,t.created_by)
   or (totals->>'cashDelta')::numeric is distinct from -t.cash_amount or (totals->>'cashBookDelta')::numeric>0 then
   raise exception 'قيد دولار الشراء غير متوازن؛ راجع الوصل قبل إلغائه' using errcode='PT409';end if;
 elsif w.id is not null then raise exception 'للشراء قيد قاصة غير متوقع؛ راجعه قبل الإلغاء' using errcode='PT409';end if;
 for line in
  select i.product_id,sum(i.qty) qty,sum(i.qty*case when i.landed_cost>0 then i.landed_cost else i.price end) book,
   sum(i.qty*case when t.source_currency='USD' then coalesce(i.source_price,i.price/t.exchange_rate) else 0 end) usd,
   sum(i.qty*case when t.source_currency='USD' then greatest(0,(case when i.landed_cost>0 then i.landed_cost else i.price end)-coalesce(i.source_price,i.price/t.exchange_rate)*t.exchange_rate)
    else case when i.landed_cost>0 then i.landed_cost else i.price end end) iqd
  from public.transaction_items i where i.transaction_id=t.id group by i.product_id order by i.product_id
 loop
  select * into p from public.products where id=line.product_id;
  select * into stock from solar_private.warehouse_stocks where warehouse_id=t.warehouse_id and product_id=line.product_id;
  select value into snap from jsonb_array_elements(t.purchase_stock) where(value->>'id')::bigint=line.product_id;
  if p.id is null or snap is null or not(line.qty>0) then raise exception 'بيانات مادة الشراء غير مكتملة' using errcode='PT409';end if;
  if coalesce(stock.qty,0)<line.qty or p.qty<line.qty then
   raise exception 'لا يمكن إلغاء شراء مادة «%»: المطلوب % والمتاح غير المحجوز في «%» %. أعد الكمية إلى مخزن الوصل أو أكمل معالجة حجزها أولًا.',
    p.name,line.qty,t.warehouse_name,coalesce(stock.qty,0) using errcode='PT409';end if;
  next_qty:=p.qty-line.qty;
  if not corrected and p.costing_revision=(snap->>'afterRevision')::bigint and next_qty=(snap->>'qty')::numeric then
   next_cost:=(snap->>'cost')::numeric;next_basis:=snap->'basis';
  else
   parts:=solar_private.inventory_currency_parts(p.id,p.cost_basis,p.cost);
   book_value:=p.qty*p.cost-line.book;
   usd_value:=p.qty*(parts->>'usd')::numeric-line.usd;
   iqd_value:=p.qty*(parts->>'iqd')::numeric-line.iqd;
   -- Unit book costs are stored rounded to six places. Only forgive their
   -- possible accumulated rounding error, never a real negative valuation.
   tolerance:=greatest(.00001,(p.qty+line.qty)*.0000005);
   if book_value < -tolerance or iqd_value < -tolerance or usd_value < -.00001
    or(next_qty=0 and(abs(book_value)>tolerance or abs(iqd_value)>tolerance or abs(usd_value)>.00001)) then
    raise exception 'إلغاء شراء مادة «%» يترك فرق كلفة مرتبطًا بالحركات اللاحقة؛ يلزم تصحيح الكلفة قبل الإلغاء.',p.name using errcode='PT409';end if;
   if next_qty>0 then
    next_cost:=round(greatest(0,book_value)/next_qty,6);
    next_basis:=jsonb_build_object('method','purchase-cancellation','unitCost',next_cost,'cancelledPurchaseId',t.id,
     'currencyComponents',jsonb_build_object('usd',greatest(0,usd_value)/next_qty,'iqd',greatest(0,iqd_value)/next_qty));
   else
    next_cost:=(snap->>'cost')::numeric;next_basis:=snap->'basis';
   end if;
  end if;
  rows:=rows||jsonb_build_array(jsonb_build_object('id',p.id,'name',p.name,'quantity',line.qty,
   'before',jsonb_build_object('qty',p.qty,'cost',p.cost,'basis',p.cost_basis,'revision',p.costing_revision),
   'after',jsonb_build_object('qty',next_qty,'cost',next_cost,'basis',next_basis),
   'warehouseBefore',to_jsonb(stock),'warehouseAfter',stock.qty-line.qty));
 end loop;
 return jsonb_build_object('warehouseId',t.warehouse_id,'warehouseName',t.warehouse_name,'items',rows,
  'cashRefund',case when t.cash then -(totals->>'cashDelta')::numeric else 0 end,'ledgerTotals',totals,'corrected',corrected,
  'cashCurrency',t.cash_currency,'accountCurrency',e.currency,'accountEffect',-(totals->>'supplierDelta')::numeric,
  'supplierEntry',to_jsonb(e),'walletEntry',to_jsonb(w));
end$function$
;

CREATE OR REPLACE FUNCTION solar_private.purchase_delete(invoice_id bigint, expected_revision bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET lock_timeout='5s' AS $function$
DECLARE actor public.profiles;t public.transactions;plan jsonb;item jsonb;original_items jsonb;original jsonb;totals jsonb;corrected boolean;
 e solar_private.supplier_fx_entries;w solar_private.wallet_fx_entries;reversal_id bigint;wallet_reversal_id bigint;note text;
BEGIN
 SELECT * INTO actor FROM public.profiles WHERE id=auth.uid() AND active AND user_type NOT IN('warehouse','installer');
 IF actor.id IS NULL OR NOT solar_private.receipt_delete_authorized(invoice_id) THEN RAISE EXCEPTION 'استخدم الحذف المباشر المصرح به أو موافقة طلب الحذف' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(7311,1);
 SELECT * INTO t FROM public.transactions WHERE id=invoice_id AND kind='purchase' FOR UPDATE;
 IF t.id IS NULL OR NOT solar_private.can_access_invoice(t.created_by,false) THEN RAISE EXCEPTION 'الفاتورة غير متاحة' USING ERRCODE='42501'; END IF;
 IF t.pricing_revision IS DISTINCT FROM expected_revision THEN RAISE EXCEPTION 'تغيرت الفاتورة؛ حدّث البيانات' USING ERRCODE='PT409'; END IF;
 PERFORM 1 FROM public.products p WHERE p.id IN(SELECT i.product_id FROM public.transaction_items i WHERE i.transaction_id=t.id) ORDER BY p.id FOR UPDATE;
 PERFORM 1 FROM solar_private.warehouse_stocks s WHERE s.warehouse_id=t.warehouse_id AND s.product_id IN(SELECT i.product_id FROM public.transaction_items i WHERE i.transaction_id=t.id) ORDER BY s.product_id FOR UPDATE;
 SELECT * INTO e FROM solar_private.supplier_fx_entries WHERE transaction_id=t.id FOR UPDATE;
 IF e.id IS NOT NULL THEN PERFORM 1 FROM public.suppliers WHERE id=e.supplier_id FOR UPDATE;END IF;
 SELECT * INTO w FROM solar_private.wallet_fx_entries WHERE transaction_id=t.id FOR UPDATE;
 plan:=solar_private.purchase_delete_plan(t.id);totals:=plan->'ledgerTotals';corrected:=coalesce((plan->>'corrected')::boolean,false);
 SELECT coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') INTO original_items FROM public.transaction_items i WHERE i.transaction_id=t.id;
 IF t.cash AND t.cash_currency='IQD' AND EXISTS(SELECT 1 FROM solar_private.purchase_originals o WHERE o.invoice_id=t.id) THEN
  SELECT invoice INTO original FROM solar_private.purchase_originals WHERE purchase_originals.invoice_id=t.id;
  IF original IS NULL THEN RAISE EXCEPTION 'لقطة القاصة الأصلية غير متاحة' USING ERRCODE='PT409';END IF;
  -- Preserve the old dated IQD debit when its mutable transaction is removed.
  -- Existing correction rows stay unchanged; one present-time cumulative refund follows.
  INSERT INTO solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,gain,entry_type,note,created_at)
  VALUES(coalesce(t.cashbox_user_id,t.created_by),'IQD',-(original->>'total')::numeric,-(original->>'total')::numeric,(original->>'market_rate')::numeric,0,'supplier_cash','شراء ملغى #'||coalesce(t.receipt_no::text,t.id::text),(original->>'created_at')::timestamptz) RETURNING * INTO w;
  plan:=plan||jsonb_build_object('walletEntry',to_jsonb(w));
 END IF;
 INSERT INTO solar_private.deleted_sales(invoice_id,invoice,items,deleted_by)
 VALUES(t.id,to_jsonb(t)||jsonb_build_object('purchaseCancellation',plan),original_items,actor.id);
 note:='إلغاء شراء #'||coalesce(t.receipt_no::text,t.id::text)||' · '||coalesce(t.party_name,'');
 IF e.id IS NOT NULL THEN
  UPDATE solar_private.supplier_fx_entries SET transaction_id=NULL WHERE id=e.id;
  INSERT INTO solar_private.supplier_fx_entries(supplier_id,owner_id,currency,revision,delta,book_delta,gain,rate,note,correction_for)
  VALUES(e.supplier_id,e.owner_id,e.currency,e.revision,-(totals->>'supplierDelta')::numeric,-(totals->>'supplierBookDelta')::numeric,-(totals->>'supplierGain')::numeric,e.rate,note,t.id) RETURNING id INTO reversal_id;
 END IF;
 IF w.id IS NOT NULL THEN
  UPDATE solar_private.wallet_fx_entries SET transaction_id=NULL WHERE id=w.id;
  INSERT INTO solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,gain,entry_type,note)
  VALUES(w.owner_id,w.currency,-(totals->>'cashDelta')::numeric,-(totals->>'cashBookDelta')::numeric,w.rate,-(totals->>'cashGain')::numeric,'purchase_refund',note) RETURNING id INTO wallet_reversal_id;
 END IF;
 -- CORE INTEGRATION: apply the replay plan and affected sale costs atomically here;
 -- the placeholder below preserves the prior plan's per-product application contract.
 FOR item IN SELECT value FROM jsonb_array_elements(plan->'items') LOOP
  UPDATE public.products SET qty=(item->'after'->>'qty')::numeric,cost=(item->'after'->>'cost')::numeric,cost_basis=item->'after'->'basis' WHERE id=(item->>'id')::bigint;
 END LOOP;
 UPDATE solar_private.deleted_sales d SET invoice=d.invoice||jsonb_build_object('purchaseCancellation',plan||jsonb_build_object('supplierReversalId',reversal_id,'walletReversalId',wallet_reversal_id)) WHERE d.invoice_id=t.id;
 DELETE FROM public.cash_ledger WHERE transaction_id=t.id;
 DELETE FROM public.transactions WHERE id=t.id;
END $function$;
-- Existing purchase_delete ACL is intentionally preserved; its private execution proof still guards every call.

-- Original cash receipt details must match its frozen original debit.
CREATE OR REPLACE FUNCTION solar_private.cash_movement_detail_v386(movement_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles;m record;t public.transactions;entry public.solar_cash_entries;
 handover solar_private.cash_transfers;fr solar_private.finance_requests;actor uuid;actor_name text;actor_phone text;
 balance_after numeric;original jsonb;original_items jsonb;document jsonb;items jsonb:='[]';transfer_info jsonb;exchange_info jsonb;reconciliation jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 if p.id is null or not solar_private.cash_allowed('view') then raise exception 'لا تملك صلاحية الصندوق' using errcode='42501';end if;
 if movement_id is null or length(movement_id)>100 then raise exception 'الحركة غير متاحة' using errcode='42501';end if;
 select x.*,coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'قيد التسليم') owner_name into m
 from solar_private.cash_movements() x left join public.profiles o on o.id=x.owner_id
 where x.id=movement_id and(p.is_admin or x.owner_id=p.id);
 if not found then raise exception 'الحركة غير متاحة ضمن صلاحياتك' using errcode='42501';end if;
 select coalesce(sum(x.delta),0) into balance_after from solar_private.cash_movements() x
 where x.owner_id is not distinct from m.owner_id and x.currency=m.currency and(x.created_at,x.id)<=(m.created_at,m.id);
 if m.request_id is not null then select * into fr from solar_private.finance_requests f where f.request_id=m.request_id;actor:=fr.actor_id;end if;
 if m.id like 'tx:%' then
  select * into t from public.transactions where id=split_part(m.id,':',2)::bigint;
  select o.invoice,o.items into original,original_items from solar_private.purchase_originals o where o.invoice_id=t.id;
  if original is not null then select * into t from jsonb_populate_record(null::public.transactions,original);end if;
  actor:=t.created_by;
  document:=jsonb_build_object('kind',t.kind,'receiptNo',t.receipt_no,'paymentMode',t.payment_mode,'warehouse',t.warehouse_name);
  select coalesce(jsonb_agg(jsonb_build_object('name',i.product_name,'brand',case when original_items is not null then i.brand_name else solar_private.current_product_brand(i.product_id,i.brand_name) end,'category',i.category,
   'qty',i.qty,'price',i.price,'total',round(i.qty*i.price,2)) order by i.id),'[]') into items from jsonb_populate_recordset(null::public.transaction_items,coalesce(original_items,(select jsonb_agg(to_jsonb(current_item)order by current_item.id)from public.transaction_items current_item where current_item.transaction_id=t.id),'[]'::jsonb)) i;
 elsif m.id like 'entry:%' then
  select * into entry from public.solar_cash_entries where id=split_part(m.id,':',2)::uuid;actor:=entry.actor_id;
  if entry.transfer_id is not null then
   select * into handover from solar_private.cash_transfers where id=entry.transfer_id;
   transfer_info:=jsonb_build_object('sender',(select solar_private.user_name(display_name,username,honorific) from public.profiles where id=handover.sender_id),
    'recipient',(select solar_private.user_name(display_name,username,honorific) from public.profiles where id=handover.recipient_id),'amount',handover.amount,
    'expense',handover.expense,'expenseNote',handover.expense_note,'note',handover.notes,'status',handover.status,'decidedAt',handover.decided_at,
    'decidedBy',(select solar_private.user_name(display_name,username,honorific) from public.profiles where id=handover.decided_by));
  elsif entry.job_id is not null then
   select * into t from public.transactions where id=entry.job_id;
   document:=jsonb_build_object('kind',t.kind,'receiptNo',t.receipt_no,'warehouse',t.warehouse_name);
  elsif entry.deleted_job_id is not null then
   select (jsonb_populate_record(null::public.transactions,d.invoice)).* into t from solar_private.deleted_sales d where d.invoice_id=entry.deleted_job_id;
   document:=jsonb_build_object('kind',t.kind,'receiptNo',t.receipt_no,'warehouse',t.warehouse_name,'deleted',true);
  end if;
 end if;
 select solar_private.user_name(display_name,username,honorific),phone into actor_name,actor_phone from public.profiles where id=actor;
 if m.kind='cash_reconcile' then
  reconciliation:=solar_private.cash_reconciliation_info(m.request_id,m.owner_id);
  -- The saved reconciliation is authoritative even for legacy rows sharing a timestamp.
  if reconciliation is not null then balance_after:=(reconciliation->>('after'||m.currency))::numeric;end if;
 end if;
 if fr.payload->>'mode' in('buy_usd','sell_usd') and fr.response->>'ownerId'=m.owner_id::text then
  exchange_info:=jsonb_build_object('mode',fr.payload->>'mode','amount',fr.response->'amount','rate',fr.response->'rate',
   'beforeIQD',fr.response->'beforeIQD','afterIQD',fr.response->'afterIQD','beforeUSD',fr.response->'beforeUSD','afterUSD',fr.response->'afterUSD');
 end if;
 return jsonb_build_object('id',m.id,'ownerId',m.owner_id,'ownerName',m.owner_name,'currency',m.currency,'kind',m.kind,
  'date',m.created_at,'receiptNo',m.receipt_no,'delta',m.delta,'amount',abs(m.delta),'before',balance_after-m.delta,'after',balance_after,
  'party',m.party,'note',m.note,'sourceCurrency',m.source_currency,'sourceAmount',m.source_amount,'rate',m.rate,
  'actorName',actor_name,'actorPhone',actor_phone,'document',document,'items',items,'transfer',transfer_info,
  'reconciliation',reconciliation,'exchange',exchange_info);
end$function$;

-- A correction remains a correction in supplier statements, even after cancellation.
CREATE OR REPLACE FUNCTION solar_private.fx(action text, request_id uuid DEFAULT NULL::uuid, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
#variable_conflict use_variable
declare p public.profiles;s public.suppliers;t public.transactions;prior solar_private.fx_requests;result jsonb;
 rows jsonb;before_row jsonb;uid uuid;sid bigint;tid bigint;r numeric;amt numeric;cur text;mode text;
 b numeric;v numeric;wd numeric;wb numeric;gain numeric:=0;revision bigint;owner record;token text;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') then raise exception 'غير مسموح' using errcode='42501';end if;
 if action='wallet' and payload->>'mode' in('deposit','withdraw') and not solar_private.cash_allowed('cashAdminTools') then raise exception 'إضافة وسحب رأس مال الدولار متاح للأدمن فقط' using errcode='42501';end if;
 if action='state' then
  return jsonb_build_object(
   'walletEntries',(select coalesce(jsonb_agg(solar_private.fx_entry_read_projection(to_jsonb(e),'wallet')),'[]') from solar_private.wallet_fx_entries e where p.is_admin or e.owner_id=p.id),
   'accountEntries',(select coalesce(jsonb_agg(solar_private.fx_entry_read_projection(to_jsonb(e),'supplier')),'[]') from solar_private.supplier_fx_entries e where p.is_admin or e.owner_id=p.id));
 end if;
 if action in ('account','statement','currency') then
  if not(p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true' or coalesce(p.permissions->>'supplierStatement','false')='true' or coalesce(p.permissions->>'purchase','false')='true') then raise exception 'لا تملك صلاحية حساب المورد' using errcode='42501';end if;
  sid:=(payload->>'supplierId')::bigint;select * into s from public.suppliers where id=sid;
  if s.id is null then raise exception 'المورد غير موجود';end if;
  uid:=p.id;
  if payload->>'paymentId' is not null then
   select * into t from public.transactions where id=(payload->>'paymentId')::bigint and kind='supplier_payment';
   if t.id is null or (p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id) is distinct from true then raise exception 'لا تملك صلاحية الوصل' using errcode='42501';end if;
   uid:=coalesce(t.cashbox_user_id,t.created_by);
  end if;
  select coalesce(sum(delta),0),coalesce(sum(book_delta),0) into b,v from solar_private.supplier_fx_entries e where supplier_id=sid and e.revision=s.currency_revision and(p.is_admin or owner_id=p.id);
  select md5(coalesce(jsonb_agg(to_jsonb(e) order by e.id),'[]')::text) into token from solar_private.supplier_fx_entries e where supplier_id=sid;
  result:=jsonb_build_object('supplierId',sid,'currency',s.account_currency,'revision',s.currency_revision,'balance',b,'bookBalance',v,'token',token,
   'cashBalance',solar_private.cash_balance(uid),'usdWallet',solar_private.usd_wallet(uid),'cashOwnerName',(select coalesce(solar_private.user_name(display_name,username,honorific),'مستخدم') from public.profiles where id=uid));
  if action='account' then return result;end if;
  if action='statement' then
   if not(p.is_admin or coalesce(p.permissions->>'supplierStatement','false')='true') then raise exception 'لا تملك صلاحية الكشف' using errcode='42501';end if;
   select coalesce(jsonb_agg(solar_private.supplier_entry_read_projection(to_jsonb(e)||case when ap.summary is null then '{}'::jsonb else jsonb_build_object('archivedPurchase',ap.summary,'note',case when ap.summary->>'entryRole'='original' then 'شراء ملغى #' when ap.summary->>'entryRole'='correction' then 'تصحيح شراء #' else 'إلغاء شراء #' end||coalesce(ap.summary->>'receiptNo',ap.summary->>'id')||' · '||coalesce(ap.summary->>'party',''))end||jsonb_build_object('ledgerAmount',abs(coalesce((select (o.invoice->>'account_amount')::numeric from solar_private.purchase_originals o where o.invoice_id=x.id),x.account_amount,e.delta)),'originalTransaction',(select o.invoice from solar_private.purchase_originals o where o.invoice_id=x.id),'originalItems',(select o.items from solar_private.purchase_originals o where o.invoice_id=x.id),'transaction',to_jsonb(x),'items',
    (select coalesce(jsonb_agg((to_jsonb(i)||jsonb_build_object('brand_name',solar_private.current_product_brand(i.product_id,i.brand_name)))),'[]') from public.transaction_items i where i.transaction_id=x.id))) order by e.id),'[]') into rows
   from solar_private.supplier_fx_entries e left join public.transactions x on x.id=e.transaction_id
    left join lateral(select case when e.transaction_id is null then solar_private.purchase_archive_entry('supplier',e.id)end summary offset 0)ap on true
    where e.supplier_id=sid and(p.is_admin or e.owner_id=p.id);
   return result||jsonb_build_object('name',s.name,'rows',rows);
  end if;
 end if;
 if action not in ('currency','payment','wallet') then raise exception 'إجراء غير معروف';end if;
 perform pg_advisory_xact_lock(7311,1);
 if request_id is null then raise exception 'رقم طلب الحفظ مطلوب';end if;
 select * into prior from solar_private.fx_requests q where q.request_id=fx.request_id;
 if found then
  if prior.actor_id=p.id and prior.action=action and prior.payload=payload then if action='payment' and exists(select 1 from public.transactions x where x.id=(prior.response->>'id')::bigint and (x.supplier_payment_voided_at is not null or exists(select 1 from solar_private.receipt_change_audit a where a.transaction_id=x.id and a.action='supplier_payment_update'))) then raise exception 'الوصل ملغى أو معدّل؛ حدّث سجل التسديدات' using errcode='PT409';end if;if action='payment'then return solar_private.supplier_payment_ack_read_projection(prior.response);end if;return prior.response;end if;
  raise exception 'طلب مكرر ببيانات مختلفة' using errcode='PT409';
 end if;
 if length(coalesce(payload->>'note',''))>2000 then raise exception 'الملاحظة طويلة';end if;
 if action='currency' then
  if not p.is_admin then raise exception 'عملة حساب المورد من صلاحيات المدير' using errcode='42501';end if;
  -- Account read above is repeated under the posting lock to reject stale previews.
  select * into s from public.suppliers where id=sid for update;
  select md5(coalesce(jsonb_agg(to_jsonb(e) order by e.id),'[]')::text) into token from solar_private.supplier_fx_entries e where supplier_id=sid;
  if (payload->>'expectedRevision')::bigint is distinct from s.currency_revision or payload->>'expectedToken' is distinct from token then raise exception 'تغير الحساب؛ راجع التحويل مجدداً' using errcode='PT409';end if;
  cur:=payload->>'currency';if cur is null or cur not in ('IQD','USD') or cur=s.account_currency then raise exception 'اختر عملة حساب مختلفة';end if;
  if length(trim(coalesce(payload->>'note','')))=0 then raise exception 'اكتب سبب تغيير عملة الحساب';end if;
  r:=solar_private.fx_rate((payload->>'rate')::numeric);
  before_row:=to_jsonb(s)||jsonb_build_object('account',result);
  for owner in select owner_id,sum(delta) amount,sum(book_delta) book from solar_private.supplier_fx_entries e where supplier_id=sid and e.revision=s.currency_revision group by owner_id loop
   if owner.amount<>0 or owner.book<>0 then
    if cur='USD' and owner.amount<>0 and round(owner.amount/r,2)=0 then raise exception 'الرصيد أصغر من سنت؛ عالج فرق التقريب قبل تغيير العملة';end if;
    insert into solar_private.supplier_fx_entries(supplier_id,owner_id,currency,revision,delta,book_delta,rate,note) values
     (sid,owner.owner_id,s.account_currency,s.currency_revision,-owner.amount,-owner.book,r,'إقفال العملة السابقة');
    insert into solar_private.supplier_fx_entries(supplier_id,owner_id,currency,revision,delta,book_delta,rate,note) values
     (sid,owner.owner_id,cur,s.currency_revision+1,case when cur='USD' then round(owner.amount/r,2) else round(owner.amount*r,2) end,owner.book,r,'تحويل رصيد باتفاق جديد · '||coalesce(payload->>'note',''));
   end if;
  end loop;
  update public.suppliers set account_currency=cur,currency_revision=currency_revision+1 where id=sid;
  result:=jsonb_build_object('currency',cur,'revision',s.currency_revision+1,'ok',true);
 elsif action='wallet' then
  if not solar_private.cash_allowed('view') then raise exception 'لا تملك صلاحية القاصة' using errcode='42501';end if;
  uid:=coalesce(nullif(payload->>'ownerId','')::uuid,p.id);
  if uid<>p.id and not p.is_admin then raise exception 'لا تملك صلاحية هذه القاصة' using errcode='42501';end if;
  if not exists(select 1 from public.profiles where id=uid and active and user_type not in ('installer','warehouse')) then raise exception 'صاحب القاصة غير متاح';end if;
  amt:=(payload->>'amount')::numeric;mode:=payload->>'mode';
  if not solar_private.cash_allowed(case when mode in('deposit','withdraw') then 'cashAdminTools' else 'cashExchange' end) then raise exception 'لا تملك صلاحية الصرافة أو أدوات القاصة' using errcode='42501';end if;
  r:=solar_private.fx_rate((payload->>'rate')::numeric);
  if amt is null or not(amt>0 and amt<=1000000000) or round(amt,2)<>amt or length(trim(coalesce(payload->>'note','')))=0 then raise exception 'أدخل مبلغ دولار صحيحاً وبيان الحركة';end if;
  
  if mode not in ('deposit','withdraw','buy_usd','sell_usd') or mode is null then raise exception 'اختر نوع الحركة';end if;
  select coalesce(sum(delta),0),coalesce(sum(book_delta),0) into wd,wb from solar_private.wallet_fx_entries where owner_id=uid and currency='USD';
  before_row:=jsonb_build_object('owner',uid,'usd',wd,'book',wb,'iqd',solar_private.cash_balance(uid));
  if mode in ('withdraw','sell_usd') then
   if amt>wd then raise exception 'رصيد الدولار لا يكفي' using errcode='P0002';end if;
   v:=case when amt=wd then wb else round(amt*wb/nullif(wd,0),2) end;
  else v:=round(amt*r,2);end if;
  if mode='buy_usd' and v>solar_private.cash_balance(uid) then raise exception 'رصيد الدينار لا يكفي لشراء الدولار' using errcode='P0002';end if;
  if mode='sell_usd' then gain:=round(amt*r,2)-v;end if;
  insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,gain,entry_type,note) values
   (uid,'USD',case when mode in ('withdraw','sell_usd') then -amt else amt end,case when mode in ('withdraw','sell_usd') then -v else v end,r,gain,mode,payload->>'note');
  if mode in ('buy_usd','sell_usd') then
   insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,entry_type,note) values
    (uid,'IQD',case when mode='buy_usd' then -round(amt*r,2) else round(amt*r,2) end,case when mode='buy_usd' then -round(amt*r,2) else round(amt*r,2) end,r,mode,payload->>'note');
  end if;
  result:=jsonb_build_object('ok',true,'usdWallet',solar_private.usd_wallet(uid),'cashBalance',solar_private.cash_balance(uid));
 else
  if not(p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true') then raise exception 'لا تملك صلاحية تسديد المورد' using errcode='42501';end if;
  sid:=(payload->>'supplierId')::bigint;select * into s from public.suppliers where id=sid;
  if s.id is null then raise exception 'المورد غير موجود';end if;
  tid:=(payload->>'paymentId')::bigint;
  if exists(select 1 from public.transactions where id=tid and profit_supplier_settlement_id is not null and(p.is_admin or coalesce(cashbox_user_id,created_by)=p.id)) then raise exception 'هذه الإضافة مرتبطة بتسوية أرباح محفوظة؛ لا تعدّلها كوصل مورد مستقل' using errcode='42501';end if;amt:=(payload->>'amount')::numeric;cur:=payload->>'currency';mode:=payload->>'mode';
  if tid is null or abs(tid)>9007199254740991 or amt is null or not(amt>0 and amt<=1000000000000) or round(amt,2)<>amt or cur is null or cur not in ('IQD','USD') or mode is null or mode not in ('cash','charge_extra_expense','charge_old_balance','charge_other') then raise exception 'أدخل مبلغاً وعملة ونوع حركة صحيحين';end if;
  if mode<>'cash' and length(trim(coalesce(payload->>'note','')))=0 then raise exception 'اكتب سبب الإضافة';end if;
  select * into t from public.transactions where id=tid for update;
  uid:=p.id;
  if t.id is not null then
   if t.kind<>'supplier_payment' or (p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id) is distinct from true then raise exception 'لا تملك صلاحية الوصل' using errcode='42501';end if;
   if payload->>'expectedToken' is distinct from md5(to_jsonb(t)::text) then raise exception 'تغير الوصل؛ افتحه مجدداً' using errcode='PT409';end if;
   if t.cash is distinct from (mode='cash') then raise exception 'لا يمكن تغيير اتجاه الوصل';end if;
   before_row:=to_jsonb(t);uid:=coalesce(t.cashbox_user_id,t.created_by);
  elsif payload->>'expectedToken' is not null then raise exception 'تغير الوصل؛ افتحه مجدداً' using errcode='PT409';end if;
  r:=solar_private.fx_rate((payload->>'rate')::numeric,t.market_rate);
  perform set_config('solar.fx_context',jsonb_build_object('marketRate',r,'accountRevision',payload->'accountRevision','cashCurrency',cur)::text,true);
  v:=round(amt*case when cur='USD' then r else 1 end,2)*case when mode='cash' then 1 else -1 end;
  if t.id is null then
   insert into public.transactions(id,kind,party_type,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,notes,source_currency,exchange_rate,source_subtotal)
    values(tid,'supplier_payment','supplier',sid,s.name,v,mode='cash',mode,p.id,uid,payload->>'note',cur,case when cur='USD' then r else 1 end,amt*case when mode='cash' then 1 else -1 end);
  else
   update public.transactions set party_type='supplier',party_id=sid,party_name=s.name,total=v,cash=mode='cash',payment_mode=mode,notes=payload->>'note',source_currency=cur,exchange_rate=case when cur='USD' then r else 1 end,source_subtotal=amt*case when mode='cash' then 1 else -1 end where id=tid;
  end if;
  perform set_config('solar.fx_context','',true);
  result:=solar_private.supplier_payment_get(tid); result:=result||jsonb_build_object('accountContext',solar_private.fx('account',null,jsonb_build_object('supplierId',sid,'paymentId',tid)));
 end if;
 insert into solar_private.fx_requests(request_id,actor_id,action,payload,response,before_row) values(request_id,p.id,action,payload,result,before_row);
 return result;
end $function$;


-- Internal, exact-plan derived-cost writes. A caller-controlled GUC alone never
-- grants this path: proof lives in an inaccessible private table and is bound
-- to the current transaction, authenticated actor and immutable audited plan.
create or replace function solar_private.purchase_derived_cost_allowed(relation_name text,before_row jsonb,after_row jsonb)
returns boolean language plpgsql volatile security definer set search_path='' as $function$
declare change jsonb; correction record;
begin
 if jsonb_typeof(before_row)is distinct from'object'or jsonb_typeof(after_row)is distinct from'object'then return false;end if;
 if relation_name='transaction_items'then
  if(before_row-array['cost','cost_basis'])is distinct from(after_row-array['cost','cost_basis'])then return false;end if;
 elsif relation_name='transactions'then
  if before_row->>'kind' not in('sale','system')or(before_row-array['cost','profit','pricing_revision'])is distinct from(after_row-array['cost','profit','pricing_revision'])
   or(after_row->>'pricing_revision')::bigint is distinct from(before_row->>'pricing_revision')::bigint+1 then return false;end if;
 else return false;end if;
 for correction in
  select c.plan from solar_private.purchase_corrections c
  join solar_private.purchase_correction_execution e on e.request_id=c.request_id and e.invoice_id=c.invoice_id and e.actor_id=c.actor_id
  where e.backend_txid=txid_current()and e.actor_id=auth.uid()
 loop
  if relation_name='transaction_items'then
   for change in select value from jsonb_array_elements(correction.plan->'affectedLines')loop
    if(change->>'itemId')::bigint=(before_row->>'id')::bigint and(change->>'invoiceId')::bigint=(before_row->>'transaction_id')::bigint
     and(change->>'productId')::bigint=(before_row->>'product_id')::bigint
     and before_row->'cost'is not distinct from change->'before'->'cost'and before_row->'cost_basis'is not distinct from change->'before'->'costBasis'
     and after_row->'cost'is not distinct from change->'after'->'cost'and after_row->'cost_basis'is not distinct from change->'after'->'costBasis'then return true;end if;
   end loop;
  else
   for change in select value from jsonb_array_elements(correction.plan->'affectedInvoices')loop
    if(change->>'id')::bigint=(before_row->>'id')::bigint
     and(before_row->>'pricing_revision')::bigint is not distinct from(change->'before'->>'pricingRevision')::bigint
     and before_row->'cost'is not distinct from change->'before'->'cost'and before_row->'profit'is not distinct from change->'before'->'profit'
     and after_row->'cost'is not distinct from change->'after'->'cost'and after_row->'profit'is not distinct from change->'after'->'profit'then return true;end if;
   end loop;
  end if;
 end loop;
 return false;
end $function$;
revoke all on function solar_private.purchase_derived_cost_allowed(text,jsonb,jsonb)from public,anon,authenticated;

create or replace function solar_private.apply_purchase_derived_cost(correction_request uuid)
returns void language plpgsql security definer set search_path='' as $function$
declare audited_plan jsonb;change jsonb;t public.transactions;i public.transaction_items;new_cost numeric;new_profit numeric;calculated_cost numeric;
begin
 perform pg_advisory_xact_lock(7311,1);
 select c.plan into audited_plan from solar_private.purchase_corrections c
 join solar_private.purchase_correction_execution e on e.request_id=c.request_id and e.invoice_id=c.invoice_id and e.actor_id=c.actor_id
 where c.request_id=correction_request and e.backend_txid=txid_current()and e.actor_id=auth.uid();
 if audited_plan is null then raise exception 'تصحيح الكلفة يحتاج خطة محفوظة ضمن عملية التصحيح الحالية'using errcode='42501';end if;
 if jsonb_typeof(audited_plan->'affectedLines')is distinct from'array'or jsonb_typeof(audited_plan->'affectedInvoices')is distinct from'array'then raise exception 'خطة كلفة المبيعات غير مكتملة'using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(audited_plan->'affectedLines')x group by x->>'itemId'having count(*)>1)
 or exists(select 1 from jsonb_array_elements(audited_plan->'affectedInvoices')x group by x->>'id'having count(*)>1)
 or exists(select 1 from jsonb_array_elements(audited_plan->'affectedLines')l where not exists(select 1 from jsonb_array_elements(audited_plan->'affectedInvoices')h where h->>'id'=l->>'invoiceId'))then raise exception 'خطة كلفة المبيعات مكررة أو غير مترابطة'using errcode='22023';end if;
 perform 1 from public.transactions x where x.id in(select(value->>'id')::bigint from jsonb_array_elements(audited_plan->'affectedInvoices'))order by x.id for update;
 perform 1 from public.transaction_items x where x.id in(select(value->>'itemId')::bigint from jsonb_array_elements(audited_plan->'affectedLines'))order by x.id for update;
 for change in select value from jsonb_array_elements(audited_plan->'affectedLines')order by(value->>'itemId')::bigint loop
  select * into i from public.transaction_items where id=(change->>'itemId')::bigint;
  select * into t from public.transactions where id=i.transaction_id;
  new_cost:=(change->'after'->>'cost')::numeric;
  if i.id is null or t.kind not in('sale','system')or i.transaction_id is distinct from(change->>'invoiceId')::bigint or i.product_id is distinct from(change->>'productId')::bigint
  or i.cost is distinct from(change->'before'->>'cost')::numeric or i.cost_basis is distinct from change->'before'->'costBasis'then raise exception 'تغيّرت مواد البيع المتأثرة؛ أعد معاينة تصحيح الشراء'using errcode='PT409';end if;
  if new_cost is null or new_cost::text in('NaN','Infinity','-Infinity')or new_cost<0 or jsonb_typeof(change->'after'->'costBasis')is distinct from'object'then raise exception 'كلفة المادة المصححة غير صحيحة'using errcode='22023';end if;
  if(i.cost,i.cost_basis)is distinct from(new_cost,change->'after'->'costBasis')then
   update public.transaction_items set cost=new_cost,cost_basis=change->'after'->'costBasis'where id=i.id;
  end if;
 end loop;
 for change in select value from jsonb_array_elements(audited_plan->'affectedInvoices')order by(value->>'id')::bigint loop
  select * into t from public.transactions where id=(change->>'id')::bigint;
  new_cost:=(change->'after'->>'cost')::numeric;new_profit:=(change->'after'->>'profit')::numeric;
  if t.id is null or t.kind not in('sale','system')or t.cost is distinct from(change->'before'->>'cost')::numeric or t.profit is distinct from(change->'before'->>'profit')::numeric
   or t.pricing_revision is distinct from(change->'before'->>'pricingRevision')::bigint then raise exception 'تغيّرت فاتورة بيع متأثرة؛ أعد معاينة تصحيح الشراء'using errcode='PT409';end if;
  select round(coalesce(sum(qty*cost),0),2)into calculated_cost from public.transaction_items where transaction_id=t.id;
  if new_cost is null or new_cost::text in('NaN','Infinity','-Infinity')or new_cost<0 or new_cost is distinct from calculated_cost
   or new_profit is null or new_profit::text in('NaN','Infinity','-Infinity')or new_profit is distinct from round(coalesce(t.total,0)-new_cost-coalesce(t.expenses,0)-case when t.kind='system'then coalesce(t.installation_expenses,0)else 0 end,2)then raise exception 'إجمالي كلفة وربح البيع لا يطابقان المواد المصححة'using errcode='22023';end if;
  update public.transactions set cost=new_cost,profit=new_profit where id=t.id;
 end loop;
end $function$;
revoke all on function solar_private.apply_purchase_derived_cost(uuid)from public,anon,authenticated;

-- Keep all ordinary invoice protections. Only exact before/after pairs from
-- this transaction's protected correction plan bypass operational reopening
-- and retrospective application of today's minimum selling-price policy.
do $patch$
declare signature text;expected text;definition text;fragment text;
begin
 for signature,expected in select key,value from jsonb_each_text('{
  "solar_private.warehouse_items_changed()":"05af9eed14f4f4341052ad6366ef085e",
  "solar_private.stamp_system_item_pricing()":"35ced12ca4bf602d1f158abb3fd1b290",
  "solar_private.stamp_system_pricing()":"ff10a32392183d4f6740b0d826f81660",
  "solar_private.guard_system_pricing()":"7037c68db21c88e66005b5154fe466e7",
  "solar_private.guard_wholesale_pricing()":"045df14f90d9058d50f326d9c408ada5"
 }'::jsonb)loop
  definition:=pg_get_functiondef(signature::regprocedure);
  if md5(definition)is distinct from expected then raise exception 'Review current derived-cost trigger %',signature;end if;
  fragment:='begin'||E'\n'||' if tg_op=''UPDATE''and solar_private.purchase_derived_cost_allowed(tg_table_name,to_jsonb(old),to_jsonb(new))then return '||case when signature='solar_private.stamp_system_pricing()'then'new'else'null'end||';end if;';
  if strpos(definition,E'begin\n')=0 then raise exception 'Review derived-cost trigger body %',signature;end if;
  execute replace(definition,E'begin\n',fragment||E'\n');
 end loop;
end $patch$;


-- Existing legacy quotes can reference an old receipt recursively. Corrected
-- live quotes/snapshots carry explicit components; untouched archived quotes
-- retain their original source document without rewriting history JSON.
do $$declare definition text;needle text;begin
 definition:=pg_get_functiondef('solar_private.inventory_currency_parts(bigint,jsonb,numeric,integer)'::regprocedure);
 needle:='select * into t from public.transactions where id=(source->>''invoiceId'')::bigint and kind=''purchase'';';
 if strpos(definition,needle)=0 then raise exception 'Legacy currency basis lookup changed';end if;
 execute replace(definition,needle,needle||'
 select o.invoice,o.items into archived_invoice,archived_items from solar_private.purchase_originals o where o.invoice_id=(source->>''invoiceId'')::bigint;
 if archived_invoice is not null then t:=jsonb_populate_record(null::public.transactions,archived_invoice);end if;');
end$$;


create or replace function solar_private.purchase_correction_plan(payload jsonb, deleting boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor public.profiles;t public.transactions;product public.products;stock solar_private.warehouse_stocks;supplier public.suppliers;line record;item public.transaction_items;invoice public.transactions;
 old_items jsonb;new_items jsonb:=payload->'items';normalized jsonb:='[]';proposed jsonb;ledger jsonb;history jsonb;base jsonb;candidate jsonb;replacement jsonb;state jsonb;old_state jsonb;
 material_rows jsonb:='[]';affected_lines jsonb:='[]';affected_invoices jsonb:='[]';snapshots jsonb:='[]';fingerprints jsonb:='[]';before_summary jsonb;after_summary jsonb;
 changed boolean;requires_correction boolean:=false;source_sum numeric:=0;expenses numeric;landed numeric;new_cost numeric;new_profit numeric;delta_cost numeric;count_visible integer:=0;profit_before numeric:=0;profit_after numeric:=0;
 old_qty numeric;new_qty numeric;old_price numeric;new_price numeric;old_landed numeric;preview_rate numeric;parts jsonb;new_basis jsonb;receipt_snapshot jsonb;affected_id bigint;token text;locked boolean;
begin
 select * into actor from public.profiles where id=auth.uid() and active and user_type not in('installer','warehouse');
 if actor.id is null or(not deleting and not(actor.is_admin or coalesce((actor.permissions->>'purchase')::boolean,false))) then raise exception 'لا تملك صلاحية تعديل الشراء' using errcode='42501';end if;
 select * into t from public.transactions where id=(payload->>'invoiceId')::bigint and kind='purchase';
 if t.id is null or not solar_private.can_access_invoice(t.created_by,false) or(not deleting and not solar_private.warehouse_access_allowed(actor.id,t.warehouse_id)) then raise exception 'الفاتورة غير متاحة ضمن صلاحياتك' using errcode='42501';end if;
 if not deleting and not actor.is_admin and coalesce(t.cashbox_user_id,t.created_by) is distinct from actor.id then raise exception 'لا يمكنك تعديل فاتورة مرتبطة بقاصة مستخدم آخر' using errcode='42501';end if;
 if (payload->>'expectedRevision')::bigint is distinct from t.pricing_revision then raise exception 'تغيرت الفاتورة؛ افتح التعديل مجددًا' using errcode='PT409';end if;
 select coalesce(jsonb_agg(to_jsonb(i) order by i.product_id),'[]') into old_items from public.transaction_items i where i.transaction_id=t.id;
 if jsonb_typeof(new_items) is distinct from 'array' or jsonb_array_length(new_items)>500 or(not deleting and jsonb_array_length(new_items)=0) then raise exception 'اختر مواد الشراء وكمياتها' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(new_items)i where jsonb_typeof(i->'id') is distinct from 'number' or jsonb_typeof(i->'qty') is distinct from 'number' or jsonb_typeof(i->'price') is distinct from 'number'
  or (i->>'qty')::numeric<=0 or (i->>'price')::numeric<0 or (i->>'qty')::numeric>100000000 or (i->>'price')::numeric>1000000000000
  or(i->>'qty')::numeric::text in('NaN','Infinity','-Infinity') or(i->>'price')::numeric::text in('NaN','Infinity','-Infinity'))
  or(select count(*) from jsonb_array_elements(new_items))<>(select count(distinct(i->>'id')::bigint)from jsonb_array_elements(new_items)i) then raise exception 'مواد أو كميات أو أسعار الشراء غير صحيحة' using errcode='22023';end if;
 expenses:=coalesce((payload->>'expenses')::numeric,0);
 if expenses<0 or expenses>1000000000000 or expenses::text in('NaN','Infinity','-Infinity') then raise exception 'مصاريف الشراء غير صحيحة' using errcode='22023';end if;
 select coalesce(sum((i->>'qty')::numeric*(i->>'price')::numeric),0) into source_sum from jsonb_array_elements(new_items)i;
 if source_sum=0 and expenses>0 then raise exception 'لا يمكن توزيع المصاريف على مواد بلا قيمة' using errcode='22023';end if;
 if source_sum*t.exchange_rate+expenses>1000000000000 then raise exception 'إجمالي الشراء أكبر من الحد المسموح' using errcode='22023';end if;
 changed:=deleting or expenses is distinct from t.expenses or
  (select jsonb_agg(jsonb_build_object('id',(i->>'product_id')::bigint,'qty',(i->>'qty')::numeric,'price',coalesce((i->>'source_price')::numeric,(i->>'price')::numeric))order by(i->>'product_id')::bigint) from jsonb_array_elements(old_items)i)
  is distinct from(select jsonb_agg(jsonb_build_object('id',(i->>'id')::bigint,'qty',(i->>'qty')::numeric,'price',(i->>'price')::numeric)order by(i->>'id')::bigint)from jsonb_array_elements(new_items)i)
  or coalesce(payload->>'sourceCurrency','IQD') is distinct from t.source_currency or coalesce((payload->>'exchangeRate')::numeric,1) is distinct from t.exchange_rate;
 requires_correction:=deleting or exists(select 1 from solar_private.purchase_corrections where invoice_id=t.id)
  or exists(select 1 from public.transaction_items i join public.products p on p.id=i.product_id left join lateral(select value snap from jsonb_array_elements(t.purchase_stock) where(value->>'id')::bigint=i.product_id)s on true
    where i.transaction_id=t.id and(p.costing_revision is distinct from(s.snap->>'afterRevision')::bigint))
  or exists(select 1 from solar_private.supplier_fx_entries e join solar_private.supplier_fx_entries next on next.supplier_id=e.supplier_id and next.id>e.id where e.transaction_id=t.id)
  or exists(select 1 from solar_private.wallet_fx_entries e join solar_private.wallet_fx_entries next on next.owner_id=e.owner_id and next.currency='USD' and next.id>e.id where e.transaction_id=t.id);
 before_summary:=jsonb_build_object('total',t.total,'sourceSubtotal',coalesce(t.source_subtotal,t.subtotal/t.exchange_rate),'expenses',t.expenses,'accountAmount',t.account_amount,'accountCurrency',t.account_currency,'cashAmount',case when t.cash then t.cash_amount else 0 end,'cashCurrency',t.cash_currency);
 proposed:=jsonb_build_object('total',round(source_sum*t.exchange_rate,2)+expenses,'sourceSubtotal',source_sum,'expenses',expenses);
 if not requires_correction then
  -- Pristine receipts retain the existing save workflow and editable fields.
  -- The correction preview must not add accounting requirements to that path.
  proposed:=jsonb_build_object('total',round(source_sum*case when coalesce(payload->>'sourceCurrency','IQD')='USD' then coalesce((payload->>'exchangeRate')::numeric,t.exchange_rate) else 1 end,2)+expenses,'sourceSubtotal',source_sum,'expenses',expenses);
  select * into supplier from public.suppliers where name=payload->>'party' and active order by id limit 1;
  if supplier.id is null then raise exception 'اختر المورد المسجّل'using errcode='42501';end if;
  preview_rate:=coalesce((payload->>'marketRate')::numeric,t.market_rate);
  if preview_rate<=0 or preview_rate::text in('NaN','Infinity','-Infinity')then raise exception 'سعر الصرف غير صحيح'using errcode='22023';end if;
  after_summary:=proposed||jsonb_build_object('accountCurrency',supplier.account_currency,'cashCurrency',t.cash_currency,'accountAmount',case when supplier.account_currency='USD' then case when payload->>'sourceCurrency'='USD'then round(source_sum+expenses/preview_rate,2)else round((proposed->>'total')::numeric/preview_rate,2)end else(proposed->>'total')::numeric end,'cashAmount',case when not t.cash then 0 when t.cash_currency='USD' then round((proposed->>'total')::numeric/preview_rate,2) else(proposed->>'total')::numeric end);
  return jsonb_build_object('invoiceId',t.id,'receiptNo',t.receipt_no,'pricingRevision',t.pricing_revision,'token',md5((to_jsonb(t)||jsonb_build_object('items',old_items))::text),'changed',changed,'requiresCorrection',false,'canApply',true,'blockedReason',null,
   'locks',jsonb_build_object('supplier',false,'warehouse',true,'paymentMode',true,'sourceCurrency',false,'exchangeRate',false,'cashCurrency',true),'before',before_summary,'after',after_summary,
   'delta',jsonb_build_object('total',(after_summary->>'total')::numeric-t.total,'accountAmount',(after_summary->>'accountAmount')::numeric-t.account_amount,'cashAmount',(after_summary->>'cashAmount')::numeric-(before_summary->>'cashAmount')::numeric),'items','[]'::jsonb,'affectedSales',jsonb_build_object('count',0,'profitBefore',0,'profitAfter',0,'profitDelta',0),'paymentsPreserved',true,'unrelatedMaterialsPreserved',true);
 end if;
 if requires_correction then
  if (coalesce(payload->>'sourceCurrency','IQD'),coalesce((payload->>'exchangeRate')::numeric,1),coalesce((payload->>'marketRate')::numeric,t.market_rate),coalesce((payload->>'accountRevision')::bigint,t.account_revision),coalesce(payload->>'cashCurrency',t.cash_currency),coalesce(payload->>'mode',t.payment_mode),coalesce(payload->>'party',t.party_name),coalesce((payload->>'warehouseId')::bigint,t.warehouse_id))
   is distinct from(t.source_currency,t.exchange_rate,t.market_rate,t.account_revision,t.cash_currency,t.payment_mode,t.party_name,t.warehouse_id)
   or(payload->>'partyId' is not null and(payload->>'partyId')::bigint is distinct from t.party_id) then
   raise exception 'تصحيح الكمية والسعر يحافظ على المورد والمخزن وطريقة الدفع والعملات والصرف الأصلي.' using errcode='PT409';end if;
 end if;
 if not changed then
  return jsonb_build_object('invoiceId',t.id,'receiptNo',t.receipt_no,'pricingRevision',t.pricing_revision,'token',md5((to_jsonb(t)||jsonb_build_object('items',old_items))::text),'changed',false,'requiresCorrection',requires_correction,'canApply',true,'blockedReason',null,
   'locks',jsonb_build_object('supplier',requires_correction,'warehouse',true,'paymentMode',true,'sourceCurrency',requires_correction,'exchangeRate',requires_correction,'cashCurrency',true),'before',before_summary,'after',before_summary,
   'delta',jsonb_build_object('total',0,'accountAmount',0,'cashAmount',0),'items','[]'::jsonb,'affectedSales',jsonb_build_object('count',0,'profitBefore',0,'profitAfter',0,'profitDelta',0),'paymentsPreserved',true,'unrelatedMaterialsPreserved',true);
 end if;
 -- The preview of an unchanged receipt still reports protected-field locks.
 ledger:=solar_private.purchase_correction_ledger_plan(t,proposed);
 after_summary:=proposed||jsonb_build_object('accountAmount',ledger->'after'->'accountAmount','accountCurrency',t.account_currency,'cashAmount',case when t.cash then ledger->'after'->'cashAmount' else '0'::jsonb end,'cashCurrency',t.cash_currency);
 for line in
  select distinct id from(select(i->>'product_id')::bigint id from jsonb_array_elements(old_items)i union select(i->>'id')::bigint from jsonb_array_elements(new_items)i)s order by id
 loop
  select * into product from public.products where id=line.id;
  select * into stock from solar_private.warehouse_stocks where warehouse_id=t.warehouse_id and product_id=line.id;
  if product.id is null then raise exception 'إحدى مواد الشراء غير موجودة' using errcode='PT409';end if;
  select coalesce(sum((i->>'qty')::numeric),0),coalesce(max(coalesce((i->>'source_price')::numeric,(i->>'price')::numeric)),0),coalesce(max(case when(i->>'landed_cost')::numeric>0 then(i->>'landed_cost')::numeric else(i->>'price')::numeric end),0)
   into old_qty,old_price,old_landed from jsonb_array_elements(old_items)i where(i->>'product_id')::bigint=product.id;
  select coalesce((i->>'qty')::numeric,0),coalesce((i->>'price')::numeric,0) into new_qty,new_price from jsonb_array_elements(new_items)i where(i->>'id')::bigint=product.id;
  new_qty:=coalesce(new_qty,0);new_price:=coalesce(new_price,0);landed:=round(new_price*t.exchange_rate+case when source_sum>0 then expenses*new_price/source_sum else 0 end,6);
  if new_qty>0 then normalized:=normalized||jsonb_build_array(jsonb_build_object('id',product.id,'qty',new_qty,'sourcePrice',new_price,'price',round(new_price*t.exchange_rate,6),'landedCost',landed,'name',product.name,'brand',(select name from public.brands where id=product.brand_id),'category',product.category));end if;
  if not changed or(old_qty,old_price,old_landed) is not distinct from(new_qty,new_price,landed) then continue;end if;
  if old_qty=0 then raise exception 'أضف المادة الجديدة بوصل شراء مستقل؛ هذا التصحيح يخص مواد الوصل الأصلية.' using errcode='PT409';end if;
  if coalesce(stock.qty,0)+new_qty-old_qty<0 then raise exception 'لا تكفي كمية «%» المتاحة في مخزن الوصل: المتاح % والمطلوب تخفيضه %. أعد الكمية إلى المخزن أو أنهِ حجزها أولًا.',product.name,coalesce(stock.qty,0),old_qty-new_qty using errcode='PT409';end if;
  history:=solar_private.purchase_material_history(t,product.id);
  base:=solar_private.purchase_material_replay(history->'seed',history->'events',t.id,null);
  parts:=solar_private.inventory_currency_parts(product.id,product.cost_basis,product.cost);
  if(base->>'qty')::numeric is distinct from product.qty or abs((base->>'cost')::numeric-product.cost)>.000001
   or abs((base->'parts'->>'usd')::numeric-(parts->>'usd')::numeric)>.000001 or abs((base->'parts'->>'iqd')::numeric-(parts->>'iqd')::numeric)>.000001 then
   raise exception 'تعذر مطابقة تسلسل كلفة مادة «%» مع مخزونها الحالي؛ لم يُحفظ أي تعديل. يلزم مراجعة حركاتها الناقصة.',product.name using errcode='PT409';end if;
  replacement:=jsonb_build_object('qty',new_qty,'price',new_price,'currency',t.source_currency,'rate',t.exchange_rate,'expenses',expenses,'sourceTotal',source_sum);
  candidate:=solar_private.purchase_material_replay(history->'seed',history->'events',t.id,replacement);
  if(candidate->>'qty')::numeric is distinct from product.qty+new_qty-old_qty then raise exception 'تعذر مطابقة فرق كمية المادة بعد التصحيح' using errcode='PT409';end if;
  new_basis:=product.cost_basis||jsonb_build_object('method','purchase-correction','unitCost',(candidate->>'cost')::numeric,'currencyComponents',candidate->'parts');
  material_rows:=material_rows||jsonb_build_array(jsonb_build_object('id',product.id,'name',product.name,'before',jsonb_build_object('qty',product.qty,'cost',product.cost,'basis',product.cost_basis,'revision',product.costing_revision),'after',jsonb_build_object('qty',(candidate->>'qty')::numeric,'cost',(candidate->>'cost')::numeric,'basis',new_basis),'quantityDelta',new_qty-old_qty,'bookValueDelta',(candidate->>'qty')::numeric*(candidate->>'cost')::numeric-product.qty*product.cost,'availableBefore',coalesce(stock.qty,0),'availableAfter',coalesce(stock.qty,0)+new_qty-old_qty));
  fingerprints:=fingerprints||jsonb_build_array(jsonb_build_object('product',to_jsonb(product),'stock',to_jsonb(stock),'history',history));
  for item in select i.* from public.transaction_items i join public.transactions x on x.id=i.transaction_id where i.product_id=product.id and x.kind in('sale','system') and candidate->'states'?i.transaction_id::text loop
   state:=candidate->'states'->item.transaction_id::text;old_state:=base->'states'->item.transaction_id::text;
   if(old_state->>'qty')::numeric is distinct from item.qty or abs((old_state->>'cost')::numeric-item.cost)>.000001
    or abs((old_state->>'book')::numeric-coalesce((item.cost_basis->>'bookUnitCost')::numeric,item.cost))>.000001
    or abs((old_state->'parts'->>'usd')::numeric-(solar_private.inventory_currency_parts(item.product_id,item.cost_basis,coalesce((item.cost_basis->>'bookUnitCost')::numeric,item.cost))->>'usd')::numeric)>.000001
    or abs((old_state->'parts'->>'iqd')::numeric-(solar_private.inventory_currency_parts(item.product_id,item.cost_basis,coalesce((item.cost_basis->>'bookUnitCost')::numeric,item.cost))->>'iqd')::numeric)>.000001 then
    raise exception 'تعذر مطابقة كلفة بيع مرتبط بمادة «%»؛ لم يُحفظ أي تعديل.',product.name using errcode='PT409';end if;
   new_basis:=item.cost_basis||jsonb_build_object('unitCost',(state->>'book')::numeric,'bookUnitCost',(state->>'book')::numeric,'valuationUnitCost',(state->>'cost')::numeric,'currencyComponents',state->'parts');
   if abs((state->>'cost')::numeric-item.cost)>.00000001 or state->'parts' is distinct from old_state->'parts' or abs((state->>'book')::numeric-(old_state->>'book')::numeric)>.00000001 then
    affected_lines:=affected_lines||jsonb_build_array(jsonb_build_object('invoiceId',item.transaction_id,'productId',item.product_id,'itemId',item.id,'before',jsonb_build_object('cost',item.cost,'costBasis',item.cost_basis),'after',jsonb_build_object('cost',(state->>'cost')::numeric,'costBasis',new_basis)));
   end if;
  end loop;
  for affected_id in select(key)::bigint from jsonb_each(candidate->'snapshots') loop
   if affected_id=t.id then continue;end if;
   select * into invoice from public.transactions where id=affected_id and kind='purchase';
   if invoice.id is null then continue;end if;
   select value into receipt_snapshot from jsonb_array_elements(invoice.purchase_stock) where(value->>'id')::bigint=product.id;
   if receipt_snapshot is null then raise exception 'لقطة شراء لاحق غير مكتملة للمادة «%».',product.name using errcode='PT409';end if;
   state:=candidate->'snapshots'->affected_id::text;
   snapshots:=snapshots||jsonb_build_array(jsonb_build_object('invoiceId',affected_id,'productId',product.id,'before',receipt_snapshot,'after',receipt_snapshot||state||jsonb_build_object('id',product.id,'replayedByPurchase',t.id,'afterRevision',-1)));
  end loop;
 end loop;
 for affected_id in select distinct(v->>'invoiceId')::bigint from jsonb_array_elements(affected_lines)v loop
  select * into invoice from public.transactions where id=affected_id;
  if invoice.profit_settlement_id is not null then raise exception 'حالة تسوية ربح الفاتورة المرتبطة غير متوافقة؛ راجع الإدارة.' using errcode='PT409';end if;
  if invoice.cost is distinct from(select round(sum(i.qty*i.cost),2)from public.transaction_items i where i.transaction_id=invoice.id)
   or invoice.profit is distinct from(invoice.total-invoice.cost-invoice.expenses-case when invoice.kind='system'then coalesce(invoice.installation_expenses,0)else 0 end)then
   raise exception 'إجماليات كلفة فاتورة مرتبطة لا تطابق موادها؛ لم يُحفظ التصحيح، راجع الفاتورة أولًا.'using errcode='PT409';end if;
  select round(sum(i.qty*coalesce((a->'after'->>'cost')::numeric,i.cost)),2) into new_cost from public.transaction_items i left join lateral(select value a from jsonb_array_elements(affected_lines)where(value->>'itemId')::bigint=i.id)a on true where i.transaction_id=invoice.id;
  new_profit:=invoice.total-new_cost-case when invoice.kind='system' or not coalesce(invoice.expenses_on_customer,true) then invoice.expenses else invoice.expenses end;
  -- Customer-paid wholesale expenses are included in total and removed once.
  if invoice.kind='sale' and not coalesce(invoice.expenses_on_customer,true) then new_profit:=invoice.total-new_cost-invoice.expenses;end if;
  if invoice.kind='system' then new_profit:=new_profit-coalesce(invoice.installation_expenses,0);end if;
  affected_invoices:=affected_invoices||jsonb_build_array(jsonb_build_object('id',invoice.id,'ownerId',coalesce((select owner_id from solar_private.invoice_profit_owners where invoice_id=invoice.id),invoice.cashbox_user_id,invoice.created_by),'kind',invoice.kind,'receiptNo',invoice.receipt_no,'createdAt',invoice.created_at,'before',jsonb_build_object('cost',invoice.cost,'profit',invoice.profit,'pricingRevision',invoice.pricing_revision),'after',jsonb_build_object('cost',new_cost,'profit',new_profit),'legacySettlementId',invoice.profit_settlement_id));
  if solar_private.can_access_invoice(invoice.created_by,false) then count_visible:=count_visible+1;profit_before:=profit_before+invoice.profit;profit_after:=profit_after+new_profit;end if;
 end loop;
 token:=md5(jsonb_build_object('invoice',to_jsonb(t),'items',old_items,'payload',payload-'purchaseCorrectionToken','fingerprints',fingerprints,'ledger',ledger,'affected',affected_invoices,'snapshots',snapshots)::text);
 return jsonb_build_object('invoiceId',t.id,'receiptNo',t.receipt_no,'pricingRevision',t.pricing_revision,'token',token,'changed',changed,'requiresCorrection',requires_correction,'canApply',true,'blockedReason',null,
  'locks',jsonb_build_object('supplier',requires_correction,'warehouse',requires_correction,'paymentMode',requires_correction,'sourceCurrency',requires_correction,'exchangeRate',requires_correction,'cashCurrency',requires_correction),
  'before',before_summary,'after',after_summary,'delta',jsonb_build_object('total',(after_summary->>'total')::numeric-t.total,'accountAmount',(after_summary->>'accountAmount')::numeric-t.account_amount,'cashAmount',(after_summary->>'cashAmount')::numeric-(before_summary->>'cashAmount')::numeric),
  'items',material_rows,'affectedLines',affected_lines,'affectedInvoices',affected_invoices,'purchaseSnapshots',snapshots,'normalizedItems',normalized,'ledgerPlan',ledger,
  'affectedSales',jsonb_build_object('count',count_visible,'profitBefore',profit_before,'profitAfter',profit_after,'profitDelta',profit_after-profit_before),'paymentsPreserved',true,'unrelatedMaterialsPreserved',true);
end$$;
revoke all on function solar_private.purchase_correction_plan(jsonb,boolean) from public,anon,authenticated;

create or replace function public.solar_purchase_correction_preview(payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare plan jsonb;t public.transactions;begin
 plan:=solar_private.purchase_correction_plan(payload);
 plan:=plan||jsonb_build_object('materialScope','changed','changedProductIds',coalesce((select jsonb_agg(i->'id')from jsonb_array_elements(plan->'items')i),'[]'));
 plan:=jsonb_set(plan,'{items}',coalesce((select jsonb_agg((i-'before'-'after')||jsonb_build_object('before',jsonb_build_object('qty',i->'before'->'qty','cost',i->'before'->'cost'),'after',jsonb_build_object('qty',i->'after'->'qty','cost',i->'after'->'cost')))from jsonb_array_elements(plan->'items')i),'[]'));
 return plan-'affectedLines'-'affectedInvoices'-'purchaseSnapshots'-'normalizedItems'-'ledgerPlan';
exception when sqlstate 'PT409' or sqlstate 'P0002' then
 -- Authenticate/authorize again before disclosing even a blocked receipt.
 select * into t from public.transactions where id=(payload->>'invoiceId')::bigint and kind='purchase';
 if t.id is null or not solar_private.can_access_invoice(t.created_by,false) then raise;end if;
 return jsonb_build_object('invoiceId',t.id,'receiptNo',t.receipt_no,'pricingRevision',t.pricing_revision,'token',md5(to_jsonb(t)::text),'changed',true,'requiresCorrection',true,'canApply',false,'blockedReason',sqlerrm,'locks',jsonb_build_object('supplier',true,'warehouse',true,'paymentMode',true,'sourceCurrency',true,'exchangeRate',true,'cashCurrency',true));
end$$;
revoke all on function public.solar_purchase_correction_preview(jsonb) from public,anon;
grant execute on function public.solar_purchase_correction_preview(jsonb) to authenticated;


create or replace function solar_private.purchase_save_v419(request_id uuid,payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare actor public.profiles;t public.transactions;after_row public.transactions;prior solar_private.invoice_requests;plan jsonb;ledger jsonb;original_items jsonb;item jsonb;line jsonb;result jsonb;header_id bigint;next_snapshots jsonb;context_before text;total_cost numeric;
begin
 select * into actor from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 if actor.id is null or not(actor.is_admin or coalesce((actor.permissions->>'purchase')::boolean,false)) then raise exception 'لا تملك صلاحية تعديل الشراء' using errcode='42501';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into t from public.transactions where id=(payload->>'invoiceId')::bigint and kind='purchase' for update;
 if t.id is null or not solar_private.can_access_invoice(t.created_by,false) or not solar_private.warehouse_access_allowed(actor.id,t.warehouse_id) then raise exception 'الفاتورة غير متاحة ضمن صلاحياتك' using errcode='42501';end if;
 if not actor.is_admin and coalesce(t.cashbox_user_id,t.created_by) is distinct from actor.id then raise exception 'لا يمكنك تعديل فاتورة مرتبطة بقاصة مستخدم آخر' using errcode='42501';end if;
 select * into prior from solar_private.invoice_requests r where r.request_id=request_id;
 if prior.request_id is not null then
  if prior.user_id is distinct from actor.id or prior.payload is distinct from payload then raise exception 'معرّف الحفظ مستخدم لطلب مختلف' using errcode='PT409';end if;
  return prior.result;
 end if;
 if request_id is null then raise exception 'معرف الحفظ مطلوب' using errcode='22023';end if;
 plan:=solar_private.purchase_correction_plan(payload);
 if not(plan->>'requiresCorrection')::boolean or not(plan->>'changed')::boolean then return solar_private.invoice_save_v333(request_id,payload);end if;
 if payload->>'purchaseCorrectionToken' is distinct from plan->>'token' then raise exception 'تغيرت حركات المادة أو الحساب منذ المعاينة؛ أعد معاينة التصحيح ثم احفظ.' using errcode='PT409';end if;
 select coalesce(jsonb_agg(to_jsonb(i)order by i.id),'[]') into original_items from public.transaction_items i where i.transaction_id=t.id;
 perform 1 from public.products p where p.id in(select(v->>'id')::bigint from jsonb_array_elements(plan->'items')v)order by p.id for update;
 perform 1 from public.transactions x where x.id in(select(v->>'id')::bigint from jsonb_array_elements(plan->'affectedInvoices')v union select(v->>'invoiceId')::bigint from jsonb_array_elements(plan->'purchaseSnapshots')v)order by x.id for update;
 insert into solar_private.purchase_originals(invoice_id,invoice,items)values(t.id,to_jsonb(t),original_items)on conflict(invoice_id)do nothing;
 insert into solar_private.purchase_corrections(request_id,invoice_id,actor_id,before_invoice,before_items,plan)values(request_id,t.id,actor.id,to_jsonb(t),original_items,plan);
 ledger:=solar_private.purchase_correction_ledger_apply(request_id,t.id,plan->'after');
 select coalesce(jsonb_agg(s||jsonb_build_object('afterRevision',-1,'replayedByPurchase',t.id)),'[]') into next_snapshots from jsonb_array_elements(t.purchase_stock)s where exists(select 1 from jsonb_array_elements(plan->'normalizedItems')i where(i->>'id')::bigint=(s->>'id')::bigint);
 select round(coalesce(sum((i->>'qty')::numeric*(i->>'landedCost')::numeric),0),2) into total_cost from jsonb_array_elements(plan->'normalizedItems')i;
 update public.transactions set subtotal=round((plan->'after'->>'sourceSubtotal')::numeric*t.exchange_rate,2),total=(plan->'after'->>'total')::numeric,
  expenses=(plan->'after'->>'expenses')::numeric,source_subtotal=(plan->'after'->>'sourceSubtotal')::numeric,
  account_amount=(ledger->'after'->>'accountAmount')::numeric,cash_amount=(ledger->'after'->>'cashAmount')::numeric,
  cost=total_cost,profit=0,purchase_stock=next_snapshots,notes=nullif(payload->>'notes','') where id=t.id;
 for item in select value from jsonb_array_elements(plan->'items')loop
  update public.products set qty=(item->'after'->>'qty')::numeric,cost=(item->'after'->>'cost')::numeric,cost_basis=item->'after'->'basis' where id=(item->>'id')::bigint;
 end loop;
 -- Preserve existing item identities and apply only actual signed warehouse
 -- quantity changes. A full delete/reinsert would transiently overdraw stock.
 delete from public.transaction_items i where i.transaction_id=t.id and not exists(select 1 from jsonb_array_elements(plan->'normalizedItems')n where(n->>'id')::bigint=i.product_id);
 for line in select value from jsonb_array_elements(plan->'normalizedItems')loop
  update public.transaction_items set qty=(line->>'qty')::numeric,price=(line->>'price')::numeric,source_price=(line->>'sourcePrice')::numeric,
   cost=(line->>'landedCost')::numeric,landed_cost=(line->>'landedCost')::numeric,
   cost_basis=jsonb_build_object('currency',t.source_currency,'rate',t.exchange_rate,'sourcePrice',(line->>'sourcePrice')::numeric,'invoiceId',t.id)
   where transaction_id=t.id and product_id=(line->>'id')::bigint and
    (qty,price,source_price,cost,landed_cost)is distinct from((line->>'qty')::numeric,(line->>'price')::numeric,(line->>'sourcePrice')::numeric,(line->>'landedCost')::numeric,(line->>'landedCost')::numeric);
 end loop;
 perform solar_private.apply_purchase_derived_cost(request_id);
 context_before:=coalesce(current_setting('solar.fx_context',true),'');
 for header_id in select distinct(v->>'invoiceId')::bigint from jsonb_array_elements(plan->'purchaseSnapshots')v loop
  select * into after_row from public.transactions where id=header_id;
  select jsonb_agg(coalesce((select v->'after' from jsonb_array_elements(plan->'purchaseSnapshots')v where(v->>'invoiceId')::bigint=header_id and(v->>'productId')::bigint=(s->>'id')::bigint),s)) into next_snapshots from jsonb_array_elements(after_row.purchase_stock)s;
  perform set_config('solar.fx_context',jsonb_build_object('marketRate',after_row.market_rate,'accountRevision',after_row.account_revision,'cashCurrency',after_row.cash_currency)::text,true);
  update public.transactions set purchase_stock=next_snapshots where id=header_id;
 end loop;
 perform set_config('solar.fx_context',context_before,true);
 select * into after_row from public.transactions where id=t.id;
 update solar_private.purchase_corrections c set after_invoice=to_jsonb(after_row),after_items=(select jsonb_agg(to_jsonb(i)order by i.id)from public.transaction_items i where i.transaction_id=t.id)where c.request_id=request_id;
 insert into solar_private.receipt_change_audit(request_id,actor_id,transaction_id,action,before_row,after_row)values(request_id,actor.id,t.id,'invoice_edit',to_jsonb(t),to_jsonb(after_row));
 result:=jsonb_build_object('id',after_row.id,'receiptNo',after_row.receipt_no,'pricingRevision',after_row.pricing_revision,'total',after_row.total,'cost',after_row.cost,'profit',after_row.profit,'invoiceAccount',after_row.invoice_account,'warehouseQrToken',after_row.warehouse_qr_token,'warehouseId',after_row.warehouse_id,'warehouseName',after_row.warehouse_name,
  'purchaseCorrection',jsonb_build_object('requestId',request_id,'affectedSales',plan->'affectedSales','paymentsPreserved',true));
 insert into solar_private.invoice_requests(request_id,user_id,payload,result)values(request_id,actor.id,payload,result);
 return result;
end$$;
revoke all on function solar_private.purchase_save_v419(uuid,jsonb)from public,anon,authenticated;

do $$declare definition text;needle text:='invoice_result:=solar_private.invoice_save_v333(request_id,payload);';begin
 definition:=pg_get_functiondef('solar_private.invoice_save(uuid,jsonb)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Protected invoice save contract changed';end if;
 execute replace(definition,needle,'invoice_result:=case when payload->>''kind''=''purchase'' and payload->>''invoiceId'' is not null then solar_private.purchase_save_v419(request_id,payload) else solar_private.invoice_save_v333(request_id,payload) end;');
end$$;


create or replace function solar_private.purchase_delete_replay_plan(invoice_id bigint)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare t public.transactions;begin
 select * into t from public.transactions where id=invoice_id and kind='purchase';
 if t.id is null then raise exception 'وصل الشراء غير متاح' using errcode='PT409';end if;
 return solar_private.purchase_correction_plan(jsonb_build_object('kind','purchase','invoiceId',t.id,'expectedRevision',t.pricing_revision,'party',t.party_name,'partyId',t.party_id,'mode',t.payment_mode,'sourceCurrency',t.source_currency,'exchangeRate',t.exchange_rate,'marketRate',t.market_rate,'accountRevision',t.account_revision,'cashCurrency',t.cash_currency,'warehouseId',t.warehouse_id,'expenses',0,'items','[]'::jsonb),true);
end$$;
revoke all on function solar_private.purchase_delete_replay_plan(bigint)from public,anon,authenticated;

create or replace function solar_private.purchase_delete_plan(invoice_id bigint)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare t public.transactions;plan jsonb;totals jsonb;e solar_private.supplier_fx_entries;w solar_private.wallet_fx_entries;rows jsonb;begin
 select * into t from public.transactions where id=invoice_id and kind='purchase';
 plan:=solar_private.purchase_delete_replay_plan(invoice_id);
 totals:=solar_private.purchase_correction_ledger_totals(invoice_id);
 select * into e from solar_private.supplier_fx_entries where transaction_id=invoice_id;
 select * into w from solar_private.wallet_fx_entries where transaction_id=invoice_id;
 select jsonb_agg(i||jsonb_build_object('quantity',-(i->>'quantityDelta')::numeric,'warehouseAfter',(i->>'availableAfter')::numeric,'warehouseBefore',(select to_jsonb(s)from solar_private.warehouse_stocks s where s.warehouse_id=t.warehouse_id and s.product_id=(i->>'id')::bigint)))into rows from jsonb_array_elements(plan->'items')i;
 return jsonb_build_object('warehouseId',t.warehouse_id,'warehouseName',t.warehouse_name,'items',coalesce(rows,'[]'),'cashRefund',case when t.cash then -(totals->>'cashDelta')::numeric else 0 end,
  'ledgerTotals',totals,'corrected',exists(select 1 from solar_private.purchase_corrections c where c.invoice_id=t.id),'cashCurrency',t.cash_currency,'accountCurrency',e.currency,'accountEffect',-(totals->>'supplierDelta')::numeric,'supplierEntry',to_jsonb(e),'walletEntry',to_jsonb(w),'affectedSales',plan->'affectedSales');
end$$;

create or replace function solar_private.purchase_apply_snapshots(request_id uuid)
returns void language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare plan jsonb;t public.transactions;header_id bigint;next_snapshots jsonb;context_before text;
begin
 select c.plan into plan from solar_private.purchase_corrections c join solar_private.purchase_correction_execution e using(request_id)where c.request_id=request_id and e.actor_id=auth.uid()and e.backend_txid=txid_current();
 if plan is null then raise exception 'سياق تطبيق كلفة الشراء غير صالح' using errcode='42501';end if;
 context_before:=coalesce(current_setting('solar.fx_context',true),'');
 for header_id in select distinct(v->>'invoiceId')::bigint from jsonb_array_elements(plan->'purchaseSnapshots')v loop
  select * into t from public.transactions where id=header_id;
  select jsonb_agg(coalesce((select v->'after'from jsonb_array_elements(plan->'purchaseSnapshots')v where(v->>'invoiceId')::bigint=header_id and(v->>'productId')::bigint=(s->>'id')::bigint),s))into next_snapshots from jsonb_array_elements(t.purchase_stock)s;
  perform set_config('solar.fx_context',jsonb_build_object('marketRate',t.market_rate,'accountRevision',t.account_revision,'cashCurrency',t.cash_currency)::text,true);
  update public.transactions set purchase_stock=next_snapshots where id=header_id;
 end loop;
 perform set_config('solar.fx_context',context_before,true);
end$$;
revoke all on function solar_private.purchase_apply_snapshots(uuid)from public,anon,authenticated;

-- Keep the approved financial reversal workflow, adding only the trusted
-- causal material-cost plan before it removes this purchase's stock quantity.
do $$declare definition text;needle text;begin
 definition:=pg_get_functiondef('solar_private.purchase_delete(bigint,bigint)'::regprocedure);
 needle:='e solar_private.supplier_fx_entries;w solar_private.wallet_fx_entries;reversal_id bigint;wallet_reversal_id bigint;note text;';
 if strpos(definition,needle)=0 then raise exception 'Purchase deletion declarations changed';end if;
 definition:=replace(definition,needle,'replay jsonb;correction_id uuid:=gen_random_uuid();'||needle);
 needle:='SELECT coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),''[]'') INTO original_items FROM public.transaction_items i WHERE i.transaction_id=t.id;';
 if strpos(definition,needle)=0 then raise exception 'Purchase deletion archive contract changed';end if;
 definition:=replace(definition,needle,needle||'
 replay:=solar_private.purchase_delete_replay_plan(t.id);
 INSERT INTO solar_private.purchase_originals(invoice_id,invoice,items)VALUES(t.id,to_jsonb(t),original_items)ON CONFLICT ON CONSTRAINT purchase_originals_pkey DO NOTHING;
 INSERT INTO solar_private.purchase_corrections(request_id,invoice_id,actor_id,before_invoice,before_items,plan)VALUES(correction_id,t.id,actor.id,to_jsonb(t),original_items,replay||jsonb_build_object(''action'',''delete''));
 INSERT INTO solar_private.purchase_correction_execution(request_id,invoice_id,actor_id,backend_txid)VALUES(correction_id,t.id,actor.id,txid_current());
 PERFORM solar_private.apply_purchase_derived_cost(correction_id);
 PERFORM solar_private.purchase_apply_snapshots(correction_id);');
 execute definition;
end$$;


create function solar_private.purchase_cancellation_public(plan jsonb)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('warehouseId',plan->'warehouseId','warehouseName',plan->'warehouseName','cashRefund',plan->'cashRefund','cashCurrency',plan->'cashCurrency','accountCurrency',plan->'accountCurrency','accountEffect',plan->'accountEffect','affectedSales',plan->'affectedSales',
  'items',coalesce((select jsonb_agg(jsonb_build_object('id',i->'id','name',i->'name','quantity',i->'quantity','warehouseAfter',i->'warehouseAfter','availableBefore',i->'availableBefore','availableAfter',i->'availableAfter','before',jsonb_build_object('qty',i->'before'->'qty','cost',i->'before'->'cost'),'after',jsonb_build_object('qty',i->'after'->'qty','cost',i->'after'->'cost')))from jsonb_array_elements(plan->'items')i),'[]'))
$$;
revoke all on function solar_private.purchase_cancellation_public(jsonb)from public,anon,authenticated;
do $$declare definition text;needle text:='plan-''supplierEntry''-''walletEntry''';begin
 definition:=pg_get_functiondef('solar_private.receipt_delete_context(bigint)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Purchase deletion public projection changed';end if;
 execute replace(definition,needle,'solar_private.purchase_cancellation_public(plan)');
end$$;

NOTIFY pgrst,'reload schema';
