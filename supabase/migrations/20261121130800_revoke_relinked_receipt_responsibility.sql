-- An invoice correction can legitimately change the customer. The previous
-- customer's explicit delegation ends at that change, before any notifications.
create table solar_private.relinked_receipt_assignments (
 transaction_id bigint not null,
 assignment_request_id uuid not null,
 assignment jsonb not null,
 new_customer_id bigint,
 recorded_at timestamptz not null default clock_timestamp(),
 actor_id uuid default auth.uid(),
 database_actor name not null default session_user,
 primary key (transaction_id, assignment_request_id)
);
alter table solar_private.relinked_receipt_assignments enable row level security;
revoke all on solar_private.relinked_receipt_assignments from public,anon,authenticated;

create function solar_private.revoke_relinked_receipt(receipt_id bigint, linked_customer_id bigint)
returns void language sql security definer set search_path='' as $$
 with revoked as (
  delete from solar_private.customer_receipt_responsibility r
  where r.transaction_id=receipt_id and r.customer_id is distinct from linked_customer_id
  returning r.*
 )
 insert into solar_private.relinked_receipt_assignments(transaction_id,assignment_request_id,assignment,new_customer_id)
 select r.transaction_id,r.request_id,to_jsonb(r),linked_customer_id from revoked r
$$;
revoke all on function solar_private.revoke_relinked_receipt(bigint,bigint) from public,anon,authenticated;

create function solar_private.customer_receipt_party_changed() returns trigger
language plpgsql security definer set search_path='' as $$
declare linked_customer_id bigint;
begin
 if not exists (select 1 from solar_private.customer_receipt_responsibility r where r.transaction_id=new.id) then
  return null;
 end if;
 if new.kind in ('sale','system') then
  if new.party_id is not null then
   linked_customer_id:=new.party_id;
  else
   -- Historical name-only invoices follow the same uniqueness rules as the ledger.
   select l.customer_id into linked_customer_id from solar_private.customer_movement_links() l where l.transaction_id=new.id;
  end if;
 end if;
 perform solar_private.revoke_relinked_receipt(new.id,linked_customer_id);
 return null;
end $$;
revoke all on function solar_private.customer_receipt_party_changed() from public,anon,authenticated;

select pg_advisory_xact_lock(7311,1);
create trigger solar_assignment_after_party_change
 after update of party_id,party_name,kind on public.transactions
 for each row when ((old.party_id,old.party_name,old.kind) is distinct from (new.party_id,new.party_name,new.kind))
 execute function solar_private.customer_receipt_party_changed();

-- Retain the original transfer's actor and reason for assignments that already
-- outlived their customer link before this migration arrived.
do $$
declare stale record;
begin
 for stale in
  select r.transaction_id,case when t.kind in ('sale','system') then l.customer_id end as linked_customer_id
  from solar_private.customer_receipt_responsibility r
  join public.transactions t on t.id=r.transaction_id
  left join solar_private.customer_movement_links() l on l.transaction_id=r.transaction_id
  where t.kind not in ('sale','system') or r.customer_id is distinct from l.customer_id
 loop
  perform solar_private.revoke_relinked_receipt(stale.transaction_id,stale.linked_customer_id);
 end loop;
end $$;
