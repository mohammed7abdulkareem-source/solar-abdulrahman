-- Both clients use the same capital calculation and authorization gate. The
-- balance-only variant aggregates the cash ledger before attaching owner names.
do $migration$
declare definition text; needle text; start_at integer; end_at integer; old_cash text;
begin
 definition:=pg_get_functiondef('solar_private.capital_snapshot()'::regprocedure);
 needle:='FUNCTION solar_private.capital_snapshot()';
 if strpos(definition,needle)=0 then raise exception 'Missing capital snapshot signature';end if;
 definition:=replace(definition,needle,'FUNCTION solar_private.capital_snapshot(current_cash boolean)');

 start_at:=strpos(definition,E' with movements as (\n  select m.*');
 needle:=' into iqd,usd,usd_book,flows,cash_rows from movements;';
 end_at:=strpos(definition,needle)+length(needle);
 if start_at<1 or end_at<=start_at then raise exception 'Missing capital cash ledger calculation';end if;
 old_cash:=substr(definition,start_at,end_at-start_at);
 definition:=replace(definition,old_cash,$cash$
 if current_cash then
  with scoped as (
   select m.owner_id, m.currency, m.delta, m.book_delta, m.kind,
    case when m.owner_id is not null then 'owner'
         when m.kind='transfer_transit' then 'transit' else 'unassigned' end allocation_kind
   from solar_private.cash_movements() m where company or m.owner_id=p.id
  ), allocations as (
   select owner_id,allocation_kind,
    coalesce(sum(delta) filter(where currency='IQD'),0) iqd_amount,
    coalesce(sum(delta) filter(where currency='USD'),0) usd_amount,
    coalesce(sum(book_delta) filter(where currency='USD'),0) usd_book_amount,
    coalesce(sum(case when currency='IQD' then delta else book_delta end)
     filter(where kind in ('capital_deposit','capital_withdraw','deposit','withdraw')),0) capital_flow
   from scoped group by owner_id,allocation_kind
  ), named as (
   select a.*,case a.allocation_kind when 'transit' then 'قيد الاستلام' when 'unassigned' then 'قاصة غير محددة'
    else coalesce(solar_private.user_name(u.display_name,u.username,u.honorific),'قاصة غير محددة') end owner_name
   from allocations a left join public.profiles u on u.id=a.owner_id
  )
  select coalesce(sum(iqd_amount),0),coalesce(sum(usd_amount),0),coalesce(sum(usd_book_amount),0),coalesce(sum(capital_flow),0),
   jsonb_build_object('allocations',coalesce(jsonb_agg(jsonb_build_object(
    'kind',allocation_kind,'ownerId',owner_id,'ownerName',owner_name,'iqd',iqd_amount,'usd',usd_amount,'usdBook',usd_book_amount)
    order by case allocation_kind when 'owner' then 0 when 'transit' then 1 else 2 end,owner_name,owner_id)
    filter(where iqd_amount<>0 or usd_amount<>0 or usd_book_amount<>0),'[]'::jsonb))
  into iqd,usd,usd_book,flows,cash_rows from named;

  -- A handover is denominated in IQD and reserved from the sender on posting.
  -- Show open requests to the two parties or company admin without adding
  -- their amounts to the balances, which already include posted transit.
  select cash_rows||jsonb_build_object('pendingHandovers',coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'createdAt',t.created_at,'amount',t.amount,'currency','IQD',
    'senderId',t.sender_id,'senderName',coalesce(solar_private.user_name(s.display_name,s.username,s.honorific),'مستخدم'),
    'recipientId',t.recipient_id,'recipientName',coalesce(solar_private.user_name(r.display_name,r.username,r.honorific),'مستخدم'))
    order by t.created_at desc,t.id),'[]'::jsonb))
  into cash_rows from solar_private.cash_transfers t
  join public.profiles s on s.id=t.sender_id join public.profiles r on r.id=t.recipient_id
  where t.status='pending' and (company or p.id in(t.sender_id,t.recipient_id));
 else
$cash$||old_cash||E'\n end if;');

 needle:='''usdBook'',round(usd_book,2),''rows'',cash_rows)';
 if strpos(definition,needle)=0 then raise exception 'Missing capital cash response';end if;
 definition:=replace(definition,needle,$result$'usdBook',round(usd_book,2))||case when current_cash then cash_rows else jsonb_build_object('rows',cash_rows) end$result$);
 execute definition;
end$migration$;
revoke all on function solar_private.capital_snapshot(boolean) from public,anon;
grant execute on function solar_private.capital_snapshot(boolean) to authenticated;

-- Preserve the public and private no-argument signatures for installed clients.
create or replace function solar_private.capital_snapshot() returns jsonb
language sql stable security invoker set search_path='' as $$select solar_private.capital_snapshot(false)$$;
create function public.solar_capital_current_snapshot() returns jsonb
language sql stable security invoker set search_path='' as $$select solar_private.capital_snapshot(true)$$;
revoke all on function public.solar_capital_current_snapshot() from public,anon;
grant execute on function public.solar_capital_current_snapshot() to authenticated;
notify pgrst,'reload schema';
