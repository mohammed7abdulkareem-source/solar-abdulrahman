-- Track this account by supplier ID and retain its historical names for
-- pre-ID receipts, even after an administrator renames or deletes the account.
alter table public.suppliers add column admin_only boolean not null default false;
create table solar_private.protected_supplier_aliases(
 supplier_id bigint not null,
 name_key text not null,
 primary key(supplier_id,name_key)
);
revoke all on table solar_private.protected_supplier_aliases from public,anon,authenticated;

update public.suppliers set admin_only=true where solar_private.customer_name_key(name)='abdulrahman';
insert into solar_private.protected_supplier_aliases(supplier_id,name_key)
 select id,solar_private.customer_name_key(name) from public.suppliers where admin_only;

create function solar_private.supplier_admin_only(supplier_id bigint, supplier_name text default null)
returns boolean language sql stable security definer set search_path='' as $$
 select solar_private.customer_name_key($2)='abdulrahman' or exists(
  select 1 from solar_private.protected_supplier_aliases a
  where a.supplier_id=$1 or a.name_key=solar_private.customer_name_key($2))
$$;
revoke all on function solar_private.supplier_admin_only(bigint,text) from public,anon,authenticated;
grant execute on function solar_private.supplier_admin_only(bigint,text) to authenticated;

create or replace function solar_private.guard_supplier_account_identity()
returns trigger language plpgsql security definer set search_path='' as $$
declare old_protected boolean:=false; new_protected boolean:=false;
begin
 if tg_op='INSERT' or (tg_op='UPDATE' and new.name is distinct from old.name) then
  -- Directory RPCs and direct master edits serialize assignment of a name.
  perform pg_advisory_xact_lock(hashtextextended(solar_private.customer_name_key(new.name),4134));
 end if;
 if tg_op<>'INSERT' then
  old_protected:=old.admin_only or solar_private.supplier_admin_only(old.id,old.name);
 end if;
 if tg_op<>'DELETE' then
  new_protected:=old_protected or solar_private.supplier_admin_only(new.id,new.name);
 end if;
 if (old_protected or new_protected or (tg_op<>'DELETE' and new.admin_only))
  and (auth.uid() is not null or current_setting('role',true) in ('anon','authenticated'))
  and solar_private.role_name() is distinct from 'admin' then
  raise exception 'حساب هذا المورد متاح للأدمن فقط' using errcode='42501';
 end if;
 if tg_op='DELETE' then return old;end if;
 -- Only the named account and its remembered identities carry this marker.
 new.admin_only:=new_protected;
 if new_protected then
  if exists(select 1 from public.suppliers s where s.id<>new.id and (tg_op='INSERT' or s.id<>old.id)
    and (solar_private.customer_name_key(s.name)=solar_private.customer_name_key(new.name) or
      exists(select 1 from solar_private.protected_supplier_aliases a where a.supplier_id=s.id
        and a.name_key=solar_private.customer_name_key(new.name)))) then
   raise exception 'هذا المورد مسجل مسبقاً' using errcode='23505';
  end if;
  insert into solar_private.protected_supplier_aliases(supplier_id,name_key)
   values(new.id,solar_private.customer_name_key(new.name)) on conflict do nothing;
 end if;
 return new;
end $$;

drop trigger solar_supplier_account_identity on public.suppliers;
create trigger solar_supplier_account_identity before insert or update or delete on public.suppliers
 for each row execute function solar_private.guard_supplier_account_identity();

alter policy solar_feature_read on public.suppliers using (
 (select solar_private.role_name())='admin' or (not admin_only and
 (select solar_private.any_feature(solar_private.office_features(),'suppliers','supplierStatement','supplierBalances','supplierPayment')))
);

create or replace function solar_private.purchase_suppliers()
returns table(id bigint, name text, account_currency text, currency_revision bigint)
language sql stable security definer set search_path='' as $$
 select s.id,s.name,s.account_currency,s.currency_revision
 from public.suppliers s
 where s.active and ((select solar_private.role_name())='admin' or
  (not s.admin_only and (select solar_private.any_feature(solar_private.office_features(),'purchase'))))
 order by s.id
$$;

-- Check both the selected account and the original receipt before retrieving
-- previews, testing idempotency, or changing any supplier or cash records.
create function solar_private.require_supplier_access(supplier_id bigint, payment_id bigint, supplier_name text default null)
returns void language plpgsql stable security definer set search_path='' as $$
begin
 if solar_private.role_name()='admin' then return;end if;
 if solar_private.supplier_admin_only($1,$3) or
  ($2 is not null and (exists(select 1 from public.transactions t where t.id=$2 and t.kind='supplier_payment'
     and solar_private.supplier_admin_only(t.party_id,t.party_name)) or
   exists(select 1 from solar_private.supplier_fx_entries e where e.transaction_id=$2 and solar_private.supplier_admin_only(e.supplier_id)))) then
  raise exception 'حساب هذا المورد متاح للأدمن فقط' using errcode='42501';
 end if;
end $$;
revoke all on function solar_private.require_supplier_access(bigint,bigint,text) from public,anon,authenticated;

create or replace function solar_private.guard_supplier_payment()
returns trigger language plpgsql set search_path='' as $$
begin
 if (tg_op<>'INSERT' and old.kind='supplier_payment') or (tg_op<>'DELETE' and new.kind='supplier_payment') then
  if current_user in ('anon','authenticated') then
   raise exception 'استخدم إجراء تسديد المورد' using errcode='42501';
  end if;
  if auth.uid() is not null then
   if tg_op<>'INSERT' and old.kind='supplier_payment' then perform solar_private.require_supplier_access(old.party_id,old.id,old.party_name);end if;
   if tg_op<>'DELETE' and new.kind='supplier_payment' then perform solar_private.require_supplier_access(new.party_id,new.id,new.party_name);end if;
  end if;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;

create function solar_private.guard_protected_supplier_ledger()
returns trigger language plpgsql set search_path='' as $$
begin
 if (auth.uid() is not null or current_user in ('anon','authenticated')) and solar_private.role_name() is distinct from 'admin' then
  if (tg_op<>'INSERT' and solar_private.supplier_admin_only(old.supplier_id))
   or (tg_op<>'DELETE' and solar_private.supplier_admin_only(new.supplier_id)) then
   raise exception 'حساب هذا المورد متاح للأدمن فقط' using errcode='42501';
  end if;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
revoke all on function solar_private.guard_protected_supplier_ledger() from public,anon,authenticated;
create trigger solar_protected_supplier_ledger before insert or update or delete on solar_private.supplier_fx_entries
 for each row execute function solar_private.guard_protected_supplier_ledger();

-- Keep existing RPC signatures, original role and ownership checks, and the
-- accounting/ledger implementations shared by all current and older clients.
do $migration$
declare patch record; definition text;
begin
 for patch in select * from (values
  ('solar_private.enforce_own_user_scope()',
   $old$ if (new.is_admin is not true or new.user_type in ('installer','warehouse')) and new.permissions ? 'supplierPayment' then
  new.permissions:=new.permissions-'supplierPayment';
 end if;
$old$,''),
  ('solar_private.receipt_feature(jsonb,text,boolean)',
   $old$when 'supplier_payment' then not writing and solar_private.any_feature(grants,'supplierStatement')$old$,
   $new$when 'supplier_payment' then solar_private.any_feature(grants,'supplierPayment') or (not writing and solar_private.any_feature(grants,'supplierStatement'))$new$),
  ('solar_private.delete_kind_feature(jsonb,text)',
   $old$when kind='supplier_payment' then false$old$,
   $new$when kind='supplier_payment' then solar_private.any_feature(grants,'supplierPayment')$new$),
  ('solar_private.supplier_directory()',
   $old$)) a on true;$old$,
   $new$)) a on true where p.is_admin or not s.admin_only;$new$),
  ('solar_private.supplier_save(uuid,jsonb)',
   $old$perform pg_advisory_xact_lock(7311,1);$old$,
   $new$perform solar_private.require_supplier_access(nullif(payload->>'id','')::bigint,null,payload->>'name');
 perform pg_advisory_xact_lock(7311,1);$new$),
  ('solar_private.supplier_save(uuid,jsonb)',
   $old$and prior.payload=payload then return prior.response;$old$,
   $new$and prior.payload=payload then perform solar_private.require_supplier_access((prior.response->>'id')::bigint,null,prior.response->>'name');return prior.response;$new$),
  ('solar_private.fx(text,uuid,jsonb)',
   $old$(action='payment' and p.is_admin is not true)$old$,
   $new$(action='payment' and not(p.is_admin or solar_private.any_feature(p.permissions,'supplierPayment')))$new$),
  ('solar_private.fx(text,uuid,jsonb)',
   $old$if action='wallet' and payload->>'mode'$old$,
   $new$if action in('account','statement','currency','payment') then
   perform solar_private.require_supplier_access((payload->>'supplierId')::bigint,(payload->>'paymentId')::bigint);
  end if;
 if action='wallet' and payload->>'mode'$new$),
  ('solar_private.fx(text,uuid,jsonb)',
   $old$solar_private.any_feature(p.permissions,'supplierStatement')$old$,
   $new$solar_private.any_feature(p.permissions,'supplierPayment','supplierStatement')$new$),
  ('solar_private.fx(text,uuid,jsonb)',
   $old$from solar_private.supplier_fx_entries e where p.is_admin or (solar_private.any_feature$old$,
   $new$from solar_private.supplier_fx_entries e where p.is_admin or (not solar_private.supplier_admin_only(e.supplier_id) and solar_private.any_feature$new$),
  ('solar_private.supplier_account(bigint,bigint)',
   $old$or p.is_admin is not true then raise exception 'لا تملك صلاحية حساب المورد'$old$,
   $new$or not(p.is_admin or solar_private.any_feature(p.permissions,'supplierPayment')) then raise exception 'لا تملك صلاحية حساب المورد'$new$),
  ('solar_private.supplier_account(bigint,bigint)',
   $old$select * into s from public.suppliers where id=supplier_id;$old$,
   $new$perform solar_private.require_supplier_access(supplier_id,payment_id);
 select * into s from public.suppliers where id=supplier_id;$new$),
  ('solar_private.supplier_movement_save(uuid,bigint,bigint,numeric,text,text,text)',
   $old$or p.is_admin is not true then raise exception 'لا تملك صلاحية تسديد أو إضافة حساب مورد'$old$,
   $new$or not(p.is_admin or solar_private.any_feature(p.permissions,'supplierPayment')) then raise exception 'لا تملك صلاحية تسديد أو إضافة حساب مورد'$new$),
  ('solar_private.supplier_movement_save(uuid,bigint,bigint,numeric,text,text,text)',
   $old$if request_id is null or payment_id is null$old$,
   $new$perform solar_private.require_supplier_access(supplier_id,payment_id);
 if request_id is null or payment_id is null$new$),
  ('solar_private.supplier_payment_save(uuid,bigint,bigint,numeric,text,text)',
   $old$or p.is_admin is not true then raise exception 'تسديد المورد متاح للأدمن فقط'$old$,
   $new$or not(p.is_admin or solar_private.any_feature(p.permissions,'supplierPayment')) then raise exception 'لا تملك صلاحية تسديد المورد'$new$),
  ('solar_private.supplier_payment_save(uuid,bigint,bigint,numeric,text,text)',
   $old$if request_id is null or payment_id is null$old$,
   $new$perform solar_private.require_supplier_access(supplier_id,payment_id);
 if request_id is null or payment_id is null$new$),
  ('solar_private.supplier_payment_manage(text,uuid,jsonb)',
   $old$or actor.is_admin is not true then raise exception$old$,
   $new$or not(actor.is_admin or solar_private.any_feature(actor.permissions,'supplierPayment')) then raise exception$new$),
  ('solar_private.supplier_payment_manage(text,uuid,jsonb)',
   $old$if action in('update','delete') then
  if request_id$old$,
   $new$perform solar_private.require_supplier_access(null,(payload->>'id')::bigint);
 if action in('update','delete') then
  if request_id$new$),
  ('solar_private.supplier_payment_manage(text,uuid,jsonb)',
   $old$where tx.kind='supplier_payment' and tx.supplier_payment_voided_at is null$old$,
   $new$where tx.kind='supplier_payment' and (actor.is_admin or not solar_private.supplier_admin_only(tx.party_id,tx.party_name)) and tx.supplier_payment_voided_at is null$new$),
  ('solar_private.supplier_payment_get(bigint)',
   $old$not(p.is_admin or coalesce(p.permissions->>'supplierStatement','false')='true')$old$,
   $new$not(p.is_admin or solar_private.any_feature(p.permissions,'supplierPayment','supplierStatement'))$new$),
  ('solar_private.supplier_payment_get(bigint)',
   $old$select * into t from public.transactions where id=payment_id$old$,
   $new$perform solar_private.require_supplier_access(null,payment_id);
 select * into t from public.transactions where id=payment_id$new$),
  ('solar_private.payment_history(text,jsonb)',
   $old$if p.is_admin or coalesce(p.permissions->>'supplierStatement','false')='true' then allowed:=$old$,
   $new$if p.is_admin or solar_private.any_feature(p.permissions,'supplierPayment','supplierStatement') then allowed:=$new$),
  ('solar_private.payment_history(text,jsonb)',
   $old$where tx.kind=any(allowed) and tx.cash and tx.total>0$old$,
   $new$where tx.kind=any(allowed) and tx.cash and tx.total>0
    and (p.is_admin or tx.kind<>'supplier_payment' or not solar_private.supplier_admin_only(tx.party_id,tx.party_name))$new$)
 ) as changes(signature,old_text,new_text)
 loop
  definition:=pg_get_functiondef(patch.signature::regprocedure);
  if strpos(definition,patch.old_text)=0 then raise exception 'Review supplier access migration source for %',patch.signature;end if;
  execute replace(definition,patch.old_text,patch.new_text);
 end loop;
end $migration$;

notify pgrst,'reload schema';

-- For historical requests, both the saved document and the current receipt
-- count. Reassignment or cancellation must not uncover a protected snapshot.
create function solar_private.protected_supplier_document(doc jsonb) returns boolean
language sql stable set search_path='' as $$
 select coalesce(coalesce(doc#>>'{invoice,kind}',doc->>'kind') in ('purchase','supplier_payment')
  and solar_private.supplier_admin_only(
   nullif(coalesce(doc#>>'{invoice,party_id}',doc->>'party_id'),'')::bigint,
   coalesce(doc#>>'{invoice,party_name}',doc->>'party_name',doc->>'party')),false)
$$;

create function solar_private.protected_supplier_receipt(invoice_id bigint,snapshot jsonb default null) returns boolean
language sql stable security definer set search_path='' as $$
 select solar_private.protected_supplier_document(snapshot)
  or exists(select 1 from public.transactions t where t.id=$1 and t.kind in ('purchase','supplier_payment')
   and solar_private.supplier_admin_only(t.party_id,t.party_name))
  or exists(select 1 from solar_private.deleted_sales d where d.invoice_id=$1
   and solar_private.protected_supplier_document(d.invoice))
$$;
revoke all on function solar_private.protected_supplier_document(jsonb),solar_private.protected_supplier_receipt(bigint,jsonb) from public,anon,authenticated;

-- Direct line reads already require a visible parent through solar_item_owner.
create policy solar_protected_supplier_receipt_read on public.transactions as restrictive for select to authenticated
using ((select solar_private.role_name())='admin' or kind not in ('purchase','supplier_payment')
 or not solar_private.supplier_admin_only(party_id,party_name));

-- The notification body can include the supplier or an administrator's note.
create function solar_private.supplier_delete_notice_allowed(request_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from solar_private.receipt_delete_requests q where q.id=$1
  and exists(select 1 from public.solar_notifications n where n.delete_request_id=q.id and n.user_id=auth.uid())
  and not solar_private.protected_supplier_receipt(q.invoice_id,q.snapshot))
$$;
revoke all on function solar_private.supplier_delete_notice_allowed(uuid) from public,anon,authenticated;
grant execute on function solar_private.supplier_delete_notice_allowed(uuid) to authenticated;
create policy solar_protected_supplier_delete_notice on public.solar_notifications as restrictive for select to authenticated
using (delete_request_id is null or (select solar_private.role_name())='admin'
 or solar_private.supplier_delete_notice_allowed(delete_request_id));

drop trigger solar_guard_updated_purchase_debt on public.transactions;
drop trigger solar_guard_deleted_purchase_debt on public.transactions;
drop function solar_private.guard_purchase_supplier_debt();

create function solar_private.guard_protected_supplier_purchase() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if (auth.uid() is null and coalesce(current_setting('role',true),'') not in ('anon','authenticated')
     and session_user not in ('anon','authenticated','authenticator'))
    or solar_private.role_name()='admin' then return null;end if;
 if tg_table_name='transactions' then
  if (tg_op<>'INSERT' and old.kind='purchase' and solar_private.supplier_admin_only(old.party_id,old.party_name))
    or (tg_op<>'DELETE' and new.kind='purchase' and solar_private.supplier_admin_only(new.party_id,new.party_name)) then
   raise exception 'الوصل غير متاح ضمن صلاحياتك' using errcode='42501';
  end if;
 elsif tg_table_name='transaction_items' then
  if (tg_op<>'INSERT' and solar_private.protected_supplier_receipt(old.transaction_id))
   or (tg_op<>'DELETE' and solar_private.protected_supplier_receipt(new.transaction_id)) then
   raise exception 'الوصل غير متاح ضمن صلاحياتك' using errcode='42501';
  end if;
 else -- Archived documents have no FK to a current transaction.
  if (tg_op<>'INSERT' and solar_private.protected_supplier_document(old.invoice))
   or (tg_op<>'DELETE' and solar_private.protected_supplier_document(new.invoice)) then
   raise exception 'الوصل غير متاح ضمن صلاحياتك' using errcode='42501';
  end if;
 end if;
 return null;
end
$$;
revoke all on function solar_private.guard_protected_supplier_purchase() from public,anon,authenticated;
-- AFTER sees the canonical supplier resolved by FX, even for old name-only clients.
create trigger solar_protected_new_purchase after insert on public.transactions
 for each row when (new.kind='purchase') execute function solar_private.guard_protected_supplier_purchase();
create trigger solar_protected_modified_purchase after update on public.transactions
 for each row when (old.kind='purchase' or new.kind='purchase') execute function solar_private.guard_protected_supplier_purchase();
create trigger solar_protected_deleted_purchase after delete on public.transactions
 for each row when (old.kind='purchase') execute function solar_private.guard_protected_supplier_purchase();
create trigger solar_protected_purchase_items after insert or update or delete on public.transaction_items
 for each row execute function solar_private.guard_protected_supplier_purchase();
create trigger solar_protected_archived_document after insert or update or delete on solar_private.deleted_sales
 for each row execute function solar_private.guard_protected_supplier_purchase();

-- Run before projection, validation, and cached acknowledgements. Compare the
-- original invoice too when a purchase is edited or replayed with a new party.
create function solar_private.check_purchase_supplier_access(attempt_id uuid,body jsonb) returns void
language plpgsql stable security definer set search_path='' as $$
begin
 if body->>'kind'='purchase' and solar_private.role_name() is distinct from 'admin' and (
    solar_private.supplier_admin_only(nullif(body->>'partyId','')::bigint,body->>'party')
    or solar_private.protected_supplier_receipt(nullif(body->>'invoiceId','')::bigint)
    or exists(select 1 from solar_private.invoice_requests r where r.request_id=attempt_id and r.user_id=auth.uid()
      and solar_private.protected_supplier_receipt((r.result->>'id')::bigint))
 ) then raise exception 'الوصل غير متاح ضمن صلاحياتك' using errcode='42501';end if;
end
$$;
revoke all on function solar_private.check_purchase_supplier_access(uuid,jsonb) from public,anon,authenticated;

do $adjust$
declare definition text; target text; start_pos integer; end_pos integer;
begin
 foreach target in array array['solar_private.invoice_save(uuid,jsonb)','solar_private.invoice_attempt_resolve(uuid,jsonb)'] loop
  definition:=pg_get_functiondef(target::regprocedure);
  if strpos(definition,' perform pg_advisory_xact_lock(7311,1);')=0 then raise exception 'Changed lock in %',target;end if;
  execute replace(definition,' perform pg_advisory_xact_lock(7311,1);',
    ' perform pg_advisory_xact_lock(7311,1); perform solar_private.check_purchase_supplier_access(request_id,payload);');
 end loop;

 definition:=pg_get_functiondef('public.solar_purchase_correction_preview(jsonb)'::regprocedure);
 start_pos:=strpos(definition,'plan:=solar_private.purchase_correction_plan(payload);');
 end_pos:=strpos(definition,'plan:=plan||jsonb_build_object(''materialScope''');
 if start_pos=0 or end_pos<=start_pos or strpos(substr(definition,start_pos,end_pos-start_pos),'solar_private.purchase_supplier_debt')=0 then
  raise exception 'Review previous credit purchase preview';end if;
 execute substr(definition,1,start_pos-1)
  ||'perform solar_private.check_purchase_supplier_access(null,payload||jsonb_build_object(''kind'',''purchase''));
     plan:=solar_private.purchase_correction_plan(payload); '
  ||substr(definition,end_pos);

 definition:=pg_get_functiondef('solar_private.receipt_direct_eligibility(bigint)'::regprocedure);
 target:='if not p.is_admin and solar_private.purchase_supplier_debt(t) is not null then';
 if strpos(definition,target)=0 then raise exception 'Review previous credit purchase direct delete';end if;
 execute replace(definition,target,'if not p.is_admin and solar_private.supplier_admin_only(t.party_id,t.party_name) then');

 definition:=pg_get_functiondef('solar_private.receipt_delete_context(bigint)'::regprocedure);
 target:='context:=solar_private.receipt_delete_context_v3102(invoice_id);';
 if strpos(definition,target)=0 then raise exception 'Review receipt deletion context';end if;
 execute replace(definition,target,'if solar_private.role_name() is distinct from ''admin''
   and solar_private.protected_supplier_receipt(invoice_id) then raise exception ''الوصل غير متاح ضمن صلاحياتك'' using errcode=''42501'';end if; '||target);

 -- Filter before LIMIT so old protected requests do not displace permitted ones.
 definition:=pg_get_functiondef('solar_private.receipt_delete_requests_v3102(text,uuid,jsonb)'::regprocedure);
 target:='from(select * from solar_private.receipt_delete_requests q where(p.is_admin';
 if strpos(definition,target)=0 then raise exception 'Review deletion request listing';end if;
 execute replace(definition,target,'from(select * from solar_private.receipt_delete_requests q where
   (p.is_admin or not solar_private.protected_supplier_receipt(q.invoice_id,q.snapshot)) and (p.is_admin');

 definition:=pg_get_functiondef('solar_private.receipt_delete_requests(text,uuid,jsonb)'::regprocedure);
 target:='result:=solar_private.receipt_delete_requests_v4124(action,request_id,payload);';
 if strpos(definition,target)=0 then raise exception 'Review receipt deletion request wrapper';end if;
 execute replace(definition,target,$check$
 if action in ('request','approve','reject','cancel','delete_direct') then perform pg_advisory_xact_lock(7311,1);end if;
 if action <> 'list' and solar_private.role_name() is distinct from 'admin' and (
   solar_private.protected_supplier_receipt((payload->>'invoiceId')::bigint) or
   exists(select 1 from solar_private.receipt_delete_requests q where q.id=request_id and solar_private.protected_supplier_receipt(q.invoice_id,q.snapshot)) or
   exists(select 1 from solar_private.receipt_delete_executions e where e.request_id=receipt_delete_requests.request_id and solar_private.protected_supplier_receipt(e.invoice_id,e.snapshot))
 ) then raise exception 'الوصل غير متاح ضمن صلاحياتك' using errcode='42501';end if;
 $check$||target);
end
$adjust$;
drop function solar_private.purchase_supplier_debt(public.transactions);

-- A wallet refund and the supplier reversal are posted in a single transaction.
-- Older refunds have no transaction_id. Use the paired reversal and its source
-- receipt, so unrelated supplier refunds keep their existing visibility.
create function solar_private.protected_supplier_fx(entry_source text, entry_id bigint)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare wallet solar_private.wallet_fx_entries; entry solar_private.supplier_fx_entries;
 archive jsonb; restricted boolean;
begin
 if entry_source='supplier' then
  select * into entry from solar_private.supplier_fx_entries where id=entry_id;
  return not found or solar_private.supplier_admin_only(entry.supplier_id)
   or (coalesce(entry.transaction_id,entry.correction_for) is not null
    and solar_private.protected_supplier_receipt(coalesce(entry.transaction_id,entry.correction_for)));
 end if;
 if entry_source<>'wallet' then return false;end if;
 select * into wallet from solar_private.wallet_fx_entries where id=entry_id;
 if not found then return true;end if;
 if wallet.transaction_id is not null then
  return solar_private.protected_supplier_receipt(wallet.transaction_id,
   (select o.invoice from solar_private.purchase_originals o where o.invoice_id=wallet.transaction_id));
 end if;
 if wallet.entry_type='supplier_payment_refund' then
  select bool_or(solar_private.supplier_admin_only(e.supplier_id) or solar_private.protected_supplier_receipt(e.correction_for))
  into restricted from solar_private.supplier_fx_entries e
  where e.correction_for is not null and e.owner_id=wallet.owner_id and e.created_at=wallet.created_at and e.note=wallet.note;
  return coalesce(restricted,true);
 end if;
 if wallet.entry_type in ('supplier_cash','purchase_correction','purchase_refund') then
  if wallet.entry_type='purchase_correction' and exists(select 1 from solar_private.purchase_corrections c
   where c.ledger->>'walletEntryId'=entry_id::text and
   (solar_private.protected_supplier_document(c.before_invoice) or solar_private.protected_supplier_document(c.after_invoice))) then
   return true;
  end if;
  archive:=solar_private.purchase_archive_entry('wallet',entry_id);
  if archive is null then return true;end if;
  return solar_private.protected_supplier_receipt((archive->>'id')::bigint)
    or solar_private.supplier_admin_only(null,archive->>'party');
 end if;
 return false;
end $$;
revoke all on function solar_private.protected_supplier_fx(text,bigint) from public,anon,authenticated;

create function solar_private.protected_supplier_cash(movement_id text) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare tid bigint;
begin
 if movement_id ~ '^fx:-?[0-9]+$' then
  return solar_private.protected_supplier_fx('wallet',substr(movement_id,4)::bigint);
 elsif movement_id ~ '^tx:-?[0-9]+$' then
  tid:=substr(movement_id,4)::bigint;
  return solar_private.protected_supplier_receipt(tid,(select o.invoice from solar_private.purchase_originals o where o.invoice_id=tid));
 elsif movement_id ~ '^entry:[a-f0-9-]{36}$' then
  select coalesce(e.job_id,e.deleted_job_id) into tid from public.solar_cash_entries e where e.id=substr(movement_id,7)::uuid;
  return tid is not null and solar_private.protected_supplier_receipt(tid);
 end if;
 return false;
end $$;
revoke all on function solar_private.protected_supplier_cash(text) from public,anon,authenticated;

do $migration$
declare edit record; definition text;
begin
 for edit in select * from (values
  ('solar_private.invoice_read_allowed(bigint)',
   $old$ select t.created_by,t.kind into creator,receipt_kind$old$,
   $new$ if solar_private.protected_supplier_receipt(invoice_id) then return false;end if;
 select t.created_by,t.kind into creator,receipt_kind$new$),
  ('solar_private.invoice_read_allowed(bigint)',
   $old$solar_private.any_feature(solar_private.office_features(),'supplierStatement')$old$,
   $new$solar_private.any_feature(solar_private.office_features(),'supplierStatement','supplierPayment')$new$),
  ('solar_private.cash_read_restricted(text)',
   $old$ if solar_private.can_access_invoice(null,false) then return false;end if;$old$,
   $new$ if solar_private.can_access_invoice(null,false) then return false;end if;
 if solar_private.protected_supplier_cash(movement_id) then return true;end if;$new$),
  ('solar_private.cash_read_restricted(text)',
   $old$solar_private.any_feature(solar_private.office_features(),'supplierStatement')$old$,
   $new$solar_private.any_feature(solar_private.office_features(),'supplierStatement','supplierPayment')$new$),
  ('solar_private.cash_read_projection(jsonb)',
   $old$ return safe ||$old$,
   $new$ if solar_private.protected_supplier_cash(row_data->>'id') then safe:=safe-array['rate','source_currency','sourceCurrency'];end if;
 return safe ||$new$),
  ('solar_private.fx_entry_read_projection(jsonb,text)',
   $old$ if entry_source='wallet' and row_data->>'entry_type'='supplier_payment_refund'$old$,
   $new$ if solar_private.protected_supplier_fx(entry_source,(row_data->>'id')::bigint) then
  return jsonb_build_object('id','restricted:'||md5(auth.uid()::text||':'||entry_source||':'||(row_data->>'id')),
   'receiptRestricted',true,'owner_id',row_data->'owner_id','created_at',row_data->'created_at','gain',row_data->'gain',
   'note','حركة مالية مرتبطة بوصل محجوب')||case when entry_source='wallet' then
    jsonb_build_object('currency',row_data->'currency','delta',row_data->'delta','book_delta',row_data->'book_delta',
     'entry_type',row_data->'entry_type') else '{}'::jsonb end;
 end if;
 if entry_source='wallet' and row_data->>'entry_type'='supplier_payment_refund'$new$),
  ('solar_private.fx_entry_read_projection(jsonb,text)',
   $old$solar_private.any_feature(solar_private.office_features(),'supplierStatement')$old$,
   $new$solar_private.any_feature(solar_private.office_features(),'supplierStatement','supplierPayment')$new$),
  ('solar_private.personal_receipt_snapshot(bigint,text[])',
   $old$    and t.kind in ('sale','system','purchase') and t.kind=any(kinds)$old$,
   $new$    and t.kind in ('sale','system','purchase') and t.kind=any(kinds)
    and (t.kind<>'purchase' or not solar_private.supplier_admin_only(t.party_id,t.party_name))$new$),
  ('solar_private.profit_read_projection(jsonb)',
   $old$    and not solar_private.any_feature(solar_private.office_features(),'supplierStatement') then$old$,
   $new$    and (not solar_private.any_feature(solar_private.office_features(),'supplierStatement','supplierPayment') or
     case when value ? 'supplier_receipt' then
       solar_private.supplier_admin_only((value->>'supplier_id')::bigint,value#>>'{supplier_receipt,name}')
       or (value->>'supplier_id' is null and exists(select 1 from solar_private.profit_settlements s
         where s.id=(value->>'id')::uuid and solar_private.supplier_admin_only(s.supplier_id,s.supplier_receipt->>'name')))
      when source_key like 'walletfx:%' then solar_private.protected_supplier_fx('wallet',substr(source_key,10)::bigint)
      else solar_private.protected_supplier_fx('supplier',substr(source_key,12)::bigint) end) then$new$)
 ) as patches(signature,old_text,new_text) loop
  definition:=pg_get_functiondef(edit.signature::regprocedure);
  if strpos(definition,edit.old_text)=0 then raise exception 'Review supplier visibility in %',edit.signature;end if;
  execute replace(definition,edit.old_text,edit.new_text);
 end loop;
end
$migration$;

-- These reports run with their owner's privileges. Apply supplier scope before
-- pagination and financial aggregation, including unmatched historical names.
do $migration$
declare edit record; definition text;
begin
 for edit in select * from (values
  ('solar_private.quick_search(text,text)',
   $old$where solar_private.quick_search_matches(s.name||' '||coalesce(s.phone,''),words)$old$,
   $new$where (p.is_admin or not solar_private.supplier_admin_only(s.id,s.name))
     and solar_private.quick_search_matches(s.name||' '||coalesce(s.phone,''),words)$new$),

  ('solar_private.party_balances_legacy_iqd(text,date)',
   $old$from public.suppliers s where report_kind='suppliers'$old$,
   $new$from public.suppliers s where report_kind='suppliers' and (p.is_admin or not solar_private.supplier_admin_only(s.id,s.name))$new$),
  ('solar_private.party_balances_legacy_iqd(text,date)',
   $old$and (report_kind='customers' or p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id)$old$,
   $new$and (report_kind='customers' or p.is_admin or
    (coalesce(t.cashbox_user_id,t.created_by)=p.id and not solar_private.supplier_admin_only(t.party_id,t.party_name)))$new$),
  ('solar_private.supplier_fx_balances(date)',
   $old$last_pay on true;$old$,
   $new$last_pay on true
   where p.is_admin or not solar_private.supplier_admin_only(s.id,s.name);$new$),

  ('solar_private.capital_snapshot(boolean)',
   $old$where company or e.owner_id=p.id$old$,
   $new$where company or (e.owner_id=p.id and not solar_private.supplier_admin_only(s.id,s.name))$new$),
  ('solar_private.capital_snapshot(boolean)',
   $old$where t.kind in('purchase','supplier_payment') and t.supplier_payment_voided_at is null and(company or t.created_by=p.id)$old$,
   $new$where t.kind in('purchase','supplier_payment') and t.supplier_payment_voided_at is null
    and (company or (t.created_by=p.id and not solar_private.supplier_admin_only(t.party_id,t.party_name)))$new$),
  ('solar_private.capital_snapshot(boolean)',
   $old$and t.payment_mode in('opening_balance','charge_old_balance') and t.supplier_payment_voided_at is null$old$,
   $new$and t.payment_mode in('opening_balance','charge_old_balance') and t.supplier_payment_voided_at is null
    and (company or t.kind<>'supplier_payment' or not solar_private.supplier_admin_only(t.party_id,t.party_name))$new$),

  -- Keep cash totals intact while protecting document references in the
  -- historical cash view, including cancellations whose source is archived.
  ('solar_private.capital_snapshot(boolean)',
   $old$coalesce(jsonb_agg(jsonb_build_object('id',id,'ownerId',owner_id,'ownerName',owner_name,'currency',currency,'delta',delta,'bookDelta',book_delta,
   'kind',kind,'party',party,'notes',note,'receiptNo',receipt_no,'date',created_at) order by created_at,id),'[]')$old$,
   $new$coalesce(jsonb_agg(case when not company and solar_private.cash_read_restricted(id) then
    jsonb_build_object('id','restricted:'||md5(p.id::text||':'||id),'ownerId',owner_id,'ownerName',owner_name,
     'currency',currency,'delta',delta,'bookDelta',book_delta,'kind',kind,'party','','notes','','receiptNo',null,'date',created_at,'receiptRestricted',true)
    else jsonb_build_object('id',id,'ownerId',owner_id,'ownerName',owner_name,'currency',currency,'delta',delta,'bookDelta',book_delta,
     'kind',kind,'party',party,'notes',note,'receiptNo',receipt_no,'date',created_at) end order by created_at,id),'[]')$new$),

  -- Quantities, running balances and correction order still include the
  -- underlying stock event. Expose an opaque id after ordering, so the
  -- material report cannot enrich a protected event with receipt details.
  ('solar_private.inventory_movements(bigint,bigint,text,date,date)',
   $old$jsonb_build_object('id',id,'productId',product_id,'name',product_name,'brand',brand_name,'category',category,'receiptNo',receipt_no,'kind',kind,'party',party_name$old$,
   $new$jsonb_build_object('id',case when source.protected then 'restricted:'||md5(auth.uid()::text||':'||id) else id end,
    'productId',product_id,'name',product_name,'brand',brand_name,'category',category,
    'receiptNo',case when not source.protected then receipt_no end,'kind',kind,'party',case when source.protected then '' else party_name end$new$),
  ('solar_private.inventory_movements(bigint,bigint,text,date,date)',
   $old$into result from balances
 where (solar_private.role_name()$old$,
   $new$into result from balances
 cross join lateral (select case when balances.kind='purchase' and (select solar_private.role_name()) is distinct from 'admin' then
    exists(select 1 from public.transaction_items i join public.transactions t on t.id=i.transaction_id
     where i.id=substr(balances.id,6)::bigint and solar_private.supplier_admin_only(t.party_id,t.party_name))
    else false end as protected offset 0) source
 where (solar_private.role_name()$new$)
 ) as changes(signature,previous,replacement)
 loop
  definition:=pg_get_functiondef(edit.signature::regprocedure);
  if strpos(definition,edit.previous)=0 then raise exception 'Expected report definition missing for %',edit.signature;end if;
  execute replace(definition,edit.previous,edit.replacement);
 end loop;
end $migration$;
