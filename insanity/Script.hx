package insanity;

import insanity.backend.Exception;
import insanity.backend.Parser;
import insanity.backend.Interp;
import insanity.backend.Expr;

@:access(insanity.backend.Interp)
class Script {
	public var name:String;

	public var parser:Parser = new Parser();
	public var interp:Interp = null;
	public var program:Expr = null;

	public var failed:Bool = false;

	public var variables(get, never):Map<String, Dynamic>;

	inline function get_variables():Map<String, Dynamic> {
		return interp.variables;
	}

	public function new(string:String, name:String = 'hscript', ?environment:Environment):Void {
		parser.allowTypes = parser.allowJSON = parser.allowMetadata = true;
		interp = Type.createInstance(Config.interpClass, [environment, this]);
		interp.defineGlobals = true;

		this.name = name;

		parse(string);
	}

	public function parse(string:String):Expr {
		try {
			program = parser.parseScript(string, name);
		} catch (e:haxe.Exception) {
			onParsingError(e);
			program = null;
		}

		return program;
	}

	public function start(?expr:Expr):Any {
		try {
			if (program == null)
				throw 'Program is uninitialized';

			failed = false;
			setDefaults();

			if (interp.environment != null) {
				for (k => v in interp.environment.variables)
					if (!variables.exists(k))
						variables.set(k, v);
			}

			return interp.execute(program);
		} catch (e:haxe.Exception) {
			onProgramError(e);
			failed = true;
		}

		return null;
	}

	public function call(variable:String, ?args:Array<Dynamic>):Any {
		if (interp == null)
			throw 'Interpreter is uninitialized';

		var fun = (variables.get(variable) ?? interp.getLocal(variable));

		if (!Reflect.isFunction(fun)) {
			trace('$variable isn\'t a function');
			return null;
		}

		return Reflect.callMethod(interp, fun, args ?? []);
	}

	public function setDefaults():Void {
		interp.setDefaults();

		variables.set('this', this);
		variables.set('script', this);
		variables.set('interp', interp);
	}

	public dynamic function onParsingError(e:haxe.Exception):Void {
		trace('Failed to initialize script program!\n' + e.details());
	}

	public dynamic function onProgramError(e:haxe.Exception):Void {
		trace('Script program stopped unexpectedly!\n' + e.details());
	}
}
