-- A transfer can delegate an individual sale without transferring its author or
-- cashier. Only customer-account reads gain this additional authorization.
create function solar_private.assigned_customer_receipt(account_id bigint, receipt_id bigint)
returns boolean language sql stable security definer set search_path='' as $$
 select exists (
  select 1 from solar_private.customer_receipt_responsibility r
  join public.customers c on c.id=r.customer_id and c.owner_id=r.owner_id
  join public.profiles p on p.id=r.owner_id and p.active and p.user_type not in ('warehouse','installer')
  where r.transaction_id=receipt_id and r.customer_id=account_id and r.owner_id=auth.uid()
 )
$$;
revoke all on function solar_private.assigned_customer_receipt(bigint,bigint) from public,anon,authenticated;

create or replace function solar_private.customer_ledger_read_projection(rows jsonb,customer_id bigint)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(case
  when solar_private.invoice_read_allowed((r.value->>'id')::bigint)
    or solar_private.assigned_customer_receipt(customer_id,(r.value->>'id')::bigint) then
   case when r.value->>'systemInvoiceId' is not null
      and not solar_private.invoice_read_allowed((r.value->>'systemInvoiceId')::bigint)
      and not solar_private.assigned_customer_receipt(customer_id,(r.value->>'systemInvoiceId')::bigint)
    then r.value-'systemInvoiceId'-'systemReceiptNo' else r.value end
  else jsonb_build_object('id','restricted:'||md5(customer_id::text||':'||coalesce(auth.uid()::text,'')||':'||(r.value->>'id')),
   'date',r.value->'date','effect',r.value->'effect','kind',r.value->'kind','mode',r.value->'mode','receiptRestricted',true)
  end order by r.ordinality),'[]'::jsonb)
 from jsonb_array_elements(rows) with ordinality r(value,ordinality)
$$;

do $$
declare definition text; old_text text;
begin
 definition:=pg_get_functiondef('solar_private.customer_documents(bigint,bigint,date,date,text,text)'::regprocedure);
 old_text:='filtered as(select * from ranked where(p.is_admin or created_by=p.id)';
 if strpos(definition,old_text)=0 then raise exception 'Review readable customer document selection'; end if;
 definition:=replace(definition,old_text,'filtered as(select * from ranked where(p.is_admin or created_by=p.id or solar_private.assigned_customer_receipt(c.id,ranked.id))');
 old_text:='and solar_private.invoice_read_allowed((l.x->>''systemInvoiceId'')::bigint) then';
 if strpos(definition,old_text)=0 then raise exception 'Review statement document allocation label'; end if;
 definition:=replace(definition,old_text,'and (solar_private.invoice_read_allowed((l.x->>''systemInvoiceId'')::bigint) or solar_private.assigned_customer_receipt(c.id,(l.x->>''systemInvoiceId'')::bigint)) then');
 -- The authorized document is also the source for solar_statement_sale_for_edit.
 -- Preserve the original creator and tell their editor who currently manages expenses.
 old_text:=$original$rows:=rows||jsonb_build_array(jsonb_build_object('type','invoice','movement',movement,'invoice',solar_private.customer_invoice_document(t)));$original$;
 if strpos(definition,old_text)=0 then raise exception 'Review original invoice document'; end if;
 definition:=replace(definition,old_text,$document$
   invoice:=solar_private.customer_invoice_document(t)||jsonb_build_object('operationalOwnerId',solar_private.receipt_responsible(t.id,t.created_by));
   if not p.is_admin and t.created_by is distinct from p.id then
    -- The issued account snapshot can identify a payment that was not delegated.
    invoice:=(invoice-'invoice_account')||jsonb_build_object('assignedReceipt',true,
     'expenses',case when t.kind='sale' and coalesce(t.expenses_on_customer,true) then t.expenses else 0 end);
   end if;
   rows:=rows||jsonb_build_array(jsonb_build_object('type','invoice','movement',movement,'invoice',invoice));$document$);
 old_text:='where i.id=t.system_invoice_id and i.kind=''system'' and(p.is_admin or i.created_by=p.id);';
 if strpos(definition,old_text)=0 then raise exception 'Review statement linked original system'; end if;
 execute replace(definition,old_text,'where i.id=t.system_invoice_id and i.kind=''system'' and(p.is_admin or i.created_by=p.id or solar_private.assigned_customer_receipt(c.id,i.id));');

 definition:=pg_get_functiondef('solar_private.customer_invoice_report_batch(bigint,bigint[],text)'::regprocedure);
 old_text:='where t.id=any(invoice_ids) and t.kind in (''sale'',''system'') and (p.is_admin or t.created_by=p.id);';
 if strpos(definition,old_text)=0 then raise exception 'Review customer batch detail permissions'; end if;
 execute replace(definition,old_text,'where t.id=any(invoice_ids) and t.kind in (''sale'',''system'') and (p.is_admin or t.created_by=p.id or solar_private.assigned_customer_receipt(c.id,t.id));');

 definition:=pg_get_functiondef('solar_private.customer_account_actions(bigint,boolean)'::regprocedure);
 old_text:='else r.value || jsonb_build_object(';
 if strpos(definition,old_text)=0 then raise exception 'Review customer account receipt actions'; end if;
 execute replace(definition,old_text,$actions$else r.value || case when t.created_by is distinct from p.id and solar_private.assigned_customer_receipt(c.id,t.id) then
    jsonb_build_object('assignedReceipt',true,'canFollowInstallation',t.kind='system' and
     (p.is_admin or solar_private.any_feature(p.permissions,'system','installations')))
   else '{}'::jsonb end || jsonb_build_object($actions$);
end $$;
notify pgrst,'reload schema';
