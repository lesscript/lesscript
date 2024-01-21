# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

newPrefixProc "parseFor":
  let tk = p.curr
  walk p
  expectWalkOrNil tkLP
  case p.curr.kind
  of tkVar, tkLet, tkConst:
    let xVar = p.curr
    let varType = getVarType(p.curr)
    var itemNode: Node
    if unlikely(p.next is tkLB):
      walk p
      itemNode = p.parseDestructor(xVar, varType)
    else:
      itemNode = p.parseVar()
    if p.curr.kind in {tkIn, tkOf}:
      walk p
      var itemsNode = p.parse()
      expectWalkOrNil tkRP
      result = ast.newFor(itemNode, itemsNode, tk)
      stmtBody(result.forBody)
  else: discard
