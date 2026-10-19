-- Local-only API wrappers copied from production. They deliberately remain invokers.
CREATE OR REPLACE FUNCTION public.solar_cash_workspace(payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$select solar_private.cash_workspace(payload)$function$;
revoke all on function public.solar_cash_workspace(payload jsonb) from public,anon;
grant execute on function public.solar_cash_workspace(payload jsonb) to authenticated;

CREATE OR REPLACE FUNCTION public.solar_customer_statement(customer_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$select solar_private.customer_statement(customer_id)$function$;
revoke all on function public.solar_customer_statement(customer_id bigint) from public,anon;
grant execute on function public.solar_customer_statement(customer_id bigint) to authenticated;

CREATE OR REPLACE FUNCTION public.solar_installation_action(job_id bigint, expected_revision bigint, action text, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select solar_private.installation_action(job_id,expected_revision,action,payload) $function$;
revoke all on function public.solar_installation_action(job_id bigint, expected_revision bigint, action text, payload jsonb) from public,anon;
grant execute on function public.solar_installation_action(job_id bigint, expected_revision bigint, action text, payload jsonb) to authenticated;

CREATE OR REPLACE FUNCTION public.solar_installation_jobs()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select solar_private.installation_jobs() $function$;
revoke all on function public.solar_installation_jobs() from public,anon;
grant execute on function public.solar_installation_jobs() to authenticated;

CREATE OR REPLACE FUNCTION public.solar_invoice_save(request_id uuid, payload jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.invoice_save(request_id,payload)$function$;
revoke all on function public.solar_invoice_save(request_id uuid, payload jsonb) from public,anon;
grant execute on function public.solar_invoice_save(request_id uuid, payload jsonb) to authenticated;

CREATE OR REPLACE FUNCTION public.solar_profit_workspace(action text, request_id uuid DEFAULT NULL::uuid, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.profit_workspace(action,request_id,payload)$function$;
revoke all on function public.solar_profit_workspace(action text, request_id uuid, payload jsonb) from public,anon;
grant execute on function public.solar_profit_workspace(action text, request_id uuid, payload jsonb) to authenticated;

CREATE OR REPLACE FUNCTION public.solar_sale_delete(invoice_id bigint, expected_token text)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.currency_sale_delete(invoice_id,expected_token)$function$;
revoke all on function public.solar_sale_delete(invoice_id bigint, expected_token text) from public,anon;
grant execute on function public.solar_sale_delete(invoice_id bigint, expected_token text) to authenticated;

CREATE OR REPLACE FUNCTION public.solar_sale_delete_preview(invoice_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.sale_delete_data(invoice_id)$function$;
revoke all on function public.solar_sale_delete_preview(invoice_id bigint) from public,anon;
grant execute on function public.solar_sale_delete_preview(invoice_id bigint) to authenticated;

CREATE OR REPLACE FUNCTION public.solar_sales_history(search_text text DEFAULT ''::text, sale_kind text DEFAULT ''::text, date_from date DEFAULT NULL::date, date_to date DEFAULT NULL::date, job_status text DEFAULT ''::text, page_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select solar_private.sales_history(search_text,sale_kind,date_from,date_to,job_status,page_offset)
$function$;
revoke all on function public.solar_sales_history(search_text text, sale_kind text, date_from date, date_to date, job_status text, page_offset integer) from public,anon;
grant execute on function public.solar_sales_history(search_text text, sale_kind text, date_from date, date_to date, job_status text, page_offset integer) to authenticated;

CREATE OR REPLACE FUNCTION public.solar_stock_movements(product_filter bigint DEFAULT NULL::bigint, customer_filter text DEFAULT ''::text, date_from date DEFAULT NULL::date, date_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.stock_movements(product_filter,customer_filter,date_from,date_to)$function$;
revoke all on function public.solar_stock_movements(product_filter bigint, customer_filter text, date_from date, date_to date) from public,anon;
grant execute on function public.solar_stock_movements(product_filter bigint, customer_filter text, date_from date, date_to date) to authenticated;

CREATE OR REPLACE FUNCTION public.solar_stock_quantities()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.stock_quantities()$function$;
revoke all on function public.solar_stock_quantities() from public,anon;
grant execute on function public.solar_stock_quantities() to authenticated;

CREATE OR REPLACE FUNCTION public.solar_supplier_payment_get(payment_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.supplier_payment_get(payment_id)$function$;
revoke all on function public.solar_supplier_payment_get(payment_id bigint) from public,anon;
grant execute on function public.solar_supplier_payment_get(payment_id bigint) to authenticated;

CREATE OR REPLACE FUNCTION public.solar_system_payment_context(customer_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$select solar_private.system_payment_context(customer_id)$function$;
revoke all on function public.solar_system_payment_context(customer_id bigint) from public,anon;
grant execute on function public.solar_system_payment_context(customer_id bigint) to authenticated;

CREATE OR REPLACE FUNCTION public.solar_warehouse_action(invoice_id bigint, expected_token text, action text, lines jsonb DEFAULT NULL::jsonb, note text DEFAULT ''::text)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.warehouse_action(invoice_id,expected_token,action,lines,note)$function$;
revoke all on function public.solar_warehouse_action(invoice_id bigint, expected_token text, action text, lines jsonb, note text) from public,anon;
grant execute on function public.solar_warehouse_action(invoice_id bigint, expected_token text, action text, lines jsonb, note text) to authenticated;

CREATE OR REPLACE FUNCTION public.solar_warehouse_orders(search_text text DEFAULT ''::text, state text DEFAULT 'pending'::text, page_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.warehouse_orders(search_text,state,page_offset)$function$;
revoke all on function public.solar_warehouse_orders(search_text text, state text, page_offset integer) from public,anon;
grant execute on function public.solar_warehouse_orders(search_text text, state text, page_offset integer) to authenticated;

CREATE OR REPLACE FUNCTION public.solar_warehouse_statuses(invoice_ids bigint[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$select solar_private.warehouse_statuses(invoice_ids)$function$;
revoke all on function public.solar_warehouse_statuses(invoice_ids bigint[]) from public,anon;
grant execute on function public.solar_warehouse_statuses(invoice_ids bigint[]) to authenticated;

CREATE OR REPLACE FUNCTION public.solar_warranty_manage(action text, request_id uuid DEFAULT NULL::uuid, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.warranty_manage(action,request_id,payload)$function$;
revoke all on function public.solar_warranty_manage(action text, request_id uuid, payload jsonb) from public,anon;
grant execute on function public.solar_warranty_manage(action text, request_id uuid, payload jsonb) to authenticated;
