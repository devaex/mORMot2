/// Framework Core Low-Level JSON Processing
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.core.json;

{
  *****************************************************************************

   JSON functions shared by all framework units
    - Low-Level JSON Processing Functions
    - TTextWriter class with proper JSON escaping and WriteObject() support
    - JSON-aware TSynNameValue TSynPersistentStoreJson TRawByteStringGroup
    - JSON-aware TSynDictionary Storage
    - JSON Unserialization for any kind of Values
    - JSON Serialization Wrapper Functions
    - Abstract Classes with Auto-Create-Fields

  *****************************************************************************
}

interface

{$I ..\mormot.defines.inc}

uses
  classes,
  contnrs,
  sysutils,
  {$ifndef FPC}
  typinfo, // for proper Delphi inlining
  {$endif FPC}
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.rtti,
  mormot.core.buffers,
  mormot.core.data;


{ ********** Low-Level JSON Processing Functions }

type
  /// exception raised by this unit, in relation to raw JSON process
  EJSONException = class(ESynException);

  /// kind of character used from JSON_CHARS[] for efficient JSON parsing
  // - using such a set compiles into TEST [MEM], IMM so is more efficient
  // than a regular set of AnsiChar which generates much slower BT [MEM], IMM
  // - the same 256-byte memory will also be reused from L1 CPU cache
  // during the parsing of complex JSON input
  TJsonChar = set of (
    jcJsonIdentifierFirstChar,
    jcJsonIdentifier,
    jcEndOfJsonFieldOr0,
    jcEndOfJsonFieldNotName,
    jcEndOfJsonValueField,
    jcJsonStringMarker,
    jcDigitFirstChar,
    jcDigitFloatChar);

  /// defines a lookup table used for branch-less JSON parsing
  TJsonCharSet = array[AnsiChar] of TJsonChar;
  /// points to a lookup table used for branch-less JSON parsing
  PJsonCharSet = ^TJsonCharSet;

var
  /// 256-byte lookup table for fast branchless JSON text escaping
  // - 0 = JSON_ESCAPE_NONE indicates no escape needed
  // - 1 = JSON_ESCAPE_ENDINGZERO indicates #0 (end of string)
  // - 2 = JSON_ESCAPE_UNICODEHEX should be escaped as \u00xx
  // - b,t,n,f,r,\," as escaped character for #8,#9,#10,#12,#13,\,"
  JSON_ESCAPE: array[byte] of byte;

const
  /// JSON_ESCAPE[] lookup value: indicates no escape needed
  JSON_ESCAPE_NONE = 0;
  /// JSON_ESCAPE[] lookup value: indicates #0 (end of string)
  JSON_ESCAPE_ENDINGZERO = 1;
  /// JSON_ESCAPE[] lookup value: should be escaped as \u00xx
  JSON_ESCAPE_UNICODEHEX = 2;

var
  /// 256-byte lookup table for fast branchless JSON parsing
  // - to be used e.g. as:
  // ! if jvJsonIdentifier in JSON_CHARS[P^] then ...
  JSON_CHARS: TJsonCharSet;


/// returns TRUE if the given text buffers would be escaped when written as JSON
// - e.g. if contains " or \ characters, as defined by
// http://www.ietf.org/rfc/rfc4627.txt
function NeedsJsonEscape(const Text: RawUtf8): boolean; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// returns TRUE if the given text buffers would be escaped when written as JSON
// - e.g. if contains " or \ characters, as defined by
// http://www.ietf.org/rfc/rfc4627.txt

function NeedsJsonEscape(P: PUtf8Char): boolean; overload;

/// returns TRUE if the given text buffers would be escaped when written as JSON
// - e.g. if contains " or \ characters, as defined by
// http://www.ietf.org/rfc/rfc4627.txt
function NeedsJsonEscape(P: PUtf8Char; PLen: integer): boolean; overload;

/// UTF-8 encode one or two \u#### JSON escaped codepoints into Dest
// - P^ should point at 'u1234' just after \u1234
// - return ending P position, maybe after another \u#### UTF-16 surrogate char
function JsonEscapeToUtf8(var D: PUtf8Char; P: PUtf8Char): PUtf8Char;
  {$ifdef HASINLINE}inline;{$endif}

/// test if the supplied buffer is a "string" value or a numerical value
// (floating point or integer), according to the characters within
// - this version will recognize null/false/true as strings
// - e.g. IsString('0')=false, IsString('abc')=true, IsString('null')=true
function IsString(P: PUtf8Char): boolean;

/// test if the supplied buffer is a "string" value or a numerical value
// (floating or integer), according to the JSON encoding schema
// - this version will NOT recognize JSON null/false/true as strings
// - e.g. IsStringJson('0')=false, IsStringJson('abc')=true,
// but IsStringJson('null')=false
// - will follow the JSON definition of number, i.e. '0123' is a string (i.e.
// '0' is excluded at the begining of a number) and '123' is not a string
function IsStringJson(P: PUtf8Char): boolean;

/// test if the supplied buffer is a correct JSON value
function IsValidJson(P: PUtf8Char; len: PtrInt): boolean; overload;

/// test if the supplied buffer is a correct JSON value
function IsValidJson(const s: RawUtf8): boolean; overload;

/// simple method to go after the next ',' character
procedure IgnoreComma(var P: PUtf8Char);
  {$ifdef HASINLINE}inline;{$endif}

/// returns TRUE if the given text buffer contains simple characters as
// recognized by JSON extended syntax
// - follow GetJsonPropName and GotoNextJsonObjectOrArray expectations
function JsonPropNameValid(P: PUtf8Char): boolean;
  {$ifdef HASINLINE}inline;{$endif}

/// decode a JSON field value in-place from an UTF-8 encoded text buffer
// - this function decodes in the P^ buffer memory itself (no memory allocation
// or copy), for faster process - so take care that P^ is not shared
// - works for both field names or values (e.g. '"FieldName":' or 'Value,')
// - EndOfObject (if not nil) is set to the JSON value char (',' ':' or '}' e.g.)
// - optional WasString is set to true if the JSON value was a JSON "string"
// - returns a PUtf8Char to the decoded value, with its optional length in Len^
// - '"strings"' are decoded as 'strings', with WasString=true, properly JSON
// unescaped (e.g. any \u0123 pattern would be converted into UTF-8 content)
// - null is decoded as nil, with WasString=false
// - true/false boolean values are returned as 'true'/'false', with WasString=false
// - any number value is returned as its ascii representation, with WasString=false
// - PDest points to the next field to be decoded, or nil on JSON parsing error
function GetJsonField(P: PUtf8Char; out PDest: PUtf8Char;
  WasString: PBoolean = nil; EndOfObject: PUtf8Char = nil;
  Len: PInteger = nil): PUtf8Char;

/// decode a JSON field name in an UTF-8 encoded buffer
// - this function decodes in the P^ buffer memory itself (no memory allocation
// or copy), for faster process - so take care that P^ is not shared
// - it will return the property name (with an ending #0) or nil on error
// - this function will handle strict JSON property name (i.e. a "string"), but
// also MongoDB extended syntax, e.g. {age:{$gt:18}} or {'people.age':{$gt:18}}
// see @http://docs.mongodb.org/manual/reference/mongodb-extended-json
function GetJsonPropName(var P: PUtf8Char; Len: PInteger = nil): PUtf8Char; overload;

/// decode a JSON field name in an UTF-8 encoded shortstring variable
// - this function would left the P^ buffer memory untouched, so may be safer
// than the overloaded GetJsonPropName() function in some cases
// - it will return the property name as a local UTF-8 encoded shortstring,
// or PropName='' on error
// - this function won't unescape the property name, as strict JSON (i.e. a "st\"ring")
// - but it will handle MongoDB syntax, e.g. {age:{$gt:18}} or {'people.age':{$gt:18}}
// see @http://docs.mongodb.org/manual/reference/mongodb-extended-json
procedure GetJsonPropName(var P: PUtf8Char; out PropName: shortstring); overload;

/// decode a JSON content in an UTF-8 encoded buffer
// - GetJsonField() will only handle JSON "strings" or numbers - if
// HandleValuesAsObjectOrArray is TRUE, this function will process JSON {
// objects } or [ arrays ] and add a #0 at the end of it
// - this function decodes in the P^ buffer memory itself (no memory allocation
// or copy), for faster process - so take care that it is an unique string
// - returns a pointer to the value start, and moved P to the next field to
// be decoded, or P=nil in case of any unexpected input
// - WasString is set to true if the JSON value was a "string"
// - EndOfObject (if not nil) is set to the JSON value end char (',' ':' or '}')
// - if Len is set, it will contain the length of the returned pointer value
function GetJsonFieldOrObjectOrArray(var P: PUtf8Char;
  WasString: PBoolean = nil; EndOfObject: PUtf8Char = nil;
  HandleValuesAsObjectOrArray: boolean = false;
  NormalizeBoolean: boolean = true; Len: PInteger = nil): PUtf8Char;

/// retrieve the next JSON item as a RawJson variable
// - buffer can be either any JSON item, i.e. a string, a number or even a
// JSON array (ending with ]) or a JSON object (ending with })
// - EndOfObject (if not nil) is set to the JSON value end char (',' ':' or '}')
procedure GetJsonItemAsRawJson(var P: PUtf8Char; var result: RawJson;
  EndOfObject: PAnsiChar = nil);

/// retrieve the next JSON item as a RawUtf8 decoded buffer
// - buffer can be either any JSON item, i.e. a string, a number or even a
// JSON array (ending with ]) or a JSON object (ending with })
// - EndOfObject (if not nil) is set to the JSON value end char (',' ':' or '}')
// - just call GetJsonField(), and create a new RawUtf8 from the returned value,
// after proper unescape if WasString^=true
function GetJsonItemAsRawUtf8(var P: PUtf8Char; var output: RawUtf8;
  WasString: PBoolean = nil; EndOfObject: PUtf8Char = nil): boolean;

/// read the position of the JSON value just after a property identifier
// - this function will handle strict JSON property name (i.e. a "string"), but
// also MongoDB extended syntax, e.g. {age:{$gt:18}} or {'people.age':{$gt:18}}
// see @http://docs.mongodb.org/manual/reference/mongodb-extended-json
function GotoNextJsonPropName(P: PUtf8Char): PUtf8Char;

/// get the next character after a quoted buffer
// - the first character in P^ must be "
// - it will return the latest " position, ignoring \" within
// - caller should check that return PUtf8Char is indeed a "
function GotoEndOfJsonString(P: PUtf8Char): PUtf8Char; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// get the next character after a quoted buffer
// - the first character in P^ must be "
// - it will return the latest " position, ignoring \" within
// - overloaded version when JSON_CHARS table is already available locally
function GotoEndOfJsonString(P: PUtf8Char; tab: PJsonCharSet): PUtf8Char; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// reach positon just after the current JSON item in the supplied UTF-8 buffer
// - buffer can be either any JSON item, i.e. a string, a number or even a
// JSON array (ending with ]) or a JSON object (ending with })
// - returns nil if the specified buffer is not valid JSON content
// - returns the position in buffer just after the item excluding the separator
// character - i.e. result^ may be ',','}',']'
// - for speed, numbers and true/false/null constant won't be exactly checked,
// and MongoDB extended syntax like {age:{$gt:18}} will be allowed - so you
// may consider GotoEndJsonItemStrict() if you expect full standard JSON parsing
function GotoEndJsonItem(P: PUtf8Char; PMax: PUtf8Char = nil): PUtf8Char;

/// reach positon just after the current JSON item in the supplied UTF-8 buffer
// - in respect to GotoEndJsonItem(), this function will validate for strict
// JSON simple values, i.e. real numbers or only true/false/null constants,
// and refuse MongoDB extended syntax like {age:{$gt:18}}
function GotoEndJsonItemStrict(P: PUtf8Char): PUtf8Char;

/// reach the positon of the next JSON item in the supplied UTF-8 buffer
// - buffer can be either any JSON item, i.e. a string, a number or even a
// JSON array (ending with ]) or a JSON object (ending with })
// - returns nil if the specified number of items is not available in buffer
// - returns the position in buffer after the item including the separator
// character (optionally in EndOfObject) - i.e. result will be at the start of
// the next object, and EndOfObject may be ',','}',']'
function GotoNextJsonItem(P: PUtf8Char; NumberOfItemsToJump: cardinal = 1;
  EndOfObject: PAnsiChar = nil): PUtf8Char;

/// reach the position of the next JSON object of JSON array
// - first char is expected to be either '[' or '{'
// - will return nil in case of parsing error or unexpected end (#0)
// - will return the next character after ending ] or } - i.e. may be , } ]
function GotoNextJsonObjectOrArray(P: PUtf8Char): PUtf8Char; overload;
  {$ifdef FPC}inline;{$endif}

/// reach the position of the next JSON object of JSON array
// - first char is expected to be just after the initial '[' or '{'
// - specify ']' or '}' as the expected EndChar
// - will return nil in case of parsing error or unexpected end (#0)
// - will return the next character after ending ] or } - i.e. may be , } ]
function GotoNextJsonObjectOrArray(P: PUtf8Char;
  EndChar: AnsiChar): PUtf8Char; overload;
  {$ifdef FPC}inline;{$endif}

/// reach the position of the next JSON object of JSON array
// - first char is expected to be either '[' or '{'
// - this version expects a maximum position in PMax: it may be handy to break
// the parsing for HUGE content - used e.g. by JsonArrayCount(P,PMax)
// - will return nil in case of parsing error or if P reached PMax limit
// - will return the next character after ending ] or { - i.e. may be , } ]
function GotoNextJsonObjectOrArrayMax(P, PMax: PUtf8Char): PUtf8Char;
  {$ifdef FPC}inline;{$endif}

/// search the EndOfObject of a JSON buffer, just like GetJsonField() does
function ParseEndOfObject(P: PUtf8Char; out EndOfObject: AnsiChar): PUtf8Char;
  {$ifdef HASINLINE}inline;{$endif}

/// compute the number of elements of a JSON array
// - this will handle any kind of arrays, including those with nested
// JSON objects or arrays
// - incoming P^ should point to the first char AFTER the initial '[' (which
// may be a closing ']')
// - returns -1 if the supplied input is invalid, or the number of identified
// items in the JSON array buffer
function JsonArrayCount(P: PUtf8Char): integer; overload;

/// compute the number of elements of a JSON array
// - this will handle any kind of arrays, including those with nested
// JSON objects or arrays
// - incoming P^ should point to the first char after the initial '[' (which
// may be a closing ']')
// - this overloaded method will abort if P reaches a certain position, and
// return the current counted number of items as negative, which could be used
// as initial allocation before the loop - typical use in this case is e.g.
// ! cap := abs(JsonArrayCount(P, P + 256 shl 10));
function JsonArrayCount(P, PMax: PUtf8Char): integer; overload;

/// go to the #nth item of a JSON array
// - implemented via a fast SAX-like approach: the input buffer is not changed,
// nor no memory buffer allocated neither content copied
// - returns nil if the supplied index is out of range
// - returns a pointer to the index-nth item in the JSON array (first index=0)
// - this will handle any kind of arrays, including those with nested
// JSON objects or arrays
// - incoming P^ should point to the first initial '[' char
function JsonArrayItem(P: PUtf8Char; Index: integer): PUtf8Char;

/// retrieve the positions of all elements of a JSON array
// - this will handle any kind of arrays, including those with nested
// JSON objects or arrays
// - incoming P^ should point to the first char AFTER the initial '[' (which
// may be a closing ']')
// - returns false if the supplied input is invalid
// - returns true on success, with Values[] pointing to each unescaped value,
// may be a JSON string, object, array of constant
function JsonArrayDecode(P: PUtf8Char;
  out Values: TPUtf8CharDynArray): boolean;

/// compute the number of fields in a JSON object
// - this will handle any kind of objects, including those with nested
// JSON objects or arrays
// - incoming P^ should point to the first char after the initial '{' (which
// may be a closing '}')
function JsonObjectPropCount(P: PUtf8Char): integer;

/// go to a named property of a JSON object
// - implemented via a fast SAX-like approach: the input buffer is not changed,
// nor no memory buffer allocated neither content copied
// - returns nil if the supplied property name does not exist
// - returns a pointer to the matching item in the JSON object
// - this will handle any kind of objects, including those with nested
// JSON objects or arrays
// - incoming P^ should point to the first initial '{' char
function JsonObjectItem(P: PUtf8Char; const PropName: RawUtf8;
  PropNameFound: PRawUtf8 = nil): PUtf8Char;

/// go to a property of a JSON object, by its full path, e.g. 'parent.child'
// - implemented via a fast SAX-like approach: the input buffer is not changed,
// nor no memory buffer allocated neither content copied
// - returns nil if the supplied property path does not exist
// - returns a pointer to the matching item in the JSON object
// - this will handle any kind of objects, including those with nested
// JSON objects or arrays
// - incoming P^ should point to the first initial '{' char
function JsonObjectByPath(JsonObject, PropPath: PUtf8Char): PUtf8Char;

/// return all matching properties of a JSON object
// - here the PropPath could be a comma-separated list of full paths,
// e.g. 'Prop1,Prop2' or 'Obj1.Obj2.Prop1,Obj1.Prop2'
// - returns '' if no property did match
// - returns a JSON object of all matching properties
// - this will handle any kind of objects, including those with nested
// JSON objects or arrays
// - incoming P^ should point to the first initial '{' char
function JsonObjectsByPath(JsonObject, PropPath: PUtf8Char): RawUtf8;

/// convert one JSON object into two JSON arrays of keys and values
// - i.e. makes the following transformation:
// $ {key1:value1,key2,value2...} -> [key1,key2...] + [value1,value2...]
// - this function won't allocate any memory during its process, nor
// modify the JSON input buffer
// - is the reverse of the TTextWriter.AddJsonArraysAsJsonObject() method
// - used e.g. by TSynDictionary.LoadFromJson
function JsonObjectAsJsonArrays(Json: PUtf8Char;
  out keys, values: RawUtf8): boolean;

/// remove comments and trailing commas from a text buffer before passing
// it to a JSON parser
// - handle two types of comments: starting from // till end of line
// or /* ..... */ blocks anywhere in the text content
// - trailing commas is replaced by ' ', so resulting JSON is valid for parsers
// what not allows trailing commas (browsers for example)
// - may be used to prepare configuration files before loading;
// for example we store server configuration in file config.json and
// put some comments in this file then code for loading is:
// !var cfg: RawUtf8;
// !  cfg := StringFromFile(ExtractFilePath(paramstr(0))+'Config.json');
// !  RemoveCommentsFromJson(@cfg[1]);
// !  pLastChar := JsonToObject(sc,pointer(cfg),configValid);
procedure RemoveCommentsFromJson(P: PUtf8Char); overload;

/// remove comments from a text buffer before passing it to JSON parser
// - won't remove the comments in-place, but allocate a new string
function RemoveCommentsFromJson(const s: RawUtf8): RawUtf8; overload;

/// helper to retrieve the bit mapped integer value of a set from its JSON text
// - Names and MaxValue should be retrieved from RTTI
// - if supplied P^ is a JSON integer number, will read it directly
// - if P^ maps some ["item1","item2"] content, would fill all matching bits
// - if P^ contains ['*'], would fill all bits
// - returns P=nil if reached prematurely the end of content, or returns
// the value separator (e.g. , or }) in EndOfObject (like GetJsonField)
function GetSetNameValue(Names: PShortString; MaxValue: integer;
  var P: PUtf8Char; out EndOfObject: AnsiChar): QWord; overload;

/// helper to retrieve the bit mapped integer value of a set from its JSON text
// - overloaded function using the RTTI
function GetSetNameValue(Info: PRttiInfo;
  var P: PUtf8Char; out EndOfObject: AnsiChar): QWord; overload;

type
  /// points to one value of raw UTF-8 content, decoded from a JSON buffer
  // - used e.g. by JsonDecode() overloaded function to returns names/values
  TValuePUtf8Char = object
  public
    /// a pointer to the actual UTF-8 text
    Value: PUtf8Char;
    /// how many UTF-8 bytes are stored in Value
    ValueLen: PtrInt;
    /// convert the value into a UTF-8 string
    procedure ToUtf8(var Text: RawUtf8); overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// convert the value into a UTF-8 string
    function ToUtf8: RawUtf8; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// convert the value into a VCL/generic string
    function ToString: string;
      {$ifdef HASINLINE}inline;{$endif}
    /// convert the value into a signed integer
    function ToInteger: PtrInt;
      {$ifdef HASINLINE}inline;{$endif}
    /// convert the value into an unsigned integer
    function ToCardinal: PtrUInt;
      {$ifdef HASINLINE}inline;{$endif}
    /// will call IdemPropNameU() over the stored text Value
    function Idem(const Text: RawUtf8): boolean;
      {$ifdef HASINLINE}inline;{$endif}
  end;
  /// used e.g. by JsonDecode() overloaded function to returns values
  TValuePUtf8CharArray =
    array[0 .. maxInt div SizeOf(TValuePUtf8Char) - 1] of TValuePUtf8Char;
  PValuePUtf8CharArray = ^TValuePUtf8CharArray;

  /// store one name/value pair of raw UTF-8 content, from a JSON buffer
  // - used e.g. by JsonDecode() overloaded function or UrlEncodeJsonObject()
  // to returns names/values
  TNameValuePUtf8Char = record
    /// a pointer to the actual UTF-8 name text
    Name: PUtf8Char;
    /// a pointer to the actual UTF-8 value text
    Value: PUtf8Char;
    /// how many UTF-8 bytes are stored in Name (should be integer, not PtrInt)
    NameLen: integer;
    /// how many UTF-8 bytes are stored in Value
    ValueLen: integer;
  end;

  /// used e.g. by JsonDecode() overloaded function to returns name/value pairs
  TNameValuePUtf8CharDynArray = array of TNameValuePUtf8Char;

/// decode the supplied UTF-8 JSON content for the supplied names
// - data will be set in Values, according to the Names supplied e.g.
// ! JsonDecode(JSON,['name','year'],@Values) -> Values[0].Value='John'; Values[1].Value='1972';
// - if any supplied name wasn't found its corresponding Values[] will be nil
// - this procedure will decode the JSON content in-memory, i.e. the PUtf8Char
// array is created inside JSON, which is therefore modified: make a private
// copy first if you want to reuse the JSON content
// - if HandleValuesAsObjectOrArray is TRUE, then this procedure will handle
// JSON arrays or objects
// - support enhanced JSON syntax, e.g. '{name:'"John",year:1972}' is decoded
// just like '{"name":'"John","year":1972}'
procedure JsonDecode(var Json: RawUtf8; const Names: array of RawUtf8;
  Values: PValuePUtf8CharArray;
  HandleValuesAsObjectOrArray: boolean = false); overload;

/// decode the supplied UTF-8 JSON content for the supplied names
// - an overloaded function when the JSON is supplied as a RawJson variable
procedure JsonDecode(var Json: RawJson; const Names: array of RawUtf8;
  Values: PValuePUtf8CharArray;
  HandleValuesAsObjectOrArray: boolean = false); overload;

/// decode the supplied UTF-8 JSON content for the supplied names
// - data will be set in Values, according to the Names supplied e.g.
// ! JsonDecode(P,['name','year'],Values) -> Values[0]^='John'; Values[1]^='1972';
// - if any supplied name wasn't found its corresponding Values[] will be nil
// - this procedure will decode the JSON content in-memory, i.e. the PUtf8Char
// array is created inside P, which is therefore modified: make a private
// copy first if you want to reuse the JSON content
// - if HandleValuesAsObjectOrArray is TRUE, then this procedure will handle
// JSON arrays or objects
// - if ValuesLen is set, ValuesLen[] will contain the length of each Values[]
// - returns a pointer to the next content item in the JSON buffer
function JsonDecode(P: PUtf8Char; const Names: array of RawUtf8;
  Values: PValuePUtf8CharArray;
  HandleValuesAsObjectOrArray: boolean = false): PUtf8Char; overload;

/// decode the supplied UTF-8 JSON content into an array of name/value pairs
// - this procedure will decode the JSON content in-memory, i.e. the PUtf8Char
// array is created inside JSON, which is therefore modified: make a private
// copy first if you want to reuse the JSON content
// - the supplied JSON buffer should stay available until Name/Value pointers
// from returned Values[] are accessed
// - if HandleValuesAsObjectOrArray is TRUE, then this procedure will handle
// JSON arrays or objects
// - support enhanced JSON syntax, e.g. '{name:'"John",year:1972}' is decoded
// just like '{"name":'"John","year":1972}'
function JsonDecode(P: PUtf8Char; out Values: TNameValuePUtf8CharDynArray;
  HandleValuesAsObjectOrArray: boolean = false): PUtf8Char; overload;

/// decode the supplied UTF-8 JSON content for the one supplied name
// - this function will decode the JSON content in-memory, so will unescape it
// in-place: it must be called only once with the same JSON data
function JsonDecode(var Json: RawUtf8; const aName: RawUtf8 = 'result';
  WasString: PBoolean = nil;
  HandleValuesAsObjectOrArray: boolean = false): RawUtf8; overload;

/// retrieve a pointer to JSON string field content, without unescaping it
// - returns either ':' for name field, or } , for value field
// - returns nil on JSON content error
// - this function won't touch the JSON buffer, so you can call it before
// using in-place escape process via JsonDecode() or GetJsonField()
function JsonRetrieveStringField(P: PUtf8Char; out Field: PUtf8Char;
  out FieldLen: integer; ExpectNameField: boolean): PUtf8Char;
  {$ifdef HASINLINE}inline;{$endif}

/// retrieve a class Rtti, as saved by ObjectToJson(...,[...,woStoreClassName,...]);
// - JSON input should be either 'null', either '{"ClassName":"TMyClass",...}'
// - calls IdemPropName/JsonRetrieveStringField so input buffer won't be
// modified, but caller should ignore this "ClassName" property later on
// - the corresponding class shall have been previously registered by
// Rtti.RegisterClass(), in order to retrieve the class type from it name -
// or, at least, by the RTL Classes.RegisterClass() function, if AndGlobalFindClass
// parameter is left to default true so that RTL Classes.FindClass() is called
function JsonRetrieveObjectRttiCustom(var Json: PUtf8Char;
  AndGlobalFindClass: boolean): TRttiCustom;

/// encode a JSON object UTF-8 buffer into URI parameters
// - you can specify property names to ignore during the object decoding
// - you can omit the leading query delimiter ('?') by setting IncludeQueryDelimiter=false
// - warning: the ParametersJson input buffer will be modified in-place
function UrlEncodeJsonObject(const UriName: RawUtf8; ParametersJson: PUtf8Char;
  const PropNamesToIgnore: array of RawUtf8;
  IncludeQueryDelimiter: boolean = true): RawUtf8; overload;

/// encode a JSON object UTF-8 buffer into URI parameters
// - you can specify property names to ignore during the object decoding
// - you can omit the leading query delimiter ('?') by setting IncludeQueryDelimiter=false
// - overloaded function which will make a copy of the input JSON before parsing
function UrlEncodeJsonObject(const UriName, ParametersJson: RawUtf8;
  const PropNamesToIgnore: array of RawUtf8;
  IncludeQueryDelimiter: boolean = true): RawUtf8; overload;

/// wrapper to serialize a T*ObjArray dynamic array as JSON
// - for proper serialization on Delphi 7-2009, use Rtti.RegisterObjArray()
function ObjArrayToJson(const aObjArray;
  aOptions: TTextWriterWriteObjectOptions = [woDontStoreDefault]): RawUtf8;

/// encode the supplied data as an UTF-8 valid JSON object content
// - data must be supplied two by two, as Name,Value pairs, e.g.
// ! JsonEncode(['name','John','year',1972]) = '{"name":"John","year":1972}'
// - or you can specify nested arrays or objects with '['..']' or '{'..'}':
// ! J := JsonEncode(['doc','{','name','John','abc','[','a','b','c',']','}','id',123]);
// ! assert(J='{"doc":{"name":"John","abc":["a","b","c"]},"id":123}');
// - note that, due to a Delphi compiler limitation, cardinal values should be
// type-casted to Int64() (otherwise the integer mapped value will be converted)
// - you can pass nil as parameter for a null JSON value
function JsonEncode(const NameValuePairs: array of const): RawUtf8; overload;

/// encode the supplied (extended) JSON content, with parameters,
// as an UTF-8 valid JSON object content
// - in addition to the JSON RFC specification strict mode, this method will
// handle some BSON-like extensions, e.g. unquoted field names:
// ! aJson := JsonEncode('{id:?,%:{name:?,birthyear:?}}',['doc'],[10,'John',1982]);
// - you can use nested _Obj() / _Arr() instances
// ! aJson := JsonEncode('{%:{$in:[?,?]}}',['type'],['food','snack']);
// ! aJson := JsonEncode('{type:{$in:?}}',[],[_Arr(['food','snack'])]);
// ! // will both return
// ! '{"type":{"$in":["food","snack"]}}')
// - if the mormot.db.nosql.bson unit is used in the application, the MongoDB
// Shell syntax will also be recognized to create TBsonVariant, like
// ! new Date()   ObjectId()   MinKey   MaxKey  /<jRegex>/<jOptions>
// see @http://docs.mongodb.org/manual/reference/mongodb-extended-json
// !  aJson := JsonEncode('{name:?,field:/%/i}',['acme.*corp'],['John']))
// ! // will return
// ! '{"name":"John","field":{"$regex":"acme.*corp","$options":"i"}}'
// - will call internally _JsonFastFmt() to create a temporary TDocVariant with
// all its features - so is slightly slower than other JsonEncode* functions
function JsonEncode(const Format: RawUtf8;
  const Args, Params: array of const): RawUtf8; overload;

/// encode the supplied RawUtf8 array data as an UTF-8 valid JSON array content
function JsonEncodeArrayUtf8(
  const Values: array of RawUtf8): RawUtf8; overload;

/// encode the supplied integer array data as a valid JSON array
function JsonEncodeArrayInteger(
  const Values: array of integer): RawUtf8; overload;

/// encode the supplied floating-point array data as a valid JSON array
function JsonEncodeArrayDouble(
  const Values: array of double): RawUtf8; overload;

/// encode the supplied array data as a valid JSON array content
// - if WithoutBraces is TRUE, no [ ] will be generated
// - note that, due to a Delphi compiler limitation, cardinal values should be
// type-casted to Int64() (otherwise the integer mapped value will be converted)
function JsonEncodeArrayOfConst(const Values: array of const;
  WithoutBraces: boolean = false): RawUtf8; overload;

/// encode the supplied array data as a valid JSON array content
// - if WithoutBraces is TRUE, no [ ] will be generated
// - note that, due to a Delphi compiler limitation, cardinal values should be
// type-casted to Int64() (otherwise the integer mapped value will be converted)
procedure JsonEncodeArrayOfConst(const Values: array of const;
  WithoutBraces: boolean; var result: RawUtf8); overload;

/// encode as JSON {"name":value} object, from a potential SQL quoted value
// - will unquote the SQLValue using TTextWriter.AddQuotedStringAsJson()
procedure JsonEncodeNameSQLValue(const Name, SQLValue: RawUtf8;
  var result: RawUtf8);

/// formats and indents a JSON array or document to the specified layout
// - just a wrapper around TTextWriter.AddJsonReformat() method
// - WARNING: the JSON buffer is decoded in-place, so P^ WILL BE modified
procedure JsonBufferReformat(P: PUtf8Char; out result: RawUtf8;
  Format: TTextWriterJsonFormat = jsonHumanReadable);

/// formats and indents a JSON array or document to the specified layout
// - just a wrapper around TTextWriter.AddJsonReformat, making a private
// of the supplied JSON buffer (so that JSON content  would stay untouched)
function JsonReformat(const Json: RawUtf8;
  Format: TTextWriterJsonFormat = jsonHumanReadable): RawUtf8;

/// formats and indents a JSON array or document as a file
// - just a wrapper around TTextWriter.AddJsonReformat() method
// - WARNING: the JSON buffer is decoded in-place, so P^ WILL BE modified
function JsonBufferReformatToFile(P: PUtf8Char; const Dest: TFileName;
  Format: TTextWriterJsonFormat = jsonHumanReadable): boolean;

/// formats and indents a JSON array or document as a file
// - just a wrapper around TTextWriter.AddJsonReformat, making a private
// of the supplied JSON buffer (so that JSON content  would stay untouched)
function JsonReformatToFile(const Json: RawUtf8; const Dest: TFileName;
  Format: TTextWriterJsonFormat = jsonHumanReadable): boolean;


/// convert UTF-8 content into a JSON string
// - with proper escaping of the content, and surounding " characters
procedure QuotedStrJson(const aText: RawUtf8; var result: RawUtf8;
  const aPrefix: RawUtf8 = ''; const aSuffix: RawUtf8 = ''); overload;
  {$ifdef HASINLINE}inline;{$endif}

/// convert UTF-8 buffer into a JSON string
// - with proper escaping of the content, and surounding " characters
procedure QuotedStrJson(P: PUtf8Char; PLen: PtrInt; var result: RawUtf8;
  const aPrefix: RawUtf8 = ''; const aSuffix: RawUtf8 = ''); overload;

/// convert UTF-8 content into a JSON string
// - with proper escaping of the content, and surounding " characters
function QuotedStrJson(const aText: RawUtf8): RawUtf8; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// fast Format() function replacement, handling % and ? parameters
// - will include Args[] for every % in Format
// - will inline Params[] for every ? in Format, handling special "inlined"
// parameters, as exected by our ORM or DB units, i.e. :(1234): for numerical
// values, and :('quoted '' string'): for textual values
// - if optional JsonFormat parameter is TRUE, ? parameters will be written
// as JSON escaped strings, without :(...): tokens, e.g. "quoted \" string"
// - resulting string has no length limit and uses fast concatenation
// - note that, due to a Delphi compiler limitation, cardinal values should be
// type-casted to Int64() (otherwise the integer mapped value will be converted)
// - any supplied TObject instance will be written as their class name
function FormatUtf8(const Format: RawUtf8;
  const Args, Params: array of const;
  JsonFormat: boolean = false): RawUtf8; overload;


{ ********** TTextWriter class with proper JSON escaping and WriteObject() support }

type
  /// JSON-capable TBaseWriter inherited class
  // - in addition to TBaseWriter, will handle JSON serialization of any
  // kind of value, including classes
  TTextWriter = class(TBaseWriter)
  protected
    // used by AddCRAndIndent for enums, sets and T*ObjArray comment of values
    fBlockComment: RawUtf8;
    // used by WriteObjectAsString/AddDynArrayJsonAsString methods
    fInternalJsonWriter: TTextWriter;
    procedure InternalAddFixedAnsi(Source: PAnsiChar; SourceChars: cardinal;
      AnsiToWide: PWordArray; Escape: TTextWriterKind);
    // called after TRttiCustomProp.GetValueDirect/GetValueGetter
    procedure AddRttiVarData(const Value: TRttiVarData;
      WriteOptions: TTextWriterWriteObjectOptions);
  public
    /// release all internal structures
    destructor Destroy; override;
    /// gives access to an internal temporary TTextWriter
    // - may be used to escape some JSON espaced value (i.e. escape it twice),
    // in conjunction with AddJsonEscape(Source: TTextWriter)
    function InternalJsonWriter: TTextWriter;
    /// append '[' or '{' with proper indentation
    procedure BlockBegin(Starter: AnsiChar; Options: TTextWriterWriteObjectOptions);
    /// append ',' with proper indentation
    // - warning: this will break CancelLastComma, since CRLF+tabs are added
    procedure BlockAfterItem(Options: TTextWriterWriteObjectOptions);
      {$ifdef HASINLINE}inline;{$endif}
    /// append ']' or '}' with proper indentation
    procedure BlockEnd(Stopper: AnsiChar; Options: TTextWriterWriteObjectOptions);
    /// used internally by WriteObject() when serializing a published property
    // - will call AddCRAndIndent then append "PropName":
    procedure WriteObjectPropName(PropName: PUtf8Char; PropNameLen: PtrInt;
      Options: TTextWriterWriteObjectOptions);
    /// used internally by WriteObject() when serializing a published property
    // - will call AddCRAndIndent then append "PropName":
    procedure WriteObjectPropNameShort(const PropName: shortstring;
      Options: TTextWriterWriteObjectOptions);
      {$ifdef HASINLINE}inline;{$endif}
    /// same as WriteObject(), but will double all internal " and bound with "
    // - this implementation will avoid most memory allocations
    procedure WriteObjectAsString(Value: TObject;
      Options: TTextWriterWriteObjectOptions = [woDontStoreDefault]);
    /// same as AddDynArrayJson(), but will double all internal " and bound with "
    // - this implementation will avoid most memory allocations
    procedure AddDynArrayJsonAsString(aTypeInfo: PRttiInfo; var aValue;
      WriteOptions: TTextWriterWriteObjectOptions = []);
    /// append a JSON field name, followed by an escaped UTF-8 JSON String and
    // a comma (',')
    procedure AddPropJsonString(const PropName: shortstring; const Text: RawUtf8);
    /// append a JSON field name, followed by a number value and a comma (',')
    procedure AddPropJSONInt64(const PropName: shortstring; Value: Int64);
    /// append CR+LF (#13#10) chars and #9 indentation
    // - will also flush any fBlockComment
    procedure AddCRAndIndent; override;
    /// write some #0 ended UTF-8 text, according to the specified format
    // - if Escape is a constant, consider calling directly AddNoJsonEscape,
    // AddJsonEscape or AddOnSameLine methods
    procedure Add(P: PUtf8Char; Escape: TTextWriterKind); overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// write some #0 ended UTF-8 text, according to the specified format
    // - if Escape is a constant, consider calling directly AddNoJsonEscape,
    // AddJsonEscape or AddOnSameLine methods
    procedure Add(P: PUtf8Char; Len: PtrInt; Escape: TTextWriterKind); overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// write some #0 ended Unicode text as UTF-8, according to the specified format
    // - if Escape is a constant, consider calling directly AddNoJsonEscapeW,
    // AddJsonEscapeW or AddOnSameLineW methods
    procedure AddW(P: PWord; Len: PtrInt; Escape: TTextWriterKind);
      {$ifdef HASINLINE}inline;{$endif}
    /// append some UTF-8 encoded chars to the buffer, from the main AnsiString type
    // - use the current system code page for AnsiString parameter
    procedure AddAnsiString(const s: AnsiString; Escape: TTextWriterKind); overload;
    /// append some UTF-8 encoded chars to the buffer, from any AnsiString value
    // - if CodePage is left to its default value of -1, it will assume
    // CurrentAnsiConvert.CodePage prior to Delphi 2009, but newer UNICODE
    // versions of Delphi will retrieve the code page from string
    // - if CodePage is defined to a >= 0 value, the encoding will take place
    procedure AddAnyAnsiString(const s: RawByteString; Escape: TTextWriterKind;
      CodePage: integer = -1);
    /// append some UTF-8 encoded chars to the buffer, from any Ansi buffer
    // - the codepage should be specified, e.g. CP_UTF8, CP_RAWBYTESTRING,
    // CODEPAGE_US, or any version supported by the Operating System
    // - if codepage is 0, the current CurrentAnsiConvert.CodePage would be used
    // - will use TSynAnsiConvert to perform the conversion to UTF-8
    procedure AddAnyAnsiBuffer(P: PAnsiChar; Len: PtrInt;
      Escape: TTextWriterKind; CodePage: integer);
    /// write some data Base64 encoded
    // - if withMagic is TRUE, will write as '"\uFFF0base64encodedbinary"'
    procedure WrBase64(P: PAnsiChar; Len: PtrUInt; withMagic: boolean);
    /// write some binary-saved data with Base64 encoding
    // - if withMagic is TRUE, will write as '"\uFFF0base64encodedbinary"'
    // - is a wrapper around BinarySave() and WrBase64()
    procedure BinarySaveBase64(Data: pointer; Info: PRttiInfo;
      Kinds: TRttiKinds; withMagic: boolean; withCrc: boolean = false);
    /// append some values at once
    // - text values (e.g. RawUtf8) will be escaped as JSON
    procedure Add(const Values: array of const); overload;
    /// append an array of integers as CSV
    procedure AddCsvInteger(const Integers: array of integer); overload;
    /// append an array of doubles as CSV
    procedure AddCsvDouble(const Doubles: array of double); overload;
    /// append an array of RawUtf8 as CSV of JSON strings
    procedure AddCsvUtf8(const Values: array of RawUtf8); overload;
    /// append an array of const as CSV of JSON values
    procedure AddCsvConst(const Values: array of const);
    /// append a quoted string as JSON, with in-place decoding
    // - if QuotedString does not start with ' or ", it will written directly
    // (i.e. expects to be a number, or null/true/false constants)
    // - as used e.g. by TJsonObjectDecoder.EncodeAsJson method and
    // JsonEncodeNameSQLValue() function
    procedure AddQuotedStringAsJson(const QuotedString: RawUtf8);
    /// append a TTimeLog value, expanded as Iso-8601 encoded text
    procedure AddTimeLog(Value: PInt64; QuoteChar: AnsiChar = #0);
    /// append a TUnixTime value, expanded as Iso-8601 encoded text
    procedure AddUnixTime(Value: PInt64; QuoteChar: AnsiChar = #0);
    /// append a TUnixMSTime value, expanded as Iso-8601 encoded text
    procedure AddUnixMSTime(Value: PInt64; WithMS: boolean = false;
      QuoteChar: AnsiChar = #0);
    /// append a TDateTime value, expanded as Iso-8601 encoded text
    // - use 'YYYY-MM-DDThh:mm:ss' format (with FirstChar='T')
    // - if WithMS is TRUE, will append '.sss' for milliseconds resolution
    // - if QuoteChar is not #0, it will be written before and after the date
    procedure AddDateTime(Value: PDateTime; FirstChar: AnsiChar = 'T';
      QuoteChar: AnsiChar = #0; WithMS: boolean = false;
      AlwaysDateAndTime: boolean = false); overload;
    /// append a TDateTime value, expanded as Iso-8601 encoded text
    // - use 'YYYY-MM-DDThh:mm:ss' format
    // - append nothing if Value=0
    // - if WithMS is TRUE, will append '.sss' for milliseconds resolution
    procedure AddDateTime(const Value: TDateTime; WithMS: boolean = false); overload;
    /// append a TDateTime value, expanded as Iso-8601 text with milliseconds
    // and Time Zone designator
    // - i.e. 'YYYY-MM-DDThh:mm:ss.sssZ' format
    // - TZD is the ending time zone designator ('', 'Z' or '+hh:mm' or '-hh:mm')
    procedure AddDateTimeMS(const Value: TDateTime; Expanded: boolean = true;
      FirstTimeChar: AnsiChar = 'T'; const TZD: RawUtf8 = 'Z');
    /// append the current UTC date and time, in our log-friendly format
    // - e.g. append '20110325 19241502' - with no trailing space nor tab
    // - you may set LocalTime=TRUE to write the local date and time instead
    // - this method is very fast, and avoid most calculation or API calls
    procedure AddCurrentLogTime(LocalTime: boolean);
    /// append the current UTC date and time, in our log-friendly format
    // - e.g. append '19/Feb/2019:06:18:55 ' - including a trailing space
    // - you may set LocalTime=TRUE to write the local date and time instead
    // - this method is very fast, and avoid most calculation or API calls
    procedure AddCurrentNCSALogTime(LocalTime: boolean);

    /// append strings or integers with a specified format
    // - this overriden version will properly handle JSON escape
    // - % = #37 marks a string, integer, floating-point, or class parameter
    // to be appended as text (e.g. class name)
    // - note that due to a limitation of the "array of const" format, cardinal
    // values should be type-casted to Int64() - otherwise the integer mapped
    // value will be transmitted, therefore wrongly
    procedure Add(const Format: RawUtf8; const Values: array of const;
      Escape: TTextWriterKind = twNone;
      WriteObjectOptions: TTextWriterWriteObjectOptions = [woFullExpand]); override;
    /// append a variant content as number or string
    // - this overriden version will properly handle JSON escape
    // - properly handle Value as a TRttiVarData from TRttiProp.GetValue
    procedure AddVariant(const Value: variant; Escape: TTextWriterKind = twJsonEscape;
      WriteOptions: TTextWriterWriteObjectOptions = []); override;
    /// append complex types as JSON content using raw TypeInfo()
    // - handle rkClass as WriteObject, rkEnumeration/rkSet with proper options,
    // rkRecord, rkDynArray or rkVariant using proper JSON serialization
    // - other types will append 'null'
    procedure AddTypedJson(Value, TypeInfo: pointer;
      WriteOptions: TTextWriterWriteObjectOptions = []); override;
    /// serialize as JSON the given object
    procedure WriteObject(Value: TObject;
      WriteOptions: TTextWriterWriteObjectOptions = [woDontStoreDefault]); override;
    /// append complex types as JSON content using TRttiCustom
    // - called e.g. by TTextWriter.AddVariant() for varAny / TRttiVarData
    procedure AddRttiCustomJson(Value: pointer; RttiCustom: TObject;
      WriteOptions: TTextWriterWriteObjectOptions);
    /// append a JSON value, array or document, in a specified format
    // - this overriden version will properly handle JSON escape
    function AddJsonReformat(Json: PUtf8Char; Format: TTextWriterJsonFormat;
      EndOfObject: PUtf8Char): PUtf8Char; override;
    /// append a JSON value, array or document as simple XML content
    // - you can use JsonBufferToXML() and JsonToXML() functions as wrappers
    // - this method is called recursively to handle all kind of JSON values
    // - WARNING: the JSON buffer is decoded in-place, so will be changed
    // - returns the end of the current JSON converted level, or nil if the
    // supplied content was not correct JSON
    function AddJsonToXML(Json: PUtf8Char; ArrayName: PUtf8Char = nil;
      EndOfObject: PUtf8Char = nil): PUtf8Char;

    /// append a record content as UTF-8 encoded JSON or custom serialization
    // - default serialization will use Base64 encoded binary stream, or
    // a custom serialization, in case of a previous registration via
    // RegisterCustomJsonSerializer() class method - from a dynamic array
    // handling this kind of records, or directly from TypeInfo() of the record
    // - by default, custom serializers defined via RegisterCustomJsonSerializer()
    // would write enumerates and sets as integer numbers, unless
    // twoEnumSetsAsTextInRecord or twoEnumSetsAsBooleanInRecord is set in
    // the instance CustomOptions
    // - returns the element size
    function AddRecordJson(Value: pointer; RecordInfo: PRttiInfo;
      WriteOptions: TTextWriterWriteObjectOptions = []): PtrInt;
    /// append a void record content as UTF-8 encoded JSON or custom serialization
    // - this method will first create a void record (i.e. filled with #0 bytes)
    // then save its content with default or custom serialization
    procedure AddVoidRecordJson(RecordInfo: PRttiInfo;
      WriteOptions: TTextWriterWriteObjectOptions = []);
    /// append a dynamic array content as UTF-8 encoded JSON array
    // - typical content could be
    // ! '[1,2,3,4]' or '["\uFFF0base64encodedbinary"]'
    procedure AddDynArrayJson(var DynArray: TDynArray;
      WriteOptions: TTextWriterWriteObjectOptions = []); overload;
    /// append a dynamic array content as UTF-8 encoded JSON array
    // - expect a dynamic array TDynArrayHashed wrapper as incoming parameter
    procedure AddDynArrayJson(var DynArray: TDynArrayHashed;
      WriteOptions: TTextWriterWriteObjectOptions = []); overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// append a dynamic array content as UTF-8 encoded JSON array
    // - returns the array element size
    function AddDynArrayJson(Value: pointer; Info: TRttiCustom;
      WriteOptions: TTextWriterWriteObjectOptions = []): PtrInt; overload;
    /// append UTF-8 content as text
    // - Text CodePage will be used (if possible) - assume RawUtf8 otherwise
    // - will properly handle JSON escape between two " double quotes
    procedure AddText(const Text: RawByteString; Escape: TTextWriterKind = twJsonEscape);
    /// append UTF-16 content as text
    // - P should be a #0 terminated PWideChar buffer
    // - will properly handle JSON escape between two " double quotes
    procedure AddTextW(P: PWord; Escape: TTextWriterKind = twJsonEscape);
    /// append some UTF-8 encoded chars to the buffer
    // - escapes chars according to the JSON RFC
    // - if Len is 0, writing will stop at #0 (default Len = 0 is slightly faster
    // than specifying Len>0 if you are sure P is zero-ended - e.g. from RawUtf8)
    procedure AddJsonEscape(P: Pointer; Len: PtrInt = 0); overload;
    /// append some Unicode encoded chars to the buffer
    // - if Len is 0, Len is calculated from zero-ended widechar
    // - escapes chars according to the JSON RFC
    procedure AddJsonEscapeW(P: PWord; Len: PtrInt = 0);
    /// append some UTF-8 encoded chars to the buffer, from a generic string type
    // - faster than AddJsonEscape(pointer(StringToUtf8(string))
    // - escapes chars according to the JSON RFC
    procedure AddJsonEscapeString(const s: string);
      {$ifdef HASINLINE}inline;{$endif}
    /// append some UTF-8 encoded chars to the buffer, from the main AnsiString type
    // - escapes chars according to the JSON RFC
    procedure AddJsonEscapeAnsiString(const s: AnsiString);
    /// append an open array constant value to the buffer
    // - "" will be added if necessary
    // - escapes chars according to the JSON RFC
    // - very fast (avoid most temporary storage)
    procedure AddJsonEscape(const V: TVarRec); overload;
    /// append a UTF-8 JSON String, between double quotes and with JSON escaping
    procedure AddJsonString(const Text: RawUtf8);
    /// flush a supplied TTextWriter, and write pending data as JSON escaped text
    // - may be used with InternalJsonWriter, as a faster alternative to
    // ! AddJsonEscape(Pointer(fInternalJsonWriter.Text),0);
    procedure AddJsonEscape(Source: TTextWriter); overload;
    /// flush a supplied TTextWriter, and write pending data as JSON escaped text
    // - may be used with InternalJsonWriter, as a faster alternative to
    // ! AddNoJsonEscapeUtf8(Source.Text);
    procedure AddNoJsonEscape(Source: TTextWriter); overload;
    /// append an open array constant value to the buffer
    // - "" won't be added for string values
    // - string values may be escaped, depending on the supplied parameter
    // - very fast (avoid most temporary storage)
    procedure Add(const V: TVarRec; Escape: TTextWriterKind = twNone;
      WriteObjectOptions: TTextWriterWriteObjectOptions = [woFullExpand]); overload;
    /// encode the supplied data as an UTF-8 valid JSON object content
    // - data must be supplied two by two, as Name,Value pairs, e.g.
    // ! aWriter.AddJsonEscape(['name','John','year',1972]);
    // will append to the buffer:
    // ! '{"name":"John","year":1972}'
    // - or you can specify nested arrays or objects with '['..']' or '{'..'}':
    // ! aWriter.AddJsonEscape(['doc','{','name','John','ab','[','a','b']','}','id',123]);
    // will append to the buffer:
    // ! '{"doc":{"name":"John","abc":["a","b"]},"id":123}'
    // - note that, due to a Delphi compiler limitation, cardinal values should be
    // type-casted to Int64() (otherwise the integer mapped value will be converted)
    // - you can pass nil as parameter for a null JSON value
    procedure AddJsonEscape(
      const NameValuePairs: array of const); overload;
    /// encode the supplied (extended) JSON content, with parameters,
    // as an UTF-8 valid JSON object content
    // - in addition to the JSON RFC specification strict mode, this method will
    // handle some BSON-like extensions, e.g. unquoted field names:
    // ! aWriter.AddJson('{id:?,%:{name:?,birthyear:?}}',['doc'],[10,'John',1982]);
    // - you can use nested _Obj() / _Arr() instances
    // ! aWriter.AddJson('{%:{$in:[?,?]}}',['type'],['food','snack']);
    // ! aWriter.AddJson('{type:{$in:?}}',[],[_Arr(['food','snack'])]);
    // ! // which are the same as:
    // ! aWriter.AddShort('{"type":{"$in":["food","snack"]}}');
    // - if the mormot.db.nosql.bson unit is used in the application, the MongoDB
    // Shell syntax will also be recognized to create TBsonVariant, like
    // ! new Date()   ObjectId()   MinKey   MaxKey  /<jRegex>/<jOptions>
    // see @http://docs.mongodb.org/manual/reference/mongodb-extended-json
    // !  aWriter.AddJson('{name:?,field:/%/i}',['acme.*corp'],['John']))
    // ! // will write
    // ! '{"name":"John","field":{"$regex":"acme.*corp","$options":"i"}}'
    // - will call internally _JsonFastFmt() to create a temporary TDocVariant
    // with all its features - so is slightly slower than other AddJson* methods
    procedure AddJson(const Format: RawUtf8;
      const Args, Params: array of const);
    /// append two JSON arrays of keys and values as one JSON object
    // - i.e. makes the following transformation:
    // $ [key1,key2...] + [value1,value2...] -> {key1:value1,key2,value2...}
    // - this method won't allocate any memory during its process, nor
    // modify the keys and values input buffers
    // - is the reverse of the JsonObjectAsJsonArrays() function
    // - used e.g. by TSynDictionary.SaveToJson
    procedure AddJsonArraysAsJsonObject(keys, values: PUtf8Char);
  end;


{ ************ JSON-aware TSynNameValue TSynPersistentStoreJson TRawByteStringGroup }

type
  /// store one Name/Value pair, as used by TSynNameValue class
  TSynNameValueItem = record
    /// the name of the Name/Value pair
    // - this property is hashed by TSynNameValue for fast retrieval
    Name: RawUtf8;
    /// the value of the Name/Value pair
    Value: RawUtf8;
    /// any associated Pointer or numerical value
    Tag: PtrInt;
  end;

  /// Name/Value pairs storage, as used by TSynNameValue class
  TSynNameValueItemDynArray = array of TSynNameValueItem;

  /// event handler used to convert on the fly some UTF-8 text content
  TOnSynNameValueConvertRawUtf8 = function(
    const text: RawUtf8): RawUtf8 of object;

  /// callback event used by TSynNameValue
  TOnSynNameValueNotify = procedure(
    const Item: TSynNameValueItem; Index: PtrInt) of object;

  /// pseudo-class used to store Name/Value RawUtf8 pairs
  // - use internally a TDynArrayHashed instance for fast retrieval
  // - is therefore faster than TRawUtf8List
  // - is defined as an object, not as a class: you can use this in any
  // class, without the need to destroy the content
  // - Delphi "object" is buggy on stack -> also defined as record with methods
  {$ifdef USERECORDWITHMETHODS}
  TSynNameValue = record
  private
  {$else}
  TSynNameValue = object
  protected
  {$endif USERECORDWITHMETHODS}
    fOnAdd: TOnSynNameValueNotify;
    function GetBlobData: RawByteString;
    procedure SetBlobData(const aValue: RawByteString);
    function GetStr(const aName: RawUtf8): RawUtf8;
      {$ifdef HASINLINE}inline;{$endif}
    function GetInt(const aName: RawUtf8): Int64;
      {$ifdef HASINLINE}inline;{$endif}
    function GetBool(const aName: RawUtf8): boolean;
      {$ifdef HASINLINE}inline;{$endif}
  public
    /// the internal Name/Value storage
    List: TSynNameValueItemDynArray;
    /// the number of Name/Value pairs
    Count: integer;
    /// low-level access to the internal storage hasher
    DynArray: TDynArrayHashed;
    /// initialize the storage
    // - will also reset the internal List[] and the internal hash array
    procedure Init(aCaseSensitive: boolean);
    /// add an element to the array
    // - if aName already exists, its associated Value will be updated
    procedure Add(const aName, aValue: RawUtf8; aTag: PtrInt = 0);
    /// reset content, then add all name=value pairs from a supplied .ini file
    // section content
    // - will first call Init(false) to initialize the internal array
    // - Section can be retrieved e.g. via FindSectionFirstLine()
    procedure InitFromIniSection(Section: PUtf8Char;
      const OnTheFlyConvert: TOnSynNameValueConvertRawUtf8 = nil;
      const OnAdd: TOnSynNameValueNotify = nil);
    /// reset content, then add all name=value; CSV pairs
    // - will first call Init(false) to initialize the internal array
    // - if ItemSep=#10, then any kind of line feed (CRLF or LF) will be handled
    procedure InitFromCsv(Csv: PUtf8Char; NameValueSep: AnsiChar = '=';
      ItemSep: AnsiChar = #10);
    /// reset content, then add all fields from an JSON object
    // - will first call Init() to initialize the internal array
    // - then parse the incoming JSON object, storing all its field values
    // as RawUtf8, and returning TRUE if the supplied content is correct
    // - warning: the supplied JSON buffer will be decoded and modified in-place
    function InitFromJson(Json: PUtf8Char; aCaseSensitive: boolean = false): boolean;
    /// reset content, then add all name, value pairs
    // - will first call Init(false) to initialize the internal array
    procedure InitFromNamesValues(const Names, Values: array of RawUtf8);
    /// search for a Name, return the index in List
    // - using fast O(1) hash algoritm
    function Find(const aName: RawUtf8): integer;
    /// search for the first chars of a Name, return the index in List
    // - using O(n) calls of IdemPChar() function
    // - here aUpperName should be already uppercase, as expected by IdemPChar()
    function FindStart(const aUpperName: RawUtf8): PtrInt;
    /// search for a Value, return the index in List
    // - using O(n) brute force algoritm with case-sensitive aValue search
    function FindByValue(const aValue: RawUtf8): PtrInt;
    /// search for a Name, and delete its entry in the List if it exists
    function Delete(const aName: RawUtf8): boolean;
    /// search for a Value, and delete its entry in the List if it exists
    // - returns the number of deleted entries
    // - you may search for more than one match, by setting a >1 Limit value
    function DeleteByValue(const aValue: RawUtf8; Limit: integer = 1): integer;
    /// search for a Name, return the associated Value as a UTF-8 string
    function Value(const aName: RawUtf8; const aDefaultValue: RawUtf8 = ''): RawUtf8;
    /// search for a Name, return the associated Value as integer
    function ValueInt(const aName: RawUtf8; const aDefaultValue: Int64 = 0): Int64;
    /// search for a Name, return the associated Value as boolean
    // - returns true only if the value is exactly '1'
    function ValueBool(const aName: RawUtf8): boolean;
    /// search for a Name, return the associated Value as an enumerate
    // - returns true and set aEnum if aName was found, and associated value
    // matched an aEnumTypeInfo item
    // - returns false if no match was found
    function ValueEnum(const aName: RawUtf8; aEnumTypeInfo: PRttiInfo;
      out aEnum; aEnumDefault: PtrUInt = 0): boolean; overload;
    /// returns all values, as CSV or INI content
    function AsCsv(const KeySeparator: RawUtf8 = '=';
      const ValueSeparator: RawUtf8 = #13#10; const IgnoreKey: RawUtf8 = ''): RawUtf8;
    /// returns all values as a JSON object of string fields
    function AsJson: RawUtf8;
    /// fill the supplied two arrays of RawUtf8 with the stored values
    procedure AsNameValues(out Names,Values: TRawUtf8DynArray);
    /// search for a Name, return the associated Value as variant
    // - returns null if the name was not found
    function ValueVariantOrNull(const aName: RawUtf8): variant;
    /// compute a TDocVariant document from the stored values
    // - output variant will be reset and filled as a TDocVariant instance,
    // ready to be serialized as a JSON object
    // - if there is no value stored (i.e. Count=0), set null
    procedure AsDocVariant(out DocVariant: variant;
      ExtendedJson: boolean = false; ValueAsString: boolean = true;
      AllowVarDouble: boolean = false); overload;
    /// compute a TDocVariant document from the stored values
    function AsDocVariant(ExtendedJson: boolean = false;
      ValueAsString: boolean = true): variant; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// merge the stored values into a TDocVariant document
    // - existing properties would be updated, then new values will be added to
    // the supplied TDocVariant instance, ready to be serialized as a JSON object
    // - if ValueAsString is TRUE, values would be stored as string
    // - if ValueAsString is FALSE, numerical values would be identified by
    // IsString() and stored as such in the resulting TDocVariant
    // - if you let ChangedProps point to a TDocVariantData, it would contain
    // an object with the stored values, just like AsDocVariant
    // - returns the number of updated values in the TDocVariant, 0 if
    // no value was changed
    function MergeDocVariant(var DocVariant: variant; ValueAsString: boolean;
      ChangedProps: PVariant = nil; ExtendedJson: boolean = false;
      AllowVarDouble: boolean = false): integer;
    /// returns true if the Init() method has been called
    function Initialized: boolean;
    /// can be used to set all data from one BLOB memory buffer
    procedure SetBlobDataPtr(aValue: pointer);
    /// can be used to set or retrieve all stored data as one BLOB content
    property BlobData: RawByteString
      read GetBlobData write SetBlobData;
    /// event triggerred after an item has just been added to the list
    property OnAfterAdd: TOnSynNameValueNotify
      read fOnAdd write fOnAdd;
    /// search for a Name, return the associated Value as a UTF-8 string
    // - returns '' if aName is not found in the stored keys
    property Str[const aName: RawUtf8]: RawUtf8
      read GetStr; default;
    /// search for a Name, return the associated Value as integer
    // - returns 0 if aName is not found, or not a valid Int64 in the stored keys
    property Int[const aName: RawUtf8]: Int64
      read GetInt;
    /// search for a Name, return the associated Value as boolean
    // - returns true if aName stores '1' as associated value
    property Bool[const aName: RawUtf8]: boolean
      read GetBool;
  end;

  /// a reference pointer to a Name/Value RawUtf8 pairs storage
  PSynNameValue = ^TSynNameValue;


type
  /// implement binary persistence and JSON serialization (not deserialization)
  TSynPersistentStoreJson = class(TSynPersistentStore)
  protected
    // append "name" -> inherited should add properties to the JSON object
    procedure AddJson(W: TTextWriter); virtual;
  public
    /// serialize this instance as a JSON object
    function SaveToJson(reformat: TTextWriterJsonFormat = jsonCompact): RawUtf8;
  end;


type
  /// item as stored in a TRawByteStringGroup instance
  TRawByteStringGroupValue = record
    Position: integer;
    Value: RawByteString;
  end;

  PRawByteStringGroupValue = ^TRawByteStringGroupValue;

  /// items as stored in a TRawByteStringGroup instance
  TRawByteStringGroupValueDynArray = array of TRawByteStringGroupValue;

  /// store several RawByteString content with optional concatenation
  {$ifdef USERECORDWITHMETHODS}
  TRawByteStringGroup = record
  {$else}
  TRawByteStringGroup = object
  {$endif USERECORDWITHMETHODS}
  public
    /// actual list storing the data
    Values: TRawByteStringGroupValueDynArray;
    /// how many items are currently stored in Values[]
    Count: integer;
    /// the current size of data stored in Values[]
    Position: integer;
    /// naive but efficient cache for Find()
    LastFind: integer;
    /// add a new item to Values[]
    procedure Add(const aItem: RawByteString); overload;
    /// add a new item to Values[]
    procedure Add(aItem: pointer; aItemLen: integer); overload;
    /// add another TRawByteStringGroup to Values[]
    procedure Add(const aAnother: TRawByteStringGroup); overload;
    /// low-level method to abort the latest Add() call
    // - warning: will work only once, if an Add() has actually been just called:
    // otherwise, the behavior is unexpected, and may wrongly truncate data
    procedure RemoveLastAdd;
    /// compare two TRawByteStringGroup instance stored text
    function Equals(const aAnother: TRawByteStringGroup): boolean;
    /// clear any stored information
    procedure Clear;
    /// append stored information into another RawByteString, and clear content
    procedure AppendTextAndClear(var aDest: RawByteString);
    // compact the Values[] array into a single item
    // - is also used by AsText to compute a single RawByteString
    procedure Compact;
    /// return all content as a single RawByteString
    // - will also compact the Values[] array into a single item (which is returned)
    function AsText: RawByteString;
    /// return all content as a single TByteDynArray
    function AsBytes: TByteDynArray;
    /// save all content into a TTextWriter instance
    procedure Write(W: TTextWriter; Escape: TTextWriterKind = twJsonEscape); overload;
    /// save all content into a TBufferWriter instance
    procedure WriteBinary(W: TBufferWriter); overload;
    /// save all content as a string into a TBufferWriter instance
    // - storing the length as WriteVarUInt32() prefix
    procedure WriteString(W: TBufferWriter);
    /// add another TRawByteStringGroup previously serialized via WriteString()
    procedure AddFromReader(var aReader: TFastReader);
    /// returns a pointer to Values[] containing a given position
    // - returns nil if not found
    function Find(aPosition: integer): PRawByteStringGroupValue; overload;
    /// returns a pointer to Values[].Value containing a given position and length
    // - returns nil if not found
    function Find(aPosition, aLength: integer): pointer; overload;
    /// returns the text at a given position in Values[]
    // - text should be in a single Values[] entry
    procedure FindAsText(aPosition, aLength: integer; out aText: RawByteString); overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// returns the text at a given position in Values[]
    // - text should be in a single Values[] entry
    function FindAsText(aPosition, aLength: integer): RawByteString; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// returns the text at a given position in Values[]
    // - text should be in a single Values[] entry
    // - explicitly returns null if the supplied text was not found
    procedure FindAsVariant(aPosition, aLength: integer; out aDest: variant);
      {$ifdef HASINLINE}inline;{$endif}
    /// append the text at a given position in Values[], JSON escaped by default
    // - text should be in a single Values[] entry
    procedure FindWrite(aPosition, aLength: integer; W: TTextWriter;
      Escape: TTextWriterKind = twJsonEscape; TrailingCharsToIgnore: integer = 0);
      {$ifdef HASINLINE}inline;{$endif}
    /// append the blob at a given position in Values[], base-64 encoded
    // - text should be in a single Values[] entry
    procedure FindWriteBase64(aPosition, aLength: integer; W: TTextWriter;
      withMagic: boolean);
      {$ifdef HASINLINE}inline;{$endif}
    /// copy the text at a given position in Values[]
    // - text should be in a single Values[] entry
    procedure FindMove(aPosition, aLength: integer; aDest: pointer);
  end;

  /// pointer reference to a TRawByteStringGroup
  PRawByteStringGroup = ^TRawByteStringGroup;

type
  /// implement a cache of some key/value pairs, e.g. to improve reading speed
  // - used e.g. by TSqlDataBase for caching the SELECT statements results in an
  // internal JSON format (which is faster than a query to the SQLite3 engine)
  // - internally make use of an efficient hashing algorithm for fast response
  // (i.e. TSynNameValue will use the TDynArrayHashed wrapper mechanism)
  // - this class is thread-safe if you use properly the associated Safe lock
  TSynCache = class(TSynLocked)
  protected
    fFindLastKey: RawUtf8;
    fNameValue: TSynNameValue;
    fRamUsed: cardinal;
    fMaxRamUsed: cardinal;
    fTimeoutSeconds: cardinal;
    fTimeoutTix: cardinal;
    procedure ResetIfNeeded;
  public
    /// initialize the internal storage
    // - aMaxCacheRamUsed can set the maximum RAM to be used for values, in bytes
    // (default is 16 MB), after which the cache is flushed
    // - by default, key search is done case-insensitively, but you can specify
    // another option here
    // - by default, there is no timeout period, but you may specify a number of
    // seconds of inactivity (i.e. no Add call) after which the cache is flushed
    constructor Create(aMaxCacheRamUsed: cardinal = 16 shl 20;
      aCaseSensitive: boolean = false; aTimeoutSeconds: cardinal = 0); reintroduce;
    /// find a Key in the cache entries
    // - return '' if nothing found: you may call Add() just after to insert
    // the expected value in the cache
    // - return the associated Value otherwise, and the associated integer tag
    // if aResultTag address is supplied
    // - this method is not thread-safe, unless you call Safe.Lock before
    // calling Find(), and Safe.Unlock after calling Add()
    function Find(const aKey: RawUtf8; aResultTag: PPtrInt = nil): RawUtf8;
    /// add a Key and its associated value (and tag) to the cache entries
    // - you MUST always call Find() with the associated Key first
    // - this method is not thread-safe, unless you call Safe.Lock before
    // calling Find(), and Safe.Unlock after calling Add()
    procedure Add(const aValue: RawUtf8; aTag: PtrInt);
    /// add a Key/Value pair in the cache entries
    // - returns true if aKey was not existing yet, and aValue has been stored
    // - returns false if aKey did already exist in the internal cache, and
    // its entry has been updated with the supplied aValue/aTag
    // - this method is thread-safe, using the Safe locker of this instance
    function AddOrUpdate(const aKey, aValue: RawUtf8; aTag: PtrInt): boolean;
    /// called after a write access to the database to flush the cache
    // - set Count to 0
    // - release all cache memory
    // - returns TRUE if was flushed, i.e. if there was something in cache
    // - this method is thread-safe, using the Safe locker of this instance
    function Reset: boolean;
    /// number of entries in the cache
    function Count: integer;
    /// access to the internal locker, for thread-safe process
    // - Find/Add methods calls should be protected as such:
    // ! cache.Safe.Lock;
    // ! try
    // !   ... cache.Find/cache.Add ...
    // ! finally
    // !   cache.Safe.Unlock;
    // ! end;
    property Safe: PSynLocker
      read fSafe;
    /// the current global size of Values in RAM cache, in bytes
    property RamUsed: cardinal
      read fRamUsed;
    /// the maximum RAM to be used for values, in bytes
    // - the cache is flushed when ValueSize reaches this limit
    // - default is 16 MB (16 shl 20)
    property MaxRamUsed: cardinal
      read fMaxRamUsed;
    /// after how many seconds betwen Add() calls the cache should be flushed
    // - equals 0 by default, meaning no time out
    property TimeoutSeconds: cardinal
      read fTimeoutSeconds;
  end;


{ *********** JSON-aware TSynDictionary Storage }

type
  /// exception raised during TSynDictionary process
  ESynDictionary = class(ESynException);

  // internal flag, used only by TSynDictionary.InArray protected method
  TSynDictionaryInArray = (
    iaFind,
    iaFindAndDelete,
    iaFindAndUpdate,
    iaFindAndAddIfNotExisting,
    iaAdd,
    iaAddForced);

  /// event called by TSynDictionary.ForEach methods to iterate over stored items
  // - if the implementation method returns TRUE, will continue the loop
  // - if the implementation method returns FALSE, will stop values browsing
  // - aOpaque is a custom value specified at ForEach() method call
  TOnSynDictionary = function(const aKey; var aValue;
    aIndex, aCount: integer; aOpaque: pointer): boolean of object;

  /// event called by TSynDictionary.DeleteDeprecated
  // - called just before deletion: return false to by-pass this item
  TOnSynDictionaryCanDelete = function(const aKey, aValue;
    aIndex: integer): boolean of object;

  /// thread-safe dictionary to store some values from associated keys
  // - will maintain a dynamic array of values, associated with a hash table
  // for the keys, so that setting or retrieving values would be O(1)
  // - all process is protected by a TSynLocker, so will be thread-safe
  // - TDynArray is a wrapper which do not store anything, whereas this class
  // is able to store both keys and values, and provide convenient methods to
  // access the stored data, including JSON serialization and binary storage
  TSynDictionary = class(TSynLocked)
  protected
    fKeys: TDynArrayHashed;
    fValues: TDynArray;
    fTimeOut: TCardinalDynArray;
    fTimeOuts: TDynArray;
    fCompressAlgo: TAlgoCompress;
    fOnCanDelete: TOnSynDictionaryCanDelete;
    function InArray(const aKey, aArrayValue; aAction: TSynDictionaryInArray;
      aCompare: TDynArraySortCompare): boolean;
    procedure SetTimeouts;
    function ComputeNextTimeOut: cardinal;
    function KeyFullHash(const Elem): cardinal;
    function KeyFullCompare(const A, B): integer;
    function GetCapacity: integer;
    procedure SetCapacity(const Value: integer);
    function GetTimeOutSeconds: cardinal;
    procedure SetTimeOutSeconds(Value: cardinal);
  public
    /// initialize the dictionary storage, specifyng dynamic array keys/values
    // - aKeyTypeInfo should be a dynamic array TypeInfo() RTTI pointer, which
    // would store the keys within this TSynDictionary instance
    // - aValueTypeInfo should be a dynamic array TypeInfo() RTTI pointer, which
    // would store the values within this TSynDictionary instance
    // - by default, string keys would be searched following exact case, unless
    // aKeyCaseInsensitive is TRUE
    // - you can set an optional timeout period, in seconds - you should call
    // DeleteDeprecated periodically to search for deprecated items
    constructor Create(aKeyTypeInfo, aValueTypeInfo: PRttiInfo;
      aKeyCaseInsensitive: boolean = false; aTimeoutSeconds: cardinal = 0;
      aCompressAlgo: TAlgoCompress = nil); reintroduce; virtual;
    /// finalize the storage
    // - would release all internal stored values
    destructor Destroy; override;
    /// try to add a value associated with a primary key
    // - returns the index of the inserted item, -1 if aKey is already existing
    // - this method is thread-safe, since it will lock the instance
    function Add(const aKey, aValue): integer;
    /// store a value associated with a primary key
    // - returns the index of the matching item
    // - if aKey does not exist, a new entry is added
    // - if aKey does exist, the existing entry is overriden with aValue
    // - this method is thread-safe, since it will lock the instance
    function AddOrUpdate(const aKey, aValue): integer;
    /// clear the value associated via aKey
    // - does not delete the entry, but reset its value
    // - returns the index of the matching item, -1 if aKey was not found
    // - this method is thread-safe, since it will lock the instance
    function Clear(const aKey): integer;
    /// delete all key/value stored in the current instance
    procedure DeleteAll;
    /// delete a key/value association from its supplied aKey
    // - this would delete the entry, i.e. matching key and value pair
    // - returns the index of the deleted item, -1 if aKey was not found
    // - this method is thread-safe, since it will lock the instance
    function Delete(const aKey): integer;
    /// delete a key/value association from its internal index
    // - this method is not thread-safe: you should use fSafe.Lock/Unlock
    // e.g. then Find/FindValue to retrieve the index value
    function DeleteAt(aIndex: integer): boolean;
    /// search and delete all deprecated items according to TimeoutSeconds
    // - returns how many items have been deleted
    // - you can call this method very often: it will ensure that the
    // search process will take place at most once every second
    // - this method is thread-safe, but blocking during the process
    function DeleteDeprecated: integer;
    /// search of a primary key within the internal hashed dictionary
    // - returns the index of the matching item, -1 if aKey was not found
    // - if you want to access the value, you should use fSafe.Lock/Unlock:
    // consider using Exists or FindAndCopy thread-safe methods instead
    // - aUpdateTimeOut will update the associated timeout value of the entry
    function Find(const aKey; aUpdateTimeOut: boolean = false): integer;
    /// search of a primary key within the internal hashed dictionary
    // - returns a pointer to the matching item, nil if aKey was not found
    // - if you want to access the value, you should use fSafe.Lock/Unlock:
    // consider using Exists or FindAndCopy thread-safe methods instead
    // - aUpdateTimeOut will update the associated timeout value of the entry
    function FindValue(const aKey; aUpdateTimeOut: boolean = false;
      aIndex: PInteger = nil): pointer;
    /// search of a primary key within the internal hashed dictionary
    // - returns a pointer to the matching or already existing item
    // - if you want to access the value, you should use fSafe.Lock/Unlock:
    // consider using Exists or FindAndCopy thread-safe methods instead
    // - will update the associated timeout value of the entry, if applying
    function FindValueOrAdd(const aKey; var added: boolean;
      aIndex: PInteger = nil): pointer;
    /// search of a stored value by its primary key, and return a local copy
    // - so this method is thread-safe
    // - returns TRUE if aKey was found, FALSE if no match exists
    // - will update the associated timeout value of the entry, unless
    // aUpdateTimeOut is set to false
    function FindAndCopy(const aKey;
      out aValue; aUpdateTimeOut: boolean = true): boolean;
    /// search of a stored value by its primary key, then delete and return it
    // - returns TRUE if aKey was found, fill aValue with its content,
    // and delete the entry in the internal storage
    // - so this method is thread-safe
    // - returns FALSE if no match exists
    function FindAndExtract(const aKey; out aValue): boolean;
    /// search for a primary key presence
    // - returns TRUE if aKey was found, FALSE if no match exists
    // - this method is thread-safe
    function Exists(const aKey): boolean;
    /// apply a specified event over all items stored in this dictionnary
    // - would browse the list in the adding order
    // - returns the number of times OnEach has been called
    // - this method is thread-safe, since it will lock the instance
    function ForEach(const OnEach: TOnSynDictionary;
      Opaque: pointer = nil): integer; overload;
    /// apply a specified event over matching items stored in this dictionnary
    // - would browse the list in the adding order, comparing each key and/or
    // value item with the supplied comparison functions and aKey/aValue content
    // - returns the number of times OnMatch has been called, i.e. how many times
    // KeyCompare(aKey,Keys[#])=0 or ValueCompare(aValue,Values[#])=0
    // - this method is thread-safe, since it will lock the instance
    function ForEach(const OnMatch: TOnSynDictionary;
      KeyCompare, ValueCompare: TDynArraySortCompare; const aKey, aValue;
      Opaque: pointer = nil): integer; overload;
    /// touch the entry timeout field so that it won't be deprecated sooner
    // - this method is not thread-safe, and is expected to be execute e.g.
    // from a ForEach() TOnSynDictionary callback
    procedure SetTimeoutAtIndex(aIndex: integer);
    /// search aArrayValue item in a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, then use TDynArray.Find
    // to delete any aArrayValue match in the associated dynamic array
    // - returns FALSE if Values is not a tkDynArray, or if aKey or aArrayValue
    // were not found
    // - this method is thread-safe, since it will lock the instance
    function FindInArray(const aKey, aArrayValue;
      aCompare: TDynArraySortCompare = nil): boolean;
    /// search of a stored key by its associated key, and return a key local copy
    // - won't use any hashed index but RTTI TDynArray.IndexOf search over
    // over fValues() so is much slower than FindAndCopy() for huge arrays
    // - will update the associated timeout value of the entry, unless
    // aUpdateTimeOut is set to false
    // - this method is thread-safe
    // - returns TRUE if aValue was found, FALSE if no match exists
    function FindKeyFromValue(const aValue; out aKey;
      aUpdateTimeOut: boolean = true): boolean;
    /// add aArrayValue item within a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, then use TDynArray.Add
    // to add aArrayValue to the associated dynamic array
    // - returns FALSE if Values is not a tkDynArray, or if aKey was not found
    // - this method is thread-safe, since it will lock the instance
    function AddInArray(const aKey, aArrayValue;
      aCompare: TDynArraySortCompare = nil): boolean;
    /// add aArrayValue item within a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, create the entry if not found,
    //  then use TDynArray.Add to add aArrayValue to the associated dynamic array
    // - returns FALSE if Values is not a tkDynArray
    // - this method is thread-safe, since it will lock the instance
    function AddInArrayForced(const aKey, aArrayValue;
      aCompare: TDynArraySortCompare = nil): boolean;
    /// add once aArrayValue within a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, then use
    // TDynArray.FindAndAddIfNotExisting to add once aArrayValue to the
    // associated dynamic array
    // - returns FALSE if Values is not a tkDynArray, or if aKey was not found
    // - this method is thread-safe, since it will lock the instance
    function AddOnceInArray(const aKey, aArrayValue;
      aCompare: TDynArraySortCompare = nil): boolean;
    /// clear aArrayValue item of a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, then use TDynArray.FindAndDelete
    // to delete any aArrayValue match in the associated dynamic array
    // - returns FALSE if Values is not a tkDynArray, or if aKey or aArrayValue
    // were not found
    // - this method is thread-safe, since it will lock the instance
    function DeleteInArray(const aKey, aArrayValue;
      aCompare: TDynArraySortCompare = nil): boolean;
    /// replace aArrayValue item of a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, then use TDynArray.FindAndUpdate
    // to delete any aArrayValue match in the associated dynamic array
    // - returns FALSE if Values is not a tkDynArray, or if aKey or aArrayValue were
    // not found
    // - this method is thread-safe, since it will lock the instance
    function UpdateInArray(const aKey, aArrayValue;
      aCompare: TDynArraySortCompare = nil): boolean;
    /// make a copy of the stored values
    // - this method is thread-safe, since it will lock the instance during copy
    // - resulting length(Dest) will match the exact values count
    // - T*ObjArray will be reallocated and copied by content (using a temporary
    // JSON serialization), unless ObjArrayByRef is true and pointers are copied
    procedure CopyValues(out Dest; ObjArrayByRef: boolean = false);
    /// serialize the content as a "key":value JSON object
    procedure SaveToJson(
      W: TTextWriter; EnumSetsAsText: boolean = false); overload;
    /// serialize the content as a "key":value JSON object
    function SaveToJson(
      EnumSetsAsText: boolean = false): RawUtf8; overload;
    /// serialize the Values[] as a JSON array
    function SaveValuesToJson(EnumSetsAsText: boolean = false): RawUtf8;
    /// unserialize the content from "key":value JSON object
    // - if the JSON input may not be correct (i.e. if not coming from SaveToJson),
    // you may set EnsureNoKeyCollision=TRUE for a slow but safe keys validation
    function LoadFromJson(const Json: RawUtf8;
      CustomVariantOptions: PDocVariantOptions = nil): boolean; overload;
    /// unserialize the content from "key":value JSON object
    // - note that input JSON buffer is not modified in place: no need to create
    // a temporary copy if the buffer is about to be re-used
    function LoadFromJson(Json: PUtf8Char;
      CustomVariantOptions: PDocVariantOptions = nil): boolean; overload;
    /// save the content as SynLZ-compressed raw binary data
    // - warning: this format is tied to the values low-level RTTI, so if you
    // change the value/key type definitions, LoadFromBinary() would fail
    function SaveToBinary(NoCompression: boolean = false;
      Algo: TAlgoCompress = nil): RawByteString;
    /// load the content from SynLZ-compressed raw binary data
    // - as previously saved by SaveToBinary method
    function LoadFromBinary(const binary: RawByteString): boolean;
    /// can be assigned to OnCanDeleteDeprecated to check TSynPersistentLock(aValue).Safe.IsLocked
    class function OnCanDeleteSynPersistentLock(
      const aKey, aValue; aIndex: integer): boolean;
    /// can be assigned to OnCanDeleteDeprecated to check TSynPersistentLock(aValue).Safe.IsLocked
    class function OnCanDeleteSynPersistentLocked(
      const aKey, aValue; aIndex: integer): boolean;
    /// returns how many items are currently stored in this dictionary
    // - this method is thread-safe
    function Count: integer;
    /// fast returns how many items are currently stored in this dictionary
    // - this method is NOT thread-safe so should be protected by fSafe.Lock/UnLock
    function RawCount: integer;
      {$ifdef HASINLINE}inline;{$endif}
    /// direct access to the primary key identifiers
    // - if you want to access the keys, you should use fSafe.Lock/Unlock
    property Keys: TDynArrayHashed
      read fKeys;
    /// direct access to the associated stored values
    // - if you want to access the values, you should use fSafe.Lock/Unlock
    property Values: TDynArray
      read fValues;
    /// defines how many items are currently stored in Keys/Values internal arrays
    property Capacity: integer
      read GetCapacity write SetCapacity;
    /// direct low-level access to the internal access tick (GetTickCount64 shr 10)
    // - may be nil if TimeOutSeconds=0
    property TimeOut: TCardinalDynArray
      read fTimeOut;
    /// returns the aTimeOutSeconds parameter value, as specified to Create()
    // - warning: setting a new timeout will clear all previous content
    property TimeOutSeconds: cardinal
      read GetTimeOutSeconds write SetTimeOutSeconds;
    /// the compression algorithm used for binary serialization
    property CompressAlgo: TAlgoCompress
      read fCompressAlgo write fCompressAlgo;
    /// callback to by-pass DeleteDeprecated deletion by returning false
    // - can be assigned e.g. to OnCanDeleteSynPersistentLock if Value is a
    // TSynPersistentLock instance, to avoid any potential access violation
    property OnCanDeleteDeprecated: TOnSynDictionaryCanDelete
      read fOnCanDelete write fOnCanDelete;
  end;



{ ********** Low-level JSON Serialization for any kind of Values }

type
  /// internal stack-allocated structure for nested serialization
  // - defined here for low-level use of TRttiJsonSave functions
  TJsonSaveContext = object
  protected
    W: TTextWriter;
    Options: TTextWriterWriteObjectOptions;
    Info: TRttiCustom;
    Prop: PRttiCustomProp;
    procedure Add64(Value: PInt64; UnSigned: boolean);
    procedure AddShort(PS: PShortString);
    procedure AddShortBoolean(PS: PShortString; Value: boolean);
    procedure AddDateTime(Value: PDateTime; WithMS: boolean);
  public
    /// initialize this low-level context
    procedure Init(WR: TTextWriter;
      WriteOptions: TTextWriterWriteObjectOptions; Rtti: TRttiCustom);
      {$ifdef HASINLINE}inline;{$endif}
  end;

  /// internal function handler for JSON persistence of any TRttiParserType value
  // - i.e. the kind of functions called via PT_JSONSAVE[] lookup table
  TRttiJsonSave = procedure(Data: pointer; const Ctxt: TJsonSaveContext);


{ ********** Low-level JSON Unserialization for any kind of Values }

type
  /// available options for JSON parsing process
  // - by default, parsing will fail if a JSON field name is not part of the
  // object published properties, unless jpoIgnoreUnknownProperty is defined -
  // this option will also ignore read-only properties (i.e. with only a getter)
  // - by default, function will check that the supplied JSON value will
  // be a JSON string when the property is a string, unless jpoIgnoreStringType
  // is defined and JSON numbers are accepted and stored as text
  // - by default any unexpected value for enumerations will be marked as
  // invalid, unless jpoIgnoreUnknownEnum is defined, so that in such case the
  // ordinal 0 value is left, and loading continues
  // - by default, only simple kind of variant types (string/numbers) are
  // handled: set jpoHandleCustomVariants if you want to handle any custom -
  // in this case , it will handle direct JSON [array] of {object}: but if you
  // also define jpoHandleCustomVariantsWithinString, it will also try to
  // un-escape a JSON string first, i.e. handle "[array]" or "{object}" content
  // (may be used e.g. when JSON has been retrieved from a database TEXT column)
  // - by default, a temporary instance will be created if a published field
  // has a setter, and the instance is expected to be released later by the
  // owner class: set jpoSetterExpectsToFreeTempInstance to let JsonParser
  // (and TPropInfo.ClassFromJson) release it when the setter returns, and
  // jpoSetterNoCreate to avoid the published field instance creation
  // - set jpoAllowInt64Hex to let Int64/QWord fields accept hexadecimal string
  // (as generated e.g. via the woInt64AsHex option)
  // - by default, double values won't be stored as variant values, unless
  // jpoAllowDouble is set - see also dvoAllowDoubleValue in TDocVariantOptions
  // - jpoObjectListClassNameGlobalFindClass would also search for "ClassName":
  // TObjectList serialized field with the global Classes.FindClass() function
  // - null will release any class instance, unless jpoNullDontReleaseObjectInstance
  // is set which will leave the instance untouched
  // - values will be left untouched before parsing, unless jpoClearValues
  // is defined, to void existing record fields or class published properties
  TJsonParserOption = (
    jpoIgnoreUnknownProperty,
    jpoIgnoreStringType,
    jpoIgnoreUnknownEnum,
    jpoHandleCustomVariants,
    jpoHandleCustomVariantsWithinString,
    jpoSetterExpectsToFreeTempInstance,
    jpoSetterNoCreate,
    jpoAllowInt64Hex,
    jpoAllowDouble,
    jpoObjectListClassNameGlobalFindClass,
    jpoNullDontReleaseObjectInstance,
    jpoClearValues);

  /// set of options for JsonParser() parsing process
  TJsonParserOptions = set of TJsonParserOption;

  /// efficient execution context of the JSON parser
  // - defined here for low-level use of TRttiJsonLoad functions
  TJsonParserContext = object
  public
    /// current position in the JSON input
    Json: PUtf8Char;
    /// true if the last parsing succeeded
    Valid: boolean;
    /// the last parsed character, just before current JSON
    EndOfObject: AnsiChar;
    /// customize parsing
    Options: TJsonParserOptions;
    /// how TDocVariant should be created
    CustomVariant: PDocVariantOptions;
    /// contains the current value RTTI
    Info: TRttiCustom;
    /// contains the current property value RTTI
    Prop: PRttiCustomProp;
    /// force the item class when reading a TObjectList without "ClassName":...
    ObjectListItem: TRttiCustom;
    /// ParseNext unserialized value
    Value: PUtf8Char;
    /// ParseNext unserialized value length
    ValueLen: integer;
    /// if ParseNext unserialized a JSON string
    WasString: boolean;
    /// TDocVariant initialization options
    DVO: TDocVariantOptions;
    /// initialize this unserialization context
    procedure Init(P: PUtf8Char; Rtti: TRttiCustom; O: TJsonParserOptions;
      CV: PDocVariantOptions; ObjectListItemClass: TClass);
    /// call GetJsonField() to retrieve the next JSON value
    // - on success, return true and set Value/ValueLen and WasString fields
    function ParseNext: boolean;
      {$ifdef HASINLINE}inline;{$endif}
    /// retrieve the next JSON value as UTF-8 text
    function ParseUtf8: RawUtf8;
    /// retrieve the next JSON value as VCL string text
    function ParseString: string;
    /// set the EndOfObject field of a JSON buffer, just like GetJsonField() does
    // - to be called whan a JSON object or JSON array has been manually parsed
    procedure ParseEndOfObject;
      {$ifdef HASINLINE}inline;{$endif}
    /// parse a 'null' value from JSON buffer
    function ParseNull: boolean;
      {$ifdef HASINLINE}inline;{$endif}
    /// parse initial '[' token from JSON buffer
    // - once all the nested values have been read, call ParseEndOfObject
    function ParseArray: boolean;
    /// parse a JSON object from the buffer into a
    // - if ObjectListItem was not defined, expect the JSON input to start as
    // '{"ClassName":"TMyClass",...}'
    function ParseNewObject: TObject;
      {$ifdef HASINLINE}inline;{$endif}
    /// wrapper around JsonDecode() to easily get JSON object values
    function ParseObject(const Names: array of RawUtf8;
      Values: PValuePUtf8CharArray;
      HandleValuesAsObjectOrArray: boolean = false): boolean;
    /// parse a property value, properly calling any setter
    procedure ParseProp(Data: pointer);
  end;

  PJsonParserContext = ^TJsonParserContext;

  /// internal function handler for JSON reading of any TRttiParserType value
  TRttiJsonLoad = procedure(Data: pointer; var Ctxt: TJsonParserContext);


var
  /// default options for the JSON parser
  // - as supplied to LoadJson() with Tolerant=false
  // - defined as var, not as const, to allow process-wide override
  JSONPARSER_DEFAULTOPTIONS: TJsonParserOptions = [];

  /// some open-minded options for the JSON parser
  // - as supplied to LoadJson() with Tolerant=true
  // - won't block JSON unserialization due to some minor unexpected values
  // - used e.g. by TObjArraySerializer.CustomReader and
  // TInterfacedObjectFake.FakeCall/TServiceMethodExecute.ExecuteJson methods
  // - defined as var, not as const, to allow process-wide override
  JSONPARSER_TOLERANTOPTIONS: TJsonParserOptions =
    [jpoHandleCustomVariants, jpoIgnoreUnknownEnum,
     jpoIgnoreUnknownProperty, jpoIgnoreStringType, jpoAllowInt64Hex];

  /// access default (false) or tolerant (true) JSON parser options
  // - to be used as JSONPARSER_DEFAULTORTOLERANTOPTIONS[tolerant]
  JSONPARSER_DEFAULTORTOLERANTOPTIONS: array[boolean] of TJsonParserOptions = (
    [],
    [jpoHandleCustomVariants, jpoIgnoreUnknownEnum,
     jpoIgnoreUnknownProperty, jpoIgnoreStringType, jpoAllowInt64Hex]);

{$ifndef PUREMORMOT2}
// backward compatibility types redirections

type
  TJsonToObjectOption = TJsonParserOption;
  TJsonToObjectOptions = TJsonParserOptions;

const
  j2oSQLRawBlobAsBase64 = woRawBlobAsBase64;
  j2oIgnoreUnknownProperty = jpoIgnoreUnknownProperty;
  j2oIgnoreStringType = jpoIgnoreStringType;
  j2oIgnoreUnknownEnum = jpoIgnoreUnknownEnum;
  j2oHandleCustomVariants = jpoHandleCustomVariants;
  j2oHandleCustomVariantsWithinString = jpoHandleCustomVariantsWithinString;
  j2oSetterExpectsToFreeTempInstance = jpoSetterExpectsToFreeTempInstance;
  j2oSetterNoCreate = jpoSetterNoCreate;
  j2oAllowInt64Hex = jpoAllowInt64Hex;

const
  JSONTOOBJECT_TOLERANTOPTIONS: TJsonParserOptions =
    [jpoHandleCustomVariants, jpoIgnoreUnknownEnum,
     jpoIgnoreUnknownProperty, jpoIgnoreStringType, jpoAllowInt64Hex];

{$endif PUREMORMOT2}


{ ********** Custom JSON Serialization }

type
  /// the callback signature used by TRttiJson for serializing JSON data
  // - Data^ should be written into W, with the supplied Options
  TOnRttiJsonWrite = procedure(W: TTextWriter; Data: pointer;
    Options: TTextWriterWriteObjectOptions) of object;

  /// the callback signature used by TRttiJson for unserializing JSON data
  // - set Context.Valid=true if Context.JSON has been parsed into Data^
  TOnRttiJsonRead = procedure(var Context: TJsonParserContext;
    Data: pointer) of object;

  /// the callback signature used by TRttiJson for serializing JSON classes
  // - Instance should be written into W, with the supplied Options
  // - is in fact a convenient alias to the TOnRttiJsonWrite callback
  TOnClassJsonWrite = procedure(W: TTextWriter; Instance: TObject;
    Options: TTextWriterWriteObjectOptions) of object;

  /// the callback signature used by TRttiJson for unserializing JSON classes
  // - set Context.Valid=true if Context.JSON has been parsed into Instance
  // - is in fact a convenient alias to the TOnRttiJsonRead callback
  TOnClassJsonRead = procedure(var Context: TJsonParserContext;
    Instance: TObject) of object;

  /// JSON-aware TRttiCustom class - used for global RttiCustom: TRttiCustomList
  TRttiJson = class(TRttiCustom)
  protected
    fCompare: array[boolean] of TRttiCompare;
    fIncludeReadOptions: TJsonParserOptions;
    fIncludeWriteOptions: TTextWriterWriteObjectOptions;
    // overriden for proper JSON process - set fJsonSave and fJsonLoad
    function SetParserType(aParser: TRttiParserType;
      aParserComplex: TRttiParserComplexType): TRttiCustom; override;
  public
    /// simple wrapper around TRttiJsonSave(fJsonSave)
    procedure RawSaveJson(Data: pointer; const Ctxt: TJsonSaveContext);
      {$ifdef HASINLINE}inline;{$endif}
    /// simple wrapper around TRttiJsonLoad(fJsonLoad)
    procedure RawLoadJson(Data: pointer; var Ctxt: TJsonParserContext);
      {$ifdef HASINLINE}inline;{$endif}
    /// create and parse a new TObject instance of this rkClass
    function ParseNewInstance(var Context: TJsonParserContext): TObject;
    /// compare two stored values of this type
    function ValueCompare(Data, Other: pointer; CaseInsensitive: boolean): integer; override;
    /// unserialize some JSON input into Data^
    procedure ValueLoadJson(Data: pointer; var Json: PUtf8Char; EndOfObject: PUtf8Char;
      ParserOptions: TJsonParserOptions; CustomVariantOptions: PDocVariantOptions;
      ObjectListItemClass: TClass = nil);
    /// efficient search of TRttiJson from a given RTTI TypeInfo()
    // - to be used instead of Rtti.Find() to return directly the TRttiJson instance
    class function Find(Info: PRttiInfo): TRttiJson;
      {$ifdef HASINLINE}inline;{$endif}
    /// register a custom callback for JSON serialization of a given TypeInfo()
    // - for a dynamic array, will customize the item serialization callbacks
    // - replace deprecated TJsonSerializer.RegisterCustomSerializer() method
    class function RegisterCustomSerializer(Info: PRttiInfo;
      const Reader: TOnRttiJsonRead; const Writer: TOnRttiJsonWrite): TRttiJson;
    /// unregister any custom callback for JSON serialization of a given TypeInfo()
    // - will also work after RegisterFromText()
    class function UnRegisterCustomSerializer(Info: PRttiInfo): TRttiJson;
    /// register a custom callback for JSON serialization of a given class
    // - replace deprecated TJsonSerializer.RegisterCustomSerializer() method
    class function RegisterCustomSerializerClass(ObjectClass: TClass;
      const Reader: TOnClassJsonRead; const Writer: TOnClassJsonWrite): TRttiJson;
    /// unregister any custom callback for JSON serialization of a given class
    class function UnRegisterCustomSerializerClass(ObjectClass: TClass): TRttiJson;
    /// register TypeInfo() custom JSON serialization for a given dynamic
    // array or record
    // - to be used instead of homonomous Rtti.RegisterFromText() to supply
    // an additional set of serialization/unserialization JSON options
    class function RegisterFromText(DynArrayOrRecord: PRttiInfo;
      const RttiDefinition: RawUtf8;
      IncludeReadOptions: TJsonParserOptions;
      IncludeWriteOptions: TTextWriterWriteObjectOptions): TRttiJson;
    /// define an additional set of unserialization JSON options
    // - is included for this type to the supplied TJsonParserOptions
    property IncludeReadOptions: TJsonParserOptions
      read fIncludeReadOptions write fIncludeReadOptions;
    /// define an additional set of serialization JSON options
    // - is included for this type to the supplied TTextWriterWriteObjectOptions
    property IncludeWriteOptions: TTextWriterWriteObjectOptions
      read fIncludeWriteOptions write fIncludeWriteOptions;
  end;


{ ********** JSON Serialization Wrapper Functions }

var
  /// the options used by TObjArraySerializer, TInterfacedObjectFake and
  // TServiceMethodExecute when serializing values as JSON
  // - used as DEFAULT_WRITEOPTIONS[DontStoreVoidJson]
  // - you can modify this global variable to customize the whole process
  DEFAULT_WRITEOPTIONS: array[boolean] of TTextWriterWriteObjectOptions = (
    [woDontStoreDefault, woRawBlobAsBase64],
    [woDontStoreDefault, woDontStoreVoid, woRawBlobAsBase64]);

  /// the options used by TSynJsonFileSettings.SaveIfNeeded
  // - you can modify this global variable to customize the whole process
  SETTINGS_WRITEOPTIONS: TTextWriterWriteObjectOptions =
    [woHumanReadable, woStoreStoredFalse, woHumanReadableFullSetsAsStar,
     woHumanReadableEnumSetAsComment, woInt64AsHex];

  /// the options used by TServiceFactoryServer.OnLogRestExecuteMethod
  // - you can modify this global variable to customize the whole process
  SERVICELOG_WRITEOPTIONS: TTextWriterWriteObjectOptions =
    [woDontStoreDefault, woDontStoreVoid, woHideSensitivePersonalInformation];


/// serialize most kind of content as JSON, using its RTTI
// - is just a wrapper around TTextWriter.AddTypedJson()
// - so would handle tkClass, tkEnumeration, tkSet, tkRecord, tkDynArray,
// tkVariant kind of content - other kinds would return 'null'
// - you can override serialization options if needed
procedure SaveJson(const Value; TypeInfo: PRttiInfo;
  Options: TTextWriterOptions; var result: RawUtf8); overload;

/// serialize most kind of content as JSON, using its RTTI
// - is just a wrapper around TTextWriter.AddTypedJson()
// - so would handle tkClass, tkEnumeration, tkSet, tkRecord, tkDynArray,
// tkVariant kind of content - other kinds would return 'null'
function SaveJson(const Value; TypeInfo: PRttiInfo;
  EnumSetsAsText: boolean = false): RawUtf8; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// save record into its JSON serialization as saved by TTextWriter.AddRecordJson
// - will use default Base64 encoding over RecordSave() binary - or custom true
// JSON format (as set by TTextWriter.RegisterCustomJsonSerializer or via
// enhanced RTTI), if available (following EnumSetsAsText optional parameter
// for nested enumerates and sets)
function RecordSaveJson(const Rec; TypeInfo: PRttiInfo;
  EnumSetsAsText: boolean = false): RawUtf8;
  {$ifdef HASINLINE}inline;{$endif}

/// serialize a dynamic array content as JSON
// - Value shall be set to the source dynamic array field
// - is just a wrapper around TTextWriter.AddDynArrayJson(), creating
// a temporary TDynArray wrapper on the stack
// - to be used e.g. for custom record JSON serialization, within a
// TDynArrayJsonCustomWriter callback or RegisterCustomJsonSerializerFromText()
// (following EnumSetsAsText optional parameter for nested enumerates and sets)
function DynArraySaveJson(const Value; TypeInfo: PRttiInfo;
  EnumSetsAsText: boolean = false): RawUtf8;

/// serialize a dynamic array content, supplied as raw binary buffer, as JSON
// - Value shall be set to the source dynamic array field
// - is just a wrapper around TTextWriter.AddDynArrayJson(), creating
// a temporary TDynArray wrapper on the stack
// - to be used e.g. for custom record JSON serialization, within a
// TDynArrayJsonCustomWriter callback or RegisterCustomJsonSerializerFromText()
function DynArrayBlobSaveJson(TypeInfo: PRttiInfo; BlobValue: pointer): RawUtf8;

/// will serialize any TObject into its UTF-8 JSON representation
/// - serialize as JSON the published integer, Int64, floating point values,
// TDateTime (stored as ISO 8601 text), string, variant and enumerate
// (e.g. boolean) properties of the object (and its parents)
// - would set twoForceJsonStandard to force standard (non-extended) JSON
// - the enumerates properties are stored with their integer index value
// - will write also the properties published in the parent classes
// - nested properties are serialized as nested JSON objects
// - any TCollection property will also be serialized as JSON arrays
// - you can add some custom serializers for ANY class, via mormot.core.json
// TRttiJson.RegisterCustomSerializer() class method
function ObjectToJson(Value: TObject;
  Options: TTextWriterWriteObjectOptions = [woDontStoreDefault]): RawUtf8;

/// will serialize set of TObject into its UTF-8 JSON representation
// - follows ObjectToJson()/TTextWriter.WriterObject() functions output
// - if Names is not supplied, the corresponding class names would be used
function ObjectsToJson(const Names: array of RawUtf8; const Values: array of TObject;
  Options: TTextWriterWriteObjectOptions = [woDontStoreDefault]): RawUtf8;

/// persist a class instance into a JSON file
// - returns TRUE on success, false on error (e.g. the file name is invalid
// or the file is existing and could not be overwritten)
function ObjectToJsonFile(Value: TObject; const JsonFile: TFileName;
  Options: TTextWriterWriteObjectOptions = [woHumanReadable]): boolean;

/// will serialize any TObject into its expanded UTF-8 JSON representation
// - includes debugger-friendly information, similar to TSynLog, i.e.
// class name and sets/enumerates as text
// - redirect to ObjectToJson() with the proper TTextWriterWriteObjectOptions,
// since our JSON serialization detects and serialize Exception.Message
function ObjectToJsonDebug(Value: TObject;
  Options: TTextWriterWriteObjectOptions = [woDontStoreDefault,
    woHumanReadable, woStoreClassName, woStorePointer]): RawUtf8;

/// unserialize most kind of content as JSON, using its RTTI, as saved by
// TTextWriter.AddRecordJson / RecordSaveJson
// - is just a wrapper around GetDataFromJson() global low-level function
// - returns nil on error, or the end of buffer on success
// - warning: the JSON buffer will be modified in-place during process - use
// a temporary copy if you need to access it later or if the string comes from
// a constant (refcount=-1) - see e.g. the overloaded RecordLoadJson()
function LoadJson(var Value; Json: PUtf8Char; TypeInfo: PRttiInfo;
  EndOfObject: PUtf8Char = nil; CustomVariantOptions: PDocVariantOptions = nil;
  Tolerant: boolean = true): PUtf8Char;

/// fill a record content from a JSON serialization as saved by
// TTextWriter.AddRecordJson / RecordSaveJson
// - will use default Base64 encoding over RecordSave() binary - or custom true
// JSON format (as set by TTextWriter.RegisterCustomJsonSerializer or via
// enhanced RTTI), if available
// - returns nil on error, or the end of buffer on success
// - warning: the JSON buffer will be modified in-place during process - use
// a temporary copy if you need to access it later or if the string comes from
// a constant (refcount=-1) - see e.g. the overloaded RecordLoadJson()
function RecordLoadJson(var Rec; Json: PUtf8Char; TypeInfo: PRttiInfo;
  EndOfObject: PUtf8Char = nil; CustomVariantOptions: PDocVariantOptions = nil;
  Tolerant: boolean = true): PUtf8Char; overload;

/// fill a record content from a JSON serialization as saved by
// TTextWriter.AddRecordJson / RecordSaveJson
// - this overloaded function will make a private copy before parsing it,
// so is safe with a read/only or shared string - but slightly slower
// - will use default Base64 encoding over RecordSave() binary - or custom true
// JSON format (as set by TTextWriter.RegisterCustomJsonSerializer or via
// enhanced RTTI), if available
function RecordLoadJson(var Rec; const Json: RawUtf8; TypeInfo: PRttiInfo;
  CustomVariantOptions: PDocVariantOptions = nil;
  Tolerant: boolean = true): boolean; overload;

/// fill a dynamic array content from a JSON serialization as saved by
// TTextWriter.AddDynArrayJson
// - Value shall be set to the target dynamic array field
// - is just a wrapper around TDynArray.LoadFromJson(), creating a temporary
// TDynArray wrapper on the stack
// - return a pointer at the end of the data read from JSON, nil in case
// of an invalid input buffer
// - to be used e.g. for custom record JSON unserialization, within a
// TDynArrayJsonCustomReader callback
// - warning: the JSON buffer will be modified in-place during process - use
// a temporary copy if you need to access it later or if the string comes from
// a constant (refcount=-1) - see e.g. the overloaded DynArrayLoadJson()
function DynArrayLoadJson(var Value; Json: PUtf8Char; TypeInfo: PRttiInfo;
  EndOfObject: PUtf8Char = nil; CustomVariantOptions: PDocVariantOptions = nil;
  Tolerant: boolean = true): PUtf8Char; overload;

/// fill a dynamic array content from a JSON serialization as saved by
// TTextWriter.AddDynArrayJson, which won't be modified
// - this overloaded function will make a private copy before parsing it,
// so is safe with a read/only or shared string - but slightly slower
function DynArrayLoadJson(var Value; const Json: RawUtf8;
  TypeInfo: PRttiInfo; CustomVariantOptions: PDocVariantOptions = nil;
  Tolerant: boolean = true): boolean; overload;

/// read an object properties, as saved by ObjectToJson function
// - ObjectInstance must be an existing TObject instance
// - the data inside From^ is modified in-place (unescaped and transformed):
// calling JsonToObject(pointer(JSONRawUtf8)) will change the JSONRawUtf8
// variable content, which may not be what you expect - consider using the
// ObjectLoadJson() function instead
// - handle integer, Int64, enumerate (including boolean), set, floating point,
// TDateTime, TCollection, TStrings, TRawUtf8List, variant, and string properties
// (excluding ShortString, but including WideString and UnicodeString under
// Delphi 2009+)
// - TList won't be handled since it may leak memory when calling TList.Clear
// - won't handle TObjectList (even if ObjectToJson is able to serialize
// them) since has no way of knowing the object type to add (TCollection.Add
// is missing), unless: 1. you set the TObjectListItemClass property as expected,
// and provide a TObjectList object, or 2. woStoreClassName option has been
// used at ObjectToJson() call and the corresponding classes have been previously
// registered by TJsonSerializer.RegisterClassForJson() (or Classes.RegisterClass)
// - will clear any previous TCollection objects, and convert any null JSON
// basic type into nil - e.g. if From='null', will call FreeAndNil(Value)
// - you can add some custom (un)serializers for ANY class, via mormot.core.json
// TRttiJson.RegisterCustomSerializer() class method
// - set Valid=TRUE on success, Valid=FALSE on error, and the main function
// will point in From at the syntax error place (e.g. on any unknown property name)
// - caller should explicitely perform a SetDefaultValuesObject(Value) if
// the default values are expected to be set before JSON parsing
function JsonToObject(var ObjectInstance; From: PUtf8Char;
  out Valid: boolean; TObjectListItemClass: TClass = nil;
  Options: TJsonParserOptions = []): PUtf8Char;

/// parse the supplied JSON with some tolerance about Settings format
// - will make a TSynTempBuffer copy for parsing, and un-comment it
// - returns true if the supplied JSON was successfully retrieved
// - returns false and set InitialJsonContent := '' on error
function JSONSettingsToObject(var InitialJsonContent: RawUtf8;
  Instance: TObject): boolean;

/// read an object properties, as saved by ObjectToJson function
// - ObjectInstance must be an existing TObject instance
// - this overloaded version will make a private copy of the supplied JSON
// content (via TSynTempBuffer), to ensure the original buffer won't be modified
// during process, before calling safely JsonToObject()
// - will return TRUE on success, or FALSE if the supplied JSON was invalid
function ObjectLoadJson(var ObjectInstance; const Json: RawUtf8;
  TObjectListItemClass: TClass = nil;
  Options: TJsonParserOptions = []): boolean;

/// create a new object instance, as saved by ObjectToJson(...,[...,woStoreClassName,...]);
// - JSON input should be either 'null', either '{"ClassName":"TMyClass",...}'
// - woStoreClassName option shall have been used at ObjectToJson() call
// - and the corresponding class shall have been previously registered by
// TJsonSerializer.RegisterClassForJson(), in order to retrieve the class type
// from it name - or, at least, by a Classes.RegisterClass() function call
// - the data inside From^ is modified in-place (unescaped and transformed):
// don't call JsonToObject(pointer(JSONRawUtf8)) but makes a temporary copy of
// the JSON text buffer before calling this function, if want to reuse it later
function JsonToNewObject(var From: PUtf8Char; var Valid: boolean;
  Options: TJsonParserOptions = []): TObject;

/// read an TObject published property, as saved by ObjectToJson() function
// - will use direct in-memory reference to the object, or call the corresponding
// setter method (if any), creating a temporary instance
// - unserialize the JSON input buffer via a call to JsonToObject()
// - by default, a temporary instance will be created if a published field
// has a setter, and the instance is expected to be released later by the
// owner class: you can set the j2oSetterExpectsToFreeTempInstance option
// to let this method release it when the setter returns
function PropertyFromJson(Prop: PRttiCustomProp; Instance: TObject;
  From: PUtf8Char; var Valid: boolean;
  Options: TJsonParserOptions = []): PUtf8Char;

/// decode a specified parameter compatible with URI encoding into its original
// object contents
// - ObjectInstance must be an existing TObject instance
// - will call internally JsonToObject() function to unserialize its content
// - UrlDecodeExtended('price=20.45&where=LastName%3D%27M%C3%B4net%27','PRICE=',P,@Next)
// will return Next^='where=...' and P=20.45
// - if Upper is not found, Value is not modified, and result is FALSE
// - if Upper is found, Value is modified with the supplied content, and result is TRUE
function UrlDecodeObject(U: PUtf8Char; Upper: PAnsiChar;
  var ObjectInstance; Next: PPUtf8Char = nil;
  Options: TJsonParserOptions = []): boolean;

/// fill the object properties from a JSON file content
// - ObjectInstance must be an existing TObject instance
// - this function will call RemoveCommentsFromJson() before process
function JsonFileToObject(const JsonFile: TFileName; var ObjectInstance;
  TObjectListItemClass: TClass = nil;
  Options: TJsonParserOptions = []): boolean;


const
  /// standard header for an UTF-8 encoded XML file
  XMLUTF8_HEADER = '<?xml version="1.0" encoding="UTF-8"?>'#13#10;

  /// standard namespace for a generic XML File
  XMLUTF8_NAMESPACE = '<contents xmlns="http://www.w3.org/2001/XMLSchema-instance">';

/// convert a JSON array or document into a simple XML content
// - just a wrapper around TTextWriter.AddJsonToXML, with an optional
// header before the XML converted data (e.g. XMLUTF8_HEADER), and an optional
// name space content node which will nest the generated XML data (e.g.
// '<contents xmlns="http://www.w3.org/2001/XMLSchema-instance">') - the
// corresponding ending token will be appended after (e.g. '</contents>')
// - WARNING: the JSON buffer is decoded in-place, so P^ WILL BE modified
procedure JsonBufferToXML(P: PUtf8Char; const Header, NameSpace: RawUtf8;
  out result: RawUtf8);

/// convert a JSON array or document into a simple XML content
// - just a wrapper around TTextWriter.AddJsonToXML, making a private copy
// of the supplied JSON buffer using TSynTempBuffer (so that JSON content
// would stay untouched)
// - the optional header is added at the beginning of the resulting string
// - an optional name space content node could be added around the generated XML,
// e.g. '<content>'
function JsonToXML(const Json: RawUtf8; const Header: RawUtf8 = XMLUTF8_HEADER;
  const NameSpace: RawUtf8 = ''): RawUtf8;


{ ********************* Abstract Classes with Auto-Create-Fields }

/// should be called by T*AutoCreateFields constructors
// - will also register this class type, if needed, so RegisterClass() is
// redundant to this method
procedure AutoCreateFields(ObjectInstance: TObject);
  {$ifdef HASINLINE}inline;{$endif}

/// should be called by T*AutoCreateFields destructors
// - constructor should have called AutoCreateFields()
procedure AutoDestroyFields(ObjectInstance: TObject);
  {$ifdef HASINLINE}inline;{$endif}

/// internal function called by AutoCreateFields() when inlined
// - do not call this internal function, but always AutoCreateFields()
function DoRegisterAutoCreateFields(ObjectInstance: TObject): TRttiJson;


type
  /// abstract TPersistent class, which will instantiate all its nested TPersistent
  // class published properties, then release them (and any T*ObjArray) when freed
  // - TSynAutoCreateFields is to be preferred in most cases, thanks to its
  // lower overhead
  // - note that non published (e.g. public) properties won't be instantiated,
  // serialized, nor released - but may contain weak references to other classes
  // - please take care that you will not create any endless recursion: you should
  // ensure that at one level, nested published properties won't have any class
  // instance refering to its owner (there is no weak reference - remember!)
  // - since the destructor will release all nested properties, you should
  // never store a reference to any of those nested instances if this owner
  // may be freed before
  TPersistentAutoCreateFields = class(TPersistentWithCustomCreate)
  public
    /// this overriden constructor will instantiate all its nested
    // TPersistent/TSynPersistent/TSynAutoCreateFields published properties
    constructor Create; override;
    /// finalize the instance, and release its published properties
    destructor Destroy; override;
  end;

  /// our own empowered TPersistentAutoCreateFields-like parent class
  // - this class is a perfect parent to store any data by value, e.g. DDD Value
  // Objects, Entities or Aggregates
  // - is defined as an abstract class able with a virtual constructor, RTTI
  // for published properties, and automatic memory management of all nested
  // class published properties: any class defined as a published property will
  // be owned by this instance - i.e. with strong reference
  // - will also release any T*ObjArray dynamic array storage of persistents,
  // previously registered via Rtti.RegisterObjArray() for Delphi 7-2009
  // - nested published classes (or T*ObjArray) don't need to inherit from
  // TSynAutoCreateFields: they may be from any TPersistent/TSynPersistent type
  // - note that non published (e.g. public) properties won't be instantiated,
  // serialized, nor released - but may contain weak references to other classes
  // - please take care that you will not create any endless recursion: you should
  // ensure that at one level, nested published properties won't have any class
  // instance refering to its owner (there is no weak reference - remember!)
  // - since the destructor will release all nested properties, you should
  // never store a reference to any of those nested instances if this owner
  // may be freed before
  // - TPersistent/TPersistentAutoCreateFields have an unexpected speed overhead
  // due a giant lock introduced to manage property name fixup resolution
  // (which we won't use outside the VCL) - this class is definitively faster
  TSynAutoCreateFields = class(TSynPersistent)
  public
    /// this overriden constructor will instantiate all its nested
    // TPersistent/TSynPersistent/TSynAutoCreateFields published properties
    constructor Create; override;
    /// finalize the instance, and release its published properties
    destructor Destroy; override;
  end;

  /// adding locking methods to a TSynAutoCreateFields with virtual constructor
  TSynAutoCreateFieldsLocked = class(TSynPersistentLock)
  public
    /// initialize the object instance, and its associated lock
    constructor Create; override;
    /// release the instance (including the locking resource)
    destructor Destroy; override;
  end;

  /// abstract TInterfacedObject class, which will instantiate all its nested
  // TPersistent/TSynPersistent published properties, then release them when freed
  // - will handle automatic memory management of all nested class and T*ObjArray
  // published properties: any class or T*ObjArray defined as a published
  // property will be owned by this instance - i.e. with strong reference
  // - non published properties (e.g. public) won't be instantiated, so may
  // store weak class references
  // - could be used for gathering of TCollectionItem properties, e.g. for
  // Domain objects in DDD, especially for list of value objects, with some
  // additional methods defined by an Interface
  // - since the destructor will release all nested properties, you should
  // never store a reference to any of those nested instances if this owner
  // may be freed before
  TInterfacedObjectAutoCreateFields = class(TInterfacedObjectWithCustomCreate)
  public
    /// this overriden constructor will instantiate all its nested
    // TPersistent/TSynPersistent/TSynAutoCreateFields class and T*ObjArray
    // published properties
    constructor Create; override;
    /// finalize the instance, and release its published properties
    destructor Destroy; override;
  end;

  /// abstract TCollectionItem class, which will instantiate all its nested class
  // published properties, then release them (and any T*ObjArray) when freed
  // - could be used for gathering of TCollectionItem properties, e.g. for
  // Domain objects in DDD, especially for list of value objects
  // - consider using T*ObjArray dynamic array published properties in your
  // value types instead of TCollection storage: T*ObjArray have a lower overhead
  // and are easier to work with, once Rtti.RegisterObjArray is called on Delphi
  // 7-2009 to register the T*ObjArray type (not needed on FPC and Delphi 2010+)
  // - note that non published (e.g. public) properties won't be instantiated,
  // serialized, nor released - but may contain weak references to other classes
  // - please take care that you will not create any endless recursion: you should
  // ensure that at one level, nested published properties won't have any class
  // instance refering to its owner (there is no weak reference - remember!)
  // - since the destructor will release all nested properties, you should
  // never store a reference to any of those nested instances if this owner
  // may be freed before
  TCollectionItemAutoCreateFields = class(TCollectionItem)
  public
    /// this overriden constructor will instantiate all its nested
    // TPersistent/TSynPersistent/TSynAutoCreateFields published properties
    constructor Create(Collection: TCollection); override;
    /// finalize the instance, and release its published properties
    destructor Destroy; override;
  end;

  /// abstract parent class able to store settings as JSON file
  TSynJsonFileSettings = class(TSynAutoCreateFields)
  protected
    fInitialJsonContent: RawUtf8;
    fFileName: TFileName;
  public
    /// read existing settings from a JSON content
    function LoadFromJson(var aJson: RawUtf8): boolean;
    /// read existing settings from a JSON file
    function LoadFromFile(const aFileName: TFileName): boolean; virtual;
    /// persist the settings as a JSON file, named from LoadFromFile() parameter
    procedure SaveIfNeeded; virtual;
    /// optional persistence file name, as set by LoadFromFile()
    property FileName: TFileName
      read fFileName;
  end;


implementation

uses
  mormot.core.datetime,
  mormot.core.variants;


{ ********** Low-Level JSON Processing Functions }

function NeedsJsonEscape(P: PUtf8Char; PLen: integer): boolean;
var
  tab: PByteArray;
begin
  result := true;
  tab := @JSON_ESCAPE;
  if PLen > 0 then
    repeat
      if tab[ord(P^)] <> JSON_ESCAPE_NONE then
        exit;
      inc(P);
      dec(PLen);
    until PLen = 0;
  result := false;
end;

function NeedsJsonEscape(const Text: RawUtf8): boolean;
begin
  result := NeedsJsonEscape(pointer(Text), length(Text));
end;

function NeedsJsonEscape(P: PUtf8Char): boolean;
var
  tab: PByteArray;
  esc: byte;
begin
  result := false;
  if P = nil then
    exit;
  tab := @JSON_ESCAPE;
  repeat
    esc := tab[ord(P^)];
    if esc = JSON_ESCAPE_NONE then
      inc(P)
    else if esc = JSON_ESCAPE_ENDINGZERO then
      exit
    else
      break;
  until false;
  result := true;
end;

function JsonEscapeToUtf8(var D: PUtf8Char;  P: PUtf8Char): PUtf8Char;
var
  c, s: cardinal;
begin
  // P^ points at 'u1234' just after \u0123
  c := (ConvertHexToBin[ord(P[1])] shl 12) or
       (ConvertHexToBin[ord(P[2])] shl 8) or
       (ConvertHexToBin[ord(P[3])] shl 4) or
        ConvertHexToBin[ord(P[4])];
  if c = 0 then
    D^ := '?' // \u0000 is an invalid value
  else if c <= $7f then
    D^ := AnsiChar(c)
  else if c < $7ff then
  begin
    D[0] := AnsiChar($C0 or (c shr 6));
    D[1] := AnsiChar($80 or (c and $3F));
    inc(D);
  end
  else if (c >= UTF16_HISURROGATE_MIN) and
          (c <= UTF16_LOSURROGATE_MAX) then
    if PWord(P + 5)^ = ord('\') + ord('u') shl 8 then
    begin
      s := (ConvertHexToBin[ord(P[7])] shl 12)+
           (ConvertHexToBin[ord(P[8])] shl 8)+
           (ConvertHexToBin[ord(P[9])] shl 4)+
            ConvertHexToBin[ord(P[10])];
      case c of // inlined Utf16CharToUtf8()
        UTF16_HISURROGATE_MIN..UTF16_HISURROGATE_MAX:
          c := ((c - $D7C0) shl 10) or (s xor UTF16_LOSURROGATE_MIN);
        UTF16_LOSURROGATE_MIN..UTF16_LOSURROGATE_MAX:
          c := ((s - $D7C0)shl 10) or (c xor UTF16_LOSURROGATE_MIN);
      end;
      inc(D, Ucs4ToUtf8(c, D));
      result := P + 11;
      exit;
    end
    else
      D^ := '?'
  else
  begin
    D[0] := AnsiChar($E0 or (c shr 12));
    D[1] := AnsiChar($80 or ((c shr 6) and $3F));
    D[2] := AnsiChar($80 or (c and $3F));
    inc(D,2);
  end;
  inc(D);
  result := P + 5;
end;

function IsString(P: PUtf8Char): boolean;  // test if P^ is a "string" value
begin
  if P = nil then
  begin
    result := false;
    exit;
  end;
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  if (P[0] in ['0'..'9']) or // is first char numeric?
     ((P[0] in ['-', '+']) and
      (P[1] in ['0'..'9'])) then
  begin
    // check if P^ is a true numerical value
    repeat
      inc(P);
    until not (P^ in ['0'..'9']); // check digits
    if P^ = '.' then
      repeat
        inc(P);
      until not (P^ in ['0'..'9']); // check fractional digits
    if ((P^ = 'e') or
        (P^ = 'E')) and
       (P[1] in ['0'..'9', '+', '-']) then
    begin
      inc(P);
      if P^ = '+' then
        inc(P)
      else if P^ = '-' then
        inc(P);
      while (P^ >= '0') and
            (P^ <= '9') do
        inc(P);
    end;
    while (P^ <= ' ') and
          (P^ <> #0) do
      inc(P);
    result := (P^ <> #0);
    exit;
  end
  else
    result := true; // don't begin with a numerical value -> must be a string
end;

function IsStringJson(P: PUtf8Char): boolean;  // test if P^ is a "string" value
var
  c4: integer;
  c: AnsiChar;
  tab: PJsonCharSet;
begin
  if P = nil then
  begin
    result := false;
    exit;
  end;
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  tab := @JSON_CHARS;
  c4 := PInteger(P)^;
  if (((c4 = NULL_LOW) or
       (c4 = TRUE_LOW)) and
      (jcEndOfJsonValueField in tab[P[4]])) or
     ((c4 = FALSE_LOW) and
      (P[4] = 'e') and
      (jcEndOfJsonValueField in tab[P[5]])) then
  begin
    result := false; // constants are no string
    exit;
  end;
  c := P^;
  if (jcDigitFirstChar in tab[c]) and
     (((c >= '1') and (c <= '9')) or // is first char numeric?
     ((c = '0') and ((P[1] < '0') or
                     (P[1] > '9'))) or // '012' excluded by JSON
     ((c = '-') and (P[1] >= '0') and (P[1] <= '9'))) then
  begin
    // check if c is a true numerical value
    repeat
      inc(P);
    until (P^ < '0') or
          (P^ > '9'); // check digits
    if P^ = '.' then
      repeat
        inc(P);
      until (P^ < '0') or
            (P^ > '9'); // check fractional digits
    if ((P^ = 'e') or
        (P^ = 'E')) and
       (jcDigitFirstChar in tab[P[1]]) then
    begin
      inc(P);
      c := P^;
      if c = '+' then
        inc(P)
      else if c = '-' then
        inc(P);
      while (P^ >= '0') and
            (P^ <= '9') do
        inc(P);
    end;
    while (P^ <= ' ') and
          (P^ <> #0) do
      inc(P);
    result := (P^ <> #0);
    exit;
  end
  else
    result := true; // don't begin with a numerical value -> must be a string
end;

function IsValidJson(const s: RawUtf8): boolean;
begin
  result := IsValidJson(pointer(s), length(s));
end;

function IsValidJson(P: PUtf8Char; len: PtrInt): boolean;
var
  B: PUtf8Char;
begin
  result := false;
  if (P = nil) or
     (len <= 0) or
     // ensure there is no unexpected/unsupported #0 in the middle of input
     (StrLen(P) <> len) then
    exit;
  B := P;
  P :=  GotoEndJsonItemStrict(B);
  result := (P <> nil) and
            (P - B = len);
end;

procedure IgnoreComma(var P: PUtf8Char);
begin
  if P <> nil then
  begin
    while (P^ <= ' ') and
          (P^ <> #0) do
      inc(P);
    if P^ = ',' then
      inc(P);
  end;
end;

function JsonPropNameValid(P: PUtf8Char): boolean;
var
  tab: PJsonCharSet;
begin
  tab := @JSON_CHARS;
  if (P <> nil) and
     (jcJsonIdentifierFirstChar in tab[P^]) then
  begin
    // ['_', '0'..'9', 'a'..'z', 'A'..'Z', '$']
    repeat
      inc(P);
    until not (jcJsonIdentifier in tab[P^]);
    // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '.', '[', ']']
    result := P^ = #0;
  end
  else
    result := false;
end;

type
  TJsonToken = (
    jtNone,
    jtDoubleQuote,
    jtFirstDigit,
    jtNullFirstChar,
    jtTrueFirstChar,
    jtFalseFirstChar,
    jtObjectStart,
    jtObjectStop,
    jtArrayStart,
    jtArrayStop,
    jtAssign,
    jtComma,
    jtSingleQuote,
    jtIdentifierFirstChar,
    jtSlash);
  TJsonTokens = array[AnsiChar] of TJsonToken;
  PJsonTokens = ^TJsonTokens;

var
  JSON_TOKENS: TJsonTokens;

function GetJsonField(P: PUtf8Char; out PDest: PUtf8Char; WasString: PBoolean;
  EndOfObject: PUtf8Char; Len: PInteger): PUtf8Char;
var
  D: PUtf8Char;
  c4, surrogate, extra: PtrUInt;
  c: AnsiChar;
  {$ifdef CPUX86NOTPIC}
  jsonset: TJsonCharSet absolute JSON_CHARS; // not enough registers
  {$else}
  jsonset: PJsonCharSet;
  {$endif CPUX86NOTPIC}
label
  lit;
begin
  // see http://www.ietf.org/rfc/rfc4627.txt
  if WasString <> nil then
    // not a string by default
    WasString^ := false;
  if Len <> nil then
    // ensure returns Len=0 on invalid input (PDest=nil)
    Len^ := 0;
  PDest := nil; // PDest=nil indicates error or unexpected end (#0)
  result := nil;
  if P = nil then
    exit;
  while P^ <= ' ' do
  begin
    if P^ = #0 then
      exit;
    inc(P);
  end;
  {$ifndef CPUX86NOTPIC}
  jsonset := @JSON_CHARS;
  {$endif CPUX86NOTPIC}
  case JSON_TOKENS[P^] of
    jtFirstDigit: // '-', '0'..'9'
      begin
        // numerical value
        result := P;
        if P^ = '0' then
          if (P[1] >= '0') and
             (P[1] <= '9') then
            // 0123 excluded by JSON!
            exit;
        repeat // loop all '-', '+', '0'..'9', '.', 'E', 'e'
          inc(P);
        until not (jcDigitFloatChar in jsonset[P^]);
        if P^ = #0 then
          exit; // a JSON number value should be followed by , } or ]
        if Len <> nil then
          Len^ := P - result;
        if P^ <= ' ' then
        begin
          P^ := #0; // force numerical field with no trailing ' '
          inc(P);
        end;
      end;
    jtDoubleQuote: // '"'
      begin
        // " -> unescape P^ into D^
       inc(P);
       result := P; // result points to the unescaped JSON string
        if WasString <> nil then
          WasString^ := true;
        while not (jcJsonStringMarker in jsonset[P^]) do
          // not [#0, '"', '\']
          inc(P); // very fast parsing of most UTF-8 chars within "string"
        D := P;
        if P^ <> '"' then
        repeat
          // escape needed -> inplace unescape from P^ into D^
          c := P^;
          if not (jcJsonStringMarker in jsonset[c]) then
          begin
lit:        inc(P);
            D^ := c;
            inc(D);
            continue; // very fast parsing of most UTF-8 chars within "string"
          end;
          // P^ is either #0, '"' or '\'
          if c = '"' then
            // end of string
            break;
          if c = #0 then
            // premature ending (PDest=nil)
            exit;
          // unescape JSON text: get char after \
          inc(P); // P^ was '\' here
          c := P^;
          if (c = '"') or
             (c = '\') then
            // most common cases are \\ or \"
            goto lit
          else if c = #0 then
            // to avoid potential buffer overflow issue on \#0
            exit
          else if c = 'b' then
            c := #8
          else if c = 't' then
            c := #9
          else if c = 'n' then
            c := #10
          else if c = 'f' then
            c := #12
          else if c = 'r' then
            c := #13
          else if c = 'u' then
          begin
            // decode '\u0123' UTF-16 into UTF-8
            // note: JsonEscapeToUtf8() inlined here to optimize GetJsonField
            c4 := (ConvertHexToBin[ord(P[1])] shl 12) or
                  (ConvertHexToBin[ord(P[2])] shl 8) or
                  (ConvertHexToBin[ord(P[3])] shl 4) or
                   ConvertHexToBin[ord(P[4])];
            inc(P, 5); // optimistic conversion (no check)
            case c4 of
              0:
                begin
                  // \u0000 is an invalid value (at least in our framework)
                  D^ := '?';
                  inc(D);
                end;
              1..$7f:
                begin
                  D^ := AnsiChar(c4);
                  inc(D);
                end;
              $80..$7ff:
                begin
                  D[0] := AnsiChar($C0 or (c4 shr 6));
                  D[1] := AnsiChar($80 or (c4 and $3F));
                  inc(D, 2);
                end;
              UTF16_HISURROGATE_MIN..UTF16_LOSURROGATE_MAX:
                if PWord(P)^ = ord('\') + ord('u') shl 8 then
                begin
                  inc(P);
                  surrogate := (ConvertHexToBin[ord(P[1])] shl 12) or
                               (ConvertHexToBin[ord(P[2])] shl 8) or
                               (ConvertHexToBin[ord(P[3])] shl 4) or
                                ConvertHexToBin[ord(P[4])];
                  case c4 of
                    // inlined Utf16CharToUtf8()
                    UTF16_HISURROGATE_MIN..UTF16_HISURROGATE_MAX:
                      c4 := ((c4 - $D7C0) shl 10) or
                         (surrogate xor UTF16_LOSURROGATE_MIN);
                    UTF16_LOSURROGATE_MIN..UTF16_LOSURROGATE_MAX:
                      c4 := ((surrogate - $D7C0) shl 10) or
                         (c4 xor UTF16_LOSURROGATE_MIN);
                  end;
                  if c4 <= $7ff then
                    c := #2
                  else if c4 <= $ffff then
                    c := #3
                  else if c4 <= $1FFFFF then
                    c := #4
                  else if c4 <= $3FFFFFF then
                    c := #5
                  else
                    c := #6;
                  extra := ord(c) - 1;
                  repeat
                    D[extra] := AnsiChar((c4 and $3f) or $80);
                    c4 := c4 shr 6;
                    dec(extra);
                  until extra = 0;
                  D^ := AnsiChar(byte(c4) or UTF8_TABLE.FirstByte[ord(c)]);
                  inc(D, ord(c));
                  inc(P, 5);
                end
                else
                begin
                  // unexpected surrogate without its pair
                  D^ := '?';
                  inc(D);
                end;
            else
              begin
                D[0] := AnsiChar($E0 or (c4 shr 12));
                D[1] := AnsiChar($80 or ((c4 shr 6) and $3F));
                D[2] := AnsiChar($80 or (c4 and $3F));
                inc(D, 3);
              end;
            end;
            continue;
          end;
          goto lit;
        until false;
        // here P^='"'
        inc(P);
        D^ := #0; // make zero-terminated
        if Len <> nil then
          Len^ := D - result;
      end;
    jtNullFirstChar: // 'n'
      if (PInteger(P)^ = NULL_LOW) and
         (jcEndOfJsonValueField in jsonset[P[4]]) then
         // [#0, #9, #10, #13, ' ',  ',', '}', ']']
      begin
        // null -> returns nil and WasString=false
        result := nil;
        if Len <> nil then
          Len^ := 0; // when result is converted to string
        inc(P, 4);
      end
      else
        exit;
    jtFalseFirstChar: // 'f'
      if (PInteger(P + 1)^ = FALSE_LOW2) and
         (jcEndOfJsonValueField in jsonset[P[5]]) then
         // [#0, #9, #10, #13, ' ',  ',', '}', ']']
      begin
        // false -> returns 'false' and WasString=false
        result := P;
        if Len <> nil then
          Len^ := 5;
        inc(P, 5);
      end
      else
        exit;
    jtTrueFirstChar: // 't'
      if (PInteger(P)^ = TRUE_LOW) and
         (jcEndOfJsonValueField in jsonset[P[4]]) then
         // [#0, #9, #10, #13, ' ',  ',', '}', ']']
      begin
        // true -> returns 'true' and WasString=false
        result := P;
        if Len <> nil then
          Len^ := 4;
        inc(P, 4);
      end
      else
        exit;
  else
    // leave PDest=nil to notify error
    exit;
  end;
  while not (jcEndOfJsonFieldOr0 in jsonset[P^]) do
    if P^ = #0 then
      // leave PDest=nil for unexpected end
      exit
    else
      // loop until #0 , ] } : delimiter
      inc(P);
  if EndOfObject <> nil then
    EndOfObject^ := P^;
  // ensure JSON value is zero-terminated, and continue after it
  if P^ <> #0 then
  begin
    P^ := #0;
    PDest := P + 1;
  end
  else
    PDest := P;
end;

function GotoEndOfJsonString(P: PUtf8Char; tab: PJsonCharSet): PUtf8Char;
begin
  // P^='"' at function call
  inc(P);
  repeat
    if not (jcJsonStringMarker in tab[P^]) then
    begin
      inc(P);   // not [#0, '"', '\']
      continue; // very fast parsing of most UTF-8 chars
    end;
    if (P^ = '"') or
       (P^ = #0) or
       (P[1] = #0) then
      // end of string/buffer, or buffer overflow detected as \#0
      break;
    inc(P, 2); // P^ was '\' -> ignore \#
  until false;
  result := P;
  // P^='"' at function return (if input was correct)
end;

function GotoEndOfJsonString(P: PUtf8Char): PUtf8Char;
begin
  result := GotoEndOfJsonString(P, @JSON_CHARS);
end;

function GetJsonPropName(var P: PUtf8Char; Len: PInteger): PUtf8Char;
var
  Name: PUtf8Char;
  WasString: boolean;
  c, EndOfObject: AnsiChar;
  tab: PJsonCharSet;
begin
  // should match GotoNextJsonObjectOrArray() and JsonPropNameValid()
  result := nil;
  if P = nil then
    exit;
  while P^ <= ' ' do
  begin
    if P^ = #0 then
    begin
      P := nil;
      exit;
    end;
    inc(P);
  end;
  Name := P; // put here to please some versions of Delphi compiler
  c := P^;
  if c = '"' then
  begin
    Name := GetJsonField(P, P, @WasString, @EndOfObject, Len);
    if (Name = nil) or
       not WasString or
       (EndOfObject <> ':') then
      exit;
  end
  else if c = '''' then
  begin
    // single quotes won't handle nested quote character
    inc(P);
    Name := P;
    while P^ <> '''' do
      if P^ < ' ' then
        exit
      else
        inc(P);
    if Len <> nil then
      Len^ := P - Name;
    P^ := #0;
    repeat
      inc(P)
    until (P^ > ' ') or
          (P^ = #0);
    if P^ <> ':' then
      exit;
    inc(P);
  end
  else
  begin
    // e.g. '{age:{$gt:18}}'
    tab := @JSON_CHARS;
    if not (jcJsonIdentifierFirstChar in tab[c]) then
      exit; // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '$']
    repeat
      inc(P);
    until not (jcJsonIdentifier in tab[P^]);
    // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '.', '[', ']']
    if Len <> nil then
      Len^ := P - Name;
    if (P^ <= ' ') and
       (P^ <> #0) then
    begin
      P^ := #0;
      inc(P);
    end;
    while (P^ <= ' ') and
          (P^ <> #0) do
      inc(P);
    if not (P^ in [':', '=']) then
      // allow both age:18 and age=18 pairs (very relaxed JSON syntax)
      exit;
    P^ := #0;
    inc(P);
  end;
  result := Name;
end;

procedure GetJsonPropName(var P: PUtf8Char; out PropName: shortstring);
var
  Name: PAnsiChar;
  c: AnsiChar;
  tab: PJsonCharSet;
begin
  // match GotoNextJsonObjectOrArray() and overloaded GetJsonPropName()
  PropName[0] := #0;
  if P = nil then
    exit;
  while P^ <= ' ' do
  begin
    if P^ = #0 then
    begin
      P := nil;
      exit;
    end;
    inc(P);
  end;
  Name := pointer(P);
  c := P^;
  if c = '"' then
  begin
    inc(Name);
    tab := @JSON_CHARS;
    repeat
      inc(P);
    until jcJsonStringMarker in tab[P^]; // end at [#0, '"', '\']
    if P^ <> '"' then
      exit;
    SetString(PropName, Name, P - Name); // note: won't unescape JSON strings
    repeat
      inc(P)
    until (P^ > ' ') or
          (P^ = #0);
    if P^ <> ':' then
    begin
      PropName[0] := #0;
      exit;
    end;
    inc(P);
  end
  else if c = '''' then
  begin
    // single quotes won't handle nested quote character
    inc(P);
    inc(Name);
    while P^ <> '''' do
      if P^ < ' ' then
        exit
      else
        inc(P);
    SetString(PropName, Name, P - Name);
    repeat
      inc(P)
    until (P^ > ' ') or
          (P^ = #0);
    if P^ <> ':' then
    begin
      PropName[0] := #0;
      exit;
    end;
    inc(P);
  end
  else
  begin
    // e.g. '{age:{$gt:18}}'
    tab := @JSON_CHARS;
    if not (jcJsonIdentifierFirstChar in tab[c]) then
      exit; // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '$']
    repeat
      inc(P);
    until not (jcJsonIdentifier in tab[P^]);
    // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '.', '[', ']']
    SetString(PropName, Name, P - Name);
    while (P^ <= ' ') and
          (P^ <> #0) do
      inc(P);
    if (P^ <> ':') and
       (P^ <> '=') then
    begin
      // allow both age:18 and age=18 pairs (very relaxed JSON syntax)
      PropName[0] := #0;
      exit;
    end;
    inc(P);
  end;
end;

function GotoNextJsonPropName(P: PUtf8Char): PUtf8Char;
var
  c: AnsiChar;
  tab: PJsonCharSet;
label
  s;
begin
  // should match GotoNextJsonObjectOrArray()
  result := nil;
  if P = nil then
    exit;
  while P^ <= ' ' do
  begin
    if P^ = #0 then
      exit;
    inc(P);
  end;
  c := P^;
  if c = '"' then
  begin
    P := GotoEndOfJsonString(P, @JSON_CHARS);
    if P^ <> '"' then
      exit;
s:  repeat
      inc(P)
    until (P^ > ' ') or
          (P^ = #0);
    if P^ <> ':' then
      exit;
  end
  else if c = '''' then
  begin
    // single quotes won't handle nested quote character
    inc(P);
    while P^ <> '''' do
      if P^ < ' ' then
        exit
      else
        inc(P);
    goto s;
  end
  else
  begin
    // e.g. '{age:{$gt:18}}'
    tab := @JSON_CHARS;
    if not (jcJsonIdentifierFirstChar in tab[c]) then
      exit; // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '$']
    repeat
      inc(P);
    until not (jcJsonIdentifier in tab[P^]);
    // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '.', '[', ']']
    if (P^ <= ' ') and
       (P^ <> #0) then
      inc(P);
    while (P^ <= ' ') and
          (P^ <> #0) do
      inc(P);
    if not (P^ in [':', '=']) then
      // allow both age:18 and age=18 pairs (very relaxed JSON syntax)
      exit;
  end;
  repeat
    inc(P)
  until (P^ > ' ') or
        (P^ = #0);
  result := P;
end;


{ TValuePUtf8Char }

procedure TValuePUtf8Char.ToUtf8(var Text: RawUtf8);
begin
  FastSetString(Text, Value, ValueLen);
end;

function TValuePUtf8Char.ToUtf8: RawUtf8;
begin
  FastSetString(result, Value, ValueLen);
end;

function TValuePUtf8Char.ToString: string;
begin
  Utf8DecodeToString(Value, ValueLen, result);
end;

function TValuePUtf8Char.ToInteger: PtrInt;
begin
  result := GetInteger(Value);
end;

function TValuePUtf8Char.ToCardinal: PtrUInt;
begin
  result := GetCardinal(Value);
end;

function TValuePUtf8Char.Idem(const Text: RawUtf8): boolean;
begin
  result := (length(Text) = ValueLen) and
            ((ValueLen = 0) or
             IdemPropNameUSameLenNotNull(pointer(Text), Value, ValueLen));
end;


procedure JsonDecode(var Json: RawUtf8; const Names: array of RawUtf8;
  Values: PValuePUtf8CharArray; HandleValuesAsObjectOrArray: boolean);
begin
  JsonDecode(UniqueRawUtf8(Json), Names, Values, HandleValuesAsObjectOrArray);
end;

procedure JsonDecode(var Json: RawJson; const Names: array of RawUtf8;
  Values: PValuePUtf8CharArray; HandleValuesAsObjectOrArray: boolean);
begin
  JsonDecode(UniqueRawUtf8(RawUtf8(Json)), Names, Values, HandleValuesAsObjectOrArray);
end;

function JsonDecode(P: PUtf8Char; const Names: array of RawUtf8;
  Values: PValuePUtf8CharArray; HandleValuesAsObjectOrArray: boolean): PUtf8Char;
var
  n, i: PtrInt;
  namelen, valuelen: integer;
  name, value: PUtf8Char;
  EndOfObject: AnsiChar;
begin
  result := nil;
  if Values = nil then
    exit; // avoid GPF
  n := length(Names);
  FillCharFast(Values[0], n * SizeOf(Values[0]), 0);
  dec(n);
  if P = nil then
    exit;
  while P^ <> '{' do
    if P^ = #0 then
      exit
    else
      inc(P);
  inc(P); // jump {
  repeat
    name := GetJsonPropName(P, @namelen);
    if name = nil then
      exit;  // invalid Json content
    value := GetJsonFieldOrObjectOrArray(P, nil, @EndOfObject,
      HandleValuesAsObjectOrArray, true, @valuelen);
    if not (EndOfObject in [',', '}']) then
      exit; // invalid item separator
    for i := 0 to n do
      if (Values[i].value = nil) and
         IdemPropNameU(Names[i], name, namelen) then
      begin
        Values[i].value := value;
        Values[i].valuelen := valuelen;
        break;
      end;
  until (P = nil) or
        (EndOfObject = '}');
  if P = nil then // result=nil indicates failure -> points to #0 for end of text
    result := @NULCHAR
  else
    result := P;
end;

function JsonDecode(var Json: RawUtf8; const aName: RawUtf8; WasString: PBoolean;
  HandleValuesAsObjectOrArray: boolean): RawUtf8;
var
  P, Name, Value: PUtf8Char;
  NameLen, ValueLen: integer;
  EndOfObject: AnsiChar;
begin
  result := '';
  P := pointer(Json);
  if P = nil then
    exit;
  while P^ <> '{' do
    if P^ = #0 then
      exit
    else
      inc(P);
  inc(P); // jump {
  repeat
    Name := GetJsonPropName(P, @NameLen);
    if Name = nil then
      exit;  // invalid Json content
    Value := GetJsonFieldOrObjectOrArray(P, WasString, @EndOfObject,
      HandleValuesAsObjectOrArray, true, @ValueLen);
    if not (EndOfObject in [',', '}']) then
      exit; // invalid item separator
    if IdemPropNameU(aName, Name, NameLen) then
    begin
      FastSetString(result, Value, ValueLen);
      exit;
    end;
  until (P = nil) or
        (EndOfObject = '}');
end;

function JsonDecode(P: PUtf8Char; out Values: TNameValuePUtf8CharDynArray;
  HandleValuesAsObjectOrArray: boolean): PUtf8Char;
var
  n: PtrInt;
  field: TNameValuePUtf8Char;
  EndOfObject: AnsiChar;
begin
  {$ifdef FPC}
  Values := nil;
  {$endif FPC}
  result := nil;
  n := 0;
  if P <> nil then
  begin
    while P^ <> '{' do
      if P^ = #0 then
        exit
      else
        inc(P);
    inc(P); // jump {
    repeat
      field.Name := GetJsonPropName(P, @field.NameLen);
      if field.Name = nil then
        exit;  // invalid JSON content
      field.Value := GetJsonFieldOrObjectOrArray(P, nil, @EndOfObject,
        HandleValuesAsObjectOrArray, true, @field.ValueLen);
      if not (EndOfObject in [',', '}']) then
        exit; // invalid item separator
      if n = length(Values) then
        SetLength(Values, n + 32);
      Values[n] := field;
      inc(n);
    until (P = nil) or
          (EndOfObject = '}');
  end;
  SetLength(Values, n);
  if P = nil then // result=nil indicates failure -> points to #0 for end of text
    result := @NULCHAR
  else
    result := P;
end;

function JsonRetrieveStringField(P: PUtf8Char; out Field: PUtf8Char;
  out FieldLen: integer; ExpectNameField: boolean): PUtf8Char;
var
  tab: PJsonCharSet;
begin
  result := nil;
  // retrieve string field
  if P = nil then
    exit;
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  if P^ <> '"' then
    exit;
  inc(P);
  Field := P;
  tab := @JSON_CHARS;
  while not (jcJsonStringMarker in tab[P^]) do
    // not [#0, '"', '\']
    inc(P); // very fast parsing of most UTF-8 chars within "string"
  if P^ <> '"' then
    exit; // here P^ should be '"'
  FieldLen := P - Field;
  // check valid JSON delimiter
  repeat
    inc(P)
  until (P^ > ' ') or
        (P^ = #0);
  if ExpectNameField then
  begin
    if P^ <> ':' then
      exit; // invalid name field
  end
  else if not (P^ in ['}', ',']) then
    exit; // invalid value field
  result := P; // return either ':' for name field, or } , for value field
end;

function GlobalFindClass(classname: PUtf8Char; classnamelen: integer): TRttiCustom;
var
  name: string;
  c: TClass;
begin
  Utf8DecodeToString(classname, classnamelen, name);
  c := FindClass(name);
  if c = nil then
    result := nil
  else
    result := Rtti.RegisterClass(c);
end;

function JsonRetrieveObjectRttiCustom(var Json: PUtf8Char;
  AndGlobalFindClass: boolean): TRttiCustom;
var
  tab: PNormTable;
  P, classname: PUtf8Char;
  classnamelen: integer;
begin
  // at input, Json^ = '{'
  result := nil;
  P := GotoNextNotSpace(Json + 1);
  tab := @NormToUpperAnsi7;
  if IdemPChar(P, '"CLASSNAME":', tab) then
    inc(P, 12)
  else if IdemPChar(P, 'CLASSNAME:', tab) then
    inc(P, 10)
  else
    exit; // we expect woStoreClassName option to have been used
  P := JsonRetrieveStringField(P, classname, classnamelen, false);
  if P = nil then
    exit; // invalid (maybe too complex) Json string value
  Json := P; // Json^ is either } or ,
  result := Rtti.Find(classname, classnamelen, rkClass);
  if (result = nil) and
     AndGlobalFindClass then
    result := GlobalFindClass(classname, classnamelen);
end;

function GetJsonFieldOrObjectOrArray(var P: PUtf8Char; WasString: PBoolean;
  EndOfObject: PUtf8Char; HandleValuesAsObjectOrArray: boolean;
  NormalizeBoolean: boolean; Len: PInteger): PUtf8Char;
var
  Value: PUtf8Char;
  wStr: boolean;
begin
  result := nil;
  if P = nil then
    exit;
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  if HandleValuesAsObjectOrArray and
     (P^ in ['{', '[']) then
  begin
    Value := P;
    P := GotoNextJsonObjectOrArrayMax(P, nil);
    if P = nil then
      exit; // invalid content
    if Len <> nil then
      Len^ := P - Value;
    if WasString <> nil then
      WasString^ := false; // was object or array
    while (P^ <= ' ') and
          (P^ <> #0) do
      inc(P);
    if EndOfObject <> nil then
      EndOfObject^ := P^;
    if P^ <> #0 then
    begin
      P^ := #0; // make zero-terminated
      inc(P);
    end;
    result := Value;
  end
  else
  begin
    result := GetJsonField(P, P, @wStr, EndOfObject, Len);
    if WasString <> nil then
      WasString^ := wStr;
    if not wStr and
       NormalizeBoolean and
       (result <> nil) then
    begin
      if PInteger(result)^ = TRUE_LOW then
        result := pointer(SmallUInt32Utf8[1])
      else // normalize true -> 1
      if PInteger(result)^ = FALSE_LOW then
        result := pointer(SmallUInt32Utf8[0])
      else  // normalize false -> 0
        exit;
      if Len <> nil then
        Len^ := 1;
    end;
  end;
end;

procedure GetJsonItemAsRawJson(var P: PUtf8Char; var result: RawJson;
  EndOfObject: PAnsiChar);
var
  B: PUtf8Char;
begin
  result := '';
  if P = nil then
    exit;
  B := GotoNextNotSpace(P);
  P := GotoEndJsonItem(B);
  if P = nil then
    exit;
  FastSetString(RawUtf8(result), B, P - B);
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  if EndOfObject <> nil then
    EndOfObject^ := P^;
  if P^ <> #0 then //if P^=',' then
    repeat
      inc(P)
    until (P^ > ' ') or
          (P^ = #0);
end;

function GetJsonItemAsRawUtf8(var P: PUtf8Char; var output: RawUtf8;
  WasString: PBoolean; EndOfObject: PUtf8Char): boolean;
var
  V: PUtf8Char;
  VLen: integer;
begin
  V := GetJsonFieldOrObjectOrArray(P, WasString, EndOfObject, true, true, @VLen);
  if V = nil then // parsing error
    result := false
  else
  begin
    FastSetString(output, V, VLen);
    result := true;
  end;
end;

function GotoNextJsonObjectOrArrayInternal(P, PMax: PUtf8Char;
  EndChar: AnsiChar): PUtf8Char;
var
  {$ifdef CPUX86NOTPIC} // not enough registers
  jt: TJsonTokens absolute JSON_TOKENS;
  jsonset: TJsonCharSet absolute JSON_CHARS;
  {$else}
  jt: PJsonTokens;
  jsonset: PJsonCharSet;
  {$endif CPUX86NOTPIC}
label
  Prop;
begin
  // should match GetJsonPropName()
  result := nil;
  {$ifndef CPUX86NOTPIC}
  jt := @JSON_TOKENS;
  {$endif CPUX86NOTPIC}
  repeat
    // main loop for quick parsing without full validation
    case jt[P^] of
      jtObjectStart: // '{'
        begin
          repeat
            inc(P)
          until (P^ > ' ') or
                (P^ = #0);
          P := GotoNextJsonObjectOrArrayInternal(P, PMax, '}');
          if P = nil then
            exit;
        end;
      jtArrayStart: // '['
        begin
          repeat
            inc(P)
          until (P^ > ' ') or
                (P^ = #0);
          P := GotoNextJsonObjectOrArrayInternal(P, PMax, ']');
          if P = nil then
            exit;
        end;
      jtAssign: // ':'
        if EndChar <> '}' then
          exit
        else
          inc(P); // syntax for JSON object only
      jtComma: // ','
        inc(P); // comma appears in both JSON objects and arrays
      jtObjectStop: // '}'
        if EndChar = '}' then
          break
        else
          exit;
      jtArrayStop: // ']'
        if EndChar = ']' then
          break
        else
          exit;
      jtDoubleQuote: // '"'
        begin
          P := GotoEndOfJsonString(P, @JSON_CHARS);
          if P^ <> '"' then
            exit;
          inc(P);
        end;
      jtFirstDigit: // '-', '0'..'9'
        begin
          // '0123' excluded by JSON, but not here
          {$ifndef CPUX86NOTPIC}
          jsonset := @JSON_CHARS;
          {$endif CPUX86NOTPIC}
          repeat
            inc(P);
          until not (jcDigitFloatChar in jsonset[P^]);
          // not ['-', '+', '0'..'9', '.', 'E', 'e']
        end;
      jtTrueFirstChar: // 't'
        if PInteger(P)^ = TRUE_LOW then
          inc(P, 4)
        else
          goto Prop;
      jtFalseFirstChar: // 'f'
        if PInteger(P + 1)^ = FALSE_LOW2 then
          inc(P, 5)
        else
          goto Prop;
      jtNullFirstChar: // 'n'
        if PInteger(P)^ = NULL_LOW then
          inc(P, 4)
        else
          goto Prop;
      jtSingleQuote: // '''' as single-quoted identifier
        begin
          repeat
            inc(P);
            if P^ <= ' ' then
              exit;
          until P^ = '''';
          repeat
            inc(P)
          until (P^ > ' ') or
                (P^ = #0);
          if P^ <> ':' then
            exit;
        end;
      jtSlash: // '/' to allow extended /regex/ syntax
        begin
          repeat
            inc(P);
            if P^ = #0 then
              exit;
          until P^ = '/';
          repeat
            inc(P)
          until (P^ > ' ') or
                (P^ = #0);
        end;
      jtIdentifierFirstChar: // ['_', 'a'..'z', 'A'..'Z', '$']
        begin
Prop:     {$ifndef CPUX86NOTPIC}
          jsonset := @JSON_CHARS;
          {$endif CPUX86NOTPIC}
          repeat
            inc(P);
          until not (jcJsonIdentifier in jsonset[P^]);
          // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '.', '[', ']']
          while (P^ <= ' ') and
                (P^ <> #0) do
            inc(P);
          if P^ = '(' then
          begin
            // handle e.g. "born":isodate("1969-12-31")
            inc(P);
            while (P^ <= ' ') and
                  (P^ <> #0) do
              inc(P);
            if P^ = '"' then
            begin
              P := GotoEndOfJsonString(P, {$ifdef CPUX86NOTPIC}@{$endif}jsonset);
              if P^ <> '"' then
                exit;
            end;
            inc(P);
            while (P^ <= ' ') and
                  (P^ <> #0) do
              inc(P);
            if P^ <> ')' then
              exit;
            inc(P);
          end
          else if P^ <> ':' then
            exit;
        end
    else
      // unexpected character in input JSON
      exit;
    end;
    while (P^ <= ' ') and
          (P^ <> #0) do
      inc(P);
    if (PMax <> nil) and
       (P >= PMax) then
      exit;
  until P^ = EndChar;
  result := P + 1;
end;

function GotoEndJsonItemStrict(P: PUtf8Char): PUtf8Char;
var
  {$ifdef CPUX86NOTPIC}
  jsonset: TJsonCharSet absolute JSON_CHARS; // not enough registers
  {$else}
  jsonset: PJsonCharSet;
  {$endif CPUX86NOTPIC}
label
  pok, ok;
begin
  result := nil; // to notify unexpected end
  if P = nil then
    exit;
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  {$ifndef CPUX86NOTPIC}
  jsonset := @JSON_CHARS;
  {$endif CPUX86NOTPIC}
  case JSON_TOKENS[P^] of
    // complex JSON string, object or array
    jtDoubleQuote: // '"'
      begin
        P := GotoEndOfJsonString(P {$ifndef CPUX86NOTPIC}, jsonset{$endif} );
        if P^ <> '"' then
          exit;
        inc(P);
        goto ok;
      end;
    jtArrayStart: // '['
      begin
        repeat
          inc(P)
        until (P^ > ' ') or
              (P^ = #0);
        P := GotoNextJsonObjectOrArrayInternal(P, nil, ']');
        goto pok;
      end;
    jtObjectStart: // '{'
      begin
        repeat
          inc(P)
        until (P^ > ' ') or
              (P^ = #0);
        P := GotoNextJsonObjectOrArrayInternal(P, nil, '}');
pok:    if P = nil then
          exit;
ok:     while (P^ <= ' ') and
              (P^ <> #0) do
          inc(P);
        result := P;
        exit;
      end;
    // strict JSON numbers and constants validation
    jtTrueFirstChar: // 't'
      if PInteger(P)^ = TRUE_LOW then
      begin
        inc(P, 4);
        goto ok;
      end;
    jtFalseFirstChar: // 'f'
      if PInteger(P + 1)^ = FALSE_LOW2 then
      begin
        inc(P, 5);
        goto ok;
      end;
    jtNullFirstChar: // 'n'
      if PInteger(P)^ = NULL_LOW then
      begin
        inc(P, 4);
        goto ok;
      end;
    jtFirstDigit: // '-', '0'..'9'
      begin
        repeat
          inc(P)
        until not (jcDigitFloatChar in jsonset[P^]);
        // not ['-', '+', '0'..'9', '.', 'E', 'e']
        goto ok;
      end;
  end;
end;

function GotoEndJsonItem(P, PMax: PUtf8Char): PUtf8Char;
var
  {$ifdef CPUX86NOTPIC}
  jsonset: TJsonCharSet absolute JSON_CHARS; // not enough registers
  {$else}
  jsonset: PJsonCharSet;
  {$endif CPUX86NOTPIC}
label
  pok, ok;
begin
  result := nil; // to notify unexpected end
  if P = nil then
    exit;
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  // handle complex JSON string, object or array
  {$ifndef CPUX86NOTPIC}
  jsonset := @JSON_CHARS;
  {$endif CPUX86NOTPIC}
  case P^ of
    '"':
      begin
        P := GotoEndOfJsonString(P {$ifndef CPUX86NOTPIC}, jsonset{$endif} );
        if (P^ <> '"') or
           ((PMax <> nil) and
            (P > PMax)) then
          exit;
        inc(P);
        goto ok;
      end;
    '[':
      begin
        repeat
          inc(P)
        until (P^ > ' ') or
              (P^ = #0);
        P := GotoNextJsonObjectOrArrayInternal(P, PMax, ']');
        goto pok;
      end;
    '{':
      begin
        repeat
          inc(P)
        until (P^ > ' ') or
              (P^ = #0);
        P := GotoNextJsonObjectOrArrayInternal(P, PMax, '}');
pok:    if P = nil then
          exit;
ok:     while (P^ <= ' ') and
              (P^ <> #0) do
          inc(P);
        result := P;
        exit;
      end;
  end;
  // quick ignore numeric or true/false/null or MongoDB extended {age:{$gt:18}}
  if jcEndOfJsonFieldOr0 in jsonset[P^] then // #0 , ] } :
    exit; // no value
  repeat
    inc(P);
  until jcEndOfJsonFieldNotName in jsonset[P^]; // : exists in MongoDB IsoDate()
  if (P^ = #0) or
     ((PMax <> nil) and
      (P > PMax)) then
    exit; // unexpected end
  result := P;
end;

function GotoNextJsonItem(P: PUtf8Char; NumberOfItemsToJump: cardinal;
  EndOfObject: PAnsiChar): PUtf8Char;
begin
  result := nil; // to notify unexpected end
  while NumberOfItemsToJump <> 0 do
  begin
    P := GotoEndJsonItem(P);
    if P = nil then
      exit;
    inc(P); // ignore jcEndOfJsonFieldOr0
    dec(NumberOfItemsToJump);
  end;
  if EndOfObject <> nil then
    EndOfObject^ := P[-1]; // return last jcEndOfJsonFieldOr0
  result := P;
end;

function GotoNextJsonObjectOrArray(P: PUtf8Char; EndChar: AnsiChar): PUtf8Char;
begin
  // should match GetJsonPropName()
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  result := GotoNextJsonObjectOrArrayInternal(P, nil, EndChar);
end;

function GotoNextJsonObjectOrArrayMax(P, PMax: PUtf8Char): PUtf8Char;
var
  EndChar: AnsiChar;
begin
  // should match GetJsonPropName()
  result := nil; // mark error or unexpected end (#0)
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  case P^ of
    '[':
      EndChar := ']';
    '{':
      EndChar := '}';
  else
    exit;
  end;
  repeat
    inc(P)
  until (P^ > ' ') or
        (P^ = #0);
  result := GotoNextJsonObjectOrArrayInternal(P, PMax, EndChar);
end;

function GotoNextJsonObjectOrArray(P: PUtf8Char): PUtf8Char;
begin
  result := GotoNextJsonObjectOrArrayMax(P, nil);
end;

function JsonArrayCount(P: PUtf8Char): integer;
var
  n: integer;
begin
  result := -1;
  n := 0;
  P := GotoNextNotSpace(P);
  if P^ <> ']' then
    repeat
      P := GotoEndJsonItem(P);
      if P = nil then
        // invalid content, or #0 reached
        exit;
      inc(n);
      if P^ <> ',' then
        break;
      inc(P);
    until false;
  if P^ = ']' then
    result := n;
end;

function JsonArrayCount(P, PMax: PUtf8Char): integer;
begin
  result := 0;
  P := GotoNextNotSpace(P);
  if P^ <> ']' then
    while P < PMax do
    begin
      P := GotoEndJsonItem(P, PMax);
      if P = nil then
        // invalid content, or #0/PMax reached
        break;
      inc(result);
      if P^ <> ',' then
        break;
      inc(P);
    end;
  if (P = nil) or
     (P^ <> ']') then
    // aborted when PMax or #0 was reached or the JSON input was invalid
    if result = 0 then
      dec(result) // -1 to ensure the caller tries to get something
    else
      result := -result; // return the current count as negative
end;

function JsonArrayDecode(P: PUtf8Char; out Values: TPUtf8CharDynArray): boolean;
var
  n, max: integer;
begin
  result := false;
  max := 0;
  n := 0;
  P := GotoNextNotSpace(P);
  if P^ <> ']' then
    repeat
      if max = n then
      begin
        max := NextGrow(max);
        SetLength(Values, max);
      end;
      Values[n] := P;
      P := GotoEndJsonItem(P);
      if P = nil then
        exit; // invalid content, or #0 reached
      if P^ <> ',' then
        break;
      inc(P);
    until false;
  if P^ = ']' then
  begin
    SetLength(Values, n);
    result := true;
  end
  else
    Values := nil;
end;

function JsonArrayItem(P: PUtf8Char; Index: integer): PUtf8Char;
begin
  if P <> nil then
  begin
    P := GotoNextNotSpace(P);
    if P^ = '[' then
    begin
      P := GotoNextNotSpace(P + 1);
      if P^ <> ']' then
        repeat
          if Index <= 0 then
          begin
            result := P;
            exit;
          end;
          P := GotoEndJsonItem(P);
          if (P = nil) or
             (P^ <> ',') then
            break; // invalid content or #0 reached
          inc(P);
          dec(Index);
        until false;
    end;
  end;
  result := nil;
end;

function JsonObjectPropCount(P: PUtf8Char): integer;
var
  n: integer;
begin
  result := -1;
  n := 0;
  P := GotoNextNotSpace(P);
  if P^ <> '}' then
    repeat
      P := GotoNextJsonPropName(P);
      if P = nil then
        exit; // invalid field name
      P := GotoEndJsonItem(P);
      if P = nil then
        exit; // invalid content, or #0 reached
      inc(n);
      if P^ <> ',' then
        break;
      inc(P);
    until false;
  if P^ = '}' then
    result := n;
end;

function JsonObjectItem(P: PUtf8Char; const PropName: RawUtf8;
  PropNameFound: PRawUtf8): PUtf8Char;
var
  name: shortstring; // no memory allocation nor P^ modification
  PropNameLen: integer;
  PropNameUpper: array[byte] of AnsiChar;
begin
  if P <> nil then
  begin
    P := GotoNextNotSpace(P);
    PropNameLen := length(PropName);
    if PropNameLen <> 0 then
    begin
      if PropName[PropNameLen] = '*' then
      begin
        UpperCopy255Buf(PropNameUpper{%H-},
          pointer(PropName), PropNameLen - 1)^ := #0;
        PropNameLen := 0;
      end;
      if P^ = '{' then
        P := GotoNextNotSpace(P + 1);
      if P^ <> '}' then
        repeat
          GetJsonPropName(P, name);
          if (name[0] = #0) or
             (name[0] > #200) then
            break;
          while (P^ <= ' ') and
                (P^ <> #0) do
            inc(P);
          if PropNameLen = 0 then // 'PropName*'
          begin
            name[ord(name[0]) + 1] := #0; // make ASCIIZ
            if IdemPChar(@name[1], PropNameUpper) then
            begin
              if PropNameFound <> nil then
                FastSetString(PropNameFound^, @name[1], ord(name[0]));
              result := P;
              exit;
            end;
          end
          else if IdemPropName(name, pointer(PropName), PropNameLen) then
          begin
            result := P;
            exit;
          end;
          P := GotoEndJsonItem(P);
          if (P = nil) or
             (P^ <> ',') then
            break; // invalid content, or #0 reached
          inc(P);
        until false;
    end;
  end;
  result := nil;
end;

function JsonObjectByPath(JsonObject, PropPath: PUtf8Char): PUtf8Char;
var
  objName: RawUtf8;
begin
  result := nil;
  if (JsonObject = nil) or
     (PropPath = nil) then
    exit;
  repeat
    GetNextItem(PropPath, '.', objName);
    if objName = '' then
      exit;
    JsonObject := JsonObjectItem(JsonObject, objName);
    if JsonObject = nil then
      exit;
  until PropPath = nil; // found full name scope
  result := JsonObject;
end;

function JsonObjectsByPath(JsonObject, PropPath: PUtf8Char): RawUtf8;
var
  itemName, objName, propNameFound, objPath: RawUtf8;
  start, ending, obj: PUtf8Char;
  WR: TBaseWriter;
  temp: TTextWriterStackBuffer;

  procedure AddFromStart(const name: RawUtf8);
  begin
    start := GotoNextNotSpace(start);
    ending := GotoEndJsonItem(start);
    if ending = nil then
      exit;
    if WR = nil then
    begin
      WR := TBaseWriter.CreateOwnedStream(temp);
      WR.Add('{');
    end
    else
      WR.AddComma;
    WR.AddFieldName(name);
    while (ending > start) and
          (ending[-1] <= ' ') do
      dec(ending); // trim right
    WR.AddNoJsonEscape(start, ending - start);
  end;

begin
  result := '';
  if (JsonObject = nil) or
     (PropPath = nil) then
    exit;
  WR := nil;
  try
    repeat
      GetNextItem(PropPath, ',', itemName);
      if itemName = '' then
        break;
      if itemName[length(itemName)] <> '*' then
      begin
        start := JsonObjectByPath(JsonObject, pointer(itemName));
        if start <> nil then
          AddFromStart(itemName);
      end
      else
      begin
        objPath := '';
        obj := pointer(itemName);
        repeat
          GetNextItem(obj, '.', objName);
          if objName = '' then
            exit;
          propNameFound := '';
          JsonObject := JsonObjectItem(JsonObject, objName, @propNameFound);
          if JsonObject = nil then
            exit;
          if obj = nil then
          begin
            // found full name scope
            start := JsonObject;
            repeat
              AddFromStart(objPath + propNameFound);
              ending := GotoNextNotSpace(ending);
              if ending^ <> ',' then
                break;
              propNameFound := '';
              start := JsonObjectItem(GotoNextNotSpace(ending + 1), objName, @propNameFound);
            until start = nil;
            break;
          end
          else
            objPath := objPath + objName + '.';
        until false;
      end;
    until PropPath = nil;
    if WR <> nil then
    begin
      WR.Add('}');
      WR.SetText(result);
    end;
  finally
    WR.Free;
  end;
end;

function JsonObjectAsJsonArrays(Json: PUtf8Char; out keys, values: RawUtf8): boolean;
var
  wk, wv: TBaseWriter;
  kb, ke, vb, ve: PUtf8Char;
  temp1, temp2: TTextWriterStackBuffer;
begin
  result := false;
  if (Json = nil) or
     (Json^ <> '{') then
    exit;
  wk := TBaseWriter.CreateOwnedStream(temp1);
  wv := TBaseWriter.CreateOwnedStream(temp2);
  try
    wk.Add('[');
    wv.Add('[');
    kb := Json + 1;
    repeat
      ke := GotoEndJsonItem(kb);
      if (ke = nil) or
         (ke^ <> ':') then
        exit; // invalid input content
      vb := ke + 1;
      ve := GotoEndJsonItem(vb);
      if (ve = nil) or
         not (ve^ in [',', '}']) then
        exit;
      wk.AddNoJsonEscape(kb, ke - kb);
      wk.AddComma;
      wv.AddNoJsonEscape(vb, ve - vb);
      wv.AddComma;
      kb := ve + 1;
    until ve^ = '}';
    wk.CancelLastComma;
    wk.Add(']');
    wk.SetText(keys);
    wv.CancelLastComma;
    wv.Add(']');
    wv.SetText(values);
    result := true;
  finally
    wv.Free;
    wk.Free;
  end;
end;

function TryRemoveComment(P: PUtf8Char): PUtf8Char;
  {$ifdef HASINLINE} inline; {$endif}
begin
  result := P + 1;
  case result^ of
    '/':
      begin // this is // comment - replace by ' '
        dec(result);
        repeat
          result^ := ' ';
          inc(result)
        until result^ in [#0, #10, #13];
        if result^ <> #0 then
          inc(result);
      end;
    '*':
      begin // this is /* comment - replace by ' ' but keep CRLF
        result[-1] := ' ';
        repeat
          if not (result^ in [#10, #13]) then
            result^ := ' '; // keep CRLF for correct line numbering (e.g. for error)
          inc(result);
          if PWord(result)^ = ord('*') + ord('/') shl 8 then
          begin
            PWord(result)^ := $2020;
            inc(result, 2);
            break;
          end;
        until result^ = #0;
      end;
  end;
end;

procedure RemoveCommentsFromJSON(P: PUtf8Char);
var
  PComma: PUtf8Char;
begin // replace comments by ' ' characters which will be ignored by parser
  if P <> nil then
    while P^ <> #0 do
    begin
      case P^ of
        '"':
          begin
            P := GotoEndOfJSONString(P);
            if P^ <> '"' then
              exit
            else
              inc(P);
          end;
        '/':
          P := TryRemoveComment(P);
        ',':
          begin // replace trailing comma by space for strict JSON parsers
            PComma := P;
            repeat
              inc(P)
            until (P^ > ' ') or
                  (P^ = #0);
            if P^ = '/' then
              P := TryRemoveComment(P);
            while (P^ <= ' ') and
                  (P^ <> #0) do
              inc(P);
            if P^ in ['}', ']'] then
              PComma^ := ' '; // see https://github.com/synopse/mORMot/pull/349
          end;
      else
        inc(P);
      end;
    end;
end;

function RemoveCommentsFromJson(const s: RawUtf8): RawUtf8;
begin
  if PosExChar('/', s) = 0 then
    result := s
  else
  begin
    FastSetString(result, pointer(s), length(s));
    RemoveCommentsFromJson(pointer(s)); // remove in-place
  end;
end;

function ParseEndOfObject(P: PUtf8Char; out EndOfObject: AnsiChar): PUtf8Char;
var
  tab: PJsonCharSet;
begin
  if P <> nil then
  begin
    tab := @JSON_CHARS; // mimics GetJsonField()
    while not (jcEndOfJsonFieldOr0 in tab[P^]) do
      inc(P); // not #0 , ] } :
    EndOfObject := P^;
    if P^ <> #0 then
      repeat
        inc(P); // ignore trailing , ] } and any successive spaces
      until (P^ > ' ') or
            (P^ = #0);
  end;
  result := P;
end;

function GetSetNameValue(Names: PShortString; MaxValue: integer;
  var P: PUtf8Char; out EndOfObject: AnsiChar): QWord;
var
  Text: PUtf8Char;
  WasString: boolean;
  TextLen, i: integer;
begin
  result := 0;
  if (P = nil) or
     (Names = nil) or
     (MaxValue < 0) then
    exit;
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  if P^ = '[' then
  begin
    repeat
      inc(P)
    until (P^ > ' ') or
          (P^ = #0);
    if P^ = ']' then
      inc(P)
    else
    begin
      repeat
        Text := GetJsonField(P, P, @WasString, @EndOfObject, @TextLen);
        if (Text = nil) or
           not WasString then
        begin
          P := nil; // invalid input (expects a JSON array of strings)
          exit;
        end;
        if Text^ = '*' then
        begin
          if MaxValue < 32 then
            result := ALLBITS_CARDINAL[MaxValue + 1]
          else
            result := QWord(-1);
          break;
        end;
        if Text^ in ['a'..'z'] then
          i := FindShortStringListExact(names, MaxValue, Text, TextLen)
        else
          i := -1;
        if i < 0 then
          i := FindShortStringListTrimLowerCase(names, MaxValue, Text, TextLen);
        if i >= 0 then
          SetBitPtr(@result, i);
        // unknown enum names (i=-1) would just be ignored
      until EndOfObject = ']';
      if P = nil then
        exit; // avoid GPF below if already reached the input end
    end;
    P := ParseEndOfObject(P, EndOfObject); // mimics GetJsonField()
  end
  else
    SetQWord(GetJsonField(P, P, nil, @EndOfObject), result);
end;

function GetSetNameValue(Info: PRttiInfo;
  var P: PUtf8Char; out EndOfObject: AnsiChar): QWord;
var
  Names: PShortString;
  MaxValue: integer;
begin
  if (Info <> nil) and
     (Info^.Kind = rkSet) and
     (Info^.SetEnumType(Names, MaxValue) <> nil) then
    result := GetSetNameValue(Names, MaxValue, P, EndOfObject)
  else
    result := 0;
end;

function UrlEncodeJsonObject(const UriName: RawUtf8; ParametersJson: PUtf8Char;
  const PropNamesToIgnore: array of RawUtf8; IncludeQueryDelimiter: boolean): RawUtf8;
var
  i, j: integer;
  sep: AnsiChar;
  Params: TNameValuePUtf8CharDynArray;
  temp: TTextWriterStackBuffer;
begin
  if ParametersJson = nil then
    result := UriName
  else
    with TBaseWriter.CreateOwnedStream(temp) do
    try
      AddString(UriName);
      if (JsonDecode(ParametersJson, Params, true) <> nil) and
         (Params <> nil) then
      begin
        sep := '?';
        for i := 0 to length(Params) - 1 do
          with Params[i] do
          begin
            for j := 0 to high(PropNamesToIgnore) do
              if IdemPropNameU(PropNamesToIgnore[j], name, NameLen) then
              begin
                NameLen := 0;
                break;
              end;
            if NameLen = 0 then
              continue;
            if IncludeQueryDelimiter then
              Add(sep);
            AddNoJsonEscape(name, NameLen);
            Add('=');
            AddString(UrlEncode(Value));
            sep := '&';
            IncludeQueryDelimiter := true;
          end;
      end;
      SetText(result);
    finally
      Free;
    end;
end;

function UrlEncodeJsonObject(const UriName, ParametersJson: RawUtf8;
  const PropNamesToIgnore: array of RawUtf8; IncludeQueryDelimiter: boolean): RawUtf8;
var
  temp: TSynTempBuffer;
begin
  temp.Init(ParametersJson);
  try
    result := UrlEncodeJsonObject(UriName, temp.buf, PropNamesToIgnore, IncludeQueryDelimiter);
  finally
    temp.Done;
  end;
end;

function ObjArrayToJson(const aObjArray;
  aOptions: TTextWriterWriteObjectOptions): RawUtf8;
var
  temp: TTextWriterStackBuffer;
begin
  with TTextWriter.CreateOwnedStream(temp) do
  try
    if woEnumSetsAsText in aOptions then
      CustomOptions := CustomOptions + [twoEnumSetsAsTextInRecord];
    AddObjArrayJson(aObjArray, aOptions);
    SetText(result);
  finally
    Free;
  end;
end;

function JsonEncode(const NameValuePairs: array of const): RawUtf8;
var
  temp: TTextWriterStackBuffer;
begin
  if high(NameValuePairs) < 1 then
    // return void JSON object on error
    result := '{}'
  else
    with TTextWriter.CreateOwnedStream(temp) do
    try
      AddJsonEscape(NameValuePairs);
      SetText(result);
    finally
      Free
    end;
end;

function JsonEncode(const Format: RawUtf8;
  const Args, Params: array of const): RawUtf8;
var
  temp: TTextWriterStackBuffer;
begin
  with TTextWriter.CreateOwnedStream(temp) do
  try
    AddJson(Format, Args, Params);
    SetText(result);
  finally
    Free
  end;
end;

function JsonEncodeArrayDouble(const Values: array of double): RawUtf8;
var
  W: TTextWriter;
  temp: TTextWriterStackBuffer;
begin
  W := TTextWriter.CreateOwnedStream(temp);
  try
    W.Add('[');
    W.AddCsvDouble(Values);
    W.Add(']');
    W.SetText(result);
  finally
    W.Free
  end;
end;

function JsonEncodeArrayUtf8(const Values: array of RawUtf8): RawUtf8;
var
  W: TTextWriter;
  temp: TTextWriterStackBuffer;
begin
  W := TTextWriter.CreateOwnedStream(temp);
  try
    W.Add('[');
    W.AddCsvUtf8(Values);
    W.Add(']');
    W.SetText(result);
  finally
    W.Free
  end;
end;

function JsonEncodeArrayInteger(const Values: array of integer): RawUtf8;
var
  W: TTextWriter;
  temp: TTextWriterStackBuffer;
begin
  W := TTextWriter.CreateOwnedStream(temp);
  try
    W.Add('[');
    W.AddCsvInteger(Values);
    W.Add(']');
    W.SetText(result);
  finally
    W.Free
  end;
end;

function JsonEncodeArrayOfConst(const Values: array of const;
  WithoutBraces: boolean): RawUtf8;
begin
  JsonEncodeArrayOfConst(Values, WithoutBraces, result);
end;

procedure JsonEncodeArrayOfConst(const Values: array of const;
  WithoutBraces: boolean; var result: RawUtf8);
var
  temp: TTextWriterStackBuffer;
begin
  if length(Values) = 0 then
    if WithoutBraces then
      result := ''
    else
      result := '[]'
  else
    with TTextWriter.CreateOwnedStream(temp) do
    try
      if not WithoutBraces then
        Add('[');
      AddCsvConst(Values);
      if not WithoutBraces then
        Add(']');
      SetText(result);
    finally
      Free
    end;
end;

procedure JsonEncodeNameSQLValue(const Name, SQLValue: RawUtf8;
  var result: RawUtf8);
var
  temp: TTextWriterStackBuffer;
begin
  if (SQLValue <> '') and
     (SQLValue[1] in ['''', '"']) then
    // unescape SQL quoted string value into a valid JSON string
    with TTextWriter.CreateOwnedStream(temp) do
    try
      Add('{', '"');
      AddNoJsonEscapeUtf8(Name);
      Add('"', ':');
      AddQuotedStringAsJson(SQLValue);
      Add('}');
      SetText(result);
    finally
      Free;
    end
  else
    // Value is a number or null/true/false
    result := '{"' + Name + '":' + SQLValue + '}';
end;


procedure QuotedStrJson(P: PUtf8Char; PLen: PtrInt; var result: RawUtf8;
  const aPrefix, aSuffix: RawUtf8);
var
  temp: TTextWriterStackBuffer;
  Lp, Ls: PtrInt;
  D: PUtf8Char;
begin
  if (P = nil) or
     (PLen <= 0) then
    result := '""'
  else if (pointer(result) = pointer(P)) or
          NeedsJsonEscape(P, PLen) then
    // use TTextWriter.AddJsonEscape() for proper JSON escape
    with TTextWriter.CreateOwnedStream(temp) do
    try
      AddString(aPrefix);
      Add('"');
      AddJsonEscape(P, PLen);
      Add('"');
      AddString(aSuffix);
      SetText(result);
      exit;
    finally
      Free;
    end
  else
  begin
    // direct allocation if no JSON escape is needed
    Lp := length(aPrefix);
    Ls := length(aSuffix);
    FastSetString(result, nil, PLen + Lp + Ls + 2);
    D := pointer(result); // we checked dest result <> source P above
    if Lp > 0 then
    begin
      MoveFast(pointer(aPrefix)^, D^, Lp);
      inc(D, Lp);
    end;
    D^ := '"';
    MoveFast(P^, D[1], PLen);
    inc(D, PLen);
    D[1] := '"';
    if Ls > 0 then
      MoveFast(pointer(aSuffix)^, D[2], Ls);
  end;
end;

procedure QuotedStrJson(const aText: RawUtf8; var result: RawUtf8;
  const aPrefix, aSuffix: RawUtf8);
begin
  QuotedStrJson(pointer(aText), Length(aText), result, aPrefix, aSuffix);
end;

function QuotedStrJson(const aText: RawUtf8): RawUtf8;
begin
  QuotedStrJson(pointer(aText), Length(aText), result, '', '');
end;

procedure JsonBufferReformat(P: PUtf8Char; out result: RawUtf8;
  Format: TTextWriterJsonFormat);
var
  temp: array[word] of byte; // 64KB buffer
begin
  if P <> nil then
    with TTextWriter.CreateOwnedStream(@temp, SizeOf(temp)) do
    try
      AddJsonReformat(P, Format, nil);
      SetText(result);
    finally
      Free;
    end;
end;

function JsonReformat(const Json: RawUtf8; Format: TTextWriterJsonFormat): RawUtf8;
var
  tmp: TSynTempBuffer;
begin
  tmp.Init(Json);
  try
    JsonBufferReformat(tmp.buf, result, Format);
  finally
    tmp.Done;
  end;
end;

function JsonBufferReformatToFile(P: PUtf8Char; const Dest: TFileName;
  Format: TTextWriterJsonFormat): boolean;
var
  F: TFileStream;
  temp: array[word] of word; // 128KB
begin
  try
    F := TFileStream.Create(Dest, fmCreate);
    try
      with TTextWriter.Create(F, @temp, SizeOf(temp)) do
      try
        AddJsonReformat(P, Format, nil);
        FlushFinal;
      finally
        Free;
      end;
      result := true;
    finally
      F.Free;
    end;
  except
    on Exception do
      result := false;
  end;
end;

function JsonReformatToFile(const Json: RawUtf8; const Dest: TFileName;
  Format: TTextWriterJsonFormat): boolean;
var
  tmp: TSynTempBuffer;
begin
  tmp.Init(Json);
  try
    result := JsonBufferReformatToFile(tmp.buf, Dest, Format);
  finally
    tmp.Done;
  end;
end;


function FormatUtf8(const Format: RawUtf8; const Args, Params: array of const;
  JsonFormat: boolean): RawUtf8;
var
  A, P: PtrInt;
  F, FDeb: PUtf8Char;
  isParam: AnsiChar;
  toquote: TTempUtf8;
  temp: TTextWriterStackBuffer;
begin
  if (Format = '') or
     ((high(Args) < 0) and
      (high(Params) < 0)) then
    // no formatting to process, but may be a const
    // -> make unique since e.g. _JsonFmt() will parse it in-place
    FastSetString(result, pointer(Format), length(Format))
  else if high(Params) < 0 then
    // faster function with no ?
    FormatUtf8(Format, Args, result)
  else if Format = '%' then
    // optimize raw conversion
    VarRecToUtf8(Args[0], result)
  else
    // handle any number of parameters with minimal memory allocations
    with TTextWriter.CreateOwnedStream(temp) do
    try
      A := 0;
      P := 0;
      F := pointer(Format);
      while F^ <> #0 do
      begin
        if (F^ <> '%') and
           (F^ <> '?') then
        begin
          // handle plain text between % ? markers
          FDeb := F;
          repeat
            inc(F);
          until F^ in [#0, '%', '?'];
          AddNoJsonEscape(FDeb, F - FDeb);
          if F^ = #0 then
            break;
        end;
        isParam := F^;
        inc(F); // jump '%' or '?'
        if (isParam = '%') and
           (A <= high(Args)) then
        begin
          // handle % substitution
          if Args[A].VType = vtObject then
            AddShort(ClassNameShort(Args[A].VObject)^)
          else
            Add(Args[A]);
          inc(A);
        end
        else if (isParam = '?') and
                (P <= high(Params)) then
        begin
          // handle ? substitution as JSON or SQL
          if JsonFormat then
            AddJsonEscape(Params[P]) // does the JSON magic including "quotes"
          else
          begin
            Add(':', '('); // markup for SQL parameter binding
            if Params[P].VType in [vtBoolean, vtInteger, vtInt64
                {$ifdef FPC} , vtQWord {$endif}, vtCurrency, vtExtended] then
              Add(Params[P]) // numbers or boolean
            else
            begin
              VarRecToTempUtf8(Params[P], toquote);
              AddQuotedStr(toquote.Text, toquote.Len, ''''); // SQL double quote
              if toquote.TempRawUtf8 <> nil then
                RawUtf8(toquote.TempRawUtf8) := ''; // release temp memory
            end;
            Add(')', ':');
          end;
          inc(P);
        end
        else
        begin
          // no more available Args or Params -> add all remaining text
          AddNoJsonEscape(F, length(Format) - (F - pointer(Format)));
          break;
        end;
      end;
      SetText(result);
    finally
      Free;
    end;
end;



{ ********** Low-Level JSON Serialization for all TRttiParserType }

procedure TTextWriter.BlockAfterItem(Options: TTextWriterWriteObjectOptions);
begin
  // defined here for proper inlining
  AddComma;
  if woHumanReadable in Options then
    AddCRAndIndent;
end;

{ TJsonSaveContext }

procedure TJsonSaveContext.Init(WR: TTextWriter;
  WriteOptions: TTextWriterWriteObjectOptions; Rtti: TRttiCustom);
begin
  W := WR;
  Info := Rtti;
  Options := WriteOptions;
  if Rtti <> nil then
    Options := Options + TRttiJson(Rtti).fIncludeWriteOptions;
  Prop := nil;
end;

procedure TJsonSaveContext.Add64(Value: PInt64; UnSigned: boolean);
begin
  if woInt64AsHex in Options then
    if Value^ = 0 then
      W.Add('"', '"')
    else
      W.AddBinToHexDisplayLower(Value, SizeOf(Value^), '"')
  else if UnSigned then
    W.AddQ(PQWord(Value)^)
  else
    W.Add(Value^);
end;

procedure TJsonSaveContext.AddShort(PS: PShortString);
begin
  W.Add('"');
  if twoTrimLeftEnumSets in W.CustomOptions then
    W.AddTrimLeftLowerCase(PS)
  else
    W.AddShort(PS^);
  W.Add('"');
end;

procedure TJsonSaveContext.AddShortBoolean(PS: PShortString; Value: boolean);
begin
  AddShort(PS);
  W.Add(':');
  W.Add(Value);
end;

procedure TJsonSaveContext.AddDateTime(Value: PDateTime; WithMS: boolean);
var
  d: double;
begin
  if woDateTimeWithMagic in Options then
    W.AddShorter(JSON_SQLDATE_MAGIC_QUOTE_STR)
  else
    W.Add('"');
  d := unaligned(Value^);
  W.AddDateTime(d, WithMS);
  if woDateTimeWithZSuffix in Options then
    if frac(d) = 0 then // FireFox can't decode short form "2017-01-01Z"
      W.AddShorter('T00:00Z')
    else
      W.Add('Z');
  W.Add('"');
end;


procedure _JS_Boolean(Data: PBoolean; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.Add(Data^);
end;

procedure _JS_Byte(Data: PByte; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddU(Data^);
end;

procedure _JS_Cardinal(Data: PCardinal; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddU(Data^);
end;

procedure _JS_Currency(Data: PInt64; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddCurr64(Data);
end;

procedure _JS_Double(Data: PDouble; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddDouble(unaligned(Data^));
end;

procedure _JS_Extended(Data: PSynExtended; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddDouble({$ifndef TSYNEXTENDED80}unaligned{$endif}(Data^));
end;

procedure _JS_Int64(Data: PInt64; const Ctxt: TJsonSaveContext);
begin
  Ctxt.Add64(Data, {unsigned=}false);
end;

procedure _JS_Integer(Data: PInteger; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.Add(Data^);
end;

procedure _JS_QWord(Data: PInt64; const Ctxt: TJsonSaveContext);
begin
  Ctxt.Add64(Data, {unsigned=}true);
end;

procedure _JS_RawByteString(Data: PRawByteString; const Ctxt: TJsonSaveContext);
begin
  if (rcfIsRawBlob in Ctxt.Info.Cache.Flags) and
     not (woRawBlobAsBase64 in Ctxt.Options) then
    Ctxt.W.AddNull
  else
    Ctxt.W.WrBase64(pointer(Data^), length(Data^), {withmagic=}true);
end;

procedure _JS_RawJson(Data: PRawJson; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddRawJson(Data^);
end;

procedure _JS_RawUtf8(Data: PPAnsiChar; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.Add('"');
  if Data^ <> nil then
    with PStrRec(Data^ - SizeOf(TStrRec))^ do
      // will handle RawUtf8 but also AnsiString, WinAnsiString and RawUnicode
      Ctxt.W.AddAnyAnsiBuffer(Data^, length, twJsonEscape,
       {$ifdef HASCODEPAGE} codePage {$else} Ctxt.Info.Cache.CodePage {$endif});
  Ctxt.W.Add('"');
end;

procedure _JS_Single(Data: PSingle; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddSingle(Data^);
end;

procedure _JS_Unicode(Data: PPWord; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.Add('"');
  Ctxt.W.AddJsonEscapeW(Data^);
  Ctxt.W.Add('"');
end;

procedure _JS_DateTime(Data: PDateTime; const Ctxt: TJsonSaveContext);
begin
  Ctxt.AddDateTime(Data, {withms=}false);
end;

procedure _JS_DateTimeMS(Data: PDateTime; const Ctxt: TJsonSaveContext);
begin
  Ctxt.AddDateTime(Data, {withms=}true);
end;

procedure _JS_GUID(Data: PGUID; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.Add(Data, '"');
end;

procedure _JS_Hash(Data: pointer; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddBinToHexDisplayLower(Data, Ctxt.Info.Size, '"');
end;

procedure _JS_Binary(Data: pointer; const Ctxt: TJsonSaveContext);
begin
  if IsZeroSmall(Data, Ctxt.Info.BinarySize) then
    Ctxt.W.Add('"', '"') // serialize "" for 0 value
  else
    Ctxt.W.AddBinToHexDisplayLower(Data, Ctxt.Info.BinarySize, '"');
end;

procedure _JS_TimeLog(Data: PInt64; const Ctxt: TJsonSaveContext);
begin
  if woTimeLogAsText in Ctxt.Options then
    Ctxt.W.AddTimeLog(Data, '"')
  else
    Ctxt.Add64(Data, true);
end;

procedure _JS_UnixTime(Data: PInt64; const Ctxt: TJsonSaveContext);
begin
  if woTimeLogAsText in Ctxt.Options then
    Ctxt.W.AddUnixTime(Data, '"')
  else
    Ctxt.Add64(Data, true);
end;

procedure _JS_UnixMSTime(Data: PInt64; const Ctxt: TJsonSaveContext);
begin
  if woTimeLogAsText in Ctxt.Options then
    Ctxt.W.AddUnixMSTime(Data, {withms=}true, '"')
  else
    Ctxt.Add64(Data, true);
end;

procedure _JS_Variant(Data: PVariant; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddVariant(Data^);
end;

procedure _JS_WinAnsi(Data: PWinAnsiString; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.Add('"');
  Ctxt.W.AddAnyAnsiBuffer(pointer(Data^), length(Data^), twJsonEscape, CODEPAGE_US);
  Ctxt.W.Add('"');
end;

procedure _JS_Word(Data: PWord; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddU(Data^);
end;

procedure _JS_Interface(Data: PInterface; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddNull;
end;

procedure _JS_ID(Data: PInt64; const Ctxt: TJsonSaveContext);
var
  _str: shortstring;
begin
  Ctxt.W.Add(Data^);
  if woIDAsIDstr in Ctxt.Options then
  begin
    Ctxt.W.BlockAfterItem(Ctxt.Options);
    if (Ctxt.Prop <> nil) and
       (Ctxt.Prop^.Name <> '') then
    begin
      FormatShort('%_str', [Ctxt.Prop^.Name], _str);
      Ctxt.W.WriteObjectPropNameShort(_str, Ctxt.Options);
    end
    else
      Ctxt.W.WriteObjectPropNameShort('ID_str', Ctxt.Options);
    Ctxt.W.Add('"');
    Ctxt.W.Add(Data^);
    Ctxt.W.Add('"');
  end;
end;

procedure _JS_Enumeration(Data: PByte; const Ctxt: TJsonSaveContext);
var
  o: TTextWriterOptions;
  PS: PShortString;
begin
  o := Ctxt.W.CustomOptions;
  if (Ctxt.Options * [woFullExpand, woHumanReadable, woEnumSetsAsText] <> []) or
     (o * [twoEnumSetsAsBooleanInRecord, twoEnumSetsAsTextInRecord] <> []) then
  begin
    PS := Ctxt.Info.Cache.EnumInfo^.GetEnumNameOrd(Data^);
    if twoEnumSetsAsBooleanInRecord in o then
      Ctxt.AddShortBoolean(PS, true)
    else
      Ctxt.AddShort(PS);
    if woHumanReadableEnumSetAsComment in Ctxt.Options then
      Ctxt.Info.Cache.EnumInfo^.GetEnumNameAll(Ctxt.W.fBlockComment, '', true);
  end
  else
    Ctxt.W.AddU(Data^);
end;

procedure _JS_Set(Data: PCardinal; const Ctxt: TJsonSaveContext);
var
  PS: PShortString;
  i: cardinal;
  v: QWord;
  o: TTextWriterOptions;
begin
  o := Ctxt.W.CustomOptions;
  if twoEnumSetsAsBooleanInRecord in o then
  begin
    // { "set1": true/false, .... } with proper indentation
    PS := Ctxt.Info.Cache.EnumList;
    Ctxt.W.BlockBegin('{', Ctxt.Options);
    i := 0;
    repeat
      Ctxt.AddShortBoolean(PS, GetBitPtr(Data, i));
      if i = Ctxt.Info.Cache.EnumMax then
        break;
      inc(i);
      Ctxt.W.BlockAfterItem(Ctxt.Options);
      inc(PByte(PS), PByte(PS)^ + 1); // next
    until false;
    Ctxt.W.BlockEnd('}', Ctxt.Options);
  end
  else if (Ctxt.Options * [woFullExpand, woHumanReadable, woEnumSetsAsText] <> []) or
          (twoEnumSetsAsTextInRecord in o) then
  begin
    // [ "set1", "set4", .... } on same line
    Ctxt.W.Add('[');
    if ((twoFullSetsAsStar in o) or
        (woHumanReadableFullSetsAsStar in Ctxt.Options)) and
       GetAllBits(Data^, Ctxt.Info.Cache.EnumMax + 1) then
      Ctxt.W.AddShorter('"*"')
    else
    begin
      PS := Ctxt.Info.Cache.EnumList;
      for i := 0 to Ctxt.Info.Cache.EnumMax do
      begin
        if GetBitPtr(Data, i) then
        begin
          Ctxt.W.Add('"');
          Ctxt.W.AddShort(PS^);
          Ctxt.W.Add('"', ',');
        end;
        inc(PByte(PS), PByte(PS)^ + 1); // next
      end;
      Ctxt.W.CancelLastComma;
    end;
    Ctxt.W.Add(']');
    if woHumanReadableEnumSetAsComment in Ctxt.Options then
      Ctxt.Info.Cache.EnumInfo^.GetEnumNameAll(
        Ctxt.W.fBlockComment, '"*" or a set of ', true);
  end
  else
  begin
    // standard serialization as unsigned integer (up to 64 items)
    v := 0;
    MoveSmall(Data, @v, Ctxt.Info.Size);
    Ctxt.W.AddQ(v);
  end;
end;

procedure _JS_Array(Data: PAnsiChar; const Ctxt: TJsonSaveContext);
var
  n: integer;
  jsonsave: TRttiJsonSave;
  c: TJsonSaveContext;
begin
  {%H-}c.Init(Ctxt.W, Ctxt.Options, Ctxt.Info.ArrayRtti);
  c.W.BlockBegin('[', c.Options);
  jsonsave := c.Info.JsonSave; // e.g. PT_JSONSAVE/PTC_JSONSAVE
  if Assigned(jsonsave) then
  begin
    // efficient JSON serialization
    n := Ctxt.Info.Cache.ItemCount;
    repeat
      jsonsave(Data, c);
      dec(n);
      if n = 0 then
        break;
      c.W.BlockAfterItem(c.Options);
      inc(Data, c.Info.Cache.Size);
    until false;
  end
  else
    // fallback to raw RTTI binary serialization with Base64 encoding
    c.W.BinarySaveBase64(Data, Ctxt.Info.Info, [rkArray],
      {withMagic=}true, {withcrc=}false);
  c.W.BlockEnd(']', c.Options);
end;

procedure _JS_DynArray_Custom(Data: pointer; const Ctxt: TJsonSaveContext);
begin
  // TRttiJson.RegisterCustomSerializer() custom callback for each item
  TOnRttiJsonWrite(TRttiJson(Ctxt.Info).fJsonWriter)(
    Ctxt.W, Data, Ctxt.Options);
end;

procedure _JS_DynArray(Data: PPointer; const Ctxt: TJsonSaveContext);
var
  n, s: PtrInt;
  jsonsave: TRttiJsonSave;
  P: PAnsiChar;
  c: TJsonSaveContext;
begin
  {%H-}c.Init(Ctxt.W, Ctxt.Options, Ctxt.Info.ArrayRtti);
  c.W.BlockBegin('[', c.Options);
  if Data^ <> nil then
  begin
    if TRttiJson(Ctxt.Info).fJsonWriter.Code <> nil then
    begin
      // TRttiJson.RegisterCustomSerializer() custom callbacks
      c.Info := Ctxt.Info;
      jsonsave := @_JS_DynArray_Custom;
    end
    else if c.Info = nil then
      jsonsave := nil
    else
      jsonsave := c.Info.JsonSave; // e.g. PT_JSONSAVE/PTC_JSONSAVE
    if Assigned(jsonsave) then
    begin
      // efficient JSON serialization
      P := Data^;
      n := PDALen(P - _DALEN)^ + _DAOFF; // length(Data)
      s := Ctxt.Info.Cache.ItemSize; // c.Info may be nil
      repeat
        jsonsave(P, c);
        dec(n);
        if n = 0 then
          break;
        c.W.BlockAfterItem(c.Options);
        inc(P, s);
      until false;
    end
    else
      // fallback to raw RTTI binary serialization with Base64 encoding
      c.W.BinarySaveBase64(Data, Ctxt.Info.Info, [rkDynArray],
        {withMagic=}true, {withcrc=}false);
  end
  else if (woHumanReadableEnumSetAsComment in Ctxt.Options) and
          (c.Info <> nil) and
          (rcfHasNestedProperties in c.Info.Flags) then
    // void dynarray should include record/T*ObjArray fields as comment
    c.Info.Props.AsText(c.W.fBlockComment, true, 'array of {', '}');
  c.W.BlockEnd(']', c.Options);
end;

const
  /// use pointer to allow any kind of Data^ type in above functions
  // - typecast to TRttiJsonSave for proper function call
  // - rkRecord and rkClass are handled in TRttiJson.SetParserType
  PT_JSONSAVE: array[TRttiParserType] of pointer = (
    nil, @_JS_Array, @_JS_Boolean, @_JS_Byte, @_JS_Cardinal, @_JS_Currency,
    @_JS_Double, @_JS_Extended, @_JS_Int64, @_JS_Integer, @_JS_QWord,
    @_JS_RawByteString, @_JS_RawJson, @_JS_RawUtf8, nil, @_JS_Single,
    {$ifdef UNICODE} @_JS_Unicode {$else} @_JS_RawUtf8 {$endif},
    @_JS_Unicode, @_JS_DateTime, @_JS_DateTimeMS, @_JS_GUID, @_JS_Hash,
    @_JS_Hash, @_JS_Hash, nil, @_JS_TimeLog, @_JS_Unicode, @_JS_UnixTime,
    @_JS_UnixMSTime, @_JS_Variant, @_JS_Unicode, @_JS_WinAnsi, @_JS_Word,
    @_JS_Enumeration, @_JS_Set, nil, @_JS_DynArray, @_JS_Interface, nil);

  /// use pointer to allow any complex kind of Data^ type in above functions
  // - typecast to TRttiJsonSave for proper function call
  PTC_JSONSAVE: array[TRttiParserComplexType] of pointer = (
    nil, nil, nil, nil, @_JS_ID, @_JS_ID, @_JS_QWord, @_JS_QWord, @_JS_QWord);

type
  TSPHook = class(TSynPersistent); // to access its protected methods
  TSPHookClass = class of TSPHook;

// serialization of published props for records and classes
procedure _JS_RttiCustom(Data: PAnsiChar; const Ctxt: TJsonSaveContext);
var
  c: TJsonSaveContext;
  p: PRttiCustomProp;
  n: integer;
  done: boolean;
begin
  c.W := Ctxt.W;
  c.Options := Ctxt.Options;
  if (Ctxt.Info.Kind = rkClass) and
     (Data <> nil) then
    // class instances are accessed by reference, records are stored by value
    Data := PPointer(Data)^
  else
    exclude(c.Options, woFullExpand); // not for null or for records
  if Data = nil then
    // append 'null' for nil class instance
    c.W.AddNull
  else if TRttiJson(Ctxt.Info).fJsonWriter.Code <> nil then
    // TRttiJson.RegisterCustomSerializer() custom callbacks
    TOnRttiJsonWrite(TRttiJson(Ctxt.Info).fJsonWriter)(c.W, Data, c.Options)
  else if not (rcfSynPersistentHook in Ctxt.Info.Flags) or
          not TSPHook(Data).RttiBeforeWriteObject(c.W, c.Options) then
  begin
    // regular JSON serialization using nested fields/properties
    c.W.BlockBegin('{', c.Options);
    c.Prop := pointer(Ctxt.Info.Props.List);
    n := Ctxt.Info.Props.Count;
    if (Ctxt.Info.Kind = rkClass) and
       (c.Options * [woFullExpand, woStoreClassName, woStorePointer, woDontStoreInherited] <> []) then
    begin
      if woFullExpand in c.Options then
      begin
        c.W.AddInstanceName(TObject(Data), ':');
        c.W.BlockBegin('{', c.Options);
      end;
      if woStoreClassName in c.Options then
      begin
        c.W.WriteObjectPropNameShort('ClassName', c.Options);
        c.W.Add('"');
        c.W.AddShort(ClassNameShort(PClass(Data)^)^);
        c.W.Add('"');
        if (c.Prop <> nil) or
           (woStorePointer in c.Options) then
          c.W.BlockAfterItem(c.Options);
      end;
      if woStorePointer in c.Options then
      begin
        c.W.WriteObjectPropNameShort('Address', c.Options);
        if Ctxt.Info.ValueRtlClass = vcESynException then
        begin // run TDebugFile.FindLocationShort if mormot.core.log is used
          c.W.Add('"');
          c.W.AddShort(GetExecutableLocation(ESynException(Data).RaisedAt));
          c.W.Add('"');
        end
        else
          c.W.AddPointer(PtrUInt(Data), '"');
        if c.Prop <> nil then
          c.W.BlockAfterItem(c.Options);
      end;
      if woDontStoreInherited in c.Options then
        with Ctxt.Info.Props do
        begin
          // List[NotInheritedIndex]..List[Count-1] store the last hierarchy level
          n := Count - NotInheritedIndex;
          inc(c.Prop, NotInheritedIndex);
        end;
    end;
    done := false;
    if n > 0 then
      // this is the main loop serializing Info.Props[]
      repeat
        p := c.Prop;
        if // handle Props.NameChange() set to New='' to ignore this field
           (p^.Name <> '') and
           // handle woStoreStoredFalse flag and "stored" attribute in code
           ((woStoreStoredFalse in c.Options) or
            (p^.Prop = nil) or
            (p^.Prop.IsStored(pointer(Data)))) and
           // handle woDontStoreDefault flag over "default" attribute in code
           (not (woDontStoreDefault in c.Options) or
            (p^.Prop = nil) or
            (p.OrdinalDefault = NO_DEFAULT) or
            not p.ValueIsDefault(Data)) and
           // detect 0 numeric values and empty strings
           (not (woDontStoreVoid in c.Options) or
            not p.ValueIsVoid(Data)) then
        begin
          // if we reached here, we should serialize this property
          if done then
            // append ',' and proper indentation if a field was just appended
            c.W.BlockAfterItem(c.Options);
          done := true;
          c.W.WriteObjectPropName(pointer(p^.Name), length(p^.Name), c.Options);
          if not (rcfSynPersistentHook in Ctxt.Info.Flags) or
             not TSPHook(Data).RttiWritePropertyValue(c.W, p, c.Options) then
            if (woHideSensitivePersonalInformation in c.Options) and
               (rcfSPI in p^.Value.Flags) then
              c.W.AddShorter('"***"')
            else if p^.OffsetGet >= 0 then
            begin
              // direct value write (record field or plain class property)
              c.Info := p^.Value;
              TRttiJsonSave(c.Info.JsonSave)(Data + p^.OffsetGet, c);
            end
            else
              // need to call a getter method
              p^.AddValueJson(c.W, Data, c.Options);
        end;
        dec(n);
        if n = 0 then
          break;
        inc(c.Prop);
      until false;
    if rcfSynPersistentHook in Ctxt.Info.Flags then
       TSPHook(Data).RttiAfterWriteObject(c.W, c.Options);
    c.W.BlockEnd('}', c.Options);
    if woFullExpand in c.Options then
      c.W.BlockEnd('}', c.Options);
  end;
end;

// most known RTL classes custom serialization

procedure _JS_Objects(W: TTextWriter; Value: PObject; Count: integer;
  Options: TTextWriterWriteObjectOptions);
var
  ctxt: TJsonSaveContext;
  save: TRttiJsonSave;
  c, v: pointer; // reuse ctxt.Info if classes are the same (very likely)
begin
  c := nil;
  save := nil;
  {%H-}ctxt.Init(W, Options, nil);
  W.BlockBegin('[', Options);
  if Count > 0 then
    repeat
      v := Value^;
      if v = nil then
        W.AddNull
      else
      begin
        v := PPointer(v)^; // check Value class
        if v <> c then
        begin
          // need to retrieve the RTTI
          c := v;
          ctxt.Info := Rtti.RegisterClass(TClass(v));
          save := ctxt.Info.JsonSave;
        end;
        // this is where each object is serialized
        save(pointer(Value), ctxt);
      end;
      dec(Count);
      if Count = 0 then
        break;
      W.BlockAfterItem(Options);
      inc(Value);
    until false;
  W.BlockEnd(']', Options);
end;

procedure _JS_TList(Data: PList; const Ctxt: TJsonSaveContext);
begin
  if Data^ = nil then
    Ctxt.W.AddNull
  else
    _JS_Objects(Ctxt.W, pointer(Data^.List), Data^.Count, Ctxt.Options);
end;

procedure _JS_TObjectList(Data: PObjectList; const Ctxt: TJsonSaveContext);
var
  o: TTextWriterWriteObjectOptions;
begin
  if Data^ = nil then
  begin
    Ctxt.W.AddNull;
    exit;
  end;
  o := Ctxt.Options;
  if not (woObjectListWontStoreClassName in o) then
    include(o, woStoreClassName);
  _JS_Objects(Ctxt.W, pointer(Data^.List), Data^.Count, o);
end;

procedure _JS_TCollection(Data: PCollection; const Ctxt: TJsonSaveContext);
var
  item: TCollectionItem;
  i, last: PtrInt;
  c: TJsonSaveContext; // reuse same context for all collection items
begin
  if Data^ = nil then
  begin
    Ctxt.W.AddNull;
    exit;
  end;
  // can't use AddObjects() since we don't have access to the TCollection list
  {%H-}c.Init(Ctxt.W, Ctxt.Options, Rtti.RegisterClass(Data^.ItemClass));
  c.W.BlockBegin('[', c.Options);
  i := 0;
  last := Data^.Count - 1;
  if last >= 0 then
    repeat
      item := Data^.Items[i];
      TRttiJsonSave(c.Info.JsonSave)(@item, c);
      if i = last then
        break;
      c.W.BlockAfterItem(c.Options);
      inc(i);
    until false;
  c.W.BlockEnd(']', c.Options);
end;

procedure _JS_TStrings(Data: PStrings; const Ctxt: TJsonSaveContext);
var
  i, last: PtrInt;
begin
  if Data^ = nil then
  begin
    Ctxt.W.AddNull;
    exit;
  end;
  Ctxt.W.BlockBegin('[', Ctxt.Options);
  i := 0;
  last := Data^.Count - 1;
  if last >= 0 then
    repeat
      Ctxt.W.Add('"');
      Ctxt.W.AddJsonEscapeString(Data^.Strings[i]);
      Ctxt.W.Add('"');
      if i = last then
        break;
      Ctxt.W.BlockAfterItem(Ctxt.Options);
      inc(i);
    until false;
  Ctxt.W.BlockEnd(']', Ctxt.Options);
end;

procedure _JS_TRawUtf8List(Data: PRawUtf8List; const Ctxt: TJsonSaveContext);
var
  i, last: PtrInt;
  u: PPUtf8CharArray;
begin
  if Data^ = nil then
  begin
    Ctxt.W.AddNull;
    exit;
  end;
  Ctxt.W.BlockBegin('[', Ctxt.Options);
  i := 0;
  u := Data^.TextPtr;
  last := Data^.Count - 1;
  if last >= 0 then
    repeat
      Ctxt.W.Add('"');
      Ctxt.W.AddJsonEscape(u[i]);
      Ctxt.W.Add('"');
      if i = last then
        break;
      Ctxt.W.BlockAfterItem(Ctxt.Options);
      inc(i);
    until false;
  Ctxt.W.BlockEnd(']', Ctxt.Options);
end;

procedure _JS_TSynList(Data: PSynList; const Ctxt: TJsonSaveContext);
begin
  if Data^ = nil then
    Ctxt.W.AddNull
  else
    _JS_Objects(Ctxt.W, pointer(Data^.List), Data^.Count, Ctxt.Options);
end;

procedure _JS_TSynObjectList(Data: PSynObjectList; const Ctxt: TJsonSaveContext);
var
  o: TTextWriterWriteObjectOptions;
begin
  if Data^ = nil then
  begin
    Ctxt.W.AddNull;
    exit;
  end;
  o := Ctxt.Options;
  if not (woObjectListWontStoreClassName in o) then
    include(o, woStoreClassName);
  _JS_Objects(Ctxt.W, pointer(Data^.List), Data^.Count, o);
end;



{ ********** TTextWriter class with proper JSON escaping and WriteObject() support }

{ TTextWriter }

procedure TTextWriter.WriteObjectPropName(PropName: PUtf8Char;
  PropNameLen: PtrInt; Options: TTextWriterWriteObjectOptions);
begin
  if woHumanReadable in Options then
    AddCRAndIndent; // won't do anything if has already been done
  AddProp(PropName, PropNameLen); // handle twoForceJsonExtended
  if woHumanReadable in Options then
    Add(' ');
end;

procedure TTextWriter.WriteObjectPropNameShort(const PropName: shortstring;
  Options: TTextWriterWriteObjectOptions);
begin
  WriteObjectPropName(@PropName[1], ord(PropName[0]), Options);
end;

procedure TTextWriter.WriteObjectAsString(Value: TObject;
  Options: TTextWriterWriteObjectOptions);
begin
  Add('"');
  InternalJsonWriter.WriteObject(Value, Options);
  AddJsonEscape(fInternalJsonWriter);
  Add('"');
end;

procedure TTextWriter.AddDynArrayJsonAsString(aTypeInfo: PRttiInfo; var aValue;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  temp: TDynArray;
begin
  Add('"');
  temp.Init(aTypeInfo, aValue);
  InternalJsonWriter.AddDynArrayJson(temp, WriteOptions);
  AddJsonEscape(fInternalJsonWriter);
  Add('"');
end;

procedure TTextWriter.BlockBegin(Starter: AnsiChar;
  Options: TTextWriterWriteObjectOptions);
begin
  if woHumanReadable in Options then
  begin
    AddCRAndIndent;
    inc(fHumanReadableLevel);
  end;
  Add(Starter);
end;

procedure TTextWriter.BlockEnd(Stopper: AnsiChar;
  Options: TTextWriterWriteObjectOptions);
begin
  if woHumanReadable in Options then
  begin
    dec(fHumanReadableLevel);
    AddCRAndIndent;
  end;
  Add(Stopper);
end;

procedure TTextWriter.AddCRAndIndent;
begin
  if fBlockComment <> '' then
  begin
    AddShorter(' // ');
    AddString(fBlockComment);
    fBlockComment := '';
  end;
  inherited AddCRAndIndent;
end;

procedure TTextWriter.AddPropJsonString(const PropName: shortstring;
  const Text: RawUtf8);
begin
  AddProp(@PropName[1], ord(PropName[0]));
  AddJsonString(Text);
  AddComma;
end;

procedure TTextWriter.AddPropJSONInt64(const PropName: shortstring;
  Value: Int64);
begin
  AddProp(@PropName[1], ord(PropName[0]));
  Add(Value);
  AddComma;
end;

procedure TTextWriter.InternalAddFixedAnsi(Source: PAnsiChar; SourceChars: cardinal;
  AnsiToWide: PWordArray; Escape: TTextWriterKind);
var
  c: cardinal;
  esc: byte;
begin
  while SourceChars > 0 do
  begin
    c := byte(Source^);
    if c <= $7F then
    begin
      if c = 0 then
        exit;
      if B >= BEnd then
        FlushToStream;
      case Escape of // twJsonEscape or twOnSameLine only occur on c <= $7f
        twNone:
          begin
            inc(B);
            B^ := AnsiChar(c);
          end;
        twJsonEscape:
          begin
            esc := JSON_ESCAPE[c]; // c<>0 -> esc<>JSON_ESCAPE_ENDINGZERO
            if esc = JSON_ESCAPE_NONE then
            begin
              // no escape needed
              inc(B);
              B^ := AnsiChar(c);
            end
            else if esc = JSON_ESCAPE_UNICODEHEX then
            begin
              // characters below ' ', #7 e.g. -> \u0007
              AddShorter('\u00');
              AddByteToHex(c);
            end
            else
              Add('\', AnsiChar(esc)); // escaped as \ + b,t,n,f,r,\,"
          end;
        twOnSameLine:
          begin
            inc(B);
            if c < 32 then
              B^ := ' '
            else
              B^ := AnsiChar(c);
          end;
      end
    end
    else
    begin
      // no surrogate is expected in TSynAnsiFixedWidth charsets
      if BEnd - B <= 3 then
        FlushToStream;
      c := AnsiToWide[c]; // convert FixedAnsi char into Unicode char
      if c > $7ff then
      begin
        B[1] := AnsiChar($E0 or (c shr 12));
        B[2] := AnsiChar($80 or ((c shr 6) and $3F));
        B[3] := AnsiChar($80 or (c and $3F));
        inc(B, 3);
      end
      else
      begin
        B[1] := AnsiChar($C0 or (c shr 6));
        B[2] := AnsiChar($80 or (c and $3F));
        inc(B, 2);
      end;
    end;
    dec(SourceChars);
    inc(Source);
  end;
end;

destructor TTextWriter.Destroy;
begin
  inherited Destroy;
  fInternalJsonWriter.Free;
end;

function TTextWriter.InternalJsonWriter: TTextWriter;
begin
  if fInternalJsonWriter = nil then
    fInternalJsonWriter := TTextWriter.CreateOwnedStream
  else
    fInternalJsonWriter.CancelAll;
  result := fInternalJsonWriter;
end;

procedure TTextWriter.Add(P: PUtf8Char; Escape: TTextWriterKind);
begin
  if P <> nil then
    case Escape of
      twNone:
        AddNoJsonEscape(P, StrLen(P));
      twJsonEscape:
        AddJsonEscape(P);
      twOnSameLine:
        AddOnSameLine(P);
    end;
end;

procedure TTextWriter.Add(P: PUtf8Char; Len: PtrInt; Escape: TTextWriterKind);
begin
  if P <> nil then
    case Escape of
      twNone:
        AddNoJsonEscape(P, Len);
      twJsonEscape:
        AddJsonEscape(P, Len);
      twOnSameLine:
        AddOnSameLine(P, Len);
    end;
end;

procedure TTextWriter.AddW(P: PWord; Len: PtrInt; Escape: TTextWriterKind);
begin
  if P <> nil then
    case Escape of
      twNone:
        AddNoJsonEscapeW(P, Len);
      twJsonEscape:
        AddJsonEScapeW(P, Len);
      twOnSameLine:
        AddOnSameLineW(P, Len);
    end;
end;

procedure TTextWriter.AddAnsiString(const s: AnsiString; Escape: TTextWriterKind);
begin
  AddAnyAnsiBuffer(pointer(s), length(s), Escape, 0);
end;

procedure TTextWriter.AddAnyAnsiString(const s: RawByteString;
  Escape: TTextWriterKind; CodePage: integer);
var
  L: integer;
begin
  L := length(s);
  if L = 0 then
    exit;
  if (L > 2) and
     (PInteger(s)^ and $ffffff = JSON_BASE64_MAGIC_C) then
  begin
    AddNoJsonEscape(pointer(s), L); // was marked as a BLOB content
    exit;
  end;
  if CodePage < 0 then
    {$ifdef HASCODEPAGE}
    CodePage := StringCodePage(s);
    {$else}
    CodePage := 0; // TSynAnsiConvert.Engine(0)=CurrentAnsiConvert
    {$endif HASCODEPAGE}
  AddAnyAnsiBuffer(pointer(s), L, Escape, CodePage);
end;

procedure EngineAppendUtf8(W: TTextWriter; Engine: TSynAnsiConvert;
  P: PAnsiChar; Len: PtrInt; Escape: TTextWriterKind);
var
  tmp: TSynTempBuffer;
begin
  // explicit conversion using a temporary UTF-16 buffer on stack
  Engine.AnsiBufferToUnicode(tmp.Init(Len * 3), P, Len); // includes ending #0
  W.AddW(tmp.buf, 0, Escape);
  tmp.Done;
end;

procedure TTextWriter.AddAnyAnsiBuffer(P: PAnsiChar; Len: PtrInt;
  Escape: TTextWriterKind; CodePage: integer);
var
  B: PUtf8Char;
  engine: TSynAnsiConvert;
begin
  if Len > 0 then
  begin
    {$ifdef FPC} // CP_UTF8 is very likely on POSIX or LCL
    if CodePage = 0 then
      CodePage := CurrentAnsiConvert.CodePage;
    {$endif FPC}
    case CodePage of
      CP_UTF8:          // direct write of RawUtf8 content
        if Escape = twJsonEscape then
          Add(PUtf8Char(P), 0, Escape)    // faster with no Len
        else
          Add(PUtf8Char(P), Len, Escape); // expects a supplied Len
      CP_RAWBYTESTRING: // direct write of RawByteString content
        Add(PUtf8Char(P), Len, Escape);
      CP_UTF16:         // direct write of UTF-16 content
        AddW(PWord(P), 0, Escape);
      CP_RAWBLOB:       // RawBlob written with Base-64 encoding
        begin
          AddShorter(JSON_BASE64_MAGIC_S); // \uFFF0
          WrBase64(P, Len, {withMagic=}false);
        end;
    else
      begin
        // first handle trailing 7-bit ASCII chars, by quad
        B := pointer(P);
        if Len >= 4 then
          repeat
            if PCardinal(P)^ and $80808080 <> 0 then
              break; // break on first non ASCII quad
            inc(P, 4);
            dec(Len, 4);
          until Len < 4;
        if (Len > 0) and
           (P^ < #128) then
          repeat
            inc(P);
            dec(Len);
          until (Len = 0) or
                (P^ >= #127);
        if P <> pointer(B) then
          Add(B, P - B, Escape);
        if Len <= 0 then
          exit;
        // rely on explicit conversion for all remaining ASCII characters
        engine := TSynAnsiConvert.Engine(CodePage);
        if PClass(engine)^ = TSynAnsiFixedWidth then
          InternalAddFixedAnsi(P, Len,
            pointer(TSynAnsiFixedWidth(engine).AnsiToWide), Escape)
        else
          EngineAppendUtf8(self, engine, P, Len, Escape);
      end;
    end;
  end;
end;

procedure TTextWriter.WrBase64(P: PAnsiChar; Len: PtrUInt; withMagic: boolean);
var
  trailing, main, n: PtrUInt;
begin
  if withMagic then
    if Len <= 0 then
    begin
      AddNull; // JSON null is better than "" for BLOBs
      exit;
    end
    else
      AddShorter(JSON_BASE64_MAGIC_QUOTE_S); // "\uFFF0
  if Len > 0 then
  begin
    n := Len div 3;
    trailing := Len - n * 3;
    dec(Len, trailing);
    if BEnd - B > integer(n + 1) shl 2 then
    begin
      // will fit in available space in Buf -> fast in-buffer Base64 encoding
      n := Base64EncodeMain(@B[1], P, Len);
      inc(B, n * 4);
      inc(P, n * 3);
    end
    else
    begin
      // bigger than available space in Buf -> do it per chunk
      FlushToStream;
      while Len > 0 do
      begin
        // length(buf) const -> so is ((length(buf)-4)shr2 )*3
        n := ((fTempBufSize - 4) shr 2) * 3;
        if Len < n then
          n := Len;
        main := Base64EncodeMain(PAnsiChar(fTempBuf), P, n);
        n := main * 4;
        if n < cardinal(fTempBufSize) - 4 then
          inc(B, n)
        else
          WriteToStream(fTempBuf, n);
        n := main * 3;
        inc(P, n);
        dec(Len, n);
      end;
    end;
    if trailing > 0 then
    begin
      Base64EncodeTrailing(@B[1], P, trailing);
      inc(B, 4);
    end;
  end;
  if withMagic then
    Add('"');
end;

procedure TTextWriter.BinarySaveBase64(Data: pointer; Info: PRttiInfo;
  Kinds: TRttiKinds; withMagic, withCrc: boolean);
var
  temp: TSynTempBuffer;
begin
  BinarySave(Data, temp, Info, Kinds, withCrc);
  WrBase64(temp.buf, temp.len, withMagic);
  temp.Done;
end;

procedure TTextWriter.Add(const Format: RawUtf8; const Values: array of const;
  Escape: TTextWriterKind; WriteObjectOptions: TTextWriterWriteObjectOptions);
var
  ValuesIndex: integer;
  S, F: PUtf8Char;
begin
  if Format = '' then
    exit;
  if (Format = '%') and
     (high(Values) >= 0) then
  begin
    Add(Values[0], Escape);
    exit;
  end;
  ValuesIndex := 0;
  F := pointer(Format);
  repeat
    S := F;
    repeat
      if (F^ = #0) or
         (F^ = '%') then
        break;
      inc(F);
    until false;
    AddNoJsonEscape(S, F - S);
    if F^ = #0 then
      exit;
    // add next value as text instead of F^='%' placeholder
    if ValuesIndex <= high(Values) then // missing value will display nothing
      Add(Values[ValuesIndex], Escape, WriteObjectOptions);
    inc(F);
    inc(ValuesIndex);
  until false;
end;

procedure TTextWriter.AddTimeLog(Value: PInt64; QuoteChar: AnsiChar);
begin
  if BEnd - B <= 31 then
    FlushToStream;
  B := PTimeLogBits(Value)^.Text(B + 1, true, 'T', QuoteChar) - 1;
end;

procedure TTextWriter.AddUnixTime(Value: PInt64; QuoteChar: AnsiChar);
var
  DT: TDateTime;
begin
  // inlined UnixTimeToDateTime()
  DT := Value^ / SecsPerDay + UnixDateDelta;
  AddDateTime(@DT, 'T', QuoteChar, {withms=}false, {dateandtime=}true);
end;

procedure TTextWriter.AddUnixMSTime(Value: PInt64; WithMS: boolean;
  QuoteChar: AnsiChar);
var
  DT: TDateTime;
begin
  // inlined UnixMSTimeToDateTime()
  DT := Value^ / MSecsPerDay + UnixDateDelta;
  AddDateTime(@DT, 'T', QuoteChar, WithMS, {dateandtime=}true);
end;

procedure TTextWriter.AddDateTime(Value: PDateTime; FirstChar: AnsiChar;
  QuoteChar: AnsiChar; WithMS: boolean; AlwaysDateAndTime: boolean);
var
  T: TSynSystemTime;
begin
  if (Value^ = 0) and
     (QuoteChar = #0) then
    exit;
  if BEnd - B <= 25 then
    FlushToStream;
  inc(B);
  if QuoteChar <> #0 then
    B^ := QuoteChar
  else
    dec(B);
  if Value^ <> 0 then
  begin
    inc(B);
    if AlwaysDateAndTime or
       (trunc(Value^) <> 0) then
    begin
      T.FromDate(Value^);
      B := DateToIso8601PChar(B, true, T.Year, T.Month, T.Day);
    end;
    if AlwaysDateAndTime or
       (frac(Value^) <> 0) then
    begin
      T.FromTime(Value^);
      B := TimeToIso8601PChar(B, true, T.Hour, T.Minute, T.Second,
        T.MilliSecond, FirstChar, WithMS);
    end;
    dec(B);
  end;
  if QuoteChar <> #0 then
  begin
    inc(B);
    B^ := QuoteChar;
  end;
end;

procedure TTextWriter.AddDateTime(const Value: TDateTime; WithMS: boolean);
begin
  if Value = 0 then
    exit;
  if BEnd - B <= 23 then
    FlushToStream;
  inc(B);
  if trunc(Value) <> 0 then
    B := DateToIso8601PChar(Value, B, true);
  if frac(Value) <> 0 then
    B := TimeToIso8601PChar(Value, B, true, 'T', WithMS);
  dec(B);
end;

procedure TTextWriter.AddDateTimeMS(const Value: TDateTime; Expanded: boolean;
  FirstTimeChar: AnsiChar; const TZD: RawUtf8);
var
  T: TSynSystemTime;
begin
  if Value = 0 then
    exit;
  T.FromDateTime(Value);
  Add(DTMS_FMT[Expanded], [UInt4DigitsToShort(T.Year), UInt2DigitsToShortFast(T.Month),
    UInt2DigitsToShortFast(T.Day), FirstTimeChar, UInt2DigitsToShortFast(T.Hour),
    UInt2DigitsToShortFast(T.Minute), UInt2DigitsToShortFast(T.Second),
    UInt3DigitsToShort(T.MilliSecond), TZD]);
end;

procedure TTextWriter.AddCurrentLogTime(LocalTime: boolean);
var
  time: TSynSystemTime;
begin
  time.FromNow(LocalTime);
  time.AddLogTime(self);
end;

procedure TTextWriter.AddCurrentNCSALogTime(LocalTime: boolean);
var
  time: TSynSystemTime;
begin
  time.FromNow(LocalTime);
  if BEnd - B <= 21 then
    FlushToStream;
  inc(B, time.ToNCSAText(B + 1));
end;

procedure TTextWriter.AddCsvInteger(const Integers: array of integer);
var
  i: PtrInt;
begin
  if length(Integers) = 0 then
    exit;
  for i := 0 to high(Integers) do
  begin
    Add(Integers[i]);
    AddComma;
  end;
  CancelLastComma;
end;

procedure TTextWriter.AddCsvDouble(const Doubles: array of double);
var
  i: PtrInt;
begin
  if length(Doubles) = 0 then
    exit;
  for i := 0 to high(Doubles) do
  begin
    AddDouble(Doubles[i]);
    AddComma;
  end;
  CancelLastComma;
end;

procedure TTextWriter.AddCsvUtf8(const Values: array of RawUtf8);
var
  i: PtrInt;
begin
  if length(Values) = 0 then
    exit;
  for i := 0 to high(Values) do
  begin
    Add('"');
    AddJsonEscape(pointer(Values[i]));
    Add('"', ',');
  end;
  CancelLastComma;
end;

procedure TTextWriter.AddCsvConst(const Values: array of const);
var
  i: PtrInt;
begin
  if length(Values) = 0 then
    exit;
  for i := 0 to high(Values) do
  begin
    AddJsonEscape(Values[i]);
    AddComma;
  end;
  CancelLastComma;
end;

procedure TTextWriter.Add(const Values: array of const);
var
  i: PtrInt;
begin
  for i := 0 to high(Values) do
    AddJsonEscape(Values[i]);
end;

procedure TTextWriter.AddQuotedStringAsJson(const QuotedString: RawUtf8);
var
  L: integer;
  P, B: PUtf8Char;
  quote: AnsiChar;
begin
  L := length(QuotedString);
  if L > 0 then
  begin
    quote := QuotedString[1];
    if (quote in ['''', '"']) and
       (QuotedString[L] = quote) then
    begin
      Add('"');
      P := pointer(QuotedString);
      inc(P);
      repeat
        B := P;
        while P[0] <> quote do
          inc(P);
        if P[1] <> quote then
          break; // end quote
        inc(P);
        AddJsonEscape(B, P - B);
        inc(P); // ignore double quote
      until false;
      if P - B <> 0 then
        AddJsonEscape(B, P - B);
      Add('"');
    end
    else
      AddNoJsonEscape(pointer(QuotedString), length(QuotedString));
  end;
end;

procedure TTextWriter.AddVariant(const Value: variant; Escape: TTextWriterKind;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  cv: TSynInvokeableVariantType;
  v: TVarData absolute Value;
  vt: cardinal;
begin
  vt := v.VType;
  case vt of
    varEmpty, varNull:
      AddNull;
    varSmallint:
      Add(v.VSmallint);
    varShortInt:
      Add(v.VShortInt);
    varByte:
      AddU(v.VByte);
    varWord:
      AddU(v.VWord);
    varLongWord:
      AddU(v.VLongWord);
    varInteger:
      Add(v.VInteger);
    varInt64:
      Add(v.VInt64);
    varWord64:
      AddQ(v.VInt64);
    varSingle:
      AddSingle(v.VSingle);
    varDouble:
      AddDouble(v.VDouble);
    varDate:
      AddDateTime(@v.VDate, 'T', '"');
    varCurrency:
      AddCurr64(@v.VInt64);
    varBoolean:
      Add(v.VBoolean); // 'true'/'false'
    varVariant:
      AddVariant(PVariant(v.VPointer)^, Escape, WriteOptions);
    varString:
      AddText(RawByteString(v.VString), Escape);
    varOleStr {$ifdef HASVARUSTRING}, varUString{$endif}:
      AddTextW(v.VAny, Escape);
    varAny:
      // rkEnumeration,rkSet,rkDynArray,rkClass,rkInterface,rkRecord,rkObject
      // from TRttiCustomProp.GetValueDirect/GetValueGetter
      AddRttiVarData(TRttiVarData(V), WriteOptions);
  else
    if vt = varVariant or varByRef then
      AddVariant(PVariant(v.VPointer)^, Escape, WriteOptions)
    else if vt = varByRef or varString then
      AddText(PRawByteString(v.VAny)^, Escape)
    else if {$ifdef HASVARUSTRING} (vt = varByRef or varUString) or {$endif}
            (vt = varByRef or varOleStr) then
      AddTextW(PPointer(v.VAny)^, Escape)
    else if vt >= varArray then // complex types are always < varArray
      AddNull
    else if DocVariantType.FindSynVariantType(vt, cv) then
      cv.ToJson(self, Value, Escape)
    else if not CustomVariantToJson(self, Value, Escape) then
      raise EJSONException.CreateUtf8('%.AddVariant VType=%', [self, vt]);
  end;
end;

procedure TTextWriter.AddTypedJson(Value, TypeInfo: pointer;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  ctxt: TJsonSaveContext;
  save: TRttiJsonSave;
begin
  {%H-}ctxt.Init(self, WriteOptions, Rtti.RegisterType(TypeInfo));
  if ctxt.Info = nil then
    AddNull // paranoid check
  else
  begin
    save := ctxt.Info.JsonSave;
    if Assigned(save) then
      save(Value, ctxt)
    else
      BinarySaveBase64(Value, TypeInfo, rkRecordTypes, {withMagic=}true);
  end;
end;

procedure TTextWriter.WriteObject(Value: TObject;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  ctxt: TJsonSaveContext;
  save: TRttiJsonSave;
begin
  if Value = nil then
    AddNull
  else
  begin
    // Rtti.RegisterClass() may create fake RTTI if {$M+} was not used
    {%H-}ctxt.Init(self, WriteOptions, Rtti.RegisterClass(PClass(Value)^));
    save := ctxt.Info.JsonSave;
    if Assigned(save) then
      save(@Value, ctxt)
    else
      AddNull;
  end;
end;

procedure TTextWriter.AddRttiCustomJson(Value: pointer; RttiCustom: TObject;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  ctxt: TJsonSaveContext;
  save: TRttiJsonSave;
begin
  {%H-}ctxt.Init(self, WriteOptions, TRttiCustom(RttiCustom));
  save := ctxt.Info.JsonSave;
  if Assigned(save) then
    save(Value, ctxt)
  else
    BinarySaveBase64(Value, ctxt.Info.Info, rkAllTypes, {magic=}true);
end;

procedure TTextWriter.AddRttiVarData(const Value: TRttiVarData;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  V64: Int64;
begin
  if Value.PropValueIsInstance then
  begin
    // from TRttiCustomProp.GetValueGetter
    if rcfGetOrdProp in Value.Prop.Value.Cache.Flags then
    begin
      // rkEnumeration,rkSet,rkDynArray,rkClass,rkInterface
      V64 := Value.Prop.Prop.GetOrdProp(Value.PropValue);
      AddRttiCustomJson(@V64, Value.Prop.Value, WriteOptions);
    end
    else
      // rkRecord,rkObject have no getter methods
      raise EJSONException.CreateUtf8('%.AddRttiVarData: unsupported % (%)',
        [self, Value.Prop.Value.Name, ToText(Value.Prop.Value.Kind)^]);
  end
  else
    // from TRttiCustomProp.GetValueDirect
    AddRttiCustomJson(Value.PropValue, Value.Prop.Value, WriteOptions);
end;

procedure TTextWriter.AddText(const Text: RawByteString; Escape: TTextWriterKind);
begin
  if Escape = twJsonEscape then
    Add('"');
  {$ifdef HASCODEPAGE}
  AddAnyAnsiString(Text, Escape);
  {$else}
  Add(pointer(Text), length(Text), Escape);
  {$endif HASCODEPAGE}
  if Escape = twJsonEscape then
    Add('"');
end;

procedure TTextWriter.AddTextW(P: PWord; Escape: TTextWriterKind);
begin
  if Escape = twJsonEscape then
    Add('"');
  AddW(P, 0, Escape);
  if Escape = twJsonEscape then
    Add('"');
end;

function TTextWriter.AddJsonReformat(Json: PUtf8Char; Format: TTextWriterJsonFormat;
 EndOfObject: PUtf8Char): PUtf8Char;
var
  objEnd: AnsiChar;
  Name, Value: PUtf8Char;
  NameLen: integer;
  ValueLen: PtrInt;
  tab: PJsonCharSet;
begin
  result := nil;
  if Json = nil then
    exit;
  while (Json^ <= ' ') and
        (Json^ <> #0) do
    inc(Json);
  case Json^ of
    '[':
      begin
        // array
        repeat
          inc(Json)
        until (Json^ = #0) or
              (Json^ > ' ');
        if Json^ = ']' then
        begin
          Add('[');
          inc(Json);
        end
        else
        begin
          if not (Format in [jsonCompact, jsonUnquotedPropNameCompact]) then
            AddCRAndIndent;
          inc(fHumanReadableLevel);
          Add('[');
          repeat
            if Json = nil then
              exit;
            if not (Format in [jsonCompact, jsonUnquotedPropNameCompact]) then
              AddCRAndIndent;
            Json := AddJsonReformat(Json, Format, @objEnd);
            if objEnd = ']' then
              break;
            Add(objEnd);
          until false;
          dec(fHumanReadableLevel);
          if not (Format in [jsonCompact, jsonUnquotedPropNameCompact]) then
            AddCRAndIndent;
        end;
        Add(']');
      end;
    '{':
      begin
        // object
        repeat
          inc(Json)
        until (Json^ = #0) or
              (Json^ > ' ');
        Add('{');
        inc(fHumanReadableLevel);
        if not (Format in [jsonCompact, jsonUnquotedPropNameCompact]) then
          AddCRAndIndent;
        if Json^ = '}' then
          repeat
            inc(Json)
          until (Json^ = #0) or
                (Json^ > ' ')
        else
          repeat
            Name := GetJsonPropName(Json, @NameLen);
            if Name = nil then
              exit;
            if (Format in [jsonUnquotedPropName, jsonUnquotedPropNameCompact]) and
               JsonPropNameValid(Name) then
              AddNoJsonEscape(Name, NameLen)
            else
            begin
              Add('"');
              AddJsonEscape(Name);
              Add('"');
            end;
            if Format in [jsonCompact, jsonUnquotedPropNameCompact] then
              Add(':')
            else
              Add(':', ' ');
            while (Json^ <= ' ') and
                  (Json^ <> #0) do
              inc(Json);
            Json := AddJsonReformat(Json, Format, @objEnd);
            if objEnd = '}' then
              break;
            Add(objEnd);
            if not (Format in [jsonCompact, jsonUnquotedPropNameCompact]) then
              AddCRAndIndent;
          until false;
        dec(fHumanReadableLevel);
        if not (Format in [jsonCompact, jsonUnquotedPropNameCompact]) then
          AddCRAndIndent;
        Add('}');
      end;
    '"':
      begin
        // string
        Value := Json;
        Json := GotoEndOfJsonString(Json, @JSON_CHARS);
        if Json^ <> '"' then
          exit;
        inc(Json);
        AddNoJsonEscape(Value, Json - Value);
      end;
  else
    begin
      // numeric value or true/false/null constant or MongoDB extended
      tab := @JSON_CHARS;
      if jcEndOfJsonFieldOr0 in tab[Json^] then
        exit; // #0 , ] } :
      Value := Json;
      ValueLen := 0;
      repeat
        inc(ValueLen);
      until jcEndOfJsonFieldOr0 in tab[Json[ValueLen]];
      inc(Json, ValueLen);
      while (ValueLen > 0) and
            (Value[ValueLen - 1] <= ' ') do
        dec(ValueLen);
      AddNoJsonEscape(Value, ValueLen);
    end;
  end;
  if Json = nil then
    exit;
  while (Json^ <= ' ') and
        (Json^ <> #0) do
    inc(Json);
  if EndOfObject <> nil then
    EndOfObject^ := Json^;
  if Json^ <> #0 then
    repeat
      inc(Json)
    until (Json^ = #0) or
          (Json^ > ' ');
  result := Json;
end;

function TTextWriter.AddJsonToXML(Json: PUtf8Char;
  ArrayName, EndOfObject: PUtf8Char): PUtf8Char;
var
  objEnd: AnsiChar;
  Name, Value: PUtf8Char;
  n, c: integer;
begin
  result := nil;
  if Json = nil then
    exit;
  while (Json^ <= ' ') and
        (Json^ <> #0) do
    inc(Json);
  case Json^ of
  '[':
    begin
      repeat
        inc(Json);
      until (Json^ = #0) or
            (Json^ > ' ');
      if Json^ = ']' then
        Json := GotoNextNotSpace(Json + 1)
      else
      begin
        n := 0;
        repeat
          if Json = nil then
            exit;
          Add('<');
          if ArrayName = nil then
            Add(n)
          else
            AddXmlEscape(ArrayName);
          Add('>');
          Json := AddJsonToXML(Json, nil, @objEnd);
          Add('<', '/');
          if ArrayName = nil then
            Add(n)
          else
            AddXmlEscape(ArrayName);
          Add('>');
          inc(n);
        until objEnd = ']';
      end;
    end;
  '{':
    begin
      repeat
        inc(Json);
      until (Json^ = #0) or
            (Json^ > ' ');
      if Json^ = '}' then
        Json := GotoNextNotSpace(Json + 1)
      else
      begin
        repeat
          Name := GetJsonPropName(Json);
          if Name = nil then
            exit;
          while (Json^ <= ' ') and
                (Json^ <> #0) do
            inc(Json);
          if Json^ = '[' then // arrays are written as list of items, without root
            Json := AddJsonToXML(Json, Name, @objEnd)
          else
          begin
            Add('<');
            AddXmlEscape(Name);
            Add('>');
            Json := AddJsonToXML(Json, Name, @objEnd);
            Add('<', '/');
            AddXmlEscape(Name);
            Add('>');
          end;
        until objEnd = '}';
      end;
    end;
  else
    begin
      Value := GetJsonField(Json, result, nil, EndOfObject); // let wasString=nil
      if Value = nil then
        AddNull
      else
      begin
        c := PInteger(Value)^ and $ffffff;
        if (c = JSON_BASE64_MAGIC_C) or
           (c = JSON_SQLDATE_MAGIC_C) then
          inc(Value, 3); // just ignore the Magic codepoint encoded as UTF-8
        AddXmlEscape(Value);
      end;
      exit;
    end;
  end;
  if Json <> nil then
  begin
    while (Json^ <= ' ') and
          (Json^ <> #0) do
      inc(Json);
    if EndOfObject <> nil then
      EndOfObject^ := Json^;
    if Json^ <> #0 then
      repeat
        inc(Json);
      until (Json^ = #0) or
            (Json^ > ' ');
  end;
  result := Json;
end;

procedure TTextWriter.AddJsonEscape(P: Pointer; Len: PtrInt);
var
  i, start: PtrInt;
  {$ifdef CPUX86NOTPIC}
  tab: TNormTableByte absolute JSON_ESCAPE;
  {$else}
  tab: PByteArray;
  {$endif CPUX86NOTPIC}
label
  noesc;
begin
  if P = nil then
    exit;
  if Len = 0 then
    dec(Len); // -1 = no end = AddJsonEscape(P, 0)
  i := 0;
  {$ifndef CPUX86NOTPIC}
  tab := @JSON_ESCAPE;
  {$endif CPUX86NOTPIC}
  if tab[PByteArray(P)[i]] = JSON_ESCAPE_NONE then
  begin
noesc:
    start := i;
    if Len < 0 then  // fastest loop is with AddJsonEscape(P, 0)
      repeat
        inc(i);
      until tab[PByteArray(P)[i]] <> JSON_ESCAPE_NONE
    else
      repeat
        inc(i);
      until (i >= Len) or
            (tab[PByteArray(P)[i]] <> JSON_ESCAPE_NONE);
    inc(PByte(P), start);
    dec(i, start);
    if Len >= 0 then
      dec(Len, start);
    if BEnd - B <= i then
      AddNoJsonEscape(P, i)
    else
    begin
      MoveFast(P^, B[1], i);
      inc(B, i);
    end;
    if (Len >= 0) and
       (i >= Len) then
      exit;
  end;
  repeat
    if B >= BEnd then
      FlushToStream;
    case tab[PByteArray(P)[i]] of // better codegen with no temp var
      JSON_ESCAPE_NONE:
        goto noesc;
      JSON_ESCAPE_ENDINGZERO:
        // #0
        exit;
      JSON_ESCAPE_UNICODEHEX:
        begin
          // characters below ' ', #7 e.g. -> // 'u0007'
          PCardinal(B + 1)^ :=
            ord('\') + ord('u') shl 8 + ord('0') shl 16 + ord('0') shl 24;
          inc(B, 4);
          PWord(B + 1)^ := TwoDigitsHexWB[PByteArray(P)[i]];
        end;
    else
      // escaped as \ + b,t,n,f,r,\,"
      PWord(B + 1)^ := (integer(tab[PByteArray(P)[i]]) shl 8) or ord('\');
    end;
    inc(i);
    inc(B, 2);
  until (Len >= 0) and
        (i >= Len);
end;

procedure TTextWriter.AddJsonEscapeString(const s: string);
begin
  if s <> '' then
    {$ifdef UNICODE}
    AddJsonEscapeW(pointer(s), Length(s));
    {$else}
    AddAnyAnsiString(s, twJsonEscape, 0);
    {$endif UNICODE}
end;

procedure TTextWriter.AddJsonEscapeAnsiString(const s: AnsiString);
begin
  AddAnyAnsiString(s, twJsonEscape, 0);
end;

procedure TTextWriter.AddJsonEscapeW(P: PWord; Len: PtrInt);
var
  i, c, s: PtrInt;
  esc: byte;
  tab: PByteArray;
begin
  if P = nil then
    exit;
  if Len = 0 then
    Len := MaxInt;
  i := 0;
  while i < Len do
  begin
    s := i;
    tab := @JSON_ESCAPE;
    repeat
      c := PWordArray(P)[i];
      if (c <= 127) and
         (tab[c] <> JSON_ESCAPE_NONE) then
        break;
      inc(i);
    until i >= Len;
    if i <> s then
      AddNoJsonEscapeW(@PWordArray(P)[s], i - s);
    if i >= Len then
      exit;
    c := PWordArray(P)[i];
    if c = 0 then
      exit;
    esc := tab[c];
    if esc = JSON_ESCAPE_ENDINGZERO then // #0
      exit
    else if esc = JSON_ESCAPE_UNICODEHEX then
    begin
      // characters below ' ', #7 e.g. -> \u0007
      AddShorter('\u00');
      AddByteToHex(c);
    end
    else
      Add('\', AnsiChar(esc)); // escaped as \ + b,t,n,f,r,\,"
    inc(i);
  end;
end;

procedure TTextWriter.AddJsonEscape(const V: TVarRec);
begin
  with V do
    case VType of
      vtPointer:
        AddNull;
      vtString, vtAnsiString, {$ifdef HASVARUSTRING}vtUnicodeString, {$endif}
      vtPChar, vtChar, vtWideChar, vtWideString, vtClass:
        begin
          Add('"');
          case VType of
            vtString:
              if (VString <> nil) and
                 (VString^[0] <> #0) then
                AddJsonEscape(@VString^[1], ord(VString^[0]));
            vtAnsiString:
              AddJsonEscape(VAnsiString);
            {$ifdef HASVARUSTRING}
            vtUnicodeString:
              AddJsonEscapeW(pointer(UnicodeString(VUnicodeString)),
                length(UnicodeString(VUnicodeString)));
            {$endif HASVARUSTRING}
            vtPChar:
              AddJsonEscape(VPChar);
            vtChar:
              AddJsonEscape(@VChar, 1);
            vtWideChar:
              AddJsonEscapeW(@VWideChar, 1);
            vtWideString:
              AddJsonEscapeW(VWideString);
            vtClass:
              AddClassName(VClass);
          end;
          Add('"');
        end;
      vtBoolean:
        Add(VBoolean); // 'true'/'false'
      vtInteger:
        Add(VInteger);
      vtInt64:
        Add(VInt64^);
      {$ifdef FPC}
      vtQWord:
        AddQ(V.VQWord^);
      {$endif FPC}
      vtExtended:
        AddDouble(VExtended^);
      vtCurrency:
        AddCurr64(VInt64);
      vtObject:
        WriteObject(VObject);
      vtVariant:
        AddVariant(VVariant^, twJsonEscape);
    end;
end;

procedure TTextWriter.AddJsonEscape(Source: TTextWriter);
begin
  if Source.fTotalFileSize = 0 then
    AddJsonEscape(Source.fTempBuf, Source.B - Source.fTempBuf + 1)
  else
    AddJsonEscape(Pointer(Source.Text));
end;

procedure TTextWriter.AddNoJsonEscape(Source: TTextWriter);
begin
  if Source.fTotalFileSize = 0 then
    AddNoJsonEscape(Source.fTempBuf, Source.B - Source.fTempBuf + 1)
  else
    AddNoJsonEscapeUtf8(Source.Text);
end;

procedure TTextWriter.AddJsonString(const Text: RawUtf8);
begin
  Add('"');
  AddJsonEscape(pointer(Text));
  Add('"');
end;

procedure TTextWriter.Add(const V: TVarRec; Escape: TTextWriterKind;
  WriteObjectOptions: TTextWriterWriteObjectOptions);
begin
  with V do
    case VType of
      vtInteger:
        Add(VInteger);
      vtBoolean:
        if VBoolean then // normalize
          Add('1')
        else
          Add('0');
      vtChar:
        Add(@VChar, 1, Escape);
      vtExtended:
        AddDouble(VExtended^);
      vtCurrency:
        AddCurr64(VInt64);
      vtInt64:
        Add(VInt64^);
      {$ifdef FPC}
      vtQWord:
        AddQ(VQWord^);
      {$endif FPC}
      vtVariant:
        AddVariant(VVariant^, Escape);
      vtString:
        if (VString <> nil) and
           (VString^[0] <> #0) then
          Add(@VString^[1], ord(VString^[0]), Escape);
      vtInterface, vtPointer:
        AddPointer(PtrUInt(VPointer));
      vtPChar:
        Add(PUtf8Char(VPChar), Escape);
      vtObject:
        WriteObject(VObject, WriteObjectOptions);
      vtClass:
        AddClassName(VClass);
      vtWideChar:
        AddW(@VWideChar, 1, Escape);
      vtPWideChar:
        AddW(pointer(VPWideChar), StrLenW(VPWideChar), Escape);
      vtAnsiString:
        if VAnsiString <> nil then
          Add(VAnsiString, length(RawUtf8(VAnsiString)), Escape); // expect RawUtf8
      vtWideString:
        if VWideString <> nil then
          AddW(VWideString, length(WideString(VWideString)), Escape);
      {$ifdef HASVARUSTRING}
      vtUnicodeString:
        if VUnicodeString <> nil then // convert to UTF-8
          AddW(VUnicodeString, length(UnicodeString(VUnicodeString)), Escape);
      {$endif HASVARUSTRING}
    end;
end;

procedure TTextWriter.AddJson(const Format: RawUtf8; const Args, Params: array of const);
var
  temp: variant;
begin
  _JsonFmt(Format, Args, Params, JSON_OPTIONS_FAST, temp);
  AddVariant(temp, twJsonEscape);
end;

procedure TTextWriter.AddJsonArraysAsJsonObject(keys, values: PUtf8Char);
var
  k, v: PUtf8Char;
begin
  if (keys = nil) or
     (keys[0] <> '[') or
     (values = nil) or
     (values[0] <> '[') or
     (keys[1] = ']') or
     (values[1] = ']') then
  begin
    AddNull;
    exit;
  end;
  inc(keys); // jump initial [
  inc(values);
  Add('{');
  repeat
    k := GotoEndJsonItem(keys);
    v := GotoEndJsonItem(values);
    if (k = nil) or
       (v = nil) then
      break; // invalid JSON input
    AddNoJsonEscape(keys, k - keys);
    Add(':');
    AddNoJsonEscape(values, v - values);
    AddComma;
    if (k^ <> ',') or
       (v^ <> ',') then
      break; // reached the end of the input JSON arrays
    keys := k + 1;
    values := v + 1;
  until false;
  CancelLastComma;
  Add('}');
end;

procedure TTextWriter.AddJsonEscape(const NameValuePairs: array of const);
var
  a: integer;

  procedure WriteValue;
  begin
    case VarRecAsChar(NameValuePairs[a]) of
      ord('['):
        begin
          Add('[');
          while a < high(NameValuePairs) do
          begin
            inc(a);
            if VarRecAsChar(NameValuePairs[a]) = ord(']') then
              break;
            WriteValue;
          end;
          CancelLastComma;
          Add(']');
        end;
      ord('{'):
        begin
          Add('{');
          while a < high(NameValuePairs) do
          begin
            inc(a);
            if VarRecAsChar(NameValuePairs[a]) = ord('}') then
              break;
            AddJsonEscape(NameValuePairs[a]);
            Add(':');
            inc(a);
            WriteValue;
          end;
          CancelLastComma;
          Add('}');
        end
    else
      AddJsonEscape(NameValuePairs[a]);
    end;
    AddComma;
  end;

begin
  Add('{');
  a := 0;
  while a < high(NameValuePairs) do
  begin
    AddJsonEscape(NameValuePairs[a]);
    inc(a);
    Add(':');
    WriteValue;
    inc(a);
  end;
  CancelLastComma;
  Add('}');
end;

function TTextWriter.AddRecordJson(Value: pointer; RecordInfo: PRttiInfo;
  WriteOptions: TTextWriterWriteObjectOptions): PtrInt;
var
  ctxt: TJsonSaveContext;
begin
  {%H-}ctxt.Init(self, WriteOptions, Rtti.RegisterType(RecordInfo));
  if rcfHasNestedProperties in ctxt.Info.Flags then
    // we know the fields from text definition
    TRttiJsonSave(ctxt.Info.JsonSave)(Value, ctxt)
  else
    // fallback to binary serialization, trailing crc32c and Base64 encoding
    BinarySaveBase64(Value, RecordInfo, rkRecordTypes, {magic=}true);
  result := ctxt.Info.Size;
end;

procedure TTextWriter.AddVoidRecordJson(RecordInfo: PRttiInfo;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  tmp: TSynTempBuffer;
begin
  tmp.InitZero(RecordInfo.RecordSize);
  AddRecordJson(tmp.buf, RecordInfo, WriteOptions);
  tmp.Done;
end;

procedure TTextWriter.AddDynArrayJson(var DynArray: TDynArray;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  ctxt: TJsonSaveContext;
  len, backup: PtrInt;
  hacklen: PDALen;
begin
  len := DynArray.Count;
  if len = 0 then
    Add('[', ']')
  else
  begin
    {%H-}ctxt.Init(self, WriteOptions, DynArray.Info);
    hacklen := PDALen(PAnsiChar(DynArray.Value^) - _DALEN);
    backup := hacklen^;
    hacklen^ := len - _DAOFF; // may use ExternalCount -> ovewrite length(Array)
    _JS_DynArray(DynArray.Value, ctxt);
    hacklen^ := backup; // restore original length/capacity
  end;
end;

procedure TTextWriter.AddDynArrayJson(var DynArray: TDynArrayHashed;
  WriteOptions: TTextWriterWriteObjectOptions);
begin
  // needed if UNDIRECTDYNARRAY is defined (Delphi 2009+)
  AddDynArrayJson(PDynArray(@DynArray)^, WriteOptions);
end;

function TTextWriter.AddDynArrayJson(Value: pointer; Info: TRttiCustom;
  WriteOptions: TTextWriterWriteObjectOptions): PtrInt;
var
  temp: TDynArray;
begin
  if Info.Kind <> rkDynArray then
    raise EDynArray.CreateUtf8('%.AddDynArrayJson: % is %, expected rkDynArray',
      [self, Info.Name, ToText(Info.Kind)^]);
  temp.InitRtti(Info, Value^);
  AddDynArrayJson(temp, WriteOptions);
  result := temp.Info.Cache.ItemSize;
end;


{ ********** Low-Level JSON UnSerialization for all TRttiParserType }

{ TJsonParserContext }

procedure TJsonParserContext.Init(P: PUtf8Char; Rtti: TRttiCustom;
  O: TJsonParserOptions; CV: PDocVariantOptions; ObjectListItemClass: TClass);
begin
  Json := P;
  Valid := true;
  if Rtti <> nil then
    O := O + TRttiJson(Rtti).fIncludeReadOptions;
  Options := O;
  if CV <> nil then
  begin
    DVO := CV^;
    CustomVariant := @DVO;
  end
  else if jpoHandleCustomVariants in O then
  begin
    DVO := JSON_OPTIONS_FAST;
    CustomVariant := @DVO;
  end
  else
    CustomVariant := nil;
  if jpoHandleCustomVariantsWithinString in O then
    include(DVO, dvoJsonObjectParseWithinString);
  Info := Rtti;
  Prop := nil;
  if ObjectListItemClass = nil then
    ObjectListItem := nil
  else
    ObjectListItem := mormot.core.rtti.Rtti.RegisterClass(ObjectListItemClass);
end;

function TJsonParserContext.ParseNext: boolean;
begin
  Value := GetJsonField(Json, Json, @WasString, @EndOfObject, @ValueLen);
  result := Json <> nil;
  Valid := result;
end;

function TJsonParserContext.ParseUtf8: RawUtf8;
begin
  if not ParseNext then
    ValueLen := 0; // return ''
  FastSetString(result, Value, ValueLen)
end;

function TJsonParserContext.ParseString: string;
begin
  if not ParseNext then
    ValueLen := 0; // return ''
  Utf8DecodeToString(Value, ValueLen, result);
end;

procedure TJsonParserContext.ParseEndOfObject;
begin
  if Valid then
  begin
    if Json^ <> #0 then
      Json := mormot.core.json.ParseEndOfObject(Json, EndOfObject);
    Valid := Json <> nil;
  end;
end;

function TJsonParserContext.ParseNull: boolean;
var
  P: PUtf8Char;
begin
  result := false;
  if Valid then
    if Json <> nil then
    begin
      P := GotoNextNotSpace(Json);
      Json := P;
      if PCardinal(P)^ = NULL_LOW then
      begin
        P := mormot.core.json.ParseEndOfObject(P + 4, EndOfObject);
        if P <> nil then
        begin
          Json := P;
          result := true;
        end
        else
          Valid := false;
      end;
    end
    else
      result := true; // nil -> null
end;

function TJsonParserContext.ParseArray: boolean;
var
  P: PUtf8Char;
begin
  result := false; // no need to parse
  P := GotoNextNotSpace(Json);
  Json := P;
  if P^ = '[' then
  begin
    P := GotoNextNotSpace(P + 1); // ignore trailing [
    if P^ = ']' then
    begin
      // void but valid array
      P := mormot.core.json.ParseEndOfObject(P + 1, EndOfObject);
      Valid := P <> nil;
      Json := P;
    end
    else
    begin
      // we have a non void [...] array -> caller should parse it
      result := true;
      Json := P;
    end;
  end
  else
    Valid := ParseNull; // only not [...] value allowed is null
end;

function TJsonParserContext.ParseNewObject: TObject;
begin
  if ObjectListItem = nil then
  begin
    Info := JsonRetrieveObjectRttiCustom(Json,
      jpoObjectListClassNameGlobalFindClass in Options);
    if (Info <> nil) and
       (Json^ = ',') then
      Json^ := '{' // will now parse other properties as a regular Json object
    else
    begin
      Valid := false;
      result := nil;
      exit;
    end;
  end;
  result := TRttiJson(Info).ParseNewInstance(self);
end;

function TJsonParserContext.ParseObject(const Names: array of RawUtf8;
  Values: PValuePUtf8CharArray; HandleValuesAsObjectOrArray: boolean): boolean;
begin
  Json := JsonDecode(Json, Names, Values, HandleValuesAsObjectOrArray);
  if Json = nil then
    Valid := false
  else
    ParseEndOfObject;
  result := Valid;
end;



procedure _JL_Boolean(Data: PBoolean; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Data^ := GetBoolean(Ctxt.Value);
end;

procedure _JL_Byte(Data: PByte; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Data^ := GetCardinal(Ctxt.Value);
end;

procedure _JL_Cardinal(Data: PCardinal; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Data^ := GetCardinal(Ctxt.Value);
end;

procedure _JL_Integer(Data: PInteger; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Data^ := GetInteger(Ctxt.Value);
end;

procedure _JL_Currency(Data: PInt64; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Data^ := StrToCurr64(Ctxt.Value);
end;

procedure _JL_Double(Data: PDouble; var Ctxt: TJsonParserContext);
var
  err: integer;
begin
  if Ctxt.ParseNext then
  begin
    unaligned(Data^) := GetExtended(Ctxt.Value, err);
    Ctxt.Valid := err = 0;
  end;
end;

procedure _JL_Extended(Data: PSynExtended; var Ctxt: TJsonParserContext);
var
  err: integer;
begin
  if Ctxt.ParseNext then
  begin
    Data^ := GetExtended(Ctxt.Value, err);
    Ctxt.Valid := err = 0;
  end;
end;

procedure _JL_Int64(Data: PInt64; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    if Ctxt.WasString and
       (Ctxt.ValueLen = SizeOf(Data^) * 2) then
      Ctxt.Valid := (jpoAllowInt64Hex in Ctxt.Options) and
        HexDisplayToBin(PAnsiChar(Ctxt.Value), pointer(Data), SizeOf(Data^))
    else
      SetInt64(Ctxt.Value, Data^);
end;

procedure _JL_QWord(Data: PQWord; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    if Ctxt.WasString and
       (Ctxt.ValueLen = SizeOf(Data^) * 2) then
      Ctxt.Valid := (jpoAllowInt64Hex in Ctxt.Options) and
        HexDisplayToBin(PAnsiChar(Ctxt.Value), pointer(Data), SizeOf(Data^))
    else
      SetQWord(Ctxt.Value, Data^);
end;

procedure _JL_RawByteString(Data: PRawByteString; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    if Ctxt.Value = nil then // null
      Data^ := ''
    else
      Ctxt.Valid := Base64MagicCheckAndDecode(Ctxt.Value, Ctxt.ValueLen, Data^);
end;

procedure _JL_RawJson(Data: PRawJson; var Ctxt: TJsonParserContext);
begin
  GetJsonItemAsRawJson(Ctxt.Json, Data^, @Ctxt.EndOfObject);
  Ctxt.Valid := Ctxt.Json <> nil;
end;

procedure _JL_RawUtf8(Data: PRawByteString; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    // will handle RawUtf8 but also AnsiString, WinAnsiString and RawUnicode
    if Ctxt.Info.Cache.CodePage = CP_UTF8 then
      FastSetString(RawUtf8(Data^), Ctxt.Value, Ctxt.ValueLen)
    else if Ctxt.Info.Cache.CodePage >= CP_RAWBLOB then
      Ctxt.Valid := false // paranoid check (RawByteString should handle it)
    else
      Ctxt.Info.Cache.Engine.Utf8BufferToAnsi(Ctxt.Value, Ctxt.ValueLen, Data^);
end;

procedure _JL_Single(Data: PSingle; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Data^ := GetExtended(Ctxt.Value);
end;

procedure _JL_String(Data: PString; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Utf8DecodeToString(Ctxt.Value, Ctxt.ValueLen, Data^);
end;

procedure _JL_SynUnicode(Data: PSynUnicode; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Utf8ToSynUnicode(Ctxt.Value, Ctxt.ValueLen, Data^);
end;

procedure _JL_DateTime(Data: PDateTime; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    if Ctxt.WasString then
      Iso8601ToDateTimePUtf8CharVar(Ctxt.Value, Ctxt.ValueLen, Data^)
    else
      Data^ := GetExtended(Ctxt.Value);
end;

procedure _JL_GUID(Data: PByteArray; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Ctxt.Valid := TextToGuid(Ctxt.Value, Data) <> nil;
end;

procedure _JL_Hash(Data: PByte; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Ctxt.Valid := (Ctxt.ValueLen = Ctxt.Info.Size * 2) and
      HexDisplayToBin(PAnsiChar(Ctxt.Value), Data, Ctxt.Info.Size);
end;

procedure _JL_Binary(Data: PByte; var Ctxt: TJsonParserContext);
var
  v: QWord;
begin
  if Ctxt.ParseNext then
    if Ctxt.WasString then
    begin
      FillZeroSmall(Data, Ctxt.Info.Size);
      if Ctxt.ValueLen > 0 then // "" -> is valid 0
        Ctxt.Valid := (Ctxt.ValueLen = Ctxt.Info.BinarySize * 2) and
          HexDisplayToBin(PAnsiChar(Ctxt.Value), Data, Ctxt.Info.BinarySize);
    end
    else
    begin
      SetQWord(Ctxt.Value, v{%H-});
      MoveSmall(@v, Data, Ctxt.Info.Size);
    end;
end;

procedure _JL_TimeLog(Data: PQWord; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    if Ctxt.WasString then
      Data^ := Iso8601ToTimeLogPUtf8Char(Ctxt.Value, Ctxt.ValueLen)
    else
      SetQWord(Ctxt.Value, Data^);
end;

procedure _JL_UnicodeString(Data: pointer; var Ctxt: TJsonParserContext);
begin
  Ctxt.ParseNext;
  {$ifdef HASVARUSTRING}
  if Ctxt.Valid then
    Utf8DecodeToUnicodeString(Ctxt.Value, Ctxt.ValueLen, PUnicodeString(Data)^);
  {$endif HASVARUSTRING}
end;

procedure _JL_UnixTime(Data: PQWord; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    if Ctxt.WasString then
      Data^ := TimeLogToUnixTime(Iso8601ToTimeLogPUtf8Char(
        Ctxt.Value, Ctxt.ValueLen))
    else
      SetQWord(Ctxt.Value, Data^);
end;

procedure _JL_UnixMSTime(Data: PQWord; var Ctxt: TJsonParserContext);
var
  dt: TDateTime; // for ms resolution
begin
  if Ctxt.ParseNext then
    if Ctxt.WasString then
    begin
      Iso8601ToDateTimePUtf8CharVar(Ctxt.Value, Ctxt.ValueLen, dt);
      Data^ := DateTimeToUnixMSTime(dt);
    end
    else
      SetQWord(Ctxt.Value, Data^);
end;

procedure _JL_Variant(Data: PVariant; var Ctxt: TJsonParserContext);
begin
  Ctxt.Json := VariantLoadJson(Data^, Ctxt.Json, @Ctxt.EndOfObject,
    Ctxt.CustomVariant, jpoAllowDouble in Ctxt.Options);
  Ctxt.Valid := Ctxt.Json <> nil;
end;

procedure _JL_WideString(Data: PWideString; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Utf8ToWideString(Ctxt.Value, Ctxt.ValueLen, Data^);
end;

procedure _JL_WinAnsi(Data: PRawByteString; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    WinAnsiConvert.Utf8BufferToAnsi(Ctxt.Value, Ctxt.ValueLen, Data^);
end;

procedure _JL_Word(Data: PWord; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Data^ := GetCardinal(Ctxt.Value);
end;

procedure _JL_Enumeration(Data: pointer; var Ctxt: TJsonParserContext);
var
  v: PtrInt;
  err: integer;
begin
  if Ctxt.ParseNext then
  begin
    if Ctxt.WasString then
      v := Ctxt.Info.Cache.EnumInfo.GetEnumNameValue(Ctxt.Value, Ctxt.ValueLen)
    else
    begin
      v := GetInteger(Ctxt.Value, err);
      if (err <> 0) or
         (PtrUInt(v) > Ctxt.Info.Cache.EnumMax) then
        v := -1;
    end;
    if v < 0 then
      if jpoIgnoreUnknownEnum in Ctxt.Options then
        v := 0
      else
        Ctxt.Valid := false;
    MoveSmall(@v, Data, Ctxt.Info.Size);
  end;
end;

procedure _JL_Set(Data: pointer; var Ctxt: TJsonParserContext);
var
  v: QWord;
begin
  v := GetSetNameValue(Ctxt.Info.Cache.EnumList,
    Ctxt.Info.Cache.EnumMax, Ctxt.Json, Ctxt.EndOfObject);
  Ctxt.Valid := Ctxt.Json <> nil;
  MoveSmall(@v, Data, Ctxt.Info.Size);
end;

procedure _JL_Array(Data: PAnsiChar; var Ctxt: TJsonParserContext);
var
  n: integer;
  arrinfo: TRttiCustom;
begin
  if not Ctxt.ParseArray then
    // detect void (i.e. []) or invalid array
    exit;
  if PCardinal(Ctxt.Json)^ = JSON_BASE64_MAGIC_QUOTE_C then
    // raw RTTI binary layout with a single Base-64 encoded item
    Ctxt.Valid := Ctxt.ParseNext and
              (Ctxt.EndOfObject = ']') and
              (Ctxt.Value <> nil) and
              (PCardinal(Ctxt.Value)^ and $ffffff = JSON_BASE64_MAGIC_C) and
              BinaryLoadBase64(pointer(Ctxt.Value + 3), Ctxt.ValueLen - 3,
                Data, Ctxt.Info.Info, {uri=}false, [rkArray], {withcrc=}false)
  else
  begin
    // efficient load of all JSON items
    arrinfo := Ctxt.Info;
    Ctxt.Info := arrinfo.ArrayRtti; // nested context = item
    n := arrInfo.Cache.ItemCount;
    repeat
      TRttiJsonLoad(Ctxt.Info.JsonLoad)(Data, Ctxt);
      dec(n);
      if Ctxt.Valid then
        if (n > 0) and
           (Ctxt.EndOfObject = ',') then
        begin
          // continue with the next item
          inc(Data, arrinfo.Cache.ItemSize);
          continue;
        end
        else if (n = 0) and
                (Ctxt.EndOfObject = ']') then
          // reached end of arrray
          break;
      Ctxt.Valid := false; // unexpected end
      exit;
    until false;
    Ctxt.Info := arrinfo;
  end;
  Ctxt.ParseEndOfObject; // mimics GetJsonField() / Ctxt.ParseNext
end;

procedure _JL_DynArray_Custom(Data: PAnsiChar; var Ctxt: TJsonParserContext);
begin
  // TRttiJson.RegisterCustomSerializer() custom callback for each item
  TOnRttiJsonRead(TRttiJson(Ctxt.Info).fJsonReader)(Ctxt, Data);
end;

procedure _JL_DynArray(Data: PAnsiChar; var Ctxt: TJsonParserContext);
var
  load: TRttiJsonLoad;
  n, cap: PtrInt;
  arr: PPointer;
  arrinfo: TRttiCustom;
begin
  arr := pointer(Data);
  if arr^ <> nil then
    Ctxt.Info.ValueFinalize(arr); // reset whole array variable
  if not Ctxt.ParseArray then
    // detect void (i.e. []) or invalid array
    exit;
  if PCardinal(Ctxt.Json)^ = JSON_BASE64_MAGIC_QUOTE_C then
    // raw RTTI binary layout with a single Base-64 encoded item
    Ctxt.Valid := Ctxt.ParseNext and
              (Ctxt.EndOfObject = ']') and
              (Ctxt.Value <> nil) and
              (PCardinal(Ctxt.Value)^ and $ffffff = JSON_BASE64_MAGIC_C) and
              BinaryLoadBase64(pointer(Ctxt.Value + 3), Ctxt.ValueLen - 3,
                Data, Ctxt.Info.Info, {uri=}false, [rkDynArray], {withcrc=}false)
  else
  begin
    // efficient load of all JSON items
    arrinfo := Ctxt.Info;
    if TRttiJson(arrinfo).fJsonReader.Code <> nil then
      // TRttiJson.RegisterCustomSerializer() custom callbacks
      load := @_JL_DynArray_Custom
    else
    begin
      Ctxt.Info := arrinfo.ArrayRtti;
      if Ctxt.Info = nil then
        load := nil
      else
        load := Ctxt.Info.JsonLoad;
    end;
    // initial guess of the JSON array count - will browse up to 256KB of input
    cap := abs(JsonArrayCount(Ctxt.Json, Ctxt.Json + 256 shl 10));
    if (cap = 0) or
       not Assigned(load) then
    begin
      Ctxt.Valid := false;
      exit;
    end;
    Data := DynArrayNew(arr, cap, arrinfo.Cache.ItemSize); // alloc zeroed mem
    // main JSON unserialization loop
    n := 0;
    repeat
      if n = cap then
      begin
        // grow if our initial guess was aborted due to huge input
        cap := NextGrow(cap);
        Data := DynArrayGrow(arr, cap, arrinfo.Cache.ItemSize) +
                  (n * arrinfo.Cache.ItemSize);
      end;
      // unserialize one item
      load(Data, Ctxt); // will call _JL_RttiCustom() for T*ObjArray
      inc(n);
      if Ctxt.Valid then
        if Ctxt.EndOfObject = ',' then
        begin
          // continue with the next item
          inc(Data, arrinfo.Cache.ItemSize);
          continue;
        end
        else if Ctxt.EndOfObject = ']' then
          // reached end of arrray
          break;
      Ctxt.Valid := false; // unexpected end
      arrinfo.ValueFinalize(arr); // whole array clear on error
      exit;
    until false;
    if n <> cap then
      // don't size down the grown memory buffer, just fake its length
      PDALen(PAnsiChar(arr^) - _DALEN)^ := n - _DAOFF;
    Ctxt.Info := arrinfo;
  end;
  Ctxt.ParseEndOfObject; // mimics GetJsonField() / Ctxt.ParseNext
end;

procedure _JL_Interface(Data: PInterface; var Ctxt: TJsonParserContext);
begin
  Ctxt.Valid := Ctxt.ParseNull;
  Data^ := nil;
end;

// defined here to have _JL_RawJson and _JL_Variant known
procedure TJsonParserContext.ParseProp(Data: pointer);
var
  v: TRttiVarData;
begin
  if Info.Parser = ptRawJson then
  begin
    v.VType := varString;
    v.Data.VAny := nil;
    _JL_RawJson(@v.Data.VAny, self);
    if Valid then
      Prop^.Prop.SetLongStrProp(Data, RawJson(v.Data.VAny));
  end
  else
  begin
    v.VType := 0;
    _JL_Variant(@v, self); // VariantLoadJson() over Ctxt
    if Valid then
      Valid := Prop^.Prop.SetValue(Data, variant(v));
  end;
  VarClearProc(v.Data);
end;

function JsonLoadProp(Data: PAnsiChar; const Prop: TRttiCustomProp;
  var Ctxt: TJsonParserContext): boolean;
var
  tmp: TObject;
  load: TRttiJsonLoad;
begin
  Ctxt.Info := Prop.Value; // caller will restore it afterwards
  Ctxt.Prop := @Prop;
  load := Ctxt.Info.JsonLoad;
  if not Assigned(load) then
    Ctxt.Valid := false
  else if Prop.OffsetSet >= 0 then
    // fast parsing into the property/field memory
    load(Data + Prop.OffsetSet, Ctxt)
  else if Prop.Value.Kind = rkClass then
    // special case of a setter method for a class property: use a temp instance
    if jpoSetterNoCreate in Ctxt.Options then
      Ctxt.Valid := false
    else
    begin
      tmp := TRttiJson(Ctxt.Info).fClassNewInstance(Ctxt.Info);
      try
        load(@tmp, Ctxt); // JsonToObject(tmp)
        if not Ctxt.Valid then
          FreeAndNil(tmp)
        else
        begin
          Prop.Prop.SetOrdProp(pointer(Data), PtrInt(tmp));
          if jpoSetterExpectsToFreeTempInstance in Ctxt.Options then
            FreeAndNil(tmp);
        end;
      except
        on Exception do
          tmp.Free;
      end;
    end
  else
    // we need to call a setter -> use a temp variant
    Ctxt.ParseProp(Data);
  Ctxt.Prop := nil;
  result := Ctxt.Valid;
end;

procedure _JL_RttiCustom(Data: PAnsiChar; var Ctxt: TJsonParserContext);
var
  root: TRttiJson;
  p: integer;
  prop: PRttiCustomProp;
  propname: PUtf8Char;
  propnamelen: integer;
label
  nxt, any;
begin
  if Ctxt.Json <> nil then
    Ctxt.Json := GotoNextNotSpace(Ctxt.Json);
  if TRttiJson(Ctxt.Info).fJsonReader.Code <> nil then
  begin
    // TRttiJson.RegisterCustomSerializer() custom callbacks
    if Ctxt.Info.Kind = rkClass then
      Data := PPointer(Data)^; // as expected by the callback
    TOnRttiJsonRead(TRttiJson(Ctxt.Info).fJsonReader)(Ctxt, Data)
  end
  else
  begin
    // always finalize and reset the existing values (in case of missing props)
    if Ctxt.Info.Kind = rkClass then
    begin
      if Ctxt.ParseNull then
      begin
        if not (jpoNullDontReleaseObjectInstance in Ctxt.Options) then
          FreeAndNil(PObject(Data)^);
        exit;
      end;
      if PPointer(Data)^ = nil then
        // e.g. from _JL_DynArray for T*ObjArray
        PPointer(Data)^ := TRttiJson(Ctxt.Info).fClassNewInstance(Ctxt.Info)
      else if jpoClearValues in Ctxt.Options then
        Ctxt.Info.Props.FinalizeAndClearPublishedProperties(PPointer(Data)^);
      // class instances are accessed by reference, records are stored by value
      Data := PPointer(Data)^;
      if (rcfSynPersistentHook in Ctxt.Info.Flags) and
         (TSPHook(Data).RttiBeforeReadObject(@Ctxt)) then
        exit;
    end
    else
    begin
      if jpoClearValues in Ctxt.Options then
        Ctxt.Info.ValueFinalizeAndClear(Data);
      if Ctxt.ParseNull then
        exit;
    end;
    // regular JSON unserialization using nested fields/properties
    Ctxt.Json := GotoNextNotSpace(Ctxt.Json);
    if Ctxt.Json^ <> '{' then
    begin
      Ctxt.Valid := false;
      exit;
    end;
    Ctxt.Json := GotoNextNotSpace(Ctxt.Json + 1);
    if Ctxt.Json^ = '}' then
    begin
      inc(Ctxt.Json);
      Ctxt.ParseEndOfObject;
    end
    else
    begin
      root := pointer(Ctxt.Info); // Ctxt.Info overriden in JsonLoadProp()
      prop := pointer(root.Props.List);
      for p := 1 to root.Props.Count do
      begin
nxt:    propname := GetJsonPropName(Ctxt.Json, @propnamelen);
        Ctxt.Valid := (Ctxt.Json <> nil) and
                      (propname <> nil);
        if not Ctxt.Valid then
          break;
        // O(1) optimistic process of the property name, following RTTI order
        if (prop^.Name <> '') and
           IdemPropNameU(prop^.Name, propname, propnamelen) then
          if JsonLoadProp(Data, prop^, Ctxt) then
            if Ctxt.EndOfObject = '}' then
              break
            else
              inc(prop)
          else
            break
        else if (Ctxt.Info.Kind = rkClass) and
                IdemPropName('ClassName', propname, propnamelen) then
        begin
          // woStoreClassName was used -> just ignore the class name
          Ctxt.Json := GotoNextJsonItem(Ctxt.Json, 1, @Ctxt.EndOfObject);
          Ctxt.Valid := Ctxt.Json <> nil;
          if Ctxt.Valid then
            goto nxt;
          break;
        end
        else
        begin
          // we didn't find the property in its natural place -> full lookup
          repeat
            prop := root.Props.Find(propname, propnamelen);
            if prop = nil then
              // unexpected "prop": value
              if (rcfReadIgnoreUnknownFields in root.Flags) or
                 (jpoIgnoreUnknownProperty in Ctxt.Options) then
              begin
                Ctxt.Json := GotoNextJsonItem(Ctxt.Json, 1, @Ctxt.EndOfObject);
                Ctxt.Valid := Ctxt.Json <> nil;
              end
              else
                Ctxt.Valid := false
            else
              Ctxt.Valid := JsonLoadProp(Data, prop^, Ctxt);
            if (not Ctxt.Valid) or
               (Ctxt.EndOfObject = '}') then
               break;
any:        propname := GetJsonPropName(Ctxt.Json, @propnamelen);
            Ctxt.Valid := (Ctxt.Json <> nil) and
                          (propname <> nil);
          until not Ctxt.Valid;
          break;
        end;
      end;
      if Ctxt.Valid and
         (Ctxt.EndOfObject = ',') and
         ((rcfReadIgnoreUnknownFields in root.Flags) or
          (jpoIgnoreUnknownProperty in Ctxt.Options)) then
        goto any;
      Ctxt.ParseEndOfObject; // mimics GetJsonField() - set Ctxt.EndOfObject
      Ctxt.Info := root; // restore
    end;
    if rcfSynPersistentHook in Ctxt.Info.Flags then
      TSPHook(Data).RttiAfterReadObject;
  end;
end;

procedure _JL_TObjectList(Data: PObjectList; var Ctxt: TJsonParserContext);
var
  root: TRttiCustom;
  item: TObject;
begin
  if Data^ = nil then
  begin
    Ctxt.Valid := Ctxt.ParseNull;
    exit;
  end;
  Data^.Clear;
  if Ctxt.ParseNull or
     not Ctxt.ParseArray then
    exit;
  root := Ctxt.Info;
  Ctxt.Info := Ctxt.ObjectListItem;
  repeat
    item := Ctxt.ParseNewObject;
    if item = nil then
      break;
    Data^.Add(item);
  until Ctxt.EndOfObject = ']';
  Ctxt.Info := root;
  Ctxt.ParseEndOfObject;
end;

procedure _JL_TCollection(Data: PCollection; var Ctxt: TJsonParserContext);
var
  root: TRttiJson;
  load: TRttiJsonLoad;
  item: TCollectionItem;
begin
  if Data^ = nil then
  begin
    Ctxt.Valid := Ctxt.ParseNull;
    exit;
  end;
  Data^.BeginUpdate;
  try
    Data^.Clear;
    if Ctxt.ParseNull or
       not Ctxt.ParseArray then
      exit;
    root := TRttiJson(Ctxt.Info);
    load := nil;
    repeat
      item := Data^.Add;
      if not Assigned(load) then
      begin
        if root.fCollectionItemRtti = nil then
        begin
          // RegisterCollection() was not called -> compute after Data^.Add
          root.fCollectionItem := PPointer(item)^;
          root.fCollectionItemRtti := Rtti.RegisterClass(PClass(item)^);
        end;
        Ctxt.Info := root.fCollectionItemRtti;
        load := Ctxt.Info.JsonLoad;
      end;
      load(@item, Ctxt);
    until (not Ctxt.Valid) or
          (Ctxt.EndOfObject = ']');
    Ctxt.Info := root;
    Ctxt.ParseEndOfObject;
  finally
    Data^.EndUpdate;
  end;
end;

procedure _JL_TSynObjectList(Data: PSynObjectList; var Ctxt: TJsonParserContext);
var
  root: TRttiCustom;
  item: TObject;
begin
  if Data^ = nil then
  begin
    Ctxt.Valid := Ctxt.ParseNull;
    exit;
  end;
  Data^.Clear;
  if Ctxt.ParseNull or
     not Ctxt.ParseArray then
    exit;
  root := Ctxt.Info;
  Ctxt.Info := Ctxt.ObjectListItem;
  repeat
    item := Ctxt.ParseNewObject;
    if item = nil then
      break;
    Data^.Add(item);
  until Ctxt.EndOfObject = ']';
  Ctxt.Info := root;
  Ctxt.ParseEndOfObject;
end;

procedure _JL_TStrings(Data: PStrings; var Ctxt: TJsonParserContext);
var
  item: string;
begin
  if Data^ = nil then
  begin
    Ctxt.Valid := Ctxt.ParseNull;
    exit;
  end;
  Data^.BeginUpdate;
  try
    Data^.Clear;
    if Ctxt.ParseNull or
       not Ctxt.ParseArray then
      exit;
    repeat
      if Ctxt.ParseNext then
      begin
        Utf8DecodeToString(Ctxt.Value, Ctxt.ValueLen, item);
        Data^.Add(item);
      end;
    until (not Ctxt.Valid) or
          (Ctxt.EndOfObject = ']');
  finally
    Data^.EndUpdate;
  end;
  Ctxt.ParseEndOfObject;
end;

procedure _JL_TRawUtf8List(Data: PRawUtf8List; var Ctxt: TJsonParserContext);
var
  item: RawUtf8;
begin
  if Data^ = nil then
  begin
    Ctxt.Valid := Ctxt.ParseNull;
    exit;
  end;
  Data^.BeginUpdate;
  try
    Data^.Clear;
    if Ctxt.ParseNull or
       not Ctxt.ParseArray then
      exit;
    repeat
      if Ctxt.ParseNext then
      begin
        FastSetString(item, Ctxt.Value, Ctxt.ValueLen);
        Data^.AddObject(item, nil);
      end;
    until (not Ctxt.Valid) or
          (Ctxt.EndOfObject = ']');
  finally
    Data^.EndUpdate;
  end;
  Ctxt.ParseEndOfObject;
end;

var
  /// use pointer to allow any kind of Data^ type in above functions
  // - typecast to TRttiJsonSave for proper function call
  // - rkRecord and rkClass are set in TRttiJson.SetParserType
  PT_JSONLOAD: array[TRttiParserType] of pointer = (
    nil, @_JL_Array, @_JL_Boolean, @_JL_Byte, @_JL_Cardinal, @_JL_Currency,
    @_JL_Double, @_JL_Extended, @_JL_Int64, @_JL_Integer, @_JL_QWord,
    @_JL_RawByteString, @_JL_RawJson, @_JL_RawUtf8, nil,
    @_JL_Single, @_JL_String, @_JL_SynUnicode, @_JL_DateTime, @_JL_DateTime,
    @_JL_GUID, @_JL_Hash, @_JL_Hash, @_JL_Hash, @_JL_Int64, @_JL_TimeLog,
    @_JL_UnicodeString, @_JL_UnixTime, @_JL_UnixMSTime, @_JL_Variant,
    @_JL_WideString, @_JL_WinAnsi, @_JL_Word, @_JL_Enumeration, @_JL_Set,
    nil, @_JL_DynArray, @_JL_Interface, nil);


{ ************ JSON-aware TSynNameValue TSynPersistentStoreJson TRawByteStringGroup }

{ TSynNameValue }

procedure TSynNameValue.Add(const aName, aValue: RawUtf8; aTag: PtrInt);
var
  added: boolean;
  i: integer;
begin
  i := DynArray.FindHashedForAdding(aName, added);
  with List[i] do
  begin
    if added then
      Name := aName;
    Value := aValue;
    Tag := aTag;
  end;
  if Assigned(fOnAdd) then
    fOnAdd(List[i], i);
end;

procedure TSynNameValue.InitFromIniSection(Section: PUtf8Char;
  const OnTheFlyConvert: TOnSynNameValueConvertRawUtf8;
  const OnAdd: TOnSynNameValueNotify);
var
  s: RawUtf8;
  i: integer;
begin
  Init(false);
  fOnAdd := OnAdd;
  while (Section <> nil) and
        (Section^ <> '[') do
  begin
    s := GetNextLine(Section, Section);
    i := PosExChar('=', s);
    if (i > 1) and
       not (s[1] in [';', '[']) then
      if Assigned(OnTheFlyConvert) then
        Add(copy(s, 1, i - 1), OnTheFlyConvert(copy(s, i + 1, 1000)))
      else
        Add(copy(s, 1, i - 1), copy(s, i + 1, 1000));
  end;
end;

procedure TSynNameValue.InitFromCsv(Csv: PUtf8Char; NameValueSep, ItemSep: AnsiChar);
var
  n, v: RawUtf8;
begin
  Init(false);
  while Csv <> nil do
  begin
    GetNextItem(Csv, NameValueSep, n);
    if ItemSep = #10 then
      GetNextItemTrimedCRLF(Csv, v)
    else
      GetNextItem(Csv, ItemSep, v);
    if n = '' then
      break;
    Add(n, v);
  end;
end;

procedure TSynNameValue.InitFromNamesValues(const Names, Values: array of RawUtf8);
var
  i: integer;
begin
  Init(false);
  if high(Names) <> high(Values) then
    exit;
  DynArray.Capacity := length(Names);
  for i := 0 to high(Names) do
    Add(Names[i], Values[i]);
end;

function TSynNameValue.InitFromJson(Json: PUtf8Char; aCaseSensitive: boolean): boolean;
var
  N, V: PUtf8Char;
  nam, val: RawUtf8;
  Nlen, Vlen, c: integer;
  EndOfObject: AnsiChar;
begin
  result := false;
  Init(aCaseSensitive);
  if Json = nil then
    exit;
  while (Json^ <= ' ') and
        (Json^ <> #0) do
    inc(Json);
  if Json^ <> '{' then
    exit;
  repeat
    inc(Json)
  until (Json^ = #0) or
        (Json^ > ' ');
  c := JsonObjectPropCount(Json);
  if c <= 0 then
    exit;
  DynArray.Capacity := c;
  repeat
    N := GetJsonPropName(Json, @Nlen);
    if N = nil then
      exit;
    V := GetJsonFieldOrObjectOrArray(Json, nil, @EndOfObject, true, true, @Vlen);
    if Json = nil then
      exit;
    FastSetString(nam, N, Nlen);
    FastSetString(val, V, Vlen);
    Add(nam, val);
  until EndOfObject = '}';
  result := true;
end;

procedure TSynNameValue.Init(aCaseSensitive: boolean);
begin
  // release dynamic arrays memory before FillcharFast()
  List := nil;
  DynArray.Hasher.Clear;
  // initialize hashed storage
  FillCharFast(self, SizeOf(self), 0);
  DynArray.InitSpecific(TypeInfo(TSynNameValueItemDynArray), List,
    ptRawUtf8, @Count, not aCaseSensitive);
end;

function TSynNameValue.Find(const aName: RawUtf8): integer;
begin
  result := DynArray.FindHashed(aName);
end;

function TSynNameValue.FindStart(const aUpperName: RawUtf8): PtrInt;
begin
  for result := 0 to Count - 1 do
    if IdemPChar(pointer(List[result].Name), pointer(aUpperName)) then
      exit;
  result := -1;
end;

function TSynNameValue.FindByValue(const aValue: RawUtf8): PtrInt;
begin
  for result := 0 to Count - 1 do
    if List[result].Value = aValue then
      exit;
  result := -1;
end;

function TSynNameValue.Delete(const aName: RawUtf8): boolean;
begin
  result := DynArray.FindHashedAndDelete(aName) >= 0;
end;

function TSynNameValue.DeleteByValue(const aValue: RawUtf8; Limit: integer): integer;
var
  ndx: PtrInt;
begin
  result := 0;
  if Limit < 1 then
    exit;
  for ndx := Count - 1 downto 0 do
    if List[ndx].Value = aValue then
    begin
      DynArray.Delete(ndx);
      inc(result);
      if result >= Limit then
        break;
    end;
  if result > 0 then
    DynArray.ReHash;
end;

function TSynNameValue.Value(const aName: RawUtf8; const aDefaultValue: RawUtf8): RawUtf8;
var
  i: integer;
begin
  if @self = nil then
    i := -1
  else
    i := DynArray.FindHashed(aName);
  if i < 0 then
    result := aDefaultValue
  else
    result := List[i].Value;
end;

function TSynNameValue.ValueInt(const aName: RawUtf8; const aDefaultValue: Int64): Int64;
var
  i, err: integer;
begin
  i := DynArray.FindHashed(aName);
  if i < 0 then
    result := aDefaultValue
  else
  begin
    result := GetInt64(pointer(List[i].Value), err);
    if err <> 0 then
      result := aDefaultValue;
  end;
end;

function TSynNameValue.ValueBool(const aName: RawUtf8): boolean;
begin
  result := Value(aName) = '1';
end;

function TSynNameValue.ValueEnum(const aName: RawUtf8; aEnumTypeInfo: PRttiInfo;
  out aEnum; aEnumDefault: PtrUInt): boolean;
var
  rtti: PRttiEnumType;
  v: RawUtf8;
  err: integer;
  i: PtrInt;
begin
  result := false;
  rtti := aEnumTypeInfo.EnumBaseType;
  if rtti = nil then
    exit;
  ToRttiOrd(rtti.RttiOrd, @aEnum, aEnumDefault); // always set the default value
  v := TrimU(Value(aName, ''));
  if v = '' then
    exit;
  i := GetInteger(pointer(v), err);
  if (err <> 0) or
     (PtrUInt(i) > PtrUInt(rtti.MaxValue)) then
    i := rtti.GetEnumNameValue(pointer(v), length(v), {alsotrimleft=}true);
  if i >= 0 then
  begin
    ToRttiOrd(rtti.RttiOrd, @aEnum, i); // we found a proper value
    result := true;
  end;
end;

function TSynNameValue.Initialized: boolean;
begin
  result := DynArray.Value = @List;
end;

function TSynNameValue.GetBlobData: RawByteString;
begin
  result := DynArray.SaveTo;
end;

procedure TSynNameValue.SetBlobDataPtr(aValue: pointer);
begin
  DynArray.LoadFrom(aValue);
  DynArray.ReHash;
end;

procedure TSynNameValue.SetBlobData(const aValue: RawByteString);
begin
  DynArray.LoadFromBinary(aValue);
  DynArray.ReHash;
end;

function TSynNameValue.GetStr(const aName: RawUtf8): RawUtf8;
begin
  result := Value(aName, '');
end;

function TSynNameValue.GetInt(const aName: RawUtf8): Int64;
begin
  result := ValueInt(aName, 0);
end;

function TSynNameValue.GetBool(const aName: RawUtf8): boolean;
begin
  result := Value(aName) = '1';
end;

function TSynNameValue.AsCsv(const KeySeparator, ValueSeparator, IgnoreKey: RawUtf8): RawUtf8;
var
  i: PtrInt;
  temp: TTextWriterStackBuffer;
begin
  with TBaseWriter.CreateOwnedStream(temp) do
  try
    for i := 0 to Count - 1 do
      if (IgnoreKey = '') or
         (List[i].Name <> IgnoreKey) then
      begin
        AddNoJsonEscapeUtf8(List[i].Name);
        AddNoJsonEscapeUtf8(KeySeparator);
        AddNoJsonEscapeUtf8(List[i].Value);
        AddNoJsonEscapeUtf8(ValueSeparator);
      end;
    SetText(result);
  finally
    Free;
  end;
end;

function TSynNameValue.AsJson: RawUtf8;
var
  i: PtrInt;
  temp: TTextWriterStackBuffer;
begin
  with TTextWriter.CreateOwnedStream(temp) do
  try
    Add('{');
    for i := 0 to Count - 1 do
      with List[i] do
      begin
        AddProp(pointer(Name), length(Name));
        Add('"');
        AddJsonEscape(pointer(Value));
        Add('"', ',');
      end;
    CancelLastComma;
    Add('}');
    SetText(result);
  finally
    Free;
  end;
end;

procedure TSynNameValue.AsNameValues(out Names, Values: TRawUtf8DynArray);
var
  i: PtrInt;
begin
  SetLength(Names, Count);
  SetLength(Values, Count);
  for i := 0 to Count - 1 do
  begin
    Names[i] := List[i].Name;
    Values[i] := List[i].Value;
  end;
end;

function TSynNameValue.ValueVariantOrNull(const aName: RawUtf8): variant;
var
  i: PtrInt;
begin
  i := Find(aName);
  if i < 0 then
    SetVariantNull(result{%H-})
  else
    RawUtf8ToVariant(List[i].Value, result);
end;

procedure TSynNameValue.AsDocVariant(out DocVariant: variant;
  ExtendedJson, ValueAsString, AllowVarDouble: boolean);
var
  ndx: PtrInt;
  dv: TDocVariantData absolute DocVariant;
begin
  if Count > 0 then
    begin
      dv.Init(JSON_OPTIONS_NAMEVALUE[ExtendedJson], dvObject);
      dv.SetCount(Count);
      dv.Capacity := Count;
      for ndx := 0 to Count - 1 do
      begin
        dv.Names[ndx] := List[ndx].Name;
        if ValueAsString or
           not GetNumericVariantFromJson(pointer(List[ndx].Value),
             TVarData(dv.Values[ndx]), AllowVarDouble) then
          RawUtf8ToVariant(List[ndx].Value, dv.Values[ndx]);
      end;
    end
  else
    TVarData(DocVariant).VType := varNull;
end;

function TSynNameValue.AsDocVariant(ExtendedJson, ValueAsString: boolean): variant;
begin
  AsDocVariant(result, ExtendedJson, ValueAsString);
end;

function TSynNameValue.MergeDocVariant(var DocVariant: variant;
  ValueAsString: boolean; ChangedProps: PVariant; ExtendedJson,
  AllowVarDouble: boolean): integer;
var
  dv: TDocVariantData absolute DocVariant;
  i, ndx: PtrInt;
  v: variant;
  intvalues: TRawUtf8Interning;
begin
  if dv.VarType <> DocVariantVType then
    TDocVariant.New(DocVariant, JSON_OPTIONS_NAMEVALUE[ExtendedJson]);
  if ChangedProps <> nil then
    TDocVariant.New(ChangedProps^, dv.Options);
  if dvoInternValues in dv.Options then
    intvalues := DocVariantType.InternValues
  else
    intvalues := nil;
  result := 0; // returns number of changed values
  for i := 0 to Count - 1 do
    if List[i].Name <> '' then
    begin
      VarClear(v{%H-});
      if ValueAsString or
         not GetNumericVariantFromJson(pointer(List[i].Value),
           TVarData(v), AllowVarDouble) then
        RawUtf8ToVariant(List[i].Value, v);
      ndx := dv.GetValueIndex(List[i].Name);
      if ndx < 0 then
        ndx := dv.InternalAdd(List[i].Name)
      else if SortDynArrayVariantComp(TVarData(v), TVarData(dv.Values[ndx]), false) = 0 then
        continue; // value not changed -> skip
      if ChangedProps <> nil then
        PDocVariantData(ChangedProps)^.AddValue(List[i].Name, v);
      SetVariantByValue(v, dv.Values[ndx]);
      if intvalues <> nil then
        intvalues.UniqueVariant(dv.Values[ndx]);
      inc(result);
    end;
end;



{ TSynPersistentStoreJson }

procedure TSynPersistentStoreJson.AddJson(W: TTextWriter);
begin
  W.AddPropJsonString('name', fName);
end;

function TSynPersistentStoreJson.SaveToJson(reformat: TTextWriterJsonFormat): RawUtf8;
var
  W: TTextWriter;
begin
  W := TTextWriter.CreateOwnedStream(65536);
  try
    W.Add('{');
    AddJson(W);
    W.CancelLastComma;
    W.Add('}');
    W.SetText(result, reformat);
  finally
    W.Free;
  end;
end;


{ TRawByteStringGroup }

procedure TRawByteStringGroup.Add(const aItem: RawByteString);
begin
  if Values = nil then
    Clear; // ensure all fields are initialized, even if on stack
  if Count = Length(Values) then
    SetLength(Values, NextGrow(Count));
  with Values[Count] do
  begin
    Position := self.Position;
    Value := aItem;
  end;
  LastFind := Count;
  inc(Count);
  inc(Position, Length(aItem));
end;

procedure TRawByteStringGroup.Add(aItem: pointer; aItemLen: integer);
var
  tmp: RawByteString;
begin
  SetString(tmp, PAnsiChar(aItem), aItemLen);
  Add(tmp);
end;

procedure TRawByteStringGroup.Add(const aAnother: TRawByteStringGroup);
var
  i: integer;
  s, d: PRawByteStringGroupValue;
begin
  if aAnother.Values = nil then
    exit;
  if Values = nil then
    Clear; // ensure all fields are initialized, even if on stack
  if Count + aAnother.Count > Length(Values) then
    SetLength(Values, Count + aAnother.Count);
  s := pointer(aAnother.Values);
  d := @Values[Count];
  for i := 1 to aAnother.Count do
  begin
    d^.Position := Position;
    d^.Value := s^.Value;
    inc(Position, length(s^.Value));
    inc(s);
    inc(d);
  end;
  inc(Count, aAnother.Count);
  LastFind := Count - 1;
end;

procedure TRawByteStringGroup.RemoveLastAdd;
begin
  if Count > 0 then
  begin
    dec(Count);
    dec(Position, Length(Values[Count].Value));
    Values[Count].Value := ''; // release memory
    LastFind := Count - 1;
  end;
end;

function TRawByteStringGroup.Equals(const aAnother: TRawByteStringGroup): boolean;
begin
  if ((Values = nil) and
      (aAnother.Values <> nil)) or
     ((Values <> nil) and
      (aAnother.Values = nil)) or
     (Position <> aAnother.Position) then
    result := false
  else if (Count <> 1) or
          (aAnother.Count <> 1) or
          (Values[0].Value <> aAnother.Values[0].Value) then
    result := AsText = aAnother.AsText
  else
    result := true;
end;

procedure TRawByteStringGroup.Clear;
begin
  Values := nil;
  Position := 0;
  Count := 0;
  LastFind := 0;
end;

procedure TRawByteStringGroup.AppendTextAndClear(var aDest: RawByteString);
var
  d, i: integer;
  v: PRawByteStringGroupValue;
begin
  d := length(aDest);
  SetLength(aDest, d + Position);
  v := pointer(Values);
  for i := 1 to Count do
  begin
    MoveFast(pointer(v^.Value)^, PByteArray(aDest)[d + v^.Position], length(v^.Value));
    inc(v);
  end;
  Clear;
end;

function TRawByteStringGroup.AsText: RawByteString;
begin
  if Values = nil then
    result := ''
  else
  begin
    if Count > 1 then
      Compact;
    result := Values[0].Value;
  end;
end;

procedure TRawByteStringGroup.Compact;
var
  i: integer;
  v: PRawByteStringGroupValue;
  tmp: RawByteString;
begin
  if (Values <> nil) and
     (Count > 1) then
  begin
    SetString(tmp, nil, Position);
    v := pointer(Values);
    for i := 1 to Count do
    begin
      MoveFast(pointer(v^.Value)^, PByteArray(tmp)[v^.Position], length(v^.Value));
      {$ifdef FPC}
      FastAssignNew(v^.Value);
      {$else}
      v^.Value := '';
      {$endif FPC}
      inc(v);
    end;
    Values[0].Value := tmp; // use result for absolute compaction ;)
    if Count > 128 then
      SetLength(Values, 128);
    Count := 1;
    LastFind := 0;
  end;
end;

function TRawByteStringGroup.AsBytes: TByteDynArray;
var
  i: integer;
begin
  result := nil;
  if Values = nil then
    exit;
  SetLength(result, Position);
  for i := 0 to Count - 1 do
    with Values[i] do
      MoveFast(pointer(Value)^, PByteArray(result)[Position], length(Value));
end;

procedure TRawByteStringGroup.Write(W: TTextWriter; Escape: TTextWriterKind);
var
  i: integer;
begin
  if Values <> nil then
    for i := 0 to Count - 1 do
      with Values[i] do
        W.Add(PUtf8Char(pointer(Value)), length(Value), Escape);
end;

procedure TRawByteStringGroup.WriteBinary(W: TBufferWriter);
var
  i: integer;
begin
  if Values <> nil then
    for i := 0 to Count - 1 do
      W.WriteBinary(Values[i].Value);
end;

procedure TRawByteStringGroup.WriteString(W: TBufferWriter);
begin
  if Values = nil then
  begin
    W.Write1(0);
    exit;
  end;
  W.WriteVarUInt32(Position);
  WriteBinary(W);
end;

procedure TRawByteStringGroup.AddFromReader(var aReader: TFastReader);
var
  complexsize: integer;
begin
  complexsize := aReader.VarUInt32;
  if complexsize > 0 then
    // directly create a RawByteString from aReader buffer
    Add(aReader.Next(complexsize), complexsize);
end;

function TRawByteStringGroup.Find(aPosition: integer): PRawByteStringGroupValue;
var
  i: integer;
begin
  if (pointer(Values) <> nil) and
     (cardinal(aPosition) < cardinal(Position)) then
  begin
    result := @Values[LastFind]; // this cache is very efficient in practice
    if (aPosition >= result^.Position) and
       (aPosition < result^.Position + length(result^.Value)) then
      exit;
    result := @Values[1]; // seldom O(n) brute force search (in CPU L1 cache)
    for i := 0 to Count - 2 do
      if result^.Position > aPosition then
      begin
        dec(result);
        LastFind := i;
        exit;
      end
      else
        inc(result);
    dec(result);
    LastFind := Count - 1;
  end
  else
    result := nil;
end;

function TRawByteStringGroup.Find(aPosition, aLength: integer): pointer;
var
  P: PRawByteStringGroupValue;
  i: integer;
label
  found;
begin
  if (pointer(Values) <> nil) and
     (cardinal(aPosition) < cardinal(Position)) then
  begin
    P := @Values[LastFind]; // this cache is very efficient in practice
    i := aPosition - P^.Position;
    if (i >= 0) and
       (i + aLength < length(P^.Value)) then
    begin
      result := @PByteArray(P^.Value)[i];
      exit;
    end;
    P := @Values[1]; // seldom O(n) brute force search (in CPU L1 cache)
    for i := 0 to Count - 2 do
      if P^.Position > aPosition then
      begin
        LastFind := i;
found:  dec(P);
        dec(aPosition, P^.Position);
        if aLength - aPosition <= length(P^.Value) then
          result := @PByteArray(P^.Value)[aPosition]
        else
          result := nil;
        exit;
      end
      else
        inc(P);
    LastFind := Count - 1;
    goto found;
  end
  else
    result := nil;
end;

procedure TRawByteStringGroup.FindAsText(aPosition, aLength: integer;
  out aText: RawByteString);
var
  P: PRawByteStringGroupValue;
begin
  P := Find(aPosition);
  if P = nil then
    exit;
  dec(aPosition, P^.Position);
  if (aPosition = 0) and
     (length(P^.Value) = aLength) then
    aText := P^.Value
  else
  // direct return if not yet compacted
  if aLength - aPosition <= length(P^.Value) then
    SetString(aText, PAnsiChar(@PByteArray(P^.Value)[aPosition]), aLength);
end;

function TRawByteStringGroup.FindAsText(aPosition, aLength: integer): RawByteString;
begin
  FindAsText(aPosition, aLength, result);
end;

procedure TRawByteStringGroup.FindAsVariant(aPosition, aLength: integer;
  out aDest: variant);
var
  tmp: RawByteString;
begin
  tmp := FindAsText(aPosition, aLength);
  if tmp <> '' then
    RawUtf8ToVariant(tmp, aDest);
end;

procedure TRawByteStringGroup.FindWrite(aPosition, aLength: integer;
  W: TTextWriter; Escape: TTextWriterKind; TrailingCharsToIgnore: integer);
var
  P: pointer;
begin
  P := Find(aPosition, aLength);
  if P <> nil then
    W.Add(PUtf8Char(P) + TrailingCharsToIgnore, aLength - TrailingCharsToIgnore, Escape);
end;

procedure TRawByteStringGroup.FindWriteBase64(aPosition, aLength: integer;
  W: TTextWriter; withMagic: boolean);
var
  P: pointer;
begin
  P := Find(aPosition, aLength);
  if P <> nil then
    W.WrBase64(P, aLength, withMagic);
end;

procedure TRawByteStringGroup.FindMove(aPosition, aLength: integer;
  aDest: pointer);
var
  P: pointer;
begin
  P := Find(aPosition, aLength);
  if P <> nil then
    MoveFast(P^, aDest^, aLength);
end;


{ TSynCache }

constructor TSynCache.Create(aMaxCacheRamUsed: cardinal;
  aCaseSensitive: boolean; aTimeoutSeconds: cardinal);
begin
  inherited Create;
  fNameValue.Init(aCaseSensitive);
  fMaxRamUsed := aMaxCacheRamUsed;
  fTimeoutSeconds := aTimeoutSeconds;
end;

procedure TSynCache.ResetIfNeeded;
var
  tix: cardinal;
begin
  if fRamUsed > fMaxRamUsed then
    Reset;
  if fTimeoutSeconds > 0 then
  begin
    tix := GetTickCount64 shr 10;
    if fTimeoutTix > tix then
      Reset;
    fTimeoutTix := tix + fTimeoutSeconds;
  end;
end;

procedure TSynCache.Add(const aValue: RawUtf8; aTag: PtrInt);
begin
  if (self = nil) or
     (fFindLastKey = '') then
    exit;
  ResetIfNeeded;
  inc(fRamUsed, length(aValue));
  fNameValue.Add(fFindLastKey, aValue, aTag);
  fFindLastKey := '';
end;

function TSynCache.Find(const aKey: RawUtf8; aResultTag: PPtrInt): RawUtf8;
var
  ndx: integer;
begin
  result := '';
  if self = nil then
    exit;
  fFindLastKey := aKey;
  if aKey = '' then
    exit;
  ndx := fNameValue.Find(aKey);
  if ndx < 0 then
    exit;
  with fNameValue.List[ndx] do
  begin
    result := Value;
    if aResultTag <> nil then
      aResultTag^ := Tag;
  end;
end;

function TSynCache.AddOrUpdate(const aKey, aValue: RawUtf8; aTag: PtrInt): boolean;
var
  ndx: integer;
begin
  result := false;
  if self = nil then
    exit; // avoid GPF
  fSafe.Lock;
  try
    ResetIfNeeded;
    ndx := fNameValue.DynArray.FindHashedForAdding(aKey, result);
    with fNameValue.List[ndx] do
    begin
      Name := aKey;
      dec(fRamUsed, length(Value));
      Value := aValue;
      inc(fRamUsed, length(Value));
      Tag := aTag;
    end;
  finally
    fSafe.Unlock;
  end;
end;

function TSynCache.Reset: boolean;
begin
  result := false;
  if self = nil then
    exit; // avoid GPF
  fSafe.Lock;
  try
    if Count <> 0 then
    begin
      fNameValue.DynArray.Clear;
      fNameValue.DynArray.ReHash;
      result := true; // mark something was flushed
    end;
    fRamUsed := 0;
    fTimeoutTix := 0;
  finally
    fSafe.Unlock;
  end;
end;

function TSynCache.Count: integer;
begin
  if self = nil then
  begin
    result := 0;
    exit;
  end;
  fSafe.Lock;
  try
    result := fNameValue.Count;
  finally
    fSafe.Unlock;
  end;
end;


{ *********** JSON-aware TSynDictionary Storage }

{ TSynDictionary }

const
  DIC_KEYCOUNT = 0;
  DIC_KEY = 1;
  DIC_VALUECOUNT = 2;
  DIC_VALUE = 3;
  DIC_TIMECOUNT = 4;
  DIC_TIMESEC = 5;
  DIC_TIMETIX = 6;

function TSynDictionary.KeyFullHash(const Elem): cardinal;
begin
  result := fKeys.Hasher.Hasher(0, @Elem, fKeys.Info.Cache.ItemSize);
end;

function TSynDictionary.KeyFullCompare(const A, B): integer;
var
  i: PtrInt;
begin
  for i := 0 to fKeys.Info.Cache.ItemSize - 1 do
  begin
    result := TByteArray(A)[i] - TByteArray(B)[i];
    if result <> 0 then
      exit;
  end;
  result := 0;
end;

constructor TSynDictionary.Create(aKeyTypeInfo, aValueTypeInfo: PRttiInfo;
  aKeyCaseInsensitive: boolean; aTimeoutSeconds: cardinal; aCompressAlgo: TAlgoCompress);
begin
  inherited Create;
  fSafe.Padding[DIC_KEYCOUNT].VType := varInteger;
  fSafe.Padding[DIC_KEY].VType := varUnknown;
  fSafe.Padding[DIC_VALUECOUNT].VType := varInteger;
  fSafe.Padding[DIC_VALUE].VType := varUnknown;
  fSafe.Padding[DIC_TIMECOUNT].VType := varInteger;
  fSafe.Padding[DIC_TIMESEC].VType := varInteger;
  fSafe.Padding[DIC_TIMETIX].VType := varInteger;
  fSafe.PaddingUsedCount := DIC_TIMETIX + 1;
  fKeys.Init(aKeyTypeInfo, fSafe.Padding[DIC_KEY].VAny, nil, nil, nil,
    @fSafe.Padding[DIC_KEYCOUNT].VInteger, aKeyCaseInsensitive);
  if not Assigned(fKeys.HashItem) then
    fKeys.EventHash := KeyFullHash;
  if not Assigned(fKeys.{$ifdef UNDIRECTDYNARRAY}InternalDynArray.{$endif}Compare) then
    fKeys.EventCompare := KeyFullCompare;
  fValues.Init(aValueTypeInfo, fSafe.Padding[DIC_VALUE].VAny,
    @fSafe.Padding[DIC_VALUECOUNT].VInteger);
  fTimeouts.Init(TypeInfo(TIntegerDynArray), fTimeOut,
    @fSafe.Padding[DIC_TIMECOUNT].VInteger);
  if aCompressAlgo = nil then
    aCompressAlgo := AlgoSynLZ;
  fCompressAlgo := aCompressAlgo;
  fSafe.Padding[DIC_TIMESEC].VInteger := aTimeoutSeconds;
end;

function TSynDictionary.ComputeNextTimeOut: cardinal;
begin
  result := fSafe.Padding[DIC_TIMESEC].VInteger;
  if result <> 0 then
    result := cardinal(GetTickCount64 shr 10) + result;
end;

function TSynDictionary.GetCapacity: integer;
begin
  fSafe.Lock;
  result := fKeys.Capacity;
  fSafe.UnLock;
end;

procedure TSynDictionary.SetCapacity(const Value: integer);
begin
  fSafe.Lock;
  fKeys.Capacity := Value;
  fValues.Capacity := Value;
  if fSafe.Padding[DIC_TIMESEC].VInteger > 0 then
    fTimeOuts.Capacity := Value;
  fSafe.UnLock;
end;

function TSynDictionary.GetTimeOutSeconds: cardinal;
begin
  result := fSafe.Padding[DIC_TIMESEC].VInteger;
end;

procedure TSynDictionary.SetTimeOutSeconds(Value: cardinal);
begin
  fSafe.Lock;
  try
    DeleteAll;
    fSafe.Padding[DIC_TIMESEC].VInteger := Value;
  finally
    fSafe.UnLock;
  end;
end;

procedure TSynDictionary.SetTimeouts;
var
  i: PtrInt;
  timeout: cardinal;
begin
  if fSafe.Padding[DIC_TIMESEC].VInteger = 0 then
    exit;
  fTimeOuts.Count := fSafe.Padding[DIC_KEYCOUNT].VInteger;
  timeout := ComputeNextTimeOut;
  for i := 0 to fSafe.Padding[DIC_TIMECOUNT].VInteger - 1 do
    fTimeOut[i] := timeout;
end;

function TSynDictionary.DeleteDeprecated: integer;
var
  i: PtrInt;
  now: cardinal;
begin
  result := 0;
  if (self = nil) or
     (fSafe.Padding[DIC_TIMECOUNT].VInteger = 0) or // no entry
     (fSafe.Padding[DIC_TIMESEC].VInteger = 0) then // nothing in fTimeOut[]
    exit;
  now := GetTickCount64 shr 10;
  if fSafe.Padding[DIC_TIMETIX].VInteger = integer(now) then
    exit; // no need to search more often than every second
  fSafe.Lock;
  try
    fSafe.Padding[DIC_TIMETIX].VInteger := now;
    for i := fSafe.Padding[DIC_TIMECOUNT].VInteger - 1 downto 0 do
      if (now > fTimeOut[i]) and
         (fTimeOut[i] <> 0) and
         (not Assigned(fOnCanDelete) or
          fOnCanDelete(fKeys.ItemPtr(i)^, fValues.ItemPtr(i)^, i)) then
      begin
        fKeys.Delete(i);
        fValues.Delete(i);
        fTimeOuts.Delete(i);
        inc(result);
      end;
    if result > 0 then
      fKeys.Rehash; // mandatory after fKeys.Delete(i)
  finally
    fSafe.UnLock;
  end;
end;

procedure TSynDictionary.DeleteAll;
begin
  if self = nil then
    exit;
  fSafe.Lock;
  try
    fKeys.Clear;
    fKeys.Hasher.Clear; // mandatory to avoid GPF
    fValues.Clear;
    if fSafe.Padding[DIC_TIMESEC].VInteger > 0 then
      fTimeOuts.Clear;
  finally
    fSafe.UnLock;
  end;
end;

destructor TSynDictionary.Destroy;
begin
  fKeys.Clear;
  fValues.Clear;
  inherited Destroy;
end;

function TSynDictionary.Add(const aKey, aValue): integer;
var
  added: boolean;
  tim: cardinal;
begin
  tim := ComputeNextTimeOut;
  fSafe.Lock;
  try
    result := fKeys.FindHashedForAdding(aKey, added);
    if added then
    begin
      fKeys{$ifdef UNDIRECTDYNARRAY}.InternalDynArray{$endif}.
        ItemCopyFrom(@aKey, result); // fKey[result] := aKey;
      if fValues.Add(aValue) <> result then
        raise ESynDictionary.CreateUtf8('%.Add fValues.Add', [self]);
      if tim > 0 then
        fTimeOuts.Add(tim);
    end
    else
      result := -1;
  finally
    fSafe.UnLock;
  end;
end;

function TSynDictionary.AddOrUpdate(const aKey, aValue): integer;
var
  added: boolean;
  tim: cardinal;
begin
  tim := ComputeNextTimeOut;
  fSafe.Lock;
  try
    result := fKeys.FindHashedForAdding(aKey, added);
    if added then
    begin
      fKeys{$ifdef UNDIRECTDYNARRAY}.InternalDynArray{$endif}.
        ItemCopyFrom(@aKey, result); // fKey[result] := aKey
      if fValues.Add(aValue) <> result then
        raise ESynDictionary.CreateUtf8('%.AddOrUpdate fValues.Add', [self]);
      if tim <> 0 then
        fTimeOuts.Add(tim);
    end
    else
    begin
      fValues.ItemCopyFrom(@aValue, result, {ClearBeforeCopy=}true);
      if tim <> 0 then
        fTimeOut[result] := tim;
    end;
  finally
    fSafe.UnLock;
  end;
end;

function TSynDictionary.Clear(const aKey): integer;
begin
  fSafe.Lock;
  try
    result := fKeys.FindHashed(aKey);
    if result >= 0 then
    begin
      fValues.ItemClear(fValues.ItemPtr(result));
      if fSafe.Padding[DIC_TIMESEC].VInteger > 0 then
        fTimeOut[result] := 0;
    end;
  finally
    fSafe.UnLock;
  end;
end;

function TSynDictionary.Delete(const aKey): integer;
begin
  fSafe.Lock;
  try
    result := fKeys.FindHashedAndDelete(aKey);
    if result >= 0 then
    begin
      fValues.Delete(result);
      if fSafe.Padding[DIC_TIMESEC].VInteger > 0 then
        fTimeOuts.Delete(result);
    end;
  finally
    fSafe.UnLock;
  end;
end;

function TSynDictionary.DeleteAt(aIndex: integer): boolean;
begin
  if cardinal(aIndex) < cardinal(fSafe.Padding[DIC_KEYCOUNT].VInteger) then
    // use Delete(aKey) to have efficient hash table update
    result := Delete(fKeys.ItemPtr(aIndex)^) = aIndex
  else
    result := false;
end;

function TSynDictionary.InArray(const aKey, aArrayValue;
  aAction: TSynDictionaryInArray; aCompare: TDynArraySortCompare): boolean;
var
  nested: TDynArray;
  ndx: PtrInt;
  new: pointer;
begin
  result := false;
  if (fValues.Info.ArrayRtti = nil) or
     (fValues.Info.ArrayRtti.Kind <> rkDynArray) then
    raise ESynDictionary.CreateUtf8('%.Values: % items are not dynamic arrays',
      [self, fValues.Info.Name]);
  fSafe.Lock;
  try
    ndx := fKeys.FindHashed(aKey);
    if ndx < 0 then
      if aAction <> iaAddForced then
        exit
      else
      begin
        new := nil;
        ndx := Add(aKey, new);
      end;
    nested.InitRtti(fValues.Info.ArrayRtti, fValues.ItemPtr(ndx)^);
    nested.Compare := aCompare;
    case aAction of
      iaFind:
        result := nested.Find(aArrayValue) >= 0;
      iaFindAndDelete:
        result := nested.FindAndDelete(aArrayValue) >= 0;
      iaFindAndUpdate:
        result := nested.FindAndUpdate(aArrayValue) >= 0;
      iaFindAndAddIfNotExisting:
        result := nested.FindAndAddIfNotExisting(aArrayValue) >= 0;
      iaAdd, iaAddForced:
        result := nested.Add(aArrayValue) >= 0;
    end;
  finally
    fSafe.UnLock;
  end;
end;

function TSynDictionary.FindInArray(const aKey, aArrayValue;
  aCompare: TDynArraySortCompare): boolean;
begin
  result := InArray(aKey, aArrayValue, iaFind, aCompare);
end;

function TSynDictionary.FindKeyFromValue(const aValue;
  out aKey; aUpdateTimeOut: boolean): boolean;
var
  ndx: integer;
begin
  fSafe.Lock;
  try
    ndx := fValues.IndexOf(aValue); // use fast RTTI for value search
    result := ndx >= 0;
    if result then
    begin
      fKeys.ItemCopyAt(ndx, @aKey);
      if aUpdateTimeOut then
        SetTimeoutAtIndex(ndx);
    end;
  finally
    fSafe.UnLock;
  end;
end;

function TSynDictionary.DeleteInArray(const aKey, aArrayValue;
  aCompare: TDynArraySortCompare): boolean;
begin
  result := InArray(aKey, aArrayValue, iaFindAndDelete, aCompare);
end;

function TSynDictionary.UpdateInArray(const aKey, aArrayValue;
  aCompare: TDynArraySortCompare): boolean;
begin
  result := InArray(aKey, aArrayValue, iaFindAndUpdate, aCompare);
end;

function TSynDictionary.AddInArray(const aKey, aArrayValue;
  aCompare: TDynArraySortCompare): boolean;
begin
  result := InArray(aKey, aArrayValue, iaAdd, aCompare);
end;

function TSynDictionary.AddInArrayForced(const aKey, aArrayValue;
  aCompare: TDynArraySortCompare): boolean;
begin
  result := InArray(aKey, aArrayValue, iaAddForced, aCompare);
end;

function TSynDictionary.AddOnceInArray(const aKey, aArrayValue;
  aCompare: TDynArraySortCompare): boolean;
begin
  result := InArray(aKey, aArrayValue, iaFindAndAddIfNotExisting, aCompare);
end;

function TSynDictionary.Find(const aKey; aUpdateTimeOut: boolean): integer;
var
  tim: cardinal;
begin
  // caller is expected to call fSafe.Lock/Unlock
  if self = nil then
    result := -1
  else
    result := fKeys.FindHashed(aKey);
  if aUpdateTimeOut and
     (result >= 0) then
  begin
    tim := fSafe.Padding[DIC_TIMESEC].VInteger;
    if tim > 0 then // inlined fTimeout[result] := GetTimeout
      fTimeout[result] := cardinal(GetTickCount64 shr 10) + tim;
  end;
end;

function TSynDictionary.FindValue(const aKey; aUpdateTimeOut: boolean;
  aIndex: PInteger): pointer;
var
  ndx: PtrInt;
begin
  ndx := Find(aKey, aUpdateTimeOut);
  if aIndex <> nil then
    aIndex^ := ndx;
  if ndx < 0 then
    result := nil
  else
    result := PAnsiChar(fValues.Value^) + ndx * fValues.Info.Cache.ItemSize;
end;

function TSynDictionary.FindValueOrAdd(const aKey; var added: boolean;
  aIndex: PInteger): pointer;
var
  ndx: integer;
  tim: cardinal;
begin
  tim := fSafe.Padding[DIC_TIMESEC].VInteger; // inlined tim := GetTimeout
  if tim <> 0 then
    tim := cardinal(GetTickCount64 shr 10) + tim;
  ndx := fKeys.FindHashedForAdding(aKey, added);
  if added then
  begin
    fKeys{$ifdef UNDIRECTDYNARRAY}.InternalDynArray{$endif}.
      ItemCopyFrom(@aKey, ndx); // fKey[i] := aKey
    fValues.Count := ndx + 1; // reserve new place for associated value
    if tim > 0 then
      fTimeOuts.Add(tim);
  end
  else if tim > 0 then
    fTimeOut[ndx] := tim;
  if aIndex <> nil then
    aIndex^ := ndx;
  result := fValues.ItemPtr(ndx);
end;

function TSynDictionary.FindAndCopy(const aKey;
  out aValue; aUpdateTimeOut: boolean): boolean;
var
  ndx: integer;
begin
  fSafe.Lock;
  try
    ndx := Find(aKey, aUpdateTimeOut);
    if ndx >= 0 then
    begin
      fValues.ItemCopyAt(ndx, @aValue);
      result := true;
    end
    else
      result := false;
  finally
    fSafe.UnLock;
  end;
end;

function TSynDictionary.FindAndExtract(const aKey; out aValue): boolean;
var
  ndx: integer;
begin
  fSafe.Lock;
  try
    ndx := fKeys.FindHashedAndDelete(aKey);
    if ndx >= 0 then
    begin
      fValues.ItemMoveTo(ndx, @aValue); // faster than ItemCopyAt()
      fValues.Delete(ndx);
      if fSafe.Padding[DIC_TIMESEC].VInteger > 0 then
        fTimeOuts.Delete(ndx);
      result := true;
    end
    else
      result := false;
  finally
    fSafe.UnLock;
  end;
end;

function TSynDictionary.Exists(const aKey): boolean;
begin
  fSafe.Lock;
  try
    result := fKeys.FindHashed(aKey) >= 0;
  finally
    fSafe.UnLock;
  end;
end;

procedure TSynDictionary.CopyValues(out Dest; ObjArrayByRef: boolean);
begin
  fSafe.Lock;
  try
    fValues.CopyTo(Dest, ObjArrayByRef);
  finally
    fSafe.UnLock;
  end;
end;

function TSynDictionary.ForEach(const OnEach: TOnSynDictionary;
  Opaque: pointer): integer;
var
  k, v: PAnsiChar;
  i, n, ks, vs: PtrInt;
begin
  result := 0;
  fSafe.Lock;
  try
    n := fSafe.Padding[DIC_KEYCOUNT].VInteger;
    if (n = 0) or
       not Assigned(OnEach) then
      exit;
    k := fKeys.Value^;
    ks := fKeys.Info.Cache.ItemSize;
    v := fValues.Value^;
    vs := fValues.Info.Cache.ItemSize;
    for i := 0 to n - 1 do
    begin
      inc(result);
      if not OnEach(k^, v^, i, n, Opaque) then
        break;
      inc(k, ks);
      inc(v, vs);
    end;
  finally
    fSafe.UnLock;
  end;
end;

function TSynDictionary.ForEach(const OnMatch: TOnSynDictionary;
  KeyCompare, ValueCompare: TDynArraySortCompare; const aKey, aValue;
  Opaque: pointer): integer;
var
  k, v: PAnsiChar;
  i, n, ks, vs: PtrInt;
begin
  fSafe.Lock;
  try
    result := 0;
    if not Assigned(OnMatch) or
       (not Assigned(KeyCompare) and
        not Assigned(ValueCompare)) then
      exit;
    n := fSafe.Padding[DIC_KEYCOUNT].VInteger;
    k := fKeys.Value^;
    ks := fKeys.Info.Cache.ItemSize;
    v := fValues.Value^;
    vs := fValues.Info.Cache.ItemSize;
    for i := 0 to n - 1 do
    begin
      if (Assigned(KeyCompare) and
          (KeyCompare(k^, aKey) = 0)) or
         (Assigned(ValueCompare) and
          (ValueCompare(v^, aValue) = 0)) then
      begin
        inc(result);
        if not OnMatch(k^, v^, i, n, Opaque) then
          break;
      end;
      inc(k, ks);
      inc(v, vs);
    end;
  finally
    fSafe.UnLock;
  end;
end;

procedure TSynDictionary.SetTimeoutAtIndex(aIndex: integer);
var
  tim: cardinal;
begin
  if cardinal(aIndex) >= cardinal(fSafe.Padding[DIC_KEYCOUNT].VInteger) then
    exit;
  tim := fSafe.Padding[DIC_TIMESEC].VInteger;
  if tim > 0 then
    fTimeOut[aIndex] := cardinal(GetTickCount64 shr 10) + tim;
end;

function TSynDictionary.Count: integer;
begin
  result := fSafe.LockedInt64[DIC_KEYCOUNT];
end;

function TSynDictionary.RawCount: integer;
begin
  result := fSafe.Padding[DIC_KEYCOUNT].VInteger;
end;

procedure TSynDictionary.SaveToJson(W: TTextWriter; EnumSetsAsText: boolean);
var
  k, v: RawUtf8;
begin
  fSafe.Lock;
  try
    if fSafe.Padding[DIC_KEYCOUNT].VInteger > 0 then
    begin
      fKeys{$ifdef UNDIRECTDYNARRAY}.InternalDynArray{$endif}.
        SaveToJson(k, EnumSetsAsText);
      fValues.SaveToJson(v, EnumSetsAsText);
    end;
  finally
    fSafe.UnLock;
  end;
  W.AddJsonArraysAsJsonObject(pointer(k), pointer(v));
end;

function TSynDictionary.SaveToJson(EnumSetsAsText: boolean): RawUtf8;
var
  W: TTextWriter;
  temp: TTextWriterStackBuffer;
begin
  W := TTextWriter.CreateOwnedStream(temp) as TTextWriter;
  try
    SaveToJson(W, EnumSetsAsText);
    W.SetText(result);
  finally
    W.Free;
  end;
end;

function TSynDictionary.SaveValuesToJson(EnumSetsAsText: boolean): RawUtf8;
begin
  fSafe.Lock;
  try
    fValues.SaveToJson(result, EnumSetsAsText);
  finally
    fSafe.UnLock;
  end;
end;

function TSynDictionary.LoadFromJson(const Json: RawUtf8;
  CustomVariantOptions: PDocVariantOptions): boolean;
begin
  // pointer(Json) is not modified in-place thanks to JsonObjectAsJsonArrays()
  result := LoadFromJson(pointer(Json), CustomVariantOptions);
end;

function TSynDictionary.LoadFromJson(Json: PUtf8Char;
  CustomVariantOptions: PDocVariantOptions): boolean;
var
  k, v: RawUtf8; // private copy of the Json input, expanded as Keys/Values arrays
begin
  result := false;
  if not JsonObjectAsJsonArrays(Json, k, v) then
    exit;
  fSafe.Lock;
  try
    if (fKeys.LoadFromJson(pointer(k), nil, CustomVariantOptions) <> nil) and
       (fValues.LoadFromJson(pointer(v), nil, CustomVariantOptions) <> nil) and
       (fKeys.Count = fValues.Count) then
      begin
        SetTimeouts;
        fKeys.Rehash; // warning: duplicated keys won't be identified
        result := true;
      end;
  finally
    fSafe.UnLock;
  end;
end;

function TSynDictionary.LoadFromBinary(const binary: RawByteString): boolean;
var
  plain: RawByteString;
  rdr: TFastReader;
  n: integer;
begin
  result := false;
  plain := fCompressAlgo.Decompress(binary);
  if plain = '' then
    exit;
  rdr.Init(plain);
  fSafe.Lock;
  try
    try
      RTTI_BINARYLOAD[rkDynArray](fKeys.Value, rdr, fKeys.Info.Info);
      RTTI_BINARYLOAD[rkDynArray](fValues.Value, rdr, fValues.Info.Info);
      n := fKeys.Capacity;
      if n = fValues.Capacity then
      begin
        // RTTI_BINARYLOAD[rkDynArray]() did not set the external count
        fSafe.Padding[DIC_KEYCOUNT].VInteger := n;
        fSafe.Padding[DIC_VALUECOUNT].VInteger := n;      
        SetTimeouts;  // set ComputeNextTimeOut for all items
        fKeys.ReHash; // optimistic: input from safe TSynDictionary.SaveToBinary
        result := true;
      end;
    except
      result := false;
    end;
  finally
    fSafe.UnLock;
  end;
end;

class function TSynDictionary.OnCanDeleteSynPersistentLock(const aKey, aValue;
  aIndex: integer): boolean;
begin
  result := not TSynPersistentLock(aValue).Safe^.IsLocked;
end;

class function TSynDictionary.OnCanDeleteSynPersistentLocked(const aKey, aValue;
  aIndex: integer): boolean;
begin
  result := not TSynPersistentLock(aValue).Safe.IsLocked;
end;

function TSynDictionary.SaveToBinary(NoCompression: boolean;
  Algo: TAlgoCompress): RawByteString;
var
  tmp: TTextWriterStackBuffer;
  W: TBufferWriter;
begin
  fSafe.Lock;
  try
    result := '';
    if fSafe.Padding[DIC_KEYCOUNT].VInteger = 0 then
      exit;
    W := TBufferWriter.Create(tmp{%H-});
    try
      RTTI_BINARYSAVE[rkDynArray](fKeys.Value, W, fKeys.Info.Info);
      RTTI_BINARYSAVE[rkDynArray](fValues.Value, W, fValues.Info.Info);
      result := W.FlushAndCompress(NoCompression, Algo);
    finally
      W.Free;
    end;
  finally
    fSafe.UnLock;
  end;
end;



{ ********** Custom JSON Serialization }

{ TRttiJson }

function _New_ObjectList(Rtti: TRttiCustom): pointer;
begin
  result := TObjectList(Rtti.ValueClass).Create;
end;

function _New_InterfacedObjectWithCustomCreate(Rtti: TRttiCustom): pointer;
begin
  result := TInterfacedObjectWithCustomCreateClass(Rtti.ValueClass).Create;
end;

function _New_PersistentWithCustomCreate(Rtti: TRttiCustom): pointer;
begin
  result := TPersistentWithCustomCreateClass(Rtti.ValueClass).Create;
end;

function _New_Component(Rtti: TRttiCustom): pointer;
begin
  result := TComponentClass(Rtti.ValueClass).Create(nil);
end;

function _New_SynPersistent(Rtti: TRttiCustom): pointer;
begin
  result := TSynPersistentClass(Rtti.ValueClass).Create;
end;

function _New_SynObjectList(Rtti: TRttiCustom): pointer;
begin
  result := TSynObjectListClass(Rtti.ValueClass).Create({ownobjects=}true);
end;

function _New_SynLocked(Rtti: TRttiCustom): pointer;
begin
  result := TSynLockedClass(Rtti.ValueClass).Create;
end;

function _New_InterfacedCollection(Rtti: TRttiCustom): pointer;
begin
  result := TInterfacedCollectionClass(Rtti.ValueClass).Create;
end;

function _New_Collection(Rtti: TRttiCustom): pointer;
begin
  if Rtti.CollectionItem = nil then
    raise ERttiException.CreateUtf8('% with CollectionItem=nil: please call ' +
      'Rtti.RegisterCollection()', [Rtti.ValueClass]);
  result := TCollectionClass(Rtti.ValueClass).Create(Rtti.CollectionItem);
end;

function _New_CollectionItem(Rtti: TRttiCustom): pointer;
begin
  result := TCollectionItemClass(Rtti.ValueClass).Create(nil);
end;

function _New_Object(Rtti: TRttiCustom): pointer;
begin
  result := Rtti.ValueClass.Create;
end;

function _BC_RawByteString(A, B: PPUtf8Char; Info: PRttiInfo;
  out Compared: integer): PtrInt;
begin
  compared := SortDynArrayRawByteString(A^, B^); // will use length not #0
  result := SizeOf(pointer);
end;

function TRttiJson.SetParserType(aParser: TRttiParserType;
  aParserComplex: TRttiParserComplexType): TRttiCustom;
var
  C: TClass;
begin
  // set Name and Flags from Props[]
  inherited SetParserType(aParser, aParserComplex);
  // set comparison functions
  if rcfObjArray in fFlags then
  begin
    fCompare[true] := _BC_ObjArray;
    fCompare[false] := _BCI_ObjArray;
  end
  else
  begin
    fCompare[true] := RTTI_COMPARE[true][Kind];
    fCompare[false] := RTTI_COMPARE[false][Kind];
    if Kind = rkLString then
      // RTTI_COMPARE[rkLString] is StrCmp/StrICmp which is mostly fine
      if Cache.CodePage >= CP_RAWBLOB then
      begin
        // should use RawByteString length, and ignore any #0
        fCompare[true] := @_BC_RawByteString;
        fCompare[false] := @_BC_RawByteString;
      end else if Cache.CodePage = CP_UTF16 then
      begin
        // RawUnicode expects _BC_WString=StrCompW and _BCI_WString=StrICompW
        fCompare[true] := RTTI_COMPARE[true][rkWString];
        fCompare[false] := RTTI_COMPARE[false][rkWString];
      end;
  end;
  // set class serialization and initialization
  if aParser = ptClass then
  begin
    // default JSON serialization of published props
    fJsonSave := @_JS_RttiCustom;
    fJsonLoad := @_JL_RttiCustom;
    // prepare efficient ClassNewInstance() and recognize most parents
    C := fValueClass;
    repeat
      if C = TObjectList then
      begin
        fClassNewInstance := @_New_ObjectList;
        fJsonSave := @_JS_TObjectList;
        fJsonLoad := @_JL_TObjectList;
      end
      else if C = TInterfacedObjectWithCustomCreate then
        fClassNewInstance := @_New_InterfacedObjectWithCustomCreate
      else if C = TPersistentWithCustomCreate then
        fClassNewInstance := @_New_PersistentWithCustomCreate
      else if C = TSynPersistent then
      begin
        fClassNewInstance := @_New_SynPersistent;
        // allow any kind of customization for TSynPersistent children
        TSPHookClass(fValueClass).RttiCustomSet(self)
      end
      else if C = TSynObjectList then
      begin
        fClassNewInstance := @_New_SynObjectList;
        fJsonSave := @_JS_TSynObjectList;
        fJsonLoad := @_JL_TSynObjectList;
      end
      else if C = TSynLocked then
        fClassNewInstance := @_New_SynLocked
      else if C = TComponent then
        fClassNewInstance := @_New_Component
      else if C = TInterfacedCollection then
      begin
        if fValueClass <> C then
        begin
          fCollectionItem := TInterfacedCollectionClass(fValueClass).GetClass;
          fCollectionItemRtti := Rtti.RegisterClass(fCollectionItem);
        end;
        fClassNewInstance := @_New_InterfacedCollection;
        fJsonSave := @_JS_TCollection;
        fJsonLoad := @_JL_TCollection;
      end
      else if C = TCollection then
      begin
        fClassNewInstance := @_New_Collection;
        fJsonSave := @_JS_TCollection;
        fJsonLoad := @_JL_TCollection;
      end
      else if C = TCollectionItem then
        fClassNewInstance := @_New_CollectionItem
      else if C = TObject then
        fClassNewInstance := @_New_Object
      else
      begin
        if C = TSynList then
          fJsonSave := @_JS_TSynList
        else if C = TRawUtf8List then
        begin
          fJsonSave := @_JS_TRawUtf8List;
          fJsonLoad := @_JL_TRawUtf8List;
        end;
        C := C.ClassParent;
        continue;
      end;
      break;
    until false;
    case fValueRtlClass of
      vcStrings:
        begin
          fJsonSave := @_JS_TStrings;
          fJsonLoad := @_JL_TStrings;
        end;
      vcList:
        fJsonSave := @_JS_TList;
    end;
  end
  else if rcfBinary in Flags then
  begin
    fJsonSave := @_JS_Binary;
    fJsonLoad := @_JL_Binary;
  end
  else
  begin
    // default well-known serialization
    fJsonSave := PTC_JSONSAVE[aParserComplex];
    if not Assigned(fJsonSave) then
      fJsonSave := PT_JSONSAVE[aParser];
    fJsonLoad := PT_JSONLOAD[aParser];
    // rkRecordTypes serialization with proper fields RTTI
    if not Assigned(fJsonSave) and
       (Flags * [rcfWithoutRtti, rcfHasNestedProperties] <> []) then
      fJsonSave := @_JS_RttiCustom;
   if not Assigned(fJsonLoad) and
      (Flags * [rcfWithoutRtti, rcfHasNestedProperties] <> []) then
    fJsonLoad := @_JL_RttiCustom
  end;
  // TRttiJson.RegisterCustomSerializer() custom callbacks have priority
  if Assigned(fJsonWriter.Code) then
    fJsonSave := @_JS_RttiCustom;
  if Assigned(fJsonReader.Code) then
    fJsonLoad := @_JL_RttiCustom;
  result := self;
end;

function TRttiJson.ParseNewInstance(var Context: TJsonParserContext): TObject;
begin
  result := fClassNewInstance(self);
  TRttiJsonLoad(fJsonLoad)(@result, Context);
  if not Context.Valid then
    FreeAndNil(result);
end;

function TRttiJson.ValueCompare(Data, Other: pointer; CaseInsensitive: boolean): integer;
begin
  if Assigned(fCompare[CaseInsensitive]) then
    fCompare[CaseInsensitive](Data, Other, Info, result)
  else
    result := ComparePointer(Data, Other);
end;

procedure TRttiJson.ValueLoadJson(Data: pointer; var Json: PUtf8Char;
  EndOfObject: PUtf8Char; ParserOptions: TJsonParserOptions;
  CustomVariantOptions: PDocVariantOptions; ObjectListItemClass: TClass);
var
  ctxt: TJsonParserContext;
begin
  if Assigned(self) then
  begin
    ctxt.Init(
      Json, self, ParserOptions, CustomVariantOptions, ObjectListItemClass);
    if Assigned(fJsonLoad) then
      // efficient direct Json parsing
      TRttiJsonLoad(fJsonLoad)(Data, ctxt)
    else
      // try if binary serialization was used
      ctxt.Valid := ctxt.ParseNext and
            (Ctxt.Value <> nil) and
            (PCardinal(Ctxt.Value)^ and $ffffff = JSON_BASE64_MAGIC_C) and
            BinaryLoadBase64(pointer(Ctxt.Value + 3), Ctxt.ValueLen - 3,
              Data, Ctxt.Info.Info, {uri=}false, rkAllTypes, {withcrc=}false);
    if ctxt.Valid then
      Json := ctxt.Json
    else
      Json := nil;
  end
  else
    Json := nil;
end;

procedure TRttiJson.RawSaveJson(Data: pointer; const Ctxt: TJsonSaveContext);
begin
  TRttiJsonSave(fJsonSave)(Data, Ctxt);
end;

procedure TRttiJson.RawLoadJson(Data: pointer; var Ctxt: TJsonParserContext);
begin
  TRttiJsonLoad(fJsonLoad)(Data, Ctxt);
end;

class function TRttiJson.Find(Info: PRttiInfo): TRttiJson;
begin
  result := pointer(Rtti.Find(Info));
end;

class function TRttiJson.RegisterCustomSerializer(Info: PRttiInfo;
  const Reader: TOnRttiJsonRead; const Writer: TOnRttiJsonWrite): TRttiJson;
begin
  result := Rtti.RegisterType(Info) as TRttiJson;
  // (re)set fJsonSave/fJsonLoad
  result.fJsonWriter := TMethod(Writer);
  result.fJsonReader := TMethod(Reader);
  if result.Kind <> rkDynArray then // Reader/Writer are for items, not array
    result.SetParserType(result.Parser, result.ParserComplex);
end;

class function TRttiJson.RegisterCustomSerializerClass(ObjectClass: TClass;
  const Reader: TOnClassJsonRead; const Writer: TOnClassJsonWrite): TRttiJson;
begin
  // without {$M+} ObjectClasss.ClassInfo=nil -> ensure fake RTTI is available
  result := Rtti.RegisterClass(ObjectClass) as TRttiJson;
  result.fJsonWriter := TMethod(Writer);
  result.fJsonReader := TMethod(Reader);
  result.SetParserType(ptClass, pctNone);
end;

class function TRttiJson.UnRegisterCustomSerializer(Info: PRttiInfo): TRttiJson;
begin
  result := Rtti.RegisterType(Info) as TRttiJson;
  result.fJsonWriter.Code := nil; // force reset of the JSON serialization
  result.fJsonReader.Code := nil;
  if result.Kind <> rkDynArray then // Reader/Writer are for items, not array
    result.SetParserType(result.Parser, result.ParserComplex);
end;

class function TRttiJson.UnRegisterCustomSerializerClass(ObjectClass: TClass): TRttiJson;
begin
  // without {$M+} ObjectClasss.ClassInfo=nil -> ensure fake RTTI is available
  result := Rtti.RegisterClass(ObjectClass) as TRttiJson;
  result.fJsonWriter.Code := nil; // force reset of the JSON serialization
  result.fJsonReader.Code := nil;
  result.SetParserType(result.Parser, result.ParserComplex);
end;

class function TRttiJson.RegisterFromText(DynArrayOrRecord: PRttiInfo;
  const RttiDefinition: RawUtf8;
  IncludeReadOptions: TJsonParserOptions;
  IncludeWriteOptions: TTextWriterWriteObjectOptions): TRttiJson;
begin
  result := Rtti.RegisterFromText(DynArrayOrRecord, RttiDefinition) as TRttiJson;
  result.fIncludeReadOptions := IncludeReadOptions;
  result.fIncludeWriteOptions := IncludeWriteOptions;
end;


procedure _GetDataFromJson(Data: pointer; var Json: PUtf8Char;
  EndOfObject: PUtf8Char; TypeInfo: PRttiInfo;
  CustomVariantOptions: PDocVariantOptions; Tolerant: boolean);
begin
  TRttiJson(Rtti.RegisterType(TypeInfo)).ValueLoadJson(Data, Json, EndOfObject,
    JSONPARSER_DEFAULTORTOLERANTOPTIONS[Tolerant], CustomVariantOptions);
end;


{ ********** JSON Serialization Wrapper Functions }

procedure SaveJson(const Value; TypeInfo: PRttiInfo; Options: TTextWriterOptions;
  var result: RawUtf8);
var
  temp: TTextWriterStackBuffer;
begin
  with TTextWriter.CreateOwnedStream(temp) do
  try
    CustomOptions := CustomOptions + Options;
    AddTypedJson(@Value, TypeInfo);
    SetText(result);
  finally
    Free;
  end;
end;

function SaveJson(const Value; TypeInfo: PRttiInfo; EnumSetsAsText: boolean): RawUtf8;
begin
  SaveJson(Value, TypeInfo, TEXTWRITEROPTIONS_SETASTEXT[EnumSetsAsText], result);
end;

function RecordSaveJson(const Rec; TypeInfo: PRttiInfo;
  EnumSetsAsText: boolean): RawUtf8;
begin
  if (TypeInfo <> nil) and
     (TypeInfo^.Kind in rkRecordTypes) then
    SaveJson(Rec, TypeInfo, TEXTWRITEROPTIONS_SETASTEXT[EnumSetsAsText], result)
  else
    result := NULL_STR_VAR;
end;

function DynArraySaveJson(const Value; TypeInfo: PRttiInfo;
  EnumSetsAsText: boolean): RawUtf8;
begin
  if (TypeInfo = nil) or
     (TypeInfo^.Kind <> rkDynArray) then
    result := NULL_STR_VAR
  else if pointer(Value) = nil then
    result := '[]'
  else
    SaveJson(Value, TypeInfo, TEXTWRITEROPTIONS_SETASTEXT[EnumSetsAsText], result);
end;

function DynArrayBlobSaveJson(TypeInfo: PRttiInfo; BlobValue: pointer): RawUtf8;
var
  DynArray: TDynArray;
  Value: pointer; // decode BlobValue into a temporary dynamic array
  temp: TTextWriterStackBuffer;
begin
  Value := nil;
  DynArray.Init(TypeInfo, Value);
  try
    if DynArray.LoadFrom(BlobValue) = nil then
      result := ''
    else
      with TTextWriter.CreateOwnedStream(temp) do
      try
        AddDynArrayJson(DynArray);
        SetText(result);
      finally
        Free;
      end;
  finally
    DynArray.Clear; // release temporary memory
  end;
end;

function ObjectToJson(Value: TObject;
  Options: TTextWriterWriteObjectOptions): RawUtf8;
var
  temp: TTextWriterStackBuffer;
begin
  if Value = nil then
    result := NULL_STR_VAR
  else
    with TTextWriter.CreateOwnedStream(temp) do
    try
      CustomOptions := CustomOptions + [twoForceJsonStandard];
      WriteObject(Value, Options);
      SetText(result);
    finally
      Free;
    end;
end;

function ObjectsToJson(const Names: array of RawUtf8;
  const Values: array of TObject;
  Options: TTextWriterWriteObjectOptions): RawUtf8;
var
  i, n: PtrInt;
  temp: TTextWriterStackBuffer;
begin
  with TTextWriter.CreateOwnedStream(temp) do
  try
    n := high(Names);
    BlockBegin('{', Options);
    i := 0;
    if i <= high(Values) then
      repeat
        if i <= n then
          AddFieldName(Names[i])
        else if Values[i] = nil then
          AddFieldName(SmallUInt32Utf8[i])
        else
          AddPropName(ClassNameShort(Values[i])^);
        WriteObject(Values[i], Options);
        if i = high(Values) then
          break;
        BlockAfterItem(Options);
        inc(i);
      until false;
    CancelLastComma;
    BlockEnd('}', Options);
    SetText(result);
  finally
    Free;
  end;
end;

function ObjectToJsonFile(Value: TObject; const JsonFile: TFileName;
  Options: TTextWriterWriteObjectOptions): boolean;
var
  humanread: boolean;
  json: RawUtf8;
begin
  humanread := woHumanReadable in Options;
  if humanread and
     (woHumanReadableEnumSetAsComment in Options) then
    humanread := false
  else
    // JsonReformat() erases comments
    exclude(Options, woHumanReadable);
  json := ObjectToJson(Value, Options);
  if humanread then
    // woHumanReadable not working with custom JSON serializers, e.g. T*ObjArray
    // TODO: check if this is always the case with our mORMot2 new serialization
    result := JsonBufferReformatToFile(pointer(json), JsonFile)
  else
    result := FileFromString(json, JsonFile);
end;

function ObjectToJsonDebug(Value: TObject;
  Options: TTextWriterWriteObjectOptions): RawUtf8;
begin
  // our JSON serialization detects and serialize Exception.Message
  result := ObjectToJson(Value, Options);
end;

function LoadJson(var Value; Json: PUtf8Char; TypeInfo: PRttiInfo;
  EndOfObject: PUtf8Char; CustomVariantOptions: PDocVariantOptions;
  Tolerant: boolean): PUtf8Char;
begin
  TRttiJson(Rtti.RegisterType(TypeInfo)).ValueLoadJson(@Value, Json, EndOfObject,
    JSONPARSER_DEFAULTORTOLERANTOPTIONS[Tolerant], CustomVariantOptions);
  result := Json;
end;

function RecordLoadJson(var Rec; Json: PUtf8Char; TypeInfo: PRttiInfo;
  EndOfObject: PUtf8Char; CustomVariantOptions: PDocVariantOptions;
  Tolerant: boolean): PUtf8Char;
begin
  if (TypeInfo = nil) or
     not (TypeInfo.Kind in rkRecordTypes) then
    raise EJSONException.CreateUtf8('RecordLoadJson: % is not a record',
      [TypeInfo.Name]);
  TRttiJson(Rtti.RegisterType(TypeInfo)).ValueLoadJson(@Rec, Json, EndOfObject,
      JSONPARSER_DEFAULTORTOLERANTOPTIONS[Tolerant], CustomVariantOptions);
  result := Json;
end;

function RecordLoadJson(var Rec; const Json: RawUtf8; TypeInfo: PRttiInfo;
  CustomVariantOptions: PDocVariantOptions; Tolerant: boolean): boolean;
var
  tmp: TSynTempBuffer;
begin
  tmp.Init(Json); // make private copy before in-place decoding
  try
    result := RecordLoadJson(Rec, tmp.buf, TypeInfo, nil,
      CustomVariantOptions, Tolerant) <> nil;
  finally
    tmp.Done;
  end;
end;

function DynArrayLoadJson(var Value; Json: PUtf8Char; TypeInfo: PRttiInfo;
  EndOfObject: PUtf8Char; CustomVariantOptions: PDocVariantOptions;
  Tolerant: boolean): PUtf8Char;
begin
  if (TypeInfo = nil) or
     (TypeInfo.Kind <> rkDynArray) then
    raise EJSONException.CreateUtf8('DynArrayLoadJson: % is not a dynamic array',
      [TypeInfo.Name]);
  TRttiJson(Rtti.RegisterType(TypeInfo)).ValueLoadJson(@Value, Json, EndOfObject,
    JSONPARSER_DEFAULTORTOLERANTOPTIONS[Tolerant], CustomVariantOptions);
  result := Json;
end;

function DynArrayLoadJson(var Value; const Json: RawUtf8; TypeInfo: PRttiInfo;
  CustomVariantOptions: PDocVariantOptions; Tolerant: boolean): boolean;
var
  tmp: TSynTempBuffer;
begin
  tmp.Init(Json); // make private copy before in-place decoding
  try
    result := DynArrayLoadJson(Value, tmp.buf, TypeInfo, nil,
      CustomVariantOptions, Tolerant) <> nil;
  finally
    tmp.Done;
  end;
end;

function JsonToObject(var ObjectInstance; From: PUtf8Char; out Valid: boolean;
  TObjectListItemClass: TClass; Options: TJsonParserOptions): PUtf8Char;
var
  ctxt: TJsonParserContext;
begin
  if pointer(ObjectInstance) = nil then
    raise ERttiException.Create('JsonToObject(nil)');
  ctxt.Init(From, Rtti.RegisterClass(TObject(ObjectInstance)), Options,
    nil, TObjectListItemClass);
  TRttiJsonLoad(Ctxt.Info.JsonLoad)(@ObjectInstance, ctxt);
  Valid := ctxt.Valid;
  result := ctxt.JSON;
end;

function JSONSettingsToObject(var InitialJsonContent: RawUtf8;
  Instance: TObject): boolean;
var
  tmp: TSynTempBuffer;
begin
  result := false;
  if InitialJsonContent = '' then
    exit;
  tmp.Init(InitialJsonContent);
  try
    RemoveCommentsFromJson(tmp.buf);
    JsonToObject(Instance, tmp.buf, result, nil, JSONPARSER_TOLERANTOPTIONS);
    if not result then
      InitialJsonContent := '';
  finally
    tmp.Done;
  end;
end;

function ObjectLoadJson(var ObjectInstance; const Json: RawUtf8;
  TObjectListItemClass: TClass; Options: TJsonParserOptions): boolean;
var
  tmp: TSynTempBuffer;
begin
  tmp.Init(Json);
  if tmp.len <> 0 then
    try
      JsonToObject(ObjectInstance, tmp.buf, result, TObjectListItemClass, Options);
    finally
      tmp.Done;
    end
  else
    result := false;
end;

function JsonToNewObject(var From: PUtf8Char; var Valid: boolean;
  Options: TJsonParserOptions): TObject;
var
  ctxt: TJsonParserContext;
begin
  ctxt.Init(From, nil, Options, nil, nil);
  result := ctxt.ParseNewObject;
end;

function PropertyFromJson(Prop: PRttiCustomProp; Instance: TObject;
  From: PUtf8Char; var Valid: boolean; Options: TJsonParserOptions): PUtf8Char;
var
  ctxt: TJsonParserContext;
begin
  Valid := false;
  result := nil;
  if (Prop = nil) or
     (Prop^.Value.Kind <> rkClass) or
     (Instance = nil) then
    exit;
  ctxt.Init(From, Prop^.Value, Options, nil, nil);
  if not JsonLoadProp(pointer(Instance), Prop^, ctxt) then
    exit;
  Valid := true;
  result := ctxt.JSON;
end;

function UrlDecodeObject(U: PUtf8Char; Upper: PAnsiChar;
  var ObjectInstance; Next: PPUtf8Char; Options: TJsonParserOptions): boolean;
var
  tmp: RawUtf8;
begin
  result := UrlDecodeValue(U, Upper, tmp, Next);
  if result then
    JsonToObject(ObjectInstance, Pointer(tmp), result, nil, Options);
end;

function JsonFileToObject(const JsonFile: TFileName; var ObjectInstance;
  TObjectListItemClass: TClass; Options: TJsonParserOptions): boolean;
var
  tmp: RawUtf8;
begin
  tmp := AnyTextFileToRawUtf8(JsonFile, true);
  if tmp = '' then
    result := false
  else
  begin
    RemoveCommentsFromJson(pointer(tmp));
    JsonToObject(ObjectInstance, pointer(tmp), result, TObjectListItemClass, Options);
  end;
end;

procedure JsonBufferToXML(P: PUtf8Char; const Header,NameSpace: RawUtf8;
  out result: RawUtf8);
var
  i, j, L: integer;
  temp: TTextWriterStackBuffer;
begin
  if P = nil then
    result := Header
  else
    with TTextWriter.CreateOwnedStream(temp) do
    try
      AddNoJsonEscape(pointer(Header), length(Header));
      L := length(NameSpace);
      if L <> 0 then
        AddNoJsonEscape(pointer(NameSpace), L);
      AddJsonToXML(P);
      if L <> 0 then
        for i := 1 to L do
          if NameSpace[i] = '<' then
          begin
            for j := i + 1 to L do
              if NameSpace[j] in [' ', '>'] then
              begin
                Add('<', '/');
                AddStringCopy(NameSpace, i + 1, j - i - 1);
                Add('>');
                break;
              end;
            break;
          end;
      SetText(result);
    finally
      Free;
    end;
end;

function JsonToXML(const Json: RawUtf8; const Header: RawUtf8;
  const NameSpace: RawUtf8): RawUtf8;
var
  tmp: TSynTempBuffer;
begin
  tmp.Init(Json);
  try
    JsonBufferToXML(tmp.buf, Header, NameSpace, result);
  finally
    tmp.Done;
  end;
end;


{ ********************* Abstract Classes with Auto-Create-Fields }

function DoRegisterAutoCreateFields(ObjectInstance: TObject): TRttiJson;
begin // sub procedure for smaller code generation in AutoCreateFields/Create
  result := Rtti.RegisterAutoCreateFieldsClass(PClass(ObjectInstance)^) as TRttiJson;
end;

procedure AutoCreateFields(ObjectInstance: TObject);
var
  rtti: TRttiJson;
  n: integer;
  p: ^PRttiCustomProp;
begin
  // inlined ClassPropertiesGet
  rtti := PPointer(PPAnsiChar(ObjectInstance)^ + vmtAutoTable)^;
  if (rtti = nil) or
     not (rcfAutoCreateFields in rtti.Flags) then
    rtti := DoRegisterAutoCreateFields(ObjectInstance);
  p := pointer(rtti.fAutoCreateClasses);
  if p = nil then
    exit;
  // create all published class fields
  n := PDALen(PAnsiChar(p) - _DALEN)^ + _DAOFF; // length(AutoCreateClasses)
  repeat
    with p^^ do
      PPointer(PAnsiChar(ObjectInstance) + OffsetGet)^ :=
        TRttiJson(Value).fClassNewInstance(Value);
    inc(p);
    dec(n);
  until n = 0;
end;

procedure AutoDestroyFields(ObjectInstance: TObject);
var
  rtti: TRttiJson;
  n: integer;
  p: ^PRttiCustomProp;
  arr: PPAnsiChar;
  o: TObject;
begin
  rtti := PPointer(PPAnsiChar(ObjectInstance)^ + vmtAutoTable)^;
  // free all published class fields
  p := pointer(rtti.fAutoCreateClasses);
  if p <> nil then
  begin
    n := PDALen(PAnsiChar(p) - _DALEN)^ + _DAOFF;
    repeat
      o := PObject(PAnsiChar(ObjectInstance) + p^^.OffsetGet)^;
      if o <> nil then
        // inlined o.Free
        o.Destroy;
      inc(p);
      dec(n);
    until n = 0;
  end;
  // release all published T*ObjArray fields
  p := pointer(rtti.fAutoCreateObjArrays);
  if p = nil then
    exit;
  n := PDALen(PAnsiChar(p) - _DALEN)^ + _DAOFF;
  repeat
    arr := pointer(PAnsiChar(ObjectInstance) + p^^.OffsetGet);
    if arr^ <> nil then
      // inlined ObjArrayClear()
      RawObjectsClear(pointer(arr^), PDALen(arr^ - _DALEN)^ + _DAOFF);
    inc(p);
    dec(n);
  until n = 0;
end;


{ TPersistentAutoCreateFields }

constructor TPersistentAutoCreateFields.Create;
begin
  AutoCreateFields(self);
end; // no need to call the void inherited TPersistentWithCustomCreate

destructor TPersistentAutoCreateFields.Destroy;
begin
  AutoDestroyFields(self);
  inherited Destroy;
end;


{ TSynAutoCreateFields }

constructor TSynAutoCreateFields.Create;
begin
  AutoCreateFields(self);
end; // no need to call the void inherited TSynPersistent

destructor TSynAutoCreateFields.Destroy;
begin
  AutoDestroyFields(self);
  inherited Destroy;
end;


{ TSynAutoCreateFieldsLocked }

constructor TSynAutoCreateFieldsLocked.Create;
begin
  AutoCreateFields(self);
  inherited Create; // initialize fSafe := NewSynLocker
end;

destructor TSynAutoCreateFieldsLocked.Destroy;
begin
  AutoDestroyFields(self);
  inherited Destroy;
end;


{ TInterfacedObjectAutoCreateFields }

constructor TInterfacedObjectAutoCreateFields.Create;
begin
  AutoCreateFields(self);
end; // no need to call TInterfacedObjectWithCustomCreate.Create

destructor TInterfacedObjectAutoCreateFields.Destroy;
begin
  AutoDestroyFields(self);
  inherited Destroy;
end;


{ TCollectionItemAutoCreateFields }

constructor TCollectionItemAutoCreateFields.Create(Collection: TCollection);
begin
  AutoCreateFields(self);
  inherited Create(Collection);
end;

destructor TCollectionItemAutoCreateFields.Destroy;
begin
  AutoDestroyFields(self);
  inherited Destroy;
end;


{ TSynJsonFileSettings }

function TSynJsonFileSettings.LoadFromJson(var aJson: RawUtf8): boolean;
begin
  result := JSONSettingsToObject(aJson, self);
end;

function TSynJsonFileSettings.LoadFromFile(const aFileName: TFileName): boolean;
begin
  fFileName := aFileName;
  fInitialJsonContent := StringFromFile(aFileName);
  result := LoadFromJson(fInitialJsonContent);
end;

procedure TSynJsonFileSettings.SaveIfNeeded;
var
  saved: RawUtf8;
begin
  if (self = nil) or
     (fFileName = '') then
    exit;
  saved := ObjectToJson(self, SETTINGS_WRITEOPTIONS);
  if saved = fInitialJsonContent then
    exit;
  FileFromString(saved, fFileName);
  fInitialJsonContent := saved;
end;


procedure InitializeUnit;
var
  i: PtrInt;
  c: AnsiChar;
begin
  // branchless JSON escaping - JSON_ESCAPE_NONE=0 if no JSON escape needed
  JSON_ESCAPE[0] := JSON_ESCAPE_ENDINGZERO;   // 1 for #0 end of input
  for i := 1 to 31 do
    JSON_ESCAPE[i] := JSON_ESCAPE_UNICODEHEX; // 2 should be escaped as \u00xx
  JSON_ESCAPE[8] := ord('b');  // others contain the escaped character
  JSON_ESCAPE[9] := ord('t');
  JSON_ESCAPE[10] := ord('n');
  JSON_ESCAPE[12] := ord('f');
  JSON_ESCAPE[13] := ord('r');
  JSON_ESCAPE[ord('\')] := ord('\');
  JSON_ESCAPE[ord('"')] := ord('"');
  // branchless JSON parsing
  for c := low(c) to high(c) do
  begin
    if c in [#0, ',', ']', '}', ':'] then
      include(JSON_CHARS[c], jcEndOfJsonFieldOr0);
    if c in [#0, ',', ']', '}'] then
      include(JSON_CHARS[c], jcEndOfJsonFieldNotName);
    if c in [#0, #9, #10, #13, ' ',  ',', '}', ']'] then
      include(JSON_CHARS[c], jcEndOfJsonValueField);
    if c in [#0, '"', '\'] then
      include(JSON_CHARS[c], jcJsonStringMarker);
    if c in ['-', '0'..'9'] then
    begin
      include(JSON_CHARS[c], jcDigitFirstChar);
      JSON_TOKENS[c] := jtFirstDigit;
    end;
    if c in ['-', '+', '0'..'9', '.', 'E', 'e'] then
      include(JSON_CHARS[c], jcDigitFloatChar);
    if c in ['_', '0'..'9', 'a'..'z', 'A'..'Z', '$'] then
      include(JSON_CHARS[c], jcJsonIdentifierFirstChar);
    if c in ['_', 'a'..'z', 'A'..'Z', '$'] then
      // exclude '0'..'9' as already in jcDigitFirstChar
      JSON_TOKENS[c] := jtIdentifierFirstChar;
    if c in ['_', '0'..'9', 'a'..'z', 'A'..'Z', '.', '[', ']'] then
      include(JSON_CHARS[c], jcJsonIdentifier);
  end;
  JSON_TOKENS['{'] := jtObjectStart;
  JSON_TOKENS['}'] := jtObjectStop;
  JSON_TOKENS['['] := jtArrayStart;
  JSON_TOKENS[']'] := jtArrayStop;
  JSON_TOKENS[':'] := jtAssign;
  JSON_TOKENS[','] := jtComma;
  JSON_TOKENS[''''] := jtSingleQuote;
  JSON_TOKENS['"'] := jtDoubleQuote;
  JSON_TOKENS['t'] := jtTrueFirstChar;
  JSON_TOKENS['f'] := jtFalseFirstChar;
  JSON_TOKENS['n'] := jtNullFirstChar;
  JSON_TOKENS['/'] := jtSlash;
  // initialize JSON serialization
  if Rtti.Count > 0 then
    raise EJSONException.CreateUtf8(
      'Rtti.Count=% at mormot.core.json start', [Rtti.Count]);
  Rtti.GlobalClass := TRttiJson;
  GetDataFromJson := _GetDataFromJson;
  _VariantToUtf8DateTimeToIso8601 := DateTimeToIso8601TextVar;
end;


initialization
  InitializeUnit;
  DefaultTextWriterSerializer := TTextWriter;
  
end.

