package blocks;

/** Points, level and the gravity curve that follows from them. */
class Scoring {
	/** Points per simultaneous line clear, indexed by count. */
	public static var LINE_POINTS:Array<Int> = [0, 100, 300, 500, 800];

	/** Running score. */
	public var score:Int = 0;

	/** Lines cleared so far. */
	public var lines:Int = 0;

	/** Current level; gravity follows from it. */
	public var level:Int = 1;

	public function new() {}

	/**
	 * Records a placement.
	 *
	 * @param cleared How many rows went at once.
	 * @param softDropped How many rows the player pushed the piece down by hand.
	 */
	public function place(cleared:Int, softDropped:Int):Void {
		score += softDropped;

		if (cleared <= 0)
			return;

		var index:Int = cleared > 4 ? 4 : cleared;
		score += LINE_POINTS[index] * level;
		lines += cleared;
		level = 1 + Std.int(lines / 10);
	}

	/** @return Seconds between automatic drops at the current level. */
	public function gravity():Float {
		var step:Float = 0.8 - (level - 1) * 0.07;
		return step < 0.05 ? 0.05 : step;
	}
}
