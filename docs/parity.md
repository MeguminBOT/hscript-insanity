# Haxe parity: what is and isn't supported

HscriptInsanity is a **tree-walking interpreter**, not a compiler. It parses Haxe-shaped source
and evaluates it directly, so it reaches a large slice of the language, classes, interfaces,
enums, typedefs, `using`, closures, comprehensions. It also runs **typed by default**: declared
types on variables, parameters, returns, and `cast(x, T)` are enforced at runtime (see section 1).
What it still cannot do is any *compile-time* work, no inference, no overload resolution, no
static errors. This page is the reference for those gaps: the things regular Haxe can do that a
script here cannot (or does differently).

> [!NOTE]
> This complements the checklist in the [README TO-DO](../README.md#to-do). The README tracks
> feature completion; this page explains the *boundaries* and *why* they exist, with pointers into
> the source.

## At a glance

| Works with parity | Erases / weakened | Not available |
| --- | --- | --- |
| classes, `extends`, `override` | type parameters (erased) | macros / `@:build` / reification |
| scripted + native interfaces | structural typedefs (shape, not field types) | `@:op` operator overloading |
| enums (+ params, `switch` extraction, guards, `\|`) | scripted abstracts (underlying/`from`/`to`) | `@:structInit`, `@:forward`, `@:multiType` |
| typedef aliases | custom metadata (mostly inert) | compile-time type errors / inference |
| static / instance / `private` / getters-setters | `private` enforcement (opt-in, explicit only) | overload resolution |
| `using`, `import` (`as` / `.*` / single field) | typed metadata / `untyped` (no-op) | overriding native `inline`/`final`/`@:generic` methods |
| string interpolation, comprehensions | | interface default methods |
| optional/default/rest args | | compile-time inlining / DCE |
| typed multi-catch, closures, `#if` | | |
| **runtime type enforcement** (`cast`/`is`/var/param/return) | | |
| **`Int`/`Float` correctness** | | |

---

## 1. Typed by default, with a dynamic escape hatch

Type annotations are **enforced at runtime**, not just parsed. This is gated by `Config.typedMode`,
which defaults on (`-D insanity_dynamic` flips the default off, and a host may set it per script
world). Enforcement flows through a single point, `tryCast` in
[`insanity/runtime/Interp.hx`](../insanity/runtime/Interp.hx), reached at variable declarations,
function arguments, function returns, `(e : T)`, and `cast(x, T)`:

- **`cast(x, T)` is a real checked cast.** In typed mode it throws when `x` is not a `T`, like Haxe's
  safe cast. `x is T` / `Std.isOfType(x, T)` also work for classes, interfaces, scripted enums, and
  the primitives.
- **Assignments are checked, Haxe-strict.** `var x:Int = aFloat`, a wrong-typed argument, or a return
  that doesn't match its declared type throws (surfaced through the script-error funnel). `Int`
  widens to `Float` where Haxe allows it. Containers (`Array`, `Map`) and function types (a callable
  is required for `f:Int->Void`) are checked; structural typedefs are checked by field presence, and
  `private` members are access-checked.
- **`Int` and `Float` are correct.** Integer arithmetic stays `Int` (so `is Int`, integer map keys,
  and array indices behave), and `/` is always `Float`. One platform caveat: on hxcpp a
  whole-number `Float` boxed in a `Dynamic` reads back as `Int` (`Type.typeof(10/2)` is `TInt`).
  That is harmless, and unavoidable in a `Dynamic` interpreter.

What is still missing is everything that needs the *compiler*:

- **No compile-time type errors and no inference.** Mismatches surface as runtime throws, not
  editor/compile errors. There is no static checker in the
  library (the upstream one was removed as dead code); adding one is a possible future direction.
- **No overload resolution.** Haxe's method overloading and implicit conversions at call boundaries
  don't exist.
- **`untyped` is a no-op**, there is nothing to suppress.

Setting `Config.typedMode = false` (or `-D insanity_dynamic`) reverts to fully-dynamic behavior:
annotations are ignored and only abstract `from`/`to` casts apply.

## 2. Type parameters and structural types erase

- **Generics are erased.** `class Pool<T>` parses and runs, but parameter *names* are kept and
  *constraints are dropped*; every `T` resolves to `Dynamic`. See the note on
  `params:Array<String>` in [`insanity/syntax/Expr.hx`](../insanity/syntax/Expr.hx). There is no
  generic type safety.
- **Anonymous-structure typedefs are checked by shape, not by field type.** `typedef Foo = {x:Int}`
  (named or inline `{x:Int}`) works for `is`, `cast`, and variable/argument annotations, matching any
  value that has all the required *field names* (`ScriptedTypedef.matchesStructure` in
  [`insanity/types/ScriptedTypedef.hx`](../insanity/types/ScriptedTypedef.hx)). Field *types* are
  not verified, so `{x: "str"}` still satisfies `{x:Int}`. **Function typedefs** (`typedef F = Int->Void`)
  have no matchable shape and erase.

## 3. Scripted abstracts are hollow

A script may declare `abstract` / `enum abstract`, but the underlying type, `from`/`to`, and
operators **all erase**: it desugars to a plain class of statics/constants (`parseAbstractDecl` in
[`insanity/syntax/Parser.hx`](../insanity/syntax/Parser.hx)).

- **No operator overloading** (`@:op`), no implicit `@:from`/`@:to`, no value boxing.
- An `enum abstract` gives you unqualified constants and nothing more.

Native (compiled) abstracts *are* bridged via
[`insanity/macro/AbstractMacro.hx`](../insanity/macro/AbstractMacro.hx), static and
instance fields and `from`/`to` casts work, but operator overloading there is still a TODO.

## 4. Overriding native (bridged) methods has holes

Scripts extend curated native bases through generated bridges
([`insanity/macro/ScriptedMacro.hx`](../insanity/macro/ScriptedMacro.hx)). A native
method **cannot be overridden** when it is:

- **`inline`**, no runtime method exists to route through.
- **`final`**.
- **`@:generic`**, the compiler emits one specialized field per instantiation, so there is no single
  method to override.
- **`dynamic`**, `super.f()` is illegal on it; scripts reassign these at runtime instead.
- signed with a **`private`/inaccessible type**, or a **class type-parameter that couldn't be
  substituted**, such methods fall through to the native `super` silently.

## 5. No macros or compile-time metaprogramming

Scripts cannot define or run macros, `@:build`/`@:autoBuild`, expression reification (`macro ...`),
or `@:genericBuild`. Those mechanisms run at *engine* compile time; script code is the dynamic layer
and never reaches that stage.

## 6. Smaller semantic differences

- **Access control is partial.** `private` is enforced in typed mode (or when `Config.strictAccess` is
  set), but only for members marked `private` *explicitly*. **Unmarked members are public**, unlike
  Haxe, where the default is stricter. See `checkAccess` in
  [`insanity/runtime/Interp.hx`](../insanity/runtime/Interp.hx).
- **Custom metadata is inert.** Only a handful are honored: `@:bypassAccessor`, `@:snapshot`,
  `@:safe`, `@:enumAbstract`, `@:enum`, `@:keep`, `@:coreType`. Anything else parses and does nothing.
- **Interfaces carry no default implementations**, signatures only.
- **No `@:structInit`, `@:forward`, `@:op`, or `@:multiType`.** `Map` is the one special-cased
  multi-type (its implementation is picked from the key type).
- **`inline` / `final` have no optimization effect**, they parse, but everything is interpreted.
  There is no constant folding, inlining, or dead-code elimination; expect interpreter-level
  performance.

## 7. Scripts can only reach what survives DCE

A script calls native code by reflection, which the compiler cannot see. With dead code elimination
on (Haxe defaults to `-dce std`), a std or library method that the **host** never calls statically
can be stripped, and the script's call then fails at runtime with "Cannot call null".

This is easy to mistake for a library bug. A standalone test program that never touches `EReg`
compiles without `EReg.replace`, so `~/a+/g.replace(...)` fails there while working under `-dce no`.

Mitigations, in order of preference: call the API somewhere in the host, add an `include()` for the
type in the build, or register a `Config.callShims` entry. The same reasoning covers `inline`
methods, which have no runtime form at all to reflect on regardless of DCE (see section 8).

## 8. Interop subtlety worth knowing

Scripted types are ordinary **class instances**, not native `Class<T>` / `Enum<T>` / `EnumValue`
runtime objects. Any interop path that hard-types a parameter or return as one of those will coerce a
scripted instance to `null` at the call boundary (this is what broke bare enum construction before
the `createEnum` fix, see the note on that method in
[`insanity/runtime/Interp.hx`](../insanity/runtime/Interp.hx)). Keep scripted-type boundaries
`Dynamic`.

---

## What has parity

For reference, the following behave like Haxe:

- classes, `extends`, `override`, `super(...)`;
- scripted interfaces **and** native interface implementation (via the bridge);
- enums with parameterized constructors, and `switch` with extraction, guards, `|` alternatives, and
  array/object patterns;
- typedef aliases to named types;
- `static` / instance / `private` / getters & setters (`get`/`set`/`null`/`never`/`default`/
  `dynamic`), `final` fields;
- `using` static extensions;
- `import`, normal, `as` alias, wildcard `.*`, and single static field / enum constructor;
- string interpolation (`'$ident'`, `'${expr}'`), array and map comprehensions;
- optional, default, and rest (`...`) arguments;
- typed **multi-catch** and raw `throw` of any value;
- closures with capture and self-recursion;
- `#if` / `#elseif` / `#else` / `#end` preprocessing against defines;
- runtime **type enforcement** of variable, parameter, return, and `cast(x, T)` annotations, plus
  `is` / `Std.isOfType` on classes, interfaces, scripted enums, and the primitives (typed mode);
- **`Int`/`Float` correctness**, integer arithmetic stays `Int`, `/` is `Float`.
