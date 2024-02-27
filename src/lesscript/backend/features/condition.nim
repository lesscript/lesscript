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
  #
  # Transpiler - Handle Conditional Statements
  #
  newHandler handleCond:
    if unlikely(node.ifBranch.body.stmtNode.list.len == 0):
      compileWarning(emptyBlockStatement, ["if"], node.meta)
    write js_if_def(c, node.meta, c.getInfix(node.ifBranch.cond, scope))
    newScope:
      curlyBlock:
        for innerNode in node.ifBranch.body.stmtNode.list:
          c.transpile(innerNode, scope, returnType)
    do: delScope()
    # handle `elif` branches
    for elifBranch in node.elifBranch:
      if unlikely(elifBranch.body.stmtNode.list.len == 0):
        compileWarning(emptyBlockStatement, ["elif"], elifBranch.body.meta)
      write js_elif_def(c, node.meta, c.getInfix(elifBranch.cond, scope))
      newScope:
        curlyBlock:
          for innerNode in elifBranch.body.stmtNode.list:
            c.transpile(innerNode, scope, returnType)
      do: delScope()
    # handle `else` branch
    if node.elseBranch != nil:
      if unlikely(node.elseBranch.stmtNode.list.len == 0):
        compileWarning(emptyBlockStatement, ["else"], node.elseBranch.meta)
      write js_else_def(c, node.meta)
      newScope:
        curlyBlock:
          for innerNode in node.elseBranch.stmtNode.list:
            c.transpile(innerNode, scope, returnType)
      do: delScope()