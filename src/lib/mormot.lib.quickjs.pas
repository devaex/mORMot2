/// low-level access to the QuickJS Engine
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.lib.quickjs;

{
  *****************************************************************************

   Cross-Platform and Cross-Compiler JavaScript Interpreter
   - QuickJS Low-Level Constants and Types
   - QuickJS Functions API
   - QuickJS to Pascal Wrappers

  *****************************************************************************

}

interface

{$I ..\mormot.defines.inc}

{
  QuickJS is a small and embeddable Javascript engine.
  It supports the ES2020 specification including modules, asynchronous
  generators, proxies and BigInt.

  Copyright 2017-2018 Fabrice Bellard and Charlie Gordon - MIT License

  Permission is hereby granted, free of charge, to any person
  obtaining a copy of this software and associated documentation files
  (the "Software"), to deal in the Software without restriction,
  including without limitation the rights to use, copy, modify, merge,
  publish, distribute, sublicense, and/or sell copies of the Software,
  and to permit persons to whom the Software is furnished to do so,
  subject to the following conditions:

  The above copyright notice and this permission notice shall be
  included in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
  ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
}



{$ifdef LIBQUICKJSSTATIC}
  // we supply https://github.com/c-smile/quickjspp (uncompatible) fork statics
  // - 64-bit JSValue on all platforms, JSX, debugger, Windows compatible
  {$define JS_STRICT_NAN_BOXING}
  {$define LIBQUICKJS}
{$endif LIBQUICKJSSTATIC}


{$ifdef LIBQUICKJS}

uses
  sysutils,
  classes,
  math,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.lib.static;

{$ifdef JS_STRICT_NAN_BOXING}
  {$define JS_ANY_NAN_BOXING}
{$else}
  // on 32-bit, JSValue is an 64-bit with double NAN bits used as tag
  // on 64-bit, JSValue is a 128-bit struct of explicit value + tag
  {$ifdef CPU32}
    {$define JS_NAN_BOXING}
    {$define JS_ANY_NAN_BOXING}
  {$endif CPU32}
{$endif JS_STRICT_NAN_BOXING}

{$ifdef FPC}
  {$packrecords C}
{$endif FPC}



{ ************ QuickJS to Pascal Wrappers }

type
  /// exception raised by this unit on QuickJS panic
  // - mainly if assert() - aka pas_assert() - failed in the C code
  EQuickJS = class(Exception);

// some definitions ahead of low-level QuickJS API to allow pointer wrapping

  {$ifdef JS_ANY_NAN_BOXING}
  {$ifdef CPU64}
    {$define JS_ANY_NAN_BOXING_CPU64}
  {$endif CPU64}
  /// JSValue as stored in a 64-bit integer (one or two registers)
  // - mandatory for the proper values marshalling over QuickJS API calls
  // - don't use this low-level type, but the high-level JSValue wrapper
  JSValueRaw = UInt64;
  {$else}
  /// JSValue as stored in a 128-bit structure (two registers)
  // - mandatory for the proper values marshalling over QuickJS API calls
  // - don't use this low-level type, but the high-level JSValue wrapper
  JSValueRaw = record
    union, tag: Int64;
  end;
  {$endif JS_ANY_NAN_BOXING}

  /// wrapper object to the QuickJS JSValueRaw opaque type
  // - you can use e.g. JSValue(somejsvaluevariable).IsObject or JSValue.Raw
  // - JSValueRaw is the low-level type mandatory for QuickJS API calls: using
  // JSValue to call the QuickJS library fails to use registers, so trigger GPF
  JSValue = object
  private
    u: record
      case byte of
        0:
          (i32,
           tag: integer);
        1:
          (f64: Double);
        2:
          (ptr: pointer);
        3:
          (u64: UInt64);
      end;
    {$ifndef JS_ANY_NAN_BOXING}
    UnboxedTag: Int64;
    {$endif JS_ANY_NAN_BOXING}
    /// return the tag of this value - won't detect JS_TAG_FLOAT64
    function TagNotFloat: PtrInt;
      {$ifdef HASINLINE} inline; {$endif}
  public
    /// set the tag bits - should be called before setting u.f64/ptr/u64 (i32 ok)
    procedure SetTag(newtag: PtrInt);
       {$ifdef HASINLINE} inline; {$endif}
    /// get the tag of this value, normalizing floats to JS_TAG_FLOAT64
    function NormTag: PtrInt;
       {$ifdef HASINLINE} inline; {$endif}
    /// detect JS_TAG_NULL
    function IsNull: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// detect JS_TAG_UNDEFINED
    function IsUndefined: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// detect JS_TAG_UNINITIALIZED
    function IsUninitialized: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// detect JS_TAG_STRING
    function IsString: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// detect JS_TAG_OBJECT
    function IsObject: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// detect JS_TAG_EXCEPTION
    function IsException: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// detect JS_TAG_SYMBOL
    function IsSymbol: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// detect JS_TAG_INT
    function IsInt32: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// detect JS_TAG_FLOAT64
    function IsFloat: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// detect JS_TAG_INT or JS_TAG_FLOAT64
    function IsNumber: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// detect NaN/+Inf/-Inf special values
    function IsNan: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// detect JS_TAG_BIG_INT
    function IsBigInt: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// detect JS_TAG_BIG_FLOAT
    function IsBigFloat: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// detect JS_TAG_BIG_DECIMAL
    function IsBigDecimal: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// detect reference-counted values
    function IsRefCounted: boolean;
       {$ifdef HASINLINE} inline; {$endif}

    /// extract the JS_TAG_INT value
    function Int32: integer;
       {$ifdef HASINLINE} inline; {$endif}
    /// extract the JS_TAG_INT or JS_TAG_FLOAT64 value as an 53-bit integer
    function Int64: Int64;
      {$ifdef HASINLINE} inline; {$endif}
    /// extract the JS_TAG_BOOL value
    function Bool: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// extract the JS_TAG_FLOAT64 value
    function F64: double;
       {$ifdef HASINLINE} inline; {$endif}
    /// may be JSObject or JSString
    function Ptr: pointer;
       {$ifdef HASINLINE} inline; {$endif}
    /// used internally by Duplicate/DuplicateRaw
    procedure IncRefCnt;
       {$ifdef HASINLINE} inline; {$endif}
    /// used internally by TJSContext.Free
    function DecRefCnt: boolean;
       {$ifdef HASINLINE} inline; {$endif}
    /// get the value as expected by the raw QuickJS API
    function Raw: JSValueRaw;
       {$ifdef HASINLINE} inline; {$endif}
    /// return a copy of this value, incrementing the refcount if needed
    function Duplicate: JSValue;
    /// return a copy of this value, without incrementing the refcount
    function DuplicateRaw: JSValueRaw;

    /// set a value from its tag and 32-bit content
    procedure From(newtag, val: integer); overload;
       {$ifdef HASINLINE} inline; {$endif}
    /// set a pointer value - may be JSObject or JSString
    procedure From(newtag: integer; ptr: pointer); overload;
     {$ifndef JS_ANY_NAN_BOXING_CPU64}{$ifdef HASINLINE}inline;{$endif}{$endif}
    /// create a JS_TAG_BOOL
    procedure From(val: boolean); overload;
       {$ifdef HASINLINE} inline; {$endif}
    /// create a JS_TAG_INT
    procedure From32(val: integer); overload;
       {$ifdef HASINLINE} inline; {$endif}
    /// create a JS_TAG_INT if possible, JS_TAG_FLOAT64 otherwise
    procedure From(val: Int64); overload;
       {$ifdef HASINLINE} inline; {$endif}
    /// create a JS_TAG_INT if possible, JS_TAG_FLOAT64 otherwise
    procedure From(val: double); overload;
       {$ifdef HASINLINE} inline; {$endif}
    /// create a JS_TAG_FLOAT64
    procedure FloatFrom(val: double); overload;
       {$ifdef HASINLINE} inline; {$endif}
  end;
  PJSValue = ^JSValue;


type
  JSRuntime = ^TJSRuntime;
  JSContext = ^TJSContext;

  /// wrapper object to the QuickJS JSRuntime abstract pointer type
  // - JSRuntime is a pointer to this opaque object
  // - only a single
  TJSRuntime = object
  public
    /// create a new execution context for this Runtime
    function New: JSContext;
    /// just a wrapper around JS_FreeRuntime(@self)
    procedure Done;
      {$ifdef HASINLINE} inline; {$endif}
    /// just a wrapper around Done with exception/signal tracking
    // - EQuickJS panic exception may occur if the GC detected some leak
    function DoneSafe: string;
  end;

  /// wrapper object to the QuickJS JSContext abstract pointer type
  // - JSContext is a pointer to this opaque object
  TJSContext = object
  public
    /// just a wrapper around JS_FreeContext(@self)
    procedure Done;
      {$ifdef HASINLINE} inline; {$endif}
    /// release the memory used by a JSValueRaw - JS_FreeValue() alternative
    procedure Free(var v: JSValueRaw); overload;
      {$ifdef HASINLINE} inline; {$endif}
    /// release the memory used by a JSValue - JS_FreeValue() alternative
    procedure Free(var v: JSValue); overload;
      {$ifdef HASINLINE} inline; {$endif}
    /// returns the current error message, after JSValue.IsException=true
    // - by default will get the exception from JS_GetException(), but you
    // can optionally specify the error reason/exception
    procedure ErrorMessage(stacktrace: boolean; var msg: RawUtf8;
      reason: PJSValue = nil);
    /// output ErrorMessage() text into the current error stream
    // - is the StdErr console by default, but may be redirected e.g. to a log
    procedure ErrorDump(stacktrace: boolean; reason: PJSValue = nil);
    /// raw execution of some JavaScript code
    function Eval(const code, fn: RawUtf8; flags: integer; out err: RawUtf8): JSValue;
    /// execute some JavaScript code in the global context
    // - returns '' on success, or an error message if compilation failed
    function EvalGlobal(const code: RawUtf8; const filename: RawUtf8 = ''): RawUtf8;
    /// execute some JavaScript code as a module
    // - returns '' on success, or an error message if compilation failed
    function EvalModule(const code, filename: RawUtf8): RawUtf8;

    /// convert a JSValue into its text
    procedure ToUtf8(var v: JSValue; var s: RawUtF8);
    /// append a JSValue as text
    procedure AddUtf8(var v: JSValue; var s: RawUtF8);
    /// detect the variant type of a JSValue
    // - returns varNull, varBoolean, varInt, varDouble, varString or varAny
    // (for JS_TAG_OBJECT)
    // - returns varUnknown if the JSValue can't be mapped into a variant
    function ToVariantType(var v: JSValue): integer;
      {$ifdef HASINLINE} inline; {$endif}
    /// convert a JSValue into a simple variant
    // - convert into varNull, varBoolean, varInt, varInt64, varDouble,
    // varString (after JsonStringify for JS_TAG_OBJECT) and returns true
    // - unhandled kinds return false
    function ToSimpleVariant(var v: JSValue; var res: variant): boolean;
    /// convert a JSValue into a simple variant and free the value
    function ToSimpleVariantFree(var v: JSValue; var res: variant): boolean;

    /// create a JS_TAG_STRING from UTF-8 buffer
    function From(P: PUtf8Char; Len: PtrInt): JSValue; overload;
       {$ifdef HASINLINE} inline; {$endif}
    /// create a JS_TAG_STRING from UTF-16 buffer
    function FromW(P: PWideChar; Len: PtrInt): JSValue; overload;
    /// create a JS_TAG_STRING from UTF-8 string
    function From(const val: RawUtF8): JSValue; overload;
       {$ifdef HASINLINE} inline; {$endif}
    /// create a JS_TAG_STRING from UTF-16 string
    function FromW(const val: SynUnicode): JSValue; overload;
       {$ifdef HASINLINE} inline; {$endif}
  end;



{ ************ QuickJS Low-Level Constants and Types }

const
  {$ifdef JS_STRICT_NAN_BOXING}

  // https://github.com/c-smile/quickjspp encoding

  JS_TAG_UNINITIALIZED = 0;
  JS_TAG_INT = 1;
  JS_TAG_BOOL = 2;
  JS_TAG_NULL = 3;
  JS_TAG_UNDEFINED = 4;
  JS_TAG_CATCH_OFFSET = 5;
  JS_TAG_EXCEPTION = 6;
  JS_TAG_FLOAT64 = 7;
  // all tags with a reference count have 0b1000 bit
  JS_TAG_OBJECT = 8;
  JS_TAG_FUNCTION_BYTECODE = 9; // used internally *
  JS_TAG_MODULE = 10;           // used internally
  JS_TAG_STRING = 11;
  JS_TAG_SYMBOL = 12;
  JS_TAG_BIG_FLOAT = 13;
  JS_TAG_BIG_INT = 14;
  JS_TAG_BIG_DECIMAL = 15;

  JS_TAG_MASK = $000FFFFFFFFFFFFF;

  JS_NAN = UInt64(JS_TAG_FLOAT64) shl 48 + 0;
  JS_INFINITY_NEGATIVE = UInt64(JS_TAG_FLOAT64) shl 48 + 1;
  JS_INFINITY_POSITIVE = UInt64(JS_TAG_FLOAT64) shl 48 + 2;

  {$else}

  // regular https://github.com/bellard/quickjs encoding (buggy on Windows)

  JS_TAG_FIRST = -11; // first negative tag
  JS_TAG_BIG_DECIMAL = -11;
  JS_TAG_BIG_INT = -10;
  JS_TAG_BIG_FLOAT = -9;
  JS_TAG_SYMBOL = -8;
  JS_TAG_STRING = -7;
  JS_TAG_MODULE = -3; // internal use
  JS_TAG_FUNCTION_BYTECODE = -2; // internal use
  JS_TAG_OBJECT = -1;
  // all tags with a reference count are negative
  JS_TAG_INT = 0;
  JS_TAG_BOOL = 1;
  JS_TAG_NULL = 2;
  JS_TAG_UNDEFINED = 3;
  JS_TAG_UNINITIALIZED = 4;
  JS_TAG_CATCH_OFFSET = 5;
  JS_TAG_EXCEPTION = 6;
  JS_TAG_FLOAT64 = 7;
  // any tag larger than FLOAT64 needs to be handled as JS_NAN_BOXING

  {$ifdef JS_NAN_BOXING}
  JS_FLOAT64_TAG_ADDEND = $7ff80000 - JS_TAG_FIRST + 1; // quiet NaN encoding
  JS_NAN = UInt64($7ff8000000000000 - (JS_FLOAT64_TAG_ADDEND shl 32));
  {$else}
var
  JS_NAN: JSValueRaw;
  {$endif JS_NAN_BOXING}

  {$endif JS_STRICT_NAN_BOXING}

const
  JS_FLOAT64_NAN: double = NaN;
  JS_FLOAT64_POSINF: double = Infinity;
  JS_FLOAT64_NEGINF: double = NegInfinity;

  {$ifdef CPU64}
  // any 64-bit pointer can be truncated to 48-bit
  JS_PTR64_MASK = $0000FFFFFFFFFFFF;
  {$endif CPU64}

const
  // flags for object properties
  JS_PROP_CONFIGURABLE = 1 shl 0;
  JS_PROP_WRITABLE = 1 shl 1;
  JS_PROP_ENUMERABLE = 1 shl 2;
  JS_PROP_C_W_E = JS_PROP_CONFIGURABLE or JS_PROP_WRITABLE or JS_PROP_ENUMERABLE;
  JS_PROP_LENGTH = 1 shl 3;  // used internally in Arrays
  JS_PROP_TMASK = 3 shl 4;   // mask for NORMAL, GETSET, VARREF, AUTOINIT
  JS_PROP_NORMAL = 0 shl 4;
  JS_PROP_GETSET = 1 shl 4;
  JS_PROP_VARREF = 2 shl 4;   // internal use
  JS_PROP_AUTOINIT = 3 shl 4; // internal use

  // flags for JS_DefineProperty
  JS_PROP_HAS_SHIFT = 8;
  JS_PROP_HAS_CONFIGURABLE = 1 shl 8;
  JS_PROP_HAS_WRITABLE = 1 shl 9;
  JS_PROP_HAS_ENUMERABLE = 1 shl 10;
  JS_PROP_HAS_GET = 1 shl 11;
  JS_PROP_HAS_SET = 1 shl 12;
  JS_PROP_HAS_VALUE = 1 shl 13;

  // throw an exception if false would be returned JS_DefineProperty/JS_SetProperty
  JS_PROP_THROW = 1 shl 14;
  // throw an exception if false would be returned in strict mode JS_SetProperty
  JS_PROP_THROW_STRICT = 1 shl 15;
  JS_PROP_NO_ADD = 1 shl 16;    // internal use
  JS_PROP_NO_EXOTIC = 1 shl 17; // internal use

  JS_DEFAULT_STACK_SIZE = 256 * 1024;

  // JS_Eval flags
  JS_EVAL_TYPE_GLOBAL = 0 shl 0;   // global code default
  JS_EVAL_TYPE_MODULE = 1 shl 0;   // module code
  JS_EVAL_TYPE_DIRECT = 2 shl 0;   // direct call internal use
  JS_EVAL_TYPE_INDIRECT = 3 shl 0; // indirect call internal use
  JS_EVAL_TYPE_MASK = 3 shl 0;
  JS_EVAL_FLAG_STRICT = 1 shl 3;   // force 'strict' mode
  JS_EVAL_FLAG_STRIP = 1 shl 4;    // force 'strip' mode

  // compile but do not run. The result is an object with a
  //  JS_TAG_FUNCTION_BYTECODE or JS_TAG_MODULE tag. It can be executed
  //  with JS_EvalFunction.
  JS_EVAL_FLAG_COMPILE_ONLY = 1 shl 5; // internal use
  JS_EVAL_FLAG_MODULE_COMPILE_ONLY = JS_EVAL_TYPE_MODULE or JS_EVAL_FLAG_COMPILE_ONLY;

  // don't include the stack frames before this eval in the Error backtraces
  JS_EVAL_FLAG_BACKTRACE_BARRIER = 1 shl 6;

  // Object Writer/Reader currently only used to handle precompiled code
  JS_WRITE_OBJ_BYTECODE = 1 shl 0; // allow function/module
  JS_WRITE_OBJ_BSWAP = 1 shl 1;    // byte swapped output

  JS_READ_OBJ_BYTECODE = 1 shl 0;  // allow function/module
  JS_READ_OBJ_ROM_DATA = 1 shl 1;  // avoid duplicating 'buf' data

  // C property definition
  JS_DEF_CFUNC = 0;
  JS_DEF_CGETSET = 1;
  JS_DEF_CGETSET_MAGIC = 2;
  JS_DEF_PROP_STRING = 3;
  JS_DEF_PROP_INT32 = 4;
  JS_DEF_PROP_INT64 = 5;
  JS_DEF_PROP_DOUBLE = 6;
  JS_DEF_PROP_UNDEFINED = 7;
  JS_DEF_OBJECT = 8;
  JS_DEF_ALIAS = 9;


  // C function definition

  // JSCFunctionEnum
  JS_CFUNC_generic = 0;
  JS_CFUNC_generic_magic = 1;
  JS_CFUNC_constructor = 2;
  JS_CFUNC_constructor_magic = 3;
  JS_CFUNC_constructor_or_func = 4;
  JS_CFUNC_constructor_or_func_magic = 5;
  JS_CFUNC_f_f = 6;
  JS_CFUNC_f_f_f = 7;
  JS_CFUNC_getter = 8;
  JS_CFUNC_setter = 9;
  JS_CFUNC_getter_magic = 10;
  JS_CFUNC_setter_magic = 11;
  JS_CFUNC_iterator_next = 12;

  JS_GPN_STRING_MASK = 1 shl 0;
  JS_GPN_SYMBOL_MASK = 1 shl 1;
  JS_GPN_PRIVATE_MASK = 1 shl 2;
  // only include the enumerable properties
  JS_GPN_ENUM_ONLY = 1 shl 4;
  // set theJSPropertyEnum.is_enumerable field
  JS_GPN_SET_ENUM = 1 shl 5;

  // C Call Flags
  JS_CALL_FLAG_CONSTRUCTOR = 1 shl 0;


type
  PJSContext = ^JSContext;
  PJSValueRaw = ^JSValueRaw;

  JSObject = pointer;

  JSClass = pointer;

  JSModuleDef = pointer;

  JS_BOOL = LongBool;

  JSString = ^pointer;

  JSClassID = cardinal;
  PJSClassID = ^JSClassID;

  JSAtom = cardinal;

  JSCFunctionEnum = integer;

  JSGCObjectHeader = pointer;

  JSValueConst = JSValueRaw;
  PJSValueConst = ^JSValueConst;

  JSValueConstArr = array[0..(MaxInt div SizeOf(JSValueConst)) - 1] of JSValueConst;
  PJSValueConstArr = ^JSValueConstArr;


type
  JSMallocState = record
    malloc_count, malloc_size, malloc_limit: PtrUInt;
    opaque: pointer;
  end;
  PJSMallocState = ^JSMallocState;

  JSMallocFunctions = record
    js_malloc: function(s: PJSMallocState; size: PtrUInt): pointer; cdecl;
    js_free: procedure(s: PJSMallocState; Ptr: pointer); cdecl;
    js_realloc: function(s: PJSMallocState; Ptr: pointer; size: PtrUInt): pointer; cdecl;
    js_malloc_usable_size: function(Ptr: pointer): PtrUInt; cdecl;
  end;
  PJSMallocFunctions = ^JSMallocFunctions;

  JSMemoryUsage = record
    malloc_size,
    malloc_limit,
    memory_used_size,
    malloc_count,
    memory_used_count,
    atom_count,
    atom_size,
    str_count,
    str_size,
    obj_count,
    obj_size,
    prop_count,
    prop_size,
    shape_count,
    shape_size,
    js_func_count,
    js_func_size,
    js_func_code_size,
    js_func_pc2line_count,
    js_func_pc2line_size,
    c_func_count,
    array_count,
    fast_array_count,
    fast_array_elements,
    binary_object_count,
    binary_object_size: Int64;
  end;
  PJSMemoryUsage = ^JSMemoryUsage;

  JSCFunction = function(ctx: JSContext; this_val: JSValueConst; argc: integer;
    argv: PJSValueConstArr): JSValueRaw; cdecl;
  PJSCFunction = ^JSCFunction;

  JSCFunctionMagic = function(ctx: JSContext; this_val: JSValueConst;
    argc: integer; argv: PJSValueConst; magic: integer): JSValueRaw; cdecl;
  PJSCFunctionMagic = ^JSCFunctionMagic;

  JSCFunctionData = function(ctx: JSContext; this_val: JSValueConst;
    argc: integer; argv: PJSValueConst; magic: integer;
    func_data: PJSValueRaw): JSValueRaw; cdecl;
  PJSCFunctionData = ^JSCFunctionData;

  JS_MarkFunc = procedure(rt: JSRuntime; gp: JSGCObjectHeader); cdecl;
  PJS_MarkFunc = ^JS_MarkFunc;

  JSClassFinalizer = procedure(rt: JSRuntime; val: JSValueRaw); cdecl;
  PJSClassFinalizer = ^JSClassFinalizer;

  JSClassGCMark = procedure(rt: JSRuntime; val: JSValueConst;
    mark_func: PJS_MarkFunc); cdecl;
  PJSClassGCMark = ^JSClassGCMark;

  JSClassCall = function(ctx: JSContext; func_obj: JSValueConst;
    this_val: JSValueConst; argc: integer; argv: PJSValueConst;
    flags: integer): JSValueRaw; cdecl;
  PJSClassCall = ^JSClassCall;

  JSFreeArrayBufferDataFunc = procedure(rt: JSRuntime;
    opaque, Ptr: pointer); cdecl;
  PJSFreeArrayBufferDataFunc = ^JSFreeArrayBufferDataFunc;

  // return != 0 if the JS code needs to be interrupted
  JSInterruptHandler = function(rt: JSRuntime; opaque: pointer): integer; cdecl;
  PJSInterruptHandler = ^JSInterruptHandler;

  // return the module specifier (allocated with js_malloc()) or nil if exception
  JSModuleNormalizeFunc = function(ctx: JSContext; const module_base_name,
    module_name: PAnsiChar; opaque: pointer): PAnsiChar; cdecl;
  PJSModuleNormalizeFunc = ^JSModuleNormalizeFunc;

  JSModuleLoaderFunc = function(ctx: JSContext; module_name: PAnsiChar;
    opaque: pointer): JSModuleDef; cdecl;
  PJSModuleLoaderFunc = ^JSModuleLoaderFunc;

  // JS Job support
  JSJobFunc = function(ctx: JSContext; argc: integer;
    argv: PJSValueConst): JSValueRaw; cdecl;
  PJSJobFunc = ^JSJobFunc;

  // C module definition
  JSModuleInitFunc = function(ctx: JSContext; m: JSModuleDef): integer; cdecl;
  PJSModuleInitFunc = ^JSModuleInitFunc;

  // Promises RejectionTracker CallBack

  // is_handled = true means that the rejection is handled
  JSHostPromiseRejectionTracker = procedure(ctx: JSContext;
    promise, reason: JSValueConst; is_handled: JS_BOOL; opaque: pointer); cdecl;
  PJSHostPromiseRejectionTracker = ^JSHostPromiseRejectionTracker;

  // object class support
  JSPropertyEnum = record
    is_enumerable: JS_BOOL;
    atom: JSAtom;
  end;
  PJSPropertyEnum = ^JSPropertyEnum;
  PPJSPropertyEnum = ^PJSPropertyEnum;

  JSPropertyDescriptor = record
    flags: integer;
    value, getter, setter: JSValueRaw;
  end;
  PJSPropertyDescriptor = ^JSPropertyDescriptor;

  JSClassExoticMethods = record
    // Return -1 if exception (can only happen in case of Proxy object),
    // 0 if the property does not exists, true if it exists. If 1 is
    // returned, the property descriptor 'desc' is filled if != nil.
    get_own_property: function(ctx: JSContext; desc: PJSPropertyDescriptor;
      obj: JSValueConst; prop: JSAtom): integer; cdecl;

    // '*ptab' should hold the '*plen' property keys. Return 0 if OK,
    // -1 if exception. The 'is_enumerable' field is ignored.
    get_own_property_names: function(ctx: JSContext; ptab: PPJSPropertyEnum;
      plen: PCardinal; obj: JSValueConst): integer; cdecl;

    // return < 0 if exception, or true/false
    delete_property: function(ctx: JSContext; obj: JSValueConst;
      prop: JSAtom): integer; cdecl;

    // return < 0 if exception or true/false
    define_own_property: function(ctx: JSContext; this_obj: JSValueConst;
      prop: JSAtom; val: JSValueConst; getter: JSValueConst;
      setter: JSValueConst; flags: integer): integer; cdecl;

    // The following methods can be emulated with the previous ones,
    //   so they are usually not needed

    // return < 0 if exception or true/false
    has_property: function(ctx: JSContext; obj: JSValueConst;
      atom: JSAtom): integer; cdecl;
    get_property: function(ctx: JSContext; obj: JSValueConst; atom: JSAtom;
      receiver: JSValueConst): JSValueRaw; cdecl;
    set_property: function(ctx: JSContext; obj: JSValueConst; atom: JSAtom;
      value: JSValueConst; receiver: JSValueConst; flags: integer): integer; cdecl;
  end;
  PJSClassExoticMethods = ^JSClassExoticMethods;

  JSClassDef = record
    class_name: PAnsiChar;
    finalizer: PJSClassFinalizer;
    gc_mark: PJSClassGCMark;
    // if call != nil, the object is a function.
    // If (flags and JS_CALL_FLAG_CONSTRUCTOR) <> 0, the function is called as a
    // constructor. In this case, 'this_val' is new.target. A
    // constructor call only happens if the object constructor bit is
    // set (see JS_SetConstructorBit())
    call: PJSClassCall;
    // XXX: suppress this indirection ? It is here only to save memory
    // because only a few classes need these methods
    exotic: PJSClassExoticMethods;
  end;
  PJSClassDef = ^JSClassDef;


  // C function definition

  constructor_magic_func = function(ctx: JSContext; new_target: JSValueConst;
    argc: integer; argv: PJSValueConst; magic: integer): JSValueRaw; cdecl;

  f_f_func = function(_para1: double): double cdecl;

  f_f_f_func = function(_para1: double; _para2: double): double; cdecl;

  Getter_func = function(ctx: JSContext; this_val: JSValueConst): JSValueRaw; cdecl;

  Setter_func = function(ctx: JSContext; this_val: JSValueConst;
    val: JSValueConst): JSValueRaw; cdecl;

  getter_magic_func = function(ctx: JSContext; this_val: JSValueConst;
    magic: integer): JSValueRaw; cdecl;

  setter_magic_func = function(ctx: JSContext; this_val: JSValueConst;
    val: JSValueConst; magic: integer): JSValueRaw; cdecl;

  iterator_next_func = function(ctx: JSContext; this_val: JSValueConst;
    argc: integer; argv: PJSValueConst; pdone: PInteger;
    magic: integer): JSValueRaw; cdecl;

  JSCFunctionType = record
    case integer of
      0:
        (generic: JSCFunction);
      1:
        (generic_magic: JSCFunctionMagic);
      2:
        (&constructor: JSCFunction);
      3:
        (constructor_magic: constructor_magic_func);
      4:
        (constructor_or_func: JSCFunction);
      5:
        (f_f: f_f_func);
      6:
        (f_f_f: f_f_f_func);
      7:
        (getter: Getter_func);
      8:
        (setter: Setter_func);
      9:
        (getter_magic: getter_magic_func);
      10:
        (setter_magic: setter_magic_func);
      11:
        (iterator_next: iterator_next_func);
  end;
  PJSCFunctionType = ^JSCFunctionType;

  // C property definition

  JSCFunctionListEntry = record
    name: PAnsiChar;
    prop_flags: byte;
    def_type: byte;
    magic: SmallInt;
    u: record
      case integer of
        0:
          (func: record
            length: byte; // XXX: should move outside union
            cproto: byte; // XXX: should move outside union
            cfunc: JSCFunctionType;
          end);
        1:
          (getset: record
            get: JSCFunctionType;
            _set: JSCFunctionType;
          end);
        2:
          (&alias: record
            name: PAnsiChar;
            base: integer;
          end);
        3:
          (prop_list: record
            tab: ^JSCFunctionListEntry;
            len: integer;
          end);
        4:
          (str: PAnsiChar);
        5:
          (i32: integer);
        6:
          (i64: Int64);
        7:
          (f64: double);
    end;
  end;
  PJSCFunctionListEntry = ^JSCFunctionListEntry;


{ ************ QuickJS Functions API }

{$ifdef LIBQUICKJSSTATIC}

  {$define QUICKJSDEBUGGER}
  {$undef QJSDLL}

{$else}

  // Windows (and Delphi) doesn't support well gcc compiled binaries
  {$define QJSDLL}

const
  {$ifdef OSWINDOWS}

  {$ifdef WIN64}
  QJ = 'quickjs64.dll';
  {$else}
  QJ = 'quickjs32.dll';
  {$endif WIN64}

  {$else}

  QJ = 'libquickjs.o';

  {$endif OSWINDOWS}

{$endif LIBQUICKJSSTATIC}

function JS_NewRuntime: JSRuntime;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

// info must remain at least as long as rt
procedure JS_SetRuntimeInfo(rt: JSRuntime; const info: PAnsiChar);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_SetMemoryLimit(rt: JSRuntime; limit: PtrUInt);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_SetGCThreshold(rt: JSRuntime; gc_threshold: PtrUInt);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_SetMaxStackSize(ctx: JSContext; stack_size: PtrUInt);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewRuntime2(const mf: PJSMallocFunctions;
  opaque: pointer): JSRuntime;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_FreeRuntime(rt: JSRuntime);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetRuntimeOpaque(rt: JSRuntime): pointer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_SetRuntimeOpaque(rt: JSRuntime; opaque: pointer);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_MarkValue(rt: JSRuntime; val: JSValueConst;
  mark_func: PJS_MarkFunc);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_RunGC(rt: JSRuntime);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_IsLiveObject(rt: JSRuntime; obj: JSValueConst): JS_BOOL;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

// {REMOVED} function JS_IsInGCSweep(rt: JSRuntime): JS_BOOL;
// cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewContext(rt: JSRuntime): JSContext;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_FreeContext(s: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_DupContext(ctx: JSContext): JSContext;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetContextOpaque(ctx: JSContext): pointer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_SetContextOpaque(ctx: JSContext; opaque: pointer);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetRuntime(ctx: JSContext): JSRuntime;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_SetClassProto(ctx: JSContext; class_id: JSClassID; obj: JSValueRaw);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetClassProto(ctx: JSContext; class_id: JSClassID): JSValueRaw;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

// the following functions are used to select the intrinsic object to save memory

function JS_NewContextRaw(rt: JSRuntime): JSContext;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_AddIntrinsicBaseObjects(ctx: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_AddIntrinsicDate(ctx: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_AddIntrinsicEval(ctx: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_AddIntrinsicStringNormalize(ctx: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_AddIntrinsicRegExpCompiler(ctx: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_AddIntrinsicRegExp(ctx: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_AddIntrinsicJSON(ctx: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_AddIntrinsicProxy(ctx: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_AddIntrinsicMapSet(ctx: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_AddIntrinsicTypedArrays(ctx: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_AddIntrinsicPromise(ctx: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_AddIntrinsicBigInt(ctx: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_AddIntrinsicBigFloat(ctx: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_AddIntrinsicBigDecimal(ctx: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

{ enable operator overloading }

procedure JS_AddIntrinsicOperators(ctx: JSContext);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

{ enable "use math" }

procedure JS_EnableBignumExt(ctx: JSContext; enable: JS_BOOL);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};


function js_string_codePointRange(ctx: JSContext; this_val: JSValueConst;
  argc: integer; argv: PJSValueConst): JSValueRaw;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_malloc_rt(rt: JSRuntime; size: PtrUInt): pointer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure js_free_rt(rt: JSRuntime; ptr: pointer);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_realloc_rt(rt: JSRuntime; ptr: pointer; size: PtrUInt): pointer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_malloc_usable_size_rt(rt: JSRuntime; ptr: pointer): PtrUInt;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_mallocz_rt(rt: JSRuntime; size: PtrUInt): pointer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_malloc(ctx: JSContext; size: PtrUInt): pointer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure js_free(ctx: JSContext; ptr: pointer);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_realloc(ctx: JSContext; ptr: pointer; size: PtrUInt): pointer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_malloc_usable_size(ctx: JSContext; ptr: pointer): PtrUInt;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_realloc2(ctx: JSContext; ptr: pointer; size: PtrUInt;
  pslack: PPtrUInt): pointer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_mallocz(ctx: JSContext; size: PtrUInt): pointer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_strdup(ctx: JSContext; str: PAnsiChar): PAnsiChar;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_strndup(ctx: JSContext; s: PAnsiChar; n: PtrUInt): PAnsiChar;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_ComputeMemoryUsage(rt: JSRuntime; s: PJSMemoryUsage);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_DumpMemoryUsage(fp: pointer; s: PJSMemoryUsage; rt: JSRuntime);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

{ atom support }

function JS_NewAtomLen(ctx: JSContext; str: PAnsiChar; len: PtrUInt): JSAtom;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewAtom(ctx: JSContext; str: PAnsiChar): JSAtom;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewAtomUInt32(ctx: JSContext; n: cardinal): JSAtom;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_DupAtom(ctx: JSContext; v: JSAtom): JSAtom;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_FreeAtom(ctx: JSContext; v: JSAtom);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_FreeAtomRT(rt: JSRuntime; v: JSAtom);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_AtomToValue(ctx: JSContext; atom: JSAtom): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_AtomToString(ctx: JSContext; atom: JSAtom): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_AtomToCString(ctx: JSContext; atom: JSAtom): PAnsiChar;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_ValueToAtom(ctx: JSContext; val: JSValueConst): JSAtom;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

{ object class support }

function JS_NewClassID(pclass_id: PJSClassID): JSClassID;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewClass(rt: JSRuntime; class_id: JSClassID;
  class_def: PJSClassDef): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_IsRegisteredClass(rt: JSRuntime; class_id: JSClassID): integer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};


{ JS Numbers }

function JS_NewBigInt64(ctx: JSContext; v: Int64): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewBigUint64(ctx: JSContext; v: UInt64): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_Throw(ctx: JSContext; obj: JSValueRaw): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetException(ctx: JSContext): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_IsError(ctx: JSContext; val: JSValueConst): JS_BOOL;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_ResetUncatchableError(ctx: JSContext);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewError(ctx: JSContext): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_ThrowSyntaxError(ctx: JSContext; fmt: PAnsiChar): JSValueRaw;
   cdecl varargs; external {$ifdef QJSDLL}QJ{$endif};

function JS_ThrowTypeError(ctx: JSContext; fmt: PAnsiChar): JSValueRaw;
   cdecl varargs; external {$ifdef QJSDLL}QJ{$endif};

function JS_ThrowReferenceError(ctx: JSContext; fmt: PAnsiChar): JSValueRaw;
   cdecl varargs; external {$ifdef QJSDLL}QJ{$endif};

function JS_ThrowRangeError(ctx: JSContext; fmt: PAnsiChar): JSValueRaw;
   cdecl varargs; external {$ifdef QJSDLL}QJ{$endif};

function JS_ThrowInternalError(ctx: JSContext; fmt: PAnsiChar): JSValueRaw;
   cdecl varargs; external {$ifdef QJSDLL}QJ{$endif};

function JS_ThrowOutOfMemory(ctx: JSContext): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure __JS_FreeValue(ctx: JSContext; v: JSValueRaw);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure __JS_FreeValueRT(rt: JSRuntime; v: JSValueRaw);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

{ JS Values - return -1 for JS_EXCEPTION }

function JS_ToBool(ctx: JSContext; val: JSValueConst): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_ToInt32(ctx: JSContext; pres: PInteger; val: JSValueConst): integer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_ToInt64(ctx: JSContext; pres: PInt64; val: JSValueConst): integer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_ToIndex(ctx: JSContext; plen: PUInt64; val: JSValueConst): integer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_ToFloat64(ctx: JSContext; pres: PDouble; val: JSValueConst): integer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};
{ return an exception if 'val' is a Number }

function JS_ToBigInt64(ctx: JSContext; pres: PInt64; val: JSValueConst): integer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};
{ same as JS_ToInt64() but allow BigInt }

function JS_ToInt64Ext(ctx: JSContext; pres: PInt64; val: JSValueConst): integer;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewStringLen(ctx: JSContext;
  str1: PAnsiChar; len1: PtrUInt): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewString(ctx: JSContext; str: PAnsiChar): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewAtomString(ctx: JSContext; str: PAnsiChar): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_ToString(ctx: JSContext; val: JSValueConst): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_ToPropertyKey(ctx: JSContext; val: JSValueConst): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_ToCStringLen2(ctx: JSContext; plen: PPtrUInt; val1: JSValueConst;
  cesu8: JS_BOOL): PAnsiChar;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_FreeCString(ctx: JSContext; ptr: PAnsiChar);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewObjectProtoClass(ctx: JSContext; proto: JSValueConst;
  class_id: JSClassID): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewObjectClass(ctx: JSContext; class_id: JSClassID): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewObjectProto(ctx: JSContext; proto: JSValueConst): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewObject(ctx: JSContext): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_IsFunction(ctx: JSContext; val: JSValueConst): JS_BOOL;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_IsConstructor(ctx: JSContext; val: JSValueConst): JS_BOOL;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_SetConstructorBit(ctx: JSContext; func_obj: JSValueConst;
  val: JS_BOOL): JS_BOOL;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewArray(ctx: JSContext): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_IsArray(ctx: JSContext; val: JSValueConst): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetPropertyInternal(ctx: JSContext; obj: JSValueConst; prop: JSAtom;
  receiver: JSValueConst; throw_ref_error: JS_BOOL): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetPropertyStr(ctx: JSContext; this_obj: JSValueConst;
  prop: PAnsiChar): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetPropertyUint32(ctx: JSContext; this_obj: JSValueConst;
  idx: cardinal): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_SetPropertyInternal(ctx: JSContext; this_obj: JSValueConst;
  prop: JSAtom; val: JSValueRaw; flags: integer): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_SetPropertyUint32(ctx: JSContext; this_obj: JSValueConst;
  idx: cardinal; val: JSValueRaw): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_SetPropertyInt64(ctx: JSContext; this_obj: JSValueConst;
  idx: Int64; val: JSValueRaw): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_SetPropertyStr(ctx: JSContext; this_obj: JSValueConst;
  prop: PAnsiChar; val: JSValueRaw): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_HasProperty(ctx: JSContext; this_obj: JSValueConst;
  prop: JSAtom): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_IsExtensible(ctx: JSContext; obj: JSValueConst): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_PreventExtensions(ctx: JSContext; obj: JSValueConst): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_DeleteProperty(ctx: JSContext; obj: JSValueConst; prop: JSAtom;
  flags: integer): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_SetPrototype(ctx: JSContext; obj: JSValueConst; proto_val:
  JSValueConst): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetPrototype(ctx: JSContext; val: JSValueConst): JSValueConst;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetOwnPropertyNames(ctx: JSContext; ptab: PPJSPropertyEnum;
  plen: PCardinal; obj: JSValueConst; flags: integer): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetOwnProperty(ctx: JSContext; desc: PJSPropertyDescriptor;
  obj: JSValueConst; prop: JSAtom): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

// 'buf' must be zero terminated i.e. buf[buf_len] := #0
function JS_ParseJSON(ctx: JSContext; buf: PAnsiChar; buf_len: PtrUInt;
  filename: PAnsiChar): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_JSONStringify(ctx: JSContext;
  obj, replacer, space0: JSValueConst): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_Call(ctx: JSContext; func_obj: JSValueConst; this_obj: JSValueConst;
  argc: integer; argv: PJSValueConstArr): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_Invoke(ctx: JSContext; this_val: JSValueConst; atom: JSAtom;
  argc: integer; argv: PJSValueConst): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_CallConstructor(ctx: JSContext; func_obj: JSValueConst;
  argc: integer; argv: PJSValueConst): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_CallConstructor2(ctx: JSContext; func_obj: JSValueConst;
  new_target: JSValueConst; argc: integer; argv: PJSValueConst): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_DetectModule(const input: PAnsiChar; input_len: PtrUInt): JS_BOOL;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};
{ 'input' must be zero terminated i.e. buf[buf_len] := #0.  }

function JS_Eval(ctx: JSContext; input: PAnsiChar; input_len: PtrUInt;
  filename: PAnsiChar; eval_flags: integer): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_EvalFunction(ctx: JSContext; fun_obj: JSValueRaw): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetGlobalObject(ctx: JSContext): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_IsInstanceOf(ctx: JSContext; val: JSValueConst; obj: JSValueConst):
  integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_DefineProperty(ctx: JSContext; this_obj: JSValueConst;
  prop: JSAtom; val: JSValueConst; getter: JSValueConst; setter: JSValueConst;
  flags: integer): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_DefinePropertyValue(ctx: JSContext; this_obj: JSValueConst;
  prop: JSAtom; val: JSValueRaw; flags: integer): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_DefinePropertyValueUint32(ctx: JSContext; this_obj: JSValueConst;
  idx: cardinal; val: JSValueRaw; flags: integer): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_DefinePropertyValueStr(ctx: JSContext; this_obj: JSValueConst;
  prop: PAnsiChar; val: JSValueRaw; flags: integer): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_DefinePropertyGetSet(ctx: JSContext; this_obj: JSValueConst;
  prop: JSAtom; getter: JSValueRaw; setter: JSValueRaw; flags: integer): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_SetOpaque(obj: JSValueRaw; opaque: pointer);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetOpaque(obj: JSValueConst; class_id: JSClassID): pointer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetOpaque2(ctx: JSContext; obj: JSValueConst;
  class_id: JSClassID): pointer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewArrayBuffer(ctx: JSContext; buf: PByte; len: PtrUInt;
  free_func: PJSFreeArrayBufferDataFunc; opaque: pointer;
  is_shared: JS_BOOL): JSValueRaw;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewArrayBufferCopy(ctx: JSContext;
  buf: PByte; len: PtrUInt): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_DetachArrayBuffer(ctx: JSContext; obj: JSValueConst);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetArrayBuffer(ctx: JSContext; psize: PPtrUInt;
  obj: JSValueConst): PByte;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetTypedArrayBuffer(ctx: JSContext; obj: JSValueConst;
  pbyte_offset, pbyte_length, pbytes_per_element: PPtrUInt): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewPromiseCapability(ctx: JSContext;
  resolving_funcs: PJSValueRaw): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_SetHostPromiseRejectionTracker(rt: JSRuntime;
  cb: PJSHostPromiseRejectionTracker; opaque: pointer);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_SetInterruptHandler(rt: JSRuntime; cb: PJSInterruptHandler;
  opaque: pointer);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

{ if can_block is true, Atomics.wait() can be used  }
procedure JS_SetCanBlock(rt: JSRuntime; can_block: JS_BOOL);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

{ module_normalize = nil is allowed and invokes the default module filename normalizer  }
procedure JS_SetModuleLoaderFunc(rt: JSRuntime;
  module_normalize: PJSModuleNormalizeFunc; module_loader: PJSModuleLoaderFunc;
  opaque: pointer);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

{ JS Job support  }

function JS_EnqueueJob(ctx: JSContext; job_func: PJSJobFunc; argc: integer;
  argv: PJSValueConst): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_IsJobPending(rt: JSRuntime): JS_BOOL;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};
// TODO: Check pctx if the type is right.

function JS_ExecutePendingJob(rt: JSRuntime; pctx: PJSContext): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

{ Object Writer/Reader (currently only used to handle precompiled code)  }
{ allow function/module  }

function JS_WriteObject(ctx: JSContext; psize: PPtrUInt; obj: JSValueConst;
  flags: integer): PByte;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_ReadObject(ctx: JSContext; buf: PByte; buf_len: PtrUInt;
  flags: integer): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

{ load the dependencies of the module 'obj'. Useful when JS_ReadObject() }
{ returns a module }

function JS_ResolveModule(ctx: JSContext; obj: JSValueConst): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};


{ C function definition }

procedure JS_SetConstructor(ctx: JSContext; func_obj, proto: JSValueConst);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewCFunction2(ctx: JSContext; func: PJSCFunction; name: PAnsiChar;
  length: integer; cproto: JSCFunctionEnum; magic: integer): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_NewCFunctionData(ctx: JSContext; func: PJSCFunctionData;
  length: integer; magic: integer;
  data_len: integer; data: PJSValueConst): JSValueRaw;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_SetPropertyFunctionList(ctx: JSContext; obj: JSValueConst;
  tab: PJSCFunctionListEntry; len: integer);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

{ C module definition  }

function JS_NewCModule(ctx: JSContext; name_str: PAnsiChar;
  func: PJSModuleInitFunc): JSModuleDef;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

{ can only be called before the module is instantiated  }
function JS_AddModuleExport(ctx: JSContext; m: JSModuleDef;
  name_str: PAnsiChar): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_AddModuleExportList(ctx: JSContext; m: JSModuleDef;
  tab: PJSCFunctionListEntry; len: integer): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

{ can only be called after the module is instantiated  }
function JS_SetModuleExport(ctx: JSContext; m: JSModuleDef;
  export_name: PAnsiChar; val: JSValueRaw): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_SetModuleExportList(ctx: JSContext; m: JSModuleDef;
  tab: PJSCFunctionListEntry; len: integer): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

{ return the import.meta object of a module }
function JS_GetImportMeta(ctx: JSContext; m: JSModuleDef): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function JS_GetModuleName(ctx: JSContext; m: JSModuleDef): JSAtom;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};


// our static bindings don't include quickjs-libc since all is done is pascal

{$ifdef QUICKJSLIBC}

{ QuickJS libc }

function js_init_module_std(ctx: JSContext; module_name: PAnsiChar): JSModuleDef;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_init_module_os(ctx: JSContext; module_name: PAnsiChar): JSModuleDef;
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure js_std_add_helpers(ctx: JSContext; argc: integer; argv: pointer);
  cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure js_std_loop(ctx: JSContext);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure js_std_free_handlers(rt: JSRuntime);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_load_file(ctx: JSContext; pbuf_len: PPtrUInt;
  filename: PAnsiChar): pointer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_module_loader(ctx: JSContext; module_name: PAnsiChar;
  opaque: pointer): JSModuleDef;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure js_std_promise_rejection_tracker(ctx: JSContext;
  promise, reason: JSValueConst; is_handled: JS_BOOL; opaque: pointer);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

{$endif QUICKJSLIBC}


// moved from quickjs-libc.c to quickjs.c to be available

function js_module_set_import_meta(ctx: JSContext; func_val: JSValueConst;
  use_realpath, is_main: JS_BOOL): integer;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

// execute version-specific opcodes from JS_WriteObject()
procedure js_std_eval_binary(ctx: JSContext; buf: pointer; buf_len: PtrUInt;
  flags: integer);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};


// moved from quickjs-libc.c to this unit for custom error logging
procedure js_std_dump_error(ctx: JSContext); cdecl;
   {$ifdef QJSDLL} external QJ; {$endif}


{$ifdef QUICKJSDEBUGGER}

{ Experimental debugger support }

type
  JSDebuggerCheckLineNoF = function(ctx: JSContext; file_name: JSAtom;
    line_no: cardinal; pc: PByte): JS_BOOL; cdecl;

procedure JS_SetBreakpointHandler(ctx: JSContext;
  line_hit_handler: JSDebuggerCheckLineNoF);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

procedure JS_SetDebuggerMode(ctx: JSContext; onoff: JS_BOOL);
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_debugger_stack_depth(ctx: JSContext): cardinal;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_debugger_build_backtrace(ctx: JSContext; cur_pc: PByte): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_debugger_closure_variables(ctx: JSContext;
  stack_index: integer): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_debugger_local_variables(ctx: JSContext;
  stack_index: integer): JSValueRaw;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

function js_debugger_get_object_id(val: JSValueRaw): JSObject;
   cdecl; external {$ifdef QJSDLL}QJ{$endif};

{$endif QUICKJSDEBUGGER}


{ special constant values - set in initialization section below }

var
  JS_NULL,
  JS_UNDEFINED,
  JS_FALSE,
  JS_TRUE,
  JS_EXCEPTION,
  JS_UNINITIALIZED: JSValueRaw;


{ JSValue complex process of the QuickJS library }

function JS_ToUint32(ctx: JSContext; pres: PCardinal;
  val: JSValueConst): integer;
  {$ifdef HASINLINE} inline; {$endif}

function JS_ToCStringLen(ctx: JSContext; plen: PPtrUInt;
  val: JSValueConst): PAnsiChar;
  {$ifdef HASINLINE} inline; {$endif}

function JS_ToCString(ctx: JSContext; val: JSValueConst): PAnsiChar;
  {$ifdef HASINLINE} inline; {$endif}

function JS_GetProperty(ctx: JSContext; this_obj: JSValueConst;
  prop: JSAtom): JSValueRaw;
  {$ifdef HASINLINE} inline; {$endif}

function JS_SetProperty(ctx: JSContext; this_obj: JSValueConst; prop: JSAtom;
  val: JSValueRaw): integer;
  {$ifdef HASINLINE} inline; {$endif}


{ C function definition }

function JS_NewCFunction(ctx: JSContext; func: PJSCFunction; name: PAnsiChar;
  length: integer): JSValueRaw;
  {$ifdef HASINLINE} inline; {$endif}

function JS_NewCFunctionMagic(ctx: JSContext; func: PJSCFunctionMagic;
  name: PAnsiChar; length: integer; cproto: JSCFunctionEnum;
  magic: integer): JSValueRaw;
  {$ifdef HASINLINE} inline; {$endif}


{ C property definition }

function JS_CFUNC_DEF(name: PAnsiChar; length: integer;
  func: JSCFunction): JSCFunctionListEntry;

function JS_CFUNC_MAGIC_DEF(name: PAnsiChar; length: integer;
  func: JSCFunctionMagic; magic: SmallInt): JSCFunctionListEntry;

function JS_CFUNC_SPECIAL_DEF(name: PAnsiChar; length: integer;
  cproto: JSCFunctionEnum; func: f_f_func): JSCFunctionListEntry; overload;

function JS_CFUNC_SPECIAL_DEF(name: PAnsiChar; length: integer;
  cproto: JSCFunctionEnum; func: f_f_f_func): JSCFunctionListEntry; overload;

function JS_ITERATOR_NEXT_DEF(name: PAnsiChar; length: integer;
  iterator_next: iterator_next_func; magic: SmallInt): JSCFunctionListEntry;

function JS_CGETSET_DEF(name: PAnsiChar; fgetter: Getter_func;
  fsetter: Setter_func): JSCFunctionListEntry;

function JS_CGETSET_MAGIC_DEF(name: PAnsiChar; fgetter_magic: getter_magic_func;
  fsetter_magic: setter_magic_func; magic: SmallInt): JSCFunctionListEntry;

function JS_PROP_STRING_DEF(name: PAnsiChar; val: PAnsiChar;
  prop_flags: byte): JSCFunctionListEntry;

function JS_PROP_INT32_DEF(name: PAnsiChar; val: integer;
  prop_flags: byte): JSCFunctionListEntry;

function JS_PROP_INT64_DEF(name: PAnsiChar; val: Int64;
  prop_flags: byte): JSCFunctionListEntry;

function JS_PROP_DOUBLE_DEF(name: PAnsiChar; val: Double;
  prop_flags: byte): JSCFunctionListEntry;

function JS_PROP_UNDEFINED_DEF(name: PAnsiChar;
  prop_flags: byte): JSCFunctionListEntry;

function JS_OBJECT_DEF(name: PAnsiChar; tab: PJSCFunctionListEntry;
  length: integer; prop_flags: byte): JSCFunctionListEntry;

function JS_ALIAS_DEF(name, from: PAnsiChar): JSCFunctionListEntry;

function JS_ALIAS_BASE_DEF(name, from: PAnsiChar;
  base: integer): JSCFunctionListEntry;





implementation

{$ifdef LIBQUICKJSSTATIC}

uses
  mormot.lib.static;

{$ifdef OSLINUX}

  {$ifdef CPUX86}
    {$linklib ..\..\static\i386-linux\libquickjs.a}
  {$endif CPUX86}
  {$ifdef CPUX64}
    {$linklib ..\..\static\x86_64-linux\libquickjs.a}
  {$endif CPUX64}
  {$ifdef CPUAARCH64}
    {$L ..\..\static\aarch64-linux\libquickjs.a}
  {$endif CPUAARCH64}
  {$ifdef CPUARM}
    {$L ..\..\static\arm-linux\libquickjs.a}
  {$endif CPUARM}

{$endif OSLINUX}

{$ifdef OSWINDOWS}
  {$ifdef CPUX86}
    {$linklib ..\..\static\i386-win32\libquickjs.a}
  {$endif CPUX86}
  {$ifdef CPUX64}
    {$linklib ..\..\static\x86_64-win64\libquickjs.a}
  {$endif CPUX64}
{$endif OSWINDOWS}

procedure js_std_dump_error1(ctx: JSContext; exc: JSValueRaw);
  {$ifdef FPC} public name _PREFIX + 'js_std_dump_error1'; {$endif}
begin
  ctx.ErrorDump({stacktrace=}true, @exc);
end;

procedure js_std_dump_error(ctx: JSContext);
  {$ifdef FPC} public name _PREFIX + 'js_std_dump_error'; {$endif}
begin
  ctx.ErrorDump({stacktrace=}true, nil);
end;

{$endif LIBQUICKJSSTATIC}


{ ************ QuickJS Functions API }

function JS_ToUint32(ctx: JSContext; pres: PCardinal;
  val: JSValueConst): integer;
begin
  result := JS_ToInt32(ctx, PInteger(pres), val);
end;

function JS_ToCStringLen(ctx: JSContext; plen: PPtrUInt;
  val: JSValueConst): PAnsiChar;
begin
  result := JS_ToCStringLen2(ctx, plen, val, false);
end;

function JS_ToCString(ctx: JSContext; val: JSValueConst): PAnsiChar;
begin
  result := JS_ToCStringLen2(ctx, nil, val, false);
end;

function JS_GetProperty(ctx: JSContext; this_obj: JSValueConst;
  prop: JSAtom): JSValueRaw;
begin
  result := JS_GetPropertyInternal(ctx, this_obj, prop, this_obj, false);
end;

function JS_SetProperty(ctx: JSContext; this_obj: JSValueConst; prop: JSAtom;
  val: JSValueRaw): integer;
begin
  result := JS_SetPropertyInternal(ctx, this_obj, prop, val, JS_PROP_THROW);
end;


{ C function definition }

function JS_NewCFunction(ctx: JSContext; func: PJSCFunction; name: PAnsiChar;
  length: integer): JSValueRaw;
begin
  result := JS_NewCFunction2(ctx, func, name, length, JS_CFUNC_generic, 0);
end;

function JS_NewCFunctionMagic(ctx: JSContext; func: PJSCFunctionMagic;
  name: PAnsiChar; length: integer; cproto: JSCFunctionEnum;
  magic: integer): JSValueRaw;
begin
  result := JS_NewCFunction2(ctx, PJSCFunction(func), name, length, cproto, magic);
end;


{ C property definition }

function JS_CFUNC_DEF(name: PAnsiChar; length: integer;
  func: JSCFunction): JSCFunctionListEntry;
begin
  result.name := name;
  result.prop_flags := JS_PROP_WRITABLE or JS_PROP_CONFIGURABLE;
  result.def_type := JS_DEF_CFUNC;
  result.magic := 0;
  result.u.func.length := length;
  result.u.func.cproto := JS_CFUNC_generic;
  result.u.func.cfunc.generic := func;
end;

function JS_CFUNC_MAGIC_DEF(name: PAnsiChar; length: integer;
  func: JSCFunctionMagic; magic: SmallInt): JSCFunctionListEntry;
begin
  result.name := name;
  result.prop_flags := JS_PROP_WRITABLE or JS_PROP_CONFIGURABLE;
  result.def_type := JS_DEF_CFUNC;
  result.magic := magic;
  result.u.func.length := length;
  result.u.func.cproto := JS_CFUNC_generic_magic;
  result.u.func.cfunc.generic_magic := func;
end;

function JS_CFUNC_SPECIAL_DEF(name: PAnsiChar; length: integer;
  cproto: JSCFunctionEnum; func: f_f_func): JSCFunctionListEntry;
begin
  result.name := name;
  result.prop_flags := JS_PROP_WRITABLE or JS_PROP_CONFIGURABLE;
  result.def_type := JS_DEF_CFUNC;
  result.magic := 0;
  result.u.func.length := length;
  result.u.func.cproto := cproto;
  result.u.func.cfunc.f_f := func;
end;

function JS_CFUNC_SPECIAL_DEF(name: PAnsiChar; length: integer;
  cproto: JSCFunctionEnum; func: f_f_f_func): JSCFunctionListEntry;
begin
  result.name := name;
  result.prop_flags := JS_PROP_WRITABLE or JS_PROP_CONFIGURABLE;
  result.def_type := JS_DEF_CFUNC;
  result.magic := 0;
  result.u.func.length := length;
  result.u.func.cproto := cproto;
  result.u.func.cfunc.f_f_f := func;
end;

function JS_ITERATOR_NEXT_DEF(name: PAnsiChar; length: integer;
  iterator_next: iterator_next_func; magic: SmallInt): JSCFunctionListEntry;
begin
  result.name := name;
  result.prop_flags := JS_PROP_WRITABLE or JS_PROP_CONFIGURABLE;
  result.def_type := JS_DEF_CFUNC;
  result.magic := magic;
  result.u.func.length := length;
  result.u.func.cproto := JS_CFUNC_iterator_next;
  result.u.func.cfunc.iterator_next := iterator_next;
end;

function JS_CGETSET_DEF(name: PAnsiChar; fgetter: Getter_func;
  fsetter: Setter_func): JSCFunctionListEntry;
begin
  result.name := name;
  result.prop_flags := JS_PROP_CONFIGURABLE;
  result.def_type := JS_DEF_CGETSET;
  result.magic := 0;
  result.u.getset.get.getter := fgetter;
  result.u.getset._set.setter := fsetter;
end;

function JS_CGETSET_MAGIC_DEF(name: PAnsiChar; fgetter_magic: getter_magic_func;
  fsetter_magic: setter_magic_func; magic: SmallInt): JSCFunctionListEntry;
begin
  result.name := name;
  result.prop_flags := JS_PROP_CONFIGURABLE;
  result.def_type := JS_DEF_CGETSET_MAGIC;
  result.magic := magic;
  result.u.getset.get.getter_magic := fgetter_magic;
  result.u.getset._set.setter_magic := fsetter_magic;
end;

function JS_PROP_STRING_DEF(name: PAnsiChar; val: PAnsiChar;
  prop_flags: byte): JSCFunctionListEntry;
begin
  result.name := name;
  result.prop_flags := prop_flags;
  result.def_type := JS_DEF_PROP_STRING;
  result.magic := 0;
  result.u.str := val;
end;

function JS_PROP_INT32_DEF(name: PAnsiChar; val: integer;
  prop_flags: byte): JSCFunctionListEntry;
begin
  result.name := name;
  result.prop_flags := prop_flags;
  result.def_type := JS_DEF_PROP_INT32;
  result.magic := 0;
  result.u.i32 := val;
end;

function JS_PROP_INT64_DEF(name: PAnsiChar; val: Int64;
  prop_flags: byte): JSCFunctionListEntry;
begin
  result.name := name;
  result.prop_flags := prop_flags;
  result.def_type := JS_DEF_PROP_INT64;
  result.magic := 0;
  result.u.i64 := val;
end;

function JS_PROP_DOUBLE_DEF(name: PAnsiChar; val: Double;
  prop_flags: byte): JSCFunctionListEntry;
begin
  result.name := name;
  result.prop_flags := prop_flags;
  result.def_type := JS_DEF_PROP_DOUBLE;
  result.magic := 0;
  result.u.f64 := val;
end;

function JS_PROP_UNDEFINED_DEF(name: PAnsiChar;
  prop_flags: byte): JSCFunctionListEntry;
begin
  result.name := name;
  result.prop_flags := prop_flags;
  result.def_type := JS_DEF_PROP_UNDEFINED;
  result.magic := 0;
  result.u.i32 := 0;
end;

function JS_OBJECT_DEF(name: PAnsiChar; tab: PJSCFunctionListEntry;
  length: integer; prop_flags: byte): JSCFunctionListEntry;
begin
  result.name := name;
  result.prop_flags := prop_flags;
  result.def_type := JS_DEF_OBJECT;
  result.magic := 0;
  result.u.prop_list.tab := pointer(tab);
  result.u.prop_list.len := length;
end;

function JS_ALIAS_DEF(name, from: PAnsiChar): JSCFunctionListEntry;
begin
  result.name := name;
  result.prop_flags := JS_PROP_WRITABLE or JS_PROP_CONFIGURABLE;
  result.def_type := JS_DEF_ALIAS;
  result.magic := 0;
  result.u.&alias.name := from;
  result.u.&alias.base := -1;
end;

function JS_ALIAS_BASE_DEF(name, from: PAnsiChar;
  base: integer): JSCFunctionListEntry;
begin
  result.name := name;
  result.prop_flags := JS_PROP_WRITABLE or JS_PROP_CONFIGURABLE;
  result.def_type := JS_DEF_ALIAS;
  result.magic := 0;
  result.u.&alias.name := from;
  result.u.&alias.base := base;
end;


{ ************ QuickJS to Pascal Wrappers }

{ JSValue }

{$ifdef JS_STRICT_NAN_BOXING}

// quickjspp schema defines strict NAN boxing for both 32 and 64 versions

//    7         6        5        4        3        2        1        0
// seeeeeee|eeeemmmm|mmmmmmmm|mmmmmmmm|mmmmmmmm|mmmmmmmm|mmmmmmmm|mmmmmmmm
// s0000000|0000tttt|vvvvvvvv|vvvvvvvv|vvvvvvvv|vvvvvvvv|vvvvvvvv|vvvvvvvv
// NaN marker   |tag|  48-bit placeholder for values: pointers, strings

// Doubles contain non-zero in NaN marker field and are stored with bits inversed
// NaN/+Inf/-Inf have special tag=JS_TAG_FLOAT64 and 0/1/2 in lower bits
// non-floats contain zero in NaN marker field and the tag in the upper 48-bit
// JS_UNINITIALIZED is strictly uint64_t(0)

procedure JSValue.SetTag(newtag: PtrInt);
begin
  u.tag := newtag shl 16;
end;

function JSValue.TagNotFloat: PtrInt;
begin
  {$ifdef CPU64}
  result := u.u64 shr 48;
  {$else}
  result := u.tag shr 16;
  {$endif CPU64}
end;

function JSValue.NormTag: PtrInt;
begin
  {$ifdef CPU64}
  result := u.u64;
  if PtrUInt(result) > JS_TAG_MASK then
    result := JS_TAG_FLOAT64
  else
    result := result shr 48;
  {$else}
  if u.u64 > JS_TAG_MASK then
    result := JS_TAG_FLOAT64
  else
    result := u.tag shr 16;
  {$endif CPU64}
end;

function JSValue.IsNan: boolean;
begin
  result := (u.u64 = JS_NAN) or
            (u.u64 = JS_INFINITY_NEGATIVE) or
            (u.u64 = JS_INFINITY_POSITIVE);
end;

function JSValue.IsFloat: boolean;
begin
  result := (u.u64 > JS_TAG_MASK) or
            (u.u64 shr 48 = JS_TAG_FLOAT64); // Nan/+Inf/-Inf
end;

function JSValue.F64: double;
var
  v: JSValue;
  i: UInt64;
begin
  i := u.u64;
  if i > JS_TAG_MASK then
  begin
    // the float value is stored bit inverted
    v.u.u64 := not i;
    result := v.u.f64;
  end
  else
    // Nan/+Inf/-Inf are seldom encountered
    if i = JS_NAN then
        result := JS_FLOAT64_NAN
      else if i = JS_INFINITY_POSITIVE then
        result := JS_FLOAT64_POSINF
      else
        result := JS_FLOAT64_NEGINF;
end;

function NanFrom(val: double): JSValueRaw;
begin
  if math.IsNan(val) then
    result := JS_NAN
  else if val < 0.0 then
    result := JS_INFINITY_NEGATIVE
  else
    result := JS_INFINITY_POSITIVE;
end;

procedure JSValue.FloatFrom(val: double);
begin
  u.f64 := val;
  if u.u64 and $7ff0000000000000 = $7ff0000000000000 then
    // normalize NaN/+Inf/-Inf
    u.u64 := NanFrom(val)
  else
    // the float value is stored bit inverted
    u.u64 := not u.u64;
end;

function JSValue.IsRefCounted: boolean;
// inlined (NormTag and $fff8) = 8
{$ifdef CPU64}
var
  t: UInt64;
begin
  t := u.u64;
  result := (t <= JS_TAG_MASK) and
            (((t shr 48) and $fff8) = $0008);
end;
{$else}
begin
  result := (u.u64 <= JS_TAG_MASK) and
            ((u.tag and $fff80000) = $00080000);
end;
{$endif CPU64}

function JSValue.IsException: boolean;
begin
  result := TagNotFloat = JS_TAG_EXCEPTION;
end;

{$else}

{$ifdef JS_NAN_BOXING}

procedure JSValue.SetTag(newtag: PtrInt);
begin
  u.tag := newtag;
end;

function JSValue.IsNan: boolean;
begin
  result := u.u64 = JS_NAN;
end;

function JSValue.IsFloat: boolean;
begin
  result := PtrUInt(u.tag - JS_TAG_FIRST) >= PtrUInt(JS_TAG_FLOAT64 - JS_TAG_FIRST);
end;

function JSValue.TagNotFloat: PtrInt;
begin
  result := u.tag;
end;

function JSValue.NormTag: PtrInt;
begin
  if IsFloat then
    result := JS_TAG_FLOAT64
  else
    result := u.tag;
end;

function JSValue.F64: double;
begin
  inc(u.tag, JS_FLOAT64_TAG_ADDEND);
  result := u.f64;
  dec(u.tag, JS_FLOAT64_TAG_ADDEND);
end;

procedure JSValue.FloatFrom(val: double);
begin
  u.f64 := val;
  if u.u64 and $7fffffffffffffff > $7ff0000000000000 then
    // normalize NaN
    u.u64 := JS_NAN
  else
    // see JSValue.F64()
    dec(u.tag, JS_FLOAT64_TAG_ADDEND);
end;

function JSValue.IsRefCounted: boolean;
begin
  result := PtrUInt(u.tag) >= PtrUInt(JS_TAG_FIRST);
end;

function JSValue.IsException: boolean;
begin
  result := u.tag = JS_TAG_EXCEPTION;
end;

{$else}

procedure JSValue.SetTag(newtag: PtrInt);
begin
  UnboxedTag := newtag;
end;

function JSValue.TagNotFloat: PtrInt;
begin
  result := UnboxedTag;
end;

function JSValue.NormTag: PtrInt;
begin
  result := UnboxedTag; // no JS_NAN_BOXING to normalize
end;

function JSValue.IsFloat: boolean;
begin
  result := UnboxedTag = JS_TAG_FLOAT64;
end;

function JSValue.IsNan: boolean;
begin
  result := (UnboxedTag = JS_TAG_FLOAT64) and
            ((u.u64 and $7fffffffffffffff) > $7ff0000000000000);
end;

function JSValue.F64: double;
begin
  result := u.f64;
end;

procedure JSValue.FloatFrom(val: double);
begin
  UnboxedTag := JS_TAG_FLOAT64;
  u.f64 := val;
end;

function JSValue.IsRefCounted: boolean;
begin
  result := PtrUInt(UnboxedTag) >= PtrUInt(JS_TAG_FIRST);
end;

function JSValue.IsException: boolean;
begin
  result := UnboxedTag = JS_TAG_EXCEPTION;
end;

{$endif JS_NAN_BOXING}

{$endif JS_STRICT_NAN_BOXING}

function JSValue.IsNull: boolean;
begin
  result := TagNotFloat = JS_TAG_NULL;
end;

function JSValue.IsUndefined: boolean;
begin
  result := TagNotFloat = JS_TAG_UNDEFINED;
end;

function JSValue.IsUninitialized: boolean;
begin
  result := TagNotFloat = JS_TAG_UNINITIALIZED;
end;

function JSValue.IsString: boolean;
begin
  result := TagNotFloat = JS_TAG_STRING;
end;

function JSValue.IsObject: boolean;
begin
  result := TagNotFloat = JS_TAG_OBJECT;
end;

function JSValue.IsSymbol: boolean;
begin
  result := TagNotFloat = JS_TAG_SYMBOL;
end;

function JSValue.IsInt32: boolean;
begin
  result := TagNotFloat = JS_TAG_INT;
end;

function JSValue.IsNumber: boolean;
begin
  result := NormTag in [JS_TAG_FLOAT64, JS_TAG_INT];
end;

function JSValue.IsBigInt: boolean;
begin
  result := TagNotFloat = JS_TAG_BIG_INT;
end;

function JSValue.IsBigFloat: boolean;
begin
  result := TagNotFloat = JS_TAG_BIG_FLOAT;
end;

function JSValue.IsBigDecimal: boolean;
begin
  result := TagNotFloat = JS_TAG_BIG_DECIMAL;
end;

function JSValue.Duplicate: JSValue;
begin
  if IsRefCounted then
    IncRefCnt;
  result := self;
end;

function JSValue.DuplicateRaw: JSValueRaw;
begin
  if IsRefCounted then
    IncRefCnt;
  result := JSValueRaw(self);
end;

function JSValue.Int32: integer;
begin
  result := u.i32;
end;

function JSValue.Int64: Int64;
begin
  if NormTag = JS_TAG_INT then
    result := u.i32
  else
    result := round(F64);
end;

function JSValue.Bool: boolean;
begin
  result := u.i32 <> 0; // normalize
end;

function JSValue.Ptr: pointer;
begin
  result := u.ptr;
  {$ifdef JS_ANY_NAN_BOXING_CPU64}
  PtrUInt(result) := PtrUInt(result) and JS_PTR64_MASK;
  {$endif JS_ANY_NAN_BOXING_CPU64}
end;

procedure JSValue.IncRefCnt;
begin
  inc(PInteger(Ptr)^);
end;

function JSValue.DecRefCnt: boolean;
var
  prefcnt: PInteger;
  refcnt: integer;
begin
  prefcnt := Ptr;
  refcnt := prefcnt^;
  dec(refcnt);
  result := refcnt = 0;
  prefcnt^ := refcnt;
end;

function JSValue.Raw: JSValueRaw;
begin
  result := JSValueRaw(self);
end;

procedure JSValue.From(newtag, val: integer);
begin
  SetTag(newtag);
  u.i32 := val;
end;

procedure JSValue.From(newtag: integer; ptr: pointer);
begin
  SetTag(newtag);
  {$ifdef JS_ANY_NAN_BOXING_CPU64}
  if PtrUInt(ptr) > JS_PTR64_MASK then
    raise EQuickJS.CreateFmt('JSValue.From(%x) 48-bit overflow', [ptr]);
  PtrUInt(u.ptr) := PtrUInt(u.ptr) or PtrUInt(ptr); // keep upper tag bits
  {$else}
  u.ptr := ptr;
  {$endif JS_ANY_NAN_BOXING_CPU64}
end;

procedure JSValue.From(val: boolean);
begin
  SetTag(JS_TAG_BOOL);
  u.i32 := ord(val);
end;

procedure JSValue.From32(val: integer);
begin
  SetTag(JS_TAG_INT);
  u.i32 := val;
end;

procedure JSValue.From(val: Int64);
var
  d: double;
begin
  u.i32 := val;
  if val = u.i32 then
    SetTag(JS_TAG_INT)
  else
  begin
    d := val; // explicit step is needed
    FloatFrom(d);
  end;
end;

procedure JSValue.From(val: double);
var
  i: integer;
  f: double;
begin
  if val < {$ifdef FPC}double{$endif}(9E18) then // avoid round() FP overflow
  begin
    i := round(val); // in two explicit steps to truncate to 32-bit resolution
    f := i;
    u.f64 := val;
    // -0 cannot be represented as integer, so we compare the bit representation
    if PUInt64(@f)^ = u.u64 then
    begin
      u.i32 := i;
      SetTag(JS_TAG_INT);
      exit;
    end;
  end;
  FloatFrom(val);
end;



{ TJSRuntime }

function TJSRuntime.New: JSContext;
begin
  result := JS_NewContext(@self);
end;

procedure TJSRuntime.Done;
begin
  JS_FreeRuntime(@self);
end;

function TJSRuntime.DoneSafe: string;
begin
  result := '';
  try
    JS_FreeRuntime(@self);
  except
    on E: Exception do
      result := Format('%s %s', [ClassNameShort(E)^, E.Message]);
  end;
end;



{ TJSContext }

procedure TJSContext.Done;
begin
  JS_FreeContext(@self);
end;

procedure TJSContext.Free(var v: JSValueRaw);
begin
  with JSValue(v) do
    if IsRefCounted and
       DecRefCnt then
      __JS_FreeValue(@self, v);
end;

procedure TJSContext.Free(var v: JSValue);
begin
  if v.IsRefCounted and
     v.DecRefCnt then
    __JS_FreeValue(@self, JSValueRaw(v));
end;

procedure TJSContext.ToUtf8(var v: JSValue; var s: RawUtF8);
var
  P: PUtf8Char;
  len: PtrUInt;
begin
  P := JS_ToCStringLen2(@self, @len, JSValueRaw(v), false);
  FastSetString(s, P, len);
  JS_FreeCString(@self, P);
end;

procedure TJSContext.AddUtf8(var v: JSValue; var s: RawUtF8);
var
  P: PUtf8Char;
  len, sl: PtrUInt;
begin
  P := JS_ToCStringLen2(@self, @len, JSValueRaw(v), false);
  if (P = nil) or
     (len = 0) then
    exit;
  sl := length(s);
  SetLength(s, len + sl);
  MoveFast(P^, PByteArray(s)[sl], len);
  JS_FreeCString(@self, P);
end;

procedure TJSContext.ErrorMessage(stacktrace: boolean; var msg: RawUtf8;
  reason: PJSValue);
var
  e, s: JSValueRaw;
begin
  if reason = nil then
    e := JS_GetException(@self)
  else
    e := reason^.Raw;
  if stacktrace then
    stacktrace := JS_IsError(@self, e);
  ToUtF8(JSValue(e), msg);
  if msg = '' then
    msg := '[exception]'#10;
  if stacktrace then
  begin
    s := JS_GetPropertyStr(@self, e, 'stack');
    AddUtf8(JSValue(s), msg);
    Free(s);
  end;
  if reason = nil then
    Free(e);
end;

procedure TJSContext.ErrorDump(stacktrace: boolean; reason: PJSValue);
var
  err: RawUtF8;
begin
  ErrorMessage({stacktrace=}true, err, reason);
  {$I-}
  writeln(StdErr, err); // default is output to the console
  {$I+}
end;

function TJSContext.Eval(const code, fn: RawUtf8; flags: integer;
  out err: RawUtf8): JSValue;
var
  f: PAnsiChar;
  fpu: TFPUExceptionMask;
begin
  if fn = '' then
    if flags and JS_EVAL_TYPE_MASK <> JS_EVAL_TYPE_GLOBAL then
      raise EQuickJS.CreateFmt('JSContext.Eval(%s,%d)', [fn, flags])
    else
      f := 'main' // only global scope is allowed without file name
  else
    f := pointer(fn);
  fpu := BeforeLibraryCall;
  try
    result := JSValue(JS_Eval(@self, pointer(code), length(code), f, flags));
    if result.IsException then
      ErrorMessage({stack=}true, err);
  finally
    AfterLibraryCall(fpu);
  end;
end;

function TJSContext.EvalGlobal(const code: RawUtf8;
  const filename: RawUtf8): RawUtf8;
var
  v: JSValue;
begin
  v := Eval(code, filename, JS_EVAL_TYPE_GLOBAL, result);
  Free(v);
end;

function TJSContext.EvalModule(const code, filename: RawUtf8): RawUtf8;
var
  v: JSValue;
begin
  v := Eval(code, filename, JS_EVAL_FLAG_MODULE_COMPILE_ONLY, result);
  if result = '' then
  begin
    // in two steps (compile+eval) to set import.meta
    js_module_set_import_meta(@self, JSValueRaw(v), {realfilename=}false, {main=}false);
    v := JSValue(JS_EvalFunction(@self, JSValueRaw(v)));
    if v.IsException then
      ErrorMessage({stack=}true, result);
  end;
  Free(v);
end;

function TJSContext.ToVariantType(var v: JSValue): integer;
begin
  case v.NormTag of
    JS_TAG_STRING:
      result := varString;
    JS_TAG_OBJECT:
      result := varAny;
    JS_TAG_INT:
      result := varInteger;
    JS_TAG_BOOL:
      result := varBoolean;
    JS_TAG_NULL:
      result := varNull;
    JS_TAG_UNDEFINED,
    JS_TAG_UNINITIALIZED:
      result := varEmpty;
    JS_TAG_BIG_DECIMAL,
    JS_TAG_BIG_FLOAT,
    JS_TAG_FLOAT64:
      result := varDouble;
    JS_TAG_BIG_INT:
      result := varInt64;
  else
    {
    JS_TAG_SYMBOL,
    JS_TAG_CATCH_OFFSET,
    JS_TAG_EXCEPTION,
    }
    result := varUnknown;
  end;
end;

function TJSContext.ToSimpleVariant(var v: JSValue; var res: variant): boolean;
var
  json: JSValueRaw;
  fpu: TFPUExceptionMask;
begin
  VarClear(res);
  with TVarData(res) do
    case v.NormTag of
      JS_TAG_STRING:
        begin
          vType := varString;
          vAny := nil; // avoid GPF when assigning the RawUtf8
          ToUtf8(v, RawUtf8(VAny));
        end;
      JS_TAG_OBJECT:
        begin
          fpu := BeforeLibraryCall;
          json := JS_JSONStringify(@self, JSValueRaw(v), JS_NULL, JS_NULL);
          result := ToSimpleVariantFree(JSValue(json), res);
          AfterLibraryCall(fpu);
          exit;
        end;
      JS_TAG_INT:
        begin
          vType := varInteger;
          vInteger := v.Int32;
        end;
      JS_TAG_BIG_INT:
        begin
          vType := varInt64;
          result := JS_ToInt64Ext(@self, @vInt64, JSValueRaw(v)) = 0;
          exit;
        end;
      JS_TAG_BOOL:
        begin
          vType := varBoolean;
          vInteger := ord(v.Bool);
        end;
      JS_TAG_NULL:
        vType := varNull;
      JS_TAG_UNDEFINED,
      JS_TAG_UNINITIALIZED:
        vType := varEmpty;
      JS_TAG_BIG_DECIMAL,
      JS_TAG_BIG_FLOAT:
          if JS_ToFloat64(@self, @vDouble, JSValueRaw(v)) = 0 then
            vType := varDouble;
      JS_TAG_FLOAT64:
        begin
          vType := varDouble;
          vDouble := v.F64;
        end;
    else
      {
      JS_TAG_SYMBOL,
      JS_TAG_CATCH_OFFSET,
      JS_TAG_EXCEPTION,
      }
      begin
        result := false; // unsupported type
        exit;
      end;
    end;
  result := true;
end;

function TJSContext.ToSimpleVariantFree(var v: JSValue; var res: variant): boolean;
begin
  result := ToSimpleVariant(v, res);
  Free(v);
end;

function TJSContext.From(P: PUtf8Char; Len: PtrInt): JSValue;
begin
  result := JSValue(JS_NewStringLen(@self, P, Len));
end;

function TJSContext.FromW(P: PWideChar; Len: PtrInt): JSValue;
var
  tmp: TSynTempBuffer; // avoid most memory allocations
  W: integer;
begin
  if (P = nil) or (Len = 0) then
    result := From(nil, 0)
  else
  begin
    tmp.Init(Len * 3);
    W := RawUnicodeToUtf8(tmp.buf, tmp.len, P, Len, []);
    result := From(tmp.buf, W);
    tmp.Done;
  end;
end;

function TJSContext.From(const val: RawUtF8): JSValue;
begin
  result := From(pointer(val), length(val));
end;

function TJSContext.FromW(const val: SynUnicode): JSValue;
begin
  result := FromW(pointer(val), length(val));
end;


initialization
  assert(SizeOf(JSValueRaw) = SizeOf(JSValue));
  {$ifdef JS_STRICT_NAN_BOXING}
  assert(SizeOf(JSValueRaw) = SizeOf(double));
  {$else}
  assert(SizeOf(JSValueRaw) = 2 * SizeOf(pointer));
  {$endif JS_STRICT_NAN_BOXING}
  { special constant values }
  JSValue(JS_NULL).From(JS_TAG_NULL, 0);
  JSValue(JS_UNDEFINED).From(JS_TAG_UNDEFINED, 0);
  JSValue(JS_FALSE).From(JS_TAG_BOOL, 0);
  JSValue(JS_TRUE).From(JS_TAG_BOOL, 1);
  JSValue(JS_EXCEPTION).From(JS_TAG_EXCEPTION);
  JSValue(JS_UNINITIALIZED).From(JS_TAG_UNINITIALIZED, 0);
  {$ifndef JS_ANY_NAN_BOXING}
  JSValue(JS_NAN).UnboxedTag := JS_TAG_FLOAT64;
  JSValue(JS_NAN).u.f64 := JS_FLOAT64_NAN;
  {$endif JS_ANY_NAN_BOXING}

{$else}

implementation // compiles as a void unit if QuickJS is not supported

{$endif LIBQUICKJS}

end.

