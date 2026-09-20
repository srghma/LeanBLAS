import Lake

open Lake DSL System Lean Elab

def linkArgs : Array String :=
  if let some p := get_config? openblas then
    #["-L" ++ p ++ "/lib", "-lblas"]
  else if System.Platform.isWindows then
    #[]
  else if System.Platform.isOSX then
    #["-L/opt/homebrew/opt/openblas/lib",
      "-L/usr/local/opt/openblas/lib", "-lblas"]
  else -- assuming linux
    #["-lblas"]

def inclArgs : Array String :=
  if let some p := get_config? openblas then
    #["-I" ++ p ++ "/include"]
  else if System.Platform.isWindows then
    #[]
  else if System.Platform.isOSX then
    #["-I/opt/homebrew/opt/openblas/include",
      "-I/usr/local/opt/openblas/include"]
  else -- assuming linux
    #["-I/usr/include/openblas"]

package leanblas {
  moreLinkArgs := linkArgs
  preferReleaseBuild := true
}

require mathlib from git "https://github.com/leanprover-community/mathlib4" @ "v4.34.0"

----------------------------------------------------------------------------------------------------
-- Build Lean ↔ BLAS bindings ---------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
extern_lib libleanblasc pkg := do
  let mut oFiles : Array (Job FilePath) := #[]
  let openblasInclude ← do
    if let some p ← IO.getEnv "OPENBLAS_PATH" then
      pure #[s!"-I{p}/include"]
    else
      pure #[]
  for file in (← (pkg.dir / "c").readDir) do
    if file.path.extension == some "c" then
      let oFile := pkg.buildDir / "c" / ((file.fileName.dropSuffix ".c").toString ++ ".o")
      let srcJob ← inputTextFile file.path
      let weakArgs := #["-I", (← getLeanIncludeDir).toString]
      oFiles := oFiles.push (← buildO oFile srcJob weakArgs (#["-DNDEBUG", "-O3", "-fPIC"] ++ inclArgs ++ openblasInclude) "gcc" getLeanTrace)
  let name := nameToStaticLib "leanblasc"

  buildStaticLib (pkg.sharedLibDir / name) (oFiles)

----------------------------------------------------------------------------------------------------

@[default_target]
lean_lib LeanBLAS where
  roots := #[`LeanBLAS]
  precompileModules := true

lean_lib LeanBLAS.FFI where
  roots := #[`LeanBLAS.FFI]
  precompileModules := true

lean_exe CBLASLevelOneTest where
  root := `Test.cblas_level_one

lean_exe CBLASLevelTwoTest where
  root := `Test.cblas_level_two

@[test_driver]
script test (_args) do
  let run (name : String) : ScriptM UInt32 := do
    IO.println s!"=== Running {name} ==="
    let proc ← IO.Process.spawn { cmd := "lake", args := #["exe", name] }
    proc.wait

  let code1 ← run "CBLASLevelOneTest"
  if code1 ≠ 0 then return code1
  let code2 ← run "CBLASLevelTwoTest"
  if code2 ≠ 0 then return code2
  IO.println "=== All LeanBLAS tests passed successfully! ==="
  return 0

-- ----------------------------------------------------------------------------------------------------
-- -- Download and build OpenBLAS ---------------------------------------------------------------------
-- -- -------------------------------------------------------------------------------------------------
-- -- This code was taken from: https://github.com/lean-dojo/LeanCopilot/blob/92a5ab6b58d06df8fd60d98dc38b1f674706eaad/lakefile.lean
-- ----------------------------------------------------------------------------------------------------

-- def nproc : IO Nat := do
--   let out ← IO.Process.output {cmd := "nproc", stdin := .null}
--   return min 1 ((out.stdout.trim.toNat? |>.getD 1) - 4)

-- private def nameToVersionedSharedLib (name : String) (v : String) : String :=
--   if Platform.isWindows then s!"{name}.dll"
--   else if Platform.isOSX  then s!"lib{name}.{v}.dylib"
--   else s!"lib{name}.so.{v}"

-- def afterReleaseAsync {α : Type} (pkg : Package) (build : JobM α) : FetchM (Job α) := do
--   if pkg.preferReleaseBuild ∧ pkg.name ≠ (← getRootPackage).name then
--     (← pkg.optGitHubRelease.fetch).mapM fun _ => build
--   else
--     Job.async build

-- def ensureDirExists (dir : FilePath) : IO Unit := do
--   if !(← dir.pathExists)  then
--     IO.FS.createDirAll dir

-- def gitClone (url : String) (cwd : Option FilePath) : LogIO Unit := do
--   proc (quiet := true) {
--     cmd := "git"
--     args := #["clone", "--recursive", url]
--     cwd := cwd
--   }

-- target libopenblas pkg : FilePath := do
--   afterReleaseAsync pkg do
--     let rootDir := pkg.buildDir / "OpenBLAS"
--     ensureDirExists rootDir
--     let dst := pkg.sharedLibDir / (nameToSharedLib "openblas")
--     createParentDirs dst
--     let url := "https://github.com/OpenMathLib/OpenBLAS"

--     try
--       let depTrace := Hash.ofString url
--       setTrace depTrace
--       buildFileUnlessUpToDate' dst do
--         logInfo s!"Cloning OpenBLAS from {url}"
--         gitClone url pkg.buildDir

--         let numThreads := max 4 $ min 32 (← nproc)
--         let flags := #["NO_LAPACK=1", "NO_FORTRAN=1", s!"-j{numThreads}"]
--         logInfo s!"Building OpenBLAS with `make{flags.foldl (· ++ " " ++ ·) ""}`"
--         proc (quiet := true) {
--           cmd := "make"
--           args := flags
--           cwd := rootDir
--         }
--         proc {
--           cmd := "cp"
--           args := #[(rootDir / nameToSharedLib "openblas").toString, dst.toString]
--         }
--         -- TODO: Don't hardcode the version "0".
--         let dst' := pkg.sharedLibDir / (nameToVersionedSharedLib "openblas" "0")
--         proc {
--           cmd := "cp"
--           args := #[dst.toString, dst'.toString]
--         }
--       let _ := (← getTrace)
--       return dst

--     else
--       proc {
--         cmd := "cp"
--         args := #[(rootDir / nameToSharedLib "openblas").toString, dst.toString]
--       }
--       let dst' := pkg.sharedLibDir / (nameToVersionedSharedLib "openblas" "0")
--       proc {
--         cmd := "cp"
--         args := #[dst.toString, dst'.toString]
--       }
--       addTrace <| ← computeTrace dst
--       return dst
