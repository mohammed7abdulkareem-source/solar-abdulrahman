-- Shared only by profit reads, inside their existing authenticated scope.
create function solar_private.assigned_profit_receipt(receipt_id bigint, financial_owner uuid, posted_only boolean)
returns boolean language sql stable security invoker set search_path='' as $$
 select exists (
  select 1 from solar_private.customer_receipt_responsibility a
  join public.transactions t on t.id=a.transaction_id
  left join solar_private.invoice_profit_owners f on f.invoice_id=t.id
  join public.profiles viewer on viewer.id=auth.uid() and viewer.active and viewer.user_type not in ('warehouse','installer')
  where a.transaction_id=receipt_id and a.owner_id=financial_owner
    and coalesce(f.owner_id,t.cashbox_user_id,t.created_by)=financial_owner
    and (viewer.is_admin or (viewer.id=financial_owner and solar_private.any_feature(viewer.permissions,'profit','profitSettlement')))
    and t.profit_settlement_id is null and t.kind in ('sale','system')
    and (not posted_only or t.kind='sale' or t.installation_status='closed')
 )
$$;
revoke all on function solar_private.assigned_profit_receipt(bigint,uuid,boolean) from public,anon,authenticated;

do $migration$
declare definition text;
begin
 definition:=pg_get_functiondef('solar_private.profit_read_projection(jsonb)'::regprocedure);
 if md5(definition)<>'577df60b91061679f62ca8ef62d3cd19' then raise exception 'Review current profit read projection'; end if;
 definition:=replace(definition,
  $old$and not solar_private.invoice_read_allowed(substr(source_key,4)::bigint) then$old$,
  $new$and not solar_private.invoice_read_allowed(substr(source_key,4)::bigint) then
   if not coalesce((value->>'deleted')::boolean,false)
      and solar_private.assigned_profit_receipt(substr(source_key,4)::bigint,auth.uid(),true) then
    return result||jsonb_build_object('assignedReceipt',true,'label',coalesce(
     (select nullif(t.party_name,'') from public.transactions t where t.id=substr(source_key,4)::bigint),'ربح وصل بيع'));
   end if;$new$);
 execute definition;

 definition:=pg_get_functiondef('solar_private.profit_detail(text,uuid)'::regprocedure);
 if md5(definition)<>'f33a5e375d43505e2e479014df328200' then raise exception 'Review current profit receipt detail'; end if;
 definition:=replace(definition,'and not solar_private.invoice_read_allowed(t.id) then',
  'and not solar_private.invoice_read_allowed(t.id) and not solar_private.assigned_profit_receipt(t.id,p.id,true) then');
 definition:=replace(definition,$old$    sales:=case when t.kind='sale'$old$,
  $new$    if t.kind='system' then materials_cost:=coalesce(t.cost,materials_cost); end if;
    sales:=case when t.kind='sale'$new$);
 definition:=replace(definition,
  $old$'profitAdjustment',(movement->>'value')::numeric-(sales-materials_cost)$old$,
  $new$'profitAdjustment',(movement->>'value')::numeric-(sales-materials_cost)
       +coalesce(t.installation_expenses,0)
       +case when t.kind='sale' and coalesce(t.expenses_on_customer,true) then 0 else coalesce(t.expenses,0) end$new$);
 definition:=replace(definition,
  $old$if not p.is_admin and coalesce(t.created_by,t.cashbox_user_id)<>p.id then return jsonb_build_object('movement',movement,'invoice',null,'transferred',true,'breakdown',breakdown);end if;$old$,
  $new$if not p.is_admin and t.kind in('sale','system') and t.created_by is distinct from p.id then
    return jsonb_build_object('movement',solar_private.profit_read_projection(movement),'invoice',null,'transferred',true,
     'breakdown',breakdown||jsonb_build_object('responsibleName',solar_private.user_name(p.display_name,p.username,p.honorific)));
   elsif not p.is_admin and coalesce(t.created_by,t.cashbox_user_id)<>p.id then
    return jsonb_build_object('movement',movement,'invoice',null,'transferred',true,'breakdown',breakdown);
   end if;$new$);
 execute definition;

 -- Append selected receipts after the existing customer collection/account queries.
 -- They contribute only to the open-file counters and provisional profit.
 definition:=pg_get_functiondef('solar_private.pending_systems(uuid,date,date)'::regprocedure);
 if md5(definition)<>'524727cace5c93ad791ed989e4a1dbc2' then raise exception 'Review current open system account projection'; end if;
 definition:=replace(definition,'result jsonb;accounts jsonb;','result jsonb;accounts jsonb;assigned jsonb;summary jsonb;target uuid;original_rows jsonb;transferred_profit numeric;');
 definition:=replace(definition,$old$ return result||jsonb_build_object('collectionBasis'$old$,
  $new$ target:=case when p.is_admin then owner_id else p.id end;
 if target is not null then
  -- The issuer retains the receipt and its collection history. Its projected
  -- profit belongs once to the beneficiary for whom both assignments agree.
  with classified as (
   select r.value,r.ordinality,exists(
    select 1 from solar_private.customer_receipt_responsibility a
    join public.transactions t on t.id=a.transaction_id
    left join solar_private.invoice_profit_owners f on f.invoice_id=t.id
    where a.transaction_id=(r.value->>'id')::bigint and a.owner_id<>target
      and coalesce(f.owner_id,t.cashbox_user_id,t.created_by)=a.owner_id
   ) other_account
   from jsonb_array_elements(result->'rows') with ordinality r
  )
  select coalesce(jsonb_agg(case when other_account then value||jsonb_build_object(
    'receiptProvisionalProfit',value->'provisionalProfit','provisionalProfit',0,'profitAttributedElsewhere',true)
    else value end order by ordinality),'[]'::jsonb),
    coalesce(sum((value->>'provisionalProfit')::numeric) filter(where other_account),0)
   into original_rows,transferred_profit from classified;
  result:=jsonb_set(jsonb_set(result,'{rows}',original_rows),'{summary,provisionalProfit}',
   to_jsonb((result#>>'{summary,provisionalProfit}')::numeric-transferred_profit));
 end if;
 if target is not null and (p.is_admin or solar_private.any_feature(p.permissions,'profit','profitSettlement')) then
  with extra as (
   select t.id,t.receipt_no,t.created_at,t.party_name,t.installation_status,t.total,t.cost,
    coalesce(t.expenses,0) invoice_expense,coalesce(t.installation_expenses,0) installation_expense,
    solar_private.user_name(author.display_name,author.username,author.honorific) creator,
    solar_private.user_name(owner.display_name,owner.username,owner.honorific) responsible
   from solar_private.customer_receipt_responsibility a join public.transactions t on t.id=a.transaction_id
   left join public.profiles author on author.id=t.created_by join public.profiles owner on owner.id=a.owner_id
   where a.owner_id=target and t.created_by is distinct from target and t.kind='system'
    and coalesce(t.installation_status,'none')<>'closed' and solar_private.assigned_profit_receipt(t.id,target,false)
    and (date_from is null or t.created_at>=(date_from::timestamp at time zone 'Asia/Baghdad'))
    and (date_to is null or t.created_at<((date_to+1)::timestamp at time zone 'Asia/Baghdad'))
  )
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'receiptNo',receipt_no,'date',created_at,'customer',party_name,
   'status',installation_status,'creatorName',creator,'responsibleName',responsible,'total',total,'materialCost',cost,
   'invoiceExpenses',invoice_expense,'approvedExpenses',installation_expense,
   'provisionalProfit',round(total-cost-invoice_expense-installation_expense,2)) order by created_at,id),'[]'::jsonb),
   jsonb_build_object('count',count(*),'invoiceTotal',coalesce(sum(total),0),
    'provisionalProfit',coalesce(sum(round(total-cost-invoice_expense-installation_expense,2)),0))
  into assigned,summary from extra;
  result:=result||jsonb_build_object('assignedRows',assigned,'summary',(result->'summary')||jsonb_build_object(
   'count',(result#>>'{summary,count}')::bigint+(summary->>'count')::bigint,
   'invoiceTotal',(result#>>'{summary,invoiceTotal}')::numeric+(summary->>'invoiceTotal')::numeric,
   'provisionalProfit',(result#>>'{summary,provisionalProfit}')::numeric+(summary->>'provisionalProfit')::numeric));
 end if;
 return result||jsonb_build_object('collectionBasis'$new$);
 execute definition;
end $migration$;
