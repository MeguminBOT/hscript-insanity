package blocks;

/**
 * The seven tetromino shapes, each as four rotation states.
 *
 * A state is eight numbers: four `x, y` pairs relative to the piece origin. Flat arrays rather than
 * nested ones, because this is read on every collision test and every draw.
 */
class Shapes {
	/** How many distinct pieces there are. */
	public static var COUNT:Int = 7;

	/** The glyph each piece draws with, indexed by kind. Index 0 is the empty cell. */
	public static var GLYPHS:Array<String> = [' ', 'I', 'O', 'T', 'S', 'Z', 'J', 'L'];

	/** `CELLS[kind][state]` is the eight-number layout. Kind is 1-based; 0 is empty. */
	public static var CELLS:Array<Array<Array<Int>>> = [
		[], // 0: empty
		[
			// I
			[0, 1, 1, 1, 2, 1, 3, 1],
			[2, 0, 2, 1, 2, 2, 2, 3],
			[0, 2, 1, 2, 2, 2, 3, 2],
			[1, 0, 1, 1, 1, 2, 1, 3]
		],
		[
			// O
			[1, 0, 2, 0, 1, 1, 2, 1],
			[1, 0, 2, 0, 1, 1, 2, 1],
			[1, 0, 2, 0, 1, 1, 2, 1],
			[1, 0, 2, 0, 1, 1, 2, 1]
		],
		[
			// T
			[1, 0, 0, 1, 1, 1, 2, 1],
			[1, 0, 1, 1, 2, 1, 1, 2],
			[0, 1, 1, 1, 2, 1, 1, 2],
			[1, 0, 0, 1, 1, 1, 1, 2]
		],
		[
			// S
			[1, 0, 2, 0, 0, 1, 1, 1],
			[1, 0, 1, 1, 2, 1, 2, 2],
			[1, 1, 2, 1, 0, 2, 1, 2],
			[0, 0, 0, 1, 1, 1, 1, 2]
		],
		[
			// Z
			[0, 0, 1, 0, 1, 1, 2, 1],
			[2, 0, 1, 1, 2, 1, 1, 2],
			[0, 1, 1, 1, 1, 2, 2, 2],
			[1, 0, 0, 1, 1, 1, 0, 2]
		],
		[
			// J
			[0, 0, 0, 1, 1, 1, 2, 1],
			[1, 0, 2, 0, 1, 1, 1, 2],
			[0, 1, 1, 1, 2, 1, 2, 2],
			[1, 0, 1, 1, 0, 2, 1, 2]
		],
		[
			// L
			[2, 0, 0, 1, 1, 1, 2, 1],
			[1, 0, 1, 1, 1, 2, 2, 2],
			[0, 1, 1, 1, 2, 1, 0, 2],
			[0, 0, 1, 0, 1, 1, 1, 2]
		]
	];

	/**
	 * The cell layout for one piece in one rotation.
	 *
	 * @param kind The piece, 1 to 7.
	 * @param state The rotation, 0 to 3.
	 * @return Eight numbers: four `x, y` pairs.
	 */
	public static function cells(kind:Int, state:Int):Array<Int> {
		if (kind < 1 || kind > COUNT)
			return [0, 0, 0, 0, 0, 0, 0, 0];

		return CELLS[kind][((state % 4) + 4) % 4];
	}
}
