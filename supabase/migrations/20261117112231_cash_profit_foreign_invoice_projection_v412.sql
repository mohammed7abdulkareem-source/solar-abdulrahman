-- V4.1.2: isolate foreign invoice descriptions in authorized financial read models.
-- No ledger filtering, historical data changes, RLS/grant broadening, token changes or repricing.
do $guard$
begin
 if md5(pg_get_functiondef('solar_private.cash_workspace(jsonb)'::regprocedure)) <> '5be3d75ae8a933ccc601619ccdee6559' then raise exception 'Unexpected definition: solar_private.cash_workspace(jsonb)';end if;
 if md5(pg_get_functiondef('solar_private.cash_statement(uuid,date,date,text)'::regprocedure)) <> '5b2accab380d58ae041693d33257f29c' then raise exception 'Unexpected definition: solar_private.cash_statement(uuid,date,date,text)';end if;
 if md5(pg_get_functiondef('solar_private.cash_movement_detail(text)'::regprocedure)) <> '0a6252820825ff1dd50563f3b52d2319' then raise exception 'Unexpected definition: solar_private.cash_movement_detail(text)';end if;
 if md5(pg_get_functiondef('solar_private.profit_detail(text,uuid)'::regprocedure)) <> '8759368366bff324801f4805f787bbd4' then raise exception 'Unexpected definition: solar_private.profit_detail(text,uuid)';end if;
 if md5(pg_get_functiondef('solar_private.profit_balance(jsonb)'::regprocedure)) <> '18584c633c4b58cb8a3b339949c67f80' then raise exception 'Unexpected definition: solar_private.profit_balance(jsonb)';end if;
 if md5(pg_get_functiondef('solar_private.profit_workspace(text,uuid,jsonb)'::regprocedure)) <> 'f4ff3c11a58255ee1f89e02b450585bc' then raise exception 'Unexpected definition: solar_private.profit_workspace(text,uuid,jsonb)';end if;
 if md5(pg_get_functiondef('solar_private.fx(text,uuid,jsonb)'::regprocedure)) <> 'b6ad31f2b507213fd58d1d16d8b9ef06' then raise exception 'Unexpected definition: solar_private.fx(text,uuid,jsonb)';end if;
 if md5(pg_get_functiondef('solar_private.can_access_invoice(uuid,boolean)'::regprocedure)) <> '0d4e667e3ab31b5e31277bcc4cf0b2ec' then raise exception 'Unexpected definition: solar_private.can_access_invoice(uuid,boolean)';end if;
end $guard$;

-- Only returned read models are redacted. Accounting sources, snapshots and tokens stay unchanged.
create or replace function solar_private.invoice_read_allowed(invoice_id bigint)
returns boolean language plpgsql stable security definer set search_path='' as $function$
declare creator uuid;
begin
 if solar_private.can_access_invoice(null,false) then return true;end if;
 select t.created_by into creator from public.transactions t where t.id=invoice_read_allowed.invoice_id;
 if not found then select nullif(d.invoice->>'created_by','')::uuid into creator from solar_private.deleted_sales d where d.invoice_id=invoice_read_allowed.invoice_id;end if;
 return coalesce(solar_private.can_access_invoice(creator,false),false);
end $function$;
revoke all on function solar_private.invoice_read_allowed(bigint) from public,anon,authenticated;

create or replace function solar_private.cash_read_restricted(movement_id text)
returns boolean language plpgsql stable security definer set search_path='' as $function$
declare tid bigint; kind text; archive jsonb; e public.solar_cash_entries;
begin
 if solar_private.can_access_invoice(null,false) then return false;end if;
 if movement_id ~ '^tx:-?[0-9]+$' then
  tid:=substr(movement_id,4)::bigint;
  select t.kind into kind from public.transactions t where t.id=tid;
  -- Standalone deposits/expenses and authorized handovers remain the owner's own cash records.
  return coalesce(kind in('sale','system','purchase','customer_payment','system_payment','supplier_payment'),false) and not solar_private.invoice_read_allowed(tid);
 elsif movement_id ~ '^entry:[a-f0-9-]{36}$' then
  select * into e from public.solar_cash_entries where id=substr(movement_id,7)::uuid;
  tid:=coalesce(e.job_id,e.deleted_job_id);
  return tid is not null and not solar_private.invoice_read_allowed(tid);
 elsif movement_id ~ '^fx:-?[0-9]+$' then
  archive:=solar_private.purchase_archive_entry('wallet',substr(movement_id,4)::bigint);
  return archive is not null and not solar_private.invoice_read_allowed((archive->>'id')::bigint);
 end if;
 return false;
end $function$;
revoke all on function solar_private.cash_read_restricted(text) from public,anon,authenticated;

create or replace function solar_private.cash_read_projection(row_data jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare safe jsonb;
begin
 if row_data is null or not solar_private.cash_read_restricted(row_data->>'id') then return row_data;end if;
 select coalesce(jsonb_object_agg(k,v),'{}'::jsonb) into safe from jsonb_each(row_data) as x(k,v)
 where k=any(array['owner_id','ownerId','ownerName','currency','delta','book_delta','kind','rate','source_currency','sourceCurrency','created_at','date','balance','amount','before','after']);
 return safe ||
  jsonb_build_object('id','restricted:'||md5(auth.uid()::text||':'||(row_data->>'id')),'receiptRestricted',true,
   'receipt_no',null,'receiptNo',null,'party','','note','حركة مالية مرتبطة بوصل محجوب',
   'source_amount',null,'sourceAmount',null,'actor_name',null,'actorName',null,'actorPhone',null,
   'warehouse_name',null,'payment_mode',null,'current_expenses',null,'current_paid',null,'job_receipt',null,
   'document',null,'items','[]'::jsonb,'edit',jsonb_build_object('canEdit',false),'deletion',jsonb_build_object('canRequest',false));
end $function$;
revoke all on function solar_private.cash_read_projection(jsonb) from public,anon,authenticated;

create or replace function solar_private.profit_read_projection(value jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare result jsonb:=value; name text; source_key text;
begin
 if value is null or solar_private.can_access_invoice(null,false) then return value;end if;
 if jsonb_typeof(value)='array' then
  select coalesce(jsonb_agg(solar_private.profit_read_projection(x.value) order by x.ordinality),'[]'::jsonb) into result from jsonb_array_elements(value) with ordinality x;
 elsif jsonb_typeof(value)='object' then
  -- Only known read-model collections are traversed; monetary totals and opaque concurrency tokens are copied exactly.
  foreach name in array array['rows','snapshot','requests','movement'] loop
   if value ? name then result:=jsonb_set(result,array[name],solar_private.profit_read_projection(value->name));end if;
  end loop;
  source_key:=value->>'key';
  if source_key ~ '^tx:-?[0-9]+$' and value->>'kind' in('sale','system') and not solar_private.invoice_read_allowed(substr(source_key,4)::bigint) then
   select coalesce(jsonb_object_agg(k,v),'{}'::jsonb) into result from jsonb_each(value) as x(k,v)
   where k=any(array['date','kind','value','settled','available','deleted','ownerId']);
   result:=result||jsonb_build_object('key','restricted:'||md5(auth.uid()::text||':'||source_key),
    'receiptNo',null,'label','ربح محوّل إلى حسابك','receiptRestricted',true);
  end if;
 end if;
 return result;
end $function$;
revoke all on function solar_private.profit_read_projection(jsonb) from public,anon,authenticated;

create or replace function solar_private.supplier_entry_read_projection(row_data jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare tid bigint; archived jsonb; safe jsonb;
begin
 tid:=coalesce(nullif(row_data->>'transaction_id','')::bigint,nullif(row_data#>>'{archivedPurchase,id}','')::bigint);
 if tid is null or solar_private.invoice_read_allowed(tid) then return row_data;end if;
 archived:=row_data->'archivedPurchase';
 if jsonb_typeof(archived)='object' then archived:=jsonb_build_object('originalKind',archived->'originalKind','entryRole',archived->'entryRole','cancelledAt',archived->'cancelledAt','receiptRestricted',true);end if;
 select coalesce(jsonb_object_agg(k,v),'{}'::jsonb) into safe from jsonb_each(row_data) as x(k,v)
 where k=any(array['id','supplier_id','owner_id','currency','revision','delta','book_delta','gain','rate','created_at','entry_type','finance_request_id']);
 return safe||jsonb_build_object(
  'receiptRestricted',true,'transaction_id',null,'correction_for',null,'note','حركة مالية مرتبطة بوصل محجوب',
  'transaction',null,'items','[]'::jsonb,'archivedPurchase',archived);
end $function$;
revoke all on function solar_private.supplier_entry_read_projection(jsonb) from public,anon,authenticated;

create or replace function solar_private.fx_entry_read_projection(row_data jsonb,entry_source text)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare tid bigint; kind text; archive jsonb;
begin
 if solar_private.can_access_invoice(null,false) then return row_data;end if;
 tid:=nullif(row_data->>'transaction_id','')::bigint;
 if tid is not null then
  select t.kind into kind from public.transactions t where t.id=tid;
  if kind not in('sale','system','purchase','customer_payment','system_payment','supplier_payment') then return row_data;end if;
 else
  archive:=solar_private.purchase_archive_entry(entry_source,(row_data->>'id')::bigint);
  tid:=(archive->>'id')::bigint;
 end if;
 if tid is null or solar_private.invoice_read_allowed(tid) then return row_data;end if;
 return solar_private.supplier_entry_read_projection(row_data||case when archive is not null then jsonb_build_object('archivedPurchase',archive)else '{}'::jsonb end);
end $function$;
revoke all on function solar_private.fx_entry_read_projection(jsonb,text) from public,anon,authenticated;


do $patch$
declare definition text;
begin
 select pg_get_functiondef('solar_private.cash_workspace(jsonb)'::regprocedure) into definition;
 if strpos(definition,$before$lower(m.party||' '||m.note||' '||coalesce(m.receipt_no::text,''))$before$)=0 then raise exception 'Missing guarded read projection replacement';end if;
 definition:=replace(definition,$before$lower(m.party||' '||m.note||' '||coalesce(m.receipt_no::text,''))$before$,$after$lower(case when solar_private.cash_read_restricted(m.id) then 'حركة مالية مرتبطة بوصل محجوب' else m.party||' '||m.note||' '||coalesce(m.receipt_no::text,'') end)$after$);
 if strpos(definition,$before$jsonb_agg(to_jsonb(x)||jsonb_build_object$before$)=0 then raise exception 'Missing guarded read projection replacement';end if;
 definition:=replace(definition,$before$jsonb_agg(to_jsonb(x)||jsonb_build_object$before$,$after$jsonb_agg(solar_private.cash_read_projection(to_jsonb(x))||jsonb_build_object$after$);
 execute definition;
 select pg_get_functiondef('solar_private.cash_statement(uuid,date,date,text)'::regprocedure) into definition;
 if strpos(definition,$before$jsonb_agg(to_jsonb(r) order by r.created_at,r.id)$before$)=0 then raise exception 'Missing guarded read projection replacement';end if;
 definition:=replace(definition,$before$jsonb_agg(to_jsonb(r) order by r.created_at,r.id)$before$,$after$jsonb_agg(solar_private.cash_read_projection(to_jsonb(r)) order by r.created_at,r.id)$after$);
 execute definition;
 select pg_get_functiondef('solar_private.cash_movement_detail(text)'::regprocedure) into definition;
 if strpos(definition,$before$return result||jsonb_build_object('edit',solar_private.cash_record_context(movement_id,false),'deletion',solar_private.cash_movement_delete_context(movement_id));$before$)=0 then raise exception 'Missing guarded read projection replacement';end if;
 definition:=replace(definition,$before$return result||jsonb_build_object('edit',solar_private.cash_record_context(movement_id,false),'deletion',solar_private.cash_movement_delete_context(movement_id));$before$,$after$return solar_private.cash_read_projection(result||jsonb_build_object('edit',solar_private.cash_record_context(movement_id,false),'deletion',solar_private.cash_movement_delete_context(movement_id)));$after$);
 execute definition;
 select pg_get_functiondef('solar_private.profit_detail(text,uuid)'::regprocedure) into definition;
 if strpos(definition,$before$if t.id is not null then
   if t.kind$before$)=0 then raise exception 'Missing guarded read projection replacement';end if;
 definition:=replace(definition,$before$if t.id is not null then
   if t.kind$before$,$after$if t.id is not null then
   if t.kind in('sale','system') and not solar_private.invoice_read_allowed(t.id) then
    return jsonb_build_object('movement',solar_private.profit_read_projection(movement),'invoice',null,'transferred',true,'breakdown',null,'receiptRestricted',true);
   end if;
   if t.kind$after$);
 if strpos(definition,$before$'movement',movement,'invoice',invoice,'breakdown',breakdown$before$)=0 then raise exception 'Missing guarded read projection replacement';end if;
 definition:=replace(definition,$before$'movement',movement,'invoice',invoice,'breakdown',breakdown$before$,$after$'movement',solar_private.profit_read_projection(movement),'invoice',invoice,'breakdown',breakdown$after$);
 execute definition;
 select pg_get_functiondef('solar_private.profit_balance(jsonb)'::regprocedure) into definition;
 if strpos(definition,$before$return result;$before$)=0 then raise exception 'Missing guarded read projection replacement';end if;
 definition:=replace(definition,$before$return result;$before$,$after$return solar_private.profit_read_projection(result);$after$);
 execute definition;
 select pg_get_functiondef('solar_private.profit_workspace(text,uuid,jsonb)'::regprocedure) into definition;
 if strpos(definition,$before$then return prior.response;$before$)=0 then raise exception 'Missing guarded read projection replacement';end if;
 definition:=replace(definition,$before$then return prior.response;$before$,$after$then return solar_private.profit_read_projection(prior.response);$after$);
 if strpos(definition,$before$return jsonb_build_object('retainedProfit'$before$)=0 then raise exception 'Missing guarded read projection replacement';end if;
 definition:=replace(definition,$before$return jsonb_build_object('retainedProfit'$before$,$after$return solar_private.profit_read_projection(jsonb_build_object('retainedProfit'$after$);
 if strpos(definition,$before$else '[]'::jsonb end);
 elsif action='request'$before$)=0 then raise exception 'Missing guarded read projection replacement';end if;
 definition:=replace(definition,$before$else '[]'::jsonb end);
 elsif action='request'$before$,$after$else '[]'::jsonb end));
 elsif action='request'$after$);
 if strpos(definition,$before$return result;$before$)=0 then raise exception 'Missing guarded read projection replacement';end if;
 definition:=replace(definition,$before$return result;$before$,$after$return solar_private.profit_read_projection(result);$after$);
 execute definition;
 select pg_get_functiondef('solar_private.fx(text,uuid,jsonb)'::regprocedure) into definition;
 if strpos(definition,$before$jsonb_agg(to_jsonb(e)||case when ap.summary$before$)=0 then raise exception 'Missing guarded read projection replacement';end if;
 definition:=replace(definition,$before$jsonb_agg(to_jsonb(e)||case when ap.summary$before$,$after$jsonb_agg(solar_private.supplier_entry_read_projection(to_jsonb(e)||case when ap.summary$after$);
 if strpos(definition,$before$where i.transaction_id=x.id)) order by e.id)$before$)=0 then raise exception 'Missing guarded read projection replacement';end if;
 definition:=replace(definition,$before$where i.transaction_id=x.id)) order by e.id)$before$,$after$where i.transaction_id=x.id))) order by e.id)$after$);
 if strpos(definition,$before$jsonb_agg(to_jsonb(e)),'[]') from solar_private.wallet_fx_entries$before$)=0 then raise exception 'Missing guarded read projection replacement';end if;
 definition:=replace(definition,$before$jsonb_agg(to_jsonb(e)),'[]') from solar_private.wallet_fx_entries$before$,$after$jsonb_agg(solar_private.fx_entry_read_projection(to_jsonb(e),'wallet')),'[]') from solar_private.wallet_fx_entries$after$);
 if strpos(definition,$before$jsonb_agg(to_jsonb(e)),'[]') from solar_private.supplier_fx_entries$before$)=0 then raise exception 'Missing guarded read projection replacement';end if;
 definition:=replace(definition,$before$jsonb_agg(to_jsonb(e)),'[]') from solar_private.supplier_fx_entries$before$,$after$jsonb_agg(solar_private.fx_entry_read_projection(to_jsonb(e),'supplier')),'[]') from solar_private.supplier_fx_entries$after$);
 execute definition;
end $patch$;
notify pgrst,'reload schema';
