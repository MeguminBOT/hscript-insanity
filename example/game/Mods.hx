package game;

import insanity.Config;
import insanity.Environment;
import insanity.Module;
import insanity.syntax.Expr.ImportMode;
import insanity.types.ScriptedClass;
import insanity.types.TypeCollection;
import game.Entity;
import sys.FileSystem;
import sys.io.File;

/**
 * The whole embedding layer: everything the host has to do to make scripts work. Four steps, and
 * `setup` runs them once.
 *
 * See [docs/embedding.md](../../docs/embedding.md) for what each one is doing and why.
 */
class Mods {
	/** The world every loaded script and type lives in. */
	public static var world:Environment;

	/** Names scripts can use without importing them. */
	static final GLOBALS:Array<String> = ['game.Entity', 'game.Component', 'game.Battle'];

	/**
	 * Loads every script in a folder and starts them as one world.
	 *
	 * @param dir The folder to read `.hx` files from.
	 */
	public static function setup(dir:String):Void {
		// 1. Let scripts name the game's types without importing them. Anything else compiled into
		//    the program is still reachable with an explicit `import`.
		//    A global import that cannot resolve throws out of the Script constructor uncaught, so
		//    only register what is actually in this build.
		for (path in GLOBALS)
			if (TypeCollection.main.fromPath(path) != null)
				Config.globalImports.set(path, INormal);

		// 2. Keep scripts away from the file system.
		//    Note these are packaged names. Blacklisting a top-level type (`Sys`) also works, but the
		//    default root wildcard import tries to resolve it on every interpreter reset and logs a
		//    warning each time, so block those by module or package instead.
		var blocked:Array<String> = Config.blacklist.get(ByType);
		for (name in ['sys.io.File', 'sys.io.Process', 'sys.FileSystem'])
			blocked.push(name);

		// 3. Build the world out of every script in the folder.
		world = new Environment();

		for (file in FileSystem.readDirectory(dir)) {
			if (!StringTools.endsWith(file, '.hx'))
				continue;

			var path:String = '$dir/$file';
			var name:String = file.substr(0, file.length - 3);
			world.addModule(new Module(File.getContent(path), name, [], path));
		}

		// 4. Give scripts the handful of values they cannot reach through their own objects.
		world.variables.set('roll', function(sides:Int):Int return 1 + Std.random(sides));

		world.start();
	}

	/**
	 * Every script-declared class in the world, by name, in a stable order.
	 *
	 * @return The loaded scripted classes.
	 */
	public static function classes():Array<ScriptedClass> {
		var found:Map<String, ScriptedClass> = [];
		for (module in world.modules)
			for (name => type in module.types)
				if (type is ScriptedClass)
					found.set(name, cast type);

		var names:Array<String> = [for (name in found.keys()) name];
		names.sort(Reflect.compare);
		return [for (name in names) found.get(name)];
	}

	/**
	 * Whether a scripted class descends from a native one.
	 *
	 * @param cls The scripted class.
	 * @param base The native base to look for.
	 * @return True if `base` is somewhere up the chain.
	 */
	public static function descendsFrom(cls:ScriptedClass, base:Class<Dynamic>):Bool {
		var native:Dynamic = cls.instanceClass;
		while (native != null) {
			if (native == base)
				return true;
			native = Type.getSuperClass(native);
		}
		return false;
	}

	/**
	 * Builds one of every entity a script declared for the given side.
	 *
	 * The host never names a script here: it asks the world which classes are entities and which
	 * side they declared themselves on, so dropping a new file into the scripts folder puts a new
	 * creature in the fight without touching any of this.
	 *
	 * @param side The value a script's `static var side` has to match.
	 * @return The newly built entities.
	 */
	public static function roster(side:String):Array<Entity> {
		var out:Array<Entity> = [];

		for (cls in classes()) {
			if (!descendsFrom(cls, Entity) || cls.reflectGetField('side') != side)
				continue;

			var made:Dynamic = cls.typeCreateInstance([]);
			if (made is Entity)
				out.push(made);
		}

		return out;
	}
}
