# عبدالرحمن سولار — V3.27

## تحديث V3.27 — صلاحيات التحصيل ونسبة الربح

- التحصيل الكامل: اختيار نسبة الربح (5%، 10%، 15% أو نسبة مخصصة) فوق الكلفة الكلية، وحفظها مع المسودة؛ المسودات القديمة بلا نسبة تبقى 5%.
- التحصيل المحدود: اختيار المواد وطلب الزبون وعرض سعر البيع فقط. السيرفر يفرض 15% وكلف المواد الحالية والمصاريف القياسية، ويخفي الكلف في المسودات والمستندات.
- صلاحيتان واضحتان في المستخدمين: التحصيل، والتحصيل الكامل. الأدمن كامل تلقائياً. الصلاحية الكاملة لا تمنح الاطلاع على مسودات الآخرين.
- أزرار المعاينة وحفظ PDF والمشاركة أعلى التحصيل والمخزون والحركة والكشوف وتقارير الأرباح ورأس المال.
- قاعدة البيانات: تطبيق migration quote_profit_permissions قبل نشر الواجهة. المستخدم المحدود يستخدم RPC محمياً؛ الوصول المباشر للمسودات محصور بالصلاحية الكاملة مع بقاء قيود الملكية.
- فتح مسودة بحساب محدود يعيد احتسابها بالكلف الحالية ونسبة 15%؛ لا يعدّل المخزون أو الصندوق.

## تحديث V3.26 — التقارير وبيع المنظومات وحماية التصفير

- تقسيم جميع تقارير PDF حسب الصفوف، مع تكرار رأس الجدول وترقيم الصفحات، ودعم المستندات متعددة الجداول والملاحظات الطويلة.
- خطوط واضحة لخلايا الجداول وكميات وأسعار سوداء غامقة في التقارير والفواتير والكشوف.
- مساحة ثابتة قابلة للتمرير لاختيار المواد ومواد فاتورة المنظومة على اللابتوب، وترتيب متجاوب للموبايل.
- توحيد معاينة المنظومات المحفوظة والمسودات، مع تسلسل وعدد الفقرات ومجموع الكميات وإجمالي واحد. النسخة المخزنية بدون أسعار.
- التحقق من باسورد الأدمن بجلسة مستقلة قبل رسالة التأكيد؛ يعيد الخادم التحقق عند التنفيذ. تبقى النسخة الاحتياطية وعبارة التأكيد مطلوبة.
- التحقق: 40 اختباراً آلياً، وتقارير طويلة ومتعددة الجداول، وتنزيل PDF مطابق للمعاينة، وشاشات 1366 و1024 و390 بكسل. اختبار التصفير بمحاكاة فقط دون حذف بيانات فعلية.

## تحديث V3.25 — حفظ PDF مباشر ومعاينة مطابقة

- أزرار حفظ PDF تنزّل الملف مباشرة، دون فتح نافذة الطباعة.
- المعاينة تعرض نفس صور صفحات A4 المستخدمة داخل ملف PDF، مع حفظ الملف نفسه من المعاينة.
- فواتير الشراء الطويلة تتوزع على الصفحات دون قطع سطر المادة، مع تكرار رأس الجدول والإجماليات في النهاية.
- زر طباعة منفصل داخل المعاينة، ومعالجة أخطاء التجهيز وإظهار حالة التحميل.

## تحديث V3.24 — تفاصيل معاينة الشراء

- معاينة موحدة للشراء الجديد والمحفوظ: تسلسل المواد، البراند والصنف بخط أسود غامق، عدد الفقرات ومجموع الكميات والمصاريف.
- توضيح البراند والصنف في قائمة المواد وجدول الفاتورة.
- قبل اكتمال العدد والسعر تظهر كلفة المخزن الحالية إن وجدت؛ بعدها يظهر سعر الوحدة الواصل شاملاً توزيع المصاريف.

## تحديث V3.23 — قائمة كاملة وبحث ثابت

- عرض جميع المواد في قائمة الاختيار قبل البحث وبعده دون حد 12 مادة.
- الاحتفاظ بكلمة البحث بعد إضافة مادة في الشراء والجملة والمنظومات، مع استمرار التنقل بالإنتر.
- إظهار رقم الفاتورة واسم المجهّز أو العميل مباشرة في قائمة الفواتير السابقة.

## تحديث V3.22 — إدخال سريع وتعديل في الفاتورة الرئيسية

- Enter ينقل من الكمية للسعر ثم للبحث؛ إضافة المادة تركز حقل الكمية تلقائياً.
- مساحة فاتورة مختصرة على اللابتوب، مع تمرير المواد داخل الجدول وبقاء الملاحظات والإجماليات والحفظ ظاهرة.
- تعديل فواتير الشراء والجملة يفتح داخل محرر الفاتورة الرئيسي مع رقمها وتاريخها وحفظ التعديل أو إلغائه، مع استعادة الفاتورة الجديدة غير المحفوظة بعد الانتهاء.

## تحديث V3.21 — تنظيم المبيعات والمشتريات

- واجهة فواتير واضحة لبيع الجملة والشراء وبيع المنظومات، ببيانات الفاتورة في الأعلى وقائمة مواد بجانب جدول الكميات والأسعار.
- ملخص مستقل للمصاريف والإجمالي، وزر حفظ بارز مع المعاينة وPDF والمشاركة ونسخ المخزن.
- بطاقات مواد مناسبة للهاتف، وبحث بالاسم والكود والبراند والصنف مع إظهار المخزون والتنبيه عند تجاوز الكمية.
- استمرار الحسابات والصلاحيات وإسناد مهندس التنصيب كما في النسخة السابقة.

## تحديث V3.20 — مدينون العملاء والموردون

- فقرتان مستقلتان في التسديدات والحسابات، بصلاحيتي `customerDebts` و`supplierBalances`؛ يمنحهما الأدمن من المستخدمين والصلاحيات.
- تقرير المدينين لعملاء المستخدم المخصصين له، والأدمن للجميع. أرصدة العميل تشمل حركاته حتى عندما يستلم التسديد مستخدم آخر.
- الموردون: الأدمن لجميع الحركات، والإداري للحركات التي تخص قاصته وفق نطاق الحركات الحالي.
- بحث، تاريخ الرصيد حسب بغداد، علامتا جملة ومنظومات، آخر تسديد موجب وتاريخه، ومعاينة/PDF/مشاركة بنفس الاختيارات.
- بيع الجملة والشراء النقدي لا ينشئان ديناً. المنظومات تحتسب سعرها ناقص تسديداتها؛ الحقل النقدي القديم فيها لا يدل على استلام التسديد. المبالغ السالبة في تسديد العميل إضافات على الحساب، وليست آخر تسديد.
- تطابق الحركة بمعرف الطرف أولاً، والاسم القديم عند كونه فريداً فقط. الحركات القديمة الملتبسة تحذّر وتمنع تصدير تقرير ناقص.
- التقرير يحسب في قاعدة البيانات ويرجع JSON واحداً لتجنب حد 1000 صف؛ لا يعدّل أي أرصدة أو فواتير.

## تحديث V3.19 — سعات البطاريات

- الحساب الجديد يبدأ بأمبير نهاري وليلي فارغين.
- اختيار سعة البطارية: 5، 7.5، 10، 15، 25، 30 كيلو؛ العدد = الليلي ÷ السعة مع التقريب للأعلى.
- تغيير السعة يلغي اختيار مادة البطارية السابق حتى يختار المستخدم المادة المطابقة وسعرها.
- تحفظ السعة في المسودة وتظهر في PDF؛ المسودات القديمة تحتفظ بقاعدة 15 كيلو.
- لا يتطلب ترحيل قاعدة بيانات.

## تحديث V3.18 — التحصيل وتصفير البيانات

داخل تحديثات البرنامج المحمية أضيف خيار تصفير بيانات العمل لجميع المستخدمين. يعرض أعداد السجلات، ويحفظ نسخة احتياطية محمية على الخادم ويتيح تنزيل JSON. التنفيذ يتطلب تنزيل النسخة، كتابة «تصفير بيانات عبدالرحمن سولار»، تأكيد الحذف، والتحقق الفوري من باسورد الأدمن على الخادم. لا يتم تنفيذ التصفير عند فتح الصفحة أو تجهيز المعاينة.

يشمل التصفير الفواتير والمشتريات والتسديدات والمصاريف ورأس المال والمخزون والمواد والبراندات والزبائن والموردين ومسودات العروض والتنصيبات والتحويلات والإشعارات وعدادات الوصولات. تبقى حسابات المستخدمين والصلاحيات وأجهزة الإشعارات وسجلات التدقيق وكل النسخ الاحتياطية. إعادة البيانات من النسخة الاحتياطية تحتاج معالجة إدارية؛ لا يوجد استرجاع تلقائي داخل الواجهة في هذا الإصدار.

الطلب صالح 15 دقيقة ولمرة واحدة، ويرفض التنفيذ إذا تغيرت بيانات العمل منذ النسخة الاحتياطية. التنفيذ يتم بمعاملة واحدة ويتراجع كاملاً عند أي خطأ. RPC التنفيذي متاح فقط لـservice_role، والـEdge Function تتحقق من JWT والمستخدم الفعال ودور الأدمن وكلمة مروره قبل استدعائه. دالة `solar-reset-data` تستخدم التحقق من الهوية داخل الكود؛ لا تعتمد على بوابة verify_jwt.

طبّق `20261004133617_admin_data_reset.sql` ثم انشر `supabase/functions/solar-reset-data/index.ts`. تم تطبيقهما على قاعدة البرنامج في هذه الجلسة. لم تُصفّر بيانات الإنتاج. اختبار `tests/data-reset-rollback.sql` اختبر الحذف وعزل الصلاحيات وتغير البيانات مع ROLLBACK كامل، واختبار الواجهة استخدم استجابات محاكاة فقط.

## التحصيل — V3.17

- فقرة مستقلة لحساب عرض سعر منظومة، مع الأمبير النهاري والليلي واختيار الانفيرتر.
- قاعدة المحل: اللوح 600W يعادل 2.15 أمبير نهاري؛ البطارية 15 كيلو تعادل 15 أمبير ليلي. عدد القطع يقرب إلى الأعلى. هذه قواعد تسعير المحل وليست نموذجاً لتصميم الأحمال أو مدة التشغيل.
- يختار المستخدم مواد 600W وبطارية 15 كيلو من الأصناف، وتُجلب كلفة المخزن مع إمكان تعديلها لهذا العرض فقط.
- المصاريف الافتراضية: 30,000 لكل لوح + كرين 25,000 + عامل 20,000 + مبرمج 35,000 + توصيل 25,000 + كهربائيات 150,000 د.ع.
- السعر = (كلفة المواد + كل المصاريف) × 1.05، دون تقريب إضافي للسعر. مثال 15×15: 7 ألواح وبطارية واحدة ومصاريف 465,000 د.ع.
- إصلاح تصدير PDF على Chromium باستعمال SVG مضمّن بدلاً من blob URL الذي كان يمنع تصدير Canvas، مع الحفاظ على اتجاه العربية وهوامش A4.
- معاينة، تنزيل ومشاركة PDF: نسخة زبون تخفي الكلفة، ونسخة داخلية تفصل الكلفة والمصاريف و5%.
- مسودات سحابية خاصة بكل مستخدم، مع البحث والفتح والتعديل والحذف. تُحفظ أسماء المواد وكلفها وقت إعداد العرض؛ لا تتغير بتغير أسعار المخزن ولا تؤثر في المخزون أو القاصة.
- صلاحية tahseel في إدارة المستخدمين؛ المستخدم القديم صاحب صلاحية بيع المنظومات يدخل التحصيل ما لم تُرفض له صلاحيتها صراحة. مسؤول المخزن والمهندس لا يدخلان التحصيل.
- الحفظ يستعمل رقم مراجعة لمنع استبدال تعديل من جهاز آخر. يمكن حفظ مسودة غير مكتملة لكن PDF والسعر النهائي يتطلبان المواد والكلف الصحيحة.

### التثبيت والفحص

التحديث مبني على ملف V3.16.0 الذي قدمه المستخدم. طبّق migration `supabase/migrations/20261004132156_tahseel_quotes.sql` مرة واحدة قبل نشر الواجهة. تم تطبيقه على قاعدة بيانات البرنامج المتصلة في جلسة التعديل بتاريخ 4 أكتوبر 2026؛ لا تعِد تطبيقه يدوياً على نفس القاعدة. لا يحتاج تغيير مفاتيح أو Edge Functions.

```sh
npm ci
node --test tests/*.test.mjs
npm run build
```

اختبار صلاحيات المسودات وحفظها وتعديلها وحذفها موجود في `tests/tahseel-rollback.sql` وينتهي بـROLLBACK. الاختبارات على الهاتف تستخدم بيانات تجريبية واستجابات API معزولة؛ لا ترسل سجلات تجريبية لقاعدة الإنتاج.

يُنشَر هذا الإصدار عبر فرع main وربط Vercel الموجود. ملاحظات الإصدارات السابقة أدناه للتاريخ وقد لا تصف السلوك الأحدث.

---

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
