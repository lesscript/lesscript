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
  newHandler enumDefinition:
    # Handle `enum` declarations
    if likely(c.inScope(node.enumIdent, scope) == false):
      let enumKeys = toSeq(node.enumFields.keys)
      if enumKeys.len > 0:  
        write js_var_assign(c, node.meta, $(vtConst), node.enumIdent)
        add c.output, "Object.freeze("
        curlyBlock:
          add c.output, js_kv_def(c, node.meta, enumKeys[0], c.toString(node.enumFields[enumKeys[0]], scope))
          for enumKey in enumKeys[1..^1]:
            add c.output, ","
            add c.output, js_kv_def(c, node.meta, enumKey, c.toString(node.enumFields[enumKey], scope))
        add c.output, ")"
        semiColon()
        c.stack(node, scope)
      else: discard # todo enum must have at least one field