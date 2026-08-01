package blocks;

import blocks.Shapes;

/** The well: a grid of settled cells, and the rules for what fits in it. */
class Board {
	/** Width in cells. */
	public var cols:Int;

	/** Height in cells. */
	public var rows:Int;

	/** Row-major cells; 0 is empty, otherwise the piece kind that settled there. */
	public var cells:Array<Int>;

	/**
	 * @param cols Width in cells.
	 * @param rows Height in cells.
	 */
	public function new(cols:Int, rows:Int) {
		this.cols = cols;
		this.rows = rows;
		reset();
	}

	/** Empties the well. */
	public function reset():Void {
		cells = [for (i in 0...cols * rows) 0];
	}

	/**
	 * @param x Column.
	 * @param y Row.
	 * @return What occupies a cell, or 0 when it is empty or out of bounds.
	 */
	public function get(x:Int, y:Int):Int {
		if (x < 0 || x >= cols || y < 0 || y >= rows)
			return 0;

		return cells[y * cols + x];
	}

	/**
	 * Whether a piece placed here would overlap anything, including the walls and floor.
	 *
	 * @param kind The piece.
	 * @param state Its rotation.
	 * @param px Origin column.
	 * @param py Origin row.
	 * @return Whether the placement is blocked.
	 */
	public function collides(kind:Int, state:Int, px:Int, py:Int):Bool {
		var shape:Array<Int> = Shapes.cells(kind, state);
		var i:Int = 0;

		while (i < 8) {
			var x:Int = px + shape[i];
			var y:Int = py + shape[i + 1];

			if (x < 0 || x >= cols || y >= rows)
				return true;

			// Above the ceiling is legal: a piece spawns partly off-grid.
			if (y >= 0 && cells[y * cols + x] != 0)
				return true;

			i += 2;
		}

		return false;
	}

	/**
	 * Writes a piece into the well permanently.
	 *
	 * @param kind The piece.
	 * @param state Its rotation.
	 * @param px Origin column.
	 * @param py Origin row.
	 */
	public function settle(kind:Int, state:Int, px:Int, py:Int):Void {
		var shape:Array<Int> = Shapes.cells(kind, state);
		var i:Int = 0;

		while (i < 8) {
			var x:Int = px + shape[i];
			var y:Int = py + shape[i + 1];

			if (x >= 0 && x < cols && y >= 0 && y < rows)
				cells[y * cols + x] = kind;

			i += 2;
		}
	}

	/**
	 * Removes every full row, dropping what was above it.
	 *
	 * @return How many rows were cleared.
	 */
	public function clearLines():Int {
		var cleared:Int = 0;
		var y:Int = rows - 1;

		while (y >= 0) {
			var full:Bool = true;

			for (x in 0...cols) {
				if (cells[y * cols + x] == 0) {
					full = false;
					break;
				}
			}

			if (!full) {
				y--;
				continue;
			}

			// Pull everything above down one row, then blank the top. `y` is not decremented, so the
			// row that just moved into it is tested next.
			var row:Int = y;
			while (row > 0) {
				for (x in 0...cols)
					cells[row * cols + x] = cells[(row - 1) * cols + x];
				row--;
			}

			for (x in 0...cols)
				cells[x] = 0;

			cleared++;
		}

		return cleared;
	}
}
