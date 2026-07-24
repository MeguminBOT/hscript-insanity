package insanity;

class ImportModule extends Module {
	var attempted:Bool = false;

	public function new(string:String, origin:String = 'hscript'):Void {
		super(string, 'import', [], origin);
	}

	public override function parse(string:String) {
		attempted = false;
		decls.resize(0);

		try {
			decls = parser.parseModule(string, origin, true);
		} catch (e:haxe.Exception) {
			onParsingError(e);
		}

		return decls;
	}

	public override function start(?environment) {
		if (attempted)
			return; // dont reload / reexecute for all modules
		attempted = true;

		try {
			if (decls.length == 0)
				throw 'Module is uninitialized';

			starting = true;

			interp.environment = environment;
			interp.setDefaults();
			interp.executeModule(decls, path);

			starting = false;
			started = true;
		} catch (e:haxe.Exception) {
			onProgramError(e);
		}
	}
}
