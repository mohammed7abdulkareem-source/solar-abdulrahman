-- Execute only on an isolated database seeded with the v3.98 fixtures.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003981',true);
do $$
declare record_json jsonb; ledger_token text; result jsonb; ids bigint[];
begin
 record_json:=public.solar_customer_get(-398001); ledger_token:=record_json->>'token';
 result:=public.solar_customer_invoice_report_batch(-398001,array[-398101,-398400],ledger_token);
 if jsonb_array_length(result->'rows')<>1 or result#>>'{rows,0,id}' <> '-398101' or result#>>'{rows,0,items,0,price}' is null then
  raise exception 'own invoice or creator isolation failed: %',result;
 end if;
 record_json:=public.solar_customer_statement(-398001);
 result:=public.solar_customer_invoice_report_batch(-398001,array[-398101],record_json->>'token');
 if jsonb_array_length(result->'rows')<>1 then raise exception 'statement token rejected';end if;
 begin
  perform public.solar_customer_invoice_report_batch(-398001,array[-398101],'stale');
  raise exception 'stale ledger was accepted';
 exception when sqlstate 'PT409' then null;end;
 begin
  select array_agg(-398100-n) into ids from generate_series(1,101)n;
  perform public.solar_customer_invoice_report_batch(-398001,ids,ledger_token);
  raise exception 'unbounded batch was accepted';
 exception when invalid_parameter_value then null;end;
 begin
  perform public.solar_customer_invoice_report_batch(-398002,array[-398101],ledger_token);
  raise exception 'other customer was accepted';
 exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003920',true);
do $$declare token text; result jsonb; begin
 token:=public.solar_customer_get(-398001)->>'token';
 result:=public.solar_customer_invoice_report_batch(-398001,array[-398101,-398400],token);
 if jsonb_array_length(result->'rows')<>2 then raise exception 'admin did not see authorized invoices';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003914',true);
do $$begin
 begin
  perform public.solar_customer_invoice_report_batch(-398001,array[-398101],'x');
  raise exception 'warehouse user was accepted';
 exception when insufficient_privilege then null;end;
end$$;
rollback;
do $$begin
 if has_function_privilege('anon','public.solar_customer_invoice_report_batch(bigint,bigint[],text)','EXECUTE') or
    has_function_privilege('anon','solar_private.customer_invoice_report_batch(bigint,bigint[],text)','EXECUTE') then
  raise exception 'anonymous execution allowed';end if;
end$$;
