-- Business-wide pause switches serialize with invoice writes. Defaults preserve
-- the existing operating state; toggles never change financial rows.
create table solar_private.operation_controls(
 id boolean primary key default true check(id),sale_paused boolean not null default false,system_paused boolean not null default false,purchase_paused boolean not null default false,
 revision bigint not null default 0,updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id)
);
insert into solar_private.operation_controls(id) values(true);
alter table solar_private.operation_controls enable row level security;
revoke all on solar_private.operation_controls from public,anon,authenticated;
create function solar_private.operation_paused(kind text) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select case kind when 'sale' then sale_paused when 'system' then system_paused when 'purchase' then purchase_paused else false end from solar_private.operation_controls where id),false)
$$;
revoke all on function solar_private.operation_paused(text) from public,anon,authenticated;
create function solar_private.operation_status() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not exists(select 1 from public.profiles where id=auth.uid() and active) then raise exception 'الدخول بحساب فعال مطلوب' using errcode='42501';end if;
 return(select jsonb_build_object('sale',sale_paused,'system',system_paused,'purchase',purchase_paused,'revision',revision,'updatedAt',updated_at) from solar_private.operation_controls where id);
end$$;
create function public.solar_operation_status() returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.operation_status()$$;
revoke all on function solar_private.operation_status(),public.solar_operation_status() from public,anon;
grant execute on function solar_private.operation_status(),public.solar_operation_status() to authenticated;
create function solar_private.operation_control(request_id uuid,payload jsonb) returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
#variable_conflict use_variable
declare p public.profiles;prior solar_private.finance_requests;s solar_private.operation_controls;kind text;paused boolean;label text;result jsonb;reason text;begin
 select * into p from public.profiles where id=auth.uid() and active and is_admin and user_type not in('warehouse','installer');
 if p.id is null then raise exception 'التحكم بالإيقاف من صلاحيات الإدارة فقط' using errcode='42501';end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' or jsonb_typeof(payload->'paused') is distinct from 'boolean' then raise exception 'طلب غير صحيح';end if;
 kind:=payload->>'kind';paused:=(payload->>'paused')::boolean;reason:=trim(coalesce(payload->>'note',''));
 if kind is null or kind not in('sale','system','purchase') or length(reason)>300 then raise exception 'حدد القسم بصورة صحيحة';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into prior from solar_private.finance_requests f where f.request_id=operation_control.request_id;
 if found then if prior.actor_id=p.id and prior.action='operation_control' and prior.payload=payload then return prior.response;end if;raise exception 'طلب مكرر ببيانات مختلفة' using errcode='PT409';end if;
 select * into s from solar_private.operation_controls where id for update;
 if s.revision is distinct from(payload->>'expectedRevision')::bigint then raise exception 'تغيّرت حالة العمل؛ حدّث الصفحة أولاً' using errcode='PT409';end if;
 if solar_private.operation_paused(kind) is distinct from paused then
  update solar_private.operation_controls set sale_paused=case when kind='sale' then paused else sale_paused end,system_paused=case when kind='system' then paused else system_paused end,purchase_paused=case when kind='purchase' then paused else purchase_paused end,revision=revision+1,updated_at=now(),updated_by=p.id where id;
  label:=case kind when 'sale' then 'بيع الجملة' when 'system' then 'بيع المنظومات' else 'الشراء' end;
  with notices as(insert into public.solar_notifications(user_id,event,title,body)
   select id,case when paused then 'operation_paused' else 'operation_resumed' end,case when paused then label||' متوقف مؤقتًا' else 'تم استئناف '||label end,
   case when paused then 'أوقفت الإدارة '||label||' مؤقتًا.' else 'أعادت الإدارة تشغيل '||label||'.' end||case when reason='' then '' else ' '||reason end from public.profiles where active returning id,user_id)
  insert into solar_private.push_deliveries(notification_id,endpoint) select n.id,sub.endpoint from notices n join public.solar_push_subscriptions sub on sub.user_id=n.user_id;
 end if;
 result:=solar_private.operation_status();
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response) values(request_id,p.id,'operation_control',payload,result);return result;
end$$;
create function public.solar_operation_control(request_id uuid,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select solar_private.operation_control(request_id,payload)$$;
revoke all on function solar_private.operation_control(uuid,jsonb),public.solar_operation_control(uuid,jsonb) from public,anon;
grant execute on function solar_private.operation_control(uuid,jsonb),public.solar_operation_control(uuid,jsonb) to authenticated;
do $$declare old_check text;begin
 select pg_get_expr(conbin,conrelid) into old_check from pg_constraint where conrelid='public.solar_notifications'::regclass and conname='solar_notifications_event_check';
 if old_check is null then raise exception 'notification constraint missing';end if;
 alter table public.solar_notifications drop constraint solar_notifications_event_check;
 execute 'alter table public.solar_notifications add constraint solar_notifications_event_check check(('||old_check||') or event in(''operation_paused'',''operation_resumed''))';
end$$;
create function solar_private.guard_operation_insert() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.kind in('sale','system','purchase') then
  perform pg_advisory_xact_lock(7311,1);
  if solar_private.operation_paused(new.kind) then raise exception '%',case when new.kind='purchase' then 'الشراء متوقف مؤقتًا بقرار الإدارة' else 'البيع متوقف مؤقتًا بقرار الإدارة' end using errcode='PT423';end if;
 end if;return new;
end$$;
revoke all on function solar_private.guard_operation_insert() from public,anon,authenticated;
create trigger solar_operation_insert_guard before insert on public.transactions for each row execute function solar_private.guard_operation_insert();
do $$declare def text;needle text;begin
 def:=pg_get_functiondef('solar_private.invoice_save_v333(uuid,jsonb)'::regprocedure);
 needle:=' invoice_id:=nullif(payload->>''invoiceId'','''')::bigint;';
 if strpos(def,needle)=0 then raise exception 'invoice pause anchor missing';end if;
 -- The check also prevents growing or repricing an existing invoice while paused.
 def:=replace(def,needle,E' if solar_private.operation_paused(kind) then raise exception ''%'' ,case when kind=''purchase'' then ''الشراء متوقف مؤقتًا بقرار الإدارة'' else ''البيع متوقف مؤقتًا بقرار الإدارة'' end using errcode=''PT423'';end if;\n'||needle);
 execute def;
end$$;
notify pgrst,'reload schema';
-- Legacy insert/update paths cannot bypass an operation pause.
create or replace function solar_private.guard_operation_insert() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.kind in('sale','system','purchase') and(tg_op='INSERT' or(new.kind,new.total,new.subtotal,new.party_id,new.cash) is distinct from(old.kind,old.total,old.subtotal,old.party_id,old.cash)) then
  perform pg_advisory_xact_lock(7311,1);
  if solar_private.operation_paused(new.kind) then raise exception '%',case when new.kind='purchase' then 'الشراء متوقف مؤقتًا بقرار الإدارة' else 'البيع متوقف مؤقتًا بقرار الإدارة' end using errcode='PT423';end if;
 end if;return new;
end$$;
drop trigger solar_operation_insert_guard on public.transactions;
create trigger solar_operation_insert_guard before insert or update on public.transactions for each row execute function solar_private.guard_operation_insert();
create function solar_private.guard_operation_items() returns trigger language plpgsql security definer set search_path='' as $$declare kind text;begin
 if tg_op='INSERT' or(new.transaction_id,new.product_id,new.qty,new.price) is distinct from(old.transaction_id,old.product_id,old.qty,old.price) then
  perform pg_advisory_xact_lock(7311,1);
  select t.kind into kind from public.transactions t where t.id=new.transaction_id;
  if solar_private.operation_paused(kind) then raise exception '%',case when kind='purchase' then 'الشراء متوقف مؤقتًا بقرار الإدارة' else 'البيع متوقف مؤقتًا بقرار الإدارة' end using errcode='PT423';end if;
 end if;return new;
end$$;
revoke all on function solar_private.guard_operation_items() from public,anon,authenticated;
create trigger solar_operation_items_guard before insert or update on public.transaction_items for each row execute function solar_private.guard_operation_items();
