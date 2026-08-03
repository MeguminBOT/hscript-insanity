package hxscript.compile;

import hxscript.compile.CppiaInput;
import hxscript.compile.CppiaResult;
import hxscript.syntax.Expr;

/**
 * Compiles hxscript modules to cppia bytecode, which hxcpp loads and JIT-compiles at runtime.
 *
 * Optional in two senses: nothing here is built unless `-D hxscript_cppia` is set, and any module
 * the emitter cannot express is reported in `skipped` and left to the interpreter rather than
 * failing the batch.
 *
 * Loading the result needs a host built with `-D scriptable`, via `cpp.cppia.Module.fromData`.
 */
class Cppia {
	/** Whether this build can compile at all. */
	public static var available(get, never):Bool;

	static function get_available():Bool {
		#if hxscript_cppia
		return true;
		#else
		return false;
		#end
	}

	#if hxscript_cppia
	/**
	 * Dotted paths of every type a module declares.
	 *
	 * @param decls The module's declarations.
	 * @return The class, interface and enum paths it defines.
	 */
	static function declaredPaths(decls:Array<ModuleDecl>):Array<String> {
		var pack:String = '';
		var paths:Array<String> = [];

		for (decl in decls) {
			switch (decl.d) {
				case DPackage(path):
					pack = path.join('.');
				case DClass(c) | DInterface(c):
					paths.push(pack.length > 0 ? pack + '.' + c.name : c.name);
				case DEnum(en):
					paths.push(pack.length > 0 ? pack + '.' + en.name : en.name);
				case _:
			}
		}

		return paths;
	}

	/**
	 * Drops modules that name a class which is not going to be there.
	 *
	 * A reference to a refused class cannot link, and the loader rejects the WHOLE module over it, so
	 * one refusal would otherwise cost every class in the batch. Dropping the modules that lean on it
	 * keeps them interpreted together, which is where their dependency already is. Repeats until
	 * nothing more falls out, since dropping one module can strand another.
	 *
	 * Presence is keyed by the CLASSES on offer rather than by module name, since a reference names a
	 * class and a module may declare several under a name of its own.
	 *
	 * @param accepted The modules that compiled on their own.
	 * @param skipped Receives each module dropped here, with its reason.
	 * @param uses What each module referenced, by module name.
	 * @return The modules that can be emitted together.
	 */
	static function dropDanglingUsers(accepted:Array<CppiaInput>, skipped:Array<{name:String, reason:String}>,
			uses:Map<String, Array<String>>):Array<CppiaInput> {
		while (true) {
			var present:Map<String, Bool> = new Map();
			for (input in accepted)
				for (path in declaredPaths(input.decls))
					present.set(path, true);

			var survivors:Array<CppiaInput> = [];
			var dropped:Bool = false;

			for (input in accepted) {
				var missing:String = null;
				var referenced:Array<String> = uses.get(input.name);

				if (referenced != null) {
					for (path in referenced) {
						if (!present.exists(path)) {
							missing = path;
							break;
						}
					}
				}

				if (missing == null) {
					survivors.push(input);
				} else {
					skipped.push({name: input.name, reason: 'uses $missing, which is interpreted'});
					dropped = true;
				}
			}

			accepted = survivors;
			if (!dropped)
				return accepted;
		}
	}
	#end

	/**
	 * Compiles as many of the given modules as it can.
	 *
	 * All modules are declared before any is emitted, so they may refer to each other in any order.
	 * Emission runs against a throwaway writer first, since a module that failed part-way through
	 * would otherwise leave a corrupt record behind.
	 *
	 * @param inputs The modules to compile.
	 * @param ambient Types the host makes available without an import.
	 * @param external Scripted classes the host has elsewhere but that are NOT in this batch. A
	 *        module naming one is left interpreted: cppia resolves a class either inside the module
	 *        being loaded or as a host class, and a scripted class in another module is neither, so
	 *        the reference would fail to link and take the batch down with it.
	 * @param statics Bare names the host answers with a static of its own, each written
	 *        `name=owner.path::field`. Compiled code has no interpreter to have them injected into,
	 *        so it reaches them where they really live.
	 * @return The compiled module, and which inputs were compiled or skipped.
	 */
	public static function compile(inputs:Array<CppiaInput>, ?ambient:Array<String>, ?external:Array<String>, ?statics:Array<String>):CppiaResult {
		#if hxscript_cppia
		var skipped:Array<{name:String, reason:String}> = [];
		var accepted:Array<CppiaInput> = [];

		var uses:Map<String, Array<String>> = new Map();

		for (input in inputs) {
			var trial:CppiaEmitter = new CppiaEmitter();
			if (ambient != null)
				trial.ambient(ambient);
			if (external != null)
				trial.externals(external);
			if (statics != null)
				trial.ambientStatics(statics);
			for (other in inputs)
				trial.declare(other.decls, other.name);

			try {
				trial.emit(input.decls, input.name);
				trial.finish();
				uses.set(input.name, trial.references());
				accepted.push(input);
			} catch (e:CppiaUnsupported) {
				skipped.push({name: input.name, reason: e.reason});
			}
		}

		accepted = dropDanglingUsers(accepted, skipped, uses);

		if (accepted.length == 0)
			return {bytes: null, compiled: [], skipped: skipped};

		var emitter:CppiaEmitter = new CppiaEmitter();
		if (ambient != null)
			emitter.ambient(ambient);
		if (external != null)
			emitter.externals(external);
		if (statics != null)
			emitter.ambientStatics(statics);
		for (input in inputs)
			emitter.declare(input.decls, input.name);

		var compiled:Array<String> = [];
		for (input in accepted) {
			emitter.emit(input.decls, input.name);
			compiled.push(input.name);
		}

		return {bytes: emitter.finish(), compiled: compiled, skipped: skipped};
		#else
		var skipped:Array<{name:String, reason:String}> = [];
		for (input in inputs)
			skipped.push({name: input.name, reason: 'built without -D hxscript_cppia'});
		return {bytes: null, compiled: [], skipped: skipped};
		#end
	}
}
