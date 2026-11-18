-- An external settlement changes one employee's personal profit entitlement.
-- Its only financial posting is the signed difference in this private ledger.
create table solar_private.profit_balance_adjustments(
 id uuid primary key,
 sequence_no bigint generated always as identity unique,
 owner_id uuid not null references public.profiles(id),
 actor_id uuid not null references public.profiles(id),
 actor_name text not null,
 created_at timestamptz not null default clock_timestamp(),
 before_amount numeric not null,
 after_amount numeric not null,
 checkpoint_offset numeric not null,
 delta numeric not null check (delta = after_amount - before_amount),
 note text not null check (length(note) <= 2000),
 pending_settlement_id uuid references solar_private.profit_settlements(id)
);
create index profit_balance_adjustments_owner_seq
 on solar_private.profit_balance_adjustments(owner_id,sequence_no desc);
create index profit_balance_adjustments_pending
 on solar_private.profit_balance_adjustments(pending_settlement_id) where pending_settlement_id is not null;
alter table solar_private.profit_balance_adjustments enable row level security;
revoke all on solar_private.profit_balance_adjustments from public,anon,authenticated;
revoke all on sequence solar_private.profit_balance_adjustments_sequence_no_seq from public,anon,authenticated;

create function solar_private.profit_adjustment_audit_guard() returns trigger
language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' and current_setting('solar.reset_inventory',true)='true' then return old;end if;
 raise exception 'سجل التسوية الخارجية محفوظ. سجّل تسوية جديدة لتصحيح الرصيد.' using errcode='42501';
end $$;
revoke all on function solar_private.profit_adjustment_audit_guard() from public,anon,authenticated;
create trigger immutable_profit_adjustment before update or delete on solar_private.profit_balance_adjustments
 for each row execute function solar_private.profit_adjustment_audit_guard();

create function solar_private.profit_adjustment_receipt(a solar_private.profit_balance_adjustments)
returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('id',a.id,'ownerId',a.owner_id,'actorId',a.actor_id,'actorName',a.actor_name,
  'createdAt',a.created_at,'before',a.before_amount,'after',a.after_amount,'delta',a.delta,'checkpointOffset',a.checkpoint_offset,'note',a.note)
$$;
revoke all on function solar_private.profit_adjustment_receipt(solar_private.profit_balance_adjustments) from public,anon,authenticated;

create function solar_private.profit_adjustment_token(owner uuid,remaining numeric)
returns text language sql stable set search_path='' as $$
 select md5(jsonb_build_array(owner,trim_scale(remaining),(
  select a.id from solar_private.profit_balance_adjustments a where a.owner_id=owner order by a.sequence_no desc limit 1
 ))::text)
$$;
revoke all on function solar_private.profit_adjustment_token(uuid,numeric) from public,anon,authenticated;

create function solar_private.adjust_personal_profit(attempt uuid,body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 actor public.profiles; owner public.profiles; prior solar_private.finance_requests;
 adjustment solar_private.profit_balance_adjustments; balance numeric; unsettled numeric; first_adjustment boolean; target numeric; memo text; result jsonb;
begin
 -- The normal settlement, cash and invoice writers participate in this lock.
 perform pg_advisory_xact_lock(7311,1);
 select * into actor from public.profiles where id=auth.uid() and active and is_admin and user_type not in ('warehouse','installer') for share;
 if actor.id is null then raise exception 'التسوية الخارجية للأرباح متاحة للأدمن فقط' using errcode='42501';end if;
 if attempt is null or jsonb_typeof(body) is distinct from 'object' then raise exception 'بيانات التسوية غير صحيحة' using errcode='22023';end if;
 select * into prior from solar_private.finance_requests f where f.request_id=attempt;
 if prior.request_id is not null then
  if prior.actor_id=actor.id and prior.action='profit_external_adjust' and prior.payload=body then return prior.response;end if;
  raise exception 'معرف التسوية مستخدم لطلب مختلف' using errcode='40001';
 end if;
 if jsonb_typeof(body->'targetBalance') is distinct from 'number'
  or jsonb_typeof(body->'ownerId') is distinct from 'string'
  or (body ? 'note' and jsonb_typeof(body->'note') is distinct from 'string') then
  raise exception 'اختر المستخدم وأدخل الرصيد المطلوب بالدينار' using errcode='22023';
 end if;
 select * into owner from public.profiles where id=(body->>'ownerId')::uuid and active and user_type not in ('warehouse','installer') for share;
 if owner.id is null then raise exception 'اختر مستخدماً إدارياً فعالاً' using errcode='22023';end if;
 target:=(body->>'targetBalance')::numeric;memo:=trim(coalesce(body->>'note',''));
 if target::text in ('NaN','Infinity','-Infinity') or round(target,2)<>target or length(memo)>2000 then
  raise exception 'أدخل رصيداً بحد أقصى منزلتين عشريتين وملاحظة لا تتجاوز ٢٠٠٠ حرف' using errcode='22023';
 end if;
 balance:=solar_private.retained_profit(owner.id);
 if body->>'expectedToken' is distinct from solar_private.profit_adjustment_token(owner.id,balance) then
  raise exception 'تغيّر رصيد الأرباح. حدّث الكشف وراجع الرصيد قبل الحفظ.' using errcode='40001';
 end if;
 -- The normal settlement ledger may predate direct cash distributions or
 -- old allocation models. Record only its opening difference from the real
 -- retained balance, separately from the financial delta.
 select coalesce(sum((x->>'available')::numeric),0) into unsettled
 from jsonb_array_elements(solar_private.profit_rows(owner.id)) x;
 select not exists(select 1 from solar_private.profit_balance_adjustments a where a.owner_id=owner.id) into first_adjustment;
 if first_adjustment then
  -- These existing payouts become visible as settled rows at activation.
  select unsettled-coalesce(sum(t.total),0) into unsettled from public.transactions t
  where coalesce(t.cashbox_user_id,t.created_by)=owner.id and t.kind='profit_distribution'
   and t.profit_settlement_id is null and coalesce(t.cash_purpose,'') not in('expense','external_profit');
 end if;
 insert into solar_private.profit_balance_adjustments(id,owner_id,actor_id,actor_name,before_amount,after_amount,delta,checkpoint_offset,note,pending_settlement_id)
 values(attempt,owner.id,actor.id,coalesce(solar_private.user_name(actor.display_name,actor.username,actor.honorific),'الإدارة'),
        balance,target,target-balance,unsettled-balance,memo,
        (select s.id from solar_private.profit_settlements s where s.owner_id=owner.id and s.status='pending' and target<>balance))
 returning * into adjustment;
 result:=solar_private.profit_adjustment_receipt(adjustment);
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response)
 values(attempt,actor.id,'profit_external_adjust',body,result);
 return result;
end $$;
revoke all on function solar_private.adjust_personal_profit(uuid,jsonb) from public,anon,authenticated;

do $patch$
declare definition text; signature text; digest text;
begin
 for signature,digest in select key,value from jsonb_each_text('{
  "solar_private.profit_workspace(text,uuid,jsonb)":"d96fc18161238d8b7037e7d468ffbc17",
  "solar_private.profit_balance(jsonb)":"bf7299aab699b1116966477dade8521f",
  "solar_private.profit_rows(uuid)":"d8410744dc326f4ee38740b1b7d64c0f",
  "solar_private.retained_profit(uuid)":"49259765694b71678fd1aef0131ced01",
  "solar_private.reset_snapshot()":"1cec717c634e51bfb641398d0d01ab7b",
  "solar_private.lock_reset_tables()":"445261533c7fcdf85a4b6e363db2d63a",
  "public.solar_execute_reset(uuid,uuid,text)":"2b47db1cea00d63a71a995f992d480cd"
 }'::jsonb) loop
  if md5(pg_get_functiondef(signature::regprocedure))<>digest then raise exception 'Review installed function % before changing personal profit accounting',signature;end if;
 end loop;

 definition:=pg_get_functiondef('solar_private.retained_profit(uuid)'::regprocedure);
 definition:=replace(definition,$old$ select coalesce((select sum(case when t.kind='system'$old$,
 $new$ select coalesce((select sum(a.delta) from solar_private.profit_balance_adjustments a where a.owner_id=uid),0)
 +coalesce((select sum(case when t.kind='system'$new$);
 execute definition;

 -- This is a real source for settlement checkpoints. Previously settled rows
 -- therefore never become newly available following another recalibration.
 definition:=pg_get_functiondef('solar_private.profit_rows(uuid)'::regprocedure);
 definition:=replace(definition,' ), rows as(', $new$ union all
 select 'adjustment:'||a.id,a.created_at,'external_adjustment','تسوية أرباح خارجية',null,a.delta
 from solar_private.profit_balance_adjustments a where a.owner_id=uid
 union all
 select 'distribution:'||md5(uid::text||':'||t.id::text),t.created_at,'personal_distribution','توزيع أرباح مدفوع',null,-t.total
 from public.transactions t where t.kind='profit_distribution' and coalesce(t.cashbox_user_id,t.created_by)=uid
  and t.profit_settlement_id is null and coalesce(t.cash_purpose,'') not in('expense','external_profit')
  and exists(select 1 from solar_private.profit_balance_adjustments a where a.owner_id=uid)
 ), rows as($new$);
 definition:=replace(definition,'coalesce(c.value,0) settled', $new$coalesce(c.value,case when s.kind='external_adjustment' then
   (select a.checkpoint_offset from solar_private.profit_balance_adjustments a where a.owner_id=uid and a.id=substr(s.source_key,12)::uuid) end,0) settled$new$);
 definition:=replace(definition,$old$'value',value,'settled',settled,$old$,
 $new$'value',case when kind='personal_distribution' then 0 else value end,
  'settled',case when kind='personal_distribution' then settled-value else settled end,$new$);
 definition:=replace(definition,$old$'deleted',deleted) order by date,key)$old$,
 $new$'deleted',deleted) || case when kind='external_adjustment' then
  jsonb_build_object('adjustment',(select solar_private.profit_adjustment_receipt(a) from solar_private.profit_balance_adjustments a where a.id=substr(key,12)::uuid and a.owner_id=uid))
  when kind='personal_distribution' then jsonb_build_object('checkpointValue',value)
  else '{}'::jsonb end order by date,key)$new$);
 execute definition;

 -- Company totals describe actual business earnings. Personal ledger entries
 -- appear only when the administrator or employee opens one owner's report.
 definition:=pg_get_functiondef('solar_private.profit_balance(jsonb)'::regprocedure);
 definition:=replace(definition,' ), period_rows as materialized(', $new$ where not all_owners or x.value->>'kind' not in ('external_adjustment','personal_distribution')
 ), period_rows as materialized($new$);
 definition:=replace(definition,$old$'earned',(select coalesce(sum((row_data->>'value')::numeric),0) from period_rows),$old$,
 $new$'earned',(select coalesce(sum((row_data->>'value')::numeric),0) from period_rows where row_data->>'kind'<>'external_adjustment'),
   'adjustments',(select coalesce(sum((row_data->>'value')::numeric),0) from period_rows where row_data->>'kind'='external_adjustment'),$new$);
 definition:=replace(definition,'coalesce(sum(solar_private.retained_profit(id)),0) from owners',
 $new$coalesce(sum(solar_private.retained_profit(id)),0) - case when all_owners then
   (select coalesce(sum(a.delta),0) from solar_private.profit_balance_adjustments a join owners o on o.id=a.owner_id)
   else 0 end from owners$new$);
 execute definition;

 definition:=pg_get_functiondef('solar_private.profit_workspace(text,uuid,jsonb)'::regprocedure);
 definition:=replace(definition,$old$ if action='balance' then$old$,
 $new$ if action='external_adjust' then return solar_private.adjust_personal_profit(request_id,payload);end if;
 if action='balance' then$new$);
 definition:=replace(definition,$old$'ownerName',(select solar_private.user_name(display_name,username,honorific) from public.profiles where id=uid),'canRequest'$old$,
 $new$'externalAdjustmentToken',case when p.is_admin and exists (select 1 from public.profiles where id=uid and active)
     then solar_private.profit_adjustment_token(uid,solar_private.retained_profit(uid)) end,
   'externalAdjustments',case when p.is_admin then (select coalesce(jsonb_agg(solar_private.profit_adjustment_receipt(h.entry) order by h.seq desc),'[]'::jsonb) from (
     select a entry,a.sequence_no seq from solar_private.profit_balance_adjustments a where a.owner_id=uid order by a.sequence_no desc limit 100
   )h) else '[]'::jsonb end,
   'ownerName',(select solar_private.user_name(display_name,username,honorific) from public.profiles where id=uid),'canRequest'$new$);
 definition:=replace(definition,$old$values(r.owner_id,item->>'key',(item->>'value')::numeric,item,r.id)$old$,
 $new$values(r.owner_id,item->>'key',case when item->>'kind'='personal_distribution' then (item->>'checkpointValue')::numeric else (item->>'value')::numeric end,item,r.id)$new$);
 -- A period can omit a downward adjustment that occurred after its end. Do
 -- not use the filter to settle more than today's actual personal balance.
 definition:=replace(definition,$old$  if total<=0 then$old$,$new$  if exists(select 1 from solar_private.profit_balance_adjustments a where a.owner_id=uid) and total>greatest(0,solar_private.retained_profit(uid)) then
   raise exception 'ربح الفترة المختارة يتجاوز الرصيد الشخصي المتبقي بعد التسوية. راجع الكشف لكل الفترات.' using errcode='40001';
  end if;
  if total<=0 then$new$);
 definition:=replace(definition,$old$   if coalesce(payload->>'collectionConfirmed'$old$,
 $new$   if exists(select 1 from solar_private.profit_balance_adjustments a where a.pending_settlement_id=r.id) then
    raise exception 'سُجّلت تسوية خارجية بعد الطلب. ألغِ الطلب أو ارفضه ثم افتح طلباً بالرصيد المحدّث.' using errcode='40001';
   end if;
   if exists(select 1 from solar_private.profit_balance_adjustments a where a.owner_id=r.owner_id)
      and r.profit>greatest(0,solar_private.retained_profit(r.owner_id)) then
    raise exception 'رصيد الأرباح الحالي لا يكفي لهذا الطلب. راجع الكشف وأصدر طلباً جديداً.' using errcode='40001';
   end if;
   if coalesce(payload->>'collectionConfirmed'$new$);
 execute definition;

 -- Preserve the existing full reset's backup, fingerprint, locks, and cleanup.
 definition:=pg_get_functiondef('solar_private.reset_snapshot()'::regprocedure);
 execute replace(definition,'''solar_private.finance_requests''','''solar_private.profit_balance_adjustments'',''solar_private.finance_requests''');
 definition:=pg_get_functiondef('solar_private.lock_reset_tables()'::regprocedure);
 execute replace(definition,'solar_private.finance_requests,','solar_private.profit_balance_adjustments,solar_private.finance_requests,');
 definition:=pg_get_functiondef('public.solar_execute_reset(uuid,uuid,text)'::regprocedure);
 if strpos(definition,'delete from solar_private.finance_requests;')=0 then raise exception 'Review full reset before adding personal profit cleanup';end if;
 execute replace(definition,'delete from solar_private.finance_requests;',
   'delete from solar_private.profit_checkpoints where source_key like ''adjustment:%'' or source_key like ''distribution:%''; delete from solar_private.profit_balance_adjustments where true; delete from solar_private.finance_requests;');
end $patch$;

notify pgrst,'reload schema';
