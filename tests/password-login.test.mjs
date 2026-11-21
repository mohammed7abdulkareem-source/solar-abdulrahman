import test from 'node:test';
import assert from 'node:assert/strict';
import {requestPasswordSession} from '../app/password-login.mjs';

const endpoint='https://example.test/functions/v1/solar-login';
const credentials={login:'local-user',password:'  Case.Sensitive '};
const request=signal=>requestPasswordSession(endpoint,'public-test-key',credentials,signal||new AbortController().signal);

test('public password grant sends exact input and does not reuse a previous session',async t=>{
 t.mock.method(globalThis,'fetch',async(url,options)=>{
  assert.equal(url,endpoint);
  assert.equal(options.credentials,'omit');
  assert.equal(options.redirect,'error');
  assert.equal(options.headers.apikey,'public-test-key');
  assert.equal(new Headers(options.headers).has('Authorization'),false);
  assert.deepEqual(JSON.parse(options.body),credentials);
  return Response.json({ok:true,access_token:'test-access',refresh_token:'test-refresh'});
 });
 assert.deepEqual(await request(),{access_token:'test-access',refresh_token:'test-refresh'});
});

test('only a confirmed credential rejection tells the user to check their password',async t=>{
 const fetch=t.mock.method(globalThis,'fetch');
 fetch.mock.mockImplementation(async()=>Response.json({code:'invalid_credentials'},{status:401}));
 await assert.rejects(request(),/غير صحيحة/);
 fetch.mock.mockImplementation(async()=>Response.json({code:'rate_limited'},{status:429}));
 await assert.rejects(request(),/انتظر/);
 fetch.mock.mockImplementation(async()=>new Response('Service unavailable',{status:503}));
 await assert.rejects(request(),/غير متاحة/);
 fetch.mock.mockImplementation(async()=>Response.json({ok:true,access_token:'incomplete'}));
 await assert.rejects(request(),/غير متاحة/);
 fetch.mock.mockImplementation(async()=>{throw new TypeError('Network unavailable');});
 await assert.rejects(request(),/الاتصال/);
});
