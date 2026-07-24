package insanity.backend.types;

using insanity.backend.TypeCollection;

/** Helpers for resolving and constructing the runtime representation of abstracts and enum abstracts. */
class AbstractTools {
	/**
	 * Resolves an abstract by path to its generated `InsanityAbstract_*` implementation class.
	 *
	 * @param path The abstract's path.
	 * @return The implementation class, or null if it isn't a (known) abstract.
	 */
	public static function resolve(path:String):Class<InsanityAbstract> {
		var t = (TypeCollection.main.fromPath(path) ?? TypeCollection.main.fromCompilePath(path));

		if (t != null) {
			var a = Type.resolveClass(t[0].pack.join('.') + (t[0].pack.length > 0 ? '.' : '') + 'InsanityAbstract_'
				+ StringTools.replace(t[0].compilePath(), '.', '_'));

			if (a != null)
				return cast a;
		}

		return null;
	}

	/**
	 * Names the type of a value, reporting an enum-abstract by its underlying implementation name.
	 *
	 * @param v The value to name.
	 * @return The type name, or `'unknown'` if it can't be determined.
	 */
	public static function resolveName(v:Dynamic):String {
		var vv:Dynamic = v;
		switch (Type.typeof(v)) {
			case TInt:
				return 'Int';
			case TFloat:
				return 'Float';
			case TBool:
				return 'Bool';
			case TObject:
				if (v is Enum)
					return Type.getEnumName(v);
			case TClass(c):
				vv = c;
			case TEnum(e):
				return Type.getEnumName(e);
			default:
				return 'unknown';
		}

		if (vv is Class) {
			if (Type.getSuperClass(vv) == InsanityAbstract) {
				return (vv.impl ?? 'unknown');
			} else {
				return Type.getClassName(vv);
			}
		}

		return 'unknown';
	}

	/**
	 * Lists an enum abstract's constructor names.
	 *
	 * @param a The enum-abstract implementation class.
	 * @return The constructor names.
	 * @throws String If `a` is not an enum abstract.
	 */
	public static function getEnumConstructs(a:Class<InsanityAbstract>):Array<String> {
		var a:Dynamic = a;

		if (a.isEnum)
			return a._enumConstructors.copy();

		throw '${a?.impl ?? a} is not an enum abstract';
		return null;
	}

	/**
	 * Constructs an enum-abstract value by constructor name.
	 *
	 * @param a The enum-abstract implementation class.
	 * @param n The constructor name.
	 * @return The wrapped value.
	 * @throws String If `a` is not an enum abstract.
	 */
	public static function createEnum(a:Class<InsanityAbstract>, n:String):InsanityAbstract {
		var a:Dynamic = a;

		if (a.isEnum)
			return Type.createInstance(a, [a._enumValues[a._enumMap.get(n) ?? -1]]);

		throw '${a?.impl ?? a} is not an enum abstract';
		return null;
	}

	/**
	 * Constructs an enum-abstract value by constructor index.
	 *
	 * @param a The enum-abstract implementation class.
	 * @param i The constructor index.
	 * @return The wrapped value.
	 * @throws String If `a` is not an enum abstract.
	 */
	public static function createEnumIndex(a:Class<InsanityAbstract>, i:Int):InsanityAbstract {
		var a:Dynamic = a;

		if (a.isEnum)
			return Type.createInstance(a, [a._enumValues[i]]);

		throw '${a?.impl ?? a} is not an enum abstract';
		return null;
	}

	/**
	 * Tests whether a value is a wrapped abstract.
	 *
	 * @param o The value.
	 * @return True if `o` is an `InsanityAbstract`.
	 */
	public static function isAbstract(o:Dynamic):Bool {
		return (o is InsanityAbstract);
	}
}

/**
 * Runtime wrapper standing in for an abstract value at interpretation time. It boxes the underlying
 * value; the per-abstract accessors and conversions are filled in by the abstract-building macro.
 */
class InsanityAbstract {
	/** The wrapped underlying value (macro-overridden per abstract). */
	var value(get, set):Dynamic;

	/** The boxed underlying value. */
	var __a(default, null):Dynamic;

	/**
	 * Wraps an underlying value.
	 *
	 * @param v The value to box.
	 */
	public function new(v:Dynamic) {
		value = v;
	}

	// The get/set below are placeholders; the abstract-building macro replaces them per abstract.

	/** @return The boxed value. */
	function get_value():Dynamic {
		return __a;
	}

	/**
	 * @param v The value to box.
	 * @return The boxed value.
	 */
	function set_value(v:Dynamic):Dynamic {
		return __a = v;
	}

	/**
	 * Converts this abstract to one of its `to` target types (macro-overridden per abstract).
	 *
	 * @param t The target type name.
	 * @return The converted value, or null in the base implementation.
	 */
	public function resolveTo(t:String):Dynamic {
		return null;
	}
}
