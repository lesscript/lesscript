# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

import std/[strutils, macros, sequtils, os, options]
import ../frontend/[ast, logger]

import pkg/[malebolgia, kapsis/cli]

type
  JSEnv* = enum
    dev, prod

  Compiler* = ref object
    env: JSEnv
    path, output: string
    module: Module
    minify, obfuscate: bool
    globalScope: ScopeTable
    imports: ModuleTable
    logger*: Logger
    strNL: string = "\n"

  CompileHandler = proc(c: Compiler, node: Node, scope: var seq[ScopeTable],
    lhs: Node = nil, returnType: Option[Type] = none(Type)) {.gcsafe.}

#
# Forward declaration
#
proc transpile(c: Compiler, node: Node, scope: var seq[ScopeTable],
  returnType: Option[Type] = none(Type)) {.gcsafe.}

proc handleFunction(c: Compiler, node: Node, scope: var seq[ScopeTable],
    lhs: Node = nil, returnType: Option[Type] = none(Type)) {.gcsafe.}

proc handleCommand(c: Compiler, node: Node,
  scope: var seq[ScopeTable], lhs: Node = nil, returnType: Option[Type] = none(Type)) {.gcsafe.}

proc unpackDotExpr(c: Compiler, node: Node,
  scope: var seq[ScopeTable], rhs: Node = nil): string {.gcsafe.}

proc unpackBracketExpr(c: Compiler, node: Node,
  scope: var seq[ScopeTable]): string {.gcsafe.}

proc walkAccessor(c: Compiler, lhs, rhs: Node,
  acc: var seq[string], scope: var seq[ScopeTable]): Node {.gcsafe.}

proc callDefinition(c: Compiler, node: Node,
  scope: var seq[ScopeTable], lhs: Node = nil, returnType: Option[Type] = none(Type)) {.gcsafe.}

proc toString(c: Compiler, node: Node, scope: var seq[Scopetable],
  implType: Type = tNone, safeUseIdent = false): string {.gcsafe.}

proc getInfix(c: Compiler, node: Node, scope: var seq[ScopeTable]): string

#
# Compile-time utils
#
const jsc = true 

include ../utils

macro js(x, y: untyped) =
  var jsStmt = macros.newStmtList() 
  result = macros.newStmtList()
  y[3] = nnkFormalParams.newTree(
    ident("string"),
    nnkIdentDefs.newTree(ident("c"), ident("Compiler"), newEmptyNode()),
    nnkIdentDefs.newTree(ident("meta"), ident("Meta"), newEmptyNode()),
    nnkIdentDefs.newTree(
      ident("args"),
      nnkBracketExpr.newTree(ident("varargs"), ident("string")),
      newEmptyNode()
    ),
  )
  jsStmt.add quote do:
    `x` % args
    # add c.output, `x` % args
  y[^1] = jsStmt
  result.add(y)

# JS Emitters
proc js_strict         {.js: "\"use strict\";\n", .}
proc js_console_log    {.js: "console.$1".}
proc js_var_definition {.js: "$1 $2;".}
proc js_var_assignment {.js: "$1 $2=$3;".}
proc js_var_assign     {.js: "$1 $2=".}
proc js_reassign       {.js: "$2=".}
proc js_assignment     {.js: "$1=$2".}
proc js_class_def      {.js: "class $1$2$3".}
proc js_class_prop     {.js: "$1$2$3=$4".} # static #name = "John"
proc js_meth_def       {.js: "$1($2)".}
proc js_func_def       {.js: "function $1($2)".}
proc js_func_return    {.js: "return $1;".}
proc js_func_call      {.js: "$1($2)".}
proc js_ident_call     {.js: "$1".}
proc js_type_def       {.js: "const $1 = $2;".}
proc js_if_def         {.js: "if($1)".}
proc js_elif_def       {.js: "else if($1)".}
proc js_else_def       {.js: "else".}
proc js_infix          {.js: "$1".}
proc js_while          {.js: "while($1)".}
proc js_do             {.js: "do".}
proc js_kv_def         {.js: "$1:$2".}
proc js_arr_def        {.js: "[$1]".}
proc js_dot_def        {.js: "$1.$2".}
proc js_doc_comment    {.js: "\n/**\n *$1/\n".}
proc js_doc_param      {.js: "{$1}$2 $3\n *".}
proc js_prefix         {.js: "$1 ".}
proc js_par_group      {.js: "($1)".}
proc js_par_start      {.js: "(".}
proc js_par_end        {.js: ");".}

macro newHandler(name, body: untyped) =
  expectKind(name, nnKident)
  newProc(name,
    [
      newEmptyNode(),
      nnkIdentDefs.newTree(ident("c"), ident("Compiler"), newEmptyNode()),
      nnkIdentDefs.newTree(ident("node"), ident("Node"), newEmptyNode()),
      nnkIdentDefs.newTree(
        ident("scope"),
        nnkVarTy.newTree(nnkBracketExpr.newTree(ident("seq"), ident("ScopeTable"))),
        newEmptyNode()
      ),
      nnkIdentDefs.newTree(ident("lhs"), ident("Node"), newNilLit()),
      nnkIdentDefs.newTree(
        ident("returnType"),
        nnkBracketExpr.newTree(
          ident("Option"),
          ident("Type")
        ),
        newCall(ident("none"), ident("Type"))
      )
    ],
    body = body,
    pragmas = nnkPragma.newTree(ident("gcsafe"))
  )

macro casey(casex, kind, body: untyped, elseBody: untyped = nil) =
  ## Generate a `case` statement with a single `of` branch.
  ## When `elseBody` is `nil` will insert a `discard` statement 
  result = macros.newStmtList()
  var elseStmt =
    if elseBody.kind == nnkNilLit:
      nnkDiscardStmt.newTree(newEmptyNode())
    else:
      elseBody
  result.add(
    nnkCaseStmt.newTree(
      casex,
      nnkOfBranch.newTree(kind, body),
      nnkElse.newTree(
        macros.newStmtList(elseStmt)
      )
    )
  )

template write(x: untyped) = c.output.add(x)
template semiColon = c.output.add(";")
template colon = c.output.add(",")
template curlyBlock(x: untyped): untyped =
  add c.output, "{"
  # add c.output, c.strNL
  `x`
  # add c.output, c.strNL
  add c.output, "}"

template squareBlock(x: untyped): untyped  =
  add c.output, "["
  `x`
  add c.output, "]"


#
# Scope API
#
include ./scope

proc jsType(t: Type): string =
  case t:
  of tString, tObject, tArray, tVoid, tAny: $t
  of tInt, tFloat, tFloat32, tFloat64: "number" # todo
  of tBool: "boolean"
  else: ""

#
# Type Checker
#
proc typeCheckCallable(c: Compiler, scopedNode, rhs, lhs: Node, rhsIdent: string): bool =
  if likely(scopedNode != nil):
    case lhs.valTypeof.identType
      of tNone:
        discard
        # lhs.valTypeof.identType = scopedNode.getType
      else:
        if unlikely(lhs.valTypeof.identType != scopedNode.getType):
          return false
    var identType: string
    case scopedNode.getType
      of tClass:    identType = scopedNode.classIdent
      of tFunction: identType = scopedNode.fnIdent
      of tCustom: discard
      else: discard
    if identType.len > 0:
      if likely(lhs.valTypeof.identName == identType):
        return true
      compileError(fnMismatchParam, [lhs.varIdent, identType, lhs.valTypeof.identName], rhs.meta)
  compileError(undeclaredIdent, [rhsIdent], rhs.meta)

proc typeCheck(c: Compiler, expected: Type, node: Node,
                scope: var seq[ScopeTable]): (bool, Type, Type) =
  case node.nt
  of ntValue:
    result = (node.val.vt == expected, node.val.vt, expected) 
  of ntCall:
    let scopedNode = c.scoped(node.callIdent, scope)
    if likely(scopedNode != nil):
      case scopedNode.nt
      of ntVarDecl:
        result = (scopedNode.valType == expected, scopedNode.valType, expected)
      else: discard
  else: discard

proc typeCheck(c: Compiler, nodeA, nodeB: Node, scope: var seq[ScopeTable]): bool =
  case nodeA.valType
  of tBool, tInt, tFloat, tString:
    let a = nodeA.getType
    var b: Type
    case nodeB.nt
    of ntCall:
      let some = c.getScope(nodeB.callIdent, scope)
      if likely(some.scopeTable != nil):
        b = some.scopeTable[nodeB.callIdent].getType
      else:
        compileError(undeclaredIdent, [nodeB.callIdent], nodeB.meta)
    else:
      b = nodeB.getType
    if likely(a == b): return true
    compileError(fnMismatchParam, [nodeA.varIdent, $(a), $(b)], nodeB.meta)
  else: discard

proc typeExpect(c: Compiler, node: Node, expectType: Type, scope: var seq[ScopeTable]): bool =
  var got: Type
  case node.nt
  of ntVarDecl:
    case node.valType
    of tBool, tInt, tFloat, tString:
      got = node.getType
    else: discard # todo
  of ntValue:
    got = node.val.vt
  of ntInfix:
    got = tbool
  of ntInfixMath:
    got = tInt # todo determine the restult from math infix
  else: discard # todo
  if unlikely(expectType != got):
    compileError(typeMismatch, [$got, $expectType], node.meta)
  result = true

proc typeCheck2(c: Compiler, lhs, rhs: Node,
    scope: var seq[ScopeTable]): bool =
  case lhs.valType
  of tNone:
    # set as `tNone` when the assigned value is an
    # identifier that can't be known at parser level,
    # in this case we'll have to determine the type of `x`
    # `var x = y` by looking for `y` in the available
    # scope tables.
    discard
  of tCustom:
    case rhs.nt
    of ntCall:
      var scopedNode = c.scoped(rhs.callIdent, scope)
      return c.typeCheckCallable(scopedNode, rhs, lhs, rhs.callIdent)
    of ntClassDef:
      if likely(not c.inScope(rhs.classIdent, scope)):
        return c.typeCheckCallable(rhs, rhs, lhs, rhs.classIdent)
      else:
        compileError(redefineIdent, [rhs.classIdent], rhs.meta)
    else:
      let rhsType = rhs.getType
      case rhs.getType
      of tString, tInt, tFloat:
        if likely(lhs.valTypeof.identType == rhsType):
          return true
        compileError(fnMismatchParam, [lhs.varIdent,
          $(rhsType), lhs.valTypeof.identName], rhs.meta)
      else:
        echo rhsType
      # case rhsType
      # of ntValue:
      #   echo rhsType
      # of ntVarDecl: 
      #   case lhs.valTypeof.identType:
      #   of tNone:
      #     if likely(lhs.valType == rhsType):
      #       return true
      #   else:
      #     if likely(lhs.valTypeof.identType == rhsType):
      #       return true
      #   compileError(fnMismatchParam, [lhs.varIdent,
      #     $(rhsType), lhs.valTypeof.identName], rhs.meta)
      # else: discard # todo?
  else:
    case rhs.nt
    of ntCall:
      var scopedNode = c.scoped(rhs.callIdent, scope)
      if likely(scopedNode != nil):
        let rhsType = scopedNode.getType
        if lhs.valTypeof != nil:
          if unlikely(lhs.valTypeof.identType == rhsType):
            return true
          compileError(fnMismatchParam, [lhs.varIdent,
            $(rhsType), $(lhs.valTypeof.identType)], rhs.meta)
          return false
        let lhstype = lhs.getType
        if likely(lhstype == rhsType):
          return true
        compileError(fnMismatchParam, [lhs.varIdent,
          $(rhsType), $(lhstype)], rhs.meta)
      compileError(undeclaredIdent, [rhs.callIdent], rhs.meta)
    else:
      let lhstype = lhs.getType
      let rhstype = rhs.getType
      if likely(lhstype == rhstype):
        return true
      compileError(fnMismatchParam, [lhs.varIdent,
        $(rhstype), $(lhstype)], rhs.meta)

#
# Type Checkers
#

proc typeCheckAssign(c: Compiler, node: Node, scope: var seq[ScopeTable]): bool =
  # Ensures type matching for assignment and variable declarations
  assert node.nt == ntVarDecl
  var
    valNode, typeofNode: Node
    trace: Meta
    rhsIdentStr: string
  if node.varValue == nil:
    # handle typed variables without an implicit value
    if node.valTypeof != nil:
      valNode = c.scoped(node.valTypeof.identName, scope)
      rhsIdentStr = node.valTypeof.identName
      trace = node.valTypeof.meta
    else: return true # nothing to check `var x: string` 
  else:
    # handle implicit value
    trace = node.varValue.meta
    if node.valTypeof != nil:
      typeofNode = c.scoped(node.valTypeof.identName, scope)
      node.valTypeof.identType = getType(typeofNode)
    case node.varValue.nt
    of ntCall:
      valNode = c.scoped(node.varValue.callIdent, scope)
      rhsIdentStr = node.varValue.callIdent
    else:
      valNode = node.varValue
  expectNode valNode, rhsIdentStr, trace:
    case node.valType
    of tNone:
      # untyped variables inherit the type from the assigned value
      node.valType = getType(valNode)
      return true
    of tCustom:
      case valNode.nt
      of ntTypeDef:
        discard # ok
      else:
        if likely(node.valTypeof != nil):
          node.valTypeof.identType = getType(valNode)
          if node.valTypeof.identExtractType:
            # retrieves type of rhs variable using `typeof` prefix. 
            if typeofNode != nil:
              # using `typeof` prefix followed by assignment
              # requires a double check
              expectMatch node.valTypeof.identType,
                getType(valNode), node.valTypeof.identName, valNode.meta:
                  node.valType = getType(valNode)
                  return true
            node.valType = getType(valNode)
            return true
        compileError(typeExpected, [$valNode.nt], node.meta)
    else:
      expectMatch node.valType, getType(valNode)
#
# Writers - Infix 
#
template checkInfixOp(node: Node, infixOp: InfixOp) =
  let valType = node.getType
  case infixOp
  of LT, LTE, GT, GTE:
    if unlikely(valType notin {tInt, tFloat}):
      compileError(invalidInfixOp, [$infixOp, $valType], node.meta)
  else: discard

proc getInfix(c: Compiler, node: Node, scope: var seq[ScopeTable]): string =
  case node.nt
  of ntInfix:
    var lhs = node.lhsInfix
    var rhs = node.rhsInfix
    case lhs.nt
    of ntValue:
      checkInfixOp(lhs, node.infixOp)
      result = c.toString(lhs, scope, safeUseIdent = true)
    of ntCall:
      let lid = lhs.callIdent
      lhs = c.scoped(lid, scope)
      expectNode lhs, lid, node.lhsInfix.meta:
        checkInfixOp(lhs, node.infixOp)
        result = c.toString(node.lhsInfix, scope, safeUseIdent = true)
    of ntBracketExpr:
      let lid = lhs.bracketIdent.callIdent
      lhs = c.scoped(lid, scope)
      expectNode lhs, lid, node.lhsInfix.meta:
        checkInfixOp(lhs, node.infixOp)
        result = c.toString(node.lhsInfix, scope, safeUseIdent = true)
        # todo, a string var `a[0]` should return a `tChar`
        # in JS backend translates to `a.charAt(0)`
    of ntInfix:
      add result, c.getInfix(lhs, scope)
    else: discard # todo
    add result, $node.infixOp
    case rhs.nt
    of ntValue:
      checkInfixOp(rhs, node.infixOp)
      case lhs.nt
      of ntInfix: discard # lhs is a separate group
      else:
        expectMatchInfix lhs.getType, rhs.getType:
          add result, c.toString(node.rhsInfix, scope, safeUseIdent = true)
        do: compileError(typeMismatch, [$rhs.getType, $lhs.getType], rhs.meta)
    of ntCall:
      let rid = node.rhsInfix.callIdent
      rhs = c.scoped(rid, scope)
      expectNode rhs, rid, node.rhsInfix.meta:
        expectMatchInfix lhs.getType, rhs.getType:
          add result, c.toString(node.rhsInfix, scope, safeUseIdent = true)
        do:
          compileError(typeMismatch, [$rhs.getType, $lhs.getType], rhs.meta)
    of ntBracketExpr:
      echo "todo ntBracketExpr"
    of ntInfix:
      add result, c.getInfix(node.rhsInfix, scope)
    else: discard # todo
  of ntValue:
    result = c.toString(node, scope)
  else: discard

proc getInfixMath(c: Compiler, node: Node, scope: var seq[ScopeTable]): string =
  result = c.toString(node.lhsMath, scope)
  result.add($node.infixMathOp)
  result.add(c.toString(node.rhsMath, scope))

#
# Writers - Storage
#

proc writeArray(c: Compiler, node: Node,
    scope: var seq[ScopeTable]): string =
  ## Unpack array to string
  add result, "["
  if node.arrayItems.len > 0:
    add result, c.toString(node.arrayItems[0], scope)
    node.arrayType = node.arrayItems[0].getType
    for item in node.arrayItems[1..^1]:
      if unlikely(node.arrayType != item.getType):
        compileError(arrayMixedTypes, node.meta)
        break
      add result, ","
      add result, c.toString(item, scope)
  add result, "]"

proc writeObject(c: Compiler, node: Node,
    scope: var seq[ScopeTable], endSemiColon = false): string =
  ## Unpack object to string
  add result, "{"
  var i = 0
  let len = node.objectItems.len - 1
  for k in node.objectItems.keys:
    add result, js_kv_def(c, node.meta, k, c.toString(node.objectItems[k], scope))
    if i != len:
      add result, ","
    inc i
  add result, "}"
  if endSemiColon:
    add result, ";"

proc walkAccessor(c: Compiler, lhs, rhs: Node,
    acc: var seq[string], scope: var seq[ScopeTable]): Node =
  var
    lhs = lhs
    rhs = rhs
  case lhs.nt
  of ntCall:
    acc.add(lhs.callIdent)
    lhs = c.scoped(lhs.callIdent, scope)
    if likely(lhs != nil):
      case lhs.nt
      of ntVarDecl:
        return c.walkAccessor(lhs.varValue, rhs, acc, scope)
      of ntEnum:
        if likely(rhs.nt == ntCall):
          if likely(rhs.callType == identCall):
            if likely(lhs.enumFields.hasKey(rhs.callIdent)):
              acc.add(rhs.callIdent)
              return lhs.enumFields[rhs.callIdent]
            else:
              compileError(undeclaredField, [rhs.callIdent], rhs.meta)
      else: discard
    else: compileError(undeclaredIdent, [lhs.callIdent], lhs.meta)
  of ntDotExpr:
    result = c.walkAccessor(lhs.lhs, lhs.rhs, acc, scope)
    if likely(result != nil):
      return c.walkAccessor(result, rhs, acc, scope)
  of objectDecl:
    var propKey: string
    case rhs.nt
    of ntCall:
      propKey = rhs.callIdent
    of ntValue:
      if likely(rhs.val.vt == tString):
        propKey = rhs.val.vStr
        acc.add(".")
      else: return nil
    else: discard
    if likely(lhs.objectItems.hasKey(propKey)):
      acc.add(propKey)
      return lhs.objectItems[propKey]
    else: compileError(undeclaredField, [propKey], rhs.meta)
  of arrayDecl:
    if lhs.arrayItems.len > 0 and rhs != nil:
      let high = lhs.arrayItems.high
      case rhs.nt
      of ntValue:
        if likely(rhs.getType == tInt):
          # if likely(high >= rhs.val.vInt):
          acc.add("[" & $(rhs.val.vInt) & "]")
          # return lhs.arrayItems[rhs.val.vInt]
          # else:
            # compileError(indexDefect, [$(rhs.val.vInt), "0", $(high)], rhs.meta)
        else:
          compileError(invalidAccessor, [$(rhs.getType), $(tArray)], rhs.meta)
      of ntBracketExpr:
        echo rhs
      of ntCall:
        var rhsNode = c.scoped(rhs.callIdent, scope)
        if likely(rhsNode != nil):
          casey rhsNode.valType, tInt:
            if likely(high >= rhsNode.varValue.val.vInt):
              acc.add("[" & $(rhs.callIdent) & "]")
              return lhs.arrayItems[rhsNode.varValue.val.vInt]
            else: compileError(indexDefect, [$(rhsNode.varValue.val.vInt), "0", $(high)], rhs.meta)
          do:
            compileError(invalidAccessor, [$(rhsNode.valType), $(tArray)], rhs.meta)
        else:
          compileError(undeclaredIdent, [rhs.callIdent], rhs.meta)
      else: discard
    else: discard
  of ntBracketExpr:
    result = c.walkAccessor(lhs.bracketIdent, lhs.bracketIndex, acc, scope)
    if likely(result != nil):
      return c.walkAccessor(result, rhs, acc, scope)
  of ntValue:
    if unlikely(rhs != nil):
      casey lhs.val.vt, tString: 
        casey rhs.val.vt, tInt:
          acc.add(".charAt(" & $(rhs.val.vInt) & ")")
          return lhs
      do: compileError(invalidAccessor, [$(rhs.getType), $(lhs.getType)], rhs.meta)
  else: discard

proc unpackDotExpr(c: Compiler, node: Node, scope: var seq[ScopeTable], rhs: Node = nil): string =
  var acc: seq[string]
  discard c.walkAccessor(node.lhs, node.rhs, acc, scope)
  result = acc.join(".")

proc unpackBracketExpr(c: Compiler, node: Node, scope: var seq[ScopeTable]): string =
  var acc: seq[string]
  discard c.walkAccessor(node.bracketIdent, node.bracketIndex, acc, scope)
  result = acc.join("")

proc getImplDefault(implType: Type): string =
  ## Returns default implicit value of `implType`
  case implType:
    of tBool:   "false"
    of tString: "\"\""
    of tInt:    "0"
    of tArray:  "[]"
    of tObject: "{}"
    of tFloat:  "0.0"
    of tClass, tFunction: "null"
    else: "null"

proc getImpl(x: Node, implType: Type): string =
  ## Returns value of `x` or default implicit value
  case x.val.vt
  of tBool:
    $(x.val.vBool)
  of tFloat:
    $(x.val.vFloat)
  of tInt:
    $(x.val.vInt)
  of tString:
    "\"" & x.val.vStr & "\""
  else: ""

proc toString(c: Compiler, node: Node, scope: var seq[ScopeTable],
    implType: Type = tNone, safeUseIdent = false): string {.gcsafe.} =
  if unlikely(node == nil):
    return getImplDefault(implType)
  case node.nt:
  of ntValue:
    result = node.getImpl(implType)
  of arrayDecl:
    result = c.writeArray(node, scope)
  of objectDecl:
    result = c.writeObject(node, scope)
  of ntDotExpr:
    result = c.unpackDotExpr(node, scope)
  of ntBracketExpr:
    result = c.unpackBracketExpr(node, scope)
  of ntCall:
    if safeUseIdent:
      result = node.callIdent
    else:
      var scopedNode = c.scoped(node.callIdent, scope)
      if likely(scopedNode != nil):
        return node.callIdent
      compileError(undeclaredIdent, [node.callIdent], node.meta)
  else: discard

proc genCommentFnParam(c: Compiler, node: Node): string =
  # Generates documentation comments for functions, classes, class methods,
  # and variable declarations when `JSEnv` is set to `prod`.
  # todo `--no:comments` flag to to disable this feature
  var ident = indent(node.varIdent, 1)
  let defaults =
      if node.varValue != nil:
        ident = ""
        "[$1=$2]" % [node.varIdent, getImpl(node.varValue, node.valType)]
      else: ""
  add result, indent("@param" & spaces(2), 1)
  if node.valTypeof == nil:
    add result, c.js_doc_param(node.meta, jsType(node.valType), ident, defaults)
  else:
    case node.valTypeof.identType
    of tGeneric:
      add result, c.js_doc_param(node.meta, jsType(node.valType), ident, defaults)
    else:
      add result, c.js_doc_param(node.meta, node.valTypeof.identName, ident, defaults)

proc genCommentFnReturn(c: Compiler, returnType: Type): string =
  # Generates the return type of a function
  result = " @return {$1}\n *" % [returnType.jsType]  

features "literal", "var", "assign", "data", "for",
          "type", "enum", "interface", "function", "class",
          "command", "condition", "comment"

#
# Handles `type` definitions
#
newHandler handleTypeDef:
  if (not c.inScope(node.typeIdent, scope)):
    c.stack(node, scope)
  else: compileError(redefinitionError, [node.typeIdent], node.meta)

#
# Handle calls 
#

newHandler callDefinition:
  let some = c.getScope(node.callIdent, scope)
  if unlikely(some.scopeTable == nil):
    compileError(undeclaredIdent, [node.callIdent], node.meta)
  let
    fnNode = some.scopeTable[node.callIdent]
    fnParams = fnNode.fnParams.keys.toSeq
  var asgnValArgs: seq[Node]
  var args: seq[string]
  if node.callArgs.len == fnNode.fnParams.len:
    var skippable: seq[string]
    for i in 0..node.callArgs.high:
      let arg = node.callArgs[i]
      if arg.argName.len > 0:
        # checking for named arguments
        if fnNode.fnParams.hasKey(arg.argName):
          let param = fnNode.fnParams[arg.argName]
          if likely(c.typeCheck(param, arg.argValue, scope)):
            add skippable, arg.argName
            if arg.argValue != nil:
              add args, c.toString(arg.argValue, scope)
            else:
              add args, arg.argName
        else:
          compileError(fnUnknownParam,
            [arg.argName], arg.argValue.meta)
      else:
        let param = fnNode.fnParams[fnParams[i]]
        debugEcho arg.argValue
        if likely(c.typeCheck(param, arg.argValue, scope)):
          if arg.argValue != nil:
            add args, c.toString(arg.argValue, scope)
          else:
            add args, arg.argName
  # transpile to JavaScript
  write js_func_call(c, node.meta, node.callIdent, args.join(","))

newHandler callDefinition2:
  #  function/class calls
  var scopedNode = c.scoped(node.callIdent, scope)
  if likely(scopedNode != nil):
    case node.callType:
    of fnCall, classCall:
      let len = node.callArgs.len
      if len > 0:
        var params = scopedNode.fnParams
        var seqParams = params.keys.toSeq
        for arg in node.callArgs:
          if arg.argName.len > 0:
            let pos = seqParams.find(arg.argName)
            if likely(pos != -1):
              let pNode = scopedNode.fnParams[arg.argName]
              if likely(c.typeCheck(pNode, arg.argValue, scope)):
                params[arg.argName].varValue = arg.argValue
                seqParams.del(pos)
              else:
                compileError(fnMismatchParam, [arg.argName,
                  $(arg.argValue.getType), $(pNode.getType)], arg.argValue.meta)
            else:
              compileError(fnUnknownParam, [arg.argName], arg.argValue.meta)
          else:
            try:
              let pNode = scopedNode.fnParams[seqParams[0]]
              if likely(c.typeCheck(pNode, arg.argValue, scope)):
                params[seqParams[0]].varValue = arg.argValue
              else:
                compileError(fnMismatchParam, [seqParams[0],
                  $(arg.argValue.getType), $(pNode.getType)], arg.argValue.meta)
            except KeyError:
              compileError(fnExtraArg, [node.callIdent, $(params.len), $(len)], arg.argValue.meta)
        var args: seq[string]
        for pName, pNode in params:
          args.add(c.toString(pNode.varValue, scope, safeUseIdent = true))
        write js_func_call(c, node.meta, node.callIdent, args.join(","))
        reset(args)
        reset(params)
      else:
        if node.callType == fnCall:
          write js_func_call(c, node.meta, node.callIdent, "")
        else:
          write js_func_call(c, node.meta, "new " & node.callIdent, "")
    else:
      if lhs != nil:
        lhs.valType = scopedNode.valType
        # echo lhs
      write js_ident_call(c, node.meta, node.callident)
    semiColon()
  else:
    compileError(undeclaredIdent, [node.callIdent], node.meta)

newHandler handleBlockStmt:
  newScope:
    write "{"
    for n in node.stmtNode.list:
      c.transpile(n, scope)
    write "}"
  do: delScope()

proc transpile(c: Compiler, node: Node,
    scope: var seq[ScopeTable], returnType: Option[Type] = none(Type)) {.gcsafe.} =
  let compileHandler: CompileHandler =
    case node.nt
    of ntVarDecl:     handleVarDecl
    of ntCommand:     handleCommand
    of ntFuncDef:     handleFunction
    of ntAssign:      handleVarAssign
    of ntIf:          handleCond
    of ntClassDef:    handleClass
    of ntTypeDef:     handleTypeDef
    of ntEnum:        enumDefinition
    of ntCall:        callDefinition
    of ntStmt:        handleBlockStmt
    of ntWhile:       handleWhileStmt
    of ntDoWhile:     handleDoWhileStmt
    else: nil

  # Handles function/class calls    else: nil
  if likely(compileHandler != nil):
    c.compileHandler(node, scope, nil, returnType)

#
# Public API
#
proc hasErrors*(c: Compiler): bool =
  c.logger.errorLogs.len > 0

proc hasWarnings*(c: Compiler): bool =
  c.logger.warnLogs.len > 0

proc getOutput*(c: Compiler): string = c.output

proc transpileModule(m: MasterHandle, fpath: string,
    module: Module, outputPath, basedir: string) {.gcsafe.} =
  var fpath = basedir / fpath
  var c = Compiler(module: module, logger: Logger(filepath: fpath),
            path: fpath, globalScope: ScopeTable())
  var localScope = newSeq[ScopeTable]()
  for i in 0..c.module.nodes.high:
    c.transpile(c.module.nodes[i], localScope)
  if unlikely(c.hasErrors):
    display("Build failed with errors:")
    for error in c.logger.errors:
      display(error)
    display(" 👉 " & c.logger.filePath)
    reset(c.output)
    m.cancel()
  else:
    writeFile(outputPath, c.getOutput)

proc newCompiler*(p: Module, minify, obfuscate = false,
        env: JSEnv = JSEnv.dev): Compiler =
  ## Creates a new instance of `Compiler` with given `Module`
  var c = Compiler(module: p, logger: Logger(filepath: p.path),
            path: p.path, minify: minify, obfuscate: obfuscate,
            env: env, globalScope: ScopeTable())
  if env == prod:
    setLen(c.strNL, 0)
  var localScope = newSeq[ScopeTable]()
  # write c.js_strict((0, 0))
  if c.module.imports.len > 0:
    var m = createMaster()
    let basedir = parentDir(p.path)
    m.awaitAll:
      for fpath, programNode in c.module.imports:
        let outputPath = fpath.parentDir / "_" & fpath.extractFilename.changefileExt("js")
        m.spawn transpileModule(m.getHandle, fpath, programNode, outputPath, basedir)
  for i in 0..c.module.nodes.high:
    c.transpile(c.module.nodes[i], localScope)
  result = c
  if unlikely(c.hasErrors):
    reset(c.output)