# عبدالرحمن سولار — V3.7

تدعم التسديدات نوعين من الحركة: تسديد ينقص الرصيد، أو مبلغ سالب يضاف على حساب الزبون بسبب مصروف إضافي أو حساب قديم أو سبب آخر، بدون إضافته إلى الصندوق.

واجهة بيع المنظومات تعرض الكمية المتوفرة بالمخزن وسعر كلفة الوحدة وكلفة الكمية قبل الحفظ.

واجهة بيع المنظومات تعرض كلفة المواد فوراً، وتجعل المهندس إلزامياً والموعد اختيارياً باليوم والساعة، مع معاينة وفاتورة PDF أوضح.

واجهة V3.4 تضع جرس الإشعارات وزر تشغيلها داخل بطاقة الاسم، وتفتح التفاصيل في نافذة صغيرة عند الطلب، وتحذف بحث الأقسام من الرئيسية.

Next.js / Supabase. Main branch deploys through the existing Vercel integration.

## Run

```sh
npm ci
npm run dev
npm run build
node --test tests/*.test.mjs
```

## Push notifications (V3.3)

- Assignment of a system invoice to an engineer creates a notification for that engineer.
- A transition from in_progress to completed creates a notification for transactions.created_by (the invoice creator), independently of the cashbox owner.
- Each person must click “تفعيل إشعارات الموبايل” and grant browser permission on their device. The UI includes an explicit self-test, device opt-out and a private inbox.
- Opening a notification navigates to the installation file. Staff with system permission can view their own files; financial approval still requires installations permission.
- Push payloads contain generic task messages, no customer names, prices or cashbox balances. Service-worker account binding blocks messages for another account; logout clears the binding, closes visible notifications and unsubscribes.
- Database triggers create a durable per-device outbox. pg_net wakes the Edge Function after commit, and pg_cron retries due deliveries every minute with a lease, bounded exponential backoff and a maximum of five attempts. Expired subscriptions are removed.
- VAPID keys and the random worker token are stored in Supabase Vault under solar_push_vapid_public, solar_push_vapid_private and solar_push_worker_token. They are not committed to this repository.
- Deploy supabase/functions/solar-push with JWT verification disabled: its body requires the private worker token using constant-time comparison. Worker configuration/claim/finish RPCs are executable only by service_role. No user token can invoke the dispatcher.
- The private delivery table deliberately has no client RLS policies. Only trusted worker RPCs access it.
- Run tests/push-rollback.sql to validate routing, private inbox access, queue leasing and retries without sending a notification or retaining test records.
- Verification: hosted worker authentication and encryption self-test succeeded. Local browser tests covered activation, test request, real service-worker display using synthetic payloads, task navigation and opt-out. Receipt on a physical phone requires that device's permission and subscription.
- Mobile OS notification settings, connectivity, and browser background restrictions still control final display; provider acceptance is not proof a person read the message.

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
