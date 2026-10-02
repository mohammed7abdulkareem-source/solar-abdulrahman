-- Atomic saves for the existing shared-data model. SECURITY INVOKER preserves RLS.
create or replace function public.solar_save_rows_v31(changes jsonb)
returns void language plpgsql security invoker set search_path = '' as $$
declare change jsonb; row_data jsonb; table_name text; columns_sql text; values_sql text; update_sql text;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and active=true) then
  raise exception 'Active login required' using errcode='42501';
 end if;
 if jsonb_typeof(changes)<>'array' then raise exception 'Invalid changes'; end if;
 for change in select value from jsonb_array_elements(changes) loop
  table_name:=change->>'table';
  if table_name is null or table_name not in ('brands','products','customers','suppliers','transactions','transaction_items') then raise exception 'Invalid table'; end if;
  if table_name='transaction_items' then
   delete from public.transaction_items where transaction_id in (select value::bigint from jsonb_array_elements_text(coalesce(change->'removeTransactionIds','[]'::jsonb)));
  else
   execute format('delete from public.%I where id in (select value::bigint from jsonb_array_elements_text($1))',table_name) using coalesce(change->'removed','[]'::jsonb);
  end if;
  for row_data in select value from jsonb_array_elements(coalesce(change->'rows','[]'::jsonb)) loop
   if jsonb_typeof(row_data)<>'object' then raise exception 'Invalid row'; end if;
   select string_agg(format('%I',key),',' order by key),string_agg(format('r.%I',key),',' order by key),string_agg(format('%I=excluded.%I',key,key),',' order by key) filter(where key<>'id')
   into columns_sql,values_sql,update_sql from jsonb_object_keys(row_data) as keys(key);
   if columns_sql is null then raise exception 'Empty row'; end if;
   if table_name='transaction_items' then
    execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I,$1) r',table_name,columns_sql,values_sql,table_name) using row_data;
   else
    execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I,$1) r on conflict(id) do update set %s',table_name,columns_sql,values_sql,table_name,update_sql) using row_data;
   end if;
  end loop;
 end loop;
end $$;
revoke all on function public.solar_save_rows_v31(jsonb) from public,anon;
grant execute on function public.solar_save_rows_v31(jsonb) to authenticated;
