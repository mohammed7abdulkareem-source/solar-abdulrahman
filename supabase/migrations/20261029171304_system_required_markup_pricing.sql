-- Opt-in minimum markup on total frozen system cost. Existing invoices and cash
-- remain untouched; unrestricted pricing stays enabled until an admin changes it.
alter table solar_private.operation_controls
 add column system_free_pricing boolean not null default true,
 add column system_markup_percent smallint not null default 25 check(system_markup_percent in(15,25));
alter table public.transactions
 add column system_min_profit_percent smallint check(system_min_profit_percent in(15,25)),
 add column system_pricing_revision bigint;

create function solar_private.system_pricing_control(request_id uuid,payload jsonb)returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s'as $$
#variable_conflict use_variable
declare actor public.profiles;prior solar_private.finance_requests;control solar_private.operation_controls;free_pricing boolean;percent smallint;reason text;result jsonb;
begin
 select * into actor from public.profiles where id=auth.uid()and active and is_admin and user_type not in('installer','warehouse');
 if actor.id is null then raise exception 'تغيير تسعير المنظومات من صلاحيات الإدارة فقط'using errcode='42501';end if;
 if request_id is null or jsonb_typeof(payload)is distinct from'object'or jsonb_typeof(payload->'freePricing')is distinct from'boolean'or jsonb_typeof(payload->'markupPercent')is distinct from'number'then raise exception 'حدد حالة البيع الحر ونسبة الربح';end if;
 if(payload->>'markupPercent')::numeric not in(15,25)then raise exception 'اختر ربح 15%% أو 25%%';end if;
 free_pricing:=(payload->>'freePricing')::boolean;percent:=(payload->>'markupPercent')::smallint;reason:=trim(coalesce(payload->>'note',''));
 if length(reason)>300 then raise exception 'الملاحظة طويلة';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into prior from solar_private.finance_requests f where f.request_id=system_pricing_control.request_id;
 if found then
  if prior.actor_id=actor.id and prior.action='system_pricing_control'and prior.payload=payload then return prior.response;end if;
  raise exception 'طلب مكرر ببيانات مختلفة'using errcode='PT409';
 end if;
 select * into control from solar_private.operation_controls where id for update;
 if control.revision is distinct from(payload->>'expectedRevision')::bigint then raise exception 'تغيّر تسعير المنظومات؛ حدّث الحالة وأعد التأكيد'using errcode='PT409';end if;
 if(control.system_free_pricing,control.system_markup_percent)is distinct from(free_pricing,percent)then
  update solar_private.operation_controls set system_free_pricing=free_pricing,system_markup_percent=percent,revision=revision+1,updated_at=now(),updated_by=actor.id where id;
  with notices as(
   insert into public.solar_notifications(user_id,event,title,body)
   select p.id,case when free_pricing then'operation_resumed'else'operation_paused'end,
    case when free_pricing then'تشغيل البيع الحر للمنظومات'else'تفعيل حد ربح المنظومات '||percent||'%'end,
    case when free_pricing then'شغّلت الإدارة البيع الحر للمنظومات وألغت حد الربح الإلزامي.'else'أوقفت الإدارة البيع الحر للمنظومات. الربح الكلي لا يقل عن '||percent||'% فوق كلفة المواد المثبتة والمصاريف المعتمدة. يجوز البيع بسعر أعلى.'end||case when reason=''then''else' '||reason end
   from public.profiles p where p.active returning id,user_id
  )insert into solar_private.push_deliveries(notification_id,endpoint)select n.id,s.endpoint from notices n join public.solar_push_subscriptions s on s.user_id=n.user_id;
 end if;
 result:=solar_private.operation_status();
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response)values(request_id,actor.id,'system_pricing_control',payload,result);
 return result;
end $$;
revoke all on function solar_private.system_pricing_control(uuid,jsonb)from public,anon,authenticated;

do $$declare definition text;anchor text;begin
 definition:=pg_get_functiondef('solar_private.operation_status()'::regprocedure);
 anchor:='''revision'',revision,''updatedAt'',updated_at';
 if strpos(definition,anchor)=0 then raise exception 'Review operation status pricing anchor';end if;
 execute replace(definition,anchor,'''systemFreePricing'',system_free_pricing,''systemMarkupPercent'',system_markup_percent,'||anchor);
 definition:=pg_get_functiondef('solar_private.operation_control(uuid,jsonb)'::regprocedure);
 anchor:=' if request_id is null or jsonb_typeof(payload)';
 if strpos(definition,anchor)=0 then raise exception 'Review operation control pricing anchor';end if;
 execute replace(definition,anchor,' if payload->>''kind''=''system_pricing''then return solar_private.system_pricing_control(request_id,payload);end if;'||E'\n'||anchor);
end $$;

-- The trusted posting path still freezes material costs and posts stock/cash.
-- These triggers only stamp the selected policy and validate the final receipt.
create function solar_private.stamp_system_pricing()returns trigger
language plpgsql security definer set search_path=''as $$
declare control solar_private.operation_controls;
begin
 if new.kind<>'system'then return new;end if;
 if tg_op='INSERT'or(new.kind,new.total,new.cost,new.expenses,new.system_min_profit_percent,new.system_pricing_revision)is distinct from(old.kind,old.total,old.cost,old.expenses,old.system_min_profit_percent,old.system_pricing_revision)then
  perform pg_advisory_xact_lock(7311,1);
  select * into control from solar_private.operation_controls where id;
  if control.id is null then raise exception 'تعذر تأكيد تسعير المنظومات';end if;
  new.system_min_profit_percent:=case when not control.system_free_pricing then control.system_markup_percent end;
  new.system_pricing_revision:=case when not control.system_free_pricing then control.revision end;
 end if;
 return new;
end $$;
revoke all on function solar_private.stamp_system_pricing()from public,anon,authenticated;
create trigger solar_system_pricing_stamp before insert or update on public.transactions for each row execute function solar_private.stamp_system_pricing();

create function solar_private.stamp_system_item_pricing()returns trigger
language plpgsql security definer set search_path=''as $$
declare invoice_id bigint;control solar_private.operation_controls;
begin
 if tg_op='UPDATE'and(new.transaction_id,new.product_id,new.qty,new.cost)is not distinct from(old.transaction_id,old.product_id,old.qty,old.cost)then return null;end if;
 invoice_id:=case when tg_op='DELETE'then old.transaction_id else new.transaction_id end;
 if not exists(select 1 from public.transactions where id=invoice_id and kind='system')then return null;end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into control from solar_private.operation_controls where id;
 update public.transactions set system_min_profit_percent=case when not control.system_free_pricing then control.system_markup_percent end,
  system_pricing_revision=case when not control.system_free_pricing then control.revision end
 where id=invoice_id and kind='system'and(system_min_profit_percent,system_pricing_revision)is distinct from
  (case when not control.system_free_pricing then control.system_markup_percent end,case when not control.system_free_pricing then control.revision end);
 return null;
end $$;
revoke all on function solar_private.stamp_system_item_pricing()from public,anon,authenticated;
create trigger solar_system_item_pricing_stamp after insert or update or delete on public.transaction_items for each row execute function solar_private.stamp_system_item_pricing();

create function solar_private.assert_system_pricing(invoice_id bigint)returns void
language plpgsql security definer set search_path=''as $$
declare invoice public.transactions;control solar_private.operation_controls;base_cost numeric;minimum_price numeric;
begin
 select * into invoice from public.transactions where id=invoice_id and kind='system';
 if invoice.id is null or invoice.system_min_profit_percent is null then return;end if;
 select * into control from solar_private.operation_controls where id;
 if control.system_free_pricing then return;end if;
 -- Historical receipts use the percentage accepted when they were priced.
 -- New material/price changes above restamp the current policy. Later expenses
 -- must retain that minimum without silently changing the agreed sale price.
 select round(coalesce(sum(i.qty*i.cost),0),2)+coalesce(invoice.expenses,0)+coalesce(invoice.installation_expenses,0)
 into base_cost from public.transaction_items i where i.transaction_id=invoice.id;
 minimum_price:=ceil(base_cost*(100+invoice.system_min_profit_percent))/100;
 if invoice.total<minimum_price then raise exception 'البيع الحر متوقف: ربح المنظومة الكلي يجب ألا يقل عن %%% فوق الكلفة الكلية. أقل سعر بيع مسموح: % د.ع',invoice.system_min_profit_percent,minimum_price using errcode='PT422';end if;
end $$;
revoke all on function solar_private.assert_system_pricing(bigint)from public,anon,authenticated;

create function solar_private.guard_system_pricing()returns trigger
language plpgsql security definer set search_path=''as $$
declare invoice_id bigint;
begin
 if tg_table_name='transactions'then
  if tg_op='UPDATE'and(new.kind,new.total,new.cost,new.expenses,new.installation_expenses,new.system_min_profit_percent,new.system_pricing_revision)is not distinct from(old.kind,old.total,old.cost,old.expenses,old.installation_expenses,old.system_min_profit_percent,old.system_pricing_revision)then return null;end if;
  invoice_id:=new.id;
 else
  if tg_op='UPDATE'and(new.transaction_id,new.product_id,new.qty,new.cost)is not distinct from(old.transaction_id,old.product_id,old.qty,old.cost)then return null;end if;
  invoice_id:=case when tg_op='DELETE'then old.transaction_id else new.transaction_id end;
 end if;
 perform pg_advisory_xact_lock(7311,1);
 perform solar_private.assert_system_pricing(invoice_id);
 if tg_table_name='transaction_items'and tg_op='UPDATE'then
  if old.transaction_id<>new.transaction_id then perform solar_private.assert_system_pricing(old.transaction_id);end if;
 end if;
 return null;
end $$;
revoke all on function solar_private.guard_system_pricing()from public,anon,authenticated;
create constraint trigger solar_system_pricing_check after insert or update on public.transactions deferrable initially deferred for each row when(new.kind='system')execute function solar_private.guard_system_pricing();
create constraint trigger solar_system_item_pricing_check after insert or update or delete on public.transaction_items deferrable initially deferred for each row execute function solar_private.guard_system_pricing();

-- Give the regular invoice RPC a clear atomic error before returning, and keep
-- its saved nonce response tied to the originally accepted policy on replay.
do $$declare definition text;anchor text;begin
 definition:=pg_get_functiondef('solar_private.invoice_save(uuid,jsonb)'::regprocedure);
 anchor:=' return invoice_result;';
 if strpos(definition,anchor)=0 then raise exception 'Review system price validation anchor';end if;
 execute replace(definition,anchor,$insert$
 if not cached and payload->>'kind'='system'then
  select * into after_row from public.transactions where id=(invoice_result->>'id')::bigint;
  if before_row.id is null or expense_change or(before_row.total,before_row.cost,before_row.expenses,before_row.system_min_profit_percent)is distinct from(after_row.total,after_row.cost,after_row.expenses,after_row.system_min_profit_percent)then
   perform solar_private.assert_system_pricing(after_row.id);
  end if;
  invoice_result:=invoice_result||jsonb_build_object('systemMarkupPercent',after_row.system_min_profit_percent,'systemPricingRevision',after_row.system_pricing_revision);
  update solar_private.invoice_requests set result=invoice_result where invoice_requests.request_id=invoice_save.request_id;
 end if;
$insert$||anchor);
end $$;
notify pgrst,'reload schema';
