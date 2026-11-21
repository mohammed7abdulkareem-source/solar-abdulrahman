-- A statement rename shares the customer writer's authorization, lock, token,
-- request history and duplicate guard. The payload contains no accounting fields.
do $migration$
declare definition text;
begin
 definition := pg_get_functiondef('solar_private.customer_save(text,uuid,jsonb)'::regprocedure);
 if md5(definition) <> '0fd7b1f563e44bce159d6dc57b39d0ed' then
  raise exception 'Review the current customer writer before adding statement renames';
 end if;
 definition := replace(definition, 'action not in (''create'',''update'',''delete'')',
  'action not in (''create'',''update'',''delete'',''rename'')');
 definition := replace(definition, '  return prior.result;', $step$
  if action='rename' and not exists (
   select 1 from public.customers x where x.id=prior.customer_id and (p.is_admin or x.owner_id=p.id)
  ) then raise exception 'لا تملك صلاحية هذا الزبون' using errcode='42501'; end if;
  return prior.result;$step$);
 definition := replace(definition, '  rows:=before_record->''rows'';', $step$
  if action='rename' then
   new_name:=regexp_replace(btrim(payload->>'name'),'[[:space:]]+',' ','g');
   if length(solar_private.customer_name_key(new_name))<2 or length(new_name)>150 then
    raise exception 'اكتب اسم العميل كاملاً بحد أقصى 150 حرفاً';
   end if;
   if solar_private.customer_name_key(new_name)<>solar_private.customer_name_key(c.name) then
    -- Prevent a rename from claiming orphaned receipts at the new name or
    -- assigning ambiguous old receipts to a different customer.
    if exists (
     select 1 from public.transactions t
     join solar_private.customer_movement_links() l on l.transaction_id=t.id
     where t.party_id is null and (
      (l.reason='unknown_name' and solar_private.customer_name_key(t.party_name)=solar_private.customer_name_key(new_name))
      or (l.reason='ambiguous_name' and solar_private.customer_name_key(t.party_name)=solar_private.customer_name_key(c.name)
          and (select count(*) from public.customers x where solar_private.customer_name_key(x.name)=solar_private.customer_name_key(c.name))=2)
     )
    ) then
     raise exception 'توجد وصولات قديمة غير مرتبطة بحساب محدد لهذا الاسم. راجع ربطها قبل تعديل الاسم.';
    end if;
    -- Only legacy rows resolved by name need an ID. Existing receipts already
    -- linked by ID keep their original document text, dates and revisions.
    update public.transactions t set party_id=c.id
     where t.party_id is null and t.id in (
      select l.transaction_id from solar_private.customer_movement_links() l where l.customer_id=c.id
     );
   end if;
   if c.name is distinct from new_name then update public.customers set name=new_name where id=c.id; end if;
   select jsonb_build_object('id',x.id,'name',x.name) into result from public.customers x where x.id=c.id;
   insert into solar_private.customer_changes(request_id,actor_id,action,customer_id,payload,before_customer,after_customer,before_opening,after_opening,result)
   values(request_id,p.id,action,c.id,payload,jsonb_build_object('id',c.id,'name',c.name),result,before_opening,before_opening,result);
   return result;
  end if;
  rows:=before_record->'rows';$step$);
 execute definition;

 -- Imported customers can have NULL phone numbers. An update that changes
 -- only the name must not additionally convert that existing value to ''.
 definition:=pg_get_functiondef('solar_private.customer_guard()'::regprocedure);
 if md5(definition)<>'6ca54dd6db4ac25797f90d14f48db76f' then
  raise exception 'Review the customer validation trigger before preserving stored phones';
 end if;
 execute replace(definition, $old$new.phone:=trim(coalesce(new.phone,''));$old$,
  $new$if tg_op='INSERT' or new.phone is distinct from old.phone then new.phone:=trim(coalesce(new.phone,''));end if;$new$);
end $migration$;
