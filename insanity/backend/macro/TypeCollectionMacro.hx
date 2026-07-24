package insanity.backend.macro;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.ExprTools;
import haxe.macro.TypedExprTools;
#end
import insanity.backend.TypeCollection;

class TypeCollectionMacro {
	static var _name:String = 'insanity.backend.macro.TypeCollectionMacro';

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
			// Context.info('types registered !!', Context.currentPos());
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
