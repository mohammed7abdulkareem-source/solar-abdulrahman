-- Supplier cash payments and non-cash account charges require an active office
-- administrator. Each entry point checks the current actor before replaying a
-- stored response. Purchases and separately granted read-only statements retain
-- their own access rules.
do $migration$
declare
 change record;
 definition text;
begin
 for change in select * from (values
  ('solar_private.fx(text,uuid,jsonb)',
   $old$(action='payment' and not(p.is_admin or solar_private.any_feature(p.permissions,'supplierPayment')))$old$,
   $new$(action='payment' and p.is_admin is not true)$new$),
  ('solar_private.supplier_payment_save(uuid,bigint,bigint,numeric,text,text)',
   $old$p.user_type='installer' or not(p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true') then raise exception 'Not permitted'$old$,
   $new$p.user_type in ('installer','warehouse') or p.is_admin is not true then raise exception 'تسديد المورد متاح للأدمن فقط'$new$),
  ('solar_private.supplier_movement_save(uuid,bigint,bigint,numeric,text,text,text)',
   $old$not(p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true')$old$,
   $new$p.is_admin is not true$new$),
  ('solar_private.supplier_payment_manage(text,uuid,jsonb)',
   $old$not(actor.is_admin or coalesce(actor.permissions->>'supplierPayment','false')='true')$old$,
   $new$actor.is_admin is not true$new$),
  ('solar_private.receipt_feature(jsonb,text,boolean)',
   $old$when 'supplier_payment' then solar_private.any_feature(grants,'supplierPayment') or (not writing and solar_private.any_feature(grants,'supplierStatement'))$old$,
   $new$when 'supplier_payment' then not writing and solar_private.any_feature(grants,'supplierStatement')$new$),
  ('solar_private.delete_kind_feature(jsonb,text)',
   $old$when kind='supplier_payment' then solar_private.any_feature(grants,'supplierPayment')$old$,
   $new$when kind='supplier_payment' then false$new$),
  ('solar_private.supplier_payment_get(bigint)',
   $old$p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true' or coalesce(p.permissions->>'supplierStatement','false')='true'$old$,
   $new$p.is_admin or coalesce(p.permissions->>'supplierStatement','false')='true'$new$),
  ('solar_private.payment_history(text,jsonb)',
   $old$p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true' or coalesce(p.permissions->>'supplierStatement','false')='true'$old$,
   $new$p.is_admin or coalesce(p.permissions->>'supplierStatement','false')='true'$new$),
  ('solar_private.enforce_own_user_scope()',
   $old$begin
 if not new.is_admin$old$,
   $new$begin
 if (new.is_admin is not true or new.user_type in ('installer','warehouse')) and new.permissions ? 'supplierPayment' then
  new.permissions:=new.permissions-'supplierPayment';
 end if;
 if not new.is_admin$new$)
 ) as edits(signature,old_text,new_text)
 loop
  definition:=pg_get_functiondef(change.signature::regprocedure);
  if strpos(definition,change.old_text)=0 then
   raise exception 'Review supplier administration migration anchor in %',change.signature;
  end if;
  execute replace(definition,change.old_text,change.new_text);
 end loop;
end
$migration$;

-- Older clients can still submit their saved permission maps. Remove the
-- retired grant at the profile write boundary as well as from current staff.
update public.profiles
set permissions=permissions-'supplierPayment',updated_at=clock_timestamp()
where (is_admin is not true or user_type in ('installer','warehouse'))
 and permissions ? 'supplierPayment';

-- Direct client writes have always needed a receipt RPC. Enforce the actor
-- rule also for ledger changes made through SECURITY DEFINER paths.
create or replace function solar_private.guard_supplier_payment()
returns trigger language plpgsql set search_path='' as $$
begin
 if (tg_op<>'INSERT' and old.kind='supplier_payment') or (tg_op<>'DELETE' and new.kind='supplier_payment') then
  if current_user in ('anon','authenticated') then
   raise exception 'استخدم إجراء تسديد المورد' using errcode='42501';
  end if;
  if auth.uid() is not null and solar_private.role_name() is distinct from 'admin' then
   raise exception 'تعديل حركات حساب المورد متاح للأدمن فقط' using errcode='42501';
  end if;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;

-- Renaming, merging or deleting an existing supplier affects statement
-- identity, including older entries matched by name. Staff with directory
-- access may still add a supplier or correct its contact phone.
create function solar_private.guard_supplier_account_identity()
returns trigger language plpgsql set search_path='' as $$
begin
 if (current_user in ('anon','authenticated') or auth.uid() is not null)
  and solar_private.role_name() is distinct from 'admin'
  and (tg_op='DELETE' or (new.id,new.name,new.active,new.account_currency,new.currency_revision)
     is distinct from (old.id,old.name,old.active,old.account_currency,old.currency_revision)) then
  raise exception 'تغيير هوية المورد أو عملة حسابه أو حذفه متاح للأدمن فقط' using errcode='42501';
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
revoke all on function solar_private.guard_supplier_account_identity() from public,anon,authenticated;
create trigger solar_supplier_account_identity before update or delete on public.suppliers
 for each row execute function solar_private.guard_supplier_account_identity();

-- Truncation does not run per-row triggers or row-level policies.
revoke truncate on public.transactions, public.transaction_items, public.suppliers from public,anon,authenticated;
-- A purchase grant permits choosing a supplier on a new invoice. The supplier
-- ledger and contact directory retain their separate read permissions.
alter policy solar_feature_read on public.suppliers using (
 (select solar_private.role_name())='admin' or
 (select solar_private.any_feature(solar_private.office_features(),'suppliers','supplierStatement','supplierBalances'))
);

create function solar_private.purchase_suppliers()
returns table(id bigint, name text, account_currency text, currency_revision bigint)
language sql stable security definer set search_path='' as $$
 select s.id,s.name,s.account_currency,s.currency_revision
 from public.suppliers s
 where s.active and ((select solar_private.role_name())='admin' or
   (select solar_private.any_feature(solar_private.office_features(),'purchase')))
 order by s.id
$$;

create function public.solar_purchase_suppliers()
returns table(id bigint, name text, account_currency text, currency_revision bigint)
language sql stable security invoker set search_path='' as $$
 select * from solar_private.purchase_suppliers()
$$;
revoke all on function public.solar_purchase_suppliers(), solar_private.purchase_suppliers() from public,anon,authenticated;
grant execute on function public.solar_purchase_suppliers(), solar_private.purchase_suppliers() to authenticated;

do $read_permissions$
declare change record; definition text;
begin
 for change in select * from (values
  ('solar_private.fx(text,uuid,jsonb)',
   $old$solar_private.any_feature(p.permissions,'purchase','supplierPayment','supplierStatement','suppliers')$old$,
   $new$solar_private.any_feature(p.permissions,'supplierStatement')$new$),
  ('solar_private.fx(text,uuid,jsonb)',
   $old$not(p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true' or coalesce(p.permissions->>'supplierStatement','false')='true' or coalesce(p.permissions->>'purchase','false')='true')$old$,
   $new$not(p.is_admin or solar_private.any_feature(p.permissions,'supplierStatement') or (action='account' and solar_private.any_feature(p.permissions,'supplierBalances')))$new$),
  ('solar_private.supplier_account(bigint,bigint)',
   $old$not(p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true')$old$,
   $new$p.is_admin is not true$new$),
  -- Keep a cashier's balance and cash delta visible while masking the linked
  -- supplier document after a statement grant is removed, even for its author.
  ('solar_private.invoice_read_allowed(bigint)',
   $old$declare creator uuid;$old$,
   $new$declare creator uuid; receipt_kind text;$new$),
  ('solar_private.invoice_read_allowed(bigint)',
   $old$select t.created_by into creator from public.transactions t where t.id=invoice_read_allowed.invoice_id;
 if not found then select nullif(d.invoice->>'created_by','')::uuid into creator from solar_private.deleted_sales d where d.invoice_id=invoice_read_allowed.invoice_id;end if;$old$,
   $new$select t.created_by,t.kind into creator,receipt_kind from public.transactions t where t.id=invoice_read_allowed.invoice_id;
 if not found then select nullif(d.invoice->>'created_by','')::uuid,d.invoice->>'kind' into creator,receipt_kind from solar_private.deleted_sales d where d.invoice_id=invoice_read_allowed.invoice_id;end if;
 if receipt_kind='supplier_payment' and not solar_private.any_feature(solar_private.office_features(),'supplierStatement') then return false;end if;$new$),
  ('solar_private.cash_read_restricted(text)',
   $old$archive:=solar_private.purchase_archive_entry('wallet',substr(movement_id,4)::bigint);$old$,
   $new$if exists(select 1 from solar_private.wallet_fx_entries w where w.id=substr(movement_id,4)::bigint and w.entry_type='supplier_payment_refund')
     and not solar_private.any_feature(solar_private.office_features(),'supplierStatement') then return true;end if;
  archive:=solar_private.purchase_archive_entry('wallet',substr(movement_id,4)::bigint);$new$),
  ('solar_private.fx_entry_read_projection(jsonb,text)',
   $old$tid:=nullif(row_data->>'transaction_id','')::bigint;$old$,
   $new$if entry_source='wallet' and row_data->>'entry_type'='supplier_payment_refund'
     and not solar_private.any_feature(solar_private.office_features(),'supplierStatement') then
   return (row_data-'note'-'finance_request_id')||jsonb_build_object('receiptRestricted',true,'note','حركة مالية مرتبطة بوصل محجوب');
  end if;
  tid:=nullif(row_data->>'transaction_id','')::bigint;$new$)
 ) as edits(signature,old_text,new_text)
 loop
  definition:=pg_get_functiondef(change.signature::regprocedure);
  if strpos(definition,change.old_text)=0 then raise exception 'Review supplier read migration anchor in %',change.signature;end if;
  execute replace(definition,change.old_text,change.new_text);
 end loop;
end
$read_permissions$;

notify pgrst,'reload schema';
