-- Read pending transfers and available cash from the same workspace snapshot.
-- This is an additive projection: no balances, receipts, or pending rows change.
do $migration$
declare definition text; old_text text; new_text text; signature text; expected_hash text;
begin
 for signature,expected_hash in select key,value from jsonb_each_text('{
  "solar_private.cash_workspace(jsonb)":"6b39680f0913f98e7449c54358ae9f27",
  "solar_private.cash_transfer_overview()":"edfd2d7dbcccd383ee00a24df9a4074b",
  "solar_private.cash_transfer_send(uuid,uuid,numeric,numeric,text,text)":"ee109ee3665504aa58c3440e777f7cfd"
 }'::jsonb) loop
  if md5(pg_get_functiondef(signature::regprocedure))<>expected_hash then
   raise exception 'Review current % definition before applying V4.1.8',signature;
  end if;
 end loop;

 definition:=pg_get_functiondef('solar_private.cash_workspace(jsonb)'::regprocedure);
 old_text:=$old$with movements as materialized($old$;
 new_text:=$new$with pending_transfers as materialized(
  select t.* from solar_private.cash_transfers t
  where t.status='pending' and(p.is_admin or t.sender_id=p.id or t.recipient_id=p.id)
   and(uid is null or t.sender_id=uid or t.recipient_id=uid)
 ), movements as materialized($new$;
 if strpos(definition,old_text)=0 then raise exception 'Review cash workspace snapshot anchor';end if;
 definition:=replace(definition,old_text,new_text);

 old_text:=$old$select jsonb_build_object('rows',$old$;
 new_text:=$new$select jsonb_build_object('pendingTransfers',(
  select coalesce(jsonb_agg(jsonb_build_object(
   'id',t.id,'sender_id',t.sender_id,'recipient_id',t.recipient_id,
   'senderName',coalesce(solar_private.user_name(sender.display_name,sender.username,sender.honorific),'مستخدم'),
   'recipientName',coalesce(solar_private.user_name(recipient.display_name,recipient.username,recipient.honorific),'مستخدم'),
   'amount',t.amount,'currency','IQD','created_at',t.created_at,'status',t.status
  )order by t.created_at desc,t.id desc),'[]'::jsonb)
  from pending_transfers t left join public.profiles sender on sender.id=t.sender_id
   left join public.profiles recipient on recipient.id=t.recipient_id
 ),'rows',$new$;
 if strpos(definition,old_text)=0 then raise exception 'Review cash workspace response anchor';end if;
 definition:=replace(definition,old_text,new_text);

 old_text:=$old$'summary',jsonb_build_object(
 'IQD',$old$;
 new_text:=$new$'summary',jsonb_build_object(
 'pendingIQD',(select coalesce(sum(amount),0)from pending_transfers),
 'pendingCount',(select count(*)from pending_transfers),
 'availableIQD',(select coalesce(sum(delta),0)from scoped where currency='IQD' and owner_id is not null),
 'availableUSD',(select coalesce(sum(delta),0)from scoped where currency='USD' and owner_id is not null),
 'IQD',$new$;
 if strpos(definition,old_text)=0 then raise exception 'Review cash workspace summary anchor';end if;
 definition:=replace(definition,old_text,new_text);

 -- Keep the existing authorized directory for selectors. Administrators also
 -- need funded inactive/operational owners visible so its totals reconcile.
 -- These flags describe eligibility; posting authorization remains unchanged.
 old_text:=$old$'id',o.id,'name',coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'مستخدم'),'IQD'$old$;
 new_text:=$new$'id',o.id,'name',coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'مستخدم'),'active',o.active,'userType',o.user_type,'IQD'$new$;
 if strpos(definition,old_text)=0 then raise exception 'Review cash owner metadata anchor';end if;
 definition:=replace(definition,old_text,new_text);
 old_text:=$old$where o.active and o.user_type not in ('installer','warehouse') and(p.is_admin or o.id=p.id)$old$;
 new_text:=$new$where ((o.active and o.user_type not in ('installer','warehouse')) or(p.is_admin and(coalesce(totals.iqd,0)<>0 or coalesce(totals.usd,0)<>0))) and(p.is_admin or o.id=p.id)$new$;
 if strpos(definition,old_text)=0 then raise exception 'Review cash owner visibility anchor';end if;
 execute replace(definition,old_text,new_text);

 -- A dedicated warehouse/installer account cannot accept a cash transfer.
 -- Stop selecting or sending new requests to those recipients; historical
 -- requests remain visible and the original sender can still cancel them.
 foreach signature in array array['solar_private.cash_transfer_overview()','solar_private.cash_transfer_send(uuid,uuid,numeric,numeric,text,text)'] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  old_text:=$old$u.user_type<>'installer'$old$;
  new_text:=$new$u.user_type not in('installer','warehouse')$new$;
  if strpos(definition,old_text)=0 then raise exception 'Review eligible recipient anchor for %',signature;end if;
  execute replace(definition,old_text,new_text);
 end loop;
end $migration$;

notify pgrst, 'reload schema';
