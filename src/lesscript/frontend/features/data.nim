# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

newPrefixProc "parseAnoObject":
  # parse an anonymous object
  let anno = ast.newObject(p.curr)
  walk p # {
  while p.curr.isIdent(anyIdent = true, anyStringKey = true) and p.next.kind == tkColon:
    let fName = p.curr
    if unlikely(p.curr is tkColon):
      return nil
    else: walk p, 2
    if likely(anno.objectItems.hasKey(fName.value) == false):
      var item: Node
      case p.curr.kind
      of tkLB:
        item = p.parseAnoArray()
      of tkLC:
        item = p.parseAnoObject()
      else:
        item = p.getPrefixOrInfix(includes = assgnTokens)
      if likely(item != nil):
        anno.objectItems[fName.value] = item
      else: return
    else:
      errorWithArgs(duplicateField, fName, [fName.value])
    if p.curr is tkComma:
      walk p # next k/v pair
  if likely(p.curr is tkRC):
    walk p
  return anno

newPrefixProc "parseAnoArray":
  # parse an anonymous array
  let tk = p.curr
  walk p # [
  var items: seq[Node]
  while p.curr.kind != tkRB:
    # var item = p.getPrefixOrInfix(includes = assgnTokens)
    var item = p.parseAssignableNode()
    if likely(item != nil):
      add items, item
    else:
      if p.curr is tkLB:
        item = p.parseAnoArray()
        if likely(item != nil):
          add items, item
        else: return # todo error multi dimensional array
      elif p.curr is tkLC:
        item = p.parseAnoObject()
        if likely(item != nil):
          add items, item
        else: return # todo error object construction
      else: return # todo error
    if p.curr is tkComma:
      walk p
  expectWalkOrNil tkRB
  result = ast.newArray(tk, items)