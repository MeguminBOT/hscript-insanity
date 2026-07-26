# Tests

Standalone programs, each with its own `main`. They embed scripts as strings, run them through the
library, and check the results, so they exercise the interpreter the way a host application does.

Run one on the eval target:

```
haxe -cp test -cp . -main ReturnTest --interp
```

Run it compiled, which is what matters for anything performance or coercion related:

```
haxe -cp test -cp . -main ReturnTest -cpp bin && ./bin/ReturnTest.exe
```

| file | covers |
| --- | --- |
| `ReturnTest` | `return` from loops, `switch`, `try`/`catch`, nested blocks, recursion, early and bare return |
| `LoopTest` | `break` / `continue` scoping to the innermost loop, comprehensions, `return` unwinding past a loop |
| `RangeTest` | `a...b` integer ranges, including with `break`, `continue`, `return` and comprehensions |
| `ArgsTest` | argument binding: exact, optional, default and rest parameters |
| `TypedTest` | typed mode: enforcement, coercion, and that dynamic mode disables it |
| `StructTest` | structural typedefs via `is`, `cast` and annotations |
| `GapProbe` | a broad sweep of everyday script constructs, used to hunt for gaps rather than assert one thing |
| `Bench` | the micro-benchmark; see [`../docs/performance.md`](../docs/performance.md) |

`GapProbe` prints `ok` or `GAP` per construct and is meant to be read, not just passed. Note that map
key order is unspecified in Haxe, so an ordering difference there is not a defect.
