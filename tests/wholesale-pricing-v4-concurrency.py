"""Two-session pricing races in a disposable LOCAL PostgreSQL clone only.

Never opens a network database connection. The source database is only used as
a clone template, and the clone is dropped in finally even after a failed test.
"""
import json
import os
import re
import select
import subprocess
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

SOURCE = os.environ.get("SOLAR_PRICING_SOURCE_DB", "solar_v4_pricing_final")
assert re.fullmatch(r"solar_[a-z0-9_]+", SOURCE), "Only a named local solar test database is allowed"
CLONE = "solar_wp_concurrency_" + uuid.uuid4().hex[:10]
OUT = Path(os.environ.get("SOLAR_PRICING_CONCURRENCY_RESULTS", "/workspace/solar-review/v4-pricing/wholesale-pricing-concurrency-results.json"))
ENV = {k: v for k, v in os.environ.items() if k not in (
    "DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_TLS", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH")}
BASE = ["docker", "--host=unix:///var/run/docker.sock", "exec", "-i",
        "solar-customers-postgres", "psql", "-X", "-U", "postgres", "-At",
        "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"]
ADMIN = "00000000-0000-0000-0000-000000410011"
MANAGER = "00000000-0000-0000-0000-000000410012"
SELLER = "00000000-0000-0000-0000-000000410013"
PRODUCT = -410011
sessions = []
results = []


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def sql(query, database=CLONE, check=True):
    response = subprocess.run(BASE + ["-d", database], input=query, text=True,
                              capture_output=True, env=ENV, timeout=30)
    if check and response.returncode:
        raise AssertionError(response.stderr.strip())
    return response


def scalar(query):
    return sql(query).stdout.strip().splitlines()[-1]


def as_actor(actor, query):
    return "begin;set local role authenticated;select set_config('request.jwt.claim.sub'," + quote(actor) + ",true);" + query + ";commit;"


def call(action, nonce, payload):
    return "select public.solar_wholesale_pricing(" + ",".join((quote(action), quote(nonce), quote(json.dumps(payload)) + "::jsonb")) + ")"


def wait_ready(session):
    until = time.monotonic() + 10
    # Read raw descriptors: TextIO buffering could hide another ready line.
    received = b""
    while time.monotonic() < until:
        if session.poll() is not None:
            raise AssertionError("First session stopped: " + session.stderr.read().decode())
        readable, _, _ = select.select([session.stdout], [], [], 0.2)
        if readable:
            received += os.read(session.stdout.fileno(), 8192)
            if b"WP_LOCK_HELD" in received:
                return
    raise AssertionError("First session did not announce its lock")


def concurrent_stale(name, winner_query, loser_query, loser_actor=MANAGER):
    application = "wp_" + name + "_loser"
    session = subprocess.Popen(BASE + ["-d", CLONE], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=ENV)
    sessions.append(session)
    session.stdin.write(("begin;set local role authenticated;select set_config('request.jwt.claim.sub'," + quote(ADMIN) + ",true);"
                         "select pg_advisory_xact_lock(7311,1);" + winner_query + ";select 'WP_LOCK_HELD';\n").encode())
    session.stdin.flush()
    wait_ready(session)
    with ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(sql, "set application_name=" + quote(application) + ";" + as_actor(loser_actor, loser_query), CLONE, False)
        blocked = False
        until = time.monotonic() + 8
        while time.monotonic() < until:
            blocked = scalar("select exists(select 1 from pg_stat_activity where datname=current_database() and application_name="
                             + quote(application) + " and wait_event_type='Lock');") == "t"
            if blocked:
                break
            if future.done():
                raise AssertionError("Second session did not wait for the shared lock: " + future.result().stderr)
            time.sleep(0.05)
        assert blocked, "Could not observe the second session waiting on the pricing lock"
        session.stdin.write(b"commit;\\q\n")
        session.stdin.flush()
        stdout, stderr = session.communicate(timeout=15)
        assert session.returncode == 0, stderr.decode()
        loser = future.result(timeout=15)
    assert loser.returncode != 0 and "PT409" in loser.stderr, loser.stderr
    return {"case": name, "observedConcurrentLockWait": True, "loserSqlstate": "PT409"}


def product_state():
    return json.loads(scalar("select jsonb_build_object('price',minimum_price,'revision',revision)from solar_private.wholesale_product_prices where product_id=" + str(PRODUCT)))


def financial_fingerprint():
    return scalar("""select md5(jsonb_build_object(
      'product',(select jsonb_build_array(qty,cost,cost_basis,costing_revision)from products where id=-410011),
      'stock',(select jsonb_agg(to_jsonb(s)order by warehouse_id)from solar_private.warehouse_stocks s where product_id=-410011),
      'sales',(select jsonb_agg(to_jsonb(t)order by id)from transactions t where created_by='00000000-0000-0000-0000-000000410013'),
      'requests',(select jsonb_agg(to_jsonb(r)order by request_id)from solar_private.invoice_requests r where user_id='00000000-0000-0000-0000-000000410013'))::text);""")


created = False
try:
    sql('create database "' + CLONE + '" template "' + SOURCE + '";', "postgres")
    created = True
    assert scalar("select enabled from solar_private.wholesale_pricing_control where id") == "f", "Source fixture must have default disabled policy"
    sql("""begin;
      insert into profiles(id,display_name,is_admin,user_type,permissions)values
      ('00000000-0000-0000-0000-000000410011','مدير سباق الأسعار',true,'admin_staff','{}'),
      ('00000000-0000-0000-0000-000000410012','مسؤول سباق الأسعار',false,'admin_staff','{"sale":true,"wholesalePricingManage":true}'),
      ('00000000-0000-0000-0000-000000410013','بائع سباق الأسعار',false,'admin_staff','{"sale":true}');
      insert into products(id,code,name,qty,cost)values(-410011,'WP-RACE','مادة سباق الأسعار',20,100);
      insert into customers(id,name,customer_type,owner_id)values(-410011,'عميل سباق الأسعار','wholesale','00000000-0000-0000-0000-000000410013');
      commit;""")
    sql(as_actor(ADMIN, call("save", str(uuid.uuid4()), {"items": [{"productId": PRODUCT, "minPrice": 1000, "enabled": True, "expectedRevision": 0}]})))

    # Both clients submit the same product revision. Only the lock winner posts.
    nonce_a, nonce_b = str(uuid.uuid4()), str(uuid.uuid4())
    base_revision = product_state()["revision"]
    payload_a = {"items": [{"productId": PRODUCT, "minPrice": 1100, "enabled": True, "expectedRevision": base_revision}]}
    payload_b = {"items": [{"productId": PRODUCT, "minPrice": 1200, "enabled": True, "expectedRevision": base_revision}]}
    result = concurrent_stale("product_revision", call("save", nonce_a, payload_a), call("save", nonce_b, payload_b))
    assert product_state() == {"price": 1100, "revision": base_revision + 1}
    assert scalar("select count(*)from solar_private.finance_requests where request_id=" + quote(nonce_b)) == "0"
    assert scalar("select count(*)from solar_private.wholesale_pricing_audit where request_id=" + quote(nonce_b)) == "0"
    result["loserHasNoWriteOrAudit"] = True
    results.append(result)

    # Both clients read one global revision; a stale toggle cannot emit notices.
    revision = int(scalar("select revision from solar_private.wholesale_pricing_control where id"))
    toggle_a, toggle_b = str(uuid.uuid4()), str(uuid.uuid4())
    result = concurrent_stale("global_revision", call("toggle", toggle_a, {"enabled": True, "expectedRevision": revision}),
                              call("toggle", toggle_b, {"enabled": True, "expectedRevision": revision}))
    assert scalar("select enabled::text||':'||revision from solar_private.wholesale_pricing_control where id") == "true:" + str(revision + 1)
    assert scalar("select count(*)from solar_private.finance_requests where request_id=" + quote(toggle_b)) == "0"
    assert scalar("select count(*)from solar_private.wholesale_pricing_audit where request_id=" + quote(toggle_b)) == "0"
    assert scalar("select count(*)from solar_notifications where user_id=" + quote(SELLER)
                  + " and title='تفعيل الحد الأدنى لأسعار بيع الجملة'") == "1"
    result["oneToggleAndOneNotificationPerRecipient"] = True
    results.append(result)

    # A sale waits behind a committed policy update. Its stale quote must roll
    # back every stock/customer/request change, not merely fail after posting.
    before = financial_fingerprint()
    revision = int(scalar("select revision from solar_private.wholesale_pricing_control where id"))
    price_revision = product_state()["revision"]
    invoice_nonce = str(uuid.uuid4())
    invoice = {"kind": "sale", "mode": "credit", "party": "عميل سباق الأسعار", "sourceCurrency": "IQD",
               "exchangeRate": 1, "wholesalePricingRevision": revision,
               "items": [{"id": PRODUCT, "qty": 2, "price": 1100}]}
    invoice_query = "select public.solar_invoice_save(" + quote(invoice_nonce) + "," + quote(json.dumps(invoice)) + "::jsonb)"
    result = concurrent_stale("sale_vs_policy", call("save", str(uuid.uuid4()), {"items": [{"productId": PRODUCT,
                              "minPrice": 1300, "enabled": True, "expectedRevision": price_revision}]}), invoice_query, SELLER)
    assert financial_fingerprint() == before, "Rejected stale sale changed stock or accounting"
    assert scalar("select count(*)from solar_private.invoice_requests where request_id=" + quote(invoice_nonce)) == "0"
    result["stockAccountsAndInvoiceNonceUnchanged"] = True
    results.append(result)
    OUT.write_text(json.dumps({"pass": True, "source": SOURCE, "isolatedClone": CLONE, "cases": results}, indent=2))
    print("PASS three real two-session pricing races: stale product, stale global toggle, atomic stale sale")
finally:
    for session in sessions:
        if session.poll() is None:
            try:
                session.stdin.write(b"rollback;\\q\n")
                session.stdin.flush()
                session.communicate(timeout=5)
            except Exception:
                session.kill()
                session.communicate()
    if created:
        sql("select pg_terminate_backend(pid)from pg_stat_activity where datname=" + quote(CLONE) + " and pid<>pg_backend_pid();", "postgres")
        sql('drop database "' + CLONE + '";', "postgres")
