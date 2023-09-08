# A fast, statically typed Rock'n'Roll language that
# transpiles to Nim lang and JavaScript.
# 
# (c) 2023 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://lesscript.com
#          https://github.com/openpeeps

when defined napi:
  import denim
  import std/sequtils
  import ./lesscript/[parser, compiler]

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
  import ./lesscript/cli/[cCommand, astCommand]

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
      $ "c" `input` `output` ["prod"]:
        ? "Transpiles code to JavaScript"
      $ "ast" `input` `output`:
        ? "Generates static binary AST"