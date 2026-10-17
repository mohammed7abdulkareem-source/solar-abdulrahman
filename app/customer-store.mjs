import {supabase} from './supabase';
export async function customerDirectory(){const {data,error}=await supabase.rpc('solar_customer_directory');if(error)throw error;return data;}
export async function customerRecord(id){const {data,error}=await supabase.rpc('solar_customer_get',{customer_id:Number(id)});if(error)throw error;return data;}
export async function checkCustomer(name,phone,id){const {data,error}=await supabase.rpc('solar_customer_check',{customer_name:name,phone,exclude_id:id??null});if(error)throw error;return data;}
export async function saveCustomer(attempt,action,payload){
 const signature=JSON.stringify({action,payload});
 if(attempt.current&&attempt.current.signature!==signature)throw new Error('توجد محاولة حفظ لم يتأكد ردّها. أعد تأكيد الحفظ بنفس البيانات أولاً.');
 if(!attempt.current)attempt.current={signature,requestId:crypto.randomUUID()};
 const {data,error}=await supabase.rpc('solar_customer_save',{action,payload,request_id:attempt.current.requestId});
 if(error){if(error.code)attempt.current=null;throw error;}
 attempt.current=null;return data;
}
