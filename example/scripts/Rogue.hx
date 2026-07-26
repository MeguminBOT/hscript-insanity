/**
 * A party member who applies the same `Poison` component the boss uses, to a target of its own
 * choosing. A component is just a behaviour with an owner, so nothing about it is specific to one
 * side of the fight.
 */
class Rogue extends Entity {
	var cooldown:Int = 0;

	/** Which side of the fight this creature joins; the host reads this to build the encounter. */
	public static var side:String = 'party';

	public function new() {
		super('rogue', 44, 8, true);
	}

	override public function takeTurn(battle:Battle) {
		var target = battle.pickFoe(this);
		if (target == null)
			return;

		if (cooldown > 0)
			cooldown--;

		var poisoned = false;
		for (c in target.components)
			if (c.name == 'poison')
				poisoned = true;

		if (cooldown == 0 && !poisoned) {
			cooldown = 3;
			battle.log('$name coats a blade and strikes ${target.name}');
			target.damage(battle, attack, this);

			if (target.alive)
				target.addComponent(new Poison(4, 3));
			return;
		}

		super.takeTurn(battle);
	}
}
