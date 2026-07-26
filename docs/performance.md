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

## Changes

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

## Where the time goes now

A script call is roughly 1.1us, against about 0.6us for an empty loop iteration, so call overhead is
now in the same order as ordinary interpreter work rather than 15x it. Per-parameter cost is about
0.3us.

Standing numbers at the time of writing (hxcpp, best of 3; useful only as a shape, since absolute
values drift with the machine):

    arith 266   locals 222   blocks 186   call 165   field 183   method 104   loopCont 85

Remaining known costs, none currently urgent:

- Every variable access is a string hash into a `Map`. Slot-resolving identifiers at parse time would
  remove it, but that is a real redesign.
- `resolveField` allocates an enum instance per field access in the chain.
- `Reflect.makeVarArgs` plus `Reflect.callMethod` remain in the call path. Measurement says they are
  not dominant (a native method call goes through the same dispatch at about 1.25us), so this is not
  the next thing to chase.
