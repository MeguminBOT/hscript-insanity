# hxScript

A Haxe interpreter. It parses Haxe-shaped source and evaluates it directly, with enough of the
language intact that a script can declare classes, enums, typedefs and abstracts, and extend the
ones your application already compiled.

Two things it is for:

- **A scripting language for your application.** Ship a program that loads `.hx` files at runtime, so
  users can add content or behaviour without rebuilding, and without learning a second language.
- **Prototyping.** Iterate on logic without a compile cycle, in the language you are already
  writing, then move the parts that settled into compiled code unchanged.

It runs **typed by default**: declared types on variables, parameters, returns and `cast(x, T)` are
enforced as values pass through them. That is the main thing separating it from the interpreters it
descends from, and it means a script fails where Haxe would reject it rather than several frames
later somewhere unrelated.

```haxe
import hxscript.Script;

// Note the DOUBLE-quoted host string: a single-quoted one would interpolate `$name`
// in your own code, before the script ever sees it.
var script = new Script("
    class Greeter {
        var name:String;
        public function new(name:String) this.name = name;
        public function greet() return 'hello, $name!';
    }

    function run() {
        var g = new Greeter('world');
        trace(g.greet());
    }
", 'MyScript');

script.start();
script.call('run');   // MyScript:10: hello, world!
```

## Install

```
haxelib git hxscript https://github.com/MeguminBOT/hxscript
```

Then `-lib hxscript` in your hxml, or `<haxelib name="hxscript" />` in a `Project.xml`. Nothing else
is required: the table of compiled types that scripts resolve names against builds itself on first
use.

The [embedding guide](docs/embedding.md) covers the rest -- exposing your API, letting scripts
subclass your classes, and the things that will bite you. [`example/`](example) is a complete worked
version: a small turn-based RPG whose creatures, bosses and status effects are all scripts.

## How it differs from hscript

[hscript](https://github.com/HaxeFoundation/hscript) is a small, fast expression interpreter. It
evaluates Haxe-shaped expressions and does that well; what it does not do is let a script declare
*types*, or bring the module-level language along with them.

| | hscript | hxScript |
| --- | --- | --- |
| expressions, functions, closures | yes | yes |
| **declaring classes in a script** | no | yes, including `extends` on your compiled classes |
| enums, typedefs, abstracts, module-level fields | no | yes, scripted or imported from compiled code |
| `import` / `using` | no | yes, incl. `as` aliases, `.*` wildcards, single fields |
| string interpolation (`'v$n'`) | no | yes |
| pattern matching | basic `switch` | extractors, guards, captures, struct and array patterns |
| property accessors (`var x(default, set)`) | no | yes |
| type annotations | parsed, ignored | **enforced at runtime** |
| `Int` / `Float` distinction | blurred by `Dynamic` | preserved (`/` is always `Float`) |
| errors | message | call stack across scripts and into the host |

The hscript column reflects 2.7.0, the version the benchmark suite actually ran; the absence of
scripted classes and of single-quote interpolation are both recorded in
[benchmarks.md](docs/benchmarks.md), which puts six libraries in this family through identical
scripts. That page is worth reading before picking one. This fork carries the largest language
surface and pays for it per operation, while being several times faster per *call*, because it
signals `return` and `break` with flags where the others throw exceptions. Neither number is the
whole story, and "fastest" depends entirely on which of the two your scripts do more of.

## Haxe parity

The useful question is not "is it Haxe" but "which Haxe does it reach". It is a tree-walking
interpreter, so what needs the *compiler* is gone and what needs only runtime values is there.

| Works with parity | Erased or weakened | Not available |
| --- | --- | --- |
| classes, `extends`, `override` | type parameters (erased to `Dynamic`) | macros, `@:build`, reification |
| scripted and native interfaces | structural typedefs (values, not literals) | compile-time type errors, inference |
| enums with params, `switch` extraction, guards | custom metadata (mostly inert) | overload resolution |
| abstracts: `@:op`, `@:arrayAccess`, `from`/`to` | `private` enforcement (opt-in) | `@:structInit`, `@:multiType` |
| typedef aliases | `untyped` (a no-op) | overriding native `inline` / `final` |
| statics, properties, getters and setters | | interface default methods |
| `using`, `import`, string interpolation | | compile-time inlining, DCE |
| comprehensions, optional / default / rest args | | |
| typed multi-catch, closures, `#if` | | |
| runtime type enforcement, `Int`/`Float` correctness | | |

[parity.md](docs/parity.md) is the long form: what each boundary is, why it is there, and where in
the source it lives. The short version of the last column is that a macro runs *in* the compiler and
there is no compiler at runtime; type parameters are erased by Haxe itself before the interpreter
ever sees them; and an `inline` method has no runtime representation to override.

Type mismatches surface as runtime throws rather than compile errors. That catches the same
mistakes, just later. There is no static checker yet, and adding one is real work rather than a
missing flag.

## The language surface

A tour of the parts that are not obvious. Everything here runs.

**Scripted types.** Classes, enums, typedefs, abstracts and module-level fields can all be declared
in a script. To let scripts subclass one of *your* classes, extend it and implement the marker
interface:

```haxe
class ScriptedThing extends BaseThing implements hxscript.IScripted {}
```

**Typed mode.** On by default; `Config.typedMode = false` or `-D hxscript_dynamic` turns it off.

```haxe
var x:Int = 5;        // ok
var y:Int = 3.5;      // throws: 3.5 should be Int
var f:Float = 5;      // ok, widened
trace(cast(5, Int));  // a real checked cast
trace(5 is Int);      // true -- primitives work as targets
```

**Abstracts**, scripted or compiled. Compiled ones need
`@:build(hxscript.macro.AbstractMacro.build())`, and an explicit cast to reach the abstract type:

```haxe
var color:FlxColor = cast 0xff0040;
color.green = FlxColor.GREEN.green;
```

**Imports and static extension**, as in Haxe:

```haxe
import sys.*;
import Reflect.getProperty as get;
using Lambda;
```

**Pattern matching**, with captures, extractors, guards and struct or array patterns:

```haxe
switch (struct) {
    case {name: a, rating: b}: '$a is $b';
    default: 'no match';
}
```

**Also**: string interpolation with nesting, regex literals (`~/hx/i`), map and array comprehension,
property accessors, rest and optional arguments, `#if` with comparisons against real compilation
defines, and field access on any compiled type without importing it first.

**Errors** carry a call stack across script boundaries and into the host, rather than a bare message:

```
Exception: ouch...
Called from test/TestScript.hxs.crash (test/TestScript.hxs line 2 column 8)
Called from script test/TestScript.hxs (test/TestScript.hxs line 4 column 1)
Called from Main.main (Main.hx line 10 column 3)
```

[`Config`](hxscript/Config.hx) sets the global behaviour: proxying or blacklisting types, modules and
packages, swapping the interpreter class, preprocessor values for conditionals, and predefined
variables and imports.

## Documentation

- **[Embedding guide](docs/embedding.md)** -- putting the library in a project, worked end to end in
  [`example/`](example).
- [Parity with Haxe](docs/parity.md) -- what scripts can and cannot do, and why.
- [Performance](docs/performance.md) -- what has been optimised, and how to measure without fooling
  yourself.
- [Benchmarks](docs/benchmarks.md) -- six libraries in this family on identical scripts.
- [Static checking](docs/checker.md) -- the design for a pre-run checker, and its limits.
- [Tests](test) -- the suites, which double as executable documentation of behaviour.

## To-do

Implemented, unless listed as not done below.

**Compiled types**: abstracts (statics, instance fields, `from`/`to`, `@:op`, `@:arrayAccess`,
`@:forward`), enum abstracts, enums with constructor arguments, typedefs (alias, and anonymous
structure checked by field name *and* field type), module-level fields.

**Scripted types**: classes (extending scripted or compiled classes, property accessors, `toString`,
iterators and iterables), enums, typedefs, module-level fields, abstracts (boxed underlying value,
constructor, methods, properties, statics, `from`/`to`, operators, enum abstracts, `@:forward`).

**Typed mode**: runtime enforcement on variables, arguments, returns and `cast`; primitives as
`is`/`cast` targets; `Int`/`Float` numeric correctness; container and function-type checking;
structural typedef shape checking; `private` access enforcement. A class or static field declared
with a type binds exactly as the identical local does, so an abstract-typed field boxes.

**Static extensions**: a `using` on a script-declared class registers, and the receiver is checked
against the extension's first parameter, so several extensions can share a method name. Compiled
extensions still cannot be checked -- see below.

**Printing**: `Printer` prints every module declaration, and printing round-trips through a reparse.

Not done:

- [ ] **Static checking before a script runs.** Designed but not built: see
      [checker.md](docs/checker.md) for what it could prove without inference, what it could not, and
      why the boundary sits there.
- [ ] **Call-stack frames across interpreters.** A method declared in a module runs on that module's
      interpreter, and each interpreter owns its own stack with no link to its caller, so the frame
      does not appear in the calling script's trace. Errors themselves now carry their frames
      wherever they are reported; this is the remaining half.

## Impossible to add

Not "not yet": these need information that stops existing once the Haxe compiler has finished, so no
amount of emulation inside a runtime interpreter recovers it.

- **Macros, `@:build` and reification in scripts.** A macro runs *in* the compiler. There is no
  compiler at runtime to run one.
- **Compile-time type errors and inference.** The interpreter sees values, not the types of
  expressions that have not run yet. A static checker over the AST could catch some before running;
  that is the to-do above, and it is a different thing from inference.
- **Generic type safety.** Type parameters are erased by the Haxe compiler itself, so at runtime
  `Array<Int>` and `Array<String>` are the same type. Nothing can tell them apart.
- **`@:multiType`.** Choosing an implementation from a type parameter is a compile-time decision.
  `Map` works only because it is special-cased on the key's runtime value.
- **Type-checking `using` extensions on compiled classes.** A compiled static's parameter types do
  not exist at runtime, so the first argument cannot be checked against them. Extensions declared in
  a script can be checked, because their declarations are still around.
- **Overriding a native `inline` or `final` method.** An `inline` method has no runtime
  representation to override, and a `final` one is devirtualised at the call site. Calls to them can
  be emulated with `Config.callShims`; overriding them cannot.

## Lineage

A fork of [inky03/hscript-insanity](https://github.com/inky03/hscript-insanity), itself an
experimental fork of [hscript](https://github.com/HaxeFoundation/hscript). Upstream drew on
[hscript-iris](https://github.com/pisayesiwsi/hscript-iris) and
[RuleScript](https://github.com/Kriptel/RuleScript); both are worth a look, and both are in the
benchmark comparison.

What this fork adds on top of that upstream: type annotations enforced at runtime, with
`-D hxscript_dynamic` to opt out and `Int` versus `Float` kept correct either way; abstracts that
work, scripted or compiled, including operators, array access and `from`/`to`; structural typedefs
checked by field *type* rather than by name alone; documentation and a runnable example rather than
a feature list; and interpreter performance work that was measured rather than assumed.

Still a work in progress. The to-do above says what is missing, and
[parity.md](docs/parity.md) is honest about where scripts diverge from real Haxe. Pull requests
welcome at [this fork](https://github.com/MeguminBOT/hxscript/pulls).
