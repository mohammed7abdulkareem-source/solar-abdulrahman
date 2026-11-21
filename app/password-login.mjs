// Login is public. A previous session (including a revoked refresh token) is
// never needed to send the credentials for a new password grant.
export async function requestPasswordSession(endpoint, publishableKey, credentials, signal) {
 const controller = new AbortController();
 const cancel = () => controller.abort();
 if (signal.aborted) cancel();
 signal.addEventListener('abort', cancel, {once:true});
 const timer = setTimeout(cancel, 25000);
 let response, body;
 try {
  response = await fetch(endpoint, {
   method:'POST', credentials:'omit', cache:'no-store', redirect:'error', signal:controller.signal,
   headers:{'Content-Type':'application/json', apikey:publishableKey},
   body:JSON.stringify(credentials)
  });
  body = await response.json().catch(()=>null);
 } catch {
  throw new Error('تعذر الاتصال بخدمة الدخول. تحقق من الإنترنت وحاول مرة ثانية.');
 } finally {
  clearTimeout(timer);
  signal.removeEventListener('abort',cancel);
 }
 if (response.ok && body?.ok && typeof body.access_token==='string' && body.access_token && typeof body.refresh_token==='string' && body.refresh_token) {
  return {access_token:body.access_token,refresh_token:body.refresh_token};
 }
 if (response.status===429 || body?.code==='rate_limited') throw new Error('محاولات الدخول كثيرة. انتظر قليلاً ثم حاول مرة ثانية.');
 if (body?.code==='invalid_credentials') throw new Error('اسم المستخدم أو كلمة المرور غير صحيحة. تأكد من الاسم وكلمة المرور وحاول مجدداً.');
 if (body?.code==='invalid_request') throw new Error('أدخل اسم المستخدم أو البريد وكلمة المرور.');
 throw new Error('خدمة تسجيل الدخول غير متاحة الآن. حاول مرة ثانية بعد قليل.');
}
