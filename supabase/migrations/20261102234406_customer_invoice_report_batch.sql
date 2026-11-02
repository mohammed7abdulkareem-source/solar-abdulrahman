-- Read invoice lines in bounded batches while retaining the exact authorization
-- of customer_documents. The existing ledger token prevents mixing snapshots.
create function solar_private.customer_invoice_report_batch(customer_id bigint, invoice_ids bigint[], expected_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_variable
declare p public.profiles; c public.customers; ledger jsonb; result jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in ('warehouse','installer');
 select * into c from public.customers where id=customer_id;
 if p.id is null or c.id is null or not(p.is_admin or (coalesce(c.owner_id=p.id,false) and
   (coalesce(p.permissions->>'customers','false')='true' or coalesce(p.permissions->>'customerCreate','false')='true' or
    coalesce(p.permissions->>'customerStatement','false')='true'))) then
  raise exception 'لا تملك صلاحية وصولات هذا العميل' using errcode='42501';
 end if;
 if invoice_ids is null or cardinality(invoice_ids)<1 or cardinality(invoice_ids)>100 or array_position(invoice_ids,null) is not null then
  raise exception 'اختر مجموعة صحيحة من الفواتير' using errcode='22023';
 end if;
 ledger:=solar_private.customer_ledger(c.id);
 if expected_token is null or (expected_token<>md5(ledger::text) and expected_token<>md5(to_jsonb(c)::text||ledger::text)) then
  raise exception 'تغيّر الحساب؛ اضغط تحديث قبل عرض الفواتير.' using errcode='PT409';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'kind',t.kind,
   'items',solar_private.customer_invoice_document(t)->'items') order by t.created_at,t.id),'[]'::jsonb)
 into result from public.transactions t
 join jsonb_array_elements(ledger) l on (l->>'id')::bigint=t.id
 where t.id=any(invoice_ids) and t.kind in ('sale','system') and (p.is_admin or t.created_by=p.id);
 return jsonb_build_object('rows',result,'customerName',c.name);
end $$;

create function public.solar_customer_invoice_report_batch(customer_id bigint, invoice_ids bigint[], expected_token text)
returns jsonb language sql stable security invoker set search_path='' as $$
 select solar_private.customer_invoice_report_batch(customer_id,invoice_ids,expected_token)
$$;
revoke all on function solar_private.customer_invoice_report_batch(bigint,bigint[],text),
 public.solar_customer_invoice_report_batch(bigint,bigint[],text) from public,anon,authenticated;
grant execute on function solar_private.customer_invoice_report_batch(bigint,bigint[],text),
 public.solar_customer_invoice_report_batch(bigint,bigint[],text) to authenticated;
notify pgrst,'reload schema';
