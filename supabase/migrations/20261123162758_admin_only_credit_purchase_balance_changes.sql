-- Only posted supplier debt is protected here. New purchases and edits that
-- leave the existing debt unchanged follow the original purchase workflow.
create function solar_private.purchase_supplier_debt(t public.transactions) returns jsonb
language sql immutable set search_path='' as $$
 select case when t.kind='purchase' and not t.cash
  and (coalesce(t.account_amount,0)<>0 or coalesce(t.total,0)<>0) then
  jsonb_build_array(t.party_id,case when t.party_id is null then t.party_name end,
   coalesce(t.cashbox_user_id,t.created_by),t.account_currency,t.account_revision,t.account_amount,t.total)
 end
$$;
revoke all on function solar_private.purchase_supplier_debt(public.transactions) from public,anon;
grant execute on function solar_private.purchase_supplier_debt(public.transactions) to authenticated;

create function solar_private.guard_purchase_supplier_debt() returns trigger
language plpgsql set search_path='' as $$
declare new_debt jsonb;
begin
 if tg_op='UPDATE' then new_debt:=solar_private.purchase_supplier_debt(new);end if;
 if solar_private.purchase_supplier_debt(old) is distinct from new_debt
  and (auth.uid() is not null or current_user in ('anon','authenticated')
   or current_setting('role',true) in ('anon','authenticated'))
  and solar_private.role_name() is distinct from 'admin' then
  raise exception 'تغيير دين المورد على فاتورة شراء محفوظة أو حذفها من صلاحيات الأدمن.' using errcode='42501';
 end if;
 return null; -- AFTER row trigger, including writes through security-definer RPCs.
end
$$;
revoke all on function solar_private.guard_purchase_supplier_debt() from public,anon,authenticated;
create trigger solar_guard_updated_purchase_debt after update on public.transactions
 for each row when ((old.kind='purchase' and not old.cash) or (new.kind='purchase' and not new.cash))
 execute function solar_private.guard_purchase_supplier_debt();
create trigger solar_guard_deleted_purchase_debt after delete on public.transactions
 for each row when (old.kind='purchase' and not old.cash)
 execute function solar_private.guard_purchase_supplier_debt();

-- Keep deletion context (including old clients) and the purchase preview in
-- sync with the row guard. Ordinary creation never enters either function.
do $patch$
declare def text; anchor text;
begin
 def:=pg_get_functiondef('solar_private.receipt_direct_eligibility(bigint)'::regprocedure);
 anchor:=$find$ if t.kind='purchase' then
  return jsonb_build_object('directEligible',true,$find$;
 if strpos(def,anchor)=0 then raise exception 'Purchase deletion eligibility changed';end if;
 execute replace(def,anchor,$inline$ if t.kind='purchase' then
  if not p.is_admin and solar_private.purchase_supplier_debt(t) is not null then
   return jsonb_build_object('directEligible',false,'deletionMode','approval','directBlockedReason','حذف فاتورة شراء عليها دين للمورد يحتاج موافقة الأدمن.');
  end if;
  return jsonb_build_object('directEligible',true,$inline$);

 def:=pg_get_functiondef('public.solar_purchase_correction_preview(jsonb)'::regprocedure);
 anchor:=$find$plan:=solar_private.purchase_correction_plan(payload);$find$;
 if strpos(def,anchor)=0 then raise exception 'Purchase correction preview changed';end if;
 execute replace(def,anchor,anchor||$inline$
 if (plan->>'canApply')::boolean and solar_private.role_name() is distinct from 'admin' then
  declare proposed public.transactions;
  begin
   select * into strict t from public.transactions where id=(payload->>'invoiceId')::bigint;
   proposed:=t;
   proposed.cash:=(coalesce(payload->>'mode',t.payment_mode)='cash');
   proposed.total:=(plan#>>'{after,total}')::numeric;
   proposed.account_amount:=(plan#>>'{after,accountAmount}')::numeric;
   proposed.account_currency:=plan#>>'{after,accountCurrency}';
   proposed.account_revision:=coalesce((payload->>'accountRevision')::bigint,t.account_revision);
   if not (plan->>'requiresCorrection')::boolean and payload->>'party' is not null then
    proposed.party_name:=payload->>'party';
    select s.id into proposed.party_id from public.suppliers s where s.name=proposed.party_name and s.active order by s.id limit 1;
   end if;
   if solar_private.purchase_supplier_debt(t) is distinct from solar_private.purchase_supplier_debt(proposed) then
    plan:=plan||jsonb_build_object('canApply',false,'blockedReason','تغيير دين المورد على فاتورة شراء محفوظة من صلاحيات الأدمن.');
   end if;
  end;
 end if;$inline$);
end
$patch$;
