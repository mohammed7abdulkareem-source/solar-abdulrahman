# عبدالرحمن سولار — V3.1

Next.js / Supabase. Main branch deploys through the existing Vercel integration.

## Run

```sh
npm ci
npm run dev
npm run build
node --test tests/*.test.mjs
```

## This update

- Mobile dashboard refresh, section search, consistent forms and buttons.
- Inventory search and brand/category filters also apply to exported reports.
- Installation status filters, corrected expense replacement on reopening, retained engineer role when editing users.
- Invoice quantity/stock validation and save-in-progress state.
- Shared records are diffed by ID; unrelated rows are never deleted during save.
- Same-event saves are sent in one transactional RPC (`db/solar_v31.sql`), including invoice lines and stock. Failure rolls back the whole batch.
- Database policies now require an active authenticated profile, including shared data reads/writes.
- Service worker only caches same-origin manifest/icon resources. No authenticated data or HTML caching; removed nonexistent icon precache URLs.

## Deployment dependency

The `solar_save_rows_v31` function was installed in the existing Solar database before this source update. It runs as SECURITY INVOKER and preserves RLS. The shared-data model for authenticated active users remains; fine-grained per-role database isolation is not completed by this UI update. UI permission hiding alone is not data isolation.

## Review limitations

- Concurrent changes to the same record still require optimistic concurrency/version checks; this release prevents rewriting unrelated records.
- Full accounting reconciliation, invoice editing cost recalculation, and server-side role-by-column restrictions require a separate audited change.
- Do not claim a full production financial audit based on the UI/build checks.
