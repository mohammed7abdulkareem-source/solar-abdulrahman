-- Resolve an uncertain invoice before replacing its payload. An absent request
-- is fenced off under the invoice lock so a delayed original cannot post later.
create table solar_private.invoice_attempt_cancellations(
 request_id uuid primary key,user_id uuid not null references public.profiles(id) on delete cascade,created_at timestamptz not null default now()
);
create index invoice_attempt_cancellations_user on solar_private.invoice_attempt_cancellations(user_id);
alter table solar_private.invoice_attempt_cancellations enable row level security;
create policy invoice_attempt_cancellations_no_client on solar_private.invoice_attempt_cancellations for all to authenticated using(false) with check(false);
revoke all on solar_private.invoice_attempt_cancellations from public,anon,authenticated;

create function solar_private.invoice_attempt_resolve(request_id uuid,payload jsonb) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='8s' set statement_timeout='10s' as $$
declare p public.profiles;r solar_private.invoice_requests;t public.transactions;owner uuid;begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('installer','warehouse');
 if p.id is null then raise exception 'الحساب غير مخوّل لتأكيد الفاتورة' using errcode='42501';end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' or coalesce(payload->>'kind','') not in('sale','system','purchase') then raise exception 'محاولة حفظ غير صحيحة' using errcode='22023';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into r from solar_private.invoice_requests where invoice_requests.request_id=invoice_attempt_resolve.request_id;
 if r.request_id is not null then
  if r.user_id<>p.id or r.payload is distinct from payload then raise exception 'محاولة الحفظ غير متاحة لحسابك' using errcode='42501';end if;
  select * into t from public.transactions where id=(r.result->>'id')::bigint;
  if t.id is null then return jsonb_build_object('state','deleted');end if;
  if not solar_private.can_access_invoice(t.created_by,false) then raise exception 'الوصل غير متاح لحسابك' using errcode='42501';end if;
  return jsonb_build_object('state','saved','invoice',jsonb_build_object('id',t.id,'kind',t.kind,'receiptNo',t.receipt_no,'party',t.party_name,'total',t.total,'date',t.created_at));
 end if;
 select user_id into owner from solar_private.invoice_attempt_cancellations c where c.request_id=invoice_attempt_resolve.request_id;
 if owner is not null and owner<>p.id then raise exception 'محاولة الحفظ غير متاحة لحسابك' using errcode='42501';end if;
 insert into solar_private.invoice_attempt_cancellations(request_id,user_id) values(request_id,p.id) on conflict do nothing;
 return jsonb_build_object('state','not_saved');
end$$;
create function public.solar_invoice_attempt_resolve(request_id uuid,payload jsonb) returns jsonb
language sql security invoker set search_path='' as $$select solar_private.invoice_attempt_resolve(request_id,payload)$$;
revoke all on function solar_private.invoice_attempt_resolve(uuid,jsonb),public.solar_invoice_attempt_resolve(uuid,jsonb) from public,anon;
grant execute on function solar_private.invoice_attempt_resolve(uuid,jsonb),public.solar_invoice_attempt_resolve(uuid,jsonb) to authenticated;

do $$declare definition text;needle text:=' perform pg_advisory_xact_lock(7311,1);';begin
 definition:=pg_get_functiondef('solar_private.invoice_save(uuid,jsonb)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Invoice lock contract missing';end if;
 execute replace(definition,needle,needle||$guard$
 if exists(select 1 from solar_private.invoice_attempt_cancellations c where c.request_id=invoice_save.request_id) then raise exception 'المحاولة السابقة انتهت دون حفظ؛ راجع البيانات واضغط حفظ مجددًا' using errcode='PT410';end if;$guard$);
end$$;
notify pgrst,'reload schema';
