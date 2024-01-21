# A fast, statically typed Rock'n'Roll language that
# transpiles to Nim lang and JavaScript.
# 
# (c) 2023 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://lesscript.com
#          https://github.com/openpeeps

when defined napibuild:
  import denim
  import std/sequtils
  import ./lesscript/frontend/parser
  import ./lesscript/backend/javascript

  init proc(module: Module) =
    proc parseProgram(path: string) {.export_napi.} =
      var p = parseProgram(readFile(path), path)
      if likely(p.hasErrors == false):
        var c = newCompiler(p.getProgram, env = JSEnv.dev)
        if unlikely(c.hasErrors):
          assert error($(c.logger.errors.toSeq[0]), "LesscriptError")
        return %* c.getOutput
      assert error($(p.logger.errors.toSeq[0], "LesscriptError"))

elif isMainModule:
  import kapsis/commands
  import kapsis/db
  import ./lesscript/cli/[cCommand, execCommand, astCommand]

  App:
    settings(
      mainCmd = "c"
    )

    about:
      "A fast, statically typed Rock'n'Roll language that\ntranspiles to Nim lang & JavaScript.\n"
      "   (c) Made by Humans from OpenPeeps | LGPLv3"
      "   https://lesscript.com"
      "   https://github.com/lesscript"

    commands:
      $ "c" `input` `output` ["release"] 'b':
        ? "Transpile Lesscript to JavaScript"
      $ "exec" `input`:
        ? "Parse a Lesscript file and execute it via JavaScriptCore"
      $ "ast" `input` `output`:
        ? "Generates static binary AST"