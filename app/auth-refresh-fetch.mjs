// The pinned Auth SDK removes its stored session on a 429, even for a
// temporary refresh quota. Its 503 path preserves the session for retry.
export function createRefreshFetch(fetchImpl = (...args) => fetch(...args), now = Date.now) {
 let retryAt = 0;
 let throttled = false;
 const listeners = new Set();
 function report(value) {
  if (throttled === value) return;
  throttled = value;
  for (const listener of listeners) listener(value);
 }
 const retryable = () => new Response(null, {
  status: 503,
  headers: {'Cache-Control':'no-store', 'Retry-After':String(Math.max(0, Math.ceil((retryAt - now()) / 1000)))}
 });

 async function request(input, init) {
  const method = init?.method || input?.method || 'GET';
  if (method.toUpperCase() !== 'POST') return fetchImpl(input, init);
  const address = typeof input === 'string' || input instanceof URL ? input : input?.url;
  let url;
  try { url = new URL(address); } catch { return fetchImpl(input, init); }
  if (url.pathname !== '/auth/v1/token' || url.searchParams.get('grant_type') !== 'refresh_token')
   return fetchImpl(input, init);
  const signal = init?.signal || input?.signal;
  if (signal?.aborted) return fetchImpl(input, init);
  if (now() < retryAt) return retryable();
  const response = await fetchImpl(input, init);
  if (response.status !== 429) {
   if (![502, 503, 504].includes(response.status)) report(false);
   return response;
  }

  const header = response.headers.get('retry-after')?.trim();
  const time = now();
  const until = !header ? NaN : /^\d+$/.test(header) ? time + Number(header) * 1000 : Date.parse(header);
  // GoTrue does not always provide Retry-After. Use one auto-refresh tick.
  retryAt = Math.max(retryAt, Number.isFinite(until) ? Math.max(time, until) : time + 30000);
  report(true);
  return retryable();
 }
 request.watchThrottle = listener => {
  listeners.add(listener);
  listener(throttled);
  return () => listeners.delete(listener);
 };
 return request;
}
