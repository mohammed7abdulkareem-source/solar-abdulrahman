import {validHonorific} from './user-name-utils.mjs';
import {normalizeUserPhone,validUserPhone} from './user-phone-utils.mjs';

export function userDetailsRequest(info,target,changePassword=false){
 const username=info.username.trim().toLowerCase(),displayName=info.display_name.trim();
 const phone=normalizeUserPhone(info.phone),honorific=info.honorific.trim();
 if(!/^[a-z0-9_.-]{2,30}$/.test(username))throw new Error('اكتب اسم الدخول بحروف إنكليزية أو أرقام من ٢ إلى ٣٠ خانة.');
 if(!displayName||!validHonorific(honorific)||((!target||phone||target.phone)&&!validUserPhone(phone)))
  throw new Error('راجع الاسم الظاهر والكنية ورقم الهاتف.');
 const body={action:'save_details',username,display_name:displayName,honorific};
 if(target){body.user_id=target.id;body.token=target.token;}
 if(!target||phone||target.phone)body.phone=phone;
 if(!target||changePassword){
  if(typeof info.password!=='string'||info.password.length<6)throw new Error('أدخل كلمة مرور من ست خانات على الأقل.');
  body.password=info.password;
  if(target)body.changePassword=true;
 }
 return body;
}
