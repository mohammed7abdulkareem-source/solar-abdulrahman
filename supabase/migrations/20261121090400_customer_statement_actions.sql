-- Enrich only a single, authorized account read. Bulk directory and search
-- operations continue to use their existing private projections.
create function solar_private.customer_account_actions(customer_id bigint,directory_access boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare account jsonb; action_rows jsonb;
begin
 account:=case when directory_access then solar_private.customer_get(customer_id)
               else solar_private.customer_statement(customer_id) end;
 select coalesce(jsonb_agg(case when r.value->'receiptRestricted'='true'::jsonb then r.value
  else r.value || jsonb_build_object(
    'canEditReceipt',case
     when t.kind in ('sale','system') then p.is_admin or
      (p.id=t.created_by and solar_private.receipt_feature(p.permissions,t.kind,true))
     when t.kind in ('customer_payment','system_payment') then solar_private.statement_payment_editable(t,c,p)
     else false end,
    'canDeleteReceipt',case
     when t.kind in ('sale','system') and t.created_by is not null and solar_private.can_delete_sale(t.created_by)
      and (p.is_admin or solar_private.delete_kind_feature(p.permissions,t.kind))
     then case when p.is_admin or solar_private.any_feature(p.permissions,'deletionRequests') then true
               else coalesce((solar_private.receipt_direct_eligibility(t.id)->>'directEligible')::boolean,false) end
     when t.kind in ('customer_payment','system_payment') then
      coalesce(t.payment_mode,'') not in ('opening_balance','account_reconciliation')
      and coalesce(t.cashbox_user_id,t.created_by) is not null
      and (p.is_admin or (c.owner_id=p.id and t.created_by=p.id and coalesce(t.cashbox_user_id,t.created_by)=p.id
        and solar_private.delete_kind_feature(p.permissions,t.kind) and solar_private.any_feature(p.permissions,'deletionRequests')))
     else false end)
  end order by r.ordinality),'[]'::jsonb) into action_rows
 from jsonb_array_elements(account->'rows') with ordinality r(value,ordinality)
 join public.customers c on c.id=customer_account_actions.customer_id
 join public.profiles p on p.id=auth.uid() and p.active and p.user_type not in ('warehouse','installer')
 left join public.transactions t on t.id=case when r.value->'receiptRestricted' is distinct from 'true'::jsonb
   then (r.value->>'id')::bigint end;
 return jsonb_set(account,'{rows}',action_rows);
end $$;

revoke all on function solar_private.customer_account_actions(bigint,boolean) from public,anon,authenticated;
grant execute on function solar_private.customer_account_actions(bigint,boolean) to authenticated;
create or replace function public.solar_customer_statement(customer_id bigint) returns jsonb
language sql stable security invoker set search_path='' as $$
 select solar_private.customer_account_actions(customer_id,false)
$$;
create or replace function public.solar_customer_get(customer_id bigint) returns jsonb
language sql stable security invoker set search_path='' as $$
 select solar_private.customer_account_actions(customer_id,true)
$$;
