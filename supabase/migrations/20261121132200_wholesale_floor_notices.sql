-- Dynamic purchase-cost floors are resolved at sale. The notification only
-- records an active manual floor; it never snapshots a company's private cost.
do $migration$
declare definition text:=pg_get_functiondef('solar_private.notify_wholesale_prices(bigint[])'::regprocedure);
 old constant text:='''minPrice'',s.minimum_price,''enabled'',s.enabled';
begin
 if strpos(definition,old)=0 then raise exception 'Review the wholesale price notice projection';end if;
 execute replace(definition,old,$new$'minPrice',case when s.enabled and s.minimum_price>0 then s.minimum_price end,'enabled',s.enabled$new$);
end $migration$;
