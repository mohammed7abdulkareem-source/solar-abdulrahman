-- A cached receipt can contain an account context. Before returning that
-- context, recheck the customer's current owner under the financial write lock.
do $$
declare
 definition text;
 previous text;
 replay_guard text := $guard$if not p.is_admin and not exists (
   select 1 from public.customers owner_row where owner_row.id=(payload->>'customerId')::bigint and owner_row.owner_id=p.id
  ) then raise exception 'هذا العميل لم يعد ضمن حساباتك. حدّث قائمة العملاء.' using errcode='42501'; end if; $guard$;
begin
 definition:=pg_get_functiondef('solar_private.customer_payment_save(uuid,jsonb)'::regprocedure);
 previous:='if prior.actor_id=p.id and prior.action=''customer_payment'' and prior.payload=payload then ';
 if strpos(definition,previous)=0 then raise exception 'Review wholesale payment replay';end if;
 execute replace(definition,previous,previous||replay_guard);

 definition:=pg_get_functiondef('solar_private.system_payment_save_v411(uuid,jsonb)'::regprocedure);
 previous:='if prior.actor_id=p.id and prior.payload=payload then';
 if strpos(definition,previous)=0 then raise exception 'Review system payment replay';end if;
 execute replace(definition,previous,previous||chr(10)||'   '||replay_guard);

 definition:=pg_get_functiondef('solar_private.customer_payment_manage(text,uuid,jsonb)'::regprocedure);
 previous:='if prior.actor_id=p.id and prior.action=''customer_payment_''||action and prior.payload=payload then return solar_private.customer_payment_ack_read_projection(prior.response);end if;';
 if strpos(definition,previous)=0 then raise exception 'Review wholesale payment correction replay';end if;
 execute replace(definition,previous,$replacement$if prior.actor_id=p.id and prior.action='customer_payment_'||action and prior.payload=payload then
    if not p.is_admin and not exists (
     select 1 from solar_private.customer_movement_links() l join public.customers owner_row on owner_row.id=l.customer_id
     where l.transaction_id=(payload->>'id')::bigint and owner_row.owner_id=p.id
    ) then raise exception 'هذا العميل لم يعد ضمن حساباتك. حدّث قائمة العملاء.' using errcode='42501'; end if;
    return solar_private.customer_payment_ack_read_projection(prior.response);
   end if;$replacement$);
end $$;
