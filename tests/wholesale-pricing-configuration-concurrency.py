"""Atomic configuration races with real safeupdate in a disposable LOCAL clone.

Requires both V4.1 migrations and V4.1.1 configuration migration on a clean,
policy-disabled source database. No network database connections are opened.
Configure SOLAR_PRICING_SOURCE_DB, SOLAR_PRICING_POSTGRES_CONTAINER, and
SOLAR_PRICING_CONCURRENCY_RESULTS as needed; remote Docker contexts are ignored.
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

SOURCE = os.environ.get("SOLAR_PRICING_SOURCE_DB", "solar_v411_configuration")
CONTAINER = os.environ.get("SOLAR_PRICING_POSTGRES_CONTAINER", "solar-customers-postgres")
OUT = Path(os.environ.get("SOLAR_PRICING_CONCURRENCY_RESULTS", "/tmp/solar-pricing-configuration-concurrency.json"))
assert re.fullmatch(r"solar_[a-z0-9_]+", SOURCE), "Use a named local test source"
assert re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_.-]*", CONTAINER)
CLONE = "solar_config_race_" + uuid.uuid4().hex[:10]
ENV = {k: v for k, v in os.environ.items() if k not in (
    "DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_TLS", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH")}
BASE = ["docker", "--host=unix:///var/run/docker.sock", "exec", "-i", CONTAINER,
        "psql", "-X", "-U", "postgres", "-At", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"]
ADMIN, MANAGER, SELLER = ["00000000-0000-0000-0000-00000041201" + str(i) for i in (1, 2, 3)]
sessions = []


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def sql(query, database=CLONE, check=True):
    result = subprocess.run(BASE + ["-d", database], input="load 'safeupdate';\n" + query,
                            text=True, capture_output=True, env=ENV, timeout=30)
    if check and result.returncode:
        raise AssertionError(result.stderr)
    return result


def scalar(query):
    return sql(query).stdout.strip().splitlines()[-1]


def as_actor(actor, query):
    return "begin;set local role authenticated;select set_config('request.jwt.claim.sub'," + quote(actor) + ",true);" + query + ";commit;"


def rpc(action, nonce, body):
    return "select public.solar_wholesale_pricing(" + ",".join((quote(action), quote(nonce), quote(json.dumps(body)) + "::jsonb")) + ")"


def race(name, winner, loser, loser_actor=MANAGER):
    session = subprocess.Popen(BASE + ["-d", CLONE], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=ENV)
    sessions.append(session)
    session.stdin.write(("load 'safeupdate';begin;set local role authenticated;select set_config('request.jwt.claim.sub'," + quote(ADMIN)
                         + ",true);select pg_advisory_xact_lock(7311,1);" + winner + ";select 'CONFIG_LOCK_HELD';\n").encode())
    session.stdin.flush()
    deadline, received = time.monotonic() + 10, b""
    while b"CONFIG_LOCK_HELD" not in received:
        if session.poll() is not None:
            raise AssertionError(session.stderr.read().decode())
        assert time.monotonic() < deadline, "Winner did not acquire shared lock"
        if select.select([session.stdout], [], [], 0.1)[0]:
            received += os.read(session.stdout.fileno(), 8192)
    application = "config_" + name
    with ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(sql, "set application_name=" + quote(application) + ";" + as_actor(loser_actor, loser), CLONE, False)
        deadline = time.monotonic() + 8
        while scalar("select exists(select 1 from pg_stat_activity where datname=current_database() and application_name="
                      + quote(application) + " and wait_event_type='Lock')") != "t":
            assert not future.done(), "Second transaction did not wait on shared lock"
            assert time.monotonic() < deadline, "Shared lock wait was not observed"
            time.sleep(0.05)
        session.stdin.write(b"commit;\\q\n")
        session.stdin.flush()
        _, stderr = session.communicate(timeout=15)
        assert session.returncode == 0, stderr.decode()
        result = future.result(timeout=15)
    assert result.returncode != 0 and "PT409" in result.stderr, result.stderr
    return {"case": name, "observedLockWait": True, "loserSqlstate": "PT409"}


def finances():
    return scalar("""select md5(jsonb_build_array(
      (select jsonb_agg(to_jsonb(t)order by id)from transactions t),
      (select jsonb_agg(to_jsonb(t)order by id)from transaction_items t),
      (select jsonb_agg(to_jsonb(t)order by id)from products t),
      (select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),
      (select jsonb_agg(to_jsonb(t)order by request_id)from solar_private.invoice_requests t))::text)""")


created = False
try:
    sql('create database "' + CLONE + '" template "' + SOURCE + '";', "postgres")
    created = True
    assert scalar("select enabled from solar_private.wholesale_pricing_control where id") == "f"
    sql("""insert into profiles(id,display_name,is_admin,user_type,permissions)values
      ('00000000-0000-0000-0000-000000412011','مدير سباق الإعدادات',true,'admin_staff','{}'),
      ('00000000-0000-0000-0000-000000412012','مسؤول سباق الإعدادات',false,'admin_staff','{"sale":true,"wholesalePricingManage":true}'),
      ('00000000-0000-0000-0000-000000412013','بائع سباق الإعدادات',false,'admin_staff','{"sale":true}');
      insert into products(id,code,name,qty,cost)values(-412011,'CONFIG-RACE','مادة اختبار الإعدادات',20,100);
      insert into customers(id,name,customer_type,owner_id)values(-412011,'عميل سباق الإعدادات','wholesale','00000000-0000-0000-0000-000000412013');""")
    sql(as_actor(ADMIN, rpc("save", str(uuid.uuid4()), {"items": [{"productId": -412011, "minPrice": 1000, "enabled": True, "expectedRevision": 0}]})))
    revision = int(scalar("select revision from solar_private.wholesale_pricing_control where id"))
    audit_before = int(scalar("select count(*)from solar_private.wholesale_pricing_audit"))
    notice_before = int(scalar("select count(*)from solar_notifications"))
    recipients = int(scalar("select count(*)from profiles p where active and user_type not in('warehouse','installer')and(is_admin or permissions->>'sale'='true'or permissions->>'wholesalePricingManage'='true')"))
    winner_nonce, loser_nonce = str(uuid.uuid4()), str(uuid.uuid4())
    winner = {"enabled": True, "mode": "selected", "userIds": [SELLER], "expectedRevision": revision}
    loser = {"enabled": False, "mode": "all", "userIds": [], "expectedRevision": revision}
    results = [race("combined_configs", rpc("configure", winner_nonce, winner), rpc("configure", loser_nonce, loser))]
    assert scalar("select enabled::text||':'||scope_mode||':'||revision from solar_private.wholesale_pricing_control where id") == "true:selected:" + str(revision + 1)
    assert scalar("select user_id from solar_private.wholesale_pricing_users") == SELLER
    assert int(scalar("select count(*)from solar_private.wholesale_pricing_audit")) == audit_before + 1
    assert int(scalar("select count(*)from solar_notifications")) == notice_before + recipients
    assert scalar("select count(*)from solar_private.finance_requests where request_id=" + quote(loser_nonce)) == "0"
    results[0]["oneFinalStateAuditAndNoticePerRecipient"] = True
    before = finances()
    invoice_nonce = str(uuid.uuid4())
    invoice = {"kind": "sale", "mode": "credit", "party": "عميل سباق الإعدادات", "sourceCurrency": "IQD", "exchangeRate": 1,
               "wholesalePricingRevision": revision + 1, "items": [{"id": -412011, "qty": 2, "price": 1000}]}
    invoice_query = "select public.solar_invoice_save(" + quote(invoice_nonce) + "," + quote(json.dumps(invoice)) + "::jsonb)"
    results.append(race("sale_vs_combined_config", rpc("configure", str(uuid.uuid4()),
                        {"enabled": False, "mode": "all", "userIds": [], "expectedRevision": revision + 1}), invoice_query, SELLER))
    assert before == finances(), "Stale sale changed stock, invoice history or request state"
    assert scalar("select count(*)from solar_private.invoice_requests where request_id=" + quote(invoice_nonce)) == "0"
    results[1]["financialStateUnchanged"] = True
    assert scalar("show safeupdate.enabled") == "on"
    OUT.write_text(json.dumps({"pass": True, "source": SOURCE, "isolatedClone": CLONE, "safeupdate": True, "cases": results}, indent=2))
    print("PASS two real safeupdate-enabled races: atomic configurations and sale versus combined configuration")
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
        sql("select pg_terminate_backend(pid)from pg_stat_activity where datname=" + quote(CLONE) + " and pid<>pg_backend_pid()", "postgres")
        sql('drop database "' + CLONE + '";', "postgres")
