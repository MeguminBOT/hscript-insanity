/*
 * Copyright (C)2008-2017 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

package insanity.backend;

enum Const {
	CInt(v:Int);
	CFloat(f:Float);
	CString(s:String, ?interp:Bool);
	CReg(pattern:String, modifiers:String);
}

typedef Position = {
	var origin:String;
	var line:Int;

	var ?pmin:Int;
	var ?pmax:Int;
	var ?column:Int;
}

typedef Expr = {
	var e:ExprDef;
	var pos:Position;
}

enum ExprDef {
	EDecl(t:ModuleDecl);
	EConst(c:Const);
	EIdent(v:String);
	EVar(n:String, ?t:CType, ?e:Expr, ?get:String, ?set:String, ?isFinal:Bool);
	EParent(e:Expr);
	EBlock(e:Array<Expr>);
	EField(e:Expr, f:String, ?maybe:Bool);
	EBinop(op:String, e1:Expr, e2:Expr);
	EUnop(op:String, prefix:Bool, e:Expr);
	ECall(e:Expr, params:Array<Expr>);
	EIf(cond:Expr, e1:Expr, ?e2:Expr);
	EWhile(cond:Expr, e:Expr);
	EFor(v:String, it:Expr, e:Expr);
	EBreak;
	EContinue;
	EFunction(args:Array<Argument>, e:Expr, ?name:String, ?ret:CType, ?id:Int);
	EReturn(?e:Expr);
	EArray(e:Expr, index:Expr);
	EArrayDecl(e:Array<Expr>);
	ENew(cl:String, params:Array<Expr>);
	EThrow(e:Expr);
	ETry(e:Expr, v:String, t:Null<CType>, ecatch:Expr, ?extra:Array<{v:String, t:Null<CType>, expr:Expr}>);
	EObject(fl:Array<{name:String, e:Expr}>);
	ETernary(cond:Expr, e1:Expr, e2:Expr);
	ESwitch(e:Expr, cases:Array<{values:Array<Expr>, expr:Expr, ?guard:Expr}>, ?defaultExpr:Expr);
	EDoWhile(cond:Expr, e:Expr);
	EMeta(name:String, args:Array<Expr>, e:Expr);
	ECheckType(e:Expr, t:CType);
	EForGen(it:Expr, e:Expr);
	ECast(e:Expr, ?t:CType);
	EImport(path:Array<String>, mode:ImportMode);
	EUsing(path:Array<String>);
}

typedef Argument = {name:String, ?t:CType, ?opt:Bool, ?value:Expr, ?rest:Bool};
typedef Metadata = Array<MetadataEntry>;
typedef MetadataEntry = {name:String, params:Array<Expr>};

enum CType {
	CTPath(path:Array<String>, ?params:Array<CType>);
	CTFun(args:Array<CType>, ret:CType);
	CTAnon(fields:Array<{name:String, t:CType, ?meta:Metadata}>);
	CTParent(t:CType);
	CTOpt(t:CType);
	CTNamed(n:String, t:CType);
	CTExpr(e:Expr); // for type parameters only
}

typedef ModuleDecl = {
	var d:ModuleDeclDef;
	var pos:Position;
}

enum ModuleDeclDef {
	DPackage(path:Array<String>);
	DImport(path:Array<String>, mode:ImportMode);
	DUsing(path:Array<String>);
	DField(c:ModuleFieldDecl);
	DClass(c:ClassDecl);
	DInterface(c:ClassDecl);
	DEnum(c:EnumDecl);
	DTypedef(c:TypeDecl);
}

typedef ModuleType = {
	var name:String;
	var params:Array<String>; // erased: names only, constraints are dropped
	var meta:Metadata;
	var isPrivate:Bool;
}

typedef ClassDecl = {
	> ModuleType,
	var extend:Null<CType>;
	var implement:Array<CType>;
	var fields:Array<FieldDecl>;
	var isExtern:Bool;
}

typedef TypeDecl = {
	> ModuleType,
	var t:CType;
}

typedef FieldDecl = {
	var name:String;
	var meta:Metadata;
	var kind:FieldKind;
	var access:Array<FieldAccess>;
}

typedef EnumDecl = {
	> ModuleType,
	var constructs:Map<String, EnumFieldDecl>;
	var names:Array<String>;
}

typedef EnumFieldDecl = {
	var name:String;
	var meta:Metadata;
	var ?arguments:Array<Argument>;
}

typedef ModuleFieldDecl = {
	> ModuleType,
	var kind:FieldKind;
}

enum FieldAccess {
	APublic;
	APrivate;
	AInline;
	ADynamic;
	AOverride;
	AStatic;
	AMacro;
}

enum FieldKind {
	KFunction(f:FunctionDecl);
	KVar(v:VarDecl);
}

typedef FunctionDecl = {
	var args:Array<Argument>;
	var expr:Expr;
	var ret:Null<CType>;
}

typedef VarDecl = {
	var get:Null<String>;
	var set:Null<String>;
	var expr:Null<Expr>;
	var type:Null<CType>;
	var isFinal:Null<Bool>;
}

enum ImportMode {
	INormal;
	IAsName(alias:String);
	IAll;
}

enum Mirror {
	MSuper(?locals:Map<String, Interp.Variable>, ?constructor:Dynamic);
	MProperty(t:Dynamic, f:String);
	MEnumValue(t:Dynamic, i:Int);
	MAbstractEnumValue(t:Dynamic, i:Int);
}
