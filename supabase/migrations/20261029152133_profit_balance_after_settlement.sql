-- Read-only reporting. Preserve the existing settlement postings, checkpoints,
-- frozen exchange rates, cash balances and all historical business rows.
create function solar_private.profit_balance(payload jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
 actor public.profiles;uid uuid;all_owners boolean;date_from date;date_to date;sale_type text;result jsonb;
begin
 select * into actor from public.profiles where id=auth.uid() and active;
 if actor.id is null or actor.user_type in('installer','warehouse') or
  not(actor.is_admin or coalesce(actor.permissions->>'profit','false')='true' or coalesce(actor.permissions->>'profitSettlement','false')='true') then
  raise exception 'لا تملك صلاحية الأرباح' using errcode='42501';
 end if;
 if jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب غير صحيح';end if;
 all_owners:=coalesce(payload->>'ownerId','')='all';
 if all_owners and not actor.is_admin then raise exception 'يمكنك مشاهدة أرباحك فقط' using errcode='42501';end if;
 uid:=case when all_owners then null else coalesce(nullif(payload->>'ownerId','')::uuid,actor.id) end;
 if not actor.is_admin and uid<>actor.id then raise exception 'يمكنك مشاهدة أرباحك فقط' using errcode='42501';end if;
 if not all_owners and not exists(select 1 from public.profiles where id=uid and user_type not in('installer','warehouse')) then raise exception 'المستخدم غير موجود';end if;
 date_from:=nullif(payload->>'from','')::date;
 date_to:=coalesce(nullif(payload->>'to','')::date,(now() at time zone 'Asia/Baghdad')::date);
 sale_type:=coalesce(payload->>'type','all');
 if date_from>date_to or date_to>(now() at time zone 'Asia/Baghdad')::date or sale_type not in('all','sale','system') then raise exception 'تصفية أرباح غير صحيحة';end if;
 with owners as materialized(
  select id from public.profiles where (all_owners or id=uid) and user_type not in('installer','warehouse')
 ), sources as materialized(
  select o.id owner_id,x.value row_data from owners o cross join lateral jsonb_array_elements(solar_private.profit_rows(o.id))x
 ), period_rows as materialized(
  select * from sources where (date_from is null or (row_data->>'date')::timestamptz at time zone 'Asia/Baghdad'>=date_from::timestamp)
   and (row_data->>'date')::timestamptz at time zone 'Asia/Baghdad'<(date_to+1)::timestamp
   and(sale_type='all' or row_data->>'kind'=sale_type or row_data->>'kind' not in('sale','system'))
 ) select jsonb_build_object(
  'ownerId',case when all_owners then 'all' else uid::text end,'currency','IQD','asOf',now(),'from',date_from,'to',date_to,'type',sale_type,
  -- Use the SAME authoritative balance as the existing cash distribution guard.
  -- Date/type filters only change the historical period, never the current balance.
  'remaining',(select coalesce(sum(solar_private.retained_profit(id)),0) from owners),
  'period',jsonb_build_object(
   'earned',(select coalesce(sum((row_data->>'value')::numeric),0) from period_rows),
   'settled',(select coalesce(sum((row_data->>'settled')::numeric),0) from period_rows),
   'available',(select coalesce(sum((row_data->>'available')::numeric),0) from period_rows)),
  'rows',(select coalesce(jsonb_agg(row_data||jsonb_build_object('ownerId',owner_id) order by row_data->>'date',owner_id,row_data->>'key'),'[]') from period_rows)
 ) into result;
 return result;
end $$;
revoke all on function solar_private.profit_balance(jsonb) from public,anon,authenticated;

do $$declare definition text;anchor text;begin
 definition:=pg_get_functiondef('solar_private.profit_workspace(text,uuid,jsonb)'::regprocedure);
 anchor:=' if action is null or action not in(''overview'',''request'',''approve'',''reject'',''cancel'')';
 if strpos(definition,anchor)=0 then raise exception 'Review profit reporting dispatch anchor';end if;
 definition:=replace(definition,anchor,' if action=''balance'' then return solar_private.profit_balance(payload);end if;'||E'\n'||anchor);
 anchor:='''rows'',snapshot,''available'',total,''token'',token';
 if strpos(definition,anchor)=0 then raise exception 'Review profit overview balance anchor';end if;
 definition:=replace(definition,anchor,'''retainedProfit'',solar_private.retained_profit(uid),'||anchor);
 execute definition;
end $$;
notify pgrst,'reload schema';
