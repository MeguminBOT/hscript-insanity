package macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/**
 * The other way to make classes scriptable: generate the bridges instead of writing them.
 *
 * `bridges/ScriptedEntity.hx` is the manual form, and for one or two bases it is the clearer one.
 * Past that it is a folder of empty classes that all say the same thing, and every one of them has
 * to be kept in the build by hand. This generates the same classes from a list, and emits a
 * `Bridges.all` array that references them, which is what keeps them from being dropped: nothing
 * else refers to a bridge, since they are only ever built reflectively.
 *
 * The example uses both at once, so they can be compared: `Entity` is bridged by hand and
 * `Component` here. A real game would pick one, and past a handful of bases it should be this one.
 *
 * Run it from the build:
 *
 *     --macro macros.BridgeMacro.generate()
 */
class BridgeMacro {
	/** The classes scripts are allowed to extend. One line each. */
	static final BASES:Array<String> = ['game.Component'];

	static inline var PACK:String = 'bridges';

	/** Defines one bridge class per entry, plus the array that keeps them alive. */
	public static function generate():Void {
		var pos:Position = Context.currentPos();
		var pack:Array<String> = PACK.split('.');
		var refs:Array<Expr> = [];

		for (base in BASES) {
			var parts:Array<String> = base.split('.');
			var superPath:TypePath = {name: parts.pop(), pack: parts};
			var name:String = 'Scripted' + superPath.name;

			// A module of its own per bridge: defined as a sub-type of another module, a bridge could
			// only ever be named through that module.
			Context.defineModule('$PACK.$name', [
				{
					pack: pack,
					name: name,
					pos: pos,
					meta: [{name: ':keep', pos: pos}],
					kind: TDClass(superPath, [{pack: ['hxscript'], name: 'IScripted'}], false, false, false),
					fields: []
				}
			]);

			refs.push(macro $p{pack.concat([name])});
		}

		Context.defineModule('$PACK.Bridges', [
			{
				pack: pack,
				name: 'Bridges',
				pos: pos,
				meta: [{name: ':keep', pos: pos}],
				kind: TDClass(null, [], false, false, false),
				fields: [
					{
						name: 'all',
						access: [APublic, AStatic],
						pos: pos,
						doc: 'Every generated bridge. Referenced so the classes survive dead-code elimination.',
						kind: FVar(macro :Array<Class<Dynamic>>, {
							expr: EArrayDecl(refs),
							pos: pos
						})
					}
				]
			}
		]);
	}
}
#end
