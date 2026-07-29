# Comparing Haxe scripting libraries

Six hscript-family libraries running identical scripts.

## Read this first: different, not better

**No library here is "the best one."** Split the suite in two and the ranking inverts: this fork is
mid-table on the cost of one ordinary operation and first by a wide margin on the cost of one
function call. Both are in the summary below, and neither is the summary on its own.

The call gap has one cause, and it is not cleverness. Every other library unwinds `return`, `break`
and `continue` by **throwing an exception**, and a thrown exception costs microseconds on a static
target. This fork signals them with flags. That is also why the corpus total flatters it: totals are
dominated by the call cases, so quote the per-operation and per-call averages instead.

`callCap20` is `call1` with twenty more variables in the enclosing scope and nothing else changed, so
the pair isolates a second design difference: whether building a call frame copies the captured
scope, and so costs something per captured variable. Four of the six pay about 30% for it. This fork
and hscript-improved pay nothing.

The same applies to features. hscript is small and fast and has no scripted classes.
hscript-improved has them and instantiates one faster than this fork does, while this fork calls
their methods several times faster -- its classes are generated bridges with real fields, theirs are
a shell over a map. RuleScript adds imports, usings and string interpolation. hscript-iris wraps a
fast interpreter in a friendlier host API. This fork and its upstream carry the largest language
surface (abstracts, modules, typedefs, properties, typed mode) and pay for it per operation.

Pick the one whose trade-off matches your workload. If you are choosing, run this suite with cases
that look like *your* scripts rather than trusting a total.

## What was measured

Every library is driven through its own public API, with the **same** script sources. Parsing is
untimed and separated from execution, so the numbers are interpreter speed rather than setup.

Every case ends in an expression whose value is known, and the harness checks it. A library that
parses and "runs" a case without doing the work is reported as `WRONG`, not as infinitely fast. That
check earned its place: it caught two mistakes in the expected values, and three genuine behavioural
differences between libraries that timings alone would have hidden.

Each case runs in its **own process**, because some libraries hang or crash on some inputs and would
otherwise take the rest of the run with them. 100,000 iterations, **median of 5**, hxcpp, one
machine, one sitting.

The median rather than the fastest run: best-of-N answers "how fast can this go when nothing
interferes", which flatters whichever library got the quietest slice of the machine. The median
answers "what does this usually cost", which is what a host budgeting a frame needs, and an unlucky
scheduler spike moves it no more than a lucky one does.

### Built with `-dce no`, and that is a correctness setting

Under hxcpp's default `-dce std` the compiler eliminates `IntIterator.hasNext` and `next`: every call
site inlines them, so nothing references them statically. An interpreter reaching them by reflection
then finds a null field, and `for (i in 0...n)` fails -- **in the host's build, not in the library**.
Earlier versions of this page reported that as a defect in four of the six libraries. It was not.

Everything here is therefore built with `-dce no`, which measures the libraries rather than the build
settings. A probe over 83 commonly-scripted standard-library members found **42 unreachable** under
`-dce std` against 3 under `-dce no`; the catalogue is in
[`embedding.md`](embedding.md#what--dce-std-actually-removes), and it is worth reading before
concluding that any scripting library "cannot do" something.

### Every library is built with position tracking

hscript's `Expr` is `typedef ExprDef = Expr` unless it is built with `-D hscriptPos`: without that
define it records no source positions **at all**. hscript-improved, hscript-iris and RuleScript
inherit the same switch.

This fork cannot turn positions off, because error reporting, `posInfos` and call-stack traces depend
on them. Comparing against a build that records nothing would not be measuring the same job, so every
library in the comparison is built **with** them. What the switch costs the libraries that have it is
reported separately at the end, where it reads as the price of a feature rather than a ranking.

### One scale

The corpus runs at 100,000 iterations. Three scales spanning 20x were used to establish that the
ranking is a property of the interpreters rather than a warm-up or fixed-setup artefact; it held,
moving by at most a few percent, so re-establishing it on every run is not worth three times the wall
time. `SCALES="25000 100000 500000"` checks it again after a change that could plausibly disturb it.
Expected values are derived from the iteration count, so the value checking holds at any scale.

## Results

<!-- BEGIN GENERATED: test/xbench/collate.py -->

### Every case, microseconds per iteration at 100,000

One row per case, and the only per-case table in this document. `kind` is which average the
row feeds: `op` and `call` are averaged separately because they differ by design rather than
by degree. `unwind` cases are in neither, being dominated by how a library implements
`continue` and `throw`, and nor are `compound` ones, which do far more than one operation per
iteration and would describe themselves rather than the interpreter.

<details>
<summary><strong>33 cases, click to expand</strong></summary>

| case | kind | this fork | insanity | hscript | improved | iris | rulescript |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `noCall` | op | 0.478 | 1.043 | 0.394 | 0.643 | 0.375 | 0.517 |
| `loopPlain` | op | 0.493 | 1.083 | 0.437 | 0.665 | 0.418 | 0.554 |
| `loopCont` | unwind | 0.695 | 5.248 | 4.463 | 4.823 | 4.452 | 4.821 |
| `postIncr` | op | 0.458 | 1.022 | 0.379 | 0.523 | WRONG (0) | 0.463 |
| `arith` | op | 0.692 | 1.234 | 0.549 | 0.820 | 0.494 | 0.703 |
| `locals` | op | 0.591 | 1.292 | 0.491 | 0.795 | 0.457 | 0.625 |
| `blocks` | op | 0.705 | 1.624 | 0.578 | 0.989 | 0.535 | 0.744 |
| `field` | op | 0.600 | 1.297 | 0.434 | 0.747 | 0.411 | 0.604 |
| `fieldSet` | op | 0.655 | 1.178 | 0.437 | 0.750 | 0.429 | 0.560 |
| `method` | op | 1.071 | 1.668 | 0.704 | 1.117 | 0.689 | 0.898 |
| `index` | op | 0.554 | 1.171 | 0.443 | 0.734 | 0.423 | 0.601 |
| `indexSet` | op | 0.546 | 1.150 | 0.447 | 0.744 | 0.435 | 0.600 |
| `not` | op | 0.568 | 1.186 | 0.481 | 0.743 | 0.445 | 0.628 |
| `neg` | op | 0.536 | 1.149 | 0.448 | 0.713 | 0.432 | 0.572 |
| `call0` | call | 0.878 | 9.218 | 7.971 | 8.426 | 7.806 | 8.250 |
| `call1` | call | 1.300 | 9.834 | 8.217 | 8.729 | 8.029 | 8.488 |
| `call3` | call | 1.986 | 10.659 | 8.637 | 9.435 | 8.319 | 9.047 |
| `callCap20` | call | 1.298 | 13.819 | 10.522 | 8.740 | 10.447 | 10.955 |
| `forRange` | op | 0.173 | 0.305 | 0.174 | 0.273 | 0.139 | 0.210 |
| `forArray` | op | 0.188 | 0.319 | 0.190 | 0.286 | 0.156 | 0.231 |
| `arrayDecl` | op | 1.019 | 1.794 | 0.707 | 1.170 | 0.628 | 0.917 |
| `strConcat` | op | 0.911 | 2.041 | 1.295 | 1.623 | 1.229 | 1.429 |
| `ternary` | op | 0.745 | 1.470 | 0.738 | 1.033 | 0.666 | 0.901 |
| `switch` | op | 0.854 | 1.604 | 0.775 | 0.996 | 0.666 | 0.894 |
| `tryCatch` | unwind | 8.173 | 9.629 | 8.029 | 8.527 | 7.689 | 8.558 |
| `strInterp` | op | 1.140 | 1.613 | WRONG (v$n) | WRONG (v$n) | WRONG (v$n) | 0.906 |
| `mapLiteral` | op | 1.395 | 2.155 | 1.192 | 1.552 | 1.035 | 1.394 |
| `arrayCompr` | compound | 3.179 | 4.227 | 3.264 | 5.209 | 10.376 | 11.308 |
| `varTyped` | op | 0.669 | 1.031 | 0.392 | 0.641 | 0.387 | not supported |
| `fnTyped` | call | 1.773 | 10.192 | 8.306 | 8.765 | 8.488 | not supported |
| `classNew` | compound | 6.976 | 111.156 | not supported | 4.687 | not supported | not supported |
| `classCall` | call | 1.563 | not supported | not supported | 9.151 | not supported | not supported |
| `classField` | op | 0.711 | 1.475 | not supported | 0.875 | not supported | not supported |

</details>

### Summary, over the 26 cases every library ran

| | this fork | insanity | hscript | improved | iris | rulescript |
| --- | --- | --- | --- | --- | --- | --- |
| us per operation (19 cases) | 0.672 | 1.303 | 0.574 | 0.863 | 0.530 | 0.715 |
| us per call (4 cases) | 1.366 | 10.882 | 8.837 | 8.833 | 8.650 | 9.185 |
| parse, ms | 0.768 | 1.28 | 1.049 | 2.608 | 0.749 | 1.124 |
| corpus total, ms | 3028 | 8740 | 6202 | 7028 | 6718 | 7501 |
| total relative to this fork | 1.00x | 2.89x | 2.05x | 2.32x | 2.22x | 2.48x |

```mermaid
xychart-beta
    title "Cost of one operation at 100,000 iterations"
    x-axis ["iris", "hscript", "this fork", "rulescript", "improved", "insanity"]
    y-axis "microseconds" 0 --> 1.499
    bar [0.530, 0.574, 0.672, 0.715, 0.863, 1.303]
```

```mermaid
xychart-beta
    title "Cost of one call at 100,000 iterations"
    x-axis ["this fork", "iris", "improved", "hscript", "rulescript", "insanity"]
    y-axis "microseconds" 0 --> 12
    bar [1.366, 8.650, 8.833, 8.837, 9.185, 10.882]
```

### How much script fits in one frame

The per-operation and per-call averages read as a budget. A 60Hz frame is 16.667ms;
the second pair is a 2ms slice of it, which is a more realistic allowance once
rendering and physics are paid for. Whole units, rounded down.

**Derived, not measured at this scale.** Timing a frame's worth of work directly is dominated
by noise -- a few hundred operations is far too short an interval to time on a preemptive OS.
These come from the 100,000-iteration averages above, which are stable, multiplied back out.
Read it the other way for a budget you already have in mind:

```
per-call us  x  calls per frame  x  60  =  us per second spent in script
```

| | this fork | insanity | hscript | improved | iris | rulescript |
| --- | --- | --- | --- | --- | --- | --- |
| operations per 60Hz frame | 24,788 | 12,787 | 29,017 | 19,316 | 31,469 | 23,316 |
| calls per 60Hz frame | 12,204 | 1,531 | 1,885 | 1,886 | 1,926 | 1,814 |
| operations per 2ms slice | 2,974 | 1,534 | 3,482 | 2,318 | 3,776 | 2,798 |
| calls per 2ms slice | 1,464 | 183 | 226 | 226 | 231 | 217 |

### The ranking does not depend on the scale

The whole corpus at each scale. If a difference only showed up at one size it would be a
warm-up or fixed-setup artefact rather than a property of the interpreter.

| | this fork | insanity | hscript | improved | iris | rulescript |
| --- | --- | --- | --- | --- | --- | --- |
| us per operation, 100,000 | 0.672 | 1.303 | 0.574 | 0.863 | 0.530 | 0.715 |
| us per call, 100,000 | 1.366 | 10.882 | 8.837 | 8.833 | 8.650 | 9.185 |
| spread, operations | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| spread, calls | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |

### What position tracking costs the libraries that can switch it off

Not a ranking. This fork cannot turn positions off, so the comparison above is built
with them on everywhere; this is what that decision costs the others. At 100,000.

| | hscript | improved | iris | rulescript |
| --- | --- | --- | --- | --- |
| us per operation, with | 0.574 | 0.863 | 0.530 | 0.715 |
| us per operation, without | 0.492 | 0.787 | 0.514 | 0.601 |
| cost | 16.7% | 9.6% | 3.0% | 18.9% |
| parse with, ms | 1.049 | 2.608 | 0.749 | 1.124 |
| parse without, ms | 0.524 | 2.128 | 0.511 | 0.526 |

<!-- END GENERATED -->

## Behavioural differences found

These came out of the value checking, not the timing, and matter more than any of the numbers above
if you are choosing a library. All were reproduced directly, outside the harness.

**`for (i in 0...n)` works everywhere, and a previous version of this page said otherwise.** It was
recorded as broken on hxcpp in hscript, hscript-improved, RuleScript and upstream insanity, blamed on
`IntIterator.hasNext`/`next` being `inline` and having no runtime form. Both halves were wrong. They
have a runtime form; `-dce std` removes it because every call site inlines them, so nothing references
them. Build with `-dce no` and all six libraries run `forRange` and `arrayCompr` correctly -- the whole
`CRASH` column this page used to carry is gone, and so are the nine timeouts behind it.

Worth stating plainly because the failure looks exactly like a library defect from the outside: a
script gets `Cannot call null`, or on a build without position tracking it silently abandons the rest
of the program. Neither points at the host's own compiler flags, which is where the cause is. See
[`embedding.md`](embedding.md#what--dce-std-actually-removes) for what else DCE takes with it.

**hscript-iris does not implement `++`.** `var i = 0; i++; i;` returns `0`, and `++i` behaves the
same; `i = i + 1` and `i += 1` both work. Any `while (i < n) { ...; i++; }` therefore never
terminates. Because of this, every loop counter in this suite uses `i += 1`, which is equally fair to
all six libraries, and the `postIncr` case exists to isolate the difference.

**RuleScript does not build against current hscript.** It needs an hscript predating
`Interp.makeKeyValueIterator` and `resolveType`; it was pinned to hscript `609c489` here. Its
`extraParams.hxml` also has to be passed by hand when using `-cp` instead of haxelib, since it patches
hscript's enums at compile time.

**Single-quote string interpolation** (`'v$n'`) is absent in hscript, hscript-improved and
hscript-iris, which return the literal text. This fork, upstream insanity and RuleScript interpolate.

## What was tested

Haxe 4.3.7, hxcpp, `-dce no`, Windows, single machine, one sitting.

| library | version | notes |
| --- | --- | --- |
| this fork | working tree | always tracks positions |
| [hscript-insanity](https://github.com/inky03/hscript-insanity) (upstream, "insanity") | `9b3c9f8` | always tracks positions |
| [hscript](https://github.com/HaxeFoundation/hscript) | 2.7.0 | built both ways |
| [hscript-improved](https://github.com/CodenameCrew/hscript-improved) | `48ec0f4` | built both ways |
| [hscript-iris](https://github.com/pisayesiwsi/hscript-iris) | 1.1.3 (`8867c9a`) | built both ways |
| [RuleScript](https://github.com/Kriptel/RuleScript) | `b5b377a` | built both ways; needs hscript `609c489` |

## Reproducing

The harness is in [`../test/xbench`](../test/xbench). In short:

```sh
LIBS=/path/to/library/checkouts sh test/xbench/run.sh
```

`LIBS` wants checkouts named `insanity-upstream`, `hscript`, `improved`, `iris`, `rulescript` and
`hscript-rs` (the older hscript RuleScript needs). Anything missing is skipped, and the collator
drops absent libraries rather than emptying the shared-case set, so a subset produces a table for
that subset.

Scales default to `25000 100000 500000` and are settable:

```sh
SCALES="50000 200000" LIBS=... sh test/xbench/run.sh
```

They must be multiples of 1000, which is the array length `forArray` walks.

`DCE` defaults to `no` and should stay there; see above. `DCE=std` reproduces what a host with default
compiler flags actually gets, which is a different and also useful question.

`collate.py` writes the whole of the Results section above. Paste its output between the two
`GENERATED` markers rather than editing the tables by hand: it is one table of record plus its
summaries, so a re-run replaces all of it in one go and there is nothing to keep in sync.

Every hscript-derived library is built twice, once with
[`hscript-pos.hxml`](../test/xbench/hscript-pos.hxml) and once without. Do not drop the
position-tracking builds when comparing against this fork: without that define those libraries record
no source positions at all, and this fork cannot work that way.

## Caveats

**Read the ratios, not the numbers.** Absolute microseconds drift with machine state by well over
10%, which is more than most of the differences between neighbouring libraries here. Rebuild and
re-run everything in one sitting before comparing anything, and never merge a re-run of one library
into a table measured in another sitting.

**The shared-case set excludes the cases some library cannot run**, so the totals and averages
describe a common subset and say nothing about the features that subset leaves out: `postIncr` (iris
has no `++`), `strInterp` (three libraries return the literal text), `varTyped` and `fnTyped`
(RuleScript rejects type annotations), and `classNew`/`classCall`/`classField` (only some libraries
have scripted classes). Excluding them is generous to the libraries that fail them. The per-case list
is where those live.

**`arrayCompr` and `classNew` are excluded from the averages too**, for a different reason: they do
far more than one operation per iteration, so a mean including them describes the outlier. Leaving
`arrayCompr` in moved hscript-iris's per-operation figure from 0.53us to 1.02us on this run, which
would have reported it as twice as slow as it is.

**A micro-benchmark is not an application.** These cases isolate single operations on purpose, so
they overstate interpreter differences relative to a real script that also touches the host's own
code. Use them to understand *where* libraries differ, then measure your own workload.
