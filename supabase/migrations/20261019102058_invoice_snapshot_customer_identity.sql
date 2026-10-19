-- Renaming a customer must not recalculate an issued account snapshot.
-- Only reassignment to a different resolved account rebuilds prior context.
create or replace function solar_private.invoice_document_guard() returns trigger
language plpgsql set search_path='' as $$
declare context jsonb;
begin
 if current_user in('anon','authenticated') and (
  (tg_op='INSERT' and (new.invoice_account is not null or new.warehouse_qr_token is not null)) or
  (tg_op='UPDATE' and (new.invoice_account,new.warehouse_qr_token) is distinct from (old.invoice_account,old.warehouse_qr_token)))
 then raise exception 'استخدم حفظ الفاتورة المعتمد' using errcode='42501';end if;
 if new.kind in('sale','system') then
  if tg_op='INSERT' then
   new.warehouse_qr_token:=gen_random_uuid();new.invoice_account:=solar_private.invoice_account_context(new);
  elsif (new.party_id,new.party_name,new.kind) is distinct from (old.party_id,old.party_name,old.kind) then
   context:=solar_private.invoice_account_context(new);
   if context->'customerId' is not distinct from old.invoice_account->'customerId' and context->'available' is not distinct from old.invoice_account->'available' then
    new.invoice_account:=old.invoice_account;
   else new.invoice_account:=context;end if;
  end if;
  if tg_op='UPDATE' and (new.total,new.cash) is distinct from (old.total,old.cash) and new.invoice_account is not null then
   new.invoice_account:=new.invoice_account||jsonb_build_object('invoiceTotal',new.total,
    'paidNow',case when new.kind='sale' and new.cash then new.total else 0 end,
    'balanceAfter',case when (new.invoice_account->>'available')::boolean then (new.invoice_account->>'previousBalance')::numeric+case when new.kind='sale' and new.cash then 0 else new.total end end);
  end if;
 end if;
 return new;
end $$;
revoke all on function solar_private.invoice_document_guard() from public,anon,authenticated;
