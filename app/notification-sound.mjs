let context=null;
export const soundKey=userId=>'solar-notification-sound:'+userId;
export function soundEnabled(userId){try{return localStorage.getItem(soundKey(userId))==='on';}catch{return false;}}
export function setSoundEnabled(userId,enabled){try{localStorage.setItem(soundKey(userId),enabled?'on':'off');}catch{}window.dispatchEvent(new CustomEvent('solar-sound-setting',{detail:{userId,enabled}}));}
export function unlockNotificationSound(){
 try{const Audio=window.AudioContext||window.webkitAudioContext;if(!Audio)return Promise.resolve(false);if(!context||context.state==='closed')context=new Audio();return context.resume().then(()=>context.state==='running').catch(()=>false);}catch{return Promise.resolve(false);}
}
export async function playNotificationSound(){
 if(!await unlockNotificationSound())return false;
 try{const start=context.currentTime;[740,988,740].forEach((frequency,index)=>{const oscillator=context.createOscillator(),gain=context.createGain(),at=start+index*.17;oscillator.type='sine';oscillator.frequency.value=frequency;gain.gain.setValueAtTime(0,at);gain.gain.linearRampToValueAtTime(.14,at+.02);gain.gain.exponentialRampToValueAtTime(.001,at+.14);oscillator.connect(gain);gain.connect(context.destination);oscillator.start(at);oscillator.stop(at+.16);});return true;}catch{return false;}
}
export function createNoticeTracker(){const ids=new Set();let initialized=false;return {baseline(rows){rows.forEach(r=>ids.add(r.id));initialized=true;},receive(rows,realtime=false){const fresh=rows.filter(r=>!ids.has(r.id));rows.forEach(r=>ids.add(r.id));if(ids.size>1000){const recent=[...ids].slice(-500);ids.clear();recent.forEach(id=>ids.add(id));}if(!initialized){initialized=true;return realtime?fresh:[];}return fresh;}};}
