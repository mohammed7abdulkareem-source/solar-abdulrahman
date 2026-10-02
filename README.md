# عبدالرحمن سولار — V3.2

Next.js / Supabase. Main branch deploys through the existing Vercel integration.

## Run

```sh
npm ci
npm run dev
npm run build
node --test tests/*.test.mjs
```

## This update (V3.2)

- Engineers receive only their assigned job details and unpriced material lists through a guarded RPC. They do not load products, transactions, cashboxes, costs or sale prices.
- Restrictive RLS policies deny engineers financial tables and constrain staff transactions, invoice items and cash ledger entries to their cashbox ownership. Administrators retain the aggregate view.
- Cashbox totals and movement lists use the same owner rule (cashbox_user_id, falling back to created_by); administrator deposits into a staff cashbox appear in that staff ledger.
- Installation stages: scheduled, in progress, report awaiting review, closed. Engineer reports include completion checks, notes and itemized task expenses.
- The server validates the assigned engineer, manager permission, state transition and expected revision. Row locks prevent double submissions. Final approved expenses replace the previous amount when reopening a job.
- Authorized staff manage installation files belonging to their cashbox; an administrator can manage all files.
- Closing a file recognizes approved installation cost; an actual cash payment is recorded separately through cashbox movements, preserving the existing accounting behavior.
- System invoice creation now awaits the transactional save and validates the engineer, appointment, address and inventory quantities.

## Verification

Run `node --test tests/*.test.mjs` and `npm run build`.
`tests/roles-rollback.sql` uses existing role identities and rollback-only fixtures to verify engineer redaction, cross-user cashbox isolation, assigned jobs, forbidden actions, transition ordering, stale revisions, report validation and close/reopen cost arithmetic. No fixture is committed to the database.
Mobile browser checks use isolated mocked sessions; no production credentials are required.

## Deployment dependency

The `solar_save_rows_v31` function was installed in the existing Solar database before this source update. It runs as SECURITY INVOKER and preserves RLS. The V3.2 migration in `supabase/migrations/` was applied to the same database. It adds the protected installation RPCs and restrictive financial access policies. Deploy the database migration before the frontend.

## Review limitations

- Concurrent changes to the same record still require optimistic concurrency/version checks; this release prevents rewriting unrelated records.
- Full accounting reconciliation, invoice editing cost recalculation, and server-side role-by-column restrictions require a separate audited change.
- Do not claim a full production financial audit based on the UI/build checks.
