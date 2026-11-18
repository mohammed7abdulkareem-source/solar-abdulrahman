-- Independent exact-value oracle for the installed V4.1.9 numeric replay.
-- No financial writes; run only against the isolated migrated test database.
-- Includes both original and corrected timelines, not implementation-derived results.
\set ON_ERROR_STOP on
begin;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "500", "price": "100000", "currency": "IQD", "rate": "1", "sourceTotal": "50000000", "expenses": 0}, {"invoiceId": 2, "kind": "purchase", "action": "save", "qty": "600", "price": "130000", "currency": "IQD", "rate": "1", "sourceTotal": "78000000", "expenses": 0}]'::jsonb,2,null);
assert (r->>'qty')::numeric=1100 and (r->>'cost')::numeric=116363.636364,'quantity_500_600_400 before stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'quantity_500_600_400 before usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(116363.636363636363636363636363636363636363636363636363636364))<.00000001,'quantity_500_600_400 before iqd component mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "500", "price": "100000", "currency": "IQD", "rate": "1", "sourceTotal": "50000000", "expenses": 0}, {"invoiceId": 2, "kind": "purchase", "action": "save", "qty": "600", "price": "130000", "currency": "IQD", "rate": "1", "sourceTotal": "78000000", "expenses": 0}]'::jsonb,2,'{"qty": "400", "price": "130000", "sourceTotal": "52000000"}'::jsonb);
assert (r->>'qty')::numeric=900 and (r->>'cost')::numeric=113333.333333,'quantity_500_600_400 after stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'quantity_500_600_400 after usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(113333.333333333333333333333333333333333333333333333333333333))<.00000001,'quantity_500_600_400 after iqd component mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "500", "price": "100000", "currency": "IQD", "rate": "1", "sourceTotal": "50000000", "expenses": 0}, {"invoiceId": 2, "kind": "purchase", "action": "save", "qty": "600", "price": "130000", "currency": "IQD", "rate": "1", "sourceTotal": "78000000", "expenses": 0}, {"invoiceId": 3, "kind": "sale", "action": "save", "qty": "100", "valuationRate": "1"}]'::jsonb,2,null);
assert (r->>'qty')::numeric=1000 and (r->>'cost')::numeric=116363.636364,'quantity_500_600_400_sold before stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'quantity_500_600_400_sold before usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(116363.636363636363636363636363636363636363636363636363636364))<.00000001,'quantity_500_600_400_sold before iqd component mismatch';
assert (r->'states'->'3'->>'cost')::numeric=116363.636364,'quantity_500_600_400_sold before first financial cost mismatch';
assert abs((r->'states'->'3'->>'book')::numeric-(116363.636364))<.00000001,'quantity_500_600_400_sold before first book mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "500", "price": "100000", "currency": "IQD", "rate": "1", "sourceTotal": "50000000", "expenses": 0}, {"invoiceId": 2, "kind": "purchase", "action": "save", "qty": "600", "price": "130000", "currency": "IQD", "rate": "1", "sourceTotal": "78000000", "expenses": 0}, {"invoiceId": 3, "kind": "sale", "action": "save", "qty": "100", "valuationRate": "1"}]'::jsonb,2,'{"qty": "400", "price": "130000", "sourceTotal": "52000000"}'::jsonb);
assert (r->>'qty')::numeric=800 and (r->>'cost')::numeric=113333.333333,'quantity_500_600_400_sold after stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'quantity_500_600_400_sold after usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(113333.333333333333333333333333333333333333333333333333333333))<.00000001,'quantity_500_600_400_sold after iqd component mismatch';
assert (r->'states'->'3'->>'cost')::numeric=113333.333333,'quantity_500_600_400_sold after first financial cost mismatch';
assert abs((r->'states'->'3'->>'book')::numeric-(113333.333333))<.00000001,'quantity_500_600_400_sold after first book mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "10", "price": "100", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 2, "kind": "sale", "action": "save", "qty": "4", "valuationRate": "1"}]'::jsonb,1,null);
assert (r->>'qty')::numeric=6 and (r->>'cost')::numeric=100.000000,'basic_price before stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'basic_price before usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(100))<.00000001,'basic_price before iqd component mismatch';
assert (r->'states'->'2'->>'cost')::numeric=100.000000,'basic_price before first financial cost mismatch';
assert abs((r->'states'->'2'->>'book')::numeric-(100.000000))<.00000001,'basic_price before first book mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "10", "price": "100", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 2, "kind": "sale", "action": "save", "qty": "4", "valuationRate": "1"}]'::jsonb,1,'{"qty": "10", "price": "120", "sourceTotal": "1200"}'::jsonb);
assert (r->>'qty')::numeric=6 and (r->>'cost')::numeric=120.000000,'basic_price after stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'basic_price after usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(120))<.00000001,'basic_price after iqd component mismatch';
assert (r->'states'->'2'->>'cost')::numeric=120.000000,'basic_price after first financial cost mismatch';
assert abs((r->'states'->'2'->>'book')::numeric-(120.000000))<.00000001,'basic_price after first book mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "10", "price": "100", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 2, "kind": "purchase", "action": "save", "qty": "10", "price": "200", "currency": "IQD", "rate": "1", "sourceTotal": "2000", "expenses": 0}, {"invoiceId": 3, "kind": "sale", "action": "save", "qty": "4", "valuationRate": "1"}, {"invoiceId": 4, "kind": "purchase", "action": "save", "qty": "4", "price": "250", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 5, "kind": "sale", "action": "save", "qty": "5", "valuationRate": "1"}]'::jsonb,2,null);
assert (r->>'qty')::numeric=15 and (r->>'cost')::numeric=170.000000,'mixed_price before stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'mixed_price before usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(170))<.00000001,'mixed_price before iqd component mismatch';
assert (r->'states'->'3'->>'cost')::numeric=150.000000,'mixed_price before first financial cost mismatch';
assert abs((r->'states'->'3'->>'book')::numeric-(150.000000))<.00000001,'mixed_price before first book mismatch';
assert (r->'states'->'5'->>'cost')::numeric=170.000000,'mixed_price before second financial cost mismatch';
assert abs((r->'states'->'5'->>'book')::numeric-(170.000000))<.00000001,'mixed_price before second book mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "10", "price": "100", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 2, "kind": "purchase", "action": "save", "qty": "10", "price": "200", "currency": "IQD", "rate": "1", "sourceTotal": "2000", "expenses": 0}, {"invoiceId": 3, "kind": "sale", "action": "save", "qty": "4", "valuationRate": "1"}, {"invoiceId": 4, "kind": "purchase", "action": "save", "qty": "4", "price": "250", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 5, "kind": "sale", "action": "save", "qty": "5", "valuationRate": "1"}]'::jsonb,2,'{"qty": "10", "price": "300", "sourceTotal": "3000"}'::jsonb);
assert (r->>'qty')::numeric=15 and (r->>'cost')::numeric=210.000000,'mixed_price after stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'mixed_price after usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(210))<.00000001,'mixed_price after iqd component mismatch';
assert (r->'states'->'3'->>'cost')::numeric=200.000000,'mixed_price after first financial cost mismatch';
assert abs((r->'states'->'3'->>'book')::numeric-(200.000000))<.00000001,'mixed_price after first book mismatch';
assert (r->'states'->'5'->>'cost')::numeric=210.000000,'mixed_price after second financial cost mismatch';
assert abs((r->'states'->'5'->>'book')::numeric-(210.000000))<.00000001,'mixed_price after second book mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "10", "price": "2", "currency": "USD", "rate": "1000", "sourceTotal": "20", "expenses": 0}, {"invoiceId": 2, "kind": "sale", "action": "save", "qty": "4", "valuationRate": "1500"}]'::jsonb,1,null);
assert (r->>'qty')::numeric=6 and (r->>'cost')::numeric=2000.000000,'historical_rate before stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(2))<.00000001,'historical_rate before usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(0))<.00000001,'historical_rate before iqd component mismatch';
assert (r->'states'->'2'->>'cost')::numeric=3000.000000,'historical_rate before first financial cost mismatch';
assert abs((r->'states'->'2'->>'book')::numeric-(2000.000000))<.00000001,'historical_rate before first book mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "10", "price": "2", "currency": "USD", "rate": "1000", "sourceTotal": "20", "expenses": 0}, {"invoiceId": 2, "kind": "sale", "action": "save", "qty": "4", "valuationRate": "1500"}]'::jsonb,1,'{"qty": "10", "price": "3", "sourceTotal": "30"}'::jsonb);
assert (r->>'qty')::numeric=6 and (r->>'cost')::numeric=3000.000000,'historical_rate after stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(3))<.00000001,'historical_rate after usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(0))<.00000001,'historical_rate after iqd component mismatch';
assert (r->'states'->'2'->>'cost')::numeric=4500.000000,'historical_rate after first financial cost mismatch';
assert abs((r->'states'->'2'->>'book')::numeric-(3000.000000))<.00000001,'historical_rate after first book mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "10", "price": "100", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 2, "kind": "sale", "action": "save", "qty": "4", "valuationRate": "1"}, {"invoiceId": 3, "kind": "purchase", "action": "save", "qty": "6", "price": "200", "currency": "IQD", "rate": "1", "sourceTotal": "1200", "expenses": 0}, {"invoiceId": 2, "kind": "sale", "action": "delete", "qty": 0}]'::jsonb,1,null);
assert (r->>'qty')::numeric=16 and (r->>'cost')::numeric=137.500000,'returned_sale before stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'returned_sale before usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(137.5))<.00000001,'returned_sale before iqd component mismatch';
assert (r->'states'->'2'->>'cost')::numeric=100.000000,'returned_sale before first financial cost mismatch';
assert abs((r->'states'->'2'->>'book')::numeric-(100.000000))<.00000001,'returned_sale before first book mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "10", "price": "100", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 2, "kind": "sale", "action": "save", "qty": "4", "valuationRate": "1"}, {"invoiceId": 3, "kind": "purchase", "action": "save", "qty": "6", "price": "200", "currency": "IQD", "rate": "1", "sourceTotal": "1200", "expenses": 0}, {"invoiceId": 2, "kind": "sale", "action": "delete", "qty": 0}]'::jsonb,1,'{"qty": "10", "price": "120", "sourceTotal": "1200"}'::jsonb);
assert (r->>'qty')::numeric=16 and (r->>'cost')::numeric=150.000000,'returned_sale after stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'returned_sale after usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(150))<.00000001,'returned_sale after iqd component mismatch';
assert (r->'states'->'2'->>'cost')::numeric=120.000000,'returned_sale after first financial cost mismatch';
assert abs((r->'states'->'2'->>'book')::numeric-(120.000000))<.00000001,'returned_sale after first book mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "10", "price": "100", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 2, "kind": "sale", "action": "save", "qty": "10", "valuationRate": "1"}, {"invoiceId": 3, "kind": "purchase", "action": "save", "qty": "5", "price": "200", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 4, "kind": "sale", "action": "save", "qty": "2", "valuationRate": "1"}]'::jsonb,1,null);
assert (r->>'qty')::numeric=3 and (r->>'cost')::numeric=200.000000,'exhaustion before stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'exhaustion before usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(200))<.00000001,'exhaustion before iqd component mismatch';
assert (r->'states'->'2'->>'cost')::numeric=100.000000,'exhaustion before first financial cost mismatch';
assert abs((r->'states'->'2'->>'book')::numeric-(100.000000))<.00000001,'exhaustion before first book mismatch';
assert (r->'states'->'4'->>'cost')::numeric=200.000000,'exhaustion before second financial cost mismatch';
assert abs((r->'states'->'4'->>'book')::numeric-(200.000000))<.00000001,'exhaustion before second book mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "10", "price": "100", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 2, "kind": "sale", "action": "save", "qty": "10", "valuationRate": "1"}, {"invoiceId": 3, "kind": "purchase", "action": "save", "qty": "5", "price": "200", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 4, "kind": "sale", "action": "save", "qty": "2", "valuationRate": "1"}]'::jsonb,1,'{"qty": "10", "price": "120", "sourceTotal": "1200"}'::jsonb);
assert (r->>'qty')::numeric=3 and (r->>'cost')::numeric=200.000000,'exhaustion after stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'exhaustion after usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(200))<.00000001,'exhaustion after iqd component mismatch';
assert (r->'states'->'2'->>'cost')::numeric=120.000000,'exhaustion after first financial cost mismatch';
assert abs((r->'states'->'2'->>'book')::numeric-(120.000000))<.00000001,'exhaustion after first book mismatch';
assert (r->'states'->'4'->>'cost')::numeric=200.000000,'exhaustion after second financial cost mismatch';
assert abs((r->'states'->'4'->>'book')::numeric-(200.000000))<.00000001,'exhaustion after second book mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "10", "price": "100", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 2, "kind": "purchase", "action": "save", "qty": "10", "price": "200", "currency": "IQD", "rate": "1", "sourceTotal": "2000", "expenses": 0}, {"invoiceId": 3, "kind": "sale", "action": "save", "qty": "4", "valuationRate": "1"}, {"invoiceId": 4, "kind": "purchase", "action": "save", "qty": "4", "price": "250", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 5, "kind": "sale", "action": "save", "qty": "5", "valuationRate": "1"}]'::jsonb,2,null);
assert (r->>'qty')::numeric=15 and (r->>'cost')::numeric=170.000000,'mixed_price_qty before stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'mixed_price_qty before usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(170))<.00000001,'mixed_price_qty before iqd component mismatch';
assert (r->'states'->'3'->>'cost')::numeric=150.000000,'mixed_price_qty before first financial cost mismatch';
assert abs((r->'states'->'3'->>'book')::numeric-(150.000000))<.00000001,'mixed_price_qty before first book mismatch';
assert (r->'states'->'5'->>'cost')::numeric=170.000000,'mixed_price_qty before second financial cost mismatch';
assert abs((r->'states'->'5'->>'book')::numeric-(170.000000))<.00000001,'mixed_price_qty before second book mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "10", "price": "100", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 2, "kind": "purchase", "action": "save", "qty": "10", "price": "200", "currency": "IQD", "rate": "1", "sourceTotal": "2000", "expenses": 0}, {"invoiceId": 3, "kind": "sale", "action": "save", "qty": "4", "valuationRate": "1"}, {"invoiceId": 4, "kind": "purchase", "action": "save", "qty": "4", "price": "250", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 5, "kind": "sale", "action": "save", "qty": "5", "valuationRate": "1"}]'::jsonb,2,'{"qty": "8", "price": "200", "sourceTotal": "1600"}'::jsonb);
assert (r->>'qty')::numeric=13 and (r->>'cost')::numeric=167.901234,'mixed_price_qty after stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'mixed_price_qty after usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(167.901234567901234567901234567901234567901234567901234567901))<.00000001,'mixed_price_qty after iqd component mismatch';
assert (r->'states'->'3'->>'cost')::numeric=144.444444,'mixed_price_qty after first financial cost mismatch';
assert abs((r->'states'->'3'->>'book')::numeric-(144.444444))<.00000001,'mixed_price_qty after first book mismatch';
assert (r->'states'->'5'->>'cost')::numeric=167.901235,'mixed_price_qty after second financial cost mismatch';
assert abs((r->'states'->'5'->>'book')::numeric-(167.901234))<.00000001,'mixed_price_qty after second book mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "10", "price": "100", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 2, "kind": "sale", "action": "save", "qty": "10", "valuationRate": "1"}, {"invoiceId": 3, "kind": "purchase", "action": "save", "qty": "5", "price": "200", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 4, "kind": "sale", "action": "save", "qty": "2", "valuationRate": "1"}]'::jsonb,1,null);
assert (r->>'qty')::numeric=3 and (r->>'cost')::numeric=200.000000,'exhaustion_qty before stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'exhaustion_qty before usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(200))<.00000001,'exhaustion_qty before iqd component mismatch';
assert (r->'states'->'2'->>'cost')::numeric=100.000000,'exhaustion_qty before first financial cost mismatch';
assert abs((r->'states'->'2'->>'book')::numeric-(100.000000))<.00000001,'exhaustion_qty before first book mismatch';
assert (r->'states'->'4'->>'cost')::numeric=200.000000,'exhaustion_qty before second financial cost mismatch';
assert abs((r->'states'->'4'->>'book')::numeric-(200.000000))<.00000001,'exhaustion_qty before second book mismatch';
end$$;
do $$declare r jsonb;begin r:=solar_private.purchase_material_replay('{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}'::jsonb,'[{"invoiceId": 1, "kind": "purchase", "action": "save", "qty": "10", "price": "100", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 2, "kind": "sale", "action": "save", "qty": "10", "valuationRate": "1"}, {"invoiceId": 3, "kind": "purchase", "action": "save", "qty": "5", "price": "200", "currency": "IQD", "rate": "1", "sourceTotal": "1000", "expenses": 0}, {"invoiceId": 4, "kind": "sale", "action": "save", "qty": "2", "valuationRate": "1"}]'::jsonb,1,'{"qty": "12", "price": "100", "sourceTotal": "1200"}'::jsonb);
assert (r->>'qty')::numeric=5 and (r->>'cost')::numeric=171.428571,'exhaustion_qty after stock mismatch';
assert abs((r->'parts'->>'usd')::numeric-(0))<.00000001,'exhaustion_qty after usd component mismatch';
assert abs((r->'parts'->>'iqd')::numeric-(171.428571428571428571428571428571428571428571428571428571429))<.00000001,'exhaustion_qty after iqd component mismatch';
assert (r->'states'->'2'->>'cost')::numeric=100.000000,'exhaustion_qty after first financial cost mismatch';
assert abs((r->'states'->'2'->>'book')::numeric-(100.000000))<.00000001,'exhaustion_qty after first book mismatch';
assert (r->'states'->'4'->>'cost')::numeric=171.428571,'exhaustion_qty after second financial cost mismatch';
assert abs((r->'states'->'4'->>'book')::numeric-(171.428571))<.00000001,'exhaustion_qty after second book mismatch';
end$$;
-- A later quantity increase consumes the then-current book mix while keeping
-- the sale's first financial quote. Correcting procurement must preserve both
-- distinct quantities, including the basis needed for a future sale return.
do $$declare events jsonb:='[
 {"invoiceId":1,"kind":"purchase","action":"save","qty":10,"price":100,"currency":"IQD","rate":1,"sourceTotal":1000,"expenses":0},
 {"invoiceId":2,"kind":"sale","action":"save","qty":2,"valuationRate":1},
 {"invoiceId":3,"kind":"purchase","action":"save","qty":2,"price":300,"currency":"IQD","rate":1,"sourceTotal":600,"expenses":0},
 {"invoiceId":2,"kind":"sale","action":"save","qty":4,"valuationRate":1}
 ]';r jsonb;seed jsonb:='{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}';begin
 r:=solar_private.purchase_material_replay(seed,events,1,null);
 assert(r->>'qty')::numeric=8 and(r->>'cost')::numeric=140;
 assert(r->'states'->'2'->>'cost')::numeric=100 and(r->'states'->'2'->>'book')::numeric=120;
 r:=solar_private.purchase_material_replay(seed,events,1,'{"qty":10,"price":120,"sourceTotal":1200}');
 assert(r->>'qty')::numeric=8 and(r->>'cost')::numeric=156;
 assert(r->'states'->'2'->>'qty')::numeric=4 and(r->'states'->'2'->>'cost')::numeric=120 and(r->'states'->'2'->>'book')::numeric=138;
 assert(r->'states'->'2'->'parts'->>'iqd')::numeric=138;
end$$;
-- A historical purchase cancellation that empties the pool restores its
-- pre-purchase remembered quote. It does not keep the cancelled batch's cost.
-- The replacement must restore the recalculated snapshot, not the old number.
do $$declare events jsonb:='[
 {"invoiceId":1,"kind":"purchase","action":"save","qty":1,"price":1825000,"currency":"IQD","rate":1,"sourceTotal":1825000,"expenses":0},
 {"invoiceId":2,"kind":"system","action":"save","qty":1,"valuationRate":1680},
 {"invoiceId":3,"kind":"purchase","action":"save","qty":15,"price":1760000,"currency":"IQD","rate":1,"sourceTotal":26400000,"expenses":250000},
 {"invoiceId":4,"kind":"sale","action":"save","qty":15,"valuationRate":1685},
 {"invoiceId":4,"kind":"sale","action":"delete"},
 {"invoiceId":3,"kind":"purchase","action":"delete"}
 ]';r jsonb;seed jsonb:='{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}';begin
 r:=solar_private.purchase_material_replay(seed,events,1,null);
 assert(r->>'qty')::numeric=0 and(r->>'cost')::numeric=1825000,'Empty stock retained the cancelled purchase cost';
 assert(r->'parts'->>'iqd')::numeric=1825000 and(r->'parts'->>'usd')::numeric=0;
 r:=solar_private.purchase_material_replay(seed,events,1,'{"qty":1,"price":1825001,"sourceTotal":1825001}');
 assert(r->>'qty')::numeric=0 and(r->>'cost')::numeric=1825001,'Empty-stock cancellation ignored the corrected prior quote';
 assert(r->'states'->'2'->>'cost')::numeric=1825001 and(r->'parts'->>'iqd')::numeric=1825001;
end$$;
-- The remembered zero-stock basis also preserves separate historical USD
-- components; book cost must never be converted at the later sale's rate.
do $$declare events jsonb:='[
 {"invoiceId":1,"kind":"purchase","action":"save","qty":1,"price":2,"currency":"USD","rate":1000,"sourceTotal":2,"expenses":0},
 {"invoiceId":2,"kind":"sale","action":"save","qty":1,"valuationRate":1500},
 {"invoiceId":3,"kind":"purchase","action":"save","qty":2,"price":3,"currency":"USD","rate":2000,"sourceTotal":6,"expenses":20},
 {"invoiceId":4,"kind":"sale","action":"save","qty":2,"valuationRate":2500},
 {"invoiceId":4,"kind":"sale","action":"delete"},
 {"invoiceId":3,"kind":"purchase","action":"delete"}
 ]';r jsonb;seed jsonb:='{"qty":0,"cost":0,"parts":{"usd":0,"iqd":0},"states":{}}';begin
 r:=solar_private.purchase_material_replay(seed,events,1,null);
 assert(r->>'qty')::numeric=0 and(r->>'cost')::numeric=2000;
 assert(r->'parts'->>'usd')::numeric=2 and(r->'parts'->>'iqd')::numeric=0;
 r:=solar_private.purchase_material_replay(seed,events,1,'{"qty":1,"price":2.5,"sourceTotal":2.5}');
 assert(r->>'qty')::numeric=0 and(r->>'cost')::numeric=2500;
 assert(r->'states'->'2'->>'cost')::numeric=3750 and(r->'parts'->>'usd')::numeric=2.5 and(r->'parts'->>'iqd')::numeric=0;
end$$;
rollback;
select '24 independent numeric replay comparisons PASS' result;
