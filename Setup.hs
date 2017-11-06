{-# OPTIONS_GHC -Wall -Wno-deprecations #-}

import Data.Foldable
import Distribution.Simple
import Distribution.Simple.LocalBuildInfo
import Distribution.Simple.Program
import Distribution.Simple.Toolkit
import Distribution.Types.BuildInfo
import Distribution.Types.GenericPackageDescription
import Distribution.Types.PackageDescription
import Distribution.Verbosity
import System.Directory
import System.FilePath

endOfFirstLineVersion :: Verbosity -> FilePath -> IO (Maybe Version)
endOfFirstLineVersion =
  findProgramVersion "--version" $ last . words . head . lines

cmakeProgram :: Program
cmakeProgram =
  (simpleProgram "cmake") {programFindVersion = endOfFirstLineVersion}

ninjaProgram :: Program
ninjaProgram =
  (simpleProgram "ninja")
  {programFindVersion = findProgramVersion "--version" id}

main :: IO ()
main =
  defaultMainWithHooks
    simpleUserHooks
    { hookedPrograms = [cmakeProgram, ninjaProgram]
    , confHook =
        \t f -> do
          lbi <- confHook simpleUserHooks t f
          rocksdb_srcdir <- (</> "rocksdb-5.8") <$> getCurrentDirectory
          let clbi = getComponentLocalBuildInfo lbi CLibName
              rocksdb_libname =
                getHSLibraryName (componentUnitId clbi) ++ "-rocksdb-5.8"
              rocksdb_builddir = componentBuildDir lbi clbi </> "rocksdb-5.8"
              lib_installdir =
                libdir $
                getComponentInstallDirs
                  (packageDescription $ fst t)
                  lbi
                  CLibName
          for_ [rocksdb_builddir, lib_installdir] $
            createDirectoryIfMissing True
          withCurrentDirectory rocksdb_builddir $ do
            runLBIProgram lbi cmakeProgram [rocksdb_srcdir, "-G", "Ninja"]
            runLBIProgram lbi ninjaProgram ["librocksdb.a"]
            copyFile "librocksdb.a" $
              lib_installdir </> "lib" ++ rocksdb_libname <.> "a"
          pure
            lbi
            { localPkgDescr =
                updatePackageDescription
                  ( Just
                      emptyBuildInfo
                      { extraLibs = [rocksdb_libname]
                      , extraLibDirs = [lib_installdir]
                      }
                  , []) $
                localPkgDescr lbi
            }
    }