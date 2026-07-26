/**
 * Damage over time. A component, so it can be stuck on anything: the boss attaches it with its
 * sting, and the party's rogue could just as well apply it to an enemy.
 */
class Poison extends Component {
	var damage:Int;
	var rounds:Int;

	public function new(damage:Int, rounds:Int) {
		super('poison');
		this.damage = damage;
		this.rounds = rounds;
	}

	override public function onTurn(battle:Battle) {
		if (rounds <= 0)
			return;

		rounds--;
		battle.log('  ${owner.name} is poisoned');
		owner.damage(battle, damage);

		if (rounds == 0)
			owner.components.remove(this);
	}
}
