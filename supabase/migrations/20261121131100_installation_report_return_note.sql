-- Match the correction form for tabs/newlines as well as ordinary spaces.
do $migration$
declare definition text:=pg_get_functiondef('solar_private.installation_action(bigint,bigint,text,jsonb)'::regprocedure);
 original constant text:=$find$length(btrim(payload->>'notes')) not between 1 and 4000$find$;
begin
 if strpos(definition,original)=0 then raise exception 'Unexpected return note validation';end if;
 execute replace(definition,original,$put$length(payload->>'notes')>4000 or (payload->>'notes') !~ '[^[:space:]]'$put$);
end
$migration$;
