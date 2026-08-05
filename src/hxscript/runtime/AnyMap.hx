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
	/** The real map, chosen from the first key written and null until then. */
	var inner:IMap<Dynamic, Dynamic>;

	public function new() {}

	/**
	 * Settles which concrete map backs this one, from the first key written.
	 *
	 * The order matches the compiler's: `String` and `Int` win outright, an enum value takes the
	 * structural map that compares its parameters, and anything else is matched by identity.
	 *
	 * @param key The key being written.
	 * @return The backing map.
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

	/**
	 * @param k The key.
	 * @return Its value, or null when the key is absent or nothing has been written yet.
	 */
	public function get(k:Dynamic):Dynamic {
		return inner == null ? null : inner.get(k);
	}

	/**
	 * Writes a value, settling which concrete map backs this one if it is the first write.
	 *
	 * @param k The key.
	 * @param v The value.
	 */
	public function set(k:Dynamic, v:Dynamic):Void {
		pick(k).set(k, v);
	}

	/**
	 * @param k The key.
	 * @return Whether it has a value.
	 */
	public function exists(k:Dynamic):Bool {
		return inner == null ? false : inner.exists(k);
	}

	/**
	 * @param k The key to drop.
	 * @return Whether it was there.
	 */
	public function remove(k:Dynamic):Bool {
		return inner == null ? false : inner.remove(k);
	}

	/** @return Every key, or an empty iterator before the first write. */
	public function keys():Iterator<Dynamic> {
		return inner == null ? [].iterator() : inner.keys();
	}

	/** @return Every value, or an empty iterator before the first write. */
	public function iterator():Iterator<Dynamic> {
		return inner == null ? [].iterator() : inner.iterator();
	}

	/** @return Every key and value together, which is what `for (k => v in m)` walks. */
	public function keyValueIterator():KeyValueIterator<Dynamic, Dynamic> {
		return inner == null ? new haxe.iterators.MapKeyValueIterator(this) : inner.keyValueIterator();
	}

	/**
	 * Copies into a map of the same concrete kind, so the copy keeps the original's key semantics
	 * rather than re-deciding them. A copy taken before the first write is still undecided.
	 */
	/** @return A map of the same kind holding the same entries. */
	public function copy():IMap<Dynamic, Dynamic> {
		var out:AnyMap = new AnyMap();
		if (inner != null)
			out.inner = inner.copy();
		return out;
	}

	/** Empties the map, and forgets which kind it had settled on. */
	public function clear():Void {
		if (inner != null)
			inner.clear();
	}

	/** @return The delegate's own rendering, or `{}` before the first write. */
	public function toString():String {
		return inner == null ? '{}' : inner.toString();
	}
}
