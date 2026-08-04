/**
 * Stands in for the engine objects a script spends its frame talking to: vertex buffers, sprites,
 * anything owned by the host rather than declared in the script.
 */
class HostSink {
	public var total:Float = 0;

	/** A property with real accessors, the shape flixel uses for `text`, `color` and `cameras`. */
	public var tinted(get, set):Int;

	var realTint:Int = 0;

	function get_tinted():Int {
		return realTint;
	}

	function set_tinted(v:Int):Int {
		realTint = v * 2;
		return realTint;
	}

	public function new() {}

	/** A method call across the boundary, which is what a per-vertex push costs. */
	public function push(v:Float):Void {
		total += v;
	}
}
