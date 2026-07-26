/**
 * An enemy with an actual decision: finish off a wounded target if there is one, otherwise hit the
 * healthiest. Overriding `takeTurn` replaces the host's default behaviour entirely.
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

		battle.log('$name ${finishing ? "moves to finish" : "lunges at"} ${target.name}');
		target.damage(battle, attack, this);
	}
}
