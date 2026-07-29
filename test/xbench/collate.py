"""Collate the per-library benchmark lines into ONE per-case list plus compact summaries.

Deliberately one table of record. An earlier version printed the whole corpus once per scale, plus
totals, plus averages, plus a chart for each -- eighteen tables and eighteen charts saying a handful
of things repeatedly, which is a lot to keep consistent by hand when a single number changes. What
comes out now is one list at a reference scale, a summary, and the evidence that the ranking does not
depend on the scale. Everything else was restatement.
"""
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

# The scale everything not explicitly about scale is reported at.
REF = scales[-1] if scales else 0

CALLS = ["call0", "call1", "call3", "callCap20", "fnTyped", "classCall"]
UNWIND = ["loopCont", "tryCatch"]


def kind(case):
    """Which average a case feeds, which is also why a reader should or should not compare it."""
    if case in CALLS:
        return "call"
    if case in UNWIND:
        return "unwind"
    return "op"


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
    series and puts the comparison on the x-axis, where it needs no key to read.

    Used twice in the whole document, for the two figures the trade-off turns on. A chart of a number
    already in a table beside it is duplication, not illustration."""
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


# ---------------------------------------------------------------- the list

print(f"\n### Every case, microseconds per iteration at {REF:,}\n")
print("One row per case, and the only per-case table in this document. `kind` is which average the")
print("row feeds: `op` and `call` are averaged separately because they differ by design rather than")
print("by degree, and `unwind` cases are in neither, being dominated by how a library implements")
print("`continue` and `throw`.\n")
print("| case | kind | " + " | ".join(LABEL[l] for l in MAIN) + " |")
print("| --- | --- |" + " --- |" * len(MAIN))
for c in order:
    if REF not in rows[c]:
        continue
    print(f"| `{c}` | {kind(c)} | " + " | ".join(per_iter(rows[c][REF].get(l), REF) for l in MAIN) + " |")

# ---------------------------------------------------------------- summary

sh = shared(REF, MAIN)
perop = [c for c in sh if kind(c) == "op"]
callc = [c for c in sh if kind(c) == "call"]
tot = {l: sum(float(rows[c][REF][l][1]) for c in sh) for l in MAIN}
base = tot["ours"] if tot.get("ours") else 1.0

print(f"\n### Summary, over the {len(sh)} cases every library ran\n")
print("| | " + " | ".join(LABEL[l] for l in MAIN) + " |")
print("| --- |" + " --- |" * len(MAIN))
print(f"| us per operation ({len(perop)} cases) | " + " | ".join("%.3f" % avg(l, perop, REF) for l in MAIN) + " |")
print(f"| us per call ({len(callc)} cases) | " + " | ".join("%.3f" % avg(l, callc, REF) for l in MAIN) + " |")
print("| parse, ms | " + " | ".join(str(parse.get(l, "n/a")) for l in MAIN) + " |")
print("| corpus total, ms | " + " | ".join("%.0f" % tot[l] for l in MAIN) + " |")
print("| total relative to this fork | " + " | ".join("%.2fx" % (tot[l] / base) for l in MAIN) + " |")

chart(f"Cost of one operation at {REF:,} iterations", "microseconds", [(LABEL[l], avg(l, perop, REF)) for l in MAIN])
chart(f"Cost of one call at {REF:,} iterations", "microseconds", [(LABEL[l], avg(l, callc, REF)) for l in MAIN])

# ---------------------------------------------------------------- scale

print("\n### The ranking does not depend on the scale\n")
print("The whole corpus at each scale. If a difference only showed up at one size it would be a")
print("warm-up or fixed-setup artefact rather than a property of the interpreter.\n")
print("| | " + " | ".join(LABEL[l] for l in MAIN) + " |")
print("| --- |" + " --- |" * len(MAIN))
for n in scales:
    s = shared(n, MAIN)
    cs = [c for c in s if kind(c) == "op"]
    print(f"| us per operation, {n:,} | " + " | ".join("%.3f" % avg(l, cs, n) for l in MAIN) + " |")
for n in scales:
    s = shared(n, MAIN)
    cs = [c for c in s if kind(c) == "call"]
    print(f"| us per call, {n:,} | " + " | ".join("%.3f" % avg(l, cs, n) for l in MAIN) + " |")


def spread(kind_name):
    out = []
    for l in MAIN:
        vals = []
        for n in scales:
            s = shared(n, MAIN)
            cs = [c for c in s if kind(c) == kind_name]
            vals.append(avg(l, cs, n))
        vals = [v for v in vals if v]
        out.append("%.1f%%" % ((max(vals) - min(vals)) / min(vals) * 100.0) if vals else "n/a")
    return out


print("| spread, operations | " + " | ".join(spread("op")) + " |")
print("| spread, calls | " + " | ".join(spread("call")) + " |")

# ---------------------------------------------------------------- no-pos

if any(l in seen for l in NOPOS):
    pairs = [("hscript-pos", "hscript"), ("hscript-improved-pos", "hscript-improved"),
             ("hscript-iris-pos", "hscript-iris"), ("rulescript-pos", "rulescript")]
    pairs = [(a, b) for a, b in pairs if a in seen and b in seen]
    if pairs:
        print("\n### What position tracking costs the libraries that can switch it off\n")
        print("Not a ranking. This fork cannot turn positions off, so the comparison above is built")
        print(f"with them on everywhere; this is what that decision costs the others. At {REF:,}.\n")
        s = shared(REF, [l for p in pairs for l in p])
        op = [c for c in s if kind(c) == "op"]
        print("| | " + " | ".join(LABEL[a] for a, _ in pairs) + " |")
        print("| --- |" + " --- |" * len(pairs))
        print("| us per operation, with | " + " | ".join("%.3f" % avg(a, op, REF) for a, _ in pairs) + " |")
        print("| us per operation, without | " + " | ".join("%.3f" % avg(b, op, REF) for _, b in pairs) + " |")
        print("| cost | " + " | ".join(
            ("%.1f%%" % ((avg(a, op, REF) / avg(b, op, REF) - 1) * 100.0)) if avg(b, op, REF) else "n/a"
            for a, b in pairs) + " |")
        print("| parse with, ms | " + " | ".join(str(parse.get(a, "n/a")) for a, _ in pairs) + " |")
        print("| parse without, ms | " + " | ".join(str(parse.get(b, "n/a")) for _, b in pairs) + " |")
