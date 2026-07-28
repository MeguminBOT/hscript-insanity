"""Collate the per-library benchmark lines into comparison tables, grouped by scale."""
import sys, collections

# Preferred column order. A library with no rows in the results is dropped rather than emptying the
# comparison, so running against a subset of checkouts produces a table for that subset.
PREFERRED = [
    "ours",
    "insanity-upstream",
    "hscript-pos",
    "hscript-improved-pos",
    "hscript-iris-pos",
    "rulescript-pos",
    "hscript",
    "hscript-improved",
    "hscript-iris",
    "rulescript",
]
LABEL = {
    "ours": "this fork",
    "insanity-upstream": "insanity",
    "hscript-pos": "hscript",
    "hscript-improved-pos": "improved",
    "hscript-iris-pos": "iris",
    "rulescript-pos": "rulescript",
    "hscript": "hscript no-pos",
    "hscript-improved": "improved no-pos",
    "hscript-iris": "iris no-pos",
    "rulescript": "rulescript no-pos",
}
# Libraries that always track positions, so they have no separate -pos build.
NOPOS = {"hscript", "hscript-improved", "hscript-iris", "rulescript"}

# case -> scale -> lib -> (status, ms, value)
rows = collections.defaultdict(lambda: collections.defaultdict(dict))
parse = {}
tier = {}
order = []
scales = []

for raw in open(sys.argv[1]):
    raw = raw.strip()
    if raw.startswith("R|"):
        _, lib, case, t, iters, status, ms, value = raw.split("|", 7)
        n = int(iters) if iters.isdigit() else 0
        if case not in tier:
            tier[case] = t
            order.append(case)
        elif t != "?":
            tier[case] = t
        if n and n not in scales:
            scales.append(n)
        rows[case][n][lib] = (status, ms, value)
    elif raw.startswith("P|"):
        parts = raw.split("|")
        parse[parts[1]] = parts[3] if len(parts) > 3 else "crash"

scales.sort()
seen = {lib for c in rows for n in rows[c] for lib in rows[c][n]} | set(parse)
LIBS = [l for l in PREFERRED if l in seen]
MAIN = [l for l in LIBS if l not in NOPOS]


CALLS = ["call0", "call1", "call3", "fnTyped", "classCall"]
UNWIND = ["loopCont", "tryCatch"]


def cell(rec):
    if rec is None:
        return "n/a"
    status, ms, value = rec
    if status == "ok":
        return ms
    if status == "unsupported":
        return "not supported"
    if status == "crash":
        return "CRASH"
    if status == "wrong":
        return f"WRONG ({value})"
    return status


def per_iter(rec, n):
    """Microseconds per iteration, or the status text when the case did not run."""
    if rec is None or rec[0] != "ok" or not n:
        return cell(rec)
    return "%.3f" % (float(rec[1]) * 1000.0 / n)


def ok(case, n, lib):
    return rows[case][n].get(lib, ("x",))[0] == "ok"


def shared(n, libs):
    """Cases every one of `libs` ran correctly at scale `n`."""
    return [c for c in order if n in rows[c] and all(ok(c, n, l) for l in libs)]


def avg(lib, cases, n):
    vals = [float(rows[c][n][lib][1]) * 1000.0 / n for c in cases if ok(c, n, lib)]
    return sum(vals) / len(vals) if vals else 0.0



def chart(title, unit, pairs, sort=True):
    """A single-series bar chart. Mermaid's xychart-beta has no legend, so every chart here plots one
    series and puts the comparison on the x-axis, where it needs no key to read."""
    pairs = [(l, v) for l, v in pairs if v is not None]
    if not pairs:
        return
    if sort:
        pairs.sort(key=lambda t: t[1])
    top = max(v for _, v in pairs)
    top = round(top * 1.15, 3) if top < 10 else int(top * 1.15)
    # Decimals follow the VALUES, not the axis top. Keying them off the top rounded a chart whose
    # axis happened to reach 11 down to whole numbers, turning 1.391 and 8.467 into 1 and 8.
    dec = "%.3f" if top < 20 else ("%.1f" if top < 1000 else "%.0f")
    print("")
    print("```mermaid")
    print("xychart-beta")
    print(f'    title "{title}"')
    print("    x-axis [" + ", ".join('"%s"' % l for l, _ in pairs) + "]")
    print(f'    y-axis "{unit}" 0 --> {top}')
    print("    bar [" + ", ".join(dec % v for _, v in pairs) + "]")
    print("```")


def table(cases, n, libs, title, fmt):
    print(f"\n#### {title}\n")
    print("| case | " + " | ".join(LABEL[l] for l in libs) + " |")
    print("| --- |" + " --- |" * len(libs))
    for c in cases:
        print(f"| `{c}` | " + " | ".join(fmt(rows[c][n].get(l), n) for l in libs) + " |")


for n in scales:
    print(f"\n### {n:,} iterations\n")
    core = [c for c in order if tier.get(c) == "core" and n in rows[c]]
    ext = [c for c in order if tier.get(c) != "core" and n in rows[c]]
    # No chart for the per-case tables. A chart can only carry one series legibly (Mermaid has no
    # legend), and one series means one library, which shows nothing the six-library table does not
    # already show better. The comparison is the point of these tables.
    for cases, name in ((core, "Core"), (ext, "Extended")):
        table(cases, n, MAIN, f"{name} cases, microseconds per iteration", per_iter)

    sh = shared(n, MAIN)
    perop = [c for c in sh if c not in CALLS and c not in UNWIND]
    callc = [c for c in sh if c in CALLS]
    print(f"\n#### Averages over the {len(perop)} operation and {len(callc)} call cases every library ran\n")
    print("| | " + " | ".join(LABEL[l] for l in MAIN) + " |")
    print("| --- |" + " --- |" * len(MAIN))
    print("| us per operation | " + " | ".join("%.3f" % avg(l, perop, n) for l in MAIN) + " |")
    print("| us per call | " + " | ".join("%.3f" % avg(l, callc, n) for l in MAIN) + " |")
    chart(f"Cost of one operation at {n:,} iterations", "microseconds", [(LABEL[l], avg(l, perop, n)) for l in MAIN])
    chart(f"Cost of one call at {n:,} iterations", "microseconds", [(LABEL[l], avg(l, callc, n)) for l in MAIN])

# Totals over the shared cases, per scale. Dominated by the call cases, so they are reported
# alongside the per-operation and per-call averages rather than instead of them.
print("\n### Total over the shared cases, per scale (ms)\n")
print("| iterations | cases | " + " | ".join(LABEL[l] for l in MAIN) + " |")
print("| --- | --- |" + " --- |" * len(MAIN))
for n in scales:
    sh = shared(n, MAIN)
    tot = {l: sum(float(rows[c][n][l][1]) for c in sh) for l in MAIN}
    print(f"| {n:,} | {len(sh)} | " + " | ".join("%.0f" % tot[l] for l in MAIN) + " |")
for n in scales:
    sh = shared(n, MAIN)
    tot = {l: sum(float(rows[c][n][l][1]) for c in sh) for l in MAIN}
    chart(f"Total over {len(sh)} shared cases at {n:,} iterations", "milliseconds", [(LABEL[l], tot[l]) for l in MAIN])
print("\nRelative to this fork:\n")
print("| iterations | " + " | ".join(LABEL[l] for l in MAIN) + " |")
print("| --- |" + " --- |" * len(MAIN))
for n in scales:
    sh = shared(n, MAIN)
    tot = {l: sum(float(rows[c][n][l][1]) for c in sh) for l in MAIN}
    base = tot["ours"] if tot.get("ours") else 1.0
    print(f"| {n:,} | " + " | ".join("%.2fx" % (tot[l] / base) for l in MAIN) + " |")
_big = scales[-1]
_sh = shared(_big, MAIN)
_tot = {l: sum(float(rows[c][_big][l][1]) for c in _sh) for l in MAIN}
_base = _tot["ours"] if _tot.get("ours") else 1.0
chart(f"Total relative to this fork, at {_big:,} iterations", "times slower", [(LABEL[l], _tot[l] / _base) for l in MAIN])

print("\n### Parse throughput (11.6KB source, ms)\n")
print("| " + " | ".join(LABEL[l] for l in LIBS) + " |")
print("|" + " --- |" * len(LIBS))
print("| " + " | ".join(parse.get(l, "n/a") for l in LIBS) + " |")
def _pf(l):
    v = parse.get(l)
    try:
        return float(v)
    except (TypeError, ValueError):
        return None
chart("Parse time for an 11.6KB script", "milliseconds", [(LABEL[l], _pf(l)) for l in MAIN])

def _spread(kind):
    out = []
    for l in MAIN:
        vals = []
        for n in scales:
            sh = shared(n, MAIN)
            cs = [c for c in sh if c in CALLS] if kind == "call" else [c for c in sh if c not in CALLS and c not in UNWIND]
            vals.append(avg(l, cs, n))
        vals = [v for v in vals if v]
        out.append((LABEL[l], (max(vals) - min(vals)) / min(vals) * 100.0 if vals else 0.0))
    return out

# How stable the ranking is across scale: the per-operation average at each scale, side by side.
print("\n### Per-operation average across scales (us)\n")
print("| iterations | " + " | ".join(LABEL[l] for l in MAIN) + " |")
print("| --- |" + " --- |" * len(MAIN))
for n in scales:
    sh = shared(n, MAIN)
    perop = [c for c in sh if c not in CALLS and c not in UNWIND]
    print(f"| {n:,} | " + " | ".join("%.3f" % avg(l, perop, n) for l in MAIN) + " |")
chart("Per-operation cost, variation across a 20x change in scale", "percent", _spread("op"))

print("\n### Per-call average across scales (us)\n")
print("| iterations | " + " | ".join(LABEL[l] for l in MAIN) + " |")
print("| --- |" + " --- |" * len(MAIN))
for n in scales:
    sh = shared(n, MAIN)
    callc = [c for c in sh if c in CALLS]
    print(f"| {n:,} | " + " | ".join("%.3f" % avg(l, callc, n) for l in MAIN) + " |")
chart("Per-call cost, variation across a 20x change in scale", "percent", _spread("call"))

# The position-tracking builds, kept separate so they cannot be mistaken for the fair comparison.
if any(l in seen for l in NOPOS):
    print("\n### The same libraries built without position tracking, per-operation average (us)\n")
    pairs = [("hscript-pos", "hscript"), ("hscript-improved-pos", "hscript-improved"), ("hscript-iris-pos", "hscript-iris"),
             ("rulescript-pos", "rulescript")]
    pairs = [(a, b) for a, b in pairs if a in seen and b in seen]
    print("| iterations | " + " | ".join(f"{LABEL[a]} | {LABEL[b]}" for a, b in pairs) + " |")
    print("| --- |" + " --- |" * (2 * len(pairs)))
    for n in scales:
        sh = shared(n, [l for p in pairs for l in p])
        perop = [c for c in sh if c not in CALLS and c not in UNWIND]
        cells = []
        for a, b in pairs:
            cells += ["%.3f" % avg(a, perop, n), "%.3f" % avg(b, perop, n)]
        print(f"| {n:,} | " + " | ".join(cells) + " |")
    _big = scales[-1]
    _sh = shared(_big, [l for pr in pairs for l in pr])
    _op = [c for c in _sh if c not in CALLS and c not in UNWIND]
    chart(f"What position tracking costs per operation, at {_big:,} iterations", "percent",
          [(LABEL[a], (avg(a, _op, _big) / avg(b, _op, _big) - 1) * 100.0) for a, b in pairs if avg(b, _op, _big)])
    print("\n| | " + " | ".join(f"{LABEL[a]} | {LABEL[b]}" for a, b in pairs) + " |")
    print("| --- |" + " --- |" * (2 * len(pairs)))
    print("| parse (ms) | " + " | ".join(f"{parse.get(a,'n/a')} | {parse.get(b,'n/a')}" for a, b in pairs) + " |")
    chart("What position tracking costs at parse time", "percent",
          [(LABEL[a], (_pf(a) / _pf(b) - 1) * 100.0) for a, b in pairs if _pf(a) and _pf(b)])
