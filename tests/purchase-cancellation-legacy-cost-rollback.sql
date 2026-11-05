begin;
-- These are isolated archived purchase fixtures; no active stock/cash is posted.
insert into solar_private.deleted_sales(invoice_id,invoice,items) values
(-3998801,'{"id":-3998801,"kind":"purchase","source_currency":"USD","exchange_rate":1500,"purchase_stock":[{"id":-3998800,"qty":2,"cost":1000000,"basis":{}}]}',
 '[{"transaction_id":-3998801,"product_id":-3998800,"qty":2,"source_price":1000,"price":1500000,"landed_cost":1500000}]'),
(-3998802,'{"id":-3998802,"kind":"purchase","source_currency":"IQD","exchange_rate":1,"purchase_stock":[{"id":-3998800,"qty":4,"cost":1250000,"basis":{"lastPurchase":{"invoiceId":-3998801}}}]}',
 '[{"transaction_id":-3998802,"product_id":-3998800,"qty":4,"source_price":500000,"price":500000,"landed_cost":500000}]'),
(-3998803,'{"id":-3998803,"kind":"sale","source_currency":"USD","exchange_rate":1500,"purchase_stock":[]}','[]'),
(-3998804,'{"id":-3998804,"kind":"purchase","source_currency":"USD","exchange_rate":1500,"purchase_stock":[{"id":-3998800,"qty":2,"cost":1000000,"basis":{}}]}','[]');
do $$declare parts jsonb;before_hash text;after_hash text;begin
 before_hash:=(select md5(jsonb_agg(to_jsonb(d)order by invoice_id)::text)from solar_private.deleted_sales d where invoice_id between -3998804 and -3998801);
 parts:=solar_private.inventory_currency_parts(-3998800,'{"lastPurchase":{"invoiceId":-3998801}}',1250000);
 assert parts='{"usd":500,"iqd":500000}'::jsonb,'Archived USD purchase lost original currency parts';
 parts:=solar_private.inventory_currency_parts(-3998800,'{"lastPurchase":{"invoiceId":-3998802}}',875000);
 assert parts='{"usd":250,"iqd":500000}'::jsonb,'Nested archived purchase did not preserve weighted components';
 parts:=solar_private.inventory_currency_parts(-3998800,'{"currencyComponents":{"usd":12.5,"iqd":345}}',99999);
 assert parts='{"usd":12.5,"iqd":345}'::jsonb,'Explicit frozen components changed';
 begin
  perform solar_private.inventory_currency_parts(-3998800,'{"lastPurchase":{"invoiceId":-3998803}}',1250000);
  assert false,'A non-purchase archive supplied a costing source';
 exception when raise_exception then assert SQLERRM='تعذر ربط أصل كلفة المادة بفاتورة الشراء';end;
 begin
  perform solar_private.inventory_currency_parts(-3998800,'{"lastPurchase":{"invoiceId":-3998899}}',1250000);
  assert false,'Missing archive supplied a costing source';
 exception when raise_exception then assert SQLERRM='تعذر ربط أصل كلفة المادة بفاتورة الشراء';end;
 begin
  perform solar_private.inventory_currency_parts(-3998800,'{"lastPurchase":{"invoiceId":-3998804}}',1250000);
  assert false,'Incomplete archived purchase supplied currency components';
 exception when raise_exception then assert SQLERRM='مصدر كلفة المادة غير مكتمل';end;
 begin
  perform solar_private.inventory_currency_parts(-3998800,'{"lastPurchase":{"invoiceId":-3998801}}',1200000);
  assert false,'Archive fallback bypassed frozen book cost consistency';
 exception when raise_exception then assert SQLERRM='تحتاج كلفة المادة مراجعة حركات الإرجاع قبل اعتماد الصرف';end;
 after_hash:=(select md5(jsonb_agg(to_jsonb(d)order by invoice_id)::text)from solar_private.deleted_sales d where invoice_id between -3998804 and -3998801);
 assert after_hash=before_hash,'Reading historical currency components changed archive';
 assert not has_function_privilege('anon','solar_private.inventory_currency_parts(bigint,jsonb,numeric,integer)','execute');
 assert not has_function_privilege('authenticated','solar_private.inventory_currency_parts(bigint,jsonb,numeric,integer)','execute');
end$$;
\echo PASS nested archived purchase costing sources, USD/IQD components, immutable history, private ACL, missing/wrong-kind/incomplete archive and frozen cost guards
rollback;
