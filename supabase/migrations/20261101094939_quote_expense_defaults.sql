-- Shared quotation expense defaults; no sales, stock, cash or draft rewrites.
create table solar_private.quote_expense_defaults(
 id boolean primary key default true check(id),
 per_panel numeric not null default 45000 check(per_panel between 0 and 1e10 and round(per_panel,2)=per_panel),
 crane numeric not null default 40000 check(crane between 0 and 1e10 and round(crane,2)=crane),
 worker numeric not null default 25000 check(worker between 0 and 1e10 and round(worker,2)=worker),
 programmer numeric not null default 40000 check(programmer between 0 and 1e10 and round(programmer,2)=programmer),
 delivery numeric not null default 25000 check(delivery between 0 and 1e10 and round(delivery,2)=delivery),
 electrical numeric not null default 200000 check(electrical between 0 and 1e10 and round(electrical,2)=electrical),
 commission numeric not null default 75000 check(commission between 0 and 1e10 and round(commission,2)=commission),
 revision bigint not null default 1 check(revision>0),updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id)
);
alter table solar_private.quote_expense_defaults enable row level security;
revoke all on solar_private.quote_expense_defaults from public,anon,authenticated;
insert into solar_private.quote_expense_defaults(id)values(true);
create table solar_private.quote_expense_defaults_audit(
 request_id uuid primary key,actor_id uuid not null references public.profiles(id),before_row jsonb not null,after_row jsonb not null,created_at timestamptz not null default now()
);
alter table solar_private.quote_expense_defaults_audit enable row level security;
revoke all on solar_private.quote_expense_defaults_audit from public,anon,authenticated;

create function solar_private.quote_defaults_state(full_details boolean,can_manage boolean)returns jsonb
language sql stable security definer set search_path=''as $$
 select jsonb_build_object('revision',revision,'updatedAt',updated_at,'canManage',can_manage)||case when full_details then
 jsonb_build_object('perPanel',per_panel::text,'expenses',jsonb_build_object('crane',crane::text,'worker',worker::text,'programmer',programmer::text,'delivery',delivery::text,'electrical',electrical::text,'commission',commission::text))else'{}'::jsonb end
 from solar_private.quote_expense_defaults where id
$$;
revoke all on function solar_private.quote_defaults_state(boolean,boolean)from public,anon,authenticated;

create function solar_private.quote_defaults(action text,request_id uuid default null,payload jsonb default '{}')returns jsonb
language plpgsql security definer set search_path=''set lock_timeout='5s'as $$
#variable_conflict use_variable
declare actor public.profiles;full_details boolean;can_manage boolean;prior solar_private.finance_requests;settings solar_private.quote_expense_defaults;previous jsonb;result jsonb;amounts numeric[]:='{}';key text;value numeric;expected numeric;
begin
 select * into actor from public.profiles where id=auth.uid()and active and user_type not in('warehouse','installer');
 if actor.id is null or not coalesce(actor.is_admin or case when actor.permissions?'tahseel'then actor.permissions->'tahseel'='true'::jsonb else actor.permissions->'system'='true'::jsonb end,false)then raise exception 'ليس لديك صلاحية التحصيل'using errcode='42501';end if;
 full_details:=coalesce(actor.is_admin or actor.permissions->'tahseelFull'='true'::jsonb,false);
 can_manage:=full_details and coalesce(actor.is_admin or actor.permissions->'tahseelDefaults'='true'::jsonb,false);
 if action='get'then return solar_private.quote_defaults_state(full_details,can_manage);end if;
 if action is distinct from'save'then raise exception 'عملية غير معروفة'using errcode='PT422';end if;
 if not can_manage then raise exception 'حفظ مصاريف التحصيل للجميع يحتاج صلاحية الإدارة أو الصلاحية المخصصة'using errcode='42501';end if;
 if request_id is null or jsonb_typeof(payload)is distinct from'object'or jsonb_typeof(payload->'expenses')is distinct from'object'then raise exception 'بيانات المصاريف غير صحيحة'using errcode='PT422';end if;
 expected:=solar_private.quote_number(payload->>'expectedRevision',9223372036854775807);
 if expected is null or expected<1 or trunc(expected)<>expected then raise exception 'حدّث المصاريف العامة قبل الحفظ'using errcode='PT422';end if;
 foreach key in array array['perPanel','crane','worker','programmer','delivery','electrical','commission']loop
  value:=solar_private.quote_number(case when key='perPanel'then payload->>'perPanel'else payload->'expenses'->>key end,1e10);
  if value is null or round(value,2)<>value then raise exception 'أدخل جميع المصاريف بأرقام صحيحة غير سالبة وبحد أقصى منزلتين عشريتين'using errcode='PT422';end if;
  amounts:=array_append(amounts,value);
 end loop;
 perform pg_advisory_xact_lock(7311,1);
 select * into prior from solar_private.finance_requests f where f.request_id=quote_defaults.request_id;
 if found then
  if prior.actor_id=actor.id and prior.action='quote_expense_defaults'and prior.payload=payload then return prior.response;end if;
  raise exception 'طلب مكرر ببيانات مختلفة'using errcode='PT409';
 end if;
 select * into settings from solar_private.quote_expense_defaults where id for update;
 if settings.revision is distinct from expected::bigint then raise exception 'تغيّرت المصاريف العامة من مستخدم آخر. حدّث القيم وراجعها قبل الحفظ'using errcode='PT409';end if;
 if(settings.per_panel,settings.crane,settings.worker,settings.programmer,settings.delivery,settings.electrical,settings.commission)is distinct from(amounts[1],amounts[2],amounts[3],amounts[4],amounts[5],amounts[6],amounts[7])then
  previous:=to_jsonb(settings);
  update solar_private.quote_expense_defaults set per_panel=amounts[1],crane=amounts[2],worker=amounts[3],programmer=amounts[4],delivery=amounts[5],electrical=amounts[6],commission=amounts[7],revision=revision+1,updated_at=clock_timestamp(),updated_by=actor.id where id returning * into settings;
  insert into solar_private.quote_expense_defaults_audit(request_id,actor_id,before_row,after_row)values(request_id,actor.id,previous,to_jsonb(settings));
 end if;
 result:=solar_private.quote_defaults_state(true,true);
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response)values(request_id,actor.id,'quote_expense_defaults',payload,result);
 return result;
end $$;
revoke all on function solar_private.quote_defaults(text,uuid,jsonb)from public,anon,authenticated;
grant execute on function solar_private.quote_defaults(text,uuid,jsonb)to authenticated;
create function public.solar_quote_defaults(action text default 'get',request_id uuid default null,payload jsonb default '{}')returns jsonb
language sql security invoker set search_path=''as $$select solar_private.quote_defaults(action,request_id,payload)$$;
revoke all on function public.solar_quote_defaults(text,uuid,jsonb)from public,anon,authenticated;
grant execute on function public.solar_quote_defaults(text,uuid,jsonb)to authenticated;

-- Keep the trusted limited-user calculator, including unit costs and 15%, and
-- read only the configured expense amounts. Old clients still work unchanged.
do $migration$
declare definition text;anchors text[];replacements text[];i integer;
begin
 definition:=pg_get_functiondef('solar_private.prepare_limited_quote(jsonb)'::regprocedure);
 anchors:=array[
 'expense_cost numeric; total_cost numeric; sale_price numeric; selected_id numeric; product record;',
 ' day:=solar_private.quote_number(',
 '''schema'',4,''markupPercent''',
 '''perPanel'',''30000'',''expenses'',jsonb_build_object(''crane'',''25000'',''worker'',''20000'',''programmer'',''35000'',''delivery'',''25000'',''electrical'',''150000'')',
 'expense_cost:=panels*30000+255000;',
 '''materials'',materials,''markupPercent'',15'
 ];
 replacements:=array[
 'expense_cost numeric; total_cost numeric; sale_price numeric; selected_id numeric; product record;expense_settings solar_private.quote_expense_defaults;',
 $replacement$ select * into expense_settings from solar_private.quote_expense_defaults where id;
 if expense_settings.id is null then raise exception 'تعذر تحميل مصاريف التحصيل';end if;
 if input?'expectedExpenseDefaultsRevision'and solar_private.quote_number(input->>'expectedExpenseDefaultsRevision',9223372036854775807)is distinct from expense_settings.revision then raise exception 'تغيّرت مصاريف التحصيل. حدّث السعر قبل حفظ المسودة'using errcode='PT409';end if;
 day:=solar_private.quote_number($replacement$,
 '''schema'',5,''markupPercent''',
 '''expenseDefaultsRevision'',expense_settings.revision,''perPanel'',expense_settings.per_panel::text,''expenses'',jsonb_build_object(''crane'',expense_settings.crane::text,''worker'',expense_settings.worker::text,''programmer'',expense_settings.programmer::text,''delivery'',expense_settings.delivery::text,''electrical'',expense_settings.electrical::text,''commission'',expense_settings.commission::text)',
 'expense_cost:=round(panels*expense_settings.per_panel+expense_settings.crane+expense_settings.worker+expense_settings.programmer+expense_settings.delivery+expense_settings.electrical+expense_settings.commission,2);',
 '''materials'',materials,''expenseDefaultsRevision'',expense_settings.revision,''markupPercent'',15'
 ];
 for i in 1..array_length(anchors,1)loop
  if(length(definition)-length(replace(definition,anchors[i],'')))/length(anchors[i])<>1 then raise exception 'Review shared quote expenses contract at anchor %',i;end if;
  definition:=replace(definition,anchors[i],replacements[i]);
 end loop;
 execute definition;
end $migration$;
notify pgrst,'reload schema';
