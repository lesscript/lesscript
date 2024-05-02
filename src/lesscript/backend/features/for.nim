# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com


when declared nimc:
  discard
elif declared jsc:
  template whileStmtNode(expr, body: Node) =
    write js_while(c, node.meta, c.getInfix(expr, scope))
    newScope:
      curlyBlock:
        for innerNode in body.stmtNode.list:
          c.transpile(innerNode, scope, returnType)
    do: delScope()

  newHandler handleWhileStmt:
    # Handle `while` statements
    whileStmtNode(node.whileExpr, node.whileBody)

  newHandler handleDoWhileStmt:
    # handle `do {} while(expr) {} statements
    write js_do(c, node.meta)
    block:
      newScope:
        curlyBlock:
          for innerNode in node.doWhileBlock.stmtNode.list:
            c.transpile(innerNode, scope, returnType)
      do: delScope()
    block:
      whileStmtNode(node.doWhileStmt.whileExpr, node.doWhileStmt.whileBody)