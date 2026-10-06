-- Limited quotations use trusted product costs, shop expenses and a fixed 15%.
-- Privileged implementation stays private; the public entry point is an invoker.
create or replace function solar_private.quote_number(value text, maximum numeric default 1000)
returns numeric language plpgsql immutable set search_path='' as $$
declare n numeric;
begin
 if value is null or length(value)>40 or value !~ '^([0-9]+(\.[0-9]*)?|\.[0-9]+)$' then return null; end if;
 n:=value::numeric; if n<0 or n>maximum then return null; end if; return n;
end $$;
revoke all on function solar_private.quote_number(text,numeric) from public,anon,authenticated;

create or replace function solar_private.prepare_limited_quote(input jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 f jsonb; safe jsonb; errors jsonb:='[]'; materials jsonb:='[]'; item jsonb;
 day numeric; night numeric; capacity numeric; panels integer:=0; batteries integer:=0;
 product_key text; label text; category_pattern text; amount numeric; unit_cost numeric; material_cost numeric:=0;
 expense_cost numeric; total_cost numeric; sale_price numeric; selected_id numeric; product record;
begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>65536 then raise exception 'بيانات العرض غير صحيحة'; end if;
 day:=solar_private.quote_number(input->>'day');night:=solar_private.quote_number(input->>'night');
 capacity:=solar_private.quote_number(coalesce(input->>'batteryCapacity',case when input->>'schema'='1' then '15' else '' end));
 if day is null or night is null or day+night<=0 then errors:=errors||jsonb_build_array('أدخل الأمبير النهاري والليلي بشكل صحيح.');end if;
 if day is not null then panels:=ceil(day*100/215);end if;
 if capacity is null or capacity not in (5,7.5,10,15,25,30) then
  capacity:=null;if night>0 then errors:=errors||jsonb_build_array('اختر سعة البطارية لحساب عدد البطاريات.');end if;
 elsif night is not null then batteries:=ceil(night/capacity);end if;
 f:=jsonb_build_object('schema',3,'markupPercent','15','customer',left(coalesce(input->>'customer',''),160),'phone',left(coalesce(input->>'phone',''),40),'day',coalesce(input->>'day',''),'night',coalesce(input->>'night',''),'batteryCapacity',coalesce(capacity::text,''),'notes',left(coalesce(input->>'notes',''),2000),'perPanel','30000','expenses',jsonb_build_object('crane','25000','worker','20000','programmer','35000','delivery','25000','electrical','150000'));
 safe:=f-'expenses'-'perPanel';
 foreach product_key in array array['panel','battery','inverter'] loop
  amount:=case product_key when 'panel' then panels when 'battery' then batteries else 1 end;
  label:=case product_key when 'panel' then 'ألواح 600W' when 'battery' then 'بطارية '||coalesce(capacity::text,'')||' كيلو' else 'انفيرتر' end;
  category_pattern:=case product_key when 'panel' then 'ألواح|الواح|panel' when 'battery' then 'بطاري|batter' else 'انفيرتر|إنفيرتر|inverter|all in one' end;
  item:=null;unit_cost:=0;
  if amount>0 then
   selected_id:=solar_private.quote_number(input->product_key->>'id',9223372036854775807);
   select p.id,p.name,p.cost,p.category,coalesce(b.name,'') as brand into product from public.products p left join public.brands b on b.id=p.brand_id where p.id=selected_id and p.category ~* category_pattern;
   if not found then errors:=errors||jsonb_build_array('اختر مادة '||label||'.');
   else
    item:=jsonb_build_object('id',product.id,'name',product.name,'brand',product.brand,'cost',product.cost::text);
    if product.cost is null or product.cost<=0 then errors:=errors||jsonb_build_array('سعر مادة '||product.name||' غير متاح؛ راجع المسؤول.');else unit_cost:=product.cost;end if;
   end if;
  end if;
  f:=f||jsonb_build_object(product_key,item);safe:=safe||jsonb_build_object(product_key,case when item is null then null else item-'cost' end);
  material_cost:=material_cost+round(amount*unit_cost,2);
  materials:=materials||jsonb_build_array(jsonb_build_object('key',product_key,'label',label,'qty',amount,'name',coalesce(item->>'name',label),'brand',coalesce(item->>'brand','')));
 end loop;
 expense_cost:=panels*30000+255000;total_cost:=material_cost+expense_cost;sale_price:=total_cost+round(total_cost*0.15,2);
 return jsonb_build_object('payload',f,'safe',safe,'result',jsonb_build_object('panelQty',panels,'batteryQty',batteries,'batteryCapacity',capacity,'materials',materials,'markupPercent',15,'price',case when jsonb_array_length(errors)=0 then sale_price else null end,'errors',errors));
end $$;
revoke all on function solar_private.prepare_limited_quote(jsonb) from public,anon,authenticated;

create or replace function solar_private.limited_quote(action text, quote_payload jsonb default '{}', quote_id uuid default null, expected_revision integer default null, page_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare me public.profiles; prepared jsonb; row public.solar_quotes; answer jsonb:='[]'; affected integer;
begin
 if auth.uid() is null then raise insufficient_privilege using message='يجب تسجيل الدخول';end if;
 select * into me from public.profiles where id=auth.uid();
 if not found or me.active is not true or coalesce(me.user_type,'') in ('warehouse','installer') or not coalesce(me.is_admin or case when me.permissions ? 'tahseel' then me.permissions->'tahseel'='true'::jsonb else me.permissions->'system'='true'::jsonb end,false) then raise insufficient_privilege using message='ليس لديك صلاحية التحصيل';end if;
 if action='preview' then return solar_private.prepare_limited_quote(quote_payload)->'result';end if;
 if action='list' then
  if page_offset is null or page_offset<0 then raise exception 'صفحة غير صحيحة';end if;
  for row in select * from public.solar_quotes where user_id=auth.uid() order by updated_at desc,id offset page_offset limit 100 loop
   prepared:=solar_private.prepare_limited_quote(row.payload);
   answer:=answer||jsonb_build_array((to_jsonb(row)-'payload')||jsonb_build_object('payload',prepared->'safe','result',prepared->'result'));
  end loop;
  return answer;
 elsif action='save' then
  if quote_id is null then raise exception 'معرف المسودة مطلوب';end if;
  prepared:=solar_private.prepare_limited_quote(quote_payload);
  if expected_revision is null then
   insert into public.solar_quotes(id,user_id,payload) values(quote_id,auth.uid(),prepared->'payload') returning * into row;
  else
   update public.solar_quotes set payload=prepared->'payload',revision=revision+1,updated_at=clock_timestamp() where id=quote_id and user_id=auth.uid() and revision=expected_revision returning * into row;
   if not found then raise exception 'تغيرت المسودة. حدّث القائمة وافتح النسخة الحالية.';end if;
  end if;
  return (to_jsonb(row)-'payload')||jsonb_build_object('payload',prepared->'safe','result',prepared->'result');
 elsif action='delete' then
  delete from public.solar_quotes where id=quote_id and user_id=auth.uid() and revision=expected_revision;
  get diagnostics affected=row_count;if affected<>1 then raise exception 'لم تحذف المسودة؛ حدّث القائمة وحاول مجدداً.';end if;
  return jsonb_build_object('ok',true);
 else raise exception 'عملية غير معروفة';end if;
end $$;
revoke all on function solar_private.limited_quote(text,jsonb,uuid,integer,integer) from public,anon,authenticated;
grant execute on function solar_private.limited_quote(text,jsonb,uuid,integer,integer) to authenticated;
create or replace function public.solar_limited_quote(action text, quote_payload jsonb default '{}', quote_id uuid default null, expected_revision integer default null, page_offset integer default 0)
returns jsonb language sql security invoker set search_path='' as $$select solar_private.limited_quote(action,quote_payload,quote_id,expected_revision,page_offset)$$;
revoke all on function public.solar_limited_quote(text,jsonb,uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.solar_limited_quote(text,jsonb,uuid,integer,integer) to authenticated;
-- Full users keep snapshot editing. Limited users must use the checked RPC,
-- including reads, so old snapshots cannot reveal costs after a role downgrade.
create policy quote_full_details on public.solar_quotes as restrictive for all to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and coalesce(p.user_type,'') not in ('installer','warehouse') and (p.is_admin or p.permissions->'tahseelFull'='true'::jsonb)))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active and coalesce(p.user_type,'') not in ('installer','warehouse') and (p.is_admin or p.permissions->'tahseelFull'='true'::jsonb)));
