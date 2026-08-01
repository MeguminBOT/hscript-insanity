/**
 * A party member, to show a script is not only for enemies. Heals whoever is worst off, and only
 * swings when nobody needs help.
 */
class Cleric extends Entity {
	/** Which side of the fight this creature joins; the host reads this to build the encounter. */
	public static var side:String = 'party';

	public function new() {
		super('cleric', 52, 6, true);
	}

	override public function takeTurn(battle:Battle) {
		var ally = battle.pickWoundedAlly(this);

		if (ally != null && ally.health < ally.maxHealth * 0.6) {
			battle.log('$name mends ${ally.name}');
			ally.heal(battle, 18);
			return;
		}

		super.takeTurn(battle);
	}
}
