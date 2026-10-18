-- Public invoker used by the production UI; older local fixtures only contain
-- the private implementation. This file is for isolated browser databases.
create or replace function public.solar_reconcile(action text,request_id uuid,payload jsonb)
returns jsonb language sql security invoker set search_path='' as $$select solar_private.reconcile(action,request_id,payload)$$;
revoke all on function public.solar_reconcile(text,uuid,jsonb) from public,anon;
grant execute on function public.solar_reconcile(text,uuid,jsonb) to authenticated;
