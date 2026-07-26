# hscript-insanity

Parse and evaluate Haxe at runtime, with enough of the language intact that a script can declare
classes, enums, typedefs and abstracts, and extend your compiled ones.

A fork of [inky03/hscript-insanity](https://github.com/inky03/hscript-insanity), itself an
experimental fork of [hscript](https://github.com/HaxeFoundation/hscript). Upstream drew on
[hscript-iris](https://github.com/pisayesiwsi/hscript-iris) and
[RuleScript](https://github.com/Kriptel/RuleScript); both are worth a look.

What this fork adds on top of upstream:

- **Type annotations enforced at runtime**, with `-D insanity_dynamic` to turn it off, and `Int`
  versus `Float` kept correct regardless.
- **Abstracts that work**, declared in a script or compiled into the host: operators, array access
  and `from`/`to` conversions, plus `@:forward` on scripted ones.
- **Structural typedefs checked by field type**, not just by field name, with optional fields.
- **Documentation and a runnable example** (below), rather than a feature list alone.
- Interpreter performance work, measured rather than assumed; see
  [performance.md](docs/performance.md).

Still a work in progress: the [TO-DO](#to-do) lists what is implemented and what is missing, and
[parity.md](docs/parity.md) is honest about where scripts diverge from real Haxe. Pull requests
welcome at [this fork](https://github.com/MeguminBOT/hscript-insanity/pulls).

## Documentation

- **[Embedding guide](docs/embedding.md)** -- putting the library in your own game: running scripts,
  exposing your API, letting scripts subclass your classes, and the things that will bite you.
  Worked end to end in [`example/`](example), a scriptable RPG battle you can run.
- [Parity with Haxe](docs/parity.md) -- what scripts can and cannot do compared to real Haxe.
- [Performance](docs/performance.md) -- what has been optimized, and how to measure without fooling yourself.
- [Tests](test) -- the suites, which double as executable documentation of behaviour.


## Features & Amendments

### Simple [`Script`](insanity/Script.hx) class

Allows you to load code from a string, give it a name, and run it easily!

```hx
import insanity.Script;

var script:Script = new Script('
function testFunction(a, b, c)
	trace(a + b + c);

trace("hi!!");
', 'MyScript');

script.start();
script.call('testFunction', [1, 2, 3]);
```

You can also edit the `variables` map in a `Script` to define custom globals on a script.<br>
By default, `this` and `script` are defined as the `Script` instance, and `interp` as the instance's interpreter.


### Scripted modules and types (with [`Module`](insanity/Module.hx) and [`Environment`](insanity/Environment.hx))

> [!WARNING]
> This feature is experimental and still incomplete!

You can load custom modules from strings and use them in scripts!

```hx
var path:String = 'test/source/TestModule.hxs';
var module:Module = new Module(File.getContent(path), 'TestModule', ['package', 'name'], path);

var environment:Environment = new Environment([module]);
environment.start();

/*
new Module creates a new module script instance...
you can then add it to a new Environment ! (think of it as the source code folder)
start() it to initialize all added modules and make them usable in new Scripts !!
*/

var path:String = 'test/scripts/TestScript.hxs';
var script:Script = new Script(File.getContent(path), path, environment);
script.start();
```

...or you can define module types in a script itself, for example:

```hx
class TestClass {
	public function new() {
		trace('hi!!');
	}
}

var instance:TestClass = new TestClass();

/*
do note that classes defined in scripts have certain limitations,
such as (maybe expectedly) not being importable in other scripts !
*/
```

To make a Haxe class extendable for scripting, extend it and implement the `insanity.IScripted` interface, like the following example:

```hx
class BaseThing {
	// ...
}

class ScriptedThing extends BaseThing implements insanity.IScripted {}
```

You can also edit the `variables` map in a `Module` or `Environment` to define custom globals on subtypes and submodules, respectively.<br>
By default, `module` is defined as the `Module` instance in modules, and `interp` as the class interpreter in scripted classes.

If you want to import other sub-modules within your module, you may do so by changing the `subModules` array!<br>
Import modules (i.e. `import.hx`) are also supported and may be added via the [`ImportModule`](insanity/Module.hx) class.

Currently , the following types can be scripted:
- [Classes](https://haxe.org/manual/types-class-instance.html)
- [Typedefs](https://haxe.org/manual/type-system-typedef.html) (only type alias typedefs are enforced)
- [Enums](https://haxe.org/manual/types-enum-instance.html) (with & without parameters)
- [Module level fields](https://haxe.org/blog/module-level-fields/) (including their respective `Module_Fields_` class)

Scripted abstracts are supported: they box their underlying value, and their methods, properties, statics, operators and `from`/`to` conversions all run. See the parity document for the limits.

(NOTE: currently only most behavior is properly implemented from extending classes. while i dont see why implement the interface in the base class, some things might have to be promptly fixed to correctly support them ...)


### Global script configs (with [`Config`](insanity/Config.hx))

[`insanity.Config`](insanity/Config.hx) allows you to define custom behaviors in scripts, such as...
- Proxying or blacklisting types, modules and packages,
- swapping the default interpreter class,
- defining preprocessors for conditionals,
- defining variables, and
- defining imports!

These behaviors will be applied globally, to all scripts.


### Typed mode & numeric correctness

Scripts run **typed by default**. Declared types on variables, function arguments, function returns, and `cast(x, T)` are enforced at runtime: an incompatible value throws (surfaced through the script error funnel), the way typed Haxe would reject it. `is` / `Std.isOfType` / `cast` also work on the `Int`, `Float`, and `Bool` primitives, not just on classes.

```hx
var x:Int = 5;        // ok
var y:Int = 3.5;      // throws: 3.5 should be Int
var f:Float = 5;      // ok, widened to Float
trace(cast(5, Int));  // 5
trace(5 is Int);      // true
```

Numeric arithmetic is corrected too: integer math keeps the `Int` type (so `is Int`, integer map keys, and array indices behave), while `/` is always `Float`, matching Haxe.

Enforcement is controlled by [`Config.typedMode`](insanity/Config.hx), which defaults on. Set it to `false` (or compile with `-D insanity_dynamic`) to fall back to fully dynamic behavior, where type annotations are ignored.

> [!NOTE]
> On the hxcpp target, a whole-number `Float` stored in a `Dynamic` reads back as `Int` (for example `Type.typeof(10 / 2)` is `TInt`). This is a platform trait and is harmless.


### Abstracts

> [!WARNING]
> This feature is very experimental. Use with caution! <br>
> Add the `@:build(insanity.macro.AbstractMacro.build())` metadata to your abstracts to make them usable in Hscript.

Importing abstracts and abstract features are *mostly* supported.

Due to technical limitations, you must *explicitly* cast an expression to the desired type (recommendably, store it in a local variable to modify it with less overhead).<br>
You can also include a type parameter for an implicit cast in variable / method argument declarations.

Enum abstracts are also supported!

```hx
import flixel.util.FlxColor;

function colorToString(color:FlxColor)
	return '(red: ${color.red} | green: ${color.green} | blue: ${color.blue})';

var color:FlxColor = cast 0xff0040; // or cast(0xff0040, FlxColor)
trace(colorToString(color)); // (red: 255 | green: 0 | blue: 64)
color.green = FlxColor.GREEN.green;
trace(colorToString(color)); // (red: 255 | green: 128 | blue: 64)
```


### Imports

The [`import`](https://haxe.org/manual/type-system-import.html) keyword is supported!

You can import classes by module or package path (wildcard), similarly to actual Haxe. Importing a single class or class field is supported, as well as aliases!

All bottom level classes like Reflect, Type and your Main application class should similarly also be exposed by default in scripts.

```hx
import sys.*; // sys package wildcard
import Reflect.getProperty as get;

trace(FileSystem.exists('Main.hx'));
trace(get({hi: 123}, 'hi'));
```

You can also import type alias typedefs, and module level fields!<br>
(Due to type parameters being mostly stripped at runtime, adding support for importing anonymous structure typedefs is not very practical)

All compile-time type information is accessible in [`insanity.types.TypeCollection.main`](insanity/types/TypeCollection.hx).


### Using (static extension)

The [`using`](https://haxe.org/manual/lf-static-extension.html) keyword is supported (to most capacity)!

```hx
using Lambda;

var array:Array<Int> = [1, 2, 3, 4, 5];

array = array.map(function(item) {
	if (item == 3) return 10;
	else return item;
});

trace(array); // [1, 2, 10, 4, 5]
```


### Enums

Enums can be imported (or created) in Hscript and support constructors.<br>
[Enum matching in switch-case statements is also fully implemented!](#pattern-matching)

```hx
// in source code ...
enum TestEnum {
	Hi(message:String);
	Bye;
}

// in script ...
import TestEnum;
trace(Hi('hello!!'));
trace(Bye);
```


### String interpolation

Haxe's [string interpolation](https://haxe.org/manual/lf-string-interpolation.html) feature is fully supported!

```hx
var test:Int = 1234;

trace('hello $test ${'can also be nested!! $$${test + 3210}'}');
```


### Pattern matching

Haxe's advanced [switch-case pattern matching features](https://haxe.org/manual/lf-pattern-matching.html) are fully supported!

```haxe
var struct:Dynamic = {name: 'Haxe', rating: 'Awesome'};

trace(switch (struct) {
	case {name: a, rating: b}:
		'$a is $b';
	default:
		'no awesome language found';
}); // Haxe is Awesome
```


### Property accessors

Haxe's [property accessors](https://haxe.org/manual/class-field-property.html) can be defined in variables within scripts and scripted classes!

```hx
var customSetter(default, set):Dynamic = 123;

function set_customSetter(v:Dynamic):Dynamic {
	trace('setting to $v !');
	return customSetter = v;
}

customSetter = 456;
```


### Field access

You can now access fields from real[^1]/scripted modules and types in scripts without having to import them beforehand!

```haxe
trace(haxe.io.Bytes.ofString('hello world').getString(0, 5)); // hello
```


### Regular expression syntax

Haxe's [regular expression syntax](https://haxe.org/manual/std-regex.html) can now be used in Hscript (instead of just `new EReg`)!

```hx
trace(~/hx/i.replace('HX is Awesome', 'Haxe')); // Haxe is Awesome
```


### Call stack

`Script` program exceptions now throw an `InterpException`, containing more detailed error info more akin to Haxe's exception call stack.

Also imposes a limit for the call stack before a Stack overflow exception (200 by default, can be adjusted with `callStackDepth` in an `Interp` instance)

```
Exception: ouch...
Called from test/TestScript.hxs.crash (test/TestScript.hxs line 2 column 8)
Called from script test/TestScript.hxs (test/TestScript.hxs line 4 column 1)
Called from Main.main (Main.hx line 10 column 3)
```


### Null coalescing operators

~~Albeit partially supported in the original library (`?.`) the other [null coalescing operators](https://haxe.org/manual/expression-null-coalesce.html) (`??` and `??=`) are now implemented~~<br>
~~also fixes unintended behavior with `ident?.method()` throwing an error is the ident is null~~<br>

(these seem to be implemented in the original library too now!)


### Function arguments

- **Rest**
	
	[Rest argument](https://api.haxe.org/haxe/Rest.html) can now be used in functions
	
- **Optional arguments**
	
	Providing a default value for an argument now treats it as optional, regardless of a `?` preceding the argument name (which is, presumably, unintended behavior in the original library)
	
	A bug where default argument values didn't work as intended in specific conditions is also corrected.
	
	```hx
	function test(?arg = false, arg2 = false) {
		trace(arg);
		trace(arg2);
	}
	```


## Conditionals & defines

Scripts now include the default compilation defines / preprocessor values by default, and you can add custom defines in [`Config`](insanity/Config.hx).<br>
Comparisons are now also supported in conditionals!

```haxe
#if (haxe >= '4.3.7')
	// ...
#end
```

A small EOF bug with conditionals has also been fixed.


## Map declaration

> [!WARNING]
> This only applies to the first level, thus nested maps won't be correctly inferred if empty. (todo ?)

You can now declare empty maps, inferring from type parameters (in the original library, `[]` usually just declares an empty array).

```hx
var map:Map<String, Dynamic> = [];
trace(Type.typeof(map));

var array = [];
trace(Type.typeof(array));
```

[Map comprehension](https://haxe.org/manual/lf-map-comprehension.html) is now also supported, joining array comprehension!

```haxe
var map:Map<Int, String> = [for (i in 0 ... 5) i => 'number ${i}'];
```


## TO-DO

### compiled

- abstracts
	- [X] static fields
	- [X] instance fields
	- [X] cast from / to types
	- [X] overload operators (`@:op`, `@:arrayAccess`)
	- [X] `@:forward` (bare or with a field list)
	
- enum abstracts
	- [X] static fields
	- [X] constructors
	
- enums
	- [X] constructors
	- [X] constructor arguments
	
- typedefs
	- [X] type alias import
	- [X] anonymous structure (checked by field name *and* field type, with optional fields)

- module level fields
	- [X] import

### scripted

- types
	- [X] classes
 		- extends
			- [X] Nothing (or scripted class)
			- [X] Real[^1] types
  		- fields
			- [X] property getters & setters
				- [X] accessor error checking in modules
      		- [X] scripted toString
  			- [X] iterables and iterators
	- [X] enums
	- [X] typedefs (type alias + structural shape check)
	- [X] module level fields
	- [X] abstracts
		- [X] underlying type (values are boxed)
		- [X] constructor, methods, properties, statics
		- [X] `from` / `to` conversions
		- [X] operators (`@:op`, `@:arrayAccess`)
		- [X] enum abstract (constants, qualified and bare)
		- [X] `@:forward` (bare or with a field list)

- general
	- [X] fix compile errors in HashLink (for now)
	- [ ] module exception call stack (inherited item; a script error and a module error currently
  report the same way, so what was meant here is unclear)
	- [ ] abstract-typed class fields: a local `var v:MyAbstract` boxes, but a class or static field
  declared with an abstract type does not

### typed mode

- [X] runtime type enforcement (variable / argument / return / `cast`)
- [X] `Int` / `Float` / `Bool` as `is` / `cast` targets
- [X] `Int` / `Float` numeric correctness
- [X] `Config.typedMode` toggle (`-D insanity_dynamic`)
- [X] container (`Array` / `Map`) and function-type checking
- [X] structural typedef shape checking
- [X] `private` access enforcement (with typed mode)
- [ ] static checking before a script runs (upstream's `Checker` was removed as dead code; a
  replacement would use the compiled type table, and is a large piece of work)

### other

- [X] proper documentation (embedding guide, parity, performance, runnable example)
- [ ] Script type parameter for interp class instead of Config (maybe ?)
- `import` keyword
	- [X] module level fields
- `using` keyword
	- [ ] explicit type checking for extensions on *scripted* classes (a `using` currently matches by
	  method name alone, so `(5).twice()` reaches a `String` extension; see the impossible list for
	  why compiled extensions cannot be checked)
- `switch` keyword
	- [X] complex pattern matching
		- [X] capture variables
		- [X] extractors
		- [X] enum
		- [X] array
		- [X] struct
		- [X] guard conditions
		- [X] multiple values (partial)
- `Printer` class
	- [X] escape characters in printed expressions round-trip
	- [ ] module declaration to string (prints expressions; class/enum/typedef declarations are not printed)

## Impossible to add

Not "not yet": these need information that stops existing once the Haxe compiler has finished, so no
amount of emulation or shimming inside a runtime interpreter recovers it.

- **Macros, `@:build` and reification in scripts.** A macro runs *in* the compiler. There is no
  compiler at runtime to run one.
- **Compile-time type errors and inference.** The interpreter sees values, not the types of
  expressions that have not run yet. Annotations are enforced when a value passes through them, which
  catches the same mistakes, just later. A separate static checker over the AST could catch some
  before running; that is the `Checker` item above, and it is a different thing from inference.
- **Generic type safety.** Type parameters are erased by the Haxe compiler itself, so at runtime
  `Array<Int>` and `Array<String>` are the same type. Nothing can distinguish them.
- **`@:multiType`.** Choosing an implementation from a type parameter is a compile-time decision.
  `Map` works only because it is special-cased on the key's runtime value.
- **Type-checking `using` extensions on compiled classes.** A compiled static's parameter types do
  not exist at runtime, so the first argument cannot be checked against them. Extensions declared in
  a script can be checked, because their declarations are still around.
- **Overriding a native `inline` or `final` method.** An `inline` method has no runtime
  representation to override, and a `final` one is devirtualized at the call site. Calls to them can
  be emulated with `Config.callShims`; overriding them cannot.

[^1]: "Real" refers to classes generated by the Haxe compiler (i.e., non scripted classes)