# Embedding the library in your game

How to put hscript-insanity into a Haxe project: running scripts, giving them access to your game,
letting them subclass your classes, and the things that will bite you.

[`example/`](../example) is a complete worked version of everything below: a small turn-based RPG
whose creatures, bosses and status effects are all loaded from scripts. Run it, then read
`example/game/Mods.hx`, which is the entire integration in one short file.

```
haxe -cp . -cp example -main Main --macro include('bridges') --macro macros.BridgeMacro.generate() --interp
```

For what a script can and cannot do once it is running, see [`parity.md`](parity.md).

## 1. Install

```
haxelib git hscript-insanity https://github.com/MeguminBOT/hscript-insanity
```

Then add the library to your build (`-lib hscript-insanity` in an hxml, or
`<haxelib name="hscript-insanity" />` in a Project.xml). Nothing else is required to start: the table
of compiled types that scripts resolve names against builds itself the first time it is used.

In a Lime or OpenFL project that is three lines, and they are the only build-level requirement the
library has:

```xml
<haxelib name="hscript-insanity" />

<!-- keeps the scripting bridges in the build; see section 6 -->
<haxeflag name="--macro" value="include('bridges')" />
<haxeflag name="--macro" value="macros.BridgeMacro.generate()" />
```

[`example/Project.xml`](../example/Project.xml) is a complete one, including shipping the scripts as
assets so they sit beside the executable.

## 2. Run a script

```haxe
var script = new Script("
	greeted = 0;
	function greet(who) { greeted++; return 'hello, ' + who; }
", "hello");

script.start();                          // runs the program top to bottom
script.call("greet", ["world"]);         // "hello, world"
```

`start()` returns the value of the program's last expression, so a one-line script is a usable
expression evaluator:

```haxe
new Script("1 + 2;", "v").start(); // 3
```

## 3. What a script shares with you

A script's `variables` map is its global scope, and the distinction that catches people is this:

```haxe
greeted = 0;      // a script variable: visible in script.variables
var notShared = 0; // a local of the program: NOT visible
```

Declared functions are script variables, which is why `call()` finds them.

**`start()` clears `variables` before it runs.** It calls `setDefaults()`, which wipes the map and
re-applies the global tables, so anything you set beforehand is gone. There are three places to put
your API, depending on how widely it should apply.

**One script world** (the usual choice). An `Environment`'s variables are copied in after the reset:

```haxe
var world = new Environment();
world.variables.set("damage", 21);

new Script("damage * 2", "w", world).start(); // 42
```

**Every script in the process**, via the global table, which `setDefaults()` re-applies:

```haxe
Config.globalVariables.set("VERSION", "1.4.0");
```

**One script, after it has started**, then call in:

```haxe
var s = new Script("function hit() return damage * 2;", "expose");
s.start();
s.variables.set("damage", 21);
s.call("hit"); // 42
```

## 4. Exposing your types

Every type compiled into your program is reachable by an explicit `import` in a script, the way real
Haxe behaves. To make a name resolve bare, register it as a global import:

```haxe
import insanity.syntax.Expr.ImportMode;

Config.globalImports.set("game.Entity", INormal);
```

```haxe
class Slime extends Entity { ... } // no import needed in the script
```

Two things to know, the second of which is sharp:

- **Imports resolve before variables.** A global import shadows a variable of the same name, so if
  you bind `File` to a sandboxed replacement, do not also global-import the real one.
- **A global import that cannot resolve throws out of the `Script` constructor, uncaught.** Global
  imports are applied on every interpreter reset, before your error handlers exist, so this is not
  routed anywhere: it escapes into your code as `Type not found: X`. It happens when the name is not
  compiled into this build, and equally when the name is blacklisted. Guard the registration:

```haxe
for (path in myTypes)
	if (TypeCollection.main.fromPath(path) != null)
		Config.globalImports.set(path, INormal);
```

A script's own `import` of a missing or blacklisted type is fine by comparison: it is reported
through `onProgramError` like any other script error.

## 5. Errors

Runtime errors are routed, not thrown at your game loop:

```haxe
var s = new Script("null.explode();", "boom");
s.onProgramError = function(e) log(e.message);
s.start();   // returns null, sets s.failed
```

**Parse errors are different, and this is a sharp edge.** Parsing happens inside the constructor, so
a handler assigned afterwards is already too late. The program is left null:

```haxe
var bad = new Script("this is not haxe", "bad");
bad.program == null; // true. `failed` is still false: only start() sets that
```

To have the handler fire, construct empty and parse explicitly:

```haxe
var s = new Script("", "deferred");
s.onParsingError = function(e) log(e.message);
s.parse(source);
```

## 6. Letting scripts subclass your classes

This is the part worth understanding, because it is what turns "run some expressions" into
"mods extend the game".

Declare a bridge: an empty class extending the base you want scriptable, implementing
`insanity.IScripted`.

```haxe
package bridges;

import game.Entity;

class ScriptedEntity extends Entity implements insanity.IScripted {}
```

That is the whole declaration. The `@:autoBuild` on the interface generates an override of every
inherited method that dispatches to the script when it defines one and falls through to `super`
otherwise, and it registers `Entity` as extendable.

**The bridge must be compiled into your build.** Nothing in your code references it, so the compiler
never types it and the registration never happens. Force it in:

```
--macro include('bridges')
```

Without this you get `Class Entity can't be extended for scripting` at the moment a script tries to
extend it, which reads like a library limitation and is actually a missing build flag.

Scripts then write ordinary Haxe, and what comes back is a real instance of your class:

```haxe
class Bandit extends Entity {
	public function new() {
		super('bandit', 34, 8);
	}

	override public function takeTurn(battle:Battle) {
		var target = battle.pickFoe(this);
		battle.log('$name lunges at ${target.name}');
		target.damage(battle, attack, this);
	}
}
```

```haxe
var bandit:Entity = cast(world.resolve("Bandit"), ScriptedClass).typeCreateInstance([]);

bandit is Entity;         // true: hand it to any native code that takes an Entity
bandit.damage(battle, 5); // inherited methods work
bandit.takeTurn(battle);  // your own turn loop runs the script's override
```

A script can also call `super`, build more of its own class (the example's slime splits into two
slimes), and construct native classes the host never exposed to it by name.

Two constraints:

- **Cost is one generated override per inherited method** that is not `inline` or `final`. Bridging a
  class with a large method surface is not free in code size, so bridge the classes people actually
  subclass rather than everything.
- **`final` classes cannot be bridged**, which is a useful lever: keeping a hot-path class `final`
  both lets the compiler devirtualize it and keeps it off the scriptable list deliberately.

### Generating bridges instead of writing them

A bridge is boilerplate, so past a handful of bases it is better generated. An init macro can define
them from a list, and emit an array that references them, which replaces the `include` above: what
keeps a bridge in the build is something referring to it.

```haxe
for (base in BASES) {
	var parts = base.split('.');
	var superPath = {name: parts.pop(), pack: parts};

	Context.defineModule('bridges.Scripted' + superPath.name, [{
		pack: ['bridges'],
		name: 'Scripted' + superPath.name,
		pos: pos,
		meta: [{name: ':keep', pos: pos}],
		kind: TDClass(superPath, [{pack: ['insanity'], name: 'IScripted'}], false, false, false),
		fields: []
	}]);
}
```

Give each bridge its own module: defined as a sub-type of a shared module, it could only ever be
named through that module. `example/macros/BridgeMacro.hx` is the whole thing, and the example runs
both forms side by side (`Entity` by hand, `Component` generated) so the difference is visible.

Adding a scriptable base then costs one line. Keep the list to what scripts actually subclass: the
cost is one generated override per inherited method, per base.

## 7. Scripted classes, modules, and worlds

A `Module` is one source file's worth of declarations. An `Environment` is the world they live in,
and what scripts resolve against.

```haxe
var world = new Environment();

for (file in FileSystem.readDirectory(dir))
	world.addModule(new Module(File.getContent('$dir/$file'), name, [], '$dir/$file'));

world.variables.set("roll", function(sides:Int) return 1 + Std.random(sides));
world.start();
```

Give the environment your API through `world.variables` (section 3) and every module and script in
it sees the same thing.

### Do not name scripts from the host

It is tempting to write `spawn("HiveQueen")` in your game code, and it undoes most of the benefit:
every new piece of content then needs a host change. Ask the world what it has instead.

```haxe
for (module in world.modules)
	for (name => type in module.types)
		if (type is ScriptedClass) { ... }
```

The example filters those by two things: whether the class descends from a native base
(`cls.instanceClass`, walked up with `Type.getSuperClass`), and a static the script declares about
itself (`cls.reflectGetField("side")`). That is enough for content to announce what it is, so
dropping a file into the scripts folder is the whole installation step. See `Mods.roster`.

## 8. What scripts can declare

Scripts are not limited to classes. A module can hold the same mix of types a Haxe module can, and
they behave the way you would expect:

```haxe
enum Element {
	Physical;
	Fire(intensity:Int);
}

typedef Loot = {
	var gold:Int;
	@:optional var charm:String;
}

interface Lootable {
	public function loot():Loot;
}

abstract Damage(Int) from Int to Int {
	public function new(v:Int) this = v;

	@:op(A + B) public function add(rhs:Damage):Damage return new Damage(this + rhs);
}
```

- **Enums** carry parameters, destructure in `switch`, and support guards.
- **Typedefs** are checked structurally, by field *and* by field type, and `?x:Int` fields may be
  absent. A value with extra fields still satisfies one.
- **Interfaces** work between scripted classes.
- **Abstracts** box their underlying value and carry their operators, `from`/`to` conversions and
  `@:forward`. They cost a wrapper at runtime, so they are worth it for meaning, not for speed.

Two things to know:

- **Types from another module need importing**, exactly as in Haxe. Everything shares one
  environment, but `import Combat;` is still what brings `Element` into scope, and an enum
  constructor from another module is written `Element.Fire(6)`.
- **A script cannot declare a field that its native base already has.** The error names it
  (`Field name should be declared with 'override' since it is inherited`), which is usually a
  collision with something ordinary like `name`.

`example/scripts/Combat.hx` declares all four in one module, and `Elementalist.hx` uses them
together.

## 9. Reloading

Rebuild the world: snapshot it, drop it, and construct a new `Environment` from freshly-read sources.

```haxe
env.snapshot(); // preserves statics marked @:snapshot across the reload
env = null;
```

Track file modification times to decide when to do it. `ScriptRegistry` in the Psych Engine
integration is a worked example: a path-to-timestamp map, a `stale()` check, and a rebuild.

## 10. Locking scripts down

```haxe
Config.blacklist.get(ByType).push("sys.io.File"); // also ByModule and ByPackage
Config.strictAccess = true;                       // enforce script-declared `private`
```

Blacklisting is by name, so use fully-qualified ones. Prefer packaged names: blacklisting a
top-level type such as `Sys` also works, but the default root wildcard import tries to resolve it on
every interpreter reset and logs a warning each time. A blacklisted type must never also be a global
import: the import cannot resolve, and that failure escapes the `Script` constructor uncaught (see
section 4).

## 11. Typed mode

Type annotations are enforced at runtime by default: a wrong-typed assignment, argument or return
throws rather than silently proceeding. `Config.typedMode = false` (or `-D insanity_dynamic`) turns
that off and leaves everything dynamic. Numeric correctness (`Int` staying `Int`) is unconditional.
See [`parity.md`](parity.md#1-typed-by-default-with-a-dynamic-escape-hatch).

## 12. Things that will bite you

- **Dead code elimination.** With `-dce std`, methods your own code never calls statically are
  stripped from the build, and a script reaching one by reflection gets `Cannot call null`. It looks
  like a library bug and is not. `-dce no`, or `@:keep` on what scripts need.
- **`inline extern` methods have no runtime form.** Reflection finds nothing, so the call fails.
  Register a real closure that performs the call in `Config.callShims`, keyed
  `<fully.qualified.Owner>.<method>`; the interpreter walks the receiver's superclasses looking for
  one before giving up. Flixel 6.2 turning `FlxG.sound.playMusic` into this form is the case that
  motivated it.
- **Native abstracts need a build macro** to have any runtime form:
  `@:build(insanity.macro.AbstractMacro.build())`. Without it, scripts see nothing usable. Abstracts
  declared *in scripts* need no setup.
- **Build macros hold type paths as strings**, which the compiler cannot check for you. If you rename
  a bridged base or move a package, nothing fails at compile time; it fails when a script asks.

## Where to go next

- [`parity.md`](parity.md) covers what scripts can do compared to real Haxe, and the deliberate
  divergences.
- [`performance.md`](performance.md) covers what is fast, what is not, and how to measure a change
  without fooling yourself.
- [`../example/`](../example) is the worked version of this guide, and is runnable.
- [`../test/`](../test) holds the suites, which double as executable documentation of behaviour.
