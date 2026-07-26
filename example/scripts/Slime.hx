/**
 * A weak enemy that splits in two the first time it is hurt. The split is a plain constructor call
 * on the script's own class, and the new halves join the fight through the battle the host passed
 * in, so a script can change the shape of the fight without the host knowing about slimes.
 */
class Slime extends Entity {
	var canSplit:Bool;

	/** Which side of the fight this creature joins; the host reads this to build the encounter. */
	public static var side:String = 'enemy';

	public function new(size:Int = 2) {
		super('slime', 8 * size, 3 * size);
		canSplit = (size > 1);
	}

	override public function onDamaged(battle:Battle, amount:Int, ?source:Entity) {
		if (!canSplit || !alive)
			return;

		canSplit = false;
		battle.log('  the slime splits!');

		for (i in 0...2) {
			var half = new Slime(1);
			half.name = 'slimelet';
			battle.add(half);
		}
	}
}
