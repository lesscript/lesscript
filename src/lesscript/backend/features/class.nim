# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

newHandler "handleClass":
  if likely(c.inCurrentScope(node.classIdent, scope) == false):
    var extends: string
    # if node.classExtends.len > 0:
      # extends = spaces(1) & "extends" & spaces(1) & node.classExtends.join(", ")
    write js_class_def(c, node.meta, node.classIdent, extends, "")
    newScope:
      curlyBlock:
        # write class properties
        for propName, propNode in node.properties:
          let
            pStatic = if propNode.pStatic: "static " else: ""            
            pReadonly = if propNode.pReadonly: "#" else: ""
            pValue = c.toString(propNode.pVal, scope, propNode.pType)
          write js_class_prop(c, node.meta, pStatic, pReadonly, $(propNode.pKey), pValue)
          semiColon()
        c.stack(ast.newVar("this", vtConst, node.meta), scope)
        for methNode in node.methods:
          if likely(c.inCurrentScope(methNode.fnIdent, scope) == false):
            if likely(methNode.fnIdent notin ["constructor"]):
              c.stack(methNode, scope)
          else: compileError(redefinitionError, [methNode.fnIdent], node.meta)
        # write class methods
        for methNode in node.methods:
          write js_meth_def(c, methNode.meta, methNode.fnIdent, "")
          newScope:
            curlyBlock:
              for innerNode in methNode.fnBody.stmtNode.list:
                c.transpile(innerNode, scope)
          do: delScope()
      semiColon()
    do:
      delScope()
    c.stack(node, scope)
    return
  compileError(redefinitionError, [node.classIdent], node.meta)