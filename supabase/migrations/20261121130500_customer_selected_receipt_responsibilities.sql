-- Operational responsibility is independent of the original invoice, cashbox and seller.
create table solar_private.customer_receipt_responsibility (
 transaction_id bigint primary key references public.transactions(id) on delete cascade,
 customer_id bigint not null references public.customers(id),
 owner_id uuid not null references public.profiles(id),
 assigned_by uuid references public.profiles(id),
 recorded_at timestamptz not null default clock_timestamp(),
 database_actor name not null default session_user,
 administrative_note text,
 request_id uuid not null,
 check(assigned_by is not null and administrative_note is null or
       assigned_by is null and nullif(btrim(administrative_note),'') is not null)
);
create index customer_receipt_responsible_owner on solar_private.customer_receipt_responsibility(owner_id,customer_id);
alter table solar_private.customer_receipt_responsibility enable row level security;
revoke all on solar_private.customer_receipt_responsibility from public, anon, authenticated;

create function solar_private.receipt_responsible(invoice_id bigint, original_creator uuid) returns uuid
language sql stable security definer set search_path='' as $$
 select coalesce((select r.owner_id from solar_private.customer_receipt_responsibility r where r.transaction_id=invoice_id),original_creator)
$$;
revoke all on function solar_private.receipt_responsible(bigint,uuid) from public,anon,authenticated;

create function solar_private.customer_transfer_receipts(customer_id bigint) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if solar_private.role_name() is distinct from 'admin' then
  raise exception 'نقل مسؤولية الوصولات متاح للأدمن فقط' using errcode='42501';
 end if;
 if not exists(select 1 from public.customers c where c.id=customer_id and c.active) then
  raise exception 'تعذّر تأكيد حساب العميل' using errcode='PT404';
 end if;
 with matching as (
  select t.id,t.receipt_no,t.kind,t.created_at,t.total,t.installation_status,
         coalesce(r.owner_id,t.created_by) as current_owner,r.request_id
  from solar_private.customer_movement_links() l
  join public.transactions t on t.id=l.transaction_id and t.kind in ('sale','system')
  left join solar_private.customer_receipt_responsibility r on r.transaction_id=t.id
  where l.customer_id=customer_transfer_receipts.customer_id
 )
 select jsonb_build_object(
  'receipts',coalesce(jsonb_agg(jsonb_build_object(
    'id',m.id,'receiptNo',m.receipt_no,'kind',m.kind,'date',m.created_at,
    'ownerId',m.current_owner,'ownerName',solar_private.user_name(p.display_name,p.username,p.honorific),
    'total',m.total,'currency','IQD','closed',m.kind='system' and coalesce(m.installation_status,'')='closed'
   ) order by m.created_at desc,m.id desc),'[]'),
  'receiptToken',md5(coalesce(jsonb_agg(jsonb_build_array(m.id,m.current_owner,m.request_id,m.installation_status,m.total) order by m.id),'[]')::text)
 ) into result from matching m left join public.profiles p on p.id=m.current_owner;
 return result;
end $$;
create function public.solar_customer_transfer_receipts(customer_id bigint) returns jsonb
language sql stable security invoker set search_path='' as $$select solar_private.customer_transfer_receipts(customer_id)$$;
revoke all on function solar_private.customer_transfer_receipts(bigint),public.solar_customer_transfer_receipts(bigint) from public,anon,authenticated;
grant execute on function solar_private.customer_transfer_receipts(bigint),public.solar_customer_transfer_receipts(bigint) to authenticated;

-- Called only from the audited transfer writer while holding the customer and shared
-- financial locks. Every selected row must still resolve to this exact account.
create function solar_private.assign_customer_receipts(customer_id bigint, destination uuid, actor uuid, intent uuid, payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare selection jsonb:=payload->'receiptIds'; available jsonb; ids bigint[]; prior_owners jsonb; n integer;
begin
 if jsonb_typeof(selection) is distinct from 'array' then
  raise exception 'اختر الوصولات من قائمة العميل' using errcode='22023';
 end if;
 if exists(select 1 from jsonb_array_elements(selection) v where jsonb_typeof(v)<>'number' or v::text !~ '^-?[0-9]+$') then
  raise exception 'قائمة الوصولات غير صحيحة' using errcode='22023';
 end if;
 select array_agg(value::bigint order by value::bigint),count(distinct value) into ids,n from jsonb_array_elements_text(selection);
 if n<>jsonb_array_length(selection) then
  raise exception 'يوجد وصل مكرر في الاختيار' using errcode='22023';
 end if;
 perform t.id from public.transactions t where t.id=any(ids) order by t.id for update;
 available:=solar_private.customer_transfer_receipts(customer_id);
 if (available->>'receiptToken') is distinct from (payload->>'receiptToken') then
  raise exception 'تغيّرت قائمة الوصولات. حدّث بيانات التحويل وأعد الاختيار.' using errcode='PT409';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',(r->>'id')::bigint,'ownerId',r->'ownerId') ||
  case when prev.administrative_note is null then '{}'::jsonb else jsonb_build_object('previousAdministrativeAssignment',to_jsonb(prev)) end order by (r->>'id')::bigint),'[]') into prior_owners
 from jsonb_array_elements(available->'receipts') r
 left join solar_private.customer_receipt_responsibility prev on prev.transaction_id=(r->>'id')::bigint
 where (r->>'id')::bigint=any(ids);
 if jsonb_array_length(prior_owners)<>n then
  raise exception 'اختر وصولات بيع مرتبطة بهذا العميل فقط' using errcode='22023';
 end if;
 if exists(select 1 from jsonb_array_elements(prior_owners) r where (r->>'ownerId')::uuid=destination) then
  raise exception 'أحد الوصولات المختارة يتبع المستخدم المحدد بالفعل' using errcode='22023';
 end if;
 insert into solar_private.customer_receipt_responsibility(transaction_id,customer_id,owner_id,assigned_by,request_id)
 select v.id,customer_id,destination,actor,intent from unnest(ids) v(id)
 on conflict(transaction_id) do update set customer_id=excluded.customer_id,owner_id=excluded.owner_id,assigned_by=excluded.assigned_by,request_id=excluded.request_id,
  recorded_at=excluded.recorded_at,database_actor=excluded.database_actor,administrative_note=excluded.administrative_note;
 return prior_owners;
end $$;
revoke all on function solar_private.assign_customer_receipts(bigint,uuid,uuid,uuid,jsonb) from public,anon,authenticated;

do $migration$
declare definition text; old text;
begin
 definition:=pg_get_functiondef('solar_private.customer_save(text,uuid,jsonb)'::regprocedure);
 if md5(definition)<>'cec5dc8d1aaa0ccd65141045ca478595' then raise exception 'Review existing customer writer before extending transfer';end if;
 old:='  return prior.result;';
 definition:=replace(definition,old,$replay$
  if action='transfer_owner' and exists(
   select 1 from jsonb_array_elements_text(prior.result->'receiptIds') v(id)
   where not exists(select 1 from solar_private.customer_receipt_responsibility r where r.transaction_id=v.id::bigint
                    and r.customer_id=prior.customer_id and r.owner_id=(prior.result->>'ownerId')::uuid and r.request_id=prior.request_id)
  ) then raise exception 'تغيّرت مسؤولية أحد الوصولات بعد التحويل. حدّث الكشف.' using errcode='PT409';end if;
  return prior.result;$replay$);
 old:='   if c.owner_id=owner then raise exception ''هذا المستخدم مسؤول عن العميل حالياً'' using errcode=''22023''; end if;
   update public.customers set owner_id=owner where id=c.id;';
 definition:=replace(definition,old,$assign$
   entries:='[]'::jsonb;
   if payload ? 'receiptIds' then
    entries:=solar_private.assign_customer_receipts(c.id,owner,p.id,request_id,payload);
    result:=result||jsonb_build_object('receiptIds',payload->'receiptIds','receiptCount',jsonb_array_length(entries));
   end if;
   if c.owner_id is distinct from owner then
    update public.customers set owner_id=owner where id=c.id;
   elsif jsonb_array_length(entries)=0 then
    raise exception 'هذا المستخدم مسؤول عن العميل حالياً. اختر وصولات لإسنادها إليه.' using errcode='22023';
   end if;$assign$);
 old:='''ownerName'',before_record->>''ownerName''),';
 definition:=replace(definition,old,$audit$'ownerName',before_record->>'ownerName')||case when payload ? 'receiptIds' then jsonb_build_object('receiptOwners',entries) else '{}'::jsonb end,$audit$);
 if strpos(definition,'entries:=solar_private.assign_customer_receipts')=0 or strpos(definition,'''receiptOwners'',entries')=0 then
  raise exception 'Failed to install invoice selection and audit';end if;
 -- An ordinary profile edit now omits ownerId. Preserve even unassigned or
 -- archived-owner accounts in that case; old clients can still explicitly select an owner.
 old:=$legacy$   owner:=case when p.is_admin then coalesce(nullif(payload->>'ownerId','')::uuid,c.owner_id,p.id) else p.id end;
   if not exists(select 1 from public.profiles where id=owner and active and user_type not in ('installer','warehouse') for share) then raise exception 'اختر مستخدماً مسؤولاً فعالاً';end if;$legacy$;
 if strpos(definition,old)=0 then raise exception 'Review omitted owner handling';end if;
 definition:=replace(definition,old,'   if payload ? ''ownerId'' then'||chr(10)||old||chr(10)||'   else owner:=c.owner_id; end if;');
 execute definition;
end $migration$;
notify pgrst,'reload schema';
