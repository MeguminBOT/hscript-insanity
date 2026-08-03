/**
 * Stands in for the engine objects a script spends its frame talking to: vertex buffers, sprites,
 * anything owned by the host rather than declared in the script.
 */
class HostSink {
	public var total:Float = 0;

	public function new() {}

	/** A method call across the boundary, which is what a per-vertex push costs. */
	public function push(v:Float):Void {
		total += v;
	}
}
