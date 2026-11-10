-- V4: state-aware direct deletion; existing accounting cancellation is reused.
-- No existing financial rows, grants or RLS policies are rewritten.
do $$declare f record;begin
 for f in select * from(values
  ('solar_private.sale_delete(bigint,text)','de776d913a0e20515848e9683cfb28eb'),
  ('solar_private.purchase_delete(bigint,bigint)','988767e0da571fce77e744e87c5c16ff'),
  ('solar_private.receipt_delete_context(bigint)','5ddcd8e4e67c32cd33c8a460c1f029cc'),
  ('solar_private.receipt_delete_requests(text,uuid,jsonb)','c02a9a2974dda5a8c296047031b2e2e2'),
  ('solar_private.guard_receipt_delete_approval()','cb472242c2d5ccccaceffecf37efff11')
 ) expected(signature,hash)loop
  if md5(pg_get_functiondef(f.signature::regprocedure))<>f.hash then
   raise exception 'Deletion workflow changed before migration: %',f.signature;
  end if;
 end loop;
end$$;

-- Bound preview/history lookup work as the receipt history grows.
create index receipt_direct_creation_lookup on solar_private.invoice_requests((result->>'id'),created_at,request_id);
create index receipt_direct_edit_lookup on solar_private.invoice_requests((payload->>'invoiceId'));
create index receipt_direct_payment_lookup on solar_private.system_payment_requests((payload->>'invoiceId'));
create index receipt_direct_change_lookup on solar_private.receipt_change_audit(transaction_id);
create index receipt_direct_warehouse_lookup on solar_private.warehouse_audit(invoice_id);

create table solar_private.receipt_delete_executions(
 request_id uuid primary key,
 invoice_id bigint not null,
 actor_id uuid not null references public.profiles(id),
 mode text not null check(mode in('direct','approval')),
 submission jsonb not null,
 snapshot jsonb not null,
 execution_txid bigint not null,
 created_at timestamptz not null default now(),
 completed_at timestamptz,
 result jsonb
);
alter table solar_private.receipt_delete_executions enable row level security;
revoke all on solar_private.receipt_delete_executions from public,anon,authenticated;
create index receipt_delete_executions_invoice on solar_private.receipt_delete_executions(invoice_id);

create function solar_private.receipt_delete_authorized(invoice_id bigint) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from solar_private.receipt_delete_executions e
  where e.invoice_id=receipt_delete_authorized.invoice_id and e.actor_id=auth.uid()
   and e.execution_txid=txid_current() and e.completed_at is null)
$$;
revoke all on function solar_private.receipt_delete_authorized(bigint) from public,anon,authenticated;

-- Creation itself posts cash/stock and applies the initial warranty. Its saved
-- revision is the baseline; any later invoice edit advances it permanently.
create function solar_private.receipt_direct_eligibility(invoice_id bigint) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;t public.transactions;initial solar_private.invoice_requests;reason text;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 select * into t from public.transactions where id=invoice_id;
 if p.id is null or t.id is null or not solar_private.can_access_invoice(t.created_by,false) then
  raise exception 'الوصل غير متاح ضمن صلاحياتك' using errcode='42501';end if;
 if t.kind='purchase' then
  return jsonb_build_object('directEligible',true,'deletionMode','direct','directBlockedReason',null);
 elsif t.kind not in('sale','system') then
  reason:='هذا النوع من الوصولات يحتاج موافقة الإدارة على الحذف.';
 elsif not solar_private.can_delete_sale(t.created_by) then
  reason:='لا تملك صلاحية حذف هذا الوصل.';
 elsif t.warehouse_status<>'pending' or t.warehouse_revision<>0 or t.warehouse_prepared_at is not null or t.warehouse_prepared_by is not null
  or exists(select 1 from solar_private.warehouse_audit a where a.invoice_id=t.id)
  or exists(select 1 from solar_private.warehouse_price_edits a where a.invoice_id=t.id)
  or exists(select 1 from solar_private.warehouse_price_requests a where a.invoice_id=t.id) then
  reason:='حصل تجهيز أو تعديل من المخزن على الوصل؛ حذفه يحتاج موافقة الإدارة.';
 elsif t.installation_status not in('none','pending') or t.installation_revision<>0
  or t.installation_started_at is not null or t.installation_completed_at is not null or t.installation_closed_at is not null
  or t.installation_expenses<>0 or t.installation_report<>'{}'::jsonb
  or exists(select 1 from public.solar_cash_entries e where e.job_id=t.id) then
  reason:='حصلت حركة تنصيب أو مصاريف مرتبطة بالوصل؛ حذفه يحتاج موافقة الإدارة.';
 elsif exists(select 1 from public.transactions x where x.system_invoice_id=t.id)
  or exists(select 1 from solar_private.system_payment_requests r where r.payload->>'invoiceId'=t.id::text)
  or exists(select 1 from solar_private.deleted_sales d where d.invoice->>'system_invoice_id'=t.id::text) then
  reason:='توجد حركة تسديد أو إضافة مرتبطة بالوصل؛ حذفه يحتاج موافقة الإدارة.';
 elsif t.profit_settlement_id is not null or t.profit_supplier_settlement_id is not null
  or exists(select 1 from solar_private.profit_checkpoints c where c.source_key='tx:'||t.id)
  or exists(select 1 from solar_private.invoice_profit_owner_audit a where a.invoice_id=t.id) then
  reason:='حصلت تسوية أو تحويل لأرباح الوصل؛ راجع مسار الموافقات.';
 elsif exists(select 1 from solar_private.receipt_change_audit a where a.transaction_id=t.id)
  or exists(select 1 from solar_private.invoice_requests r where r.payload->>'invoiceId'=t.id::text) then
  reason:='تم تعديل الوصل بعد إنشائه؛ حذفه يحتاج موافقة الإدارة.';
 else
  select * into initial from solar_private.invoice_requests r
   where r.result->>'id'=t.id::text and nullif(r.payload->>'invoiceId','') is null
   order by r.created_at,r.request_id limit 1;
  if initial.request_id is null or initial.result->>'pricingRevision' is null then
   reason:='سجل إنشاء هذا الوصل قديم أو غير مكتمل؛ حذفه يحتاج موافقة الإدارة.';
  elsif t.pricing_revision is distinct from (initial.result->>'pricingRevision')::bigint then
   reason:='حصل تغيير على الوصل بعد إنشائه؛ حذفه يحتاج موافقة الإدارة.';
  end if;
 end if;
 return jsonb_build_object('directEligible',reason is null,'deletionMode',case when reason is null then 'direct' else 'approval' end,'directBlockedReason',reason);
end$$;
revoke all on function solar_private.receipt_direct_eligibility(bigint) from public,anon,authenticated;

alter function solar_private.receipt_delete_context(bigint) rename to receipt_delete_context_v3102;
revoke all on function solar_private.receipt_delete_context_v3102(bigint) from public,anon,authenticated;
create function solar_private.receipt_delete_context(invoice_id bigint) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare context jsonb;eligibility jsonb;plan jsonb;
begin
 context:=solar_private.receipt_delete_context_v3102(invoice_id);
 if context->>'kind' in('sale','system','purchase') then
  eligibility:=solar_private.receipt_direct_eligibility(invoice_id);
  if context->>'kind'='purchase' then
   begin plan:=solar_private.purchase_delete_plan(invoice_id);
    context:=context||jsonb_build_object('purchaseCancellation',plan-'supplierEntry'-'walletEntry');
   exception when sqlstate 'PT409' then
    context:=context||jsonb_build_object('blockedReason',sqlerrm);
   end;
  end if;
 else eligibility:=jsonb_build_object('directEligible',false,'deletionMode','approval','directBlockedReason','هذا النوع من الوصولات يحتاج موافقة الإدارة على الحذف.');end if;
 -- Eligibility is advisory in a preview; every execution locks and rechecks it.
 return context||eligibility;
end$$;
revoke all on function solar_private.receipt_delete_context(bigint) from public,anon,authenticated;

-- Keep request/review/approval semantics and immutable request tokens intact.
alter function solar_private.receipt_delete_requests(text,uuid,jsonb) rename to receipt_delete_requests_v3102;
revoke all on function solar_private.receipt_delete_requests_v3102(text,uuid,jsonb) from public,anon,authenticated;
create function solar_private.receipt_delete_requests(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
#variable_conflict use_variable
declare p public.profiles;e solar_private.receipt_delete_executions;r solar_private.receipt_delete_requests;
 c jsonb;t public.transactions;preview jsonb;result jsonb;invoice_id bigint;
begin
 if action is null or action not in('context','request','list','get','approve','reject','cancel','delete_direct')
  or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب غير صحيح' using errcode='22023';end if;
 if action='request' then
  perform pg_advisory_xact_lock(7311,1);
  if exists(select 1 from solar_private.receipt_delete_executions x where x.request_id=receipt_delete_requests.request_id and x.mode='direct') then
   raise exception 'معرّف الطلب مستخدم لحذف مباشر؛ افتح محاولة جديدة' using errcode='PT409';end if;
 end if;
 if action not in('delete_direct','approve') then
  return solar_private.receipt_delete_requests_v3102(action,request_id,payload);
 end if;
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 if p.id is null then raise exception 'لا تملك صلاحية حذف الوصولات' using errcode='42501';end if;
 if request_id is null then raise exception 'رقم طلب الحفظ مطلوب' using errcode='22023';end if;
 perform pg_advisory_xact_lock(7311,1);
 if action='approve' then
  if not p.is_admin then raise exception 'الموافقة للإدارة فقط' using errcode='42501';end if;
  select * into r from solar_private.receipt_delete_requests q where q.id=request_id for update;
  if r.id is null or r.status<>'pending' then return solar_private.receipt_delete_requests_v3102(action,request_id,payload);end if;
  perform 1 from public.transactions where id=r.invoice_id for update;
  c:=solar_private.receipt_delete_context(r.invoice_id);
  insert into solar_private.receipt_delete_executions(request_id,invoice_id,actor_id,mode,submission,snapshot,execution_txid)
   values(request_id,r.invoice_id,p.id,'approval',payload,c,txid_current());
  result:=solar_private.receipt_delete_requests_v3102(action,request_id,payload);
  update solar_private.receipt_delete_executions x set completed_at=now(),result=result where x.request_id=receipt_delete_requests.request_id;
  return result;
 end if;
 select * into e from solar_private.receipt_delete_executions x where x.request_id=receipt_delete_requests.request_id;
 if found then
  if e.mode='direct' and e.actor_id=p.id and e.submission=payload and e.completed_at is not null then return e.result;end if;
  raise exception 'طلب مكرر ببيانات مختلفة' using errcode='PT409';
 end if;
 if exists(select 1 from solar_private.receipt_delete_requests q where q.id=request_id) then
  raise exception 'معرّف طلب الموافقة لا يستخدم للحذف المباشر' using errcode='PT409';end if;
 invoice_id:=(payload->>'invoiceId')::bigint;
 select * into t from public.transactions where id=invoice_id for update;
 c:=solar_private.receipt_delete_context(invoice_id);
 if c->>'blockedReason' is not null then raise exception '%',c->>'blockedReason' using errcode='PT409';end if;
 if not coalesce((c->>'directEligible')::boolean,false) then
  raise exception '%',coalesce(c->>'directBlockedReason','يلزم طلب موافقة الإدارة على حذف هذا الوصل') using errcode='PT409';end if;
 if payload->>'expectedToken' is distinct from c->>'token' then raise exception 'تغير الوصل؛ راجعه وأعد محاولة الحذف' using errcode='PT409';end if;
 if length(coalesce(payload->>'reason',''))>1000 then raise exception 'سبب الحذف طويل' using errcode='22023';end if;
 insert into solar_private.receipt_delete_executions(request_id,invoice_id,actor_id,mode,submission,snapshot,execution_txid)
  values(request_id,t.id,p.id,'direct',payload,c,txid_current());
 if t.kind in('sale','system') then
  preview:=solar_private.sale_delete_data(t.id);perform solar_private.currency_sale_delete(t.id,preview->>'token');
 elsif t.kind='purchase' then perform solar_private.purchase_delete(t.id,t.pricing_revision);
 else raise exception 'هذا النوع يحتاج موافقة الإدارة' using errcode='42501';end if;
 result:=jsonb_build_object('id',request_id,'invoiceId',t.id,'status','deleted','direct',true);
 update solar_private.receipt_delete_executions x set completed_at=now(),result=result where x.request_id=receipt_delete_requests.request_id;
 -- An old request is retained for audit and is never silently approved.
 update solar_private.receipt_delete_requests q set status='cancelled',decided_at=now(),decided_by=p.id,
  decision_note='أُلغي الطلب بعد حذف مباشر مصرح به من حالة الوصل.' where q.invoice_id=t.id and q.status='pending';
 return result;
end$$;
revoke all on function solar_private.receipt_delete_requests(text,uuid,jsonb) from public,anon;
grant execute on function solar_private.receipt_delete_requests(text,uuid,jsonb) to authenticated;
create or replace function public.solar_receipt_delete_requests(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select solar_private.receipt_delete_requests(action,request_id,payload)$$;

-- Legacy RPC entrypoints must not skip eligibility/review, even for admins.
do $$declare definition text;needle text;begin
 definition:=pg_get_functiondef('solar_private.sale_delete(bigint,text)'::regprocedure);
 needle:=$needle$if not exists(select 1 from public.profiles a where a.id=auth.uid() and a.active and a.is_admin and a.user_type not in('warehouse','installer'))then raise exception 'لا يمكن حذف الوصل قبل موافقة الإدارة' using errcode='42501';end if;$needle$;
 if strpos(definition,needle)=0 then raise exception 'Sale deletion authorization contract changed';end if;
 execute replace(definition,needle,$replacement$if not solar_private.receipt_delete_authorized(invoice_id) then raise exception 'استخدم الحذف المباشر المصرح به أو موافقة طلب الحذف' using errcode='42501';end if;$replacement$);
 definition:=pg_get_functiondef('solar_private.purchase_delete(bigint,bigint)'::regprocedure);
 needle:=$needle$select * into actor from public.profiles where id=auth.uid() and active and is_admin and user_type not in('warehouse','installer');
 if actor.id is null then raise exception 'لا يمكن حذف الوصل قبل موافقة الإدارة' using errcode='42501';end if;$needle$;
 if strpos(definition,needle)=0 then raise exception 'Purchase deletion authorization contract changed';end if;
 execute replace(definition,needle,$replacement$select * into actor from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 if actor.id is null or not solar_private.receipt_delete_authorized(invoice_id) then raise exception 'استخدم الحذف المباشر المصرح به أو موافقة طلب الحذف' using errcode='42501';end if;$replacement$);
end$$;

create or replace function solar_private.guard_receipt_delete_approval() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is not null and old.kind in('sale','system','purchase') then
  if not solar_private.receipt_delete_authorized(old.id) then raise exception 'استخدم الحذف المباشر المصرح به أو موافقة طلب الحذف' using errcode='42501';end if;
 elsif auth.uid() is not null and old.kind in('customer_payment','system_payment','supplier_payment','cash_income','cash_expense','profit_distribution')
  and not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.is_admin and p.user_type not in('warehouse','installer')) then
  raise exception 'لا يمكن حذف الوصل قبل موافقة الإدارة' using errcode='42501';
 end if;
 return old;
end$$;
notify pgrst,'reload schema';
