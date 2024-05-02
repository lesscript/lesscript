# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

newPrefix parseClassDef:
  ## Parse a new `class` definition
  let tk = p.curr
  walk p
  if p.curr.isIdent:
    let ident = p.curr
    walk p
    result = ast.newClass(ident)
    var implements: bool
    while true:
      if p.curr is tkExtends:
        if likely(result.classExtends.len == 0):
          walk p 
          if p.curr.isIdent:
            result.classExtends.add(p.curr.value)
            walk p
            while p.curr is tkComma:
              walk p
              if p.curr.isIdent and p.curr.value notin result.classExtends:
                result.classExtends.add(p.curr.value)
                walk p
              else: errorWithArgs(duplicateExtend, p.curr, [ident.value, p.curr.value])
          else: return nil
        else: return nil
      elif p.curr is tkImplements:
        if not implements:
          if p.next is tkIdentifier:
            walk p
            result.classImplements.add(p.curr.value)
            walk p
            while p.curr is tkComma:
              walk p
              if p.curr is tkIdentifier:
                if p.curr.value notin result.classImplements:
                  result.classImplements.add(p.curr.value)
                  walk p
                else: errorWithArgs(duplicateImplement, p.curr, [ident.value, p.curr.value])
              else: return nil
          implements = true
        else: return nil
      else: break
    # result.classBody = ast.newStmtTree()
    stmtBody(result.classBody, excludes = {tkImport, tkExport,
        tkVar, tkConst, tkLet, tkClassDef})
    # if p.curr is tkLC:
    #   walk p # tkLC
    #   while p.curr isnot tkRC:
    #     if p.curr is tkEOF:
    #       error(missingRC, p.curr)
    #     var isReadonly, isStatic: bool
    #     if p.curr is tkReadonly:
    #       isReadonly = true
    #       walk p
    #     if p.curr is tkStatic:
    #       isStatic = true
    #       walk p
    #     case p.curr.kind
    #     of tkIdentifier:
    #       if p.next in {tkColon, tkQMark}:
    #         let fieldIdent = p.curr
    #         var propNode = p.parseKeyType(isStatic, isReadonly)
    #         if likely(propNode != nil):
    #           if likely(result.properties.hasKey(propNode.pKey) == false):
    #             result.properties[propNode.pKey] = propNode
    #           else: errorWithArgs(duplicateField, fieldIdent, [fieldIdent.value])
    #         else: return nil
    #       elif p.next is tkLP:
    #         var fnNode = p.parseFunction()
    #         if likely(fnNode != nil):
    #           result.methods.add(fnNode)
    #     # of tkReadonly:
    #       # p.parseKeyType(true, isStatic)
    #     else: return nil
    #   if p.curr is tkRC:
    #     walk p