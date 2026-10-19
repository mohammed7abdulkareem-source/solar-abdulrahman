-- Printed account context is captured in the same cash/stock transaction.
-- Warehouse QR uses a separate, unguessable token and a strict non-financial copy.
alter table public.transactions add column invoice_account jsonb;
alter table public.transactions add column warehouse_qr_token uuid unique;

create function solar_private.invoice_account_context(t public.transactions) returns jsonb
language plpgsql stable set search_path='' as $$
declare cid bigint;previous numeric:=0;last_payment jsonb;available boolean;begin
 if t.kind not in('sale','system') then return null;end if;
 if t.party_id is not null then select c.id into cid from public.customers c where c.id=t.party_id;
 elsif coalesce(t.party_name,'')<>'' then
  select min(c.id) into cid from public.customers c where solar_private.customer_name_key(c.name)=solar_private.customer_name_key(t.party_name) having count(*)=1;
 end if;
 available:=cid is not null or (t.party_id is null and coalesce(t.party_name,'')='');
 if cid is not null then
  select coalesce(sum(case when m.kind in('customer_payment','system_payment') then -m.total when m.kind='sale' and m.cash then 0 else m.total end),0)
  into previous from public.transactions m join solar_private.customer_movement_links() l on l.transaction_id=m.id
  where l.customer_id=cid and m.id<>t.id and (m.created_at,m.id)<(t.created_at,t.id);
  select jsonb_build_object('id',m.id,'receiptNo',m.receipt_no,'date',m.created_at,'amount',m.total) into last_payment
  from public.transactions m join solar_private.customer_movement_links() l on l.transaction_id=m.id
  where l.customer_id=cid and m.id<>t.id and (m.created_at,m.id)<(t.created_at,t.id)
  and m.kind in('customer_payment','system_payment') and m.total>0 and m.cash
  and coalesce(m.payment_mode,'') not in('opening_balance','account_reconciliation')
  order by m.created_at desc,m.id desc limit 1;
 end if;
 return jsonb_build_object('version',1,'customerId',cid,'available',available,'asOf',t.created_at,
  'previousBalance',case when available then previous end,'lastPayment',last_payment,
  'invoiceTotal',t.total,'paidNow',case when t.kind='sale' and t.cash then t.total else 0 end,
  'balanceAfter',case when available then previous+case when t.kind='sale' and t.cash then 0 else t.total end end,'basis','issued');
end $$;
revoke all on function solar_private.invoice_account_context(public.transactions) from public,anon,authenticated;

create function solar_private.invoice_document_guard() returns trigger
language plpgsql set search_path='' as $$
begin
 if current_user in('anon','authenticated') and (
  (tg_op='INSERT' and (new.invoice_account is not null or new.warehouse_qr_token is not null)) or
  (tg_op='UPDATE' and (new.invoice_account,new.warehouse_qr_token) is distinct from (old.invoice_account,old.warehouse_qr_token)))
 then raise exception 'استخدم حفظ الفاتورة المعتمد' using errcode='42501';end if;
 if new.kind in('sale','system') then
  if tg_op='INSERT' then
   new.warehouse_qr_token:=gen_random_uuid();new.invoice_account:=solar_private.invoice_account_context(new);
  elsif (new.party_id,new.party_name,new.kind) is distinct from (old.party_id,old.party_name,old.kind) then
   new.invoice_account:=solar_private.invoice_account_context(new);
  elsif (new.total,new.cash) is distinct from (old.total,old.cash) and old.invoice_account is not null then
   new.invoice_account:=old.invoice_account||jsonb_build_object('invoiceTotal',new.total,
    'paidNow',case when new.kind='sale' and new.cash then new.total else 0 end,
    'balanceAfter',case when (old.invoice_account->>'available')::boolean then (old.invoice_account->>'previousBalance')::numeric+case when new.kind='sale' and new.cash then 0 else new.total end end);
  end if;
 end if;
 return new;
end $$;
create trigger solar_zz_invoice_document before insert or update on public.transactions for each row execute function solar_private.invoice_document_guard();
revoke all on function solar_private.invoice_document_guard() from public,anon,authenticated;

-- Existing invoices can only be reconstructed from the retained ledger.
update public.transactions t set invoice_account=solar_private.invoice_account_context(t)||'{"basis":"retained-ledger"}',warehouse_qr_token=gen_random_uuid() where kind in('sale','system');

do $$declare d text;needle text;begin
 select pg_get_functiondef('solar_private.invoice_save_v333(uuid,jsonb)'::regprocedure) into d;
 needle:='''profit'',invoice.profit)';
 if strpos(d,needle)=0 then raise exception 'Missing invoice response anchor';end if;
 d:=replace(d,needle,'''profit'',invoice.profit,''invoiceAccount'',invoice.invoice_account,''warehouseQrToken'',invoice.warehouse_qr_token)');
 execute d;
 select pg_get_functiondef('solar_private.warehouse_orders(text,text,integer)'::regprocedure) into d;
 needle:='''preparedAt'',t.warehouse_prepared_at';
 if strpos(d,needle)=0 then raise exception 'Missing warehouse response anchor';end if;
 execute replace(d,needle,'''warranty'',t.warranty,''warehouseQrToken'',t.warehouse_qr_token,''preparedAt'',t.warehouse_prepared_at');
end $$;

-- Same verification URL, but warehouse tokens never return prices, totals,
-- account snapshots, or the token that opens the customer copy.
create or replace function solar_private.warranty_verify(certificate_token uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare c solar_private.warranty_certificates;t public.transactions;doc jsonb;enabled boolean;items jsonb;voided boolean:=false;updated timestamptz;begin
 select * into c from solar_private.warranty_certificates where token=certificate_token;
 if c.token is not null then doc:=c.document;voided:=c.invoice_id is null;updated:=c.updated_at;
 else
  select * into t from public.transactions where warehouse_qr_token=certificate_token and kind in('sale','system');
  if t.id is null then return null;end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',i.product_id,'name',i.product_name,'brand',i.brand_name,'category',i.category,'qty',i.qty,
   'term',coalesce((select x-'id' from jsonb_array_elements(coalesce(t.warranty->'items','[]'))x where (x->>'id')::bigint=i.product_id),'{"duration":0,"unit":"months"}'::jsonb)) order by i.id),'[]') into items from public.transaction_items i where i.transaction_id=t.id;
  doc:=jsonb_build_object('copy','warehouse','token',certificate_token,'invoiceId',t.id,'receiptNo',t.receipt_no,'kind',t.kind,'customer',coalesce(t.party_name,'زبون نقدي'),
   'date',(t.created_at at time zone 'Asia/Baghdad')::date,'items',items,'warranty',t.warranty)||case when t.kind='system' then jsonb_build_object('phone',t.customer_phone,'address',t.customer_address,'installer',(select coalesce(display_name,username) from public.profiles where id=t.installer_id),'installDate',t.install_date,'installTime',t.install_time) else '{}'::jsonb end;
 end if;
 enabled:=not voided and coalesce((doc->'warranty'->>'enabled')::boolean,false);
 select coalesce(jsonb_agg(x||jsonb_build_object('status',solar_private.warranty_status((doc->>'date')::date,case when enabled then x->'term' else '{"duration":0,"unit":"months"}'::jsonb end))),'[]') into items from jsonb_array_elements(doc->'items')x;
 return doc||jsonb_build_object('voided',voided,'enabled',enabled,'checkedDate',(now() at time zone 'Asia/Baghdad')::date,'items',items,'updatedAt',updated,'maintenanceStatus',solar_private.warranty_status((doc->>'date')::date,case when enabled then doc->'warranty'->'maintenance' else '{"duration":0,"unit":"months"}'::jsonb end));
end $$;
notify pgrst,'reload schema';
