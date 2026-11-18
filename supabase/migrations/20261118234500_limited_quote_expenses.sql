-- Select the applicable seven quotation expenses in memory. Shared settings and
-- saved quotes are never rewritten by a preview or by listing an old draft.
create function solar_private.limited_quote_expenses(input jsonb)
returns solar_private.quote_expense_defaults
language plpgsql stable security invoker set search_path='' as $$
declare
 settings solar_private.quote_expense_defaults;
 field text;
 amount numeric;
 amounts jsonb := '{}';
begin
 select * into settings from solar_private.quote_expense_defaults where id;
 if not found then raise exception 'تعذر تحميل مصاريف التحصيل'; end if;
 if input ? 'expenseOverride' and jsonb_typeof(input->'expenseOverride') is distinct from 'boolean' then
  raise exception 'اختيار مصاريف العرض غير صحيح' using errcode='PT422';
 end if;
 if not (input @> '{"expenseOverride":true}') then return settings; end if;

 if jsonb_typeof(input->'expenses') is distinct from 'object' then
  raise exception 'أدخل جميع مصاريف العرض' using errcode='PT422';
 end if;
 foreach field in array array['perPanel','crane','worker','programmer','delivery','electrical','commission'] loop
  amount:=solar_private.quote_number(case when field='perPanel' then input->>'perPanel' else input->'expenses'->>field end,1e10);
  if amount is null or round(amount,2)<>amount then
   raise exception 'أدخل جميع مصاريف العرض بأرقام غير سالبة وبحد أقصى منزلتين عشريتين' using errcode='PT422';
  end if;
  amounts:=amounts||jsonb_build_object(case when field='perPanel' then 'per_panel' else field end,amount);
 end loop;
 return jsonb_populate_record(settings,amounts);
end
$$;
revoke all on function solar_private.limited_quote_expenses(jsonb) from public,anon,authenticated;

-- Both protected calculators use the same selected expenses before their
-- existing quantity, material cost, fixed 15%, and expected-revision logic.
do $$
declare
 calculator regprocedure;
 definition text;
 old_read constant text:='select * into expense_settings from solar_private.quote_expense_defaults where id;';
 old_projection constant text:='safe:=f-''expenses''-''perPanel'';';
 old_get constant text:='return solar_private.quote_defaults_state(full_details,can_manage);';
begin
 foreach calculator in array array['solar_private.prepare_limited_quote(jsonb)'::regprocedure,
                                   'solar_private.prepare_all_in_one_quote(jsonb)'::regprocedure] loop
  definition:=pg_get_functiondef(calculator);
  if strpos(definition,old_read)=0 or strpos(definition,old_projection)=0 then
   raise exception 'Unexpected quotation calculator definition: %',calculator;
  end if;
  definition:=replace(definition,old_read,'expense_settings:=solar_private.limited_quote_expenses(input);');
  -- At this point f contains only customer fields and expenses. Every product
  -- is appended afterwards with its cost redacted from the safe projection.
  definition:=replace(definition,old_projection,
   'f:=f||jsonb_build_object(''expenseOverride'',input @> ''{"expenseOverride":true}''); safe:=f;');
  execute definition;
 end loop;

 definition:=pg_get_functiondef('solar_private.quote_defaults(text,uuid,jsonb)'::regprocedure);
 if strpos(definition,old_get)=0 then raise exception 'Unexpected quotation defaults read'; end if;
 execute replace(definition,old_get,'return solar_private.quote_defaults_state(true,can_manage);');
end
$$;
