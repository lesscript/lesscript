# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

import std/[os, monotimes, times, tables, strutils]

import ../frontend/[parser, ast]
import ../backend/javascript

import ./utils

import pkg/[flatty, supersnappy]
import pkg/kapsis/[runtime, cli]

proc runCommand*(v: Values) =
  init()
  if not path.endsWith(".ast"):
    p = parseModule(readFile(path), path)
    if p.hasErrors:
      display("Build failed with errors")
      for error in p.logger.errors:
        display(error)
      display(" 👉 " & p.logger.filePath)
      QuitFailure.quit
    c = newCompiler(p.getModule(), env = env)
  else:
    c = newCompiler(fromFlatty(path.readFile, Module), env = env)
  if unlikely(c.hasErrors):
    # check for errors at compile time
    display("Build failed with errors:")
    for error in c.logger.errors:
      display(error)
    display(" 👉 " & c.logger.filePath)
    QuitFailure.quit

  if c.hasWarnings:
    for warning in c.logger.warnings:
      display(warning)
    display(" 👉 " & c.logger.filePath)

  let total = $(getMonotime() - t)
  if hasOutput:
    writeFile(outputPath, c.getOutput)
    if v.flag("b"):
      display("Done in " & total)
  else:
    echo c.getOutput
  QuitSuccess.quit