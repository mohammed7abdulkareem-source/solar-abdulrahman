-- A deleted highest transaction ID remains reserved. New cash movements must
-- not reuse it; the guard against recreating deleted invoices stays in force.
create function solar_private.next_transaction_id() returns bigint language plpgsql security definer set search_path='' as $$
declare candidate bigint;begin
 perform pg_advisory_xact_lock(7311,1);
 select greatest((extract(epoch from clock_timestamp())*1000)::bigint,
  coalesce((select max(id)+1 from public.transactions),1),
  coalesce((select max(invoice_id)+1 from solar_private.deleted_sales),1),
  coalesce((select max(record_id)+1 from solar_private.reset_record_ids where table_name='transactions'),1)) into candidate;
 if candidate>9007199254740991 then raise exception 'تعذر تخصيص رقم حركة آمن؛ راجع الإدارة';end if;
 return candidate;
end $$;
revoke all on function solar_private.next_transaction_id() from public,anon,authenticated;
do $$declare signature text;def text;needle text;begin
 needle:='greatest((extract(epoch from clock_timestamp())*1000)::bigint,coalesce((select max(id)+1 from public.transactions),1))';
 foreach signature in array array['solar_private.system_payment_save(uuid,jsonb)','solar_private.customer_payment_save(uuid,jsonb)','solar_private.cash_save(uuid,jsonb)','solar_private.supplier_payment_manage(text,uuid,jsonb)'] loop
  select pg_get_functiondef(signature::regprocedure) into def;
  if strpos(def,needle)=0 then raise exception 'Review transaction ID allocation: %',signature;end if;
  execute replace(def,needle,'solar_private.next_transaction_id()');
 end loop;
end $$;
-- Business conflicts are permanent for the submitted payload, not PostgreSQL
-- serialization failures. PostgREST 14 can retry a custom 40001 indefinitely.
-- PT409 returns the conflict immediately while true engine 40001 errors remain
-- untouched. No guard, lock, expected token or idempotency check is removed.
do $$declare fn record;definition text;begin
 for fn in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='solar_private' and p.prokind='f' loop
  definition:=pg_get_functiondef(fn.oid);
  if definition ~ 'errcode[[:space:]]*=[[:space:]]*''40001''' then
   definition:=regexp_replace(definition,'errcode[[:space:]]*=[[:space:]]*''40001''','errcode=''PT409''','g');execute definition;
  end if;
 end loop;
end $$;
notify pgrst,'reload schema';
