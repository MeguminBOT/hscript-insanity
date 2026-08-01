/**
 * One module, several types, the way a Haxe module works: the enum, the typedef, the abstract and
 * the interface below are all reachable from every other script in the world, without an import,
 * because they are loaded into the same environment.
 */

/** What a hit is made of. Enums carry parameters and destructure in `switch`, as in Haxe. */
enum Element {
	Physical;
	Fire(intensity:Int);
	Ice(chill:Int);
}

/**
 * What an enemy leaves behind. A structural typedef: any value with these fields satisfies it, and
 * `charm` is optional, so `{gold: 5}` is a valid `Loot`.
 */
typedef Loot = {
	var gold:Int;
	@:optional var charm:String;
}

/** Something that can be looted. A scripted interface, implemented by scripted classes. */
interface Lootable {
	public function loot():Loot;
}

/**
 * A damage amount. An abstract over `Int`, so it is an `Int` at runtime with no wrapper cost in the
 * host, but carries its own operators and helpers here.
 */
abstract Damage(Int) from Int to Int {
	public function new(v:Int) {
		this = v;
	}

	/** Combines two damage amounts. */
	@:op(A + B) public function add(rhs:Damage):Damage {
		return new Damage(this + rhs);
	}

	/** Scales a hit, for resistances and weaknesses. */
	public function scaled(factor:Float):Damage {
		return new Damage(Math.round(this * factor));
	}

	/** The amount, so a damage value traces as a number rather than as a box. */
	public function toString():String {
		return '' + this;
	}
}
