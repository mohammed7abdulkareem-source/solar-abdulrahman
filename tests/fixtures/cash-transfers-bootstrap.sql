-- Local financial fixture extension: original cash transfer migration, with warehouse guard.
-- No live data or schema changes.
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

create function solar_private.cash_transfer_overview() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; result jsonb;
begin
 if solar_private.role_name()='warehouse' then raise exception 'Not permitted' using errcode='42501';end if;
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
 if solar_private.role_name()='warehouse' then raise exception 'Not permitted' using errcode='42501';end if;
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
 if solar_private.role_name()='warehouse' then raise exception 'Not permitted' using errcode='42501';end if;
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
