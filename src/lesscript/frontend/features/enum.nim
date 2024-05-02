# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

newPrefix parseEnum:
  # Parse `enum` declarations
  let tk = p.curr
  if likely(p.next.isIdent):
    let ident = p.next
    walk p, 2
    if likely(p.curr is tkLC):
      walk p
      var enumTable = EnumTable()
      while p.curr is tkIdentifier:
        let fid = p.curr
        if not enumTable.hasKey(p.curr.value):
          walk p
          if p.curr is tkAssign:
            if likely(p.next in {tkInteger, tkString} ):
              walk p
              enumTable[fid.value] = p.parseAssignableNode()
          else:
            enumTable[fid.value] = nil
          if p.curr is tkComma:
            walk p # comma is optional
          else:
            checkIndent(p.prev, p.curr, tkIdentifier)
      if p.curr is tkRC:
        walk p
        result = ast.newEnum(ident, enumTable)