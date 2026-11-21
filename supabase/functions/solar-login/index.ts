import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2.57.4";
import {createLoginHandler} from "./handler.mjs";

const url=Deno.env.get('SUPABASE_URL')!;
const options={auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}};
Deno.serve(createLoginHandler({
  makeAdmin:()=>createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,options),
  makeAuth:()=>createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,options)
}));
