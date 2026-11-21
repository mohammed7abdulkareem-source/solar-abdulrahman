-- Installation follow-up belongs to the selected receipt's custodian. The
-- sales author, assigned engineer, actual cash payers and settlement attribution
-- remain on their original records.
do $migration$
declare original text; definition text;
begin
 original:=pg_get_functiondef('solar_private.installation_action(bigint,bigint,text,jsonb)'::regprocedure);
 definition:=replace(original,'solar_private.can_close_installation(j.created_by)',
   'solar_private.can_close_installation(solar_private.receipt_responsible(j.id,j.created_by))');
 if definition=original then raise exception 'Unexpected installation action authorization';end if;
 execute definition;
 original:=pg_get_functiondef('solar_private.invoice_save(uuid,jsonb)'::regprocedure);
 definition:=replace(original,'solar_private.can_close_installation(before_row.created_by)',
  'solar_private.can_close_installation(solar_private.receipt_responsible(before_row.id,before_row.created_by))');
 if definition=original then raise exception 'Unexpected invoice expense authorization';end if;
 execute definition;

 original:=pg_get_functiondef('solar_private.installation_jobs()'::regprocedure);
 definition:=replace(original,
 $find$from public.transactions t where t.kind='system'$find$,
 $put$from public.transactions t
 left join solar_private.customer_receipt_responsibility custody on custody.transaction_id=t.id
 left join public.profiles manager on manager.id=coalesce(custody.owner_id,t.created_by)
 where t.kind='system'$put$);
 if definition=original then raise exception 'Unexpected installation job source';end if;
 definition:=replace(definition,'solar_private.can_close_installation(t.created_by)',
  'solar_private.can_close_installation(coalesce(custody.owner_id,t.created_by))');
 definition:=replace(definition,'p.is_admin or t.created_by=p.id','p.is_admin or coalesce(custody.owner_id,t.created_by)=p.id');
 definition:=replace(definition,$find$'creatorId',t.created_by,$find$,
  $put$'responsibleId',manager.id,'responsibleName',solar_private.user_name(manager.display_name,manager.username,manager.honorific),'responsiblePhone',manager.phone,'creatorId',t.created_by,$put$);
 if strpos(definition,'''responsibleId'',manager.id')=0 or strpos(definition,'t.created_by=p.id')>0 or
  strpos(definition,'can_close_installation(t.created_by)')>0 then raise exception 'Unexpected installation scope';end if;
 execute definition;

 original:=pg_get_functiondef('solar_private.installation_schedule(date,date,uuid,bigint)'::regprocedure);
 definition:=replace(original,'p.is_admin or excluded.created_by=p.id',
  'p.is_admin or solar_private.receipt_responsible(excluded.id,excluded.created_by)=p.id');
 definition:=replace(definition,$find$from public.transactions t where t.kind='system'$find$,
 $put$from public.transactions t
 left join solar_private.customer_receipt_responsibility custody on custody.transaction_id=t.id
 left join public.profiles manager on manager.id=coalesce(custody.owner_id,t.created_by)
 where t.kind='system'$put$);
 definition:=replace(definition,'p.is_admin or t.created_by=p.id','p.is_admin or coalesce(custody.owner_id,t.created_by)=p.id');
 definition:=replace(definition,$find$'creatorName',(select solar_private.user_name(c.display_name,c.username,c.honorific)$find$,
  $put$'responsibleName',solar_private.user_name(manager.display_name,manager.username,manager.honorific),'creatorName',(select solar_private.user_name(c.display_name,c.username,c.honorific)$put$);
 if strpos(definition,'excluded.created_by=p.id')>0 or strpos(definition,'t.created_by=p.id')>0 or
   strpos(definition,'''responsibleName'',solar_private.user_name(manager.')=0 then raise exception 'Unexpected schedule scope';end if;
 execute definition;

 -- An installation notification links to the active file manager, respecting
 -- the same module permission as the installations screen.
 original:=pg_get_functiondef('solar_private.notification_recipient_allowed(uuid,bigint)'::regprocedure);
 definition:=replace(original,'and t.created_by=p.id)',
  $put$and (t.created_by=p.id or (t.kind='system' and (p.permissions->>'installations'='true' or p.permissions->>'system'='true')
      and exists(select 1 from solar_private.customer_receipt_responsibility h where h.transaction_id=t.id and h.owner_id=p.id))))$put$);
 if definition=original then raise exception 'Unexpected notification recipient scope';end if;
 execute definition;

 original:=pg_get_functiondef('solar_private.installation_sync_notice()'::regprocedure);
 definition:=replace(original,'installation_update_notice(new.created_by,new)',
     'installation_update_notice(solar_private.receipt_responsible(new.id,new.created_by),new)');
 if definition=original then raise exception 'Unexpected installation notice routing';end if;
 execute definition;

 original:=pg_get_functiondef('solar_private.warehouse_notify()'::regprocedure);
 definition:=replace(original,$find$id=new.created_by or(new.kind='system' and is_admin)$find$,
   $put$id=case when new.kind='system' then solar_private.receipt_responsible(new.id,new.created_by) else new.created_by end or(new.kind='system' and is_admin)$put$);
 definition:=replace(definition,$find$warehouse_notice(new.created_by,new.id,'installation_closed')$find$,
   $put$warehouse_notice(solar_private.receipt_responsible(new.id,new.created_by),new.id,'installation_closed')$put$);
 if definition=original then raise exception 'Unexpected warehouse completion notice routing';end if;
 execute definition;
end
$migration$;
