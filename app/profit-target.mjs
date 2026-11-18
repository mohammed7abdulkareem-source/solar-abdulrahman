import {supabase} from './supabase';
import {saveRequest} from './save-request.mjs';
import {runProfitTargetAttempt} from './profit-target-attempt.mjs';

export {PROFIT_TARGET_EVENT,readProfitTargetAttempt} from './profit-target-attempt.mjs';

async function currentUser(){
 const {data,error}=await supabase.auth.getSession();
 if(error)throw error;
 return data.session?.user?.id;
}
const send=attempt=>saveRequest(signal=>supabase.rpc('solar_profit_workspace',{
 action:'external_adjust',request_id:attempt.id,payload:attempt.payload
}).abortSignal(signal));

export const saveProfitTarget=(actorId,payload)=>runProfitTargetAttempt(actorId,payload,{currentUser,send});
export const retryProfitTarget=actorId=>runProfitTargetAttempt(actorId,null,{currentUser,send});
