package game;

/**
 * The fight itself: who is in it, whose turn it is, and the log. Deterministic, so the demo prints
 * the same fight every run and a change in a script is visible as a change in the output.
 */
class Battle {
	/** Everyone in the fight, in turn order. */
	public var entities:Array<Entity> = [];

	/** The round currently being played, starting at 1. */
	public var round:Int = 0;

	/** Whether one side has been wiped out. */
	public var over(get, never):Bool;

	var seed:Int;

	inline function get_over():Bool {
		return living(true).length == 0 || living(false).length == 0;
	}

	/**
	 * @param seed Seeds the battle's random number generator.
	 */
	public function new(seed:Int) {
		this.seed = seed;
	}

	/**
	 * Adds an entity to the fight.
	 *
	 * @param e The entity to add.
	 * @return The same entity.
	 */
	public function add(e:Entity):Entity {
		entities.push(e);
		return e;
	}

	/**
	 * Writes a line to the battle log.
	 *
	 * @param message The line to write.
	 */
	public function log(message:String):Void {
		Output.write(message);
	}

	/**
	 * A deterministic pseudo-random number, so the demo is reproducible.
	 *
	 * @param max One past the largest value returned.
	 * @return A number in `0...max`.
	 */
	public function random(max:Int):Int {
		seed = (seed * 1103515 + 12345) & 0x3FFFFFFF;
		return (max <= 0) ? 0 : seed % max;
	}

	/**
	 * Everyone still standing on one side.
	 *
	 * @param friendly Which side to list.
	 * @return The living entities on that side.
	 */
	public function living(friendly:Bool):Array<Entity> {
		return [for (e in entities) if (e.alive && e.friendly == friendly) e];
	}

	/**
	 * Picks a random living opponent of `of`.
	 *
	 * @param of The entity looking for a target.
	 * @return A target, or null if that side is wiped out.
	 */
	public function pickFoe(of:Entity):Entity {
		var foes:Array<Entity> = living(!of.friendly);
		return (foes.length == 0) ? null : foes[random(foes.length)];
	}

	/**
	 * Picks the most wounded living ally of `of`, which is who a healer would help.
	 *
	 * @param of The entity looking for a target.
	 * @return An ally, or null if none is alive.
	 */
	public function pickWoundedAlly(of:Entity):Entity {
		var best:Entity = null;
		for (e in living(of.friendly))
			if (best == null || e.maxHealth - e.health > best.maxHealth - best.health)
				best = e;
		return best;
	}

	/**
	 * Plays the fight to a conclusion, or until the round limit.
	 *
	 * @param maxRounds How many rounds to allow before calling it a draw.
	 */
	public function run(maxRounds:Int):Void {
		// What ModInterp resolves a script's bare identifiers against, so `log(...)` and `round`
		// reach this battle. Cleared afterwards: a stale context would keep the finished fight
		// reachable and silently answer names that should have failed.
		ModInterp.context = this;

		while (!over && round < maxRounds) {
			round++;
			log('\n-- round $round --');

			for (e in entities.copy()) {
				if (!e.alive || over)
					continue;

				for (c in e.components.copy())
					c.onTurn(this);

				if (e.alive)
					e.takeTurn(this);
			}
		}

		log('\n== ' + (over ? (living(true).length > 0 ? 'the party wins' : 'the party falls') : 'a draw') + ' ==');

		ModInterp.context = null;
	}
}
