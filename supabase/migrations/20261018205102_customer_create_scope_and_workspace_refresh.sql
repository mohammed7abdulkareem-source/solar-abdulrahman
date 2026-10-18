-- A separate create-only permission; existing customer managers retain access.
-- Ownership is enforced for the Data API as well as the protected RPCs.
create policy solar_customer_owner_scope on public.customers as restrictive
for all to authenticated
using ((select solar_private.role_name())='admin' or owner_id=(select auth.uid()))
with check ((select solar_private.role_name())='admin' or owner_id=(select auth.uid()));

do $migration$
declare definition text; original text; signature text;
begin
 foreach signature in array array[
  'solar_private.customer_get(bigint)',
  'solar_private.customer_directory()',
  'solar_private.customer_check(text,text,bigint)'
 ] loop
  original:=pg_get_functiondef(signature::regprocedure);
  definition:=replace(original,'coalesce(p.permissions->>''customers'',''false'')=''true''',
   '(coalesce(p.permissions->>''customers'',''false'')=''true'' or coalesce(p.permissions->>''customerCreate'',''false'')=''true'')');
  if definition=original then raise exception 'Customer read permission patch did not match: %',signature;end if;
  execute definition;
 end loop;

 original:=pg_get_functiondef('solar_private.customer_save(text,uuid,jsonb)'::regprocedure);
 definition:=replace(original,'coalesce(p.permissions->>''customers'',''false'')=''true''',
  '(coalesce(p.permissions->>''customers'',''false'')=''true'' or (action=''create'' and coalesce(p.permissions->>''customerCreate'',''false'')=''true''))');
 if definition=original then raise exception 'Customer save permission patch did not match';end if;
 execute definition;

 original:=pg_get_functiondef('solar_private.customer_guard()'::regprocedure);
 definition:=replace(original,'coalesce(p.permissions->>''customers'',''false'')=''true''',
  '(coalesce(p.permissions->>''customers'',''false'')=''true'' or (tg_op=''INSERT'' and coalesce(p.permissions->>''customerCreate'',''false'')=''true''))');
 if definition=original then raise exception 'Customer guard permission patch did not match';end if;
 definition:=replace(definition,'if not p.is_admin then','if tg_op=''INSERT'' and (new.customer_type is null or new.customer_type not in (''system'',''wholesale'')) then raise exception ''اختر زبون جملة أو مفرد'';end if;
  if not p.is_admin then');
 execute definition;

 original:=pg_get_functiondef('solar_private.reconcile(text,uuid,jsonb)'::regprocedure);
 definition:=replace(original,'action=''create_customer'' and coalesce(p.permissions->>''customers'',''false'')=''true''',
  'action=''create_customer'' and (coalesce(p.permissions->>''customers'',''false'')=''true'' or coalesce(p.permissions->>''customerCreate'',''false'')=''true'')');
 if definition=original then raise exception 'Customer creation permission patch did not match';end if;
 definition:=replace(definition,'if action=''create_customer'' then',
  'if action=''create_customer'' then
   if payload->>''customerType'' is null or payload->>''customerType'' not in (''system'',''wholesale'') then raise exception ''اختر زبون جملة أو مفرد'';end if;');
 execute definition;
end $migration$;
