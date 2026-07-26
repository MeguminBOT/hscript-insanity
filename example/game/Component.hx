package game;

/**
 * A behaviour attached to an entity: poison, regeneration, a counter-attack. Scripts subclass this
 * to add effects without touching the entity classes themselves.
 */
class Component {
	/** Display name, used in the battle log. */
	public var name:String;

	/** The entity this is attached to; set by `Entity.addComponent`. */
	public var owner:Entity;

	/**
	 * @param name Display name.
	 */
	public function new(name:String) {
		this.name = name;
	}

	/** Called once when the component is attached. */
	public function onAttach():Void {}

	/**
	 * Called each round, before the owner takes its turn.
	 *
	 * @param battle The fight in progress.
	 */
	public function onTurn(battle:Battle):Void {}

	/**
	 * Called when the owner takes damage.
	 *
	 * @param battle The fight in progress.
	 * @param amount The damage taken.
	 * @param source Who dealt it, if anyone.
	 */
	public function onDamaged(battle:Battle, amount:Int, ?source:Entity):Void {}
}
