-- Reuse only the original receipt balances, never the save response's internal
-- account context or cashbox summary for a statement-only reader.
do $$declare definition text;needle text:=$n$receipt:=coalesce(snapshot,'{}')||jsonb_build_object('id',t.id$n$;begin
 definition:=pg_get_functiondef('solar_private.payment_history(text,jsonb)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Payment receipt projection contract missing';end if;
 definition:=replace(definition,needle,$n$receipt:=jsonb_build_object('id',t.id$n$);
 execute definition;
end$$;
notify pgrst,'reload schema';
