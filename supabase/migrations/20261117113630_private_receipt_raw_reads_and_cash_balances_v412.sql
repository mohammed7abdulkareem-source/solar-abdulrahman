-- V4.1.2: close raw-table read paths around the receipt projections.
-- SELECT policies only: preserve existing write guards and every financial row.
do $$begin
 if md5(pg_get_functiondef('solar_private.customer_payment_manage(text,uuid,jsonb)'::regprocedure))is distinct from'ebfbec8be74113ca3f8c609d094812b4'
 or md5(pg_get_functiondef('solar_private.supplier_payment_get(bigint)'::regprocedure))is distinct from'6c596d44a62be8b8c83984954ab35064'
 or md5(pg_get_functiondef('solar_private.fx(text,uuid,jsonb)'::regprocedure))is distinct from'6deddd286b0a62fd41358ca380667810'
 or md5(pg_get_functiondef('solar_private.supplier_payment_manage(text,uuid,jsonb)'::regprocedure))is distinct from'2aeea5ca66c7d82223ba58226d140b47'
 or md5(pg_get_functiondef('solar_private.cash_movements()'::regprocedure))is distinct from'2bea4150fbbf10829a5f037ecc9352f8'
 then raise exception 'Unexpected private receipt read baseline';end if;
 if not exists(select 1 from pg_policy where polrelid='public.transactions'::regclass and polname='solar_invoice_creator_scope'and not polpermissive and polcmd='*'and md5(pg_get_expr(polqual,polrelid))='20955988dbc0f261af207246e74ff493')
 or not exists(select 1 from pg_policy where polrelid='public.solar_cash_entries'::regclass and polname='own_cash_entries'and polpermissive and polcmd='r'and md5(pg_get_expr(polqual,polrelid))='fc0bc23678dbdaa41262281945304485')
 then raise exception 'Unexpected receipt/cash-entry read policies';end if;
end$$;

create policy solar_payment_creator_read on public.transactions as restrictive for select to authenticated
using((select solar_private.role_name())='admin' or kind not in('customer_payment','system_payment','supplier_payment') or created_by=(select auth.uid()));

-- A row-bound boolean is the only policy helper callable by authenticated.
-- It cannot reveal a foreign entry or arbitrary invoice contents, and it checks
-- the same owner's entry before examining live/deleted invoice ownership.
create function solar_private.cash_entry_invoice_read_allowed(entry_id uuid)returns boolean
language plpgsql stable security definer set search_path=''as $$
declare entry public.solar_cash_entries;begin
 if solar_private.can_access_invoice(null,false)then return true;end if;
 if not exists(select 1 from public.profiles p where p.id=auth.uid()and p.active and p.user_type not in('warehouse','installer'))then return false;end if;
 select * into entry from public.solar_cash_entries e where e.id=entry_id and e.owner_id=auth.uid();
 if not found then return false;end if;
 return(entry.job_id is null or solar_private.invoice_read_allowed(entry.job_id))
  and(entry.deleted_job_id is null or solar_private.invoice_read_allowed(entry.deleted_job_id));
end$$;
revoke all on function solar_private.cash_entry_invoice_read_allowed(uuid)from public,anon;
grant execute on function solar_private.cash_entry_invoice_read_allowed(uuid)to authenticated;
create policy solar_cash_entry_invoice_read on public.solar_cash_entries as restrictive for select to authenticated
using((select solar_private.role_name())='admin' or(job_id is null and deleted_job_id is null)or solar_private.cash_entry_invoice_read_allowed(id));

-- Expose balance totals without restoring access to hidden financial documents.
-- Use the existing Cash Workspace source exactly, including USD book values,
-- inactive cash owners and unassigned/transit effects in an administrator total.
create function solar_private.cash_read_balances()returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare actor public.profiles;result jsonb;begin
 select * into actor from public.profiles where id=auth.uid()and active and user_type not in('warehouse','installer');
 if actor.id is null then raise exception 'لا تملك صلاحية قراءة أرصدة القاصة'using errcode='42501';end if;
 with movements as materialized(select m.* from solar_private.cash_movements()m where actor.is_admin or m.owner_id=actor.id),
 owners as(select p.id from public.profiles p where(actor.is_admin or p.id=actor.id)and p.user_type not in('warehouse','installer')
  union select m.owner_id from movements m),
 totals as(select o.id,coalesce(sum(m.delta)filter(where m.currency='IQD'),0)iqd,
  coalesce(sum(m.delta)filter(where m.currency='USD'),0)usd,coalesce(sum(m.book_delta)filter(where m.currency='USD'),0)usd_book
  from owners o left join movements m on m.owner_id is not distinct from o.id group by o.id)
 select jsonb_build_object('asOf',statement_timestamp(),'ownerId',case when actor.is_admin then null else actor.id end,
  'summary',jsonb_build_object('IQD',coalesce(sum(iqd),0),'USD',coalesce(sum(usd),0),'usdBook',coalesce(sum(usd_book),0)),
  'owners',coalesce(jsonb_agg(jsonb_build_object('id',id,'IQD',iqd,'USD',usd,'usdBook',usd_book)order by id),'[]'))into result from totals;
 return result;
end$$;
revoke all on function solar_private.cash_read_balances()from public,anon;
grant execute on function solar_private.cash_read_balances()to authenticated;
create function public.solar_cash_read_balances()returns jsonb
language sql stable security invoker set search_path=''as $$select solar_private.cash_read_balances()$$;
revoke all on function public.solar_cash_read_balances()from public,anon;
grant execute on function public.solar_cash_read_balances()to authenticated;

-- Known uncertain customer-payment retries remain acknowledgements of the
-- original operation. Project only their outward copies if the receipt belongs
-- to another creator; do not rewrite cached data, tokens or operation effects.
create function solar_private.customer_payment_ack_read_projection(result jsonb)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare safe jsonb;begin
 if result is null or solar_private.invoice_read_allowed((result->>'id')::bigint)then return result;end if;
 select coalesce(jsonb_object_agg(k,v),'{}')into safe from jsonb_each(result)x(k,v)
 where k=any(array['total','oldBalance','remaining','cashBefore','cashAfter','action']);
 return safe||jsonb_build_object('id',null,'receiptNo',null,'party','','receiptRestricted',true);
end$$;
revoke all on function solar_private.customer_payment_ack_read_projection(jsonb)from public,anon,authenticated;

create function solar_private.supplier_payment_ack_read_projection(result jsonb)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare safe jsonb;account jsonb;begin
 if result is null or solar_private.invoice_read_allowed((result->>'id')::bigint)then return result;end if;
 select coalesce(jsonb_object_agg(k,v),'{}')into safe from jsonb_each(result)x(k,v)
 where k=any(array['total','amount','cash','mode','date','token','sourceCurrency','sourceSubtotal','exchangeRate','marketRate','accountCurrency','accountAmount','accountRevision','cashCurrency','cashAmount','fxAccounted','action','notesOnly','balance','cashBalance']);
 if jsonb_typeof(result->'accountContext')='object'then
  select coalesce(jsonb_object_agg(k,v),'{}')into account from jsonb_each(result->'accountContext')x(k,v)
  where k=any(array['currency','revision','balance','bookBalance','token','cashBalance','usdWallet']);
  safe:=safe||jsonb_build_object('accountContext',account);
 end if;
 return safe||jsonb_build_object('id',null,'receiptNo',null,'party','','replacement',null,'receiptRestricted',true);
end$$;
revoke all on function solar_private.supplier_payment_ack_read_projection(jsonb)from public,anon,authenticated;

do $$declare definition text;begin
 definition:=pg_get_functiondef('solar_private.supplier_payment_get(bigint)'::regprocedure);
 if strpos(definition,' return jsonb_build_object(''id'',t.id,')=0 then raise exception 'Unexpected supplier payment return';end if;
 definition:=replace(definition,' return jsonb_build_object(''id'',t.id,',' if not solar_private.invoice_read_allowed(t.id)then raise exception ''الوصل غير متاح ضمن صلاحياتك''using errcode=''42501'';end if;
 return jsonb_build_object(''id'',t.id,');
 execute definition;
 definition:=pg_get_functiondef('solar_private.customer_payment_manage(text,uuid,jsonb)'::regprocedure);
 if strpos(definition,'then return prior.response;end if;')=0 or strpos(definition,' return result;')=0 then raise exception 'Unexpected customer payment acknowledgement';end if;
 definition:=replace(definition,'then return prior.response;end if;','then return solar_private.customer_payment_ack_read_projection(prior.response);end if;');
 definition:=replace(definition,' return result;',' return solar_private.customer_payment_ack_read_projection(result);');
 execute definition;
 definition:=pg_get_functiondef('solar_private.fx(text,uuid,jsonb)'::regprocedure);
 if strpos(definition,'return prior.response;end if;')=0 then raise exception 'Unexpected FX payment retry';end if;
 execute replace(definition,'return prior.response;end if;','if action=''payment''then return solar_private.supplier_payment_ack_read_projection(prior.response);end if;return prior.response;end if;');
 definition:=pg_get_functiondef('solar_private.supplier_payment_manage(text,uuid,jsonb)'::regprocedure);
 if strpos(definition,'and(actor.is_admin or coalesce(tx.cashbox_user_id,tx.created_by)=actor.id)')=0
  or strpos(definition,' if action=''get'' then return jsonb_build_object(')=0
  or strpos(definition,'then return prior.response;end if;')=0
  or strpos(definition,' return result;')=0 then raise exception 'Unexpected supplier management read boundary';end if;
 definition:=replace(definition,'and(actor.is_admin or coalesce(tx.cashbox_user_id,tx.created_by)=actor.id)',
  'and(actor.is_admin or coalesce(tx.cashbox_user_id,tx.created_by)=actor.id)and(actor.is_admin or tx.created_by=actor.id)');
 -- Reject a foreign get before accounting-specific validation can disclose data.
 definition:=replace(definition,' uid:=coalesce(t.cashbox_user_id,t.created_by);',
  ' if action=''get''and not solar_private.invoice_read_allowed(t.id)then raise exception ''الوصل غير متاح ضمن صلاحياتك''using errcode=''42501'';end if;
 uid:=coalesce(t.cashbox_user_id,t.created_by);');
 definition:=replace(definition,'then return prior.response;end if;','then return solar_private.supplier_payment_ack_read_projection(prior.response);end if;');
 definition:=replace(definition,' return result;',' return solar_private.supplier_payment_ack_read_projection(result);');
 execute definition;
end$$;
notify pgrst,'reload schema';
