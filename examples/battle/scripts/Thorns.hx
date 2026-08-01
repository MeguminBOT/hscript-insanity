/** Reflects part of every hit back at the attacker. */
class Thorns extends Component {
	var share:Float;

	public function new(share:Float) {
		super('thorns');
		this.share = share;
	}

	override public function onDamaged(battle:Battle, amount:Int, ?source:Entity) {
		if (source == null || !source.alive)
			return;

		var back:Int = Math.round(amount * share);
		if (back <= 0)
			return;

		battle.log('  ${owner.name} reflects $back onto ${source.name}');
		source.damage(battle, back, owner);
	}
}
