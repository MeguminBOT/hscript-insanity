package hxscript.macro;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
#end

/**
 * Keeps the standard-library types scripts reach by reflection from being eliminated.
 *
 * Dead code elimination decides what to strip from a build by what the *compiled* code references.
 * A script references nothing at compile time, so under hxcpp's default `-dce std` a member no
 * compiled call site happens to use is removed, and a script reaching it gets a null field. The
 * failure looks exactly like a defect in this library and is not: it is a property of how the host
 * was built, and it took a page of documentation to stop people reporting it as a bug.
 *
 * `IntIterator` is the one that catches everyone. `for (i in 0...n)` compiles to a direct loop and
 * every call site inlines `hasNext`/`next`, so nothing in a finished program references them
 * statically and DCE takes them -- leaving the most ordinary loop in the language broken in scripts
 * while working perfectly in the host beside them.
 *
 * This runs from `extraParams.hxml`, so it applies to anyone who adds the library and needs no
 * setting. It marks whole types rather than individual members on purpose: which member a script
 * will want is not knowable, and the cost of keeping a handful of standard types is small next to
 * the cost of the failure.
 *
 * `-D hxscript_no_keep` turns it off, for a host minimising binary size that would rather choose for
 * itself. `-dce no` makes it moot, and is what the benchmark suites use.
 */
class KeepMacro {
	/**
	 * The types kept, chosen by what scripts actually reach for.
	 *
	 * Neighbours worth adding for a host whose scripts use them, none of which are kept by default
	 * because each costs binary size for a program that does not: `haxe.ds.IntMap`,
	 * `haxe.ds.ObjectMap`, `haxe.ds.EnumValueMap`, `StringTools`, `haxe.Json`, `haxe.Timer`.
	 */
	public static var types:Array<String> = [
		'IntIterator',
		'Reflect',
		'Type',
		'haxe.ds.StringMap',
		'EReg',
		'List',
		'haxe.ds.List',
		'Date',
		'Sys'
	];

	/**
	 * Pulls every type in `types` into the build and marks it, along with its fields, as kept.
	 *
	 * Both halves are needed, and they answer different failures. Keeping saves a type already in
	 * the build from being stripped, and shows up as `Cannot call null` when it is missing. Including
	 * puts a type in the build that nothing referenced at all, and shows up as
	 * `Unknown identifier` -- `@:keep` cannot help there, because there is nothing yet to keep.
	 *
	 * Fields as well as types, because keeping a class whose methods were eliminated does not help:
	 * what a script resolves is the member.
	 */
	public static function run():Void {
		#if macro
		if (Context.defined('hxscript_no_keep'))
			return;

		for (path in types) {
			// Not recursive: these are exact type paths, and a recursive filter on a name like `Type`
			// would sweep in everything that merely starts with it.
			Compiler.addGlobalMetadata(path, '@:keep', false, true, true);
		}

		// Typing a path is what puts it in the build. Deferred, because a type asked for too early is
		// resolved against an incomplete class path; and guarded, because this list is shared by every
		// target and not every target has all of it -- `Sys` does not exist on a browser build, and
		// asking for it there should cost nothing rather than fail the compilation.
		Context.onAfterInitMacros(function():Void {
			for (path in types) {
				try {
					Context.getType(path);
				} catch (e:Dynamic) {}
			}
		});
		#end
	}
}
