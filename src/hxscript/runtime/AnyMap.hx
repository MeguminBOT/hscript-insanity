package hxscript.runtime;

import haxe.Constraints.IMap;
import haxe.ds.EnumValueMap;
import haxe.ds.IntMap;
import haxe.ds.ObjectMap;
import haxe.ds.StringMap;
import Reflect as HaxeReflect;

/**
 * The map a bare `new Map()` produces, where the key type was never written.
 *
 * `Map` is a multi-type abstract with no runtime class of its own: the compiler reads the key type
 * and constructs a `StringMap`, `IntMap`, `EnumValueMap` or `ObjectMap` in its place. A script that
 * writes the key type gets that same choice made for it while parsing. One that does not has nothing
 * to decide from until a key actually arrives, so this holds the decision open, picks on the first
 * write, and is a plain delegate from then on.
 *
 * Every read before that first write answers as an empty map, which is what it is.
 *
 * The delegate is the real map, so a script may hand one of these to host code typed against
 * `Map` or `IMap` and it behaves; only `Std.isOfType(m, StringMap)` can tell the difference.
 */
class AnyMap implements IMap<Dynamic, Dynamic> {
	var inner:IMap<Dynamic, Dynamic>;

	public function new() {}

	/**
	 * Settles which concrete map backs this one, from the first key written.
	 *
	 * The order matches the compiler's: `String` and `Int` win outright, an enum value takes the
	 * structural map that compares its parameters, and anything else is matched by identity.
	 */
	function pick(key:Dynamic):IMap<Dynamic, Dynamic> {
		if (inner == null) {
			if (key is String)
				inner = cast new StringMap<Dynamic>();
			else if (key is Int)
				inner = cast new IntMap<Dynamic>();
			else if (HaxeReflect.isEnumValue(key))
				inner = cast new EnumValueMap<Dynamic, Dynamic>();
			else
				inner = cast new ObjectMap<Dynamic, Dynamic>();
		}

		return inner;
	}

	public function get(k:Dynamic):Dynamic {
		return inner == null ? null : inner.get(k);
	}

	public function set(k:Dynamic, v:Dynamic):Void {
		pick(k).set(k, v);
	}

	public function exists(k:Dynamic):Bool {
		return inner == null ? false : inner.exists(k);
	}

	public function remove(k:Dynamic):Bool {
		return inner == null ? false : inner.remove(k);
	}

	public function keys():Iterator<Dynamic> {
		return inner == null ? [].iterator() : inner.keys();
	}

	public function iterator():Iterator<Dynamic> {
		return inner == null ? [].iterator() : inner.iterator();
	}

	public function keyValueIterator():KeyValueIterator<Dynamic, Dynamic> {
		return inner == null ? new haxe.iterators.MapKeyValueIterator(this) : inner.keyValueIterator();
	}

	/**
	 * Copies into a map of the same concrete kind, so the copy keeps the original's key semantics
	 * rather than re-deciding them. A copy taken before the first write is still undecided.
	 */
	public function copy():IMap<Dynamic, Dynamic> {
		var out:AnyMap = new AnyMap();
		if (inner != null)
			out.inner = inner.copy();
		return out;
	}

	public function clear():Void {
		if (inner != null)
			inner.clear();
	}

	public function toString():String {
		return inner == null ? '{}' : inner.toString();
	}
}
