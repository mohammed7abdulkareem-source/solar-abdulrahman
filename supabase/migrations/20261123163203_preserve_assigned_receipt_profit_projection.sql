-- Restore the existing dual-assignment exception for posted sales and systems
-- after applying the supplier privacy rules to personal reports.
do $migration$
declare definition text:=pg_get_functiondef('solar_private.profit_read_projection(jsonb)'::regprocedure);
begin
 if strpos(definition,'and not solar_private.invoice_read_allowed(substr(source_key,4)::bigint) then')=0
  or strpos(definition,'solar_private.assigned_profit_receipt(')>0 then
  raise exception 'Review current delegated receipt projection';
 end if;
 definition:=replace(definition,
  $old$and not solar_private.invoice_read_allowed(substr(source_key,4)::bigint) then$old$,
  $new$and not solar_private.invoice_read_allowed(substr(source_key,4)::bigint) then
   if not coalesce((value->>'deleted')::boolean,false)
      and solar_private.assigned_profit_receipt(substr(source_key,4)::bigint,auth.uid(),true) then
    return result||jsonb_build_object('assignedReceipt',true,'label',coalesce(
     (select nullif(t.party_name,'') from public.transactions t where t.id=substr(source_key,4)::bigint),'ربح وصل بيع'));
   end if;$new$);
 execute definition;
end $migration$;
