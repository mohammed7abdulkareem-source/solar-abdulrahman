-- Recheck a recipient's current modules for both past inbox rows and queued pushes.
-- Independent job, material, warehouse, transfer and recipient rules still intersect.
create function solar_private.notification_feature_allowed(p public.profiles, notice_event text, heading text)
returns boolean language sql immutable security invoker set search_path='' as $$
 select coalesce(p.active and case
  when notice_event in ('admin_message','test') then true
  when p.user_type not in ('warehouse','installer') and p.is_admin then true
  when notice_event in ('purchase_received','wholesale_prices_updated') then true -- existing material scope
  when p.user_type='installer' then notice_event in ('assigned','completed','installation_updated','installation_closed','invoice_deleted','warehouse_ready')
  when p.user_type='warehouse' then notice_event in ('warehouse_new','warehouse_reopened','warehouse_edited','warehouse_ready','invoice_deleted',
    'stock_transfer_pending','stock_transfer_prepared','stock_transfer_cancelled','stock_transfer_reversed')
  when notice_event in ('cash_received','cash_accepted','cash_rejected','cash_cancelled') then
    p.permissions @> '{"cashTransferSend":true}' or p.permissions @> '{"financeReceive":true}'
  when notice_event in ('receipt_delete_requested','receipt_delete_decided') then p.permissions @> '{"deletionRequests":true}'
  when notice_event in ('profit_requested','profit_decided') then p.permissions @> '{"profit":true}' or p.permissions @> '{"profitSettlement":true}'
  when notice_event in ('assigned','completed','installation_updated','installation_closed') then p.permissions @> '{"installations":true}' or p.permissions @> '{"system":true}'
  when notice_event in ('stock_transfer_pending','stock_transfer_prepared','stock_transfer_cancelled','stock_transfer_reversed')
    then p.permissions @> '{"warehouse":true}' or p.permissions @> '{"stock":true}'
  when notice_event in ('warehouse_new','warehouse_reopened','warehouse_ready','warehouse_edited','invoice_deleted') then
    p.permissions @> '{"warehouse":true}' or p.permissions @> '{"installations":true}' or p.permissions @> '{"system":true}' or
    case when p.permissions ? 'salesHistory' then p.permissions @> '{"salesHistory":true}' else p.permissions @> '{"sale":true}' end
  -- Operation notices historically share one event key for multiple modules.
  when notice_event in ('operation_paused','operation_resumed') then case
    when heading like '%الشراء%' then p.permissions @> '{"purchase":true}'
    when heading like '%المنظومات%' then p.permissions @> '{"system":true}'
    when heading like '%أسعار بيع الجملة%' then p.permissions @> '{"sale":true}' or p.permissions @> '{"wholesalePricingManage":true}'
    when heading like '%بيع الجملة%' then p.permissions @> '{"sale":true}'
    else false end
  else false end,false)
$$;
revoke all on function solar_private.notification_feature_allowed(public.profiles,text,text) from public,anon;
grant execute on function solar_private.notification_feature_allowed(public.profiles,text,text) to authenticated;

create policy solar_notification_feature_scope on public.solar_notifications as restrictive
 for all to authenticated
 using (exists(select 1 from public.profiles p where p.id=(select auth.uid())
        and solar_private.notification_feature_allowed(p,event,title)))
 with check (exists(select 1 from public.profiles p where p.id=(select auth.uid())
        and solar_private.notification_feature_allowed(p,event,title)));

-- The dispatcher's existing lease, recipient, warehouse and invoice checks are retained.
do $$
declare old_def text:=pg_get_functiondef('public.solar_push_claim()'::regprocedure);
 anchor constant text:=' where(n.event not in(''purchase_received'',''wholesale_prices_updated'')';
begin
 if strpos(old_def,anchor)=0 then raise exception 'Unexpected push claim entitlement query'; end if;
 execute replace(old_def,anchor,' where solar_private.notification_feature_allowed(p,n.event,n.title) and(n.event not in(''purchase_received'',''wholesale_prices_updated'')');
end
$$;
