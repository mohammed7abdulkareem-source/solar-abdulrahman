-- Return the committed account snapshot with the receipt. Existing permissions,
-- transaction locks, stale-token checks and replay keys are left in place.
do $$declare def text;needle text;begin
 select pg_get_functiondef('solar_private.system_payment_save(uuid,jsonb)'::regprocedure) into def;
 needle:='insert into solar_private.system_payment_requests(request_id,actor_id,payload,response)';
 if strpos(def,needle)=0 then raise exception 'Review system receipt integration';end if;
 def:=replace(def,needle,'result:=result||jsonb_build_object(''accountContext'',after_account); '||needle);execute def;
 select pg_get_functiondef('solar_private.customer_payment_save(uuid,jsonb)'::regprocedure) into def;
 needle:='insert into solar_private.finance_requests(request_id,actor_id,action,payload,response)';
 if strpos(def,needle)=0 then raise exception 'Review wholesale receipt integration';end if;
 def:=replace(def,needle,'result:=result||jsonb_build_object(''accountContext'',solar_private.customer_payment_context((a->>''id'')::bigint)); '||needle);execute def;
 select pg_get_functiondef('solar_private.fx(text,uuid,jsonb)'::regprocedure) into def;
 needle:='result:=solar_private.supplier_payment_get(tid);';
 if strpos(def,needle)=0 then raise exception 'Review supplier receipt integration';end if;
 def:=replace(def,needle,needle||' result:=result||jsonb_build_object(''accountContext'',solar_private.fx(''account'',null,jsonb_build_object(''supplierId'',sid,''paymentId'',tid)));');execute def;
end $$;
notify pgrst,'reload schema';
