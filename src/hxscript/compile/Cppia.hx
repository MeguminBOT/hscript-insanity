package hxscript.compile;

import hxscript.compile.CppiaInput;
import hxscript.compile.CppiaResult;

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

	/**
	 * Compiles as many of the given modules as it can.
	 *
	 * All modules are declared before any is emitted, so they may refer to each other in any order.
	 * Emission runs against a throwaway writer first, since a module that failed part-way through
	 * would otherwise leave a corrupt record behind.
	 *
	 * @param inputs The modules to compile.
	 * @return The compiled module, and which inputs were compiled or skipped.
	 */
	public static function compile(inputs:Array<CppiaInput>, ?ambient:Array<String>):CppiaResult {
		#if hxscript_cppia
		var skipped:Array<{name:String, reason:String}> = [];
		var accepted:Array<CppiaInput> = [];

		for (input in inputs) {
			var trial:CppiaEmitter = new CppiaEmitter();
			if (ambient != null)
				trial.ambient(ambient);
			for (other in inputs)
				trial.declare(other.decls, other.name);

			try {
				trial.emit(input.decls, input.name);
				trial.finish();
				accepted.push(input);
			} catch (e:CppiaUnsupported) {
				skipped.push({name: input.name, reason: e.reason});
			}
		}

		if (accepted.length == 0)
			return {bytes: null, compiled: [], skipped: skipped};

		var emitter:CppiaEmitter = new CppiaEmitter();
		if (ambient != null)
			emitter.ambient(ambient);
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
