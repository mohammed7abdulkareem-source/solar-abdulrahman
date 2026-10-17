import {supabase} from './supabase';
export async function fxRead(action,payload={}){const {data,error}=await supabase.rpc('solar_fx',{action,payload});if(error)throw error;return data;}
export async function fxSave(attempt,action,payload){
 const signature=JSON.stringify({action,payload});
 if(attempt.current&&attempt.current.signature!==signature)throw new Error('أعد تأكيد الحفظ السابق بنفس البيانات أولاً.');
 if(!attempt.current)attempt.current={signature,id:crypto.randomUUID()};
 const {data,error}=await supabase.rpc('solar_fx',{action,request_id:attempt.current.id,payload});
 if(error){if(error.code)attempt.current=null;throw error;}attempt.current=null;return data;
}
