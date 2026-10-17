\ir customer-bootstrap.sql
\ir supplier-payment-bootstrap.sql
\ir ../../supabase/migrations/20261005204736_party_balance_reports.sql
CREATE OR REPLACE FUNCTION solar_private.customer_statement(customer_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles; c public.customers; rows jsonb; balance numeric;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 select * into c from public.customers where id=customer_id;
 if p.id is null or p.user_type in ('installer','warehouse') or c.id is null or
 not(p.is_admin or (coalesce(c.owner_id=p.id,false) and coalesce(p.permissions->>'customerStatement','false')='true')) then raise exception 'لا تملك صلاحية كشف هذا العميل' using errcode='42501';end if;
 rows:=solar_private.customer_ledger(c.id);
 select coalesce(sum((r->>'effect')::numeric),0) into balance from jsonb_array_elements(rows) r;
 return jsonb_build_object('rows',rows,'balance',balance,'token',md5(rows::text),'name',c.name);
end $function$
;
create function public.solar_customer_statement(customer_id bigint) returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.customer_statement(customer_id)$$;
revoke all on function solar_private.customer_statement(bigint),public.solar_customer_statement(bigint) from public,anon;
grant execute on function solar_private.customer_statement(bigint),public.solar_customer_statement(bigint) to authenticated;
