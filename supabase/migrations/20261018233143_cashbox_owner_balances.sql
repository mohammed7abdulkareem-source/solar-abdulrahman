-- Calculate every visible owner's currency balances in the same protected read
-- as the ledger; selecting a date or owner never changes these current totals.
do $$declare def text;needle text;begin
 select pg_get_functiondef('solar_private.cash_workspace(jsonb)'::regprocedure) into def;
 needle:='with scoped as materialized(select m.* from solar_private.cash_movements() m where uid is null or m.owner_id=uid),';
 if strpos(def,needle)=0 then raise exception 'Review cash workspace scoping';end if;
 def:=replace(def,needle,'with movements as materialized(select m.* from solar_private.cash_movements() m where p.is_admin or m.owner_id=p.id), owner_totals as(select owner_id,coalesce(sum(delta) filter(where currency=''IQD''),0) iqd,coalesce(sum(delta) filter(where currency=''USD''),0) usd from movements group by owner_id), scoped as materialized(select m.* from movements m where uid is null or m.owner_id=uid),');
 needle:='jsonb_build_object(''id'',o.id,''name'',coalesce(o.display_name,o.username,''مستخدم''))';
 if strpos(def,needle)=0 then raise exception 'Review cash owner response';end if;
 def:=replace(def,needle,'jsonb_build_object(''id'',o.id,''name'',coalesce(o.display_name,o.username,''مستخدم''),''IQD'',coalesce(totals.iqd,0),''USD'',coalesce(totals.usd,0))');
 needle:='from public.profiles o where o.active and o.user_type not in (''installer'',''warehouse'') and(p.is_admin or o.id=p.id)';
 if strpos(def,needle)=0 then raise exception 'Review visible cash owners';end if;
 def:=replace(def,needle,'from public.profiles o left join owner_totals totals on totals.owner_id=o.id where o.active and o.user_type not in (''installer'',''warehouse'') and(p.is_admin or o.id=p.id)');execute def;
end $$;
notify pgrst,'reload schema';
