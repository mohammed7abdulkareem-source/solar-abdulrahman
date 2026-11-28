-- The existing "balance" follows the selected report scope. Keep the running
-- balance of each individual cashbox as well, before cutting a page or applying
-- a text, direction or date filter. A NULL owner is the in-transit ledger.
do $migration$
declare
 edit record;
 definition text;
begin
 for edit in select * from (values
  ('solar_private.cash_workspace(jsonb)',
   $old$sum(delta) over(partition by currency order by created_at,id rows unbounded preceding) balance from scoped m$old$,
   $new$sum(delta) over(partition by currency order by created_at,id rows unbounded preceding) balance,
    sum(delta) over(partition by owner_id,currency order by created_at,id rows unbounded preceding) as "ownerBalance"
   from scoped m$new$),
  -- Use the recorded outcome of a reconciliation, just as the movement detail
  -- does. Older reconciliations can share their timestamp with another entry.
  ('solar_private.cash_workspace(jsonb)',
   $old$'reconciliation',case when x.kind='cash_reconcile' then solar_private.cash_reconciliation_info(x.request_id,x.owner_id) end$old$,
   $new$'ownerBalance',coalesce((rec.info->>('after'||x.currency))::numeric,x."ownerBalance"),'reconciliation',rec.info$new$),
  ('solar_private.cash_workspace(jsonb)',
   $old$from page x left join public.profiles o on o.id=x.owner_id$old$,
   $new$from page x left join public.profiles o on o.id=x.owner_id
   left join lateral (select case when x.kind='cash_reconcile' then solar_private.cash_reconciliation_info(x.request_id,x.owner_id) end as info offset 0) rec on true$new$),
  ('solar_private.cash_movement_detail_v386(text)',
   $old$balance_after:=(reconciliation->>('after'||m.currency))::numeric;$old$,
   $new$balance_after:=coalesce((reconciliation->>('after'||m.currency))::numeric,balance_after);$new$),
  ('solar_private.cash_movement_detail_v386(text)',
   $old$'before',balance_after-m.delta,'after',balance_after$old$,
   $new$'before',balance_after-m.delta,'after',balance_after,'ownerBalance',balance_after$new$),
  ('solar_private.cash_read_projection(jsonb)',
   $old$'balance','amount','before','after'$old$,
   $new$'balance','amount','before','after','ownerBalance'$new$)
 ) as changes(signature,previous,replacement)
 loop
  definition:=pg_get_functiondef(edit.signature::regprocedure);
  if strpos(definition,edit.previous)=0 then
   raise exception 'Review cash movement balance in %',edit.signature;
  end if;
  execute replace(definition,edit.previous,edit.replacement);
 end loop;
end $migration$;

-- Called only for ledger rows in a cash workspace/statement the actor can read.
-- Normal handovers link to their request via the cash entry, even on old rows
-- whose note just says the receiver was a finance officer. Direct handovers
-- store the participants' names at posting. Their actor may be a third person.
create function solar_private.cash_transfer_parties(movement_id text, movement_kind text, finance_request_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='' as $function$
declare parties jsonb;
begin
 if movement_kind in ('transfer_in','transfer_out','transfer_transit','transfer_refund','handover_expense')
    and movement_id like 'entry:%' then
  select jsonb_build_object(
   'sender',solar_private.user_name(sender.display_name,sender.username,sender.honorific),
   'recipient',solar_private.user_name(recipient.display_name,recipient.username,recipient.honorific),
   'decidedBy',solar_private.user_name(decider.display_name,decider.username,decider.honorific),
   'status',handover.status)
  into parties from public.solar_cash_entries entry
  join solar_private.cash_transfers handover on handover.id=entry.transfer_id
  left join public.profiles sender on sender.id=handover.sender_id
  left join public.profiles recipient on recipient.id=handover.recipient_id
  left join public.profiles decider on decider.id=handover.decided_by
  where entry.id=substr(movement_id,7)::uuid;
 elsif movement_kind in ('admin_transfer_in','admin_transfer_out') and finance_request_id is not null then
  select jsonb_build_object(
   'sender',request.response->>'senderName','recipient',request.response->>'recipientName',
   'decidedBy',request.response->>'actorName','status','accepted')
  into parties from solar_private.finance_requests request
  where request.request_id=finance_request_id and request.action='admin_cash_transfer';
 end if;
 return parties;
end
$function$;
revoke all on function solar_private.cash_transfer_parties(text,text,uuid) from public,anon,authenticated;

-- Resolve parties inside the visible row scope. Filtering by name follows the
-- same private-receipt projection as filtering by note or receipt number.
do $migration$
declare definition text; anchor text; replacement text;
begin
 definition:=pg_get_functiondef('solar_private.cash_workspace(jsonb)'::regprocedure);
 anchor:='filtered as(select m.* from ranked m where m.created_at>=start_at';
 replacement:='named as(select m.*,solar_private.cash_transfer_parties(m.id,m.kind,m.request_id) as transfer from ranked m),
 filtered as(select m.* from named m where m.created_at>=start_at';
 if strpos(definition,anchor)=0 then raise exception 'Review current workspace movement scope';end if;
 definition:=replace(definition,anchor,replacement);
 anchor:=$sql$else m.party||' '||m.note||' '||coalesce(m.receipt_no::text,'') end$sql$;
 replacement:=$sql$else concat_ws(' ',m.party,m.note,m.receipt_no::text,m.transfer->>'sender',m.transfer->>'recipient',m.transfer->>'decidedBy') end$sql$;
 if strpos(definition,anchor)=0 then raise exception 'Review current workspace search scope';end if;
 execute replace(definition,anchor,replacement);

 definition:=pg_get_functiondef('solar_private.cash_statement(uuid,date,date,text)'::regprocedure);
 anchor:='solar_private.cash_read_projection(to_jsonb(r))';
 replacement:=$sql$solar_private.cash_read_projection(to_jsonb(r)||jsonb_build_object('transfer',solar_private.cash_transfer_parties(r.id,r.kind,r.request_id)))$sql$;
 if strpos(definition,anchor)=0 then raise exception 'Review current statement row projection';end if;
 execute replace(definition,anchor,replacement);
end
$migration$;
