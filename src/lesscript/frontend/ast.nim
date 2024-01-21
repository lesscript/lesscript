# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2023 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

import std/[json, tables, strutils]
import ./critbits

import pkg/bigints

when not defined release:
  import std/jsonutils
else:
  import pkg/jsony

from ./tokens import TokenTuple, TokenKind

export critbits, tables

type
  NodeType* = enum
    ntNone
    ntNil
    ntVarDecl = "Variable"
    ntAssign = "AssignStatement"
    ntTypeDef = "Type"
    ntClassDef = "Class"
    ntFuncDef = "Function"
    ntProperty = "PropertyStatement"
    ntStmt = "StatementList"
    ntCall = "CallStatement"
    ntEnum = "Enum"
    ntInterface = "Interface"
    ntDotExpr = "DotExpression"
    ntBracketExpr = "BracketExpression"
    ntCommand
    ntAccessor
    ntIdentifier
    ntValue
    ntDocComment
    ntInlineComment
    ntDeclare 
    ntInfixMath = "MathExpression"
    ntInfix = "InfixExpression"
    ntIf = "IfExpression"
    ntFor = "ForExpression"
    arrayDecl
    objectDecl
    ntUnpack
    ntImport = "ImportStatement" 
    ntGeneric = "GenericStatement"

  Type* = enum
    tNone = "none"
    tCustom
    tAny = "any"
    tVoid = "void"
    tArray = "array"
    tClass = "class"
    tEnum =  "enum"
    tFloat   = "float"
    tFloat8  = "float8"
    tFloat16 = "float16"
    tFloat32 = "float32"
    tFloat64 = "float64"
    tFunction = "function"
    tInt   = "int"
    tInt8  = "int8"
    tInt16 = "int16"
    tInt32 = "int32"
    tInt64 = "int64"
    tBigInt = "bigint"
    tInterface = "interface"
    tObject = "object"
    tString = "string"
    tTuple = "tuple"
    tBool = "bool"
    tTemplate = "template"
    tGeneric

  CommandType* = enum
    cEcho = "log"
    cWarn = "warn"
    cError = "error"
    cInfo = "info"
    cAssert = "assert"
    cCall
    cReturn

  Accessibility* = enum
    accPublic
    accProtected
    accPrivate

  VarType* = enum
    vtVar = "var"
    vtLet = "let"
    vtConst = "const"

  InfixOp* {.pure.} = enum
    infixNone
    EQ    = "=="
    NE    = "!="
    GT    = ">"
    GTE   = ">="
    LT    = "<"
    LTE   = "<="
    AND   = "&&"
    OR    = "||"
    ANDA   = "&&="

  MathOp* {.pure.} = enum
    invalidCalcOp
    mPlus = "+"
    mMinus = "-"
    mMulti = "*"
    mDiv = "/"
    mMod = "%"

  CallArg* = tuple[argName: string, argValue: Node]
  ScopeTable* = TableRef[string, Node]

  # Enums
  EnumTable* = OrderedTableRef[string, Node]
  
  Meta* = tuple[line, pos: int]

  Value* = object
    case vt*: Type
    of tArray:    vArr*: seq[Node]
    of tString:   vStr*: string
    of tBool:     vBool*: bool
    of tFloat:    vFloat*: float
    # todo
    # of tFloat8:   vFloat8*: float8 
    # of tFloat16:  vFloat16*: float16
    of tFloat32:  vFloat32*: float32
    of tFloat64:  vFloat64*: float64
    of tInt:      vInt*: int
    of tInt8:     vInt8*: int8
    of tInt16:    vInt16*: int16
    of tInt32:    vInt32*: int32
    of tInt64:    vInt64*: int64
    of tBigInt:   vBint*: BigInt
    else: discard

  StmtType* = enum
    stlist, sttree

  CallType* = enum
    identCall, fnCall, classCall

  ConditionBranch* = tuple[cond: Node, body: Node]

  StmtNode* = ref object
    case stmtType*: StmtType
    of stlist:
      list*: seq[Node]
    of sttree:
      tree*: CritBitTree[Node]

  Node* {.acyclic.} = ref object
    case nt*: NodeType
    of ntValue:
      val*: Value
    of ntNil: discard
    of ntVarDecl:
      varIdent*: string
      varType*: VarType
      valType*: Type
      valTypeof*: Node # ntIdentifier
      varValue*: Node
      varInline*, varOthers*: seq[Node] # ntVarDecl
      varUsed*: bool
    of ntAssign:
      asgnIdent*, asgnValue*: Node
    of ntTypeDef:
      typeIdent*: string
      typeNode*: Node # ntStmt
      typeLit*: Type
    of ntEnum:
      enumIdent*: string
      enumFields*: EnumTable
      enumExport*, enumUsed*: bool
    of ntInterface:
      interfaceIdent*: string
      interfaceStmt*: Node # ntStmt
      interfaceExport*, interfaceUsed*: bool
    of ntClassDef:
      classIdent*: string
      classExport*, classUsed*: bool
      classConstructor*: Node    # ntFuncDef
      methods*: seq[Node]        # ntFuncDef
      properties*: CritBitTree[Node] # ntProperty
      classExtends*: seq[string]
      classImplements*: seq[string]
      classBody*: Node # ntStmtNode
    of ntFuncDef:
      fnIdent*: string
      # todo a case `fntReturnType of `tCase` then define `fnReturnIdent` field
      # there is a bug in pkg/flatty that prevent nested object variant
      fnReturnType*: Type
      fnReturnIdent*: Node # ntCall or nil
      fnExport*, fnFwd*, fnHasReturnType*,
        fnHasGenerics*, fnAnonymous*, fnUsed*: bool
      fnParams*: OrderedTable[string, Node] # ntVar
      fnGenerics*: OrderedTable[string, Type]
      fnBody*: Node              # ntStmt
      fnDoc*: Node
    of ntProperty:
      pKey*: string
      pType*: Type
      pIdent*: string # filled when `pType` is `tCustom`, otherwise empty
      pVal*: Node
      pReadonly*, pStatic*, pOptional*: bool
      pAccessibility*: Accessibility
    of ntFor:
      forItem*, forItems*: Node
      forBody*: Node # ntStmt
    of ntUnpack:
      unpackFrom*: Node
      unpackTo*: seq[Node]
    of arrayDecl:
      arrayItems*: seq[Node]
      arrayType*: Type
    of objectDecl:
      objectItems*: OrderedTable[string, Node]
    of ntStmt:
      stmtNode*: StmtNode
    of ntCall:
      callIdent*: string
      callType*: CallType     # either classCall, fnCall, identCall
      callArgs*: seq[CallArg]
    of ntAccessor:
      accessorStorage*: Node  # objectDecl, arrayDecl
      accessorType*: NodeType # ntDot, objectDecl, arrayDecl
      accessorKey*: Node
    of ntIdentifier:
      identName*: string
      identType*: Type
      identExtractType*: bool
      # identIndex*: int # the index of seq[ScopeTable] where it can be found 
    of ntIf:
      ifBranch*: ConditionBranch
      elifBranch*: seq[ConditionBranch] # tuple[ntInfix, ntStmt]
      elseBranch*: Node # ntStmt
    of ntCommand:
      cmdType*: CommandType
      cmd*: Node
      cmdArgs*: seq[Node]
        # optional command arguments.
        # for example `assert a == b, "Some message"`
    of ntDotExpr:
      lhs*, rhs*: Node
    of ntBracketExpr:
      bracketIdent*, bracketIndex*: Node
    of ntInfix:
      infixOp*: InfixOp
      lhsInfix*, rhsInfix*: Node
    of ntInfixMath:
      infixMathOp*: MathOp
      lhsMath*, rhsMath*: Node
      infixMathResultType*: NodeType # either ntInt or ntFloat
    of ntDocComment:
      commentBlock*: string
      commentBlockParams*: seq[string]
    of ntDeclare:
      declareStmt: Node
    of ntImport:
      importPath*: string
    else: discard
    meta*: Meta

  Imports* = seq[string]

  ModuleTable* = Table[string, Module]

  Module* = object
    path*: string
    nodes*: seq[Node]
    imports*: ModuleTable


proc `$`*(node: Node): string =
  {.gcsafe.}:
    when not defined release:
      pretty(toJson(node), 2)
    else:
      toJson(node)

proc `$`*(nodes: seq[Node]): string =
  {.gcsafe.}:
    when not defined release:
      pretty(toJson(nodes), 2)
    else:
      toJson(nodes)

proc `$`*(module: Module): string =
  {.gcsafe.}:
    when not defined release:
      pretty(toJson(module), 2)
    else:
      toJson(module)

proc trace*(tk: TokenTuple): Meta = (tk.line, tk.col)

proc getType*(node: Node): Type =
  case node.nt:
  of ntValue: node.val.vt
  of ntFuncDef: tFunction
  of ntClassDef: tClass
  of objectDecl: tObject
  of arrayDecl: tArray
  of ntVarDecl:
    case node.valType
    of tNone:
      node.varValue.getType()
    else:
      node.valType
  of ntCall:
    case node.callType:
    of fnCall: tFunction
    of classCall: tClass
    else: tNone
  else: tNone

proc getInfixOp*(kind: TokenKind, isInfixInfix: bool): InfixOp =
  result =
    case kind:
    of tkEQ: EQ
    of tkNE: NE
    of tkLT: LT
    of tkLTE: LTE
    of tkGT: GT
    of tkGTE: GTE
    of tkAnd: AND
    of tkOR: OR
    of tkAndAsgn: ANDA  
    else: infixNone

proc getInfixCalcOp*(kind: TokenKind, isInfixInfix: bool): MathOp =
  result =
    case kind:
    of tkPlus: mPlus
    of tkMinus: mMinus
    of tkMulti: mMulti
    of tkDiv: mDiv
    of tkMod: mMod
    else: invalidCalcOp

proc newBool*(tk: TokenTuple): Node =
  Node(nt: ntValue, val: Value(vt: tBool, vBool: parseBool(tk.value)), meta: tk.trace)

proc newFloat*(tk: TokenTuple): Node =
  Node(nt: ntValue, val: Value(vt: tFloat, vFloat: parseFloat(tk.value)), meta: tk.trace)

proc newInt*(tk: TokenTuple): Node =
  Node(nt: ntValue, val: Value(vt: tInt, vInt: parseInt(tk.value)), meta: tk.trace)

proc newStr*(tk: TokenTuple): Node =
  Node(nt: ntValue, val: Value(vt: tString, vStr: tk.value), meta: tk.trace)

proc newComment*(tk: TokenTuple): Node =
  Node(nt: ntDocComment, commentBlock: tk.value, commentBlockParams: tk.attr, meta: tk.trace)

# proc newGeneric*(x: string): Node =
  # Node(nt: ntGeneric, genericNode)

proc newValueByType*(valType: Type, v: string): Value =
  case valType
  of tString: Value(vt: tString, vStr: v)
  of tInt: Value(vt: tInt, vInt: v.parseInt)
  of tFloat: Value(vt: tFloat, vFloat: v.parseFloat)
  else: Value(vt: tString)

proc newVar*(id: TokenTuple, varValue: Node, varType: VarType,
    valType: Type, varInline: seq[Node], tk: TokenTuple, valTypeof: Node = nil): Node =
  ## Create a new `var`, `let`, or `const` Node
  Node(nt: ntVarDecl, varIdent: id.value, varValue: varValue,
    valType: valType, varType: varType,
    varInline: varInline, valTypeof: valTypeof,
    meta: tk.trace)

proc newVar*(id, tk: TokenTuple): Node =
  ## Create a new `ntVarDecl` Node
  Node(nt: ntVarDecl, varIdent: id.value, meta: tk.trace)

proc newVar*(id: string, varType: VarType, meta: Meta): Node =
  ## Create a new `ntVarDecl` node
  Node(nt: ntVarDecl, varIdent: id, varType: varType, meta: meta)

proc newAssignment*(asgnIdent, varValue: Node, tk: TokenTuple): Node =
  ## Create a new assignment node
  Node(nt: ntAssign, asgnIdent: asgnIdent, asgnValue: varValue, meta: tk.trace)

proc newArray*(tk: TokenTuple, arrayItems: seq[Node]): Node =
  ## Create a new `arrayDecl` node
  Node(nt: arrayDecl, arrayItems: arrayItems, meta: tk.trace)

proc newObject*(tk: TokenTuple): Node =
  ## Returns an incomplete `objectDecl` node
  Node(nt: objectDecl, meta: tk.trace)

proc newUnpack*(fromVal: Node, toVars: seq[Node]): Node =
  ## Create a new `ntUnpack` node
  Node(nt: ntUnpack, unpackFrom: fromVal, unpackTo: toVars)

proc newInfix*(lht: Node): Node =
  ## Returns an incomplete `ntInfix` node
  Node(nt: ntInfix, lhsInfix: lht)

proc newInfixMath*(lht: Node): Node =
  ## Create a new `ntInfixMath` node
  Node(nt: ntInfixMath, lhsMath: lht)

proc newIfCond*(ifBranch: ConditionBranch, tk: TokenTuple): Node =
  ## Create a new `ntIf` node
  Node(nt: ntIf, ifBranch: ifBranch, meta: tk.trace)

proc newTypeDef*(tk: TokenTuple, typeNode: Node, typeLit: Type): Node =
  Node(nt: ntTypeDef, typeIdent: tk.value, typeNode: typeNode, typeLit: typeLit, meta: tk.trace)

proc newStmtList*: Node =
  ## Creates a new `ntStmt` node of `StmtType.stlist` 
  Node(nt: ntStmt, stmtNode: StmtNode(stmtType: stlist))

proc newStmtTree*: Node =
  ## Creates a new `ntStmt node of `StmtType.sttree`
  Node(nt: ntStmt, stmtNode: StmtNode(stmtType: sttree)) 

proc newFunction*(id: string, tk: TokenTuple): Node =
  Node(nt: ntFuncDef, fnIdent: id, fnReturnType: tVoid, meta: tk.trace)

proc newFunction*(tk: TokenTuple): Node =
  Node(nt: ntFuncDef, fnAnonymous: true, fnReturnType: tVoid, meta: tk.trace)

proc newClass*(ident: TokenTuple, methods: seq[Node] = @[]): Node =
  ## Creates a new `class` Node
  Node(nt: ntClassDef, classIdent: ident.value, methods: methods, meta: ident.trace)

proc newCall*(ident: string, args: seq[CallArg]): Node =
  ## Create a new `ntCall` Node for given `ident` and available `args`
  result = Node(nt: ntCall, callIdent: ident, callArgs: args)

proc newCall*(id: TokenTuple): Node =
  Node(nt: ntCall, callIdent: id.value, meta: id.trace)

proc newDeclareStmt*(id: TokenTuple, node: Node): Node =
  Node(nt: ntDeclare, declareStmt: node)

proc newProperty*(key: string): Node =
  ## Creates a new `ntProperty` node, mainly
  ## used for registering key/type/value fields for
  ## classes and interfaces. 
  Node(nt: ntProperty, pKey: key)

proc newProperty*(key: string, ptype: Type, val: Node = nil,
  isReadonly, isStatic = false, accessibility = Accessibility): Node =
  ## Create a new ntProperty property node
  result = Node(nt: ntProperty, pKey: key, `type`: ptype,
      val: val, pReadonly: isReadonly, pStatic: isStatic,
      pAccess: accessibility)

proc newEnum*(id: TokenTuple, fields: EnumTable, exported = false): Node =
  ## Creates a new `enum` node
  Node(nt: ntEnum, enumIdent: id.value, enumFields: fields, enumExport: exported)

proc newInterface*(id: string): Node =
  ## Creates a new `interface` node
  Node(nt: ntInterface, interfaceIdent: id)

proc newCommand*(cmdType: CommandType, cmd: Node, tk: TokenTuple): Node =
  Node(nt: ntCommand, cmdType: cmdType, cmd: cmd, meta: tk.trace)

proc newAccessor*(acctype: NodeType, accStorage: Node): Node =
  ## Create a new accessor node
  discard

proc newFor*(item, items: Node, tk: TokenTuple): Node =
  ## Create a new `ntFor` node
  Node(nt: ntFor, forItem: item, forItems: items, meta: tk.trace)

proc newDot*(lhs: Node, rhs: Node = nil): Node =
  Node(nt: ntDotExpr, lhs: lhs, rhs: rhs, meta: lhs.meta)

proc newBracket*(ident, index: Node): Node =
  Node(nt: ntBracketExpr, bracketIdent: ident, bracketIndex: index, meta: index.meta)

proc newId*(tk: TokenTuple): Node =
  Node(nt: ntIdentifier, identName: tk.value, meta: tk.trace)

proc newId*(identName: string): Node =
  Node(nt: ntIdentifier, identName: identName)

proc newImport*(importPath: string): Node =
  ## Creates a new `ntImport` node.
  Node(nt: ntImport, importPath: importPath)
