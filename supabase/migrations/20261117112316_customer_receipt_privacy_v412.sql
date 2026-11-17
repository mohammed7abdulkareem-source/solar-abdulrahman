-- V4.1.2: retain customer account effects without disclosing foreign receipts.
-- Raw customer_ledger, ownership, balances, write tokens and saved snapshots stay
-- unchanged. Only authorized outward read/receipt projections are redacted.
do $$begin
 if md5(pg_get_functiondef('solar_private.customer_get(bigint)'::regprocedure))is distinct from'0ffe0e64bd5b625b11350f7d2bf4b4d4'
 or md5(pg_get_functiondef('solar_private.customer_statement(bigint)'::regprocedure))is distinct from'5ce3ef5b06b10290d649b457eefee521'
 or md5(pg_get_functiondef('solar_private.system_payment_context(bigint)'::regprocedure))is distinct from'ade7263f06f9ea7ff17e3660d0ea8c3b'
 or md5(pg_get_functiondef('solar_private.system_payment_save(uuid,jsonb)'::regprocedure))is distinct from'450864dc9de6f94107d2b39f4fa90525'
 or md5(pg_get_functiondef('solar_private.customer_documents(bigint,bigint,date,date,text,text)'::regprocedure))is distinct from'd4eedf2f5906adf354ab46269f1af626'
 or md5(pg_get_functiondef('solar_private.customer_payment_manage(text,uuid,jsonb)'::regprocedure))is distinct from'bb18d2627cde8db499015d731ad5f952'
 or md5(pg_get_functiondef('public.solar_system_payment_context(bigint)'::regprocedure))is distinct from'89ac2d0c17b87560d71c2bdc5ecd0731'
 then raise exception 'Unexpected customer receipt privacy baseline';end if;
end$$;

create function solar_private.customer_ledger_read_projection(rows jsonb,customer_id bigint)returns jsonb
language sql stable security definer set search_path=''as $$
 select coalesce(jsonb_agg(case
  when solar_private.invoice_read_allowed((r.value->>'id')::bigint)then
   case when r.value->>'systemInvoiceId'is not null and not solar_private.invoice_read_allowed((r.value->>'systemInvoiceId')::bigint)
    then r.value-'systemInvoiceId'-'systemReceiptNo'else r.value end
  else jsonb_build_object('id','restricted:'||md5(customer_id::text||':'||coalesce(auth.uid()::text,'')||':'||(r.value->>'id')),
   'date',r.value->'date','effect',r.value->'effect','kind',r.value->'kind','mode',r.value->'mode','receiptRestricted',true)
  end order by r.ordinality),'[]'::jsonb)
 from jsonb_array_elements(rows)with ordinality r(value,ordinality)
$$;
revoke all on function solar_private.customer_ledger_read_projection(jsonb,bigint)from public,anon,authenticated;

-- System payment validation intentionally uses the complete private context.
-- The public context offers only readable invoices as allocation choices while
-- retaining the complete account balance and the original concurrency token.
create function solar_private.system_payment_context_read_projection(result jsonb)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare visible jsonb;begin
 if jsonb_typeof(result->'systems')is distinct from'array'or exists(select 1 from public.profiles p where p.id=auth.uid()and p.active and p.is_admin and p.user_type not in('warehouse','installer'))then return result;end if;
 select coalesce(jsonb_agg(x.value order by x.ordinality),'[]')into visible
 from jsonb_array_elements(result->'systems')with ordinality x(value,ordinality)
 where solar_private.invoice_read_allowed((x.value->>'id')::bigint);
 return jsonb_set(result,'{systems}',visible)||jsonb_build_object('restrictedSystemCount',jsonb_array_length(result->'systems')-jsonb_array_length(visible));
end$$;
revoke all on function solar_private.system_payment_context_read_projection(jsonb)from public,anon,authenticated;
create function solar_private.system_payment_context_read(customer_id bigint default null)returns jsonb
language sql stable security definer set search_path=''as $$
 select solar_private.system_payment_context_read_projection(solar_private.system_payment_context(customer_id))
$$;
revoke all on function solar_private.system_payment_context_read(bigint)from public,anon;
grant execute on function solar_private.system_payment_context_read(bigint)to authenticated;
revoke all on function solar_private.system_payment_context(bigint)from public,anon,authenticated;
create or replace function public.solar_system_payment_context(customer_id bigint default null)returns jsonb
language sql security invoker set search_path=''as $$
 select solar_private.receipt_contact_json(solar_private.system_payment_context_read(customer_id),'own')
$$;

-- Apply projections at the return expression, after original balance/token math.
do $$declare definition text;begin
 definition:=pg_get_functiondef('solar_private.customer_get(bigint)'::regprocedure);
 if strpos(definition,'''rows'',rows,')=0 then raise exception 'Unexpected customer get rows';end if;
 execute replace(definition,'''rows'',rows,','''rows'',solar_private.customer_ledger_read_projection(rows,c.id),');
 definition:=pg_get_functiondef('solar_private.customer_statement(bigint)'::regprocedure);
 if strpos(definition,'''rows'',rows,')=0 then raise exception 'Unexpected customer statement rows';end if;
 execute replace(definition,'''rows'',rows,','''rows'',solar_private.customer_ledger_read_projection(rows,c.id),');
 definition:=pg_get_functiondef('solar_private.customer_documents(bigint,bigint,date,date,text,text)'::regprocedure);
 if strpos(definition,'when l.x->>''systemReceiptNo'' is not null then')=0 then raise exception 'Unexpected customer linked receipt label';end if;
 execute replace(definition,'when l.x->>''systemReceiptNo'' is not null then','when l.x->>''systemReceiptNo'' is not null and solar_private.invoice_read_allowed((l.x->>''systemInvoiceId'')::bigint) then');
 -- Payment management's list used customer ownership, which does not imply
 -- permission to read a payment another creator posted to that account.
 definition:=pg_get_functiondef('solar_private.customer_payment_manage(text,uuid,jsonb)'::regprocedure);
 if strpos(definition,'and (p.is_admin or cu.owner_id=p.id) and (payload->>''customerId''')=0
  or strpos(definition,' if action=''get'' then')=0 then raise exception 'Unexpected customer payment read boundaries';end if;
 definition:=replace(definition,'and (p.is_admin or cu.owner_id=p.id) and (payload->>''customerId''',
  'and (p.is_admin or cu.owner_id=p.id) and (p.is_admin or tx.created_by=p.id) and (payload->>''customerId''');
 definition:=replace(definition,' if action=''get'' then',' if action=''get'' then
  if not solar_private.invoice_read_allowed(t.id)then raise exception ''التسديد غير متاح ضمن صلاحياتك''using errcode=''42501'';end if;');
 execute definition;
 -- Copy the original accounting implementation and fix its implicit block label.
 -- Cache contents and write validation remain byte-equivalent in behavior.
 definition:=pg_get_functiondef('solar_private.system_payment_save(uuid,jsonb)'::regprocedure);
 definition:=replace(definition,'FUNCTION solar_private.system_payment_save(','FUNCTION solar_private.system_payment_save_v411(');
 definition:=replace(definition,'system_payment_save.request_id','system_payment_save_v411.request_id');
 execute definition;
end$$;
revoke all on function solar_private.system_payment_save_v411(uuid,jsonb)from public,anon,authenticated;

create or replace function solar_private.system_payment_save(request_id uuid,payload jsonb)returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s'as $$
declare result jsonb;linked_id bigint;begin
 result:=solar_private.system_payment_save_v411(request_id,payload);
 if jsonb_typeof(result->'accountContext')='object'then
  result:=jsonb_set(result,'{accountContext}',solar_private.system_payment_context_read_projection(result->'accountContext'));
 end if;
 linked_id:=coalesce((result->>'systemInvoiceId')::bigint,(result->'invoice'->>'id')::bigint);
 if linked_id is not null and not solar_private.invoice_read_allowed(linked_id)then
  result:=result||jsonb_build_object('systemInvoiceId',null,'invoice',null,'invoiceBefore',null,'invoiceAfter',null,'linkedReceiptRestricted',true);
 end if;
 return result;
end$$;
-- Existing original save grants remain: no new raw data entrypoint is exposed.
notify pgrst,'reload schema';
