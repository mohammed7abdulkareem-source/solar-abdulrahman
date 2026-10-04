-- Immutable, server-posted cash movements. Transfers are not revenue or capital.
create table solar_private.cash_transfers (
 id uuid primary key,
 sender_id uuid not null references public.profiles(id),
 recipient_id uuid not null references public.profiles(id),
 amount numeric not null check(amount>0 and amount<=1000000000000),
 expense numeric not null default 0 check(expense>=0 and expense<=1000000000000),
 expense_note text not null default '', notes text not null default '',
 status text not null default 'pending' check(status in ('pending','accepted','rejected','cancelled')),
 created_at timestamptz not null default now(), decided_at timestamptz, decided_by uuid references public.profiles(id),
 check(sender_id<>recipient_id)
);
alter table solar_private.cash_transfers enable row level security;
revoke all on solar_private.cash_transfers from public,anon,authenticated;
create index solar_transfers_sender on solar_private.cash_transfers(sender_id,created_at desc);
create index solar_transfers_recipient on solar_private.cash_transfers(recipient_id,status,created_at desc);

create table public.solar_cash_entries (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid references public.profiles(id),
 delta numeric not null check(delta<>0 and abs(delta)<=1000000000000),
 entry_type text not null check(entry_type in ('installation_payout','installation_refund','handover_expense','transfer_out','transfer_in','transfer_refund','transfer_transit')),
 job_id bigint references public.transactions(id),
 transfer_id uuid references solar_private.cash_transfers(id),
 actor_id uuid not null references public.profiles(id),
 notes text not null default '', created_at timestamptz not null default now(),
 check((entry_type='transfer_transit')=(owner_id is null)),
 check((entry_type in ('installation_payout','installation_refund'))=(job_id is not null)),
 check((entry_type not in ('installation_payout','installation_refund'))=(transfer_id is not null))
);
create index solar_entries_owner on public.solar_cash_entries(owner_id,created_at);
create index solar_entries_job on public.solar_cash_entries(job_id) where job_id is not null;
create index solar_entries_transfer on public.solar_cash_entries(transfer_id) where transfer_id is not null;
alter table public.solar_cash_entries enable row level security;
revoke all on public.solar_cash_entries from public,anon,authenticated;
grant select on public.solar_cash_entries to authenticated;
create policy own_cash_entries on public.solar_cash_entries for select to authenticated
 using ((select solar_private.role_name())='admin' or ((select solar_private.role_name())='staff' and owner_id=(select auth.uid())));

-- One short transaction lock serializes cash writes, including legacy invoice writes.
create function solar_private.lock_cash_writes() returns trigger language plpgsql set search_path='' as $$
begin perform pg_advisory_xact_lock(7311,1);return null;end $$;
revoke all on function solar_private.lock_cash_writes() from public,anon,authenticated;
create trigger solar_cash_write_lock before insert or update or delete on public.transactions for each statement execute function solar_private.lock_cash_writes();

create function solar_private.cash_balance(uid uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce((select sum(case when t.kind in ('purchase','supplier_payment','cash_expense','profit_distribution') then -coalesce(t.total,0) else coalesce(t.total,0) end) from public.transactions t where t.cash and coalesce(t.cashbox_user_id,t.created_by)=uid),0)
 + coalesce((select sum(e.delta) from public.solar_cash_entries e where e.owner_id=uid),0)
$$;
revoke all on function solar_private.cash_balance(uuid) from public,anon,authenticated;

create function solar_private.cash_transfer_overview() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; result jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type='installer' or not (p.is_admin or coalesce(p.permissions->>'cashTransferSend','false')='true' or coalesce(p.permissions->>'financeReceive','false')='true') then raise exception 'Not permitted' using errcode='42501';end if;
 select jsonb_build_object('balance',solar_private.cash_balance(p.id),'canSend',p.is_admin or coalesce(p.permissions->>'cashTransferSend','false')='true','canReceive',p.is_admin or coalesce(p.permissions->>'financeReceive','false')='true',
 'managers',(select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'name',coalesce(u.display_name,u.username)) order by u.display_name),'[]'::jsonb) from public.profiles u where u.active and u.user_type<>'installer' and u.id<>p.id and (u.is_admin or u.permissions->>'financeReceive'='true')),
 'rows',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('senderName',(select coalesce(u.display_name,u.username) from public.profiles u where u.id=r.sender_id),'recipientName',(select coalesce(u.display_name,u.username) from public.profiles u where u.id=r.recipient_id)) order by r.created_at desc),'[]'::jsonb) from solar_private.cash_transfers r where (p.is_admin or r.sender_id=p.id or r.recipient_id=p.id) and (r.status='pending' or r.id in (select q.id from solar_private.cash_transfers q where p.is_admin or q.sender_id=p.id or q.recipient_id=p.id order by q.created_at desc limit 100)))) into result;
 return result;
end $$;

create function solar_private.cash_transfer_send(request_id uuid,recipient uuid,send_amount numeric,expense_amount numeric default 0,expense_note text default '',note text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare p public.profiles; old_request solar_private.cash_transfers;
begin
 perform pg_advisory_xact_lock(7311,1);
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type='installer' or not (p.is_admin or coalesce(p.permissions->>'cashTransferSend','false')='true') then raise exception 'Not permitted' using errcode='42501';end if;
 if request_id is null or send_amount is null or not(send_amount>0 and send_amount<=1000000000000) or expense_amount is null or not(expense_amount>=0 and expense_amount<=1000000000000) or length(coalesce(note,''))>2000 or length(coalesce(expense_note,''))>1000 then raise exception 'Invalid amounts';end if;
 select * into old_request from solar_private.cash_transfers where id=request_id;
 if found then
  if old_request.sender_id=p.id and old_request.recipient_id=recipient and old_request.amount=send_amount and old_request.expense=expense_amount and old_request.expense_note=coalesce(expense_note,'') and old_request.notes=coalesce(note,'') then return request_id;end if;
  raise exception 'Request conflict' using errcode='40001';
 end if;
 if recipient is null or recipient=p.id or not exists(select 1 from public.profiles u where u.id=recipient and u.active and u.user_type<>'installer' and (u.is_admin or u.permissions->>'financeReceive'='true')) then raise exception 'Recipient unavailable' using errcode='42501';end if;
 if solar_private.cash_balance(p.id)<send_amount+expense_amount then raise exception 'Insufficient cash' using errcode='P0002';end if;
 insert into solar_private.cash_transfers(id,sender_id,recipient_id,amount,expense,expense_note,notes) values(request_id,p.id,recipient,send_amount,expense_amount,coalesce(expense_note,''),coalesce(note,''));
 if expense_amount>0 then insert into public.solar_cash_entries(owner_id,delta,entry_type,transfer_id,actor_id,notes) values(p.id,-expense_amount,'handover_expense',request_id,p.id,coalesce(nullif(expense_note,''),'مصروف قبل تسليم القاصة'));end if;
 insert into public.solar_cash_entries(owner_id,delta,entry_type,transfer_id,actor_id,notes) values
 (p.id,-send_amount,'transfer_out',request_id,p.id,'إرسال أموال إلى مسؤول المالية'),
 (null,send_amount,'transfer_transit',request_id,p.id,'أموال قيد التسليم — لا تدخل قاصة المستلم قبل الموافقة');
 return request_id;
end $$;

create function solar_private.cash_transfer_decide(request_id uuid,decision text) returns void language plpgsql security definer set search_path='' as $$
declare p public.profiles; r solar_private.cash_transfers; destination uuid;
begin
 perform pg_advisory_xact_lock(7311,1);
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type='installer' then raise exception 'Not permitted' using errcode='42501';end if;
 select * into r from solar_private.cash_transfers where id=request_id for update;
 if r.id is null then raise exception 'Not permitted' using errcode='42501';end if;
 if decision='cancelled' then
  if r.sender_id<>p.id then raise exception 'Not permitted' using errcode='42501';end if;
 elsif decision in ('accepted','rejected') then
  if r.recipient_id<>p.id or not(p.is_admin or coalesce(p.permissions->>'financeReceive','false')='true') then raise exception 'Not permitted' using errcode='42501';end if;
 else raise exception 'Invalid decision';end if;
 if r.status=decision then return;end if;
 if r.status<>'pending' then raise exception 'Transfer already decided' using errcode='40001';end if;
 destination:=case when decision='accepted' then r.recipient_id else r.sender_id end;
 insert into public.solar_cash_entries(owner_id,delta,entry_type,transfer_id,actor_id,notes) values
 (null,-r.amount,'transfer_transit',r.id,p.id,'تسوية أموال قيد التسليم'),
 (destination,r.amount,case when decision='accepted' then 'transfer_in' else 'transfer_refund' end,r.id,p.id,case when decision='accepted' then 'استلام معتمد من مسؤول المالية' else 'إرجاع مبلغ تحويل غير معتمد؛ المصروف السابق يبقى مسجلاً' end);
 update solar_private.cash_transfers set status=decision,decided_at=now(),decided_by=p.id where id=r.id;
end $$;

revoke all on function solar_private.cash_transfer_overview(),solar_private.cash_transfer_send(uuid,uuid,numeric,numeric,text,text),solar_private.cash_transfer_decide(uuid,text) from public,anon;
grant execute on function solar_private.cash_transfer_overview(),solar_private.cash_transfer_send(uuid,uuid,numeric,numeric,text,text),solar_private.cash_transfer_decide(uuid,text) to authenticated;
create function public.solar_cash_transfer_overview() returns jsonb language sql security invoker set search_path='' as $$select solar_private.cash_transfer_overview()$$;
create function public.solar_cash_transfer_send(request_id uuid,recipient uuid,send_amount numeric,expense_amount numeric default 0,expense_note text default '',note text default '') returns uuid language sql security invoker set search_path='' as $$select solar_private.cash_transfer_send(request_id,recipient,send_amount,expense_amount,expense_note,note)$$;
create function public.solar_cash_transfer_decide(request_id uuid,decision text) returns void language sql security invoker set search_path='' as $$select solar_private.cash_transfer_decide(request_id,decision)$$;
revoke all on function public.solar_cash_transfer_overview(),public.solar_cash_transfer_send(uuid,uuid,numeric,numeric,text,text),public.solar_cash_transfer_decide(uuid,text) from public,anon;
grant execute on function public.solar_cash_transfer_overview(),public.solar_cash_transfer_send(uuid,uuid,numeric,numeric,text,text),public.solar_cash_transfer_decide(uuid,text) to authenticated;

-- The caller of close pays only the unpaid increase. Reopening never pays twice.
-- A downward correction refunds the original payers, never an unrelated closer.
create function solar_private.post_installation_cash(job_id bigint,approved numeric,actor uuid) returns void language plpgsql security definer set search_path='' as $$
declare paid numeric; difference numeric; refund numeric; allocation record;
begin
 if actor is distinct from auth.uid() then raise exception 'Not permitted' using errcode='42501';end if;
 select -coalesce(sum(delta),0) into paid from public.solar_cash_entries e where e.job_id=post_installation_cash.job_id;
 difference:=approved-paid;
 if difference>0 then
  if solar_private.cash_balance(actor)<difference then raise exception 'Insufficient cash' using errcode='P0002';end if;
  insert into public.solar_cash_entries(owner_id,delta,entry_type,job_id,actor_id,notes) values(actor,-difference,'installation_payout',job_id,actor,'مصاريف تنصيب ملف #'||job_id::text);
 elsif difference<0 then
  refund:=-difference;
  for allocation in select owner_id,-sum(delta) as amount,max(created_at) as last_at from public.solar_cash_entries e where e.job_id=post_installation_cash.job_id group by owner_id having sum(delta)<0 order by max(created_at) desc,owner_id loop
   insert into public.solar_cash_entries(owner_id,delta,entry_type,job_id,actor_id,notes) values(allocation.owner_id,least(refund,allocation.amount),'installation_refund',job_id,actor,'استرجاع فرق مصاريف ملف #'||job_id::text);
   refund:=refund-least(refund,allocation.amount);exit when refund=0;
  end loop;
 end if;
end $$;
revoke all on function solar_private.post_installation_cash(bigint,numeric,uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION solar_private.installation_action(job_id bigint, expected_revision bigint, action text, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles; j public.transactions; amount numeric; e jsonb; report jsonb;
begin
 perform pg_advisory_xact_lock(7311,1);
 select * into p from public.profiles where id=auth.uid() and active=true;
 if p.id is null then raise exception 'Active login required' using errcode='42501'; end if;
 select * into j from public.transactions where id=job_id and kind='system' for update;
 if j.id is null then raise exception 'Job unavailable' using errcode='42501'; end if;
 if p.user_type='installer' then
  if j.installer_id is distinct from p.id or action not in ('start','complete') then raise exception 'Not permitted' using errcode='42501'; end if;
 else
  if not (solar_private.can_close_installation(j.created_by)) or action not in ('close','reopen') then raise exception 'Not permitted' using errcode='42501'; end if;
 end if;
 if expected_revision is distinct from j.installation_revision then raise exception 'Job changed; refresh and retry' using errcode='40001'; end if;
 if action='start' then
  if j.installation_status<>'pending' then raise exception 'Invalid stage'; end if;
  update public.transactions set installation_status='in_progress',installation_started_at=now(),installation_revision=installation_revision+1 where id=j.id;
 elsif action='complete' then
  if j.installation_status<>'in_progress' then raise exception 'Start the installation first'; end if;
  if jsonb_typeof(payload) is distinct from 'object' or length(trim(coalesce(payload->>'notes','')))=0 or length(payload->>'notes')>4000 then raise exception 'Completion report required'; end if;
  if payload->'checks'->>'materials' is distinct from 'true' or payload->'checks'->>'tested' is distinct from 'true' or payload->'checks'->>'handover' is distinct from 'true' then raise exception 'Complete the checklist'; end if;
  if jsonb_typeof(payload->'expenses') is distinct from 'array' then raise exception 'Invalid expenses'; end if;
  if jsonb_array_length(payload->'expenses')>50 then raise exception 'Too many expense lines'; end if;
  amount:=0;
  for e in select value from jsonb_array_elements(payload->'expenses') loop
   if jsonb_typeof(e->'amount') is distinct from 'number' or (e->>'amount')::numeric<=0 or (e->>'amount')::numeric>1000000000 or length(trim(coalesce(e->>'description','')))=0 or length(e->>'description')>500 then raise exception 'Invalid expense line'; end if;
   amount:=amount+(e->>'amount')::numeric;
  end loop;
  report:=jsonb_build_object('notes',trim(payload->>'notes'),'checks',payload->'checks','expenses',payload->'expenses','expenseTotal',amount,'submittedAt',now(),'submittedBy',p.id);
  update public.transactions set installation_status='completed',installation_completed_at=now(),installation_report=report,installation_revision=installation_revision+1 where id=j.id;
 elsif action='close' then
  if j.installation_status<>'completed' then raise exception 'Engineer report required before closing'; end if;
  if jsonb_typeof(payload->'amount') is distinct from 'number' then raise exception 'Invalid approved expenses'; end if;
  amount:=(payload->>'amount')::numeric;
  if amount<0 or amount>1000000000 then raise exception 'Invalid approved expenses'; end if;
  if length(coalesce(payload->>'notes',''))>4000 then raise exception 'Notes too long'; end if;
  perform solar_private.post_installation_cash(j.id,amount,p.id);
  update public.transactions set installation_status='closed',installation_closed_at=now(),installation_expenses=amount,installation_expense_notes=payload->>'notes',profit=coalesce(total,0)-coalesce(cost,0)-coalesce(expenses,0)-amount,installation_revision=installation_revision+1 where id=j.id;
 elsif action='reopen' then
  if j.installation_status<>'closed' then raise exception 'Only closed files can reopen'; end if;
  update public.transactions set installation_status='completed',installation_closed_at=null,installation_revision=installation_revision+1 where id=j.id;
 else raise exception 'Invalid action'; end if;
end $function$;
