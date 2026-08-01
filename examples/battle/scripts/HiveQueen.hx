/**
 * The boss. Shows the pieces working together: it builds components in its constructor, alternates
 * between attacks on a timer, and reacts to its own health.
 */
class HiveQueen extends Entity {
	var turn:Int = 0;
	var enraged:Bool = false;

	/** Which side of the fight this creature joins; the host reads this to build the encounter. */
	public static var side:String = 'enemy';

	public function new() {
		super('hive queen', 90, 9);
		addComponent(new Thorns(0.4));
	}

	override public function takeTurn(battle:Battle) {
		turn++;

		if (!enraged && health < maxHealth / 3) {
			enraged = true;
			attack += 5;
			battle.log('$name shrieks, and its carapace splits open');
		}

		if (turn % 3 == 0) {
			battle.log('$name calls in a drone');
			var drone = new Entity('drone', 12, 4);
			battle.add(drone);
			return;
		}

		var target = battle.pickFoe(this);
		if (target == null)
			return;

		if (turn % 2 == 0) {
			battle.log('$name stings ${target.name}');
			target.damage(battle, Std.int(attack / 2), this);
			target.addComponent(new Poison(3, 3));
		} else {
			super.takeTurn(battle);
		}
	}
}
