package hxscript.macro;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.ExprTools;
import haxe.macro.TypedExprTools;
#end
import hxscript.types.TypeCollection;

/**
 * Compile-time builder of the global `TypeCollection`. After typing, it records a `TypeInfo` for
 * every type in the build (serialized into this class's metadata), then emits runtime code that
 * deserializes it into an indexed `TypeMap`. This is what lets scripts name any compiled type
 * without extra reflection cost.
 */
class TypeCollectionMacro {
	/** This macro class's own fully-qualified name (used to stash the serialized type table). */
	static var _name:String = 'hxscript.macro.TypeCollectionMacro';

	/**
	 * Records every build type's info at compile time and emits code to rebuild the indexed map at runtime.
	 *
	 * @return An expression evaluating to the populated `TypeMap`.
	 */
	public static macro function build() {
		Context.onAfterTyping(function(types) {
			var self = TypeTools.getClass(Context.getType(_name));
			if (self.meta.has('typed'))
				return;

			var _c:Map<String, Dynamic> = [];
			var map:Array<Dynamic> = [];

			function findTypeInfo(m:String, s:String) {
				return _c['$m.$s'];
			}
			function getTypeInfo(type:haxe.macro.ModuleType) {
				function makeTypeInfo(k:String, d:Dynamic) {
					var info:TypeInfo = (findTypeInfo(d.module, d.name) ?? {
						kind: k,
						module: d.module,
						name: d.name,
						pack: d.pack
					});
					if (k == 'typedef') {
						info.typedefType = switch (d.type) {
							case TInst(r, _): makeTypeInfo('class', r.get());
							default: null;
						}
					}
					if (d.isInterface) {
						info.isInterface = true;
					}
					_c['${d.module}.${d.name}'] = info;
					return info;
				}

				return switch (type) {
					case TClassDecl(r): return makeTypeInfo('class', r.get());
					case TEnumDecl(r): return makeTypeInfo('enum', r.get());
					case TTypeDecl(r): return makeTypeInfo('typedef', r.get());
					case TAbstract(r): return makeTypeInfo('abstract', r.get());
				};
			}

			for (type in types)
				map.push(getTypeInfo(type));

			self.meta.add('typed', [macro $v{haxe.Serializer.run(map)}], self.pos);
		});

		return macro {
			var meta:Array<TypeInfo> = cast haxe.Unserializer.run(haxe.rtti.Meta.getType($p{_name.split('.')}).typed[0]);
			var map:TypeMap = {
				byPackage: [],
				byModule: [],
				byPath: [],
				byCompilePath: [],
				all: []
			};

			for (info in meta) {
				var tp:Array<String> = info.pack.copy();
				tp.push(info.name);
				var packPath:String = info.pack.join('.');

				map.all.push(info);

				map.byCompilePath[tp.join('.')] = [info];
				map.byPath[info.module + (info.module.length == 0 ? '' : '.') + info.name] = [info];

				map.byModule[info.module] ??= new Array<TypeInfo>();
				map.byPackage[packPath] ??= new Array<TypeInfo>();

				map.byModule[info.module].push(info);
				map.byPackage[packPath].push(info);
			}

			cast map;
		}
	}
}
