# Appendix A - Sample Data Generator (`rmi_sample_data.py`)

Use ONLY if the Step 7 data-readiness gate finds insufficient transaction data **and the user confirms** they want sample data.

Recreate this file verbatim as `rmi_sample_data.py` in the task workspace, next to a copy of `config-defaults.json` saved as `config.json` with `org_alias` filled in (build it with Python - do not put double-brace placeholders in shell commands). Requires Python 3 (stdlib only) and the authenticated `sf` CLI.

## What it creates
- **New business across many accounts.** Transactions are spread randomly across every billing-ready account (billing/shipping street + at least one contact), capped at `max_accounts` (default 10) and excluding `exclude_accounts`. Each quote is placed **in the account's own currency** (`CurrencyIsoCode` on the Quote; price book entries resolved per currency), so multi-currency orgs get multi-currency dashboards. Set `sample_data.accounts` to an explicit list of names to restrict it.
- **Subscription lifecycle (lifecycle mode).** Upsells (add quantity), downsells (reduce quantity - shows churn) and renewals on existing active term assets, using the standard asset amend / renew actions -> amendment or renewal quote -> order -> activate. Only *pristine* assets (Initial Sale only) are touched, one action per asset, so re-runs never stack changes. Amendment effective dates are spread over the next 0-30 days; renewals pick the soonest-expiring assets (within `renewal_window_days`) and renew for one year starting the day after the current term ends.

## Modes

| Mode | Writes? | What it does |
|---|---|---|
| `discover` | No | Resolves accounts (name, currency, bill-to contact), standard price book, every product SKU/selling model in each currency, and the number of lifecycle-eligible assets; prints any `missing` items |
| `coverage-simple` | Yes | One single-line quote per simple product on the primary account -> order -> activate. Run before bulk; remove any product that fails from `simple_products` |
| `coverage-bundle` | Yes | One QuantumBit Complete Solution transaction per selling model on the primary account -> order -> activate -> draft invoice -> post |
| `simple <count> <conc>` | Yes | Random 1-4 line quotes across accounts (mixed annual/monthly/evergreen/one-time, ~55% discounted, start dates spread over the last year) -> order -> activate |
| `bundle <count> <conc>` | Yes | Bundle quotes across accounts -> order -> activate -> billing schedules -> draft invoice -> post (DRO + Billing data) |
| `lifecycle <count> <conc>` | Yes | Upsell / downsell / renewal on eligible term assets (mix from `lifecycle_mix`, default 40/30/30) -> quote -> order -> activate. **Run after `simple`** - it needs term assets |

Every run appends one JSON line per transaction to `manifest_<tag>.jsonl` (account, currency, quote/order/invoice IDs, lifecycle kind, quantity change, stage reached, error). Success stages: `order_activated` (simple, lifecycle) or `invoice_post_requested` (bundle).

## Commands - default 50 transactions total

**Default volume: 50 transactions in total** = 30 simple (17 coverage + 13 bulk) + 10 bundle with posted invoices (4 coverage + 6 bulk) + 10 lifecycle (about 4 upsell, 3 downsell, 3 renewal). If coverage drops failing products, raise the bulk counts so the totals stay 30 + 10 + 10. Do not exceed 50 unless the user explicitly asks.

```bash
python3 rmi_sample_data.py config.json discover
python3 rmi_sample_data.py config.json coverage-simple --tag cov-simple
python3 rmi_sample_data.py config.json coverage-bundle --tag cov-bundle
python3 rmi_sample_data.py config.json simple 13 6   --tag bulk-simple --seed 42    # ~4 min
python3 rmi_sample_data.py config.json bundle 6 4    --tag bulk-bundle --seed 21    # ~3 min
python3 rmi_sample_data.py config.json lifecycle 10 3 --tag lifecycle  --seed 63    # ~5 min; run AFTER simple
```
Run long batches in the background (tool timeouts are ~10 min) and poll the manifest.

Summarize results:
```bash
python3 -c "import json,collections,sys; print(collections.Counter((json.loads(l).get('kind','new'), json.loads(l)['stage']) for f in sys.argv[1:] for l in open(f)))" manifest_*.jsonl
```

Verify lifecycle history landed (expect Initial Sale, Upsells, Downsells, Renewals):
```bash
sf data query -o <ORG_ALIAS> -q "SELECT CategoryEnum, COUNT(Id) n FROM AssetAction WHERE CreatedDate = TODAY GROUP BY CategoryEnum"
```

## Notes
- Session expiry is detected and stops the run with `SESSION_EXPIRED` (it is never mistaken for "no data"). Refresh the connection and re-run the shortfall with a new `--tag`.
- Asset amend / renew are asynchronous: the response returns the new quote ID (`amendmentRecordId` - the developer guide also spells it `amendmenRecordId` - or `renewalRecordId`), and the quote is polled until pricing completes before the order is created.
- Downsell never reduces an asset below 1 unit. Downsells and upsells effective in the future change `CurrentQuantity` on their effective date.

## Source

```python
"""Revenue Management Intelligence - sample transaction generator (generalized, multi-account, auto-discovery).

Modes:
  discover                       resolve accounts/contacts/currencies/pricebook/products in the target org (no writes)
  coverage-simple                1 single-line quote per simple product (primary account) -> order -> activate
  coverage-bundle                1 bundle txn per bundle selling model -> order -> activate -> invoice draft -> post
  simple    <count> <conc>       random 1-4 line quotes across accounts -> order -> activate
  bundle    <count> <conc>       bundle quotes across accounts -> order -> activate -> invoice draft -> post
  lifecycle <count> <conc>       upsell / downsell amendments and renewals on existing active term assets
                                 -> amendment/renewal quote -> order -> activate

Usage: python3 rmi_sample_data.py <config.json> <mode> [count] [concurrency] [--tag TAG] [--seed N]
Writes manifest_<tag>.jsonl (one JSON line per transaction) next to the config file.
"""
import json, os, random, subprocess, sys, threading, time, datetime, urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed

CFG = json.load(open(sys.argv[1]))
MODE = sys.argv[2]
ORG = CFG["org_alias"]
V = "/services/data/v" + CFG.get("api_version", "68.0")
SD = CFG["sample_data"]
OK_CALC = ("CompletedWithPricing", "CompletedWithTax", "TaxCalculationSuccess")
BAD_CALC = ("PriceCalculationFailed", "TaxCalculationFailed", "SaveFailedOrIncomplete")
TRANSIENT = ("UNABLE_TO_LOCK_ROW", "REQUEST_LIMIT_EXCEEDED", "SERVER_UNAVAILABLE")
ADDR_KEYS = ("Street", "City", "State", "PostalCode", "Country")
lock = threading.Lock()
asset_lock = threading.Lock()
claimed_assets = set()


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def rest(path, method="GET", body=None, tries=3):
    data = None
    for attempt in range(tries):
        cmd = ["sf", "api", "request", "rest", V + path, "--method", method, "-o", ORG]
        if body is not None:
            cmd += ["--body", json.dumps(body)]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        out, err = proc.stdout.strip(), proc.stderr
        if "Session expired" in err or "INVALID_SESSION_ID" in err:
            raise RuntimeError("SESSION_EXPIRED - refresh the Salesforce connection and resume")
        if not out:
            if proc.returncode != 0 and attempt < tries - 1:
                time.sleep(3 * (attempt + 1)); continue
            if proc.returncode != 0:
                raise RuntimeError("REQUEST_FAILED: " + err.strip()[-300:])
            return None                      # PATCH success returns 204 / empty body
        try:
            data = json.loads(out)
        except json.JSONDecodeError:
            data = {"raw": out[:500]}
        txt = json.dumps(data)
        if "INVALID_SESSION_ID" in txt:
            raise RuntimeError("SESSION_EXPIRED - refresh the Salesforce connection and resume")
        if any(t in txt for t in TRANSIENT) and attempt < tries - 1:
            time.sleep(3 * (attempt + 1)); continue
        return data
    return data


def soql(q):
    d = rest("/query?q=" + urllib.parse.quote(q))
    if isinstance(d, list):
        raise RuntimeError(json.dumps(d)[:300])
    return d.get("records", []) if isinstance(d, dict) else []


def esc(s):
    return s.replace("\\", "\\\\").replace("'", "\\'")


# ---------------------------------------------------------------- discovery
def account_ctx(a, contact_name=None):
    def block(prefix):
        src = {k: a.get(prefix + k) for k in ADDR_KEYS}
        if not src["Street"]:
            other = "Shipping" if prefix == "Billing" else "Billing"
            src = {k: a.get(other + k) for k in ADDR_KEYS}
        return src
    cons = (a.get("Contacts") or {}).get("records", [])
    if contact_name:
        cons = [c for c in cons if c["Name"] == contact_name] or cons
    if not cons or not block("Billing")["Street"]:
        return None
    return {"id": a["Id"], "name": a["Name"], "currency": a.get("CurrencyIsoCode") or "USD",
            "bill_addr": block("Billing"), "ship_addr": block("Shipping"), "contact": cons[0]["Id"], "contact_name": cons[0]["Name"]}


def discover():
    acc_cfg = SD.get("accounts", "auto")
    base = ("SELECT Id, Name, CurrencyIsoCode, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry, "
            "ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry, "
            "(SELECT Id, Name FROM Contacts ORDER BY CreatedDate LIMIT 5) FROM Account")
    if acc_cfg == "auto":
        rows = soql(base + " WHERE (BillingStreet != null OR ShippingStreet != null) ORDER BY Name LIMIT 200")
        excl = {x.lower() for x in SD.get("exclude_accounts", [])}
        rows = [r for r in rows if r["Name"].lower() not in excl]
    else:
        names = ",".join(f"'{esc(n)}'" for n in acc_cfg)
        rows = soql(base + f" WHERE Name IN ({names})")
    accounts = [x for x in (account_ctx(r, SD.get("bill_to_contact_name")) for r in rows) if x]
    primary_name = SD.get("primary_account", SD.get("account_name", "Acme"))
    accounts.sort(key=lambda x: (x["name"] != primary_name, x["name"]))
    accounts = accounts[: int(SD.get("max_accounts", 10))]
    if not accounts:
        raise SystemExit("No billing-ready accounts (need billing/shipping street + at least one contact). Fix accounts or set sample_data.accounts")
    pb = soql("SELECT Id FROM Pricebook2 WHERE IsStandard = true AND IsActive = true LIMIT 1")
    if not pb:
        raise SystemExit("No active Standard Price Book")

    cache = {}
    def pbe(sku, model, cur):
        key = (sku, model, cur)
        if key in cache: return cache[key]
        r = soql(f"SELECT Id, Product2Id, Product2.Name, UnitPrice, ProductSellingModel.SellingModelType "
                 f"FROM PricebookEntry WHERE IsActive = true AND Pricebook2.IsStandard = true AND CurrencyIsoCode = '{cur}' "
                 f"AND Product2.StockKeepingUnit = '{esc(sku)}' AND ProductSellingModel.Name = '{esc(model)}' LIMIT 1")
        val = None
        if r:
            r = r[0]; smt = r["ProductSellingModel"]["SellingModelType"]
            kind = {"OneTime": "OT", "Evergreen": "EV"}.get(smt, "TM" if "Month" in model else "TA")
            val = {"pbe": r["Id"], "product": r["Product2Id"], "name": r["Product2"]["Name"], "sku": sku, "model": model, "kind": kind, "price": r["UnitPrice"]}
        cache[key] = val
        return val

    currencies = sorted({a["currency"] for a in accounts})
    simple, bundle, missing = {}, {}, []
    for cur in currencies:
        simple[cur] = []
        for p in SD["simple_products"]:
            x = pbe(p["sku"], p["model"], cur)
            (simple[cur].append(x) if x else missing.append({**p, "currency": cur}))
        bundle[cur] = []
        for m in SD["bundle_product"]["models_with_weights"]:
            x = pbe(SD["bundle_product"]["sku"], m["model"], cur)
            if x: bundle[cur].append({**x, "weight": m["weight"]})
            else: missing.append({"sku": SD["bundle_product"]["sku"], "model": m["model"], "currency": cur})
    # drop accounts whose currency has no usable products
    accounts = [a for a in accounts if simple.get(a["currency"]) and bundle.get(a["currency"])] or accounts
    return {"accounts": accounts, "pricebook": pb[0]["Id"], "simple": simple, "bundle": bundle, "missing": missing}


# ---------------------------------------------------------------- lifecycle helpers
def wait(fn, tries, delay):
    for _ in range(tries):
        time.sleep(delay)
        v = fn()
        if v: return v
    return None


def line_record(rng, p, start, ref, bundle=False):
    r = {"attributes": {"type": "QuoteLineItem", "method": "POST"}, "QuoteId": "@{refQuote.id}",
         "Product2Id": p["product"], "PricebookEntryId": p["pbe"], "StartDate": start}
    if bundle:
        r["Quantity"] = str(rng.choice([1, 1, 1, 2, 3]))
    elif p["kind"] == "OT":
        r["Quantity"] = str(rng.choice([1, 1, 2, 3, 5, 10]))
    else:
        r["Quantity"] = str(rng.choice([1, 2, 5, 10, 20, 50]))
    if p["kind"] == "TA":   # selling model comes from the PBE; dates/terms must match it
        r.update(SubscriptionTerm=rng.choice([1, 1, 2, 3]), SubscriptionTermUnit="Annual", BillingFrequency="Annual", PeriodBoundary="Anniversary")
    elif p["kind"] == "TM":
        r.update(SubscriptionTerm=rng.choice([6, 12, 24]), SubscriptionTermUnit="Months", BillingFrequency="Monthly", PeriodBoundary="Anniversary")
    elif p["kind"] == "EV":  # no EndDate / term for evergreen
        r.update(BillingFrequency="Monthly", PeriodBoundary="Anniversary")
    if not bundle and rng.random() < SD.get("discount_probability", 0.55):
        r["Discount"] = rng.choice([5, 10, 12.5, 15, 20, 25, 30])
    return {"referenceId": ref, "record": r}


def quote_to_activated_order(m, qid, acct, invoice=False, tag="", idx=0):
    """Shared tail: wait for pricing -> createOrderFromQuote -> addresses/contacts -> activate [-> invoice + post]."""
    def calc():
        rec = soql(f"SELECT CalculationStatus, GrandTotal FROM Quote WHERE Id = '{qid}'")
        if rec and (rec[0]["CalculationStatus"] in OK_CALC or rec[0]["CalculationStatus"] in BAD_CALC): return rec[0]
    rec = wait(calc, 48, 5)              # amendment/renewal quotes are created asynchronously - allow longer
    if not rec or rec["CalculationStatus"] not in OK_CALC:
        m.update(stage="quote_pricing_failed", calc=rec); return m
    m.update(grand_total=rec["GrandTotal"], stage="quote_priced")
    o = rest("/actions/standard/createOrderFromQuote", "POST", {"inputs": [{"quoteRecordId": qid}]})
    if not isinstance(o, list) or not o[0].get("isSuccess"):
        m.update(stage="order_failed", error=json.dumps(o)[:400]); return m
    oid = o[0]["outputValues"]["orderId"]
    m.update(order_id=oid, order_number=o[0]["outputValues"].get("orderNumber"), stage="order_created")
    patch = {"BillToContactId": acct["contact"], "ShipToContactId": acct["contact"]}
    for k, v in acct["bill_addr"].items(): patch["Billing" + k] = v
    for k, v in acct["ship_addr"].items(): patch["Shipping" + k] = v
    e = rest(f"/sobjects/Order/{oid}", "PATCH", patch) or rest(f"/sobjects/Order/{oid}", "PATCH", {"Status": "Activated"})
    if e:
        m.update(stage="activation_failed", error=json.dumps(e)[:400]); return m
    m["stage"] = "order_activated"
    if not invoice:
        return m
    def bss():
        ids = [x["Id"] for x in soql(f"SELECT Id FROM BillingSchedule WHERE ReferenceEntityId = '{oid}'")]
        return ids or None
    bs = wait(bss, 24, 5)
    if not bs:
        m.update(stage="no_billing_schedules"); return m
    time.sleep(5); bs = bss() or bs
    m.update(billing_schedules=len(bs), stage="billing_ready")
    today = datetime.date.today().isoformat()
    g = rest("/commerce/invoicing/invoices/collection/actions/generate", "POST",
             {"billingScheduleIds": bs, "action": "Draft", "invoiceDate": today, "targetDate": today, "correlationId": f"rmi-{tag}-{idx}"})
    if not isinstance(g, dict) or not g.get("success"):
        m.update(stage="invoice_generate_failed", error=json.dumps(g)[:400]); return m
    idlist = ",".join(f"'{b}'" for b in bs)
    def inv():
        rows = soql(f"SELECT InvoiceId FROM InvoiceLine WHERE BillingScheduleId IN ({idlist})")
        return sorted({x["InvoiceId"] for x in rows}) or None
    invs = wait(inv, 24, 5)
    if not invs:
        m.update(stage="invoice_draft_timeout"); return m
    m.update(invoice_ids=invs, stage="invoice_draft")
    p = rest("/commerce/invoicing/invoices/collection/actions/post", "POST", {"invoiceIds": invs, "correlationId": f"rmi-{tag}-{idx}"})
    if not isinstance(p, dict) or not p.get("success"):
        m.update(stage="invoice_post_failed", error=json.dumps(p)[:400]); return m
    m["stage"] = "invoice_post_requested"
    return m


def run_new_sale(ctx, idx, tag, seed, lines_fn, pick_account, invoice):
    rng = random.Random(seed * 100000 + idx)
    m = {"idx": idx, "tag": tag, "stage": "start"}; t0 = time.time()
    try:
        acct = pick_account(rng, idx)
        start = (datetime.date.today() - datetime.timedelta(days=rng.randint(0, SD.get("start_date_spread_days", 365)))).isoformat()
        lines, desc = lines_fn(rng, start, idx, acct["currency"])
        m.update(account=acct["name"], currency=acct["currency"], start_date=start, lines=desc)
        body = {"pricingPref": "System", "taxPref": "Skip", "graph": {"graphId": "createQuote", "records": [
            {"referenceId": "refQuote", "record": {"attributes": {"method": "POST", "type": "Quote"},
             "Name": f"RMI Sample {tag}-{idx:04d} - {acct['name']}", "QuoteAccountId": acct["id"],
             "Pricebook2Id": ctx["pricebook"], "CurrencyIsoCode": acct["currency"]}}] + lines}}
        r = rest("/connect/rev/sales-transaction/actions/place", "POST", body)
        if not isinstance(r, dict) or not r.get("isSuccess"):
            m.update(stage="quote_failed", error=json.dumps(r)[:400]); return m
        qid = r["salesTransactionId"]; m.update(quote_id=qid, stage="quote_placed")
        return quote_to_activated_order(m, qid, acct, invoice, tag, idx)
    except Exception as ex:  # noqa
        m.update(stage=m.get("stage", "?") + "_exception", error=str(ex)[:400]); return m
    finally:
        m["secs"] = round(time.time() - t0, 1)


# ---------------------------------------------------------------- amendments / renewals
def eligible_assets(ctx):
    """Active, pristine (Initial Sale only), term-defined assets from simple products on the selected accounts."""
    acct_ids = ",".join(f"'{a['id']}'" for a in ctx["accounts"])
    term_skus = sorted({p["sku"] for p in SD["simple_products"] if p["model"].startswith("Term")})
    skus = ",".join(f"'{esc(s)}'" for s in term_skus)
    today = datetime.date.today()
    rows = soql("SELECT Id, AccountId, CurrentQuantity, LifecycleStartDate, LifecycleEndDate, Product2.StockKeepingUnit, "
                "(SELECT CategoryEnum FROM AssetActions) FROM Asset "
                f"WHERE AccountId IN ({acct_ids}) AND Product2.StockKeepingUnit IN ({skus}) AND CurrentQuantity > 1 "
                f"AND LifecycleEndDate > {today.isoformat()}T00:00:00Z AND ParentId = null ORDER BY LifecycleEndDate LIMIT 500")
    out = []
    for r in rows:
        acts = [a["CategoryEnum"] for a in ((r.get("AssetActions") or {}).get("records") or [])]
        if acts != ["Initial Sale"]:
            continue      # skip assets that already have lifecycle history (re-runs stay additive, never stack)
        out.append(r)
    return out


def run_lifecycle(ctx, idx, tag, seed, asset_pool, weights):
    rng = random.Random(seed * 100000 + idx)
    m = {"idx": idx, "tag": tag, "stage": "start"}; t0 = time.time()
    try:
        kind = rng.choices(["upsell", "downsell", "renewal"], weights=[weights["upsell"], weights["downsell"], weights["renewal"]])[0]
        window = SD.get("renewal_window_days", 400)
        today = datetime.date.today()
        days = lambda x: (datetime.date.fromisoformat(x["LifecycleEndDate"][:10]) - today).days
        with asset_lock:
            free = [a for a in asset_pool if a["Id"] not in claimed_assets]
            if not free:
                m.update(stage="no_eligible_asset"); return m
            if kind == "renewal":
                due = sorted([a for a in free if 1 <= days(a) <= window], key=days)
                if due:
                    a = rng.choice(due[: max(3, len(due) // 3)])   # favour soonest-expiring (renewal due) assets
                else:
                    kind = "upsell"; a = rng.choice(free)
            else:
                a = rng.choice([x for x in free if days(x) > 3] or free)  # leave room for the amendment date
            claimed_assets.add(a["Id"])
        acct = next(x for x in ctx["accounts"] if x["id"] == a["AccountId"])
        end = datetime.date.fromisoformat(a["LifecycleEndDate"][:10])
        days_left = (end - today).days
        qty = int(a["CurrentQuantity"])
        m.update(kind=kind, asset_id=a["Id"], account=acct["name"], currency=acct["currency"], sku=a["Product2"]["StockKeepingUnit"], qty_before=qty)
        if kind in ("upsell", "downsell"):
            start = datetime.date.today() + datetime.timedelta(days=rng.randint(0, max(0, min(30, days_left - 2))))
            change = rng.choice([1, 2, 3, 5, 10]) if kind == "upsell" else -max(1, min(qty - 1, int(round(qty * rng.choice([0.1, 0.2, 0.3, 0.5])))))
            m.update(quantity_change=change, effective=start.isoformat())
            r = rest("/connect/revenue-management/assets/actions/amend", "POST",
                     {"assetIds": [a["Id"]], "amendmentStartDate": f"{start.isoformat()}T00:00:00", "outputRecordType": "Quote", "quantityChange": change})
            qid = isinstance(r, dict) and (r.get("amendmentRecordId") or r.get("amendmenRecordId"))
        else:
            rs = end + datetime.timedelta(days=1)
            re_ = rs.replace(year=rs.year + 1) - datetime.timedelta(days=1)
            m.update(renewal_start=rs.isoformat(), renewal_end=re_.isoformat())
            r = rest("/connect/revenue-management/assets/actions/renew", "POST",
                     {"assetIds": [a["Id"]], "outputRecordType": "Quote",
                      "renewalStartDate": f"{rs.isoformat()}T00:00:00", "renewalEndDate": f"{re_.isoformat()}T23:59:59"})
            qid = isinstance(r, dict) and r.get("renewalRecordId")
        if not qid or not r.get("success", True):
            m.update(stage=f"{kind}_request_failed", error=json.dumps(r)[:400]); return m
        m.update(quote_id=qid, stage=f"{kind}_quote_requested")
        return quote_to_activated_order(m, qid, acct, False, tag, idx)
    except Exception as ex:  # noqa
        m.update(stage=m.get("stage", "?") + "_exception", error=str(ex)[:400]); return m
    finally:
        m["secs"] = round(time.time() - t0, 1)


# ---------------------------------------------------------------- main
def main():
    ctx = discover()
    accounts = ctx["accounts"]
    if MODE == "discover":
        print("accounts:", json.dumps([(a["name"], a["currency"], a["contact_name"]) for a in accounts]))
        print("pricebook:", ctx["pricebook"], "| missing:", json.dumps(ctx["missing"]))
        for cur in sorted(ctx["simple"]):
            print(cur, "simple:", len(ctx["simple"][cur]), "bundle models:", [b["model"] for b in ctx["bundle"][cur]])
        try:
            print("eligible assets for lifecycle:", len(eligible_assets(ctx)))
        except Exception as ex:  # noqa
            print("eligible assets: n/a", ex)
        return
    seed = int(arg("--seed", "7"))
    primary = accounts[0]
    spread = lambda rng, idx: rng.choice(accounts)
    tag = arg("--tag", MODE + "-" + datetime.datetime.utcnow().strftime("%H%M%S"))
    if MODE == "coverage-simple":
        pool = ctx["simple"][primary["currency"]]; count, conc = len(pool), 4
        job = lambda i: run_new_sale(ctx, i, tag, seed,
                                     lambda rng, s, idx, cur: ([line_record(rng, pool[idx - 1], s, "refLine0")], [pool[idx - 1]["sku"] + "/" + pool[idx - 1]["model"]]),
                                     lambda rng, idx: primary, False)
    elif MODE == "coverage-bundle":
        pool = ctx["bundle"][primary["currency"]]; count, conc = len(pool), 4
        job = lambda i: run_new_sale(ctx, i, tag, seed,
                                     lambda rng, s, idx, cur: ([line_record(rng, pool[idx - 1], s, "refLine0", bundle=True)], [pool[idx - 1]["model"]]),
                                     lambda rng, idx: primary, True)
    elif MODE == "simple":
        count, conc = int(sys.argv[3]), int(sys.argv[4])
        def lines_fn(rng, s, idx, cur):
            n = rng.choices([1, 2, 3, 4], weights=[35, 35, 20, 10])[0]
            picks = rng.sample(ctx["simple"][cur], min(n, len(ctx["simple"][cur])))
            return [line_record(rng, p, s, f"refLine{i}") for i, p in enumerate(picks)], [p["sku"] + "/" + p["model"] for p in picks]
        job = lambda i: run_new_sale(ctx, i, tag, seed, lines_fn, spread, False)
    elif MODE == "bundle":
        count, conc = int(sys.argv[3]), int(sys.argv[4])
        def lines_fn(rng, s, idx, cur):
            p = rng.choices(ctx["bundle"][cur], weights=[b["weight"] for b in ctx["bundle"][cur]])[0]
            return [line_record(rng, p, s, "refLine0", bundle=True)], [p["model"]]
        job = lambda i: run_new_sale(ctx, i, tag, seed, lines_fn, spread, True)
    elif MODE == "lifecycle":
        count, conc = int(sys.argv[3]), int(sys.argv[4])
        pool = eligible_assets(ctx)
        print(f"eligible pristine term assets: {len(pool)}", flush=True)
        if not pool:
            raise SystemExit("No eligible assets - run the simple mode first (term subscriptions create renewable assets)")
        weights = SD.get("lifecycle_mix", {"upsell": 40, "downsell": 30, "renewal": 30})
        job = lambda i: run_lifecycle(ctx, i, tag, seed, pool, weights)
    else:
        raise SystemExit("unknown mode " + MODE)
    out = os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), f"manifest_{tag}.jsonl")
    stages = {}; done = 0
    with ThreadPoolExecutor(max_workers=conc) as ex, open(out, "a") as f:
        futs = [ex.submit(job, i) for i in range(1, count + 1)]
        for fu in as_completed(futs):
            m = fu.result(); done += 1; stages[m["stage"]] = stages.get(m["stage"], 0) + 1
            with lock:
                f.write(json.dumps(m) + "\n"); f.flush()
            if m["stage"] not in ("order_activated", "invoice_post_requested") or done % 10 == 0 or count <= 20:
                print(f"[{done}/{count}] #{m['idx']} {m.get('kind', '')} {m['stage']} {m.get('order_number', '')} {m.get('account', '')} {m.get('currency', '')} "
                      f"{m.get('lines', m.get('quantity_change', ''))} {(m.get('error') or '')[:200]}", flush=True)
    print("SUMMARY", json.dumps(stages), "manifest:", out, flush=True)


if __name__ == "__main__":
    main()
```
