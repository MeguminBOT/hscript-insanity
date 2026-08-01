package game;

/**
 * A combatant. The host defines the rules (health, damage, death); scripts subclass this to define
 * what a particular creature *does*, by overriding `takeTurn` and the damage hooks.
 *
 * The method surface is deliberately small. A scripting bridge generates one override per inherited
 * method, so a wide base class is expensive to make scriptable.
 */
class Entity {
	/** Display name. */
	public var name:String;

	/** Health at full. */
	public var maxHealth:Int;

	/** Current health; at or below zero the entity is out of the fight. */
	public var health:Int;

	/** Damage dealt by a plain attack. */
	public var attack:Int;

	/** Which side of the fight this entity is on. */
	public var friendly:Bool;

	/** Behaviours attached to this entity, run by the battle each round. */
	public var components:Array<Component> = [];

	/** Whether the entity is still fighting. */
	public var alive(get, never):Bool;

	inline function get_alive():Bool {
		return health > 0;
	}

	/**
	 * @param name Display name.
	 * @param maxHealth Starting and maximum health.
	 * @param attack Damage dealt by a plain attack.
	 * @param friendly True for the player's side.
	 */
	public function new(name:String, maxHealth:Int, attack:Int, friendly:Bool = false) {
		this.name = name;
		this.maxHealth = maxHealth;
		this.health = maxHealth;
		this.attack = attack;
		this.friendly = friendly;
	}

	/**
	 * Attaches a behaviour to this entity.
	 *
	 * @param c The component to attach.
	 * @return The same component, so calls can be chained.
	 */
	public function addComponent(c:Component):Component {
		c.owner = this;
		components.push(c);
		c.onAttach();
		return c;
	}

	/**
	 * What this entity does on its turn. The default is to hit a random foe; scripts override this to
	 * give a creature its own behaviour.
	 *
	 * @param battle The fight in progress.
	 */
	public function takeTurn(battle:Battle):Void {
		var target:Entity = battle.pickFoe(this);
		if (target == null)
			return;

		battle.log('$name attacks ${target.name}');
		target.damage(battle, attack, this);
	}

	/**
	 * Applies damage, runs the damage hooks, and reports death.
	 *
	 * @param battle The fight in progress.
	 * @param amount How much damage to apply.
	 * @param source Who dealt it, if anyone.
	 */
	public function damage(battle:Battle, amount:Int, ?source:Entity):Void {
		if (!alive || amount <= 0)
			return;

		health -= amount;
		if (health < 0)
			health = 0;

		battle.log('  ${name} takes $amount (${health}/${maxHealth})');

		for (c in components)
			c.onDamaged(battle, amount, source);

		onDamaged(battle, amount, source);

		if (!alive) {
			onDeath(battle);
			battle.log('  ${name} is defeated');
		}
	}

	/**
	 * Restores health, never above the maximum.
	 *
	 * @param battle The fight in progress.
	 * @param amount How much to restore.
	 */
	public function heal(battle:Battle, amount:Int):Void {
		if (!alive)
			return;

		var before:Int = health;
		health = (health + amount > maxHealth) ? maxHealth : health + amount;

		if (health != before)
			battle.log('  ${name} recovers ${health - before} (${health}/${maxHealth})');
	}

	/**
	 * Called after this entity takes damage. Empty by default; scripts override it to react.
	 *
	 * @param battle The fight in progress.
	 * @param amount The damage taken.
	 * @param source Who dealt it, if anyone.
	 */
	public function onDamaged(battle:Battle, amount:Int, ?source:Entity):Void {}

	/**
	 * Called when this entity's health reaches zero. Empty by default.
	 *
	 * @param battle The fight in progress.
	 */
	public function onDeath(battle:Battle):Void {}
}
