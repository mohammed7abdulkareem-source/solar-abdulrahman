import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createPasswordChangeHandler} from './handler.mjs';

Deno.serve(createPasswordChangeHandler({
 url:Deno.env.get('SUPABASE_URL')!,
 anonKey:Deno.env.get('SUPABASE_ANON_KEY')!,
}));
