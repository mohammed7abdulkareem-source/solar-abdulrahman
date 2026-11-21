const headers={
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods':'POST, OPTIONS',
  'Cache-Control':'no-store'
};
const errors={
  invalid_request:'اكتب اسم المستخدم وكلمة المرور.',
  invalid_credentials:'اسم المستخدم أو كلمة المرور غير صحيحة.',
  rate_limited:'محاولات الدخول كثيرة. انتظر قليلاً ثم حاول مجدداً.',
  unavailable:'تعذّر الاتصال بخدمة تسجيل الدخول. حاول مجدداً.'
};
function failure(code,status){
  return Response.json({ok:false,code,error:errors[code]},{status,headers});
}
const denied=()=>failure('invalid_credentials',401);
const unavailable=()=>failure('unavailable',503);
const normalize=value=>typeof value==='string'?value.trim().toLowerCase():'';

function serviceFailure(error,operation,httpStatus){
  const {code,message}=error||{};
  const status=httpStatus||error?.status;
  if(status===429||code==='over_request_rate_limit')return failure('rate_limited',429);
  if(status>=500)return unavailable();
  if(operation==='identity'&&(code==='user_not_found'||status===404))return denied();
  if(operation==='password'){
    if(['invalid_credentials','user_banned','email_not_confirmed','user_not_found'].includes(code))return denied();
    // Older GoTrue versions sent the canonical message without a machine code.
    if(!code&&[400,401].includes(status)&&/^invalid login credentials\.?$/i.test(message||''))return denied();
  }
  return unavailable();
}

// imatch accepts an anchored PostgreSQL regular expression. Escaping its
// metacharacters also keeps *, % and _ literal through PostgREST, whose
// LIKE filters otherwise treat * as an alias for %.
function exactUsername(login){
  return '^'+login.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'$';
}

async function verifyGrantedProfile(admin,data,profileId,login){
  const {session,user}=data||{};
  if(!session?.access_token||!session.refresh_token||!user?.id)return unavailable();
  if((profileId&&user.id!==profileId)||(session.user&&session.user.id!==user.id))return denied();
  const current=await admin.from('profiles').select('id,username,active').eq('id',user.id).maybeSingle();
  if(current.error)return serviceFailure(current.error,'profile',current.status);
  if(current.data?.id!==user.id||current.data.active!==true||
    (profileId&&normalize(current.data.username)!==login))return denied();
  return null;
}

export function createLoginHandler({makeAdmin,makeAuth}){
  return async function loginRequest(request){
    if(request.method==='OPTIONS')return new Response('ok',{headers});
    if(request.method!=='POST')return failure('invalid_request',405);
    let body;
    try{body=await request.json();}catch{return failure('invalid_request',400);}
    const login=normalize(body?.login),password=body?.password;
    if(!login||typeof password!=='string'||password.length===0)return failure('invalid_request',400);
    try{
      const admin=makeAdmin(),byUsername=!login.includes('@');
      let email=login,profileId;
      if(byUsername){
        const lookup=await admin.from('profiles').select('id,username,active')
          .filter('username','imatch',exactUsername(login)).limit(2);
        if(lookup.error)return serviceFailure(lookup.error,'profile',lookup.status);
        if(!Array.isArray(lookup.data))return unavailable();
        const [profile]=lookup.data;
        if(lookup.data.length!==1||!profile?.id||profile.active!==true||normalize(profile.username)!==login)return denied();
        profileId=profile.id;
        const identity=await admin.auth.admin.getUserById(profileId);
        if(identity.error)return serviceFailure(identity.error,'identity');
        const user=identity.data?.user;
        if(user?.id!==profileId||!user.email)return denied();
        email=user.email;
      }
      const auth=makeAuth();
      const {data,error}=await auth.auth.signInWithPassword({email,password});
      if(error)return serviceFailure(error,'password');
      // The profile may have changed during the grant. Release only this
      // request's newly granted session when its last authorization check fails.
      let rejected;
      try{rejected=await verifyGrantedProfile(admin,data,profileId,login);}catch{rejected=unavailable();}
      if(rejected){
        if(data?.session){
          try{await auth.auth.signOut({scope:'local'});}catch{/* Provider may already be offline. */}
        }
        return rejected;
      }
      return Response.json({ok:true,access_token:data.session.access_token,refresh_token:data.session.refresh_token},{headers});
    }catch{return unavailable();}
  };
}
