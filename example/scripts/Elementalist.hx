import Combat;

/**
 * An enemy that cycles through elements, and the one place the module's types all meet: it switches
 * on an `Element` (with its parameters bound), builds hits with the `Damage` abstract, implements
 * the `Lootable` interface, and returns a `Loot` structure with its optional field left out.
 */
class Elementalist extends Entity implements Lootable {
	public static var side:String = 'enemy';

	var rotation:Array<Element> = [Element.Fire(6), Element.Ice(4), Element.Physical];
	var index:Int = 0;

	public function new() {
		super('elementalist', 32, 5);
	}

	override public function takeTurn(battle:Battle) {
		var target = battle.pickFoe(this);
		if (target == null)
			return;

		var element:Element = rotation[index % rotation.length];
		index++;

		// Enum parameters destructure exactly as they do in Haxe, and a guard narrows further.
		var hit:Damage = switch (element) {
			case Fire(intensity) if (intensity > 5): new Damage(attack).scaled(1.5) + intensity
					;
			case Fire(intensity): new Damage(attack) + intensity;
			case Ice(chill): new Damage(attack) + chill;
			case Physical: new Damage(attack);
		}

		battle.log('$name calls down ${label(element)} on ${target.name} for $hit');
		target.damage(battle, hit, this);
	}

	/**
	 * @param element The element to name.
	 * @return A readable name for the battle log.
	 */
	function label(element:Element):String {
		return switch (element) {
			case Fire(_): 'fire';
			case Ice(_): 'ice';
			case Physical: 'a plain blow';
		}
	}

	/** Satisfies `Lootable`. The `charm` field is optional, so leaving it out is still a `Loot`. */
	public function loot():Loot {
		return {gold: 25};
	}

	override public function onDeath(battle:Battle) {
		var dropped:Loot = loot();
		battle.log('  it drops ${dropped.gold} gold${dropped.charm == null ? "" : " and a " + dropped.charm}');
	}
}
