-- Extend the existing private quote calculator. Existing snapshots are not
-- rewritten, old clients retain one inverter, and RLS/API grants stay intact.
do $migration$
declare
 definition text;
 anchors text[]:=array[
  'day numeric; night numeric; capacity numeric; panels integer:=0; batteries integer:=0;',
  ' capacity:=solar_private.quote_number(',
  '''schema'',3,''markupPercent''',
  '''notes'',left(coalesce(input->>''notes'',''''),2000)',
  'when ''battery'' then batteries else 1 end;',
  '''panelQty'',panels,''batteryQty'',batteries'
 ];
 replacements text[]:=array[
  'day numeric; night numeric; capacity numeric; inverters numeric; panels integer:=0; batteries integer:=0;',
  $replacement$ inverters:=solar_private.quote_number(case when input ? 'inverterQty' then input->>'inverterQty' else '1' end);
 if inverters is null or inverters<1 or inverters<>trunc(inverters) then
  errors:=errors||jsonb_build_array('أدخل عدد الانفيرترات كعدد صحيح من 1 إلى 1000.');
  inverters:=0;
 end if;
 capacity:=solar_private.quote_number($replacement$,
  '''schema'',4,''markupPercent''',
  '''inverterQty'',case when input ? ''inverterQty'' then coalesce(input->>''inverterQty'','''') else ''1'' end,''notes'',left(coalesce(input->>''notes'',''''),2000)',
  'when ''battery'' then batteries else inverters end;',
  '''panelQty'',panels,''batteryQty'',batteries,''inverterQty'',inverters'
 ];
 i integer;
begin
 definition:=pg_get_functiondef('solar_private.prepare_limited_quote(jsonb)'::regprocedure);
 for i in 1..array_length(anchors,1) loop
  if (length(definition)-length(replace(definition,anchors[i],'')))/length(anchors[i])<>1 then
   raise exception 'Review quotation quantity contract at anchor %',i;
  end if;
  definition:=replace(definition,anchors[i],replacements[i]);
 end loop;
 execute definition;
end $migration$;
notify pgrst,'reload schema';
