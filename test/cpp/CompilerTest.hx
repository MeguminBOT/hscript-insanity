import hxscript.Environment;
import hxscript.Module;
import hxscript.compile.Compiler;
import hxscript.types.ScriptedClass;

/** Exercises the one-call path: a world in, compiled classes running, across a reload. */
class CompilerTest {
	static var A:String = 'package p;
class Beast {
	public var hp:Int = 0;
	public function new(hp:Int) { this.hp = hp; }
	public function hit(n:Int):Int { hp -= n; return hp; }
}
';
	static var B:String = 'package p;
import p.Beast;
class Fight {
	public static function run():Int {
		var b:Beast = new Beast(30);
		var i:Int = 0;
		while (i < 4) { b.hit(5); i += 1; }
		return b.hp;
	}
}
';

	static function world():Environment {
		var env = new Environment();
		env.addModule(new Module(A, 'Beast', ['p'], 'a'));
		env.addModule(new Module(B, 'Fight', ['p'], 'b'));
		for (m in env.modules) m.init(env);
		for (m in env.modules) m.start(env);
		for (m in env.modules) m.startTypes(env);
		return env;
	}

	static function check(label:String, env:Environment):Void {
		var cls:ScriptedClass = cast env.resolve('p.Fight');
		var got:Dynamic = Reflect.callMethod(null, cls.reflectGetField('run'), []);
		Sys.println('  $label -> run() = $got, substituting = ${env.substituting}');
	}

	public static function run():Void {
		Sys.println('available: ' + Compiler.available);

		var env1 = world();
		Sys.println('interpreted first:');
		check('before', env1);

		var r1 = Compiler.compile(env1);
		Sys.println('compile: ${r1.compiled.length} classes, ${r1.skipped.length} skipped, '
			+ 'substituting=${r1.substituting}, ${Math.round(r1.ms * 100) / 100}ms');
		for (s in r1.skipped) Sys.println('  skipped ${s.name}: ${s.reason}');
		check('after', env1);
		Sys.println('  isCompiled(p.Beast) = ' + Compiler.isCompiled('p.Beast'));

		// A reload: a brand new world over the same sources. Nothing recompiles, but the new world
		// still has to end up running the compiled classes.
		Sys.println('after a reload:');
		var env2 = world();
		var r2 = Compiler.compile(env2);
		Sys.println('compile: ${r2.compiled.length} classes, ${Math.round(r2.ms * 100) / 100}ms (0 means nothing recompiled)');
		check('reloaded', env2);
	}

	static function main():Void {
		run();
		TestCase.exit();
	}
}
