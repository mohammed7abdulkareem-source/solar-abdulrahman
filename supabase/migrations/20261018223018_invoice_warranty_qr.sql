-- Public QR certificates expose only customer-copy data, never internal costs/accounts.
alter table public.transactions add column warranty jsonb not null default '{"enabled":false}',add column warranty_token uuid unique,add column warranty_revision bigint not null default 0;
create table solar_private.warranty_certificates(token uuid primary key,invoice_id bigint unique references public.transactions(id) on delete set null,document jsonb not null,updated_at timestamptz not null default now());
create table solar_private.warranty_revisions(id bigint generated always as identity primary key,token uuid not null references solar_private.warranty_certificates(token),actor_id uuid references public.profiles(id),document jsonb not null,created_at timestamptz not null default now());
alter table solar_private.warranty_certificates enable row level security;
alter table solar_private.warranty_revisions enable row level security;
revoke all on solar_private.warranty_certificates,solar_private.warranty_revisions from public,anon,authenticated;
create function solar_private.warranty_guard() returns trigger language plpgsql set search_path='' as $$begin
 if current_user in('authenticated','anon') and((tg_op='INSERT' and(new.warranty_revision<>0 or new.warranty_token is not null or new.warranty<>'{"enabled":false}'::jsonb)) or(tg_op='UPDATE' and(new.warranty_revision is distinct from old.warranty_revision or new.warranty is distinct from old.warranty or new.warranty_token is distinct from old.warranty_token))) then raise exception 'استخدم خيار ضمان الفاتورة المحمي' using errcode='42501';end if;return new;
end $$;
create trigger solar_warranty_guard before insert or update on public.transactions for each row execute function solar_private.warranty_guard();
revoke all on function solar_private.warranty_guard() from public,anon,authenticated;
create function solar_private.warranty_term(term jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare duration numeric;unit text;begin
 if term is null or term='null'::jsonb then return '{"duration":0,"unit":"months"}';end if;
 if jsonb_typeof(term)<>'object' then raise exception 'مدة ضمان غير صحيحة';end if;
 duration:=coalesce(nullif(term->>'duration','')::numeric,0);unit:=coalesce(term->>'unit','months');
 if unit not in('days','months','years') or duration::text in('NaN','Infinity','-Infinity') or duration<>round(duration) or duration<0 or duration>(case unit when 'days' then 36500 when 'months' then 1200 else 100 end) then raise exception 'أدخل مدة ضمان صحيحة بالأيام أو الأشهر أو السنوات';end if;
 return jsonb_build_object('duration',duration,'unit',unit);
end $$;
revoke all on function solar_private.warranty_term(jsonb) from public,anon,authenticated;
create function solar_private.warranty_apply(invoice_id bigint,policy jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare t public.transactions;enabled boolean;normalized jsonb;lines jsonb:='[]';items jsonb:='[]';line record;term jsonb;maintenance jsonb;token uuid;doc jsonb;has_term boolean:=false;old_doc jsonb;
begin
 select * into t from public.transactions where id=invoice_id and kind in('sale','system') for update;
 if t.id is null then raise exception 'فاتورة البيع غير موجودة';end if;
 if policy is null then
  policy:=t.warranty;
  policy:=jsonb_set(policy,'{items}',(select coalesce(jsonb_agg(x),'[]') from jsonb_array_elements(coalesce(policy->'items','[]'))x where exists(select 1 from public.transaction_items i where i.transaction_id=t.id and i.product_id=(x->>'id')::bigint)));
 end if;
 if jsonb_typeof(policy)<>'object' or coalesce(policy->>'enabled','false') not in('true','false') then raise exception 'بيانات الضمان غير صحيحة';end if;
 enabled:=coalesce((policy->>'enabled')::boolean,false);token:=t.warranty_token;
 if enabled then
  if jsonb_typeof(coalesce(policy->'items','[]'))<>'array' or jsonb_array_length(coalesce(policy->'items','[]'))>500 or length(coalesce(policy->>'notes',''))>2000 then raise exception 'راجع مواد الضمان والملاحظات';end if;
  if exists(select 1 from jsonb_array_elements(coalesce(policy->'items','[]'))x where not exists(select 1 from public.transaction_items i where i.transaction_id=t.id and i.product_id=(x->>'id')::bigint)) or exists(select 1 from jsonb_array_elements(coalesce(policy->'items','[]'))x group by x->>'id' having count(*)>1) then raise exception 'ضمان المواد يجب أن يطابق مواد الوصل بدون تكرار';end if;
  maintenance:=solar_private.warranty_term(policy->'maintenance');has_term:=(maintenance->>'duration')::numeric>0;
 else maintenance:='{"duration":0,"unit":"months"}';end if;
 for line in select * from public.transaction_items where transaction_id=t.id order by id loop
  term:=null;
  if enabled then select solar_private.warranty_term(x) into term from jsonb_array_elements(coalesce(policy->'items','[]'))x where(x->>'id')::bigint=line.product_id;end if;
  term:=coalesce(term,'{"duration":0,"unit":"months"}');has_term:=has_term or(term->>'duration')::numeric>0;
  lines:=lines||jsonb_build_array(jsonb_build_object('id',line.product_id)||term);
  items:=items||jsonb_build_array(jsonb_build_object('id',line.product_id,'name',line.product_name,'brand',line.brand_name,'category',line.category,'qty',line.qty,'price',case when t.kind='sale' then line.price end,'term',term));
 end loop;
 if enabled and not has_term then raise exception 'حدد مدة واحدة على الأقل لضمان مادة أو للصيانة';end if;
 normalized:=jsonb_build_object('enabled',enabled,'items',lines,'maintenance',maintenance,'notes',case when enabled then coalesce(policy->>'notes','') else '' end);
 if token is null and enabled then token:=gen_random_uuid();end if;
 update public.transactions set warranty=normalized,warranty_token=token,warranty_revision=warranty_revision+case when warranty is distinct from normalized then 1 else 0 end where id=t.id and(warranty is distinct from normalized or warranty_token is distinct from token);
 if token is not null then
  doc:=jsonb_build_object('token',token,'invoiceId',t.id,'receiptNo',t.receipt_no,'kind',t.kind,'customer',coalesce(t.party_name,'زبون نقدي'),'date',(t.created_at at time zone 'Asia/Baghdad')::date,'total',t.total,'currency','IQD','items',items,'warranty',normalized)||case when t.kind='system' then jsonb_build_object('phone',t.customer_phone,'address',t.customer_address,'installer',(select coalesce(display_name,username) from public.profiles where id=t.installer_id),'installDate',t.install_date,'installTime',t.install_time) else '{}'::jsonb end;
  select wc.document into old_doc from solar_private.warranty_certificates wc where wc.token=token;
  if old_doc is distinct from doc then
   insert into solar_private.warranty_certificates(token,invoice_id,document) values(token,t.id,doc) on conflict on constraint warranty_certificates_pkey do update set document=excluded.document,updated_at=clock_timestamp();
   insert into solar_private.warranty_revisions(token,actor_id,document) values(token,auth.uid(),doc);
  end if;
 end if;
 return jsonb_build_object('warranty',normalized,'warrantyToken',token,'date',t.created_at,'pricingRevision',(select pricing_revision from public.transactions where id=t.id),'warrantyRevision',(select warranty_revision from public.transactions where id=t.id));
end $$;
revoke all on function solar_private.warranty_apply(bigint,jsonb) from public,anon,authenticated;
-- Insert warranty posting into the existing atomic invoice write before its retry cache.
-- Old clients preserve the policy on edits; new clients send the optional policy.
do $$declare def text;needle text;begin
 select pg_get_functiondef('solar_private.invoice_save_v333(uuid,jsonb)'::regprocedure) into def;
 needle:='insert into solar_private.invoice_requests(request_id,user_id,payload,result) values(request_id,p.id,payload,result);';
 if strpos(def,needle)=0 then raise exception 'Review atomic invoice save integration';end if;
 def:=replace(def,needle,'if kind in (''sale'',''system'') then if existing and payload ? ''warranty'' and coalesce((payload->>''expectedWarrantyRevision'')::bigint,-1)<>invoice.warranty_revision then raise exception ''تغيّر ضمان الفاتورة؛ افتح التعديل مجدداً'' using errcode=''40001'';end if;result:=result||solar_private.warranty_apply(invoice_id,payload->''warranty'');end if; '||needle);
 execute def;
end $$;
create function solar_private.warranty_manage(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
#variable_conflict use_variable
declare p public.profiles;t public.transactions;items jsonb;token text;prior solar_private.finance_requests;result jsonb;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in('installer','warehouse') then raise exception 'لا تملك صلاحية ضمان الفواتير' using errcode='42501';end if;
 if action is null or action not in('get','save') or jsonb_typeof(payload) is distinct from 'object' then raise exception 'طلب غير صحيح';end if;
 if action='save' then
  if request_id is null then raise exception 'رقم طلب الحفظ مطلوب';end if;
  perform pg_advisory_xact_lock(7311,1);
  select * into prior from solar_private.finance_requests f where f.request_id=warranty_manage.request_id;
  if found then if prior.actor_id=p.id and prior.action='warranty' and prior.payload=payload then return prior.response;end if;raise exception 'طلب مكرر ببيانات مختلفة' using errcode='40001';end if;
 end if;
 select * into t from public.transactions where id=(payload->>'id')::bigint;
 if t.id is null or t.kind not in('sale','system') or not(p.is_admin or(coalesce(t.cashbox_user_id,t.created_by)=p.id and coalesce(p.permissions->>t.kind,'false')='true')) then raise exception 'هذه الفاتورة للإدارة أو صاحبها بصلاحية البيع' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',i.product_id,'name',i.product_name,'qty',i.qty) order by i.id),'[]') into items from public.transaction_items i where transaction_id=t.id;
 token:=md5(to_jsonb(t)::text||items::text);
 if action='get' then return jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'date',t.created_at,'party',t.party_name,'items',items,'warranty',t.warranty,'warrantyToken',t.warranty_token,'pricingRevision',t.pricing_revision,'warrantyRevision',t.warranty_revision,'expectedToken',token);end if;
 if payload->>'expectedToken' is distinct from token then raise exception 'تغيرت الفاتورة أو ضمانها؛ افتحها مجدداً' using errcode='40001';end if;
 result:=solar_private.warranty_apply(t.id,payload->'warranty');
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response) values(request_id,p.id,'warranty',payload,result);
 return result;
end $$;
create function public.solar_warranty_manage(action text,request_id uuid default null,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select solar_private.warranty_manage(action,request_id,payload)$$;
revoke all on function solar_private.warranty_manage(text,uuid,jsonb),public.solar_warranty_manage(text,uuid,jsonb) from public,anon;
grant execute on function solar_private.warranty_manage(text,uuid,jsonb),public.solar_warranty_manage(text,uuid,jsonb) to authenticated;
create function solar_private.warranty_status(start_date date,term jsonb) returns jsonb language sql stable set search_path='' as $$
 with expiry as(select case when(term->>'duration')::numeric>0 then(start_date+make_interval(days=>case when term->>'unit'='days' then(term->>'duration')::integer else 0 end,months=>case when term->>'unit'='months' then(term->>'duration')::integer else 0 end,years=>case when term->>'unit'='years' then(term->>'duration')::integer else 0 end))::date end ends)
 select jsonb_build_object('covered',ends is not null,'active',coalesce(ends>(now() at time zone 'Asia/Baghdad')::date,false),'endsExclusive',ends,'lastCoveredDate',ends-1,'daysRemaining',greatest(0,ends-(now() at time zone 'Asia/Baghdad')::date)) from expiry
$$;
revoke all on function solar_private.warranty_status(date,jsonb) from public,anon,authenticated;
create function solar_private.warranty_verify(certificate_token uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c solar_private.warranty_certificates;doc jsonb;enabled boolean;items jsonb;begin
 select * into c from solar_private.warranty_certificates where token=certificate_token;
 if c.token is null then return null;end if;
 doc:=c.document;enabled:=c.invoice_id is not null and coalesce((doc->'warranty'->>'enabled')::boolean,false);
 select coalesce(jsonb_agg(x||jsonb_build_object('status',solar_private.warranty_status((doc->>'date')::date,case when enabled then x->'term' else '{"duration":0,"unit":"months"}'::jsonb end))),'[]') into items from jsonb_array_elements(doc->'items')x;
 return doc||jsonb_build_object('voided',c.invoice_id is null,'enabled',enabled,'checkedDate',(now() at time zone 'Asia/Baghdad')::date,'items',items,'updatedAt',c.updated_at,'maintenanceStatus',solar_private.warranty_status((doc->>'date')::date,case when enabled then doc->'warranty'->'maintenance' else '{"duration":0,"unit":"months"}'::jsonb end));
end $$;
create function public.solar_warranty_verify(certificate_token uuid) returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.warranty_verify(certificate_token)$$;
revoke all on function solar_private.warranty_verify(uuid),public.solar_warranty_verify(uuid) from public;
grant execute on function solar_private.warranty_verify(uuid),public.solar_warranty_verify(uuid) to anon,authenticated;
notify pgrst,'reload schema';
