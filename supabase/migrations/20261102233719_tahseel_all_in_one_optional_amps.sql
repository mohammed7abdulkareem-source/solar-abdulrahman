-- In the new ALL IN ONE mode the daytime or nighttime value may be omitted.
-- A manual panel count still takes precedence; the standard quote is untouched.
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $migration$
declare
 definition text;
 anchor text:='  if day is null or night is null or day+night<=0 then errors:=errors||jsonb_build_array(''أدخل الأمبير النهاري والليلي بشكل صحيح.''); end if;';
 replacement text:=$text$  if (coalesce(input->>'day','')<>'' and day is null) or (coalesce(input->>'night','')<>'' and night is null) or coalesce(day,0)+coalesce(night,0)<=0 then
   errors:=errors||jsonb_build_array('أدخل الأمبير النهاري أو الليلي بشكل صحيح، أو حدّد عدد الألواح.');
  end if;$text$;
begin
 definition:=pg_get_functiondef('solar_private.prepare_all_in_one_quote(jsonb)'::regprocedure);
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then
  raise exception 'Review the ALL IN ONE amp validation before migration';
 end if;
 execute replace(definition,anchor,replacement);
end $migration$;
notify pgrst,'reload schema';
