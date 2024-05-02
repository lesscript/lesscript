# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

template setVarTypeInline {.dirty.} =
  for inlineVar in varInline:
    inlineVar.valType = implType # set default type to other vars

template parseOtherVars {.dirty.} =
  while p.curr is tkIdentifier and p.curr.pos > tk.pos:
    var otherVar: Node
    let otherIdent = p.curr
    if not isTypedOrDefault and not isArg:
      # parse `a, b, c: int`
      otherVar = ast.newVar(otherIdent, otherIdent)
      otherVar.varType = varType
      varInline.add(otherVar)
      walk p
    elif not isNest and not isArg:
      walk p
      otherVar = p.parseVarIdent(tk, otherIdent, varType, isNest = true)
      varOthers.add(otherVar)
    else:
      setVarTypeInline()
      return ast.newVar(ident, varValue, varType, implType, varInline, tk, valTypeof)

proc parseVarIdent(p: var Parser, tk, ident: TokenTuple,
      varType: VarType, isArg, isUnpack, isNest,
      hasDocType = false, parentNode: Node = nil): Node =
  var
    implType: Type
    varInline, varOthers: seq[Node]
    varValue, valTypeof: Node
    isTypedOrDefault: bool
  while true:
    case p.curr.kind
    of tkColon: # set variable type
      if likely(p.next in litTokens or p.next in {tkIdentifier, tkTypeof}):
        walk p
        if p.curr.kind == tkTypeof:
          walk p
          let id = p.curr
          expectToken p.curr, tkIdentifier:
            implType = id.getType
            walk p
          case implType
          of tAny, tCustom:
            valTypeof = ast.newId(id.value)
            valTypeof.identExtractType = true
          else: discard
          walk p
        else:
          implType = getType(p.curr)
          walk p
          case implType
          of tAny, tCustom:
            valTypeof = ast.newId(p.curr)
            walk p
          of tRange:
            varValue = p.parseRange(p.curr)
          else: discard
      else: walk p; return nil
      isTypedOrDefault = true      
    of tkAssign: # assign a Value node
      walk p
      varValue = p.parseAssignableNode()
      if unlikely(varValue == nil):
        return nil # unexpected token
      if implType == tNone:
        # set type from `varValue` if not provided
        implType = varValue.getType
      isTypedOrDefault = true
    of tkComma, tkSColon:
      # parse other identifiers separated by `,` or `;`
      if isArg: break
      if likely(p.next is tkIdentifier):
        walk p
        parseOtherVars()
      else: return nil # unexpected token
    of tkIdentifier:
      if isArg: break
      if p.curr.isChild(tk):
        parseOtherVars()
      else: break
    else: break
  if unlikely(isTypedOrDefault == false) and not hasDocType:
    error(untypedVariable, tk)
  setVarTypeInline()
  if varValue == nil and varType != vtVar:
    errorWithArgs(immutableNoImplicitValue, tk, [ident.value])
  result = ast.newVar(ident, varValue, varType, implType, varInline, tk, valTypeof)
  if varOthers.len > 0:
    result.varOthers = varOthers

proc parseDestructor(p: var Parser, xVar: TokenTuple, varType: VarType): Node =
  # unpack values from arrays or object
  # properties into distinct variables.
  walk p # tkLB
  result = Node(nt: ntUnpack)
  while p.curr.isIdent(anyIdent = true):
    let varIdent = p.curr
    walk p
    var x = p.parseVarIdent(xVar, varIdent, varType, isUnpack = true)
    expectNotNil x:
      result.unpackTo.add(x)
      casey p.curr, tkComma:
        walk p
  expectWalkOrNil tkRB
  if p.curr is tkAssign:
    walk p
    case p.curr.kind
    of tkIdentifier, tkLB, tkLC:
      result.unpackFrom = p.parse()
    else:
      errorWithArgs(invalidIterator, p.curr, [$(p.curr.getTypeByToken())])

newPrefix parseVar:
  # parse variable declarations, `var`, `let`, `const`
  # todo allow identifiers prefixed with `$`
  let tk = p.curr
  let varType = getVarType(p.curr)
  case p.next.kind
  of tkLB:
    walk p
    result = p.parseDestructor(tk, varType)
  else:
    let ident = p.next
    walk p, 2
    result = p.parseVarIdent(tk, ident, varType)