-- MonoLocalBinds is to silence a warning about a simplifiable constraint.
{-# LANGUAGE DataKinds, MonoLocalBinds, ScopedTypeVariables, TypeFamilies, TypeOperators #-}
{-# OPTIONS_GHC -Wno-missing-signatures #-}
module Semantic.Util where

import Analysis.Abstract.Caching
import Analysis.Abstract.Dead
import Analysis.Abstract.Evaluating as X
import Analysis.Abstract.Tracing
import Analysis.Declaration
import Control.Abstract.Analysis
import Control.Monad.IO.Class
import Data.Abstract.Evaluatable
import Data.Abstract.Address
import Data.Abstract.Module
import Data.Abstract.Type
import Data.Abstract.Value
import Data.Blob
import Data.Diff
import Data.Range
import Data.Record
import Data.Span
import Data.Term
import Diffing.Algorithm
import Diffing.Interpreter
import System.FilePath.Glob
import qualified GHC.TypeLits as TypeLevel
import Language.Preluded
import Parsing.Parser
import Prologue
import Semantic
import Semantic.IO as IO
import Semantic.Task
import System.FilePath.Posix

import qualified Language.Go.Assignment as Go
import qualified Language.Python.Assignment as Python
import qualified Language.TypeScript.Assignment as TypeScript

-- Ruby
evalRubyProject = evaluateProject rubyParser ["rb"]
evalRubyFile = evaluateWithPrelude rubyParser
evalRubyFiles = evaluateFilesWithPrelude rubyParser

-- Go
evalGoProject = evaluateProject goParser ["go"]
evalGoFile = evaluateFile goParser
evalGoFiles = evaluateFiles goParser
typecheckGoFile path = runAnalysis @(Caching Evaluating Go.Term Type) . evaluateModule <$> parseFile goParser Nothing path

-- Python
evalPythonProject = evaluateProject pythonParser ["py"]
evalPythonFile = evaluateWithPrelude pythonParser
evalPythonFiles = evaluateFilesWithPrelude pythonParser
typecheckPythonFile path = runAnalysis @(Caching Evaluating Python.Term Type) . evaluateModule <$> parseFile pythonParser Nothing path
tracePythonFile path = runAnalysis @(Tracing [] Evaluating Python.Term Value) . evaluateModule <$> parseFile pythonParser Nothing path
evaluateDeadTracePythonFile path = runAnalysis @(DeadCode (Tracing [] Evaluating) Python.Term Value) . evaluateModule <$> parseFile pythonParser Nothing path

-- PHP
evalPHP = evaluateProject phpParser ["php"]
evalPHPFile = evaluateFile phpParser
evalPHPFiles = evaluateFiles phpParser

-- TypeScript
evalTypeScriptProject = evaluateProject typescriptParser ["ts", "tsx"]
evalTypeScriptFile = evaluateFile typescriptParser
evalTypeScriptFiles = evaluateFiles typescriptParser
typecheckTypeScriptFile path = runAnalysis @(Caching Evaluating TypeScript.Term Type) . evaluateModule <$> parseFile typescriptParser Nothing path

evaluateProject :: forall term effects
                .  ( Evaluatable (Base term)
                   , FreeVariables term
                   , effects ~ RequiredEffects term Value (Evaluating term Value effects)
                   , MonadAddressable Precise Value (Evaluating term Value effects)
                   , MonadValue Value (Evaluating term Value effects)
                   , Recursive term
                   )
                => Parser term
                -> [FilePath]
                -> FilePath
                -> IO (Final effects Value)
evaluateProject parser exts entryPoint = do
  let rootDir = takeDirectory entryPoint
  paths <- filter (/= entryPoint) <$> getPaths exts rootDir
  evaluateFiles parser rootDir (entryPoint : paths)

getPaths exts = fmap fold . globDir (compile . mappend "**/*." <$> exts)

-- Evalute a single file.
evaluateFile :: forall term effects
             .  ( Evaluatable (Base term)
                , FreeVariables term
                , effects ~ RequiredEffects term Value (Evaluating term Value effects)
                , MonadAddressable Precise Value (Evaluating term Value effects)
                , MonadValue Value (Evaluating term Value effects)
                , Recursive term
                )
             => Parser term
             -> FilePath
             -> IO (Final effects Value)
evaluateFile parser path = runAnalysis @(Evaluating term Value) . evaluateModule <$> parseFile parser Nothing path

evaluateWith :: forall value term effects
             .  ( effects ~ RequiredEffects term value (Evaluating term value effects)
                , Evaluatable (Base term)
                , FreeVariables term
                , MonadAddressable (LocationFor value) value (Evaluating term value effects)
                , MonadValue value (Evaluating term value effects)
                , Recursive term
                , Show (LocationFor value)
                )
         => Module term
         -> Module term
         -> Final effects value
evaluateWith prelude m = runAnalysis @(Evaluating term value) $ do
  -- TODO: we could add evaluatePrelude to MonadAnalysis as an alias for evaluateModule,
  -- overridden in Evaluating to not reset the environment. In the future we'll want the
  -- result of evaluating the Prelude to be a build artifact, rather than something that's
  -- evaluated every single time, but that's contingent upon a whole lot of other future
  -- scaffolding.
  preludeEnv <- evaluateModule prelude *> getEnv
  withDefaultEnvironment preludeEnv (evaluateModule m)

evaluateWithPrelude :: forall term effects
                    .  ( Evaluatable (Base term)
                       , FreeVariables term
                       , effects ~ RequiredEffects term Value (Evaluating term Value effects)
                       , MonadAddressable Precise Value (Evaluating term Value effects)
                       , MonadValue Value (Evaluating term Value effects)
                       , Recursive term
                       , TypeLevel.KnownSymbol (PreludePath term)
                       )
                    => Parser term
                    -> FilePath
                    -> IO (Final effects Value)
evaluateWithPrelude parser path = do
  let preludePath = TypeLevel.symbolVal (Proxy :: Proxy (PreludePath term))
  prelude <- parseFile parser Nothing preludePath
  m <- parseFile parser Nothing path
  pure $ evaluateWith prelude m


-- Evaluate a list of files (head of file list is considered the entry point).
evaluateFiles :: forall term effects
              .  ( Evaluatable (Base term)
                 , FreeVariables term
                 , effects ~ RequiredEffects term Value (Evaluating term Value effects)
                 , MonadAddressable Precise Value (Evaluating term Value effects)
                 , MonadValue Value (Evaluating term Value effects)
                 , Recursive term
                 )
              => Parser term
              -> FilePath
              -> [FilePath]
              -> IO (Final effects Value)
evaluateFiles parser rootDir paths = runAnalysis @(Evaluating term Value) . evaluateModules <$> parseFiles parser rootDir paths

-- | Evaluate terms and an entry point to a value with a given prelude.
evaluatesWith :: forall value term effects
              .  ( effects ~ RequiredEffects term value (Evaluating term value effects)
                 , Evaluatable (Base term)
                 , FreeVariables term
                 , MonadAddressable (LocationFor value) value (Evaluating term value effects)
                 , MonadValue value (Evaluating term value effects)
                 , Recursive term
                 , Show (LocationFor value)
                 )
              => Module term   -- ^ Prelude to evaluate once
              -> [Module term] -- ^ List of (blob, term) pairs that make up the program to be evaluated
              -> Module term   -- ^ Entrypoint
              -> Final effects value
evaluatesWith prelude modules m = runAnalysis @(Evaluating term value) $ do
  preludeEnv <- evaluateModule prelude *> getEnv
  withDefaultEnvironment preludeEnv (withModules modules (evaluateModule m))

evaluateFilesWithPrelude :: forall term effects
                         .  ( Evaluatable (Base term)
                            , FreeVariables term
                            , effects ~ RequiredEffects term Value (Evaluating term Value effects)
                            , MonadAddressable Precise Value (Evaluating term Value effects)
                            , MonadValue Value (Evaluating term Value effects)
                            , Recursive term
                            , TypeLevel.KnownSymbol (PreludePath term)
                            )
                         => Parser term
                         -> [FilePath]
                         -> IO (Final effects Value)
evaluateFilesWithPrelude parser paths = do
  let preludePath = TypeLevel.symbolVal (Proxy :: Proxy (PreludePath term))
  prelude <- parseFile parser Nothing preludePath
  entry:xs <- traverse (parseFile parser Nothing) paths
  pure $ evaluatesWith @Value prelude xs entry

-- Read and parse a file.
parseFile :: Parser term -> Maybe FilePath -> FilePath -> IO (Module term)
parseFile parser rootDir path = runTask $ do
  blob <- file path
  moduleForBlob rootDir blob <$> parse parser blob

parseFiles :: Parser term -> FilePath -> [FilePath] -> IO [Module term]
parseFiles parser rootDir = traverse (parseFile parser (Just rootDir))
-- where x = (Just (dropFileName (head paths)))

-- Read a file from the filesystem into a Blob.
file :: MonadIO m => FilePath -> m Blob
file path = fromJust <$> IO.readFile path (languageForFilePath path)

-- Diff helpers
diffWithParser ::
               ( HasField fields Data.Span.Span
               , HasField fields Range
               , Eq1 syntax
               , Show1 syntax
               , Traversable syntax
               , Diffable syntax
               , GAlign syntax
               , HasDeclaration syntax
               )
               => Parser (Term syntax (Record fields))
               -> BlobPair
               -> Task (Diff syntax (Record (Maybe Declaration ': fields)) (Record (Maybe Declaration ': fields)))
diffWithParser parser = run (\ blob -> parse parser blob >>= decorate (declarationAlgebra blob))
  where
    run parse blobs = bidistributeFor (runJoin blobs) parse parse >>= diffTermPair diffTerms

diffBlobWithParser ::
                   ( HasField fields Data.Span.Span
                   , HasField fields Range
                   , Traversable syntax
                   , HasDeclaration syntax
                   )
                  => Parser (Term syntax (Record fields))
                  -> Blob
                  -> Task (Term syntax (Record (Maybe Declaration : fields)))
diffBlobWithParser parser = run (\ blob -> parse parser blob >>= decorate (declarationAlgebra blob))
  where
    run parse = parse
