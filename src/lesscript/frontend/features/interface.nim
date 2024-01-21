# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

newPrefixProc "parseInterface":
  ## Parse `interface` definition
  let tk = p.curr
  let ident = p.next
  walk p, 2
  result = ast.newInterface(ident.value)
  result.interfaceStmt = ast.newStmtTree()
  expectWalkOrNil tkLC
  while p.curr isnot tkRC:
    var isReadonly, isStatic: bool
    while true:
      if p.curr is tkReadonly:
        isReadonly = true
        walk p
      elif p.curr is tkStatic:
        isStatic = true
        walk p
      else: break
    let field = p.curr
    var node = p.parseKeyType(isStatic, isReadonly)
    expectNotNil node:
      if likely(result.interfaceStmt.stmtNode.tree.hasKey(node.pKey) == false):
        result.interfaceStmt.stmtNode.tree[node.pKey] = node
        if p.curr in {tkComma, tkSColon}:
          walk p
        elif p.curr.line == field.line:
          return nil # error, nested
      else:
        errorWithArgs(duplicateField, field, [field.value])
    do: break
  walk p # tkRC