create table solar_private.receipt_delete_requests(
 id uuid primary key,invoice_id bigint not null,kind text not null,
 owner_id uuid not null references public.profiles(id),requested_by uuid not null references public.profiles(id),
 status text not null default 'pending' check(status in('pending','approved','rejected','cancelled')),
 request_token text not null,snapshot jsonb not null,submission jsonb not null,
 reason text not null default '',decision_note text not null default '',
 created_at timestamptz not null default now(),decided_at timestamptz,decided_by uuid references public.profiles(id)
);
alter table solar_private.receipt_delete_requests enable row level security;
revoke all on solar_private.receipt_delete_requests from public,anon,authenticated;
create unique index receipt_delete_pending_invoice on solar_private.receipt_delete_requests(invoice_id)where status='pending';
create index receipt_delete_owner on solar_private.receipt_delete_requests(owner_id,created_at desc);
create index receipt_delete_requester on solar_private.receipt_delete_requests(requested_by,created_at desc);
create index receipt_delete_decider on solar_private.receipt_delete_requests(decided_by);
alter table public.solar_notifications add column delete_request_id uuid references solar_private.receipt_delete_requests(id)on delete cascade;
create index solar_notice_delete_request on public.solar_notifications(delete_request_id);
do $$declare definition text;begin
 select pg_get_constraintdef(oid)into definition from pg_constraint where conrelid='public.solar_notifications'::regclass and conname='solar_notifications_event_check';
 if definition is null then raise exception 'Missing notification event constraint';end if;
 alter table public.solar_notifications drop constraint solar_notifications_event_check;
 execute 'alter table public.solar_notifications add constraint solar_notifications_event_check '||left(definition,length(definition)-1)||' OR event IN(''receipt_delete_requested'',''receipt_delete_decided''))';
end$$;

create function solar_private.receipt_delete_context(invoice_id bigint)returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;t public.transactions;items jsonb;cash_entries jsonb;linked jsonb;fx jsonb;wallet jsonb;preview jsonb;uid uuid;blocked text;
begin
 select * into p from public.profiles where id=auth.uid()and active and user_type not in('installer','warehouse');
 if p.id is null then raise exception 'لا تملك صلاحية الوصولات'using errcode='42501';end if;
 select * into t from public.transactions where id=invoice_id and kind in('sale','system','purchase','customer_payment','supplier_payment','system_payment');
 uid:=case when t.kind in('sale','system','purchase')then t.created_by else coalesce(t.cashbox_user_id,t.created_by)end;
 if t.id is null or uid is null or(not p.is_admin and uid<>p.id)then raise exception 'يمكنك طلب حذف وصولاتك فقط'using errcode='42501';end if;
 if t.supplier_payment_voided_at is not null then raise exception 'الوصل ملغى مسبقًا'using errcode='PT409';end if;
 select coalesce(jsonb_agg(to_jsonb(i)order by i.id),'[]')into items from public.transaction_items i where i.transaction_id=t.id;
 select coalesce(jsonb_agg(to_jsonb(e)order by e.id),'[]')into cash_entries from public.solar_cash_entries e where e.job_id=t.id;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.id),'[]')into linked from public.transactions x where x.system_invoice_id=t.id;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.id),'[]')into fx from solar_private.supplier_fx_entries x where x.transaction_id=t.id;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.id),'[]')into wallet from solar_private.wallet_fx_entries x where x.transaction_id=t.id;
 if t.kind in('sale','system')then preview:=solar_private.sale_delete_data(t.id);blocked:=preview->>'blockedReason';
 elsif t.profit_settlement_id is not null or t.profit_supplier_settlement_id is not null then blocked:='هذا الوصل مرتبط بتسوية أرباح؛ راجع التسوية أولًا.';
 elsif t.payment_mode in('opening_balance','account_reconciliation')then blocked:='الرصيد الافتتاحي والمطابقة يُصححان من حساب العميل.';end if;
 return jsonb_build_object('id',t.id,'kind',t.kind,'receiptNo',t.receipt_no,'party',t.party_name,'total',case when t.source_currency='USD'then coalesce(t.source_subtotal,t.total)else t.total end,'currency',t.source_currency,
  'ownerId',uid,'ownerName',(select solar_private.user_name(display_name,username,honorific)from public.profiles where id=uid),
  'invoice',to_jsonb(t),'items',items,'expenseRefunds',coalesce(preview->'expenseRefunds','[]'),
  'expenseRefund',coalesce((preview->>'expenseRefund')::numeric,0),'retainedPayments',jsonb_array_length(linked),'blockedReason',blocked,
  'token',md5(to_jsonb(t)::text||items::text||cash_entries::text||linked::text||fx::text||wallet::text));
end$$;
revoke all on function solar_private.receipt_delete_context(bigint)from public,anon,authenticated;

create function solar_private.receipt_delete_requests(action text,request_id uuid default null,payload jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare p public.profiles;r solar_private.receipt_delete_requests;c jsonb;review_token text;result jsonb;target uuid;nid uuid;invoice_id bigint;preview jsonb;t public.transactions;reason text;
begin
 select * into p from public.profiles where id=auth.uid()and active and user_type not in('installer','warehouse');
 if p.id is null then raise exception 'لا تملك صلاحية طلبات الحذف'using errcode='42501';end if;
 if action not in('context','request','list','get','approve','reject','cancel')or jsonb_typeof(payload)is distinct from 'object'then raise exception 'طلب غير صحيح'using errcode='22023';end if;
 if action='context'then return solar_private.receipt_delete_context((payload->>'invoiceId')::bigint);end if;
 if action='list'then
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'invoiceId',x.invoice_id,'kind',x.kind,'status',x.status,'reason',x.reason,'decisionNote',x.decision_note,'createdAt',x.created_at,'decidedAt',x.decided_at,
   'receiptNo',x.snapshot->'receiptNo','party',x.snapshot->'party','total',x.snapshot->'total','currency',x.snapshot->'currency','ownerName',x.snapshot->'ownerName',
   'requesterName',(select solar_private.user_name(display_name,username,honorific)from public.profiles where id=x.requested_by))order by x.created_at desc),'[]')into result
  from(select * from solar_private.receipt_delete_requests q where(p.is_admin or q.owner_id=p.id)and(coalesce(payload->>'status','')=''or q.status=payload->>'status')order by q.created_at desc limit 100)x;
  return jsonb_build_object('rows',result,'isAdmin',p.is_admin);
 end if;
 perform pg_advisory_xact_lock(7311,1);
 if action='request'then
  if request_id is null then raise exception 'رقم طلب الحفظ مطلوب'using errcode='22023';end if;
  select * into r from solar_private.receipt_delete_requests q where q.id=request_id;
  if found then
   if r.requested_by=p.id and r.submission=payload and(p.is_admin or r.owner_id=p.id)then return jsonb_build_object('id',r.id,'status',r.status);end if;
   raise exception 'طلب مكرر ببيانات مختلفة'using errcode='PT409';
  end if;
  invoice_id:=(payload->>'invoiceId')::bigint;c:=solar_private.receipt_delete_context(invoice_id);
  if c->>'blockedReason'is not null then raise exception '%',c->>'blockedReason';end if;
  if payload->>'expectedToken'is distinct from c->>'token'then raise exception 'تغير الوصل؛ راجعه وأعد إرسال الطلب'using errcode='PT409';end if;
  reason:=trim(coalesce(payload->>'reason',''));if length(reason)>1000 then raise exception 'سبب الحذف طويل'using errcode='22023';end if;
  select * into r from solar_private.receipt_delete_requests q where q.invoice_id=invoice_id and q.status='pending';
  if found then return jsonb_build_object('id',r.id,'status',r.status);end if;
  insert into solar_private.receipt_delete_requests(id,invoice_id,kind,owner_id,requested_by,request_token,snapshot,submission,reason)
   values(request_id,invoice_id,c->>'kind',(c->>'ownerId')::uuid,p.id,c->>'token',c,payload,reason)returning * into r;
  for target in select id from public.profiles where active and is_admin and user_type not in('installer','warehouse')loop
   insert into public.solar_notifications(user_id,event,title,body,delete_request_id)values(target,'receipt_delete_requested','طلب موافقة على حذف وصل',
    solar_private.user_name(p.display_name,p.username,p.honorific)||' يطلب حذف الوصل #'||(c->>'receiptNo')||' · '||coalesce(c->>'party','وصل نقدي'),r.id)returning id into nid;
   insert into solar_private.push_deliveries(notification_id,endpoint)select nid,s.endpoint from public.solar_push_subscriptions s where s.user_id=target;
  end loop;
  perform solar_private.wake_push();return jsonb_build_object('id',r.id,'status',r.status);
 end if;
 select * into r from solar_private.receipt_delete_requests q where q.id=request_id for update;
 if r.id is null or(not p.is_admin and r.owner_id<>p.id)then raise exception 'الطلب غير متاح ضمن صلاحياتك'using errcode='42501';end if;
 if action='get'then
  if r.status='pending'then
   begin c:=solar_private.receipt_delete_context(r.invoice_id);exception when others then c:=null;end;
  end if;
  review_token:=md5(to_jsonb(r)::text||coalesce(c->>'token','missing'));
  return jsonb_build_object('id',r.id,'status',r.status,'snapshot',r.snapshot,'current',c,'reason',r.reason,'decisionNote',r.decision_note,
   'requesterName',(select solar_private.user_name(display_name,username,honorific)from public.profiles where id=r.requested_by),
   'stale',c is null or c->>'token'is distinct from r.request_token,'reviewToken',review_token);
 end if;
 if action in('approve','reject')and not p.is_admin then raise exception 'الموافقة والرفض للإدارة فقط'using errcode='42501';end if;
 if r.status<>'pending'then return jsonb_build_object('id',r.id,'status',r.status);end if;
 if action='approve'then
  c:=solar_private.receipt_delete_context(r.invoice_id);review_token:=md5(to_jsonb(r)::text||coalesce(c->>'token','missing'));
  if payload->>'expectedToken'is distinct from review_token or c->>'token'is distinct from r.request_token then raise exception 'تغير الوصل بعد طلب الحذف؛ ارفض الطلب واطلب مراجعته من جديد'using errcode='PT409';end if;
  if c->>'blockedReason'is not null then raise exception '%',c->>'blockedReason';end if;
  select * into t from public.transactions where id=r.invoice_id for update;
  if t.kind in('sale','system')then preview:=solar_private.sale_delete_data(t.id);perform solar_private.currency_sale_delete(t.id,preview->>'token');
  elsif t.kind='purchase'then perform solar_private.purchase_delete(t.id,t.pricing_revision);
  elsif t.kind='customer_payment'then preview:=solar_private.customer_payment_manage('get',null,jsonb_build_object('id',t.id));perform solar_private.customer_payment_manage('delete',r.id,jsonb_build_object('id',t.id,'expectedToken',preview->>'token'));
  elsif t.kind='supplier_payment'then preview:=solar_private.supplier_payment_manage('get',null,jsonb_build_object('id',t.id));perform solar_private.supplier_payment_manage('delete',r.id,jsonb_build_object('id',t.id,'expectedToken',preview->>'token'));
  elsif t.kind='system_payment'then delete from public.cash_ledger where transaction_id=t.id;delete from public.transactions where id=t.id;
  else raise exception 'نوع الوصل غير مدعوم'using errcode='22023';end if;
 end if;
 reason:=trim(coalesce(payload->>'note',''));if length(reason)>1000 then raise exception 'الملاحظة طويلة'using errcode='22023';end if;
 update solar_private.receipt_delete_requests q set status=case action when 'approve'then 'approved'when 'reject'then 'rejected'else 'cancelled'end,
  decided_by=p.id,decided_at=now(),decision_note=reason where q.id=r.id returning * into r;
 for target in select distinct id from public.profiles where id in(r.requested_by,r.owner_id)and active and user_type not in('installer','warehouse')and(id=r.owner_id or is_admin)loop
  insert into public.solar_notifications(user_id,event,title,body,delete_request_id)values(target,'receipt_delete_decided',
   case r.status when 'approved'then 'تمت الموافقة على حذف الوصل'when 'rejected'then 'رُفض طلب حذف الوصل'else 'أُلغي طلب حذف الوصل'end,
   'الوصل #'||(r.snapshot->>'receiptNo')||case when reason<>''then ' · '||reason else ''end,r.id)returning id into nid;
  insert into solar_private.push_deliveries(notification_id,endpoint)select nid,s.endpoint from public.solar_push_subscriptions s where s.user_id=target;
 end loop;
 perform solar_private.wake_push();return jsonb_build_object('id',r.id,'status',r.status);
end$$;
revoke all on function solar_private.receipt_delete_requests(text,uuid,jsonb)from public,anon;
grant execute on function solar_private.receipt_delete_requests(text,uuid,jsonb)to authenticated;
create function public.solar_receipt_delete_requests(action text,request_id uuid default null,payload jsonb default '{}')returns jsonb language sql security invoker set search_path='' as $$select solar_private.receipt_delete_requests(action,request_id,payload)$$;
revoke all on function public.solar_receipt_delete_requests(text,uuid,jsonb)from public,anon;
grant execute on function public.solar_receipt_delete_requests(text,uuid,jsonb)to authenticated;
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
 where(n.event<>'receipt_delete_decided'or p.is_admin or exists(select 1 from solar_private.receipt_delete_requests rq where rq.id=n.delete_request_id and rq.owner_id=p.id))and(n.event not in('receipt_delete_requested','receipt_delete_decided')or(p.user_type not in('installer','warehouse')and(n.event<>'receipt_delete_requested'or p.is_admin))) and(n.stock_transfer_id is null or solar_private.can_view_transfer(n.user_id,n.stock_transfer_id)) and(n.job_id is null or solar_private.notification_recipient_allowed(n.user_id,n.job_id)) and d.attempts<5 and n.created_at>now()-interval '1 day' and ((d.status='pending' and d.available_at<=now()) or (d.status='sending' and d.lease_until<now()))
 order by d.available_at for update of d skip locked limit 20
 ), claimed as (
 update solar_private.push_deliveries d set status='sending',attempts=attempts+1,lease_until=now()+interval '2 minutes'
 from eligible e where d.id=e.id returning d.*
 )
 select coalesce(jsonb_agg(jsonb_build_object('deliveryId',d.id,'attempt',d.attempts,'endpoint',s.endpoint,'keys',jsonb_build_object('p256dh',s.p256dh,'auth',s.auth_key),'notification',jsonb_build_object('id',n.id,'userId',n.user_id,'jobId',n.job_id,'event',n.event,'invoiceKind',(select t.kind from public.transactions t where t.id=n.job_id),'deleteRequestId',n.delete_request_id,'stockTransferId',n.stock_transfer_id,'transferId',n.transfer_id,'title',n.title,'body',n.body))),'[]'::jsonb)
 into result from claimed d join public.solar_notifications n on n.id=d.notification_id join public.solar_push_subscriptions s on s.endpoint=d.endpoint and s.user_id=n.user_id;
 return result;
end $function$;
-- Backstop for legacy rows and direct Data API calls as well as modern RPCs.
create function solar_private.guard_receipt_delete_approval()returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid()is not null and old.kind in('sale','system','purchase','customer_payment','system_payment','supplier_payment')and not exists(select 1 from public.profiles p where p.id=auth.uid()and p.active and p.is_admin and p.user_type not in('warehouse','installer'))then
  raise exception 'لا يمكن حذف الوصل قبل موافقة الإدارة'using errcode='42501';
 end if;
 return old;
end$$;
revoke all on function solar_private.guard_receipt_delete_approval()from public,anon,authenticated;
create trigger solar_receipt_delete_approval before delete on public.transactions for each row execute function solar_private.guard_receipt_delete_approval();
notify pgrst,'reload schema';
