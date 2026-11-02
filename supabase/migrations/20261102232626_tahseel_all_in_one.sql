-- Add a separate, trusted calculation path for an ALL IN ONE quote.
-- Existing quote snapshots, standard calculations, grants and RLS are unchanged.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $$begin
 if to_regprocedure('solar_private.prepare_all_in_one_quote(jsonb)') is not null then
  raise exception 'Review the existing ALL IN ONE quotation function before migration';
 end if;
end$$;

-- This invoker function can only be called by the existing private calculator,
-- which runs after solar_private.limited_quote has checked the current user.
create function solar_private.prepare_all_in_one_quote(input jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 f jsonb; safe jsonb; errors jsonb:='[]'; materials jsonb:='[]'; item jsonb;
 day numeric; night numeric; devices numeric; manual_panels numeric; panel_text text; panels integer:=0;
 product_key text; label text; category_pattern text; amount numeric; unit_cost numeric; material_cost numeric:=0;
 expense_cost numeric; total_cost numeric; sale_price numeric; selected_id numeric; product record;
 expense_settings solar_private.quote_expense_defaults;
begin
 select * into expense_settings from solar_private.quote_expense_defaults where id;
 if expense_settings.id is null then raise exception 'تعذر تحميل مصاريف التحصيل'; end if;
 if input?'expectedExpenseDefaultsRevision' and solar_private.quote_number(input->>'expectedExpenseDefaultsRevision',9223372036854775807) is distinct from expense_settings.revision then
  raise exception 'تغيّرت مصاريف التحصيل. حدّث السعر قبل حفظ المسودة' using errcode='PT409';
 end if;
 day:=solar_private.quote_number(input->>'day'); night:=solar_private.quote_number(input->>'night');
 panel_text:=coalesce(input->>'allInOnePanelQty','');
 if panel_text<>'' then
  manual_panels:=solar_private.quote_number(panel_text);
  if manual_panels is null or manual_panels<1 or manual_panels<>trunc(manual_panels) then
   errors:=errors||jsonb_build_array('أدخل عدد الألواح كعدد صحيح من 1 إلى 1000.');
  else panels:=manual_panels::integer; end if;
  if (coalesce(input->>'day','')<>'' and day is null) or (coalesce(input->>'night','')<>'' and night is null) then
   errors:=errors||jsonb_build_array('أدخل الأمبير النهاري والليلي بشكل صحيح.');
  end if;
 else
  if day is null or night is null or day+night<=0 then errors:=errors||jsonb_build_array('أدخل الأمبير النهاري والليلي بشكل صحيح.'); end if;
  if day is not null then panels:=ceil(day*100/215); end if;
 end if;
 devices:=solar_private.quote_number(case when input?'allInOneQty' then input->>'allInOneQty' else '1' end);
 if devices is null or devices<1 or devices<>trunc(devices) then
  errors:=errors||jsonb_build_array('أدخل عدد أجهزة ALL IN ONE كعدد صحيح من 1 إلى 1000.'); devices:=0;
 end if;
 f:=jsonb_build_object('schema',5,'systemType','all_in_one','markupPercent','15',
  'customer',left(coalesce(input->>'customer',''),160),'phone',left(coalesce(input->>'phone',''),40),
  'day',coalesce(input->>'day',''),'night',coalesce(input->>'night',''),
  'allInOneQty',case when input?'allInOneQty' then coalesce(input->>'allInOneQty','') else '1' end,'allInOnePanelQty',panel_text,
  'notes',left(coalesce(input->>'notes',''),2000),'expenseDefaultsRevision',expense_settings.revision,
  'perPanel',expense_settings.per_panel::text,'expenses',jsonb_build_object('crane',expense_settings.crane::text,'worker',expense_settings.worker::text,'programmer',expense_settings.programmer::text,'delivery',expense_settings.delivery::text,'electrical',expense_settings.electrical::text,'commission',expense_settings.commission::text));
 safe:=f-'expenses'-'perPanel';
 foreach product_key in array array['panel','allInOne'] loop
  amount:=case product_key when 'panel' then panels else devices end;
  label:=case product_key when 'panel' then 'ألواح 600W' else 'جهاز ALL IN ONE' end;
  category_pattern:=case product_key when 'panel' then 'ألواح|الواح|panel' else 'all[[:space:]_-]*in[[:space:]_-]*one' end;
  item:=null; unit_cost:=0;
  if amount>0 then
   selected_id:=solar_private.quote_number(input->product_key->>'id',9223372036854775807);
   select p.id,p.name,p.cost,p.category,coalesce(b.name,'') as brand into product
   from public.products p left join public.brands b on b.id=p.brand_id
   where p.id=selected_id and p.category ~* category_pattern;
   if not found then errors:=errors||jsonb_build_array('اختر مادة '||label||'.');
   else
    item:=jsonb_build_object('id',product.id,'name',product.name,'brand',product.brand,'cost',product.cost::text);
    if product.cost is null or product.cost<=0 then errors:=errors||jsonb_build_array('سعر مادة '||product.name||' غير متاح؛ راجع المسؤول.');
    else unit_cost:=product.cost; end if;
   end if;
  end if;
  f:=f||jsonb_build_object(product_key,item);
  safe:=safe||jsonb_build_object(product_key,case when item is null then null else item-'cost' end);
  material_cost:=material_cost+round(amount*unit_cost,2);
  materials:=materials||jsonb_build_array(jsonb_build_object('key',product_key,'label',label,'qty',amount,'name',coalesce(item->>'name',label),'brand',coalesce(item->>'brand','')));
 end loop;
 expense_cost:=round(panels*expense_settings.per_panel+expense_settings.crane+expense_settings.worker+expense_settings.programmer+expense_settings.delivery+expense_settings.electrical+expense_settings.commission,2);
 total_cost:=material_cost+expense_cost; sale_price:=total_cost+round(total_cost*0.15,2);
 return jsonb_build_object('payload',f,'safe',safe,'result',jsonb_build_object('panelQty',panels,'batteryQty',0,'inverterQty',0,'allInOneQty',devices,'batteryCapacity',null,'materials',materials,'expenseDefaultsRevision',expense_settings.revision,'markupPercent',15,'price',case when jsonb_array_length(errors)=0 then sale_price else null end,'errors',errors));
end $$;
revoke all on function solar_private.prepare_all_in_one_quote(jsonb) from public,anon,authenticated;

-- Route only the newly selected type; the legacy standard branch stays byte-for-byte
-- the same. Abort instead of overwriting an unexpected production definition.
do $migration$
declare definition text; anchor text:=
 ' if input is null or jsonb_typeof(input)<>''object'' or octet_length(input::text)>65536 then raise exception ''بيانات العرض غير صحيحة''; end if;';
begin
 definition:=pg_get_functiondef('solar_private.prepare_limited_quote(jsonb)'::regprocedure);
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then
  raise exception 'Review quotation validation contract before migration';
 end if;
 definition:=replace(definition,anchor,anchor||E'\n'||$branch$
 if coalesce(input->>'systemType','standard') not in ('standard','all_in_one') then raise exception 'نوع المنظومة غير صحيح'; end if;
 if input->>'systemType'='all_in_one' then return solar_private.prepare_all_in_one_quote(input); end if;$branch$);
 execute definition;
end $migration$;
notify pgrst,'reload schema';
