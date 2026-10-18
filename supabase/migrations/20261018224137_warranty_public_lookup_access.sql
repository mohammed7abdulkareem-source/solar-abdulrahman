-- The public SECURITY INVOKER wrapper needs schema resolution permission.
-- This grants no table access; anonymous EXECUTE is explicitly granted only
-- to the opaque-token certificate lookup (trigger functions cannot be invoked directly).
grant usage on schema solar_private to anon;
