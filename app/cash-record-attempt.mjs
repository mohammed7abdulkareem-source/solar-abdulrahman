const storageKey=(actor,movement)=>'solar-cash-record-attempt-v1:'+actor+':'+(movement||'handover');
const storage=()=>{try{return globalThis.localStorage;}catch{return null;}};
export function readCashAttempt(actor,movement){try{const x=JSON.parse(storage()?.getItem(storageKey(actor,movement))||'null');return x&&typeof x.id==='string'&&/^[a-f0-9-]{36}$/i.test(x.id)&&x.payload&&typeof x.payload==='object'?x:null;}catch{return null;}}
export function rememberCashAttempt(actor,movement,value){try{storage()?.setItem(storageKey(actor,movement),JSON.stringify(value));}catch{}}
export function clearCashAttempt(actor,movement,id){try{const x=readCashAttempt(actor,movement);if(!id||x?.id===id)storage()?.removeItem(storageKey(actor,movement));}catch{}}
