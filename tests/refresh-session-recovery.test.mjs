import assert from 'node:assert/strict';
import test from 'node:test';
import {AuthClient, isAuthRetryableFetchError} from '@supabase/supabase-js';
import {createRefreshFetch} from '../app/auth-refresh-fetch.mjs';

// Use the installed Auth client and its public getSession method, so an SDK
// change that drops a recoverable session or revives a revoked one is visible.
async function fixture(t, respond) {
  let time = Date.UTC(2026, 0, 1), sdkTime = time;
  t.mock.method(Date, 'now', () => sdkTime);
  const user = {id:'fixture-user'};
  const expired = {access_token:'old-access', refresh_token:'old-refresh', expires_at:time / 1000 - 10, user};
  const renewed = {access_token:'new-access', refresh_token:'new-refresh', expires_in:3600, token_type:'bearer', user};
  const key = 'test-session';
  const values = new Map([[key, JSON.stringify(expired)]]);
  const storage = {
    getItem:name => values.get(name) ?? null,
    setItem:(name, value) => values.set(name, value),
    removeItem:name => values.delete(name),
  };
  let calls = 0;
  const request = createRefreshFetch(async (url, init) => {
    assert.equal(new URL(url).searchParams.get('grant_type'), 'refresh_token');
    assert.equal(JSON.parse(init.body).refresh_token, expired.refresh_token);
    return respond(++calls, renewed);
  }, () => time);
  const auth = new AuthClient({
    url:'https://fixture.test/auth/v1', storageKey:key, storage, persistSession:true,
    detectSessionInUrl:false, autoRefreshToken:false,
    fetch:async (...args) => {
      const response = await request(...args);
      // Exhaust this getSession call's SDK retry budget without real sleeps.
      // The separate clock above controls the server's Retry-After window.
      if (!response.ok) sdkTime += 30_000;
      return response;
    },
  });
  await auth.initialize();
  return {auth, expired, calls:() => calls, stored:() => JSON.parse(storage.getItem(key)), advance:ms => {time += ms;}};
}

test('temporary refresh throttle preserves the session and recovers the same user after the cooldown', async t => {
  const limited = () => Response.json({error_code:'over_request_rate_limit'}, {status:429, headers:{'Retry-After':'60'}});
  const f = await fixture(t, (count, renewed) => count === 1 ? limited() : Response.json(renewed));
  for (const delay of [0, 59_000]) {
    f.advance(delay);
    const {data, error} = await f.auth.getSession();
    assert.equal(data.session, null);
    assert.ok(isAuthRetryableFetchError(error));
    assert.deepEqual(f.stored(), f.expired);
    assert.equal(f.calls(), 1);
  }
  f.advance(1_001);
  const {data, error} = await f.auth.getSession();
  assert.equal(error, null);
  assert.equal(data.session.user.id, f.expired.user.id);
  assert.equal(f.stored().refresh_token, 'new-refresh');
  assert.equal(f.calls(), 2);
});

test('an expired session whose refresh grant was actually revoked is removed', async t => {
  const f = await fixture(t, () => Response.json({error_code:'refresh_token_not_found'}, {status:400}));
  const {data, error} = await f.auth.getSession();
  assert.equal(data.session, null);
  assert.equal(error?.code, 'refresh_token_not_found');
  assert.equal(f.stored(), null);
  assert.equal(f.calls(), 1);
});

test('refresh waits until the Retry-After HTTP date or one SDK tick if the header is unavailable', async () => {
  const start = Date.UTC(2026, 0, 1);
  const refresh = new Request('https://fixture.test/auth/v1/token?grant_type=refresh_token', {method:'POST'});
  for (const [retryAfter, seconds] of [[new Date(start + 12_000).toUTCString(), 12], [null, 30], ['invalid', 30]]) {
    let time = start, requests = 0;
    const request = createRefreshFetch(async () => {
      requests++;
      return requests === 1 ? new Response(null, {status:429, headers:retryAfter ? {'Retry-After':retryAfter} : {}}) : Response.json({ok:true});
    }, () => time);
    const first = await request(refresh);
    assert.equal(first.status, 503);
    assert.equal(first.headers.get('retry-after'), String(seconds));
    time += seconds * 1000 - 1;
    assert.equal((await request(refresh)).status, 503);
    assert.equal(requests, 1);
    time++;
    assert.equal((await request(refresh)).status, 200);
    assert.equal(requests, 2);
  }
});

test('refresh cooldown never replaces the response for a password grant or unrelated Auth endpoint', async () => {
  const endpoint = 'https://fixture.test/auth/v1/token';
  const rejected = Response.json({code:'invalid_credentials'}, {status:400});
  const limited = new Response(null, {status:429});
  let upstream = limited;
  const request = createRefreshFetch(async () => upstream, () => 1_000);
  assert.equal((await request(endpoint + '?grant_type=refresh_token', {method:'POST'})).status, 503);
  upstream = rejected;
  assert.equal(await request(endpoint + '?grant_type=password', {method:'POST'}), rejected);
  upstream = limited;
  assert.equal(await request(endpoint + '?grant_type=password', {method:'POST'}), limited);
  assert.equal(await request('https://fixture.test/auth/v1/logout', {method:'POST'}), limited);
  assert.equal(await request(endpoint + '?grant_type=refresh_token', {method:'GET'}), limited);
});

test('startup observers receive the current throttle state and terminal refresh results clear it', async () => {
  const endpoint = 'https://fixture.test/auth/v1/token?grant_type=refresh_token';
  for (const terminal of [200, 400, 401]) {
    let time = 1_000, status = 429;
    const request = createRefreshFetch(async () => new Response(null, {status}), () => time);
    const early = [], late = [];
    const unsubscribe = request.watchThrottle(value => early.push(value));
    await request(endpoint, {method:'POST'});
    request.watchThrottle(value => late.push(value));
    unsubscribe();
    time += 30_001;
    status = 503;
    await request(endpoint, {method:'POST'});
    status = terminal;
    await request(endpoint, {method:'POST'});
    assert.deepEqual(early, [false, true]);
    assert.deepEqual(late, [true, false]);
  }
});
