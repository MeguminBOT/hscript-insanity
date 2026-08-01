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
| `StructTest` | structural typedefs via `is`, `cast` and annotations: field presence, field types, optional fields |
| `ClassProbe` | scripted classes: inheritance, `super`, statics, properties, interfaces, enums, closures |
| `AbstractTest` | native abstracts: construction, fields, statics, and `@:op` operator dispatch |
| `ScriptedAbstractTest` | script-declared abstracts: construction, members, implicit boxing, operators, conversions |
| `UsingTest` | static extensions on scripted classes: registration, selection by receiver type, errors inside an extension |
| `PrinterTest` | `Printer` on module declarations, checked by print-reparse-print stability |
| `FieldBindTest` | that a typed class or static field binds as the identical local does, and that field errors carry a stack |
| `SweepProbe` | numeric edges, the `#if` preprocessor, string and regex handling, error handling, imports and `using` |
| `GapProbe` | a broad sweep of everyday script constructs, used to hunt for gaps rather than assert one thing |
| `Bench` | the micro-benchmark; see [`../docs/performance.md`](../docs/performance.md) |

`AbstractTest` uses the `OpVec` and `OpBare` fixtures next to it, and asserts against the value
native Haxe computes for the same expression wherever Haxe accepts it.

`GapProbe` prints `ok` or `GAP` per construct and is meant to be read, not just passed. Note that map
key order is unspecified in Haxe, so an ordering difference there is not a defect.

`SweepProbe`'s `regex replace` reports a GAP on the **compiled** target only. That is DCE in the test
program, not the library: nothing in `SweepProbe` calls `EReg.replace` from compiled code, so it is
eliminated and the script cannot reach it. A host that uses the method keeps it.
