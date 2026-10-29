-- A reviewed profit may all be allocated to the supplier. Zero is a deliberate
-- user share, while missing, negative and non-finite inputs remain invalid.
alter table solar_private.profit_settlements drop constraint profit_settlements_check1;
alter table solar_private.profit_settlements add constraint profit_settlements_check1
 check(status<>'approved' or(share>=0 and share<=profit and receipt is not null));

do $migration$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('solar_private.cash_record(text,text,uuid,jsonb)'::regprocedure);
 needle:='or amount<=0 or amount>1e12';
 if strpos(definition,needle)=0 then raise exception 'Cash correction amount contract missing';end if;
 definition:=replace(definition,needle,'or amount<0 or (amount=0 and coalesce(ctx->>''type'','''')<>''settlement'') or amount>1e12');
 definition:=replace(definition,'أدخل مبلغًا موجبًا وبيانًا للحركة لا يتجاوز 2000 حرف','أدخل مبلغًا صحيحًا وبيانًا للحركة؛ حصة التسوية تقبل صفرًا');
 execute definition;
 definition:=pg_get_functiondef('solar_private.profit_workspace(text,uuid,jsonb)'::regprocedure);
 needle:='not(amount>0 and amount<=r.profit and amount<=1000000000000)';
 if strpos(definition,needle)=0 then raise exception 'Profit approval amount contract missing';end if;
 definition:=replace(definition,needle,'not(amount>=0 and amount<=r.profit and amount<=1000000000000)');
 definition:=replace(definition,'حدد حصة موجبة بالدينار لا تتجاوز ربح الطلب','حدد حصة بصفر أو مبلغ موجب بالدينار لا يتجاوز ربح الطلب');
 execute definition;
end$migration$;
notify pgrst,'reload schema';
