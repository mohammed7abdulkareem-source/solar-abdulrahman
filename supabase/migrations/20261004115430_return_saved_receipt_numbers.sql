create function public.solar_save_rows_with_receipts(changes jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 perform public.solar_save_rows_v31(changes);
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'receiptNo',t.receipt_no)),'[]'::jsonb) into result
 from public.transactions t where t.id in (
 select (r->>'id')::bigint from jsonb_array_elements(changes) c
 cross join lateral jsonb_array_elements(coalesce(c->'rows','[]'::jsonb)) r where c->>'table'='transactions');
 return result;
end $$;
revoke all on function public.solar_save_rows_with_receipts(jsonb) from public,anon;
grant execute on function public.solar_save_rows_with_receipts(jsonb) to authenticated;
