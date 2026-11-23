import test from 'node:test';
import assert from 'node:assert/strict';
import {userDetailsRequest} from '../app/user-admin-details.mjs';

const details={username:'Sample',display_name:'موظف',phone:'07701234567',honorific:'',password:' sample value '};
const target={id:'test-user',token:'test-revision',phone:details.phone};

test('ordinary existing-account edits never send a cached or autofilled password',()=>{
 const request=userDetailsRequest({...details,display_name:'مستخدم محدّث'},target);
 assert.equal(Object.hasOwn(request,'password'),false);
 assert.equal(Object.hasOwn(request,'changePassword'),false);
 assert.equal(request.display_name,'مستخدم محدّث');
 assert.equal(request.user_id,target.id);
 assert.equal(request.token,target.token);
 assert.equal(Object.hasOwn(userDetailsRequest(details,target,false),'password'),false);
});
test('explicit admin password changes and new-account creation preserve the exact password',()=>{
 const reset=userDetailsRequest(details,target,true),create=userDetailsRequest(details,null);
 assert.equal(reset.password,details.password);
 assert.equal(reset.changePassword,true);
 assert.equal(create.password,details.password);
 assert.equal(Object.hasOwn(create,'changePassword'),false);
 assert.throws(()=>userDetailsRequest({...details,password:''},target,true));
 assert.throws(()=>userDetailsRequest({...details,password:''},null));
});
