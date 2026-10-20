-- New invoices must use the same reserved-ID allocator as payments and cash.
-- The previous inline maximum ignored deleted receipts, so a new purchase could
-- repeatedly collide with a deleted highest ID. Keep tombstones, ownership,
-- posting locks and request replay intact; this migration changes no records.
do $migration$
declare definition text;
 old_allocation text := 'invoice_id:=greatest((extract(epoch from clock_timestamp())*1000)::bigint,coalesce((select max(t.id)+1 from public.transactions t),1));';
begin
 definition := pg_get_functiondef('solar_private.invoice_save_v333(uuid,jsonb)'::regprocedure);
 if strpos(definition,old_allocation)=0 then
  raise exception 'Invoice allocator changed; review the migration before applying';
 end if;
 execute replace(definition,old_allocation,'invoice_id:=solar_private.next_transaction_id();');
end $migration$;
notify pgrst,'reload schema';
