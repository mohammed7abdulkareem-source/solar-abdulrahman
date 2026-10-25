-- Expense reversals reduce the expense; they are never a second expense.
-- Only projections change here. Existing cash/expense records remain intact.
do $$declare definition text;needle text;begin
 definition:=pg_get_functiondef('solar_private.profit_rows(uuid)'::regprocedure);
 needle:='null,-abs(e.delta) from public.solar_cash_entries e';
 if strpos(definition,needle)=0 then raise exception 'Profit expense projection contract missing';end if;
 execute replace(definition,needle,'null,e.delta from public.solar_cash_entries e');
 definition:=pg_get_functiondef('solar_private.retained_profit(uuid)'::regprocedure);
 needle:='-coalesce((select sum(abs(e.delta)) from public.solar_cash_entries e';
 if strpos(definition,needle)=0 then raise exception 'Retained expense projection contract missing';end if;
 execute replace(definition,needle,'+coalesce((select sum(e.delta) from public.solar_cash_entries e');

 -- Expose the invoice/customer already linked to each installation cash entry.
 -- Monetary columns, movement IDs and original audit notes are unchanged.
 definition:=pg_get_functiondef('solar_private.cash_movements()'::regprocedure);
 needle:=$n$e.entry_type,'',e.notes,null,1,'IQD',abs(e.delta),e.created_at,null::uuid from public.solar_cash_entries e$n$;
 if strpos(definition,needle)=0 then raise exception 'Installation cash label contract missing';end if;
 execute replace(definition,needle,$n$e.entry_type,coalesce(j.party_name,''),e.notes,j.receipt_no,1,'IQD',abs(e.delta),e.created_at,null::uuid from public.solar_cash_entries e left join public.transactions j on j.id=e.job_id$n$);

 -- Only financial reviewers receive paid totals; engineer/warehouse data stays scoped.
 definition:=pg_get_functiondef('solar_private.installation_jobs()'::regprocedure);
 needle:=$n$'installationExpenses',t.installation_expenses,'installationExpenseNotes'$n$;
 if strpos(definition,needle)=0 then raise exception 'Installation paid expense contract missing';end if;
 execute replace(definition,needle,$n$'installationExpenses',t.installation_expenses,'installationPaidExpenses',-(select coalesce(sum(e.delta),0) from public.solar_cash_entries e where e.job_id=t.id and e.entry_type in('installation_payout','installation_refund')),'installationExpenseNotes'$n$);
end$$;

create function solar_private.pending_systems(owner_id uuid default null,date_from date default null,date_to date default null) returns jsonb
language plpgsql stable security definer set search_path='' set statement_timeout='10s' as $$
declare p public.profiles;result jsonb;begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('installer','warehouse');
 if p.id is null or not(p.is_admin or coalesce(p.permissions->>'profit','false')='true' or coalesce(p.permissions->>'profitSettlement','false')='true' or coalesce(p.permissions->>'system','false')='true' or coalesce(p.permissions->>'installations','false')='true') then raise exception 'لا تملك صلاحية كشف المنظومات غير المغلقة' using errcode='42501';end if;
 if not p.is_admin and pending_systems.owner_id is not null and pending_systems.owner_id<>p.id then raise exception 'يمكنك مشاهدة منظوماتك فقط' using errcode='42501';end if;
 if date_from is not null and date_to is not null and date_from>date_to then raise exception 'اختر فترة صحيحة' using errcode='22023';end if;
 with eligible as materialized(
  select t.*,l.customer_id,coalesce(o.display_name,o.username,'غير محدد') creator_name
  from public.transactions t left join solar_private.customer_movement_links() l on l.transaction_id=t.id left join public.profiles o on o.id=t.created_by
  where t.kind='system' and coalesce(t.installation_status,'none')<>'closed'
   and(case when p.is_admin then pending_systems.owner_id is null or t.created_by=pending_systems.owner_id else t.created_by=p.id end)
   and(date_from is null or t.created_at>=(date_from::timestamp at time zone 'Asia/Baghdad'))
   and(date_to is null or t.created_at<((date_to+1)::timestamp at time zone 'Asia/Baghdad'))
 ), receipts as materialized(
  select x.id,x.system_invoice_id,x.kind,x.created_by,coalesce(sum(m.book_delta),0) amount
  from public.transactions x join solar_private.cash_movements() m on m.id='tx:'||x.id
  where x.kind in('system','system_payment') and x.cash
  group by x.id,x.system_invoice_id,x.kind,x.created_by
 ), invoice_rows as materialized(
  select t.id,t.receipt_no,t.party_name,t.created_at,t.installation_status,t.created_by,t.creator_name,
   t.total,t.cost,coalesce(t.expenses,0) invoice_expenses,coalesce(t.installation_expenses,0) approved_expenses,
   -(select coalesce(sum(e.delta),0) from public.solar_cash_entries e where e.job_id=t.id and e.entry_type in('installation_payout','installation_refund')) paid_expenses,
   round(coalesce((select sum(r.amount) from receipts r where r.id=t.id and r.kind='system' or r.system_invoice_id=t.id and r.kind='system_payment'),0),2) collected,
   round(t.total-t.cost-coalesce(t.expenses,0)-coalesce(t.installation_expenses,0),2) provisional_profit
  from eligible t
 ), unallocated as materialized(
  select l.customer_id,coalesce(c.name,'عميل غير محدد') name,round(sum(r.amount),2) amount,count(*) receipt_count
  from receipts r join solar_private.customer_movement_links() l on l.transaction_id=r.id left join public.customers c on c.id=l.customer_id
  where r.kind='system_payment' and r.system_invoice_id is null
   and(case when p.is_admin then pending_systems.owner_id is null or r.created_by=pending_systems.owner_id else r.created_by=p.id end) and exists(select 1 from eligible t where t.customer_id=l.customer_id)
  group by l.customer_id,c.name
 )
 select jsonb_build_object('asOf',statement_timestamp(),'scope',case when p.is_admin and pending_systems.owner_id is null then 'company' else 'own' end,
  'from',date_from,'to',date_to,'summary',jsonb_build_object('count',(select count(*) from invoice_rows),
   'invoiceTotal',(select coalesce(sum(total),0) from invoice_rows),'collected',(select coalesce(sum(collected),0) from invoice_rows),
   'provisionalProfit',(select coalesce(sum(provisional_profit),0) from invoice_rows),'paidExpenses',(select coalesce(sum(paid_expenses),0) from invoice_rows),
   'unallocatedCollections',(select coalesce(sum(amount),0) from unallocated),'unallocatedCustomers',(select count(*) from unallocated)),
  'rows',coalesce((select jsonb_agg(jsonb_build_object('id',id,'receiptNo',receipt_no,'customer',party_name,'date',created_at,'status',installation_status,
   'creatorId',created_by,'creatorName',creator_name,'total',total,'materialCost',cost,'invoiceExpenses',invoice_expenses,'approvedExpenses',approved_expenses,
   'paidExpenses',paid_expenses,'collected',collected,'provisionalProfit',provisional_profit) order by created_at,id) from invoice_rows),'[]'),
  'unallocated',coalesce((select jsonb_agg(jsonb_build_object('customerId',customer_id,'customer',name,'amount',amount,'receiptCount',receipt_count) order by name,customer_id) from unallocated),'[]')) into result;
 return result;
end$$;
create function public.solar_pending_systems(owner_id uuid default null,date_from date default null,date_to date default null) returns jsonb
language sql stable security invoker set search_path='' as $$select solar_private.pending_systems(owner_id,date_from,date_to)$$;
revoke all on function solar_private.pending_systems(uuid,date,date),public.solar_pending_systems(uuid,date,date) from public,anon;
grant execute on function solar_private.pending_systems(uuid,date,date),public.solar_pending_systems(uuid,date,date) to authenticated;
notify pgrst,'reload schema';
