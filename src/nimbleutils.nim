import strutils, sequtils

when nimvm: discard
else: import osproc

type
  Backend = enum C = "c", Cc = "cc", Cpp = "cpp", Objc = "objc", Js = "js"
  VersionSelector = enum
    Equal = "==", SmallerThan = "<", LargerThan = ">", LargerOrEqual = ">=",
    SmallerOrEqual = "<=", Semver = "^=", Similar = "~=",
    Any = "any"
  Version = object
    major: int
    minor: int
    patch: int
    extras: seq[int]
    tag: string
  Dependency = object
    name: string
    version: Version
    versionSelector: VersionSelector
  NimblePkg = object
    name: string
    version: Version
    author: string
    description: string
    license: string
    skipDirs: seq[string]
    skipFiles: seq[string]
    skipExt: seq[string]
    installDirs: seq[string]
    installFiles: seq[string]
    installExt: seq[string]
    srcDir: string
    binDir: string
    bin: seq[tuple[name, sourceName: string]]
    backend: Backend
    requires: seq[Dependency]

proc nimbleDump(package: string): tuple[output: string, exitCode: int] =
  when nimvm:
    gorgeEx("nimble dump " & package)
  else:
    execCmdEx("nimble dump " & package)

proc parseVersion(version: string): Version =
  let split = version.split(".")
  result.major = -1
  result.minor = -1
  result.patch = -1
  if split.len > 0:
    try:
      result.major = split[0].parseInt
    except:
      result.tag = split[0]
  if split.len > 1: result.minor = split[1].parseInt
  if split.len > 2: result.patch = split[2].parseInt
  if split.len > 3: result.extras = split[3..^1].mapIt(it.parseInt)

proc parseDependency(dependency: string): Dependency =
  let split = dependency.split
  result.name = split[0]
  if split.len == 3:
    result.versionSelector = parseEnum[VersionSelector](split[1])
    if result.versionSelector != Any:
      result.version = parseVersion(split[2])
    else:
      result.version = parseVersion(split[1]) # Set version to all negative numbers with tag "any"
  else:
    result.version = parseVersion(split[1])

proc parseDependencies(dependencies: string): seq[Dependency] =
  dependencies.split(",").mapIt(it.strip.parseDependency)

proc addBins(pkg: var NimblePkg, bins: string) =
  let bins = bins.split(",").mapIt(it.strip)
  var toAdd: seq[tuple[name, sourceName: string]]
  for bin in bins:
    block check:
      for existing in pkg.bin:
        if existing.sourceName == bin:
          break check
      toAdd.add (name: bin, sourceName: bin)
  pkg.bin = pkg.bin & toAdd

proc addNamedBins(pkg: var NimblePkg, bins: string) =
  let bins = bins.split(",").mapIt(it.strip)
  var toAdd: seq[tuple[name, sourceName: string]]
  for bin in bins:
    let
      split = bin.split(":")
      sourceName = split[0]
      name = split[1]
    block check:
      for existing in pkg.bin:
        if existing.sourceName == sourceName:
          pkg.name = name
          break check
      toAdd.add (name: name, sourceName: sourceName)
  pkg.bin = pkg.bin & toAdd

proc getPackage*(package: string): NimblePkg =
  ## Gets all package information for a package. Package can be a nimble file
  ## path, a folder to the root path, or the name of an installed package
  let dump = nimbleDump(package)
  if dump.exitCode != 0: raise newException(KeyError, "Given package could not be found: " & package)
  for line in dump.output.splitLines.mapIt(it.split(": ")):
    if line.len != 2: continue
    let
      key = line[0]
      value = line[1].strip(chars = {'"'})
    case key:
    of "name": result.name = value
    of "version": result.version = value.parseVersion
    of "author": result.author = value
    of "desc": result.description = value
    of "license": result.license = value
    of "skipDirs": result.skipDirs = value.split(",").mapIt(it.strip)
    of "skipFiles": result.skipFiles = value.split(",").mapIt(it.strip)
    of "skipExt": result.skipExt = value.split(",").mapIt(it.strip)
    of "installDirs": result.installDirs = value.split(",").mapIt(it.strip)
    of "installFiles": result.installFiles = value.split(",").mapIt(it.strip)
    of "installExt": result.installExt = value.split(",").mapIt(it.strip)
    of "srcDir": result.srcDir = value
    of "binDir": result.binDir = value
    of "bin": result.addBins value
    of "namedBin": result.addNamedBins value
    of "backend": result.backend = parseEnum[Backend](value)
    of "requires": result.requires = parseDependencies(value)
    else: raise newException(KeyError, "Unknown key in Nimble package dump: " & key)

