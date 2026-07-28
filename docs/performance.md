# Interpreter performance

A log of what has been optimized, what it cost before, and how it was measured. Numbers come from
[`test/Bench.hx`](../test/Bench.hx), a micro-benchmark whose cases are chosen so a gain can be
attributed to a specific change rather than to "things feel faster".

## Running it

```
haxe -cp test -cp . -main Bench -cpp bin_bench && ./bin_bench/Bench.exe
```

Measure on **hxcpp**, not `--interp`. The interpreted target hides exactly the costs that matter here
(the typed-boundary coercions and exception costs behave differently), and hxcpp is what ships.

### The one rule: always rebuild the control

Absolute timings drift with machine state by well over 10%, which is more than most individual
optimizations are worth. Twice during this work a "regression" or an "improvement" turned out to be
nothing but a warmer or cooler machine.

So never compare against a number written down earlier. Build the previous commit in the **same
session**, run both, and compare those:

```
git worktree add /tmp/before <previous-commit>
haxe -cp test -cp /tmp/before -main Bench -cpp /tmp/before_bin && /tmp/before_bin/Bench.exe
git worktree remove /tmp/before --force
```

Only same-session pairs appear as verified deltas below.

## What the cases measure

| case | what it isolates |
| --- | --- |
| `arith` | operator dispatch and numeric promotion |
| `locals` | variable read/write through the scope map |
| `blocks` | per-block scope bookkeeping |
| `field` | field-access chain resolution |
| `method` | a native method call through the interpreter |
| `call` | a script function call |
| `call0` / `call1` / `call3` | fixed per-call overhead versus per-parameter cost |
| `callRet` / `callNoRet` | a body that returns versus one that does not |
| `noCall` | empty loop floor, the baseline every other case includes |
| `loopPlain` / `loopCont` | loop iteration with and without `continue` |
| `call_cap20` | whether call cost scales with captured-scope size |
| `newInstBare` / `newInstFields` | scripted-class instantiation: fixed cost versus per-member cost |
| `instCall` / `instField` | a method call and a field read through a generated instance bridge |

## Changes

### The default wildcard import, resolved once per world instead of once per interpreter

Constructing an interpreter cost **44.2us**, and **42.7us of it was `setDefaults`** seeding
`Config.globalImports`, which is `'' => IAll`: a wildcard import of the root package. `setDefaults`
with the Config seeding skipped costs 0.042us, so the seeding was a thousand times the cost of
everything else in the constructor put together.

That lands on scripted-class instantiation, which builds an interpreter per instance and paid it
twice (once in the constructor, once in the bridge's own `setDefaults` a few lines before it copied
the class's imports over the top and discarded the result).

Attribution inside the import, over the 27 root-package types, per call:

| step | cost |
| --- | --- |
| `listTypesEx('')` | 3.5us |
| plus the sub-type/`_Impl_` filter | 6.5us |
| plus resolving each surviving type | 41.9us |
| the whole `setDefaults(true, true)` | 43.4us |

So 82% of it was `TypeCollection.resolve` per type, and none of it changes until the world's type
index does. A wildcard import now remembers its name-to-type bindings (`ImportEntry`) on the
`Environment`, or in a static for interpreters with no world, and drops them in `rebuildTypes`.
`Interp.clearImportCache()` drops the world-less ones, for a host that changes `Config.blacklist` or
`Config.typeProxy` after scripts have already run.

Verified deltas (same session):

| case | before | after | |
| --- | --- | --- | --- |
| `newInstBare` | 1882 | 188 | **10.0x** |
| `newInstFields` | 1957 | 242 | **8.1x** |
| `instCall` / `instField` | 163 / 110 | 157 / 106 | unchanged |
| every other case | | unchanged | |

A scripted instance went from 94us to 9.4us. For reference a script call is about 1.1us, so
instantiation went from ~85 calls to ~9. The measurement was taken with only this library's types in
the collection; a host with a populated root package pays more before the change and the same after.

Full suite green, and `SweepProbe` gives byte-identical output to `HEAD` (30 ok, 9 intentional
parse-error traces).

### Core types kept off the type-resolution path

A type annotation was costing far more than the check it stands for. `tryCast` runs on every write to
an annotated variable, every annotated argument and every annotated return, and it re-resolved the
annotation from scratch each time: `p.join('.')` (a string allocation, for a path that is one element
in nearly every case), an `imports` lookup, a `TypeCollection` lookup with a `compilePath` and a
`resolve` behind it, and `Type.getSuperClass` (which drags in the blacklist walk) - only to reach
`case 'Int'` and do one `isOfType`.

Measured spread against the identical un-annotated code:

| | before | after | annotation overhead |
| --- | --- | --- | --- |
| `varPlain` -> `varTyped` | 102 -> 176 | 102 -> 141 | **+73% down to +38%** |
| `fnPlain` -> `fnTyped` | 148 -> 226 | 145 -> 193 | **+53% down to +33%** |
| `varTypedObj` | 156 | 152 | |

So `varTyped` -20% and `fnTyped` -15%, with every other case unchanged.

A core type cannot resolve to a script-declared type and is not in the type index, so once the
`imports` lookup misses, the index lookup and the abstract handling have nothing to contribute and the
check runs directly. A boxed abstract still takes the long way round, since it may convert. The
one-element path no longer allocates.

This matters more here than in most forks because typed mode is the default, so the better-typed a
script is, the more it used to pay.

What is left is one `imports` lookup plus the check itself, about 0.2us per typed write. Removing that
needs the resolved type cached on the slot or on the closure, which is a bigger change than this one.

### Block entry, and dead control-flow handlers

Three changes, measured as two steps against same-session controls.

**Step one, dead `Stop` handlers and `increment`.** Nothing has thrown `Stop` since control flow moved
to flags, but the handlers stayed: `loopRun` wrapped **every loop body iteration** in a
`try/catch (err:Stop)`, and `exprReturn` wrapped every call. Separately, `increment` opened with a
`locals.get(id)` whose result was never read, then did `exists` + `getLocal` + `exists` + `setLocal`,
five scope-map operations for one `i++`.

Worth **1 to 3%**, and that is the useful part of the result: removing an untaken `try` buys almost
nothing, because C++ exceptions cost nothing on the path that does not throw. Do not spend time
hunting unused `try` blocks for speed. They are still worth removing as dead code.

**Step two, the map iterator on block entry.** This is where that first bundle's gain actually came
from. Block entry ran `locals.keys().hasNext()` to ask "does this scope hold anything", which
**allocates a map iterator**, on entry to every block, every function body and every loop body.
`restore` is already a no-op when the block declared nothing, so the guard bought nothing and is gone.

| case | before | after | |
| --- | --- | --- | --- |
| `noCall` | 58 | 49 | -16% |
| `blocks` | 182 | 150 | -18% |
| `neg` / `locals` | 128 / 226 | 109 / 193 | -15% |
| `indexSet` / `index` | 132 / 154 | 114 / 133 | -14% |
| `loopPlain` | 68 | 59 | -13% |
| `field` / `not` | 192 / 143 | 168 / 125 | -13% |
| `arith` | 269 | 238 | -12% |
| `call0` / `callRet` | 105 / 107 | 93 / 95 | -11% |
| `method` / `instField` | 104 / 104 | 95 / 95 | -9% |
| `call` | 168 | 159 | -5% |

**This one changes script behaviour**, and deliberately. The guard meant a block leaked its variables
into the enclosing scope whenever that scope happened to hold no locals, so whether `{ var x = 1; } x;`
resolved depended on whether an unrelated `var` had been declared earlier:

| script | before | after |
| --- | --- | --- |
| `{ var x = 1; } x;` | `1` | error |
| `var a = 0; { var x = 1; } x;` | error | error |
| `function f() { { var x = 1; } return x; } f();` | `1` | error |
| `var x = 'outer'; { var x = 'inner'; } x;` | `outer` | `outer` |

The new column is what Haxe does and what the old column already did as soon as any local existed. A
script relying on the old leak would have had to have no locals at all in the enclosing scope.

**A bug fixed on the way.** `duplicate()` with no source map popped a map off the pool and returned it
**without clearing it**, so a new frame inherited whatever the previous frame had left there. That
reached fresh interpreters, whose first frame is pushed with no locals: a scripted class's statics
scope could start out holding another scope's variables. It also made the block guard above
nondeterministic, since it tested a map that might be dirty.

### Control flow by flag instead of exceptions (`bc537e6`, `934502e`)

The big one. `return`, `break` and `continue` unwound by throwing `Stop`, and a thrown exception costs
microseconds on static targets. `return` alone was about **94% of the cost of every script call**.

Attribution, before touching anything:

| probe | result |
| --- | --- |
| `call0` with pooled locals map | 856 ms |
| `call0` with a fresh map per call | 4825 ms (pooling was already doing the work) |
| `call0` with no scope copy at all | 852 ms (the copy is free) |
| body `return 1` | 869 ms |
| body `{ 1; }` | 112 ms |
| empty loop floor | 61 ms |

This is why the suspects that *looked* obvious (Reflect dispatch, the per-call locals map) were both
wrong, and why attribution comes before optimization.

Verified deltas (same session):

| case | before | after | |
| --- | --- | --- | --- |
| `call` | 941 | 169 | 5.6x |
| `call0` | 867 | 107 | |
| `callRet` | 868 | 108 | now equal to `callNoRet`; the penalty is gone |
| `call_cap20` | 1228 | 445 | |
| `loopCont` | 477 | 88 | 5.4x |
| `loopPlain` | 69 | 72 | unchanged |
| `arith` / `locals` / `blocks` / `field` / `method` | | unchanged | |

### Hot-path types as `@:structInit` classes (`168596d`)

`Variable`, `StackFrame`, `Expr` and `Position` were anonymous structures, which resolve fields **by
name at runtime** on static targets where a class field is a direct offset. All four are read on
essentially every interpreter step.

| case | before | after | |
| --- | --- | --- | --- |
| `arith` | 441 | 309 | -30% |
| `locals` | 382 | 256 | -33% |
| `blocks` | 309 | 214 | -31% |
| `field` | 314 | 240 | -24% |
| `method` | 157 | 125 | -20% |
| `call` | 1153 | 1028 | -11% |

`@:structInit` keeps the `{r: value}` construction syntax, so the change was contained; only two sites
needed a type annotation. Worth applying to any remaining hot anonymous structure.

### Hot-path fixes (`af48eeb`)

Three separate issues, measured together (not same-session controlled, so treat as indicative):
`blocks` -15%, `locals` -15%, `arith` -11%, `field` -11%, `method` -6%.

- Block entry called `Lambda.count(locals)` just to test "any locals", on entry to every block,
  including every function and loop body.
- `pushStack` stamped the caller frame by shifting it off, allocating a replacement frame and a new
  `SFilePos`, then unshifting it back, instead of stamping in place.
- A precedence bug: `args?.length ?? 0 != params.length` parses as
  `args?.length ?? (0 != params.length)` because `??` binds looser than `!=`, so the condition was
  `args.length` itself and every call passing arguments ran the argument-fixup path.

### Decomposition (`b837263`, `8d9924f`)

Behaviour-preserving refactors, both verified performance-neutral: splitting `Parser` into `Lexer`
plus `Parser`, and lifting the two largest arms of `Interp.expr()` (the comprehension machinery and
the `switch` evaluator) into their own methods. `Interp` deliberately stays a single class; extracting
collaborator objects would add a cross-object indirection to operations that run on every AST node.

### Restructure (`ad39d36`)

Package reorganization, verified **performance-neutral** against a same-session control (442/384/314/
1164/310/156 before versus 435/378/306/1118/301/155 after).

### Abstract operators and typed writes (`@:op`)

The one change so far that cost time rather than saving it, kept because it buys correctness:
dispatching `@:op` operators on abstracts, and enforcing a variable's declared type on every write
instead of only at its declaration.

Both land in the hottest paths there are, so the first attempt cost 5-6% interpreter-wide (11% on the
emptiest loop). Attribution split it roughly evenly between two additions:

- a type check on the value at every local write, and
- an abstract check on both operands of every `<`, `>`, `<=`, `>=`.

The write path was then rewritten to test the *slot* instead of the value: only a slot that already
holds an abstract needs its box kept in step, and `l.a != null` is a field read where
`v is AbstractValue` is a runtime type check. The declared-type check stays a null test on a field
that is null for every unannotated variable.

| case | before | after | |
| --- | --- | --- | --- |
| `arith` | 276 | 280 | +1.4% |
| `locals` | 230 | 234 | +1.7% |
| `blocks` / `field` / `call0` | | within noise | |
| `noCall` | 60.5 | 63 | +4%, the emptiest possible loop body |

Remaining cost is the two type checks per relational operator, which is what an interpreter without
static types has to pay to tell `a < b` on two abstracts apart from `a < b` on two ints.

Extending the same dispatch to the unary operators and to `@:arrayAccess` then cost **nothing
measurable**, on new `index`, `indexSet`, `not` and `neg` cases added to isolate exactly those paths.
The check disappears into the dynamic dispatch already happening around it, which is worth
remembering before assuming the next one is too expensive: measure the path, do not reason about it
from the relational-operator result.

### Measured and left alone: `strictAccess` and the blacklist

Both are on in a shipping host, and both looked like they belonged on this list: `checkAccess` runs on
every field read and write, and the blacklist walk (four `EnumValueMap` lookups and a linear scan
each) sits behind every type resolution. The `fieldGuard` / `methodGuard` / `instFieldGuard` /
`instCallGuard` cases exist to measure exactly that, by re-running the ordinary cases with
`strictAccess` on and a populated blacklist.

The answer is that they cost **nothing measurable** (170 against 173, 96 against 97, 96 against 93).
`checkAccess` returns immediately for a non-scripted receiver, and a scripted one does a single
`indexOf` on a short array. The blacklist walk is per *resolution*, and resolutions are now cached.

Recorded so the next person does not re-derive it. Do not optimize these without a new measurement
showing they became hot.

One side effect worth knowing: with a blacklist configured, the old per-interpreter wildcard import
re-warned about every blacklisted root-package type on every construction. The benchmark run emitted
**120,051** `is blacklisted` traces before the caching change and **0** after, each one a string
interpolation and a trace call. A host that configures a blacklist and then builds interpreters was
paying that in log I/O.

The one caveat of the cache: a blacklist installed *after* scripts have already run does not apply to
packages already cached. Configure it at startup, or call `Interp.clearImportCache()` after changing
it.

## Where the time goes now

A script call is roughly 1.1us, against about 0.6us for an empty loop iteration, so call overhead is
now in the same order as ordinary interpreter work rather than 15x it. Per-parameter cost is about
0.3us.

A scripted instance is roughly 9.4us to construct, down from 94us.

Standing numbers at the time of writing (hxcpp, best of 3; useful only as a shape, since absolute
values drift with the machine), against the same run of the previous release for the shape of the
gain:

| case | before | now | | case | before | now |
| --- | --- | --- | --- | --- | --- | --- |
| `arith` | 275 | 240 | | `varPlain` | 122 | 102 |
| `locals` | 239 | 197 | | `varTyped` | 197 | 142 |
| `blocks` | 197 | 152 | | `varTypedObj` | 183 | 153 |
| `call` | 176 | 161 | | `fnPlain` | 158 | 146 |
| `field` | 200 | 172 | | `fnTyped` | 239 | 191 |
| `method` | 111 | 96 | | `newInstBare` | 1888 | 188 |
| `index` / `indexSet` | 162 / 142 | 137 / 114 | | `newInstFields` | 1959 | 245 |
| `not` / `neg` | 158 / 135 | 126 / 114 | | `instCall` | 159 | 147 |
| `call0` | 110 | 96 | | `instField` | 110 | 95 |
| `loopPlain` / `loopCont` | 72 / 91 | 62 / 78 | | `noCall` | 62 | 52 |

Interpreter-wide that is 8 to 23%, and 8 to 10x on instantiation.

Remaining known costs, none currently urgent:

- Every variable access is a string hash into a `Map`, and several paths hash the same name more than
  once (`exists` followed by `get`). Reading an identifier can take up to four hashes. Collapsing the
  pairs is mechanical; slot-resolving identifiers at parse time would remove the hash entirely, but
  that is a real redesign.
- A typed write still costs one `imports` lookup, about 0.2us. Caching the resolved type on the slot
  or on the closure would remove it.
- `resolveField` allocates an array and an enum instance per field-access chain, measured at 0.32us
  per extra hop.
- Every generated bridge override tests `__interp.locals.exists(name)` and then reads it, so a native
  method the engine calls per frame pays two map hashes whether or not the script overrides it. The
  method set is known at macro time and could be a per-instance slot.
- `initOps` builds a 36-entry map of 36 closures per interpreter, and every binary operator is a
  string hash plus a closure call. A `switch` in `expr` removes both.
- `Environment.resolve` iterates every module and hashes into each one's table; `rebuildTypes` could
  build one flat index.
- `Reflect.makeVarArgs` plus `Reflect.callMethod` remain in the call path. Measurement says they are
  not dominant (a native method call goes through the same dispatch at about 1.25us), so this is not
  the next thing to chase.
- Parsing, not setup, is what script load costs: an 11KB script parses in about 714us, against ~44us
  of interpreter setup. The token pushback `List` and the reflective `Type.enumEq` in `Lexer.maybe`
  are the obvious targets if load time ever becomes a complaint.
