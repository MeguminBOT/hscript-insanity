/**
 * An enemy with an actual decision: finish off a wounded target if there is one, otherwise hit the
 * healthiest. Overriding `takeTurn` replaces the host's default behaviour entirely.
 *
 * Also the file to read for the two host-side extensions:
 *
 * - `log(...)` and `round` are the running `Battle`'s members, named without qualifying. That is
 *   `game/ModInterp.hx`, installed as `Config.interpClass`. `battle.log(...)` still works and is
 *   what the other scripts use.
 * - `Damage` is a NATIVE abstract (`game/Damage.hx`), with real operators and a real method. It has
 *   no `@:build` on it; `macros/AbstractsMacro.hx` applies the wrapper macro from outside. Without
 *   that, `hit * 1.25` here would fail with no operator and `critical()` would not exist.
 */
class Bandit extends Entity {
	/** Which side of the fight this creature joins; the host reads this to build the encounter. */
	public static var side:String = 'enemy';

	public function new() {
		super('bandit', 34, 8);
	}

	override public function takeTurn(battle:Battle) {
		var foes = battle.living(!friendly);
		if (foes.length == 0)
			return;

		var target = foes[0];
		var finishing = false;

		for (f in foes) {
			if (f.health <= attack) {
				target = f;
				finishing = true;
				break;
			}
			if (f.health > target.health)
				target = f;
		}

		// A native abstract, boxed by the annotation: `attack` is a plain Int and `Damage` declares
		// `from Int`. Its operators and methods are reachable from here only because the build macro
		// was applied to it.
		var hit:Damage = attack;
		if (finishing)
			hit = hit.critical();
		else if (round > 3)
			hit = hit * 1.25; // wears the party down as the fight drags on

		// `log` is the battle's, reached as a bare identifier through ModInterp. `describe` is the
		// abstract's own method, so this line is what fails outright if the macro was not applied.
		log('$name ${finishing ? "moves to finish" : "lunges at"} ${target.name} for ${hit.describe(attack)}');
		target.damage(battle, hit, this);
	}
}
