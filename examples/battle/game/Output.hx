package game;

/**
 * Where the battle log goes.
 *
 * The console when there is one, plus whatever listener the app attaches. That is the whole reason
 * this exists: the Lime/OpenFL build shows the same log in a window without the game code knowing
 * anything about windows.
 */
class Output {
	/** Called for every line, if the app set it. */
	public static var onLine:String->Void = null;

	/**
	 * Writes one line.
	 *
	 * @param line The line to write.
	 */
	public static function write(line:String):Void {
		#if sys
		Sys.println(line);
		#end

		if (onLine != null)
			onLine(line);
	}
}
