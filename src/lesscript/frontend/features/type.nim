# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

newPrefix parseTypeDef:
  # parse a `type` definition
  let tk = p.curr
  walk p # tkTypeDef
  if p.curr.isIdent:
    let ident = p.curr
    if p.next is tkAssign:
      walk p, 2
      var typeLit: Type
      result = ast.newTypeDef(ident, nil, tObject)
      if p.curr in litTokens:
        typeLit = getType(p.curr)
        walk p
        if typeLit == tObject:
          stmtTree(result.typeNode)
        result.typeLit = typeLit
      else:
        stmtTree(result.typeNode)
    else: return nil