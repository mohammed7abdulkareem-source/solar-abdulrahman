-- The shared standard quote calculator serves previews and draft saves/reads.
-- Its all-in-one branch returns before this battery capacity check.
do $migration$
declare
 definition text:=pg_get_functiondef('solar_private.prepare_limited_quote(jsonb)'::regprocedure);
 existing_guard constant text:='capacity not in (5,7.5,10,15,25,30)';
begin
 if array_length(string_to_array(definition,existing_guard),1) is distinct from 2 then
  raise exception 'Review the standard Tahseel battery capacity guard';
 end if;
 execute replace(definition,existing_guard,'capacity not in (5,7.5,10,15,16,25,30,32)');
end $migration$;
