# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

newPrefix parseKeyType:
  # Parse pairs of `key: value` or `key: type = value`
  result = ast.newProperty(p.curr.value)
  while true:
    if p.curr is tkReadonly:
      result.pReadonly = true; walk p
    elif p.curr is tkStatic:
      result.pStatic = true; walk p
    else: break
  result.meta = p.curr.trace
  if likely((p.curr in {tkIdentifier, tkString} or
      p.curr.value.validIdentifier) and p.next in {tkColon, tkQMark}
    ):
    walk p
    if p.curr is tkQMark:
      result.pOptional = true
      walk p # tkQMark
      if p.curr is tkColon: walk p
      else: return nil
    else:
      walk p
    if likely(p.curr in litTokens or p.curr is tkIdentifier):
      let pTypeIdent = p.curr
      result.pType = p.curr.getType
      walk p
      if p.curr is tkAssign:
        if p.next in assgnTokens:
          walk p
          result.pVal = p.parseAssignableNode()
        else: return nil # non assignnable node
      if result.pType == tCustom:
        result.pIdent = pTypeIdent.value

newPrefix parseInterface:
  ## Parse `interface` definition
  let tk = p.curr
  let ident = p.next
  walk p, 2
  result = ast.newInterface(ident.value)
  result.meta = p.prev.trace
  # result.interfaceStmt = ast.newStmtTree()
  stmtBody(result.interfaceStmt)
  expectNotNil result.interfaceStmt:
    discard