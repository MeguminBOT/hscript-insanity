# Macros, a custom interpreter, and binding your API

[embedding.md](embedding.md) covers getting scripts running. This covers what a host reaches for
once they are: **generating bridges** instead of writing them, **making native abstracts visible**
to scripts, **wiring in a game library** you do not own, **subclassing the interpreter**, and the
full set of **binding surfaces** for handing your API over.

Everything here is in [`../examples/battle/`](../examples/battle) and runs:

```
haxe -cp src -cp examples/battle -main Main \
  --macro include('bridges') --macro macros.BridgeMacro.generate() \
  --macro macros.AbstractsMacro.generate() --macro include('game') --interp
```

The same wiring in project form is [`../examples/battle/Project.xml`](../examples/battle/Project.xml).

---

## 1. Generating bridges

A script writes `class Slime extends Entity` only if a **bridge** exists: an empty class extending
`Entity` and implementing `hxscript.IScripted`, whose `@:autoBuild` generates an override of every
inherited method that dispatches to the script and falls through to `super`.

Written by hand that is one file per base ([`../examples/battle/bridges/ScriptedEntity.hx`](../examples/battle/bridges/ScriptedEntity.hx)),
which is clearer for one or two. Past that it is a folder of identical empty classes, each of which
has to be kept in the build by hand, so generate them:

```haxe
Context.defineModule('$PACK.$name', [{
	pack: pack,
	name: name,
	pos: pos,
	meta: [{name: ':keep', pos: pos}],
	kind: TDClass(superPath, [{pack: ['hxscript'], name: 'IScripted'}], false, false, false),
	fields: []
}]);
```

Full version: [`../examples/battle/macros/BridgeMacro.hx`](../examples/battle/macros/BridgeMacro.hx). Three details
in it are not obvious and all three are load-bearing.

**One module per bridge.** A type defined as a sub-type of another module can only be named through
that module, so putting them all in one makes every reference read
`bridges.Bridges.ScriptedFlxSprite`.

**Something has to reference them.** Bridges are only ever instantiated reflectively, so nothing in
the program refers to one and DCE removes them. Emit an array that does:

```haxe
kind: FVar(macro :Array<Class<Dynamic>>, {expr: EArrayDecl(refs), pos: pos})
```

`@:keep` alone is not enough if the module itself is never pulled in; pair it with an
`--macro include('bridges')` or a real reference like the array.

**Cost is per inherited method.** One generated override per non-inline, non-final inherited method.
A wide base is expensive, so bridge the classes scripts actually subclass rather than everything.

A `final` class cannot be bridged at all, and that is sometimes the right trade: keeping a class
`final` lets hxcpp devirtualise calls to it, which is worth more than scriptability on a type that
runs in a hot loop.

---

## 2. Making native abstracts visible

An abstract has **no runtime representation**. A script handed one sees nothing: no methods, no
operators, no `from`/`to`, and for an `enum abstract` none of its constants.
`hxscript.macro.AbstractMacro` emits a reflectable wrapper that gives it one.

On an abstract you own, that is one line:

```haxe
@:build(hxscript.macro.AbstractMacro.build())
abstract Damage(Int) from Int to Int { ... }
```

The abstracts a host actually wants scriptable are mostly in libraries it does not own, and those
cannot be annotated. Apply it from outside instead:

```haxe
Compiler.addMetadata('@:build(hxscript.macro.AbstractMacro.build())', 'game.Damage');
```

[`../examples/battle/macros/AbstractsMacro.hx`](../examples/battle/macros/AbstractsMacro.hx) scans a package for
`abstract` declarations and applies it to each, so an abstract added to a library later is covered
without editing a list. A hand-maintained list gets discovered the hard way: a runtime
`Unknown identifier` from somebody's script, then a rebuild to add one line.

### Four things that will cost you an afternoon

**The type also has to be in the build.** Metadata on a type nothing compiled references does
nothing, because the type is never typed. The script then fails with `Type not found: game.Damage`,
which does not point anywhere near the cause. Pair the macro with an include of the same package:

```
--macro macros.AbstractsMacro.generate() --macro include('game')
```

**An `inline` member stays invisible.** Inlining is a compile-time substitution, so there is no
method for the wrapper to expose and the call fails with `Cannot call null`. This bites hardest on
abstracts, where `inline` is the house style, and it applies whichever way the macro was applied. A
member a script has to reach cannot be `inline`. (Flixel turning `FlxG.sound.playMusic` into an
`inline extern` overload is the same failure one level up; see `callShims` below.)

**A package-wide filter is not an option.** Two shapes break the generator, and it does not degrade
on them, it fails the build: an `enum abstract` with a value-less constructor (`var Red;` with no
`= 0`), and an abstract whose members call each other unqualified. Scan and skip by name.

**Scan text, not the typer.** This runs before typing; asking the typer for a module forces it to be
typed at the wrong moment.

---

## 3. Adding a game library

Everything above applied to code you do not own. A script that says `class Boss extends FlxSprite`
needs four separate things to be true, and each one fails differently:

| | step | symptom when missing |
| --- | --- | --- |
| 1 | the library's types are **in the build** | `Type not found`, or `import()` returns null |
| 2 | a **bridge** exists for each base scripts subclass | `Class <base> can't be extended for scripting` |
| 3 | its **abstracts** are wrapped | `Unknown identifier: ADD`, or an operator does nothing |
| 4 | methods with **no runtime form** are shimmed | `Cannot call null` |

### Step 1: `include`, not `keep`

This is the one that wastes the most time, because the obvious flag is the wrong one.

- **`keep()` only adds `@:keep` metadata to types already being compiled.** It never pulls an
  unreferenced module into the build. Pointing it at a library your program does not otherwise touch
  does nothing at all, silently.
- **`include()` force-compiles *and* keeps every module** in a package.

Both were measured against the example's `game.Damage`, which nothing compiled references:
`--macro keep('game')` leaves it absent from the type table and a script fails with
`Type not found: game.Damage`; `--macro include('game')` puts it there and the script works.

Scripts reach library classes by name, reflectively, so DCE has no reason to keep anything the host
itself never references. `flixel.addons.effects.FlxSkewedSprite` resolves to null in a script for
exactly this reason until it is included.

```
--macro include('flixel', true, ['flixel.addons.nape', 'flixel.addons.editors.spine', 'flixel.system.macros'])
```

The second argument is recursive, and one recursive include covers a library and its addons when
they share a package root (flixel and flixel-addons both live under `flixel`, across classpaths).

**The ignore list is not optional.** Some modules cannot be compiled as ordinary runtime code and
will fail the build:

- **integrations for libraries you do not ship** -- `flixel.addons.nape` needs nape,
  `flixel.addons.editors.spine` needs spine;
- **macro-only classes** -- `flixel.system.macros` uses `haxe.macro.Context` and is meaningless at
  runtime;
- **deprecation stubs** -- `flixel.addons.tile.FlxRayCastTilemap` was removed in flixel-addons 5.9.0
  and its stub does not compile.

Including a library wholesale costs binary size. That is the trade: a script can construct anything,
and the build carries everything.

### Step 2: bridge the bases scripts subclass

A list, as in §1. For flixel that is the display primitives -- `FlxBasic`, `FlxObject`, `FlxSprite`,
`FlxGroup`, `FlxSpriteGroup`, `FlxText` -- plus whichever of your own states and game objects
scripts build on. Twenty or so entries covers a real game.

Keep it to what mods actually subclass. Every entry costs one generated override per inherited
non-inline, non-final method, and a display-object base has a lot of them.

A missing bridge fails in two stages, and only the first names the cause. The module's error hook
reports `Class <base> can't be extended for scripting`, but the type still appears in
`module.types`; instantiating it later throws `Type <name> is not initialized`, which does not
mention the base at all. Watch `onProgramError` during load rather than diagnosing from the
construction site.

**Some bases cannot be bridged, and it is better to find out here than at build time.** OpenFL's
display objects are the standing example: `DisplayObject`'s method surface references openfl-internal
types -- a `private` `Listener`, `openfl.Vector` -- that a generated override cannot reproduce, so
the bridge does not compile. Leave `openfl.display.Sprite` and `Bitmap` out. They are still
importable and constructible from scripts; scripts subclass `FlxSprite` instead.

The general rule: a base whose signatures mention private or otherwise unnameable types cannot be
bridged. §1's "cost is per inherited method" is the other half of the same constraint.

### Step 3: wrap the abstracts scripts touch

§2's scanner, pointed at the library's packages. `flixel` is worth scanning wholesale --
`FlxColor`, `FlxAxes`, `FlxTextAlign` and friends are exactly the things scripts hold.

**Do not scan openfl or lime.** They hold roughly four hundred abstracts between them, nearly all
platform plumbing no script will ever hold as a value, and every generated wrapper is a `@:keep`
class in the binary. Name the handful that matter:

```haxe
static final TYPES:Array<String> = [
	// `sprite.blend = BlendMode.ADD` is how any additive light, glow or flash is written.
	'openfl.display.BlendMode',
];
```

A scan makes the set implicit -- what a script can reach depends on what happens to be declared under
the scanned packages. Print it behind a define so it can be checked:

```haxe
Context.info('${wrapped.length} abstract(s) exposed to scripts', Context.currentPos());
if (Context.defined('scripted_abstracts_list'))
	for (path in wrapped) Context.info('  $path', Context.currentPos());
```

### Step 4: shim what has no runtime form

`inline` and `inline extern` members are invisible to scripts (§2). In a library this is not a thing
you control, and it changes under you between versions: flixel 6.2 turned `FlxG.sound.playMusic`
into an `inline extern` overload, and every script calling it started failing with `Cannot call null`
against code that had not changed. Register a `callShims` entry per §5.

### OpenFL specifics

Add `--macro allowPackage('flash')` if your build touches the `flash` package aliases.

### A library not covered here

Heaps, Kha, or anything else follows the same four steps. Only three things are library-specific:
what to ignore, what to bridge, and which abstracts are worth wrapping. The package roots are the
easy part -- Heaps is `h2d`, `h3d` and `hxd` -- and the three lists are not. Derive them:

1. `--macro include('<root>', true, [])` with an empty ignore list and build. Each failure names a
   module that cannot be compiled as runtime code. Add it and repeat. Expect macro-only packages and
   integrations for libraries you do not ship.
2. Add **one** bridge for the base you most want scriptable and build. If it fails, read which type
   the generated override could not name: that base is out, and its subclasses probably are too.
3. Scan the library's package for abstracts, build with the listing define on, and read what came
   out. If it is hundreds, stop scanning and name the few you need.
4. Write a script that touches the API you care about and run it. `Cannot call null` means an
   `inline` member and needs a shim; `Unknown identifier` means a missing wrap or include.

Steps 1 and 2 are compile-time and converge in a few builds. Steps 3 and 4 are the ones that keep
turning up later, which is why the listing define and a script that exercises the API are worth
having from the start.

---

## 4. A custom interpreter

`Config.interpClass` is the whole installation:

```haxe
Config.interpClass = ModInterp;
```

`Module` and `Script` build their interpreter from it **at construction**, so set it before any
script is loaded. Changing it later leaves already-built scripts on the old one.

The worked case is letting scripts name the members of some owning object directly, so a script
writes `log('...')` and `round` rather than `battle.log('...')` and `battle.round`. That is
[`../examples/battle/game/ModInterp.hx`](../examples/battle/game/ModInterp.hx). A game engine does the same thing
for the state or scene that created a script.

**Three methods are involved and missing any one leaves a hole.**

| override | covers | what breaks without it |
| --- | --- | --- |
| `resolve` | reading a bare identifier | the whole feature |
| `setVar` | writing one | `round = 3` fails with `Unknown identifier: round`, so the field is readable but not writable from a script |
| `isResolvable` | the gate in front of `a.b` | the bare name works but `name.length` on it errors, because member access checks this and fails **without calling `resolve`** |

```haxe
@:access(hxscript.runtime.Interp)
class ModInterp extends Interp {
	override public function isResolvable(id:String):Bool {
		return super.isResolvable(id) || (context != null && fields.exists(id));
	}

	override public function resolve(id:String):Dynamic {
		if (imports.exists(id)) { ... }
		if (variables.exists(id))
			return resolveMirror(variables.get(id));
		if (context != null && fields.exists(id))
			return Reflect.getProperty(context, id);

		error(EUnknownVariable(id));
		return null;
	}

	override function setVar(name:String, v:Dynamic):Dynamic {
		if (!imports.exists(name) && !variables.exists(name) && context != null && fields.exists(name)) {
			Reflect.setProperty(context, name, v);
			return v;
		}
		return super.setVar(name, v);
	}
}
```

Two things to get right in the body:

**Hold the field names as a `Map`, not the `Array` `Type.getInstanceFields` returns.** This is
consulted for every identifier a script does not otherwise resolve *and* for the base of every
member access. A context object of any size makes that expensive: a game state with a few hundred
fields puts hundreds of string comparisons on a path that runs many times per frame.

**Stay additive.** Check `imports` and `variables` first so a script's own names still win, and defer
to `super` for everything you do not handle, so the strict undeclared-variable error still fires on a
typo. When the context is null the overrides collapse to base behaviour.

The example keeps the context static because it fights one battle at a time; a host with several
script owners at once keys it per interpreter instead, so each script resolves against its own.

---

## 5. Binding your API

There are five surfaces and they are not interchangeable. Picking the wrong one is the usual cause
of "the script cannot see it".

| surface | scope | holds | resolution order |
| --- | --- | --- | --- |
| `Config.globalImports` | every interpreter | **types**, by path | first |
| `Config.globalVariables` | every interpreter | values | after imports |
| `Environment.variables` | one world | values | after imports |
| `Script.variables` / `Module.variables` | one script | values | after imports |
| `Config.typeProxy` | every interpreter | a stand-in class for a type name | at resolution |

**Imports beat variables.** A global import of `File` shadows a variable named `File`, whatever you
set it to. If you bind a name like `File` to a guarded replacement, keep the real type out of the
global imports or the import wins and the guard is bypassed.

**A global import that cannot resolve throws out of the `Script` constructor, uncaught.** Global
imports are applied on every interpreter reset, before your handlers exist. Guard the registration:

```haxe
for (path in GLOBALS)
	if (TypeCollection.main.fromPath(path) != null)
		Config.globalImports.set(path, INormal);
```

**Anything not registered is still reachable** by explicit `import`, resolved against every type
compiled into the program. Global imports are a convenience, not a permission system.

### `callShims`: methods with no runtime form

The same problem as `inline` abstract members, one level up. An `inline extern` method is inlined at
every compiled call site and has no method to reflect on, so a script gets `Cannot call null`.
Register a real closure keyed `<fully.qualified.Owner>.<method>`; the interpreter walks the
receiver's superclasses looking for one before failing:

```haxe
Config.callShims.set('flixel.system.frontEnds.SoundFrontEnd.playMusic',
	function(o:Dynamic, args:Array<Dynamic>):Dynamic {
		FlxG.sound.music = FlxG.sound.load(args[0], args[1], args[2]);
		FlxG.sound.music.play();
		return FlxG.sound.music;
	});
```

Flixel 6.2 turning `FlxG.sound.playMusic` into this form is the case that motivated it: a method that
was ordinary in 6.1 silently stopped existing for every script.

### `blacklist`: keeping scripts out

Four match kinds, in `Config.blacklist`:

```haxe
Config.blacklist.get(ByType).push('sys.io.Process');      // one exact type
Config.blacklist.get(ByModule).push('sys.io.File');       // every type in a module
Config.blacklist.get(ByPackage(false)).push('sys.io');    // that package only
Config.blacklist.get(ByPackage(true)).push('sys');        // and its sub-packages
```

**Use packaged names.** Blacklisting a top-level type works, but the default root wildcard import
tries to resolve it on every interpreter reset and logs a warning each time.

**`import` is a wider surface than name resolution**, and goes through the type collection. If you
gate resolution yourself as well, mirror the rules on both or they will disagree.

**Never blacklist `hxscript` itself.** Inside a script, `Std`, `Type` and `Reflect` resolve to
`hxscript.proxy.*` and scripted abstracts run on `hxscript.types.*`, so blocking the package
blacklists the interpreter's own machinery and every script using `Std` dies with
`Unknown identifier: Std`. Block `hxscript.Config` by exact type instead.

### The rest of `Config`

| field | default | what it is for |
| --- | --- | --- |
| `interpClass` | `Interp` | the interpreter subclass to instantiate |
| `typedMode` | on (`-D hxscript_dynamic` flips it) | enforce declared types at runtime |
| `strictAccess` | `false` | enforce `private` on script-declared members. Only explicit `private` counts; unmarked members stay public, unlike Haxe, because existing scripts rely on it |
| `preprocessorValues` | host defines + `hxscript` | what `#if` in a script sees |
| `typeProxy` | `Std`, `Type`, `Reflect` (+ `Math` on hl) | swap a type name for a stand-in class |
| `globalVariables` | `null`/`true`/`false`, `Int`/`Float`/`Bool` tokens | values in every interpreter |

---

## Order of operations

Config is process-wide and read at construction, so sequence matters:

1. **Init macros**, at compile time: bridge generation, abstract metadata, and the includes that put
   both in the build.
2. **`Config.interpClass`**, before any `Script` or `Module` exists.
3. **`Config.globalImports`, `blacklist`, `callShims`, `strictAccess`**, before the first script is
   constructed. Global imports are applied on every interpreter reset.
4. **Build the `Environment`**, add modules, set world variables.
5. **`environment.start()`**.

[`../examples/battle/game/Mods.hx`](../examples/battle/game/Mods.hx) is this list as code, in order, and is short.

## Where to go next

- [embedding.md](embedding.md) is the ground floor: running scripts, exposing types, errors,
  bridges by hand.
- [parity.md](parity.md) is what scripts can and cannot do compared to real Haxe.
- [../example/](../examples/battle) is all of it, runnable.
