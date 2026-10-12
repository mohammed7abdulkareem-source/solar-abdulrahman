-- Run only in the isolated currency fixture database after the migration.
do $$declare name text; signature regprocedure;begin
 foreach name in array array['exchange_settings','exchange_history','invoice_requests'] loop
  if not(select relrowsecurity from pg_class where oid=('solar_private.'||name)::regclass) then raise exception 'FAIL RLS: %',name;end if;
  if has_table_privilege('authenticated','solar_private.'||name,'SELECT') or has_table_privilege('anon','solar_private.'||name,'SELECT') then raise exception 'FAIL private pricing table readable: %',name;end if;
 end loop;
 foreach signature in array array['public.solar_exchange_rate_get()'::regprocedure,'public.solar_exchange_rate_set(numeric,bigint)'::regprocedure,'public.solar_invoice_save(uuid,jsonb)'::regprocedure,'public.solar_purchase_delete(bigint,bigint)'::regprocedure,'public.solar_sale_delete(bigint,text)'::regprocedure] loop
  if has_function_privilege('anon',signature,'EXECUTE') then raise exception 'FAIL anonymous pricing RPC: %',signature;end if;
  if (select prosecdef from pg_proc where oid=signature) then raise exception 'FAIL public privileged pricing RPC: %',signature;end if;
 end loop;
 foreach signature in array array['solar_private.exchange_get()'::regprocedure,'solar_private.exchange_set(numeric,bigint)'::regprocedure,'solar_private.invoice_save(uuid,jsonb)'::regprocedure,'solar_private.purchase_delete(bigint,bigint)'::regprocedure,'solar_private.currency_sale_delete(bigint,text)'::regprocedure] loop
  if has_function_privilege('anon',signature,'EXECUTE') then raise exception 'FAIL anonymous private function: %',signature;end if;
  if not(select 'search_path=""'=any(proconfig) from pg_proc where oid=signature) then raise exception 'FAIL unpinned function search path: %',signature;end if;
 end loop;
end $$;
