-- Personal presentation only; existing section order, columns and permissions remain intact.
alter table solar_private.section_layouts add column display_mode text not null default 'groups'
 check(display_mode in('groups','columns'));
create or replace function solar_private.section_layout(action text default 'get',payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.profiles;s solar_private.section_layouts;mobile integer;desktop integer;ordering text[];mode text;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null then raise exception 'غير مسموح' using errcode='42501';end if;
 if action in('save','view') then
  if jsonb_typeof(payload) is distinct from 'object' then raise exception 'اختيار التصميم غير صحيح';end if;
  if action='save' then
   if not(p.is_admin or coalesce(p.permissions->>'layoutCustomize','false')='true') then raise exception 'تخصيص الأقسام يحتاج صلاحية من الإدارة' using errcode='42501';end if;
   if jsonb_typeof(payload->'order') is distinct from 'array' then raise exception 'ترتيب الأقسام غير صحيح';end if;
   mobile:=(payload->>'mobileColumns')::integer;desktop:=(payload->>'desktopColumns')::integer;
   if mobile is null or desktop is null or mobile not between 1 and 7 or desktop not between 1 and 7 or jsonb_array_length(payload->'order')>60 then raise exception 'اختر من عمود واحد إلى سبعة';end if;
   if exists(select 1 from jsonb_array_elements(payload->'order') x where jsonb_typeof(x)<>'string' or trim(both '"' from x::text)!~'^[a-zA-Z]{1,40}$') then raise exception 'أسماء الأقسام غير صحيحة';end if;
   select coalesce(array_agg(x),'{}') into ordering from jsonb_array_elements_text(payload->'order')x;
   if cardinality(ordering)<>(select count(distinct x) from unnest(ordering)x) then raise exception 'القسم مكرر بالترتيب';end if;
  else
   mode:=payload->>'mode';if mode is null or mode not in('groups','columns') then raise exception 'اختر تصميم المجموعات أو الأعمدة';end if;
  end if;
  perform pg_advisory_xact_lock(8766,hashtext(p.id::text));
  select * into s from solar_private.section_layouts where user_id=p.id for update;
  -- Repeating a view choice is safe and never overwrites a newer column/order edit.
  if action='view' and s.display_mode=mode then null;
  else
   if(payload->>'expectedRevision')::bigint is distinct from coalesce(s.revision,0) then raise exception 'تغيّر الترتيب من جهاز آخر؛ حدّث الأقسام وأعد المحاولة' using errcode='PT409';end if;
   if action='view' then
    insert into solar_private.section_layouts(user_id,display_mode,revision) values(p.id,mode,1)
    on conflict(user_id) do update set display_mode=excluded.display_mode,revision=section_layouts.revision+1,updated_at=now() returning * into s;
   else
    insert into solar_private.section_layouts(user_id,mobile_columns,desktop_columns,section_order,revision) values(p.id,mobile,desktop,ordering,1)
    on conflict(user_id) do update set mobile_columns=excluded.mobile_columns,desktop_columns=excluded.desktop_columns,section_order=excluded.section_order,revision=section_layouts.revision+1,updated_at=now() returning * into s;
   end if;
  end if;
 elsif action='get' then select * into s from solar_private.section_layouts where user_id=p.id;
 else raise exception 'إجراء غير صحيح';end if;
 return jsonb_build_object('mode',coalesce(s.display_mode,'groups'),'mobileColumns',coalesce(s.mobile_columns,3),'desktopColumns',coalesce(s.desktop_columns,6),'order',coalesce(s.section_order,'{}'),'revision',coalesce(s.revision,0),'canCustomize',p.is_admin or coalesce(p.permissions->>'layoutCustomize','false')='true');
end $$;
revoke all on function solar_private.section_layout(text,jsonb) from public,anon;
grant execute on function solar_private.section_layout(text,jsonb) to authenticated;
notify pgrst,'reload schema';
