package host;

/**
 * The base a scripted program extends. Everything a game needs from the host is a parameter here;
 * everything else the game is, the script decides.
 *
 * The workbench instantiates whichever scripted subclass you ask it to run, then drives this
 * lifecycle: `start` once, then `key` and `step` and `draw` per frame until `done` is true.
 *
 * Subclassing this from a script is what `bridges/ScriptedApp.hx` makes possible.
 */
class App {
	/** Shown by `list`, so the workbench can describe a program without running it. */
	public var title:String = 'untitled';

	/** How wide a screen this program wants. */
	public var width:Int = 60;

	/** How tall a screen this program wants. */
	public var height:Int = 24;

	/** Set true to end the run and return to the shell. */
	public var done:Bool = false;

	public function new() {}

	/**
	 * Called once before the first frame.
	 *
	 * @param screen The screen this run will draw into.
	 */
	public function start(screen:Screen):Void {}

	/**
	 * Called with each keypress, before the step it belongs to.
	 *
	 * @param key The key, as a `Keys` constant.
	 */
	public function key(key:Int):Void {}

	/**
	 * Advances the program by one frame.
	 *
	 * @param elapsed Seconds since the previous step.
	 */
	public function step(elapsed:Float):Void {}

	/**
	 * Draws one frame. The screen is already cleared.
	 *
	 * @param screen The screen to draw into.
	 */
	public function draw(screen:Screen):Void {}

	/** Called once after the loop ends, whether the program finished or was quit. */
	public function stop():Void {}
}
