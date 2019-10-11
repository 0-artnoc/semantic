{-# LANGUAGE AllowAmbiguousTypes, ConstraintKinds, KindSignatures, GADTs, RankNTypes, ScopedTypeVariables, TypeOperators #-}
module Parsing.Parser
( Parser(..)
, SomeAnalysisParser(..)
, someAnalysisParser
-- * À la carte parsers
, goParser
, pythonParser
, rubyParser
, tsxParser
, typescriptParser
, phpParser
  -- * Abstract parsers

  -- $abstract
, SomeParser(..)
, goParser'
, javaParser'
, javascriptParser'
, jsonParserPrecise'
, jsxParser'
, phpParser'
, pythonParserALaCarte'
, pythonParserPrecise'
, pythonParser'
, rubyParser'
, tsxParser'
, typescriptParser'
  -- * Canonical sets of parsers
, aLaCarteParsers
, preciseParsers
, allParsers
) where

import           Assigning.Assignment
import           Data.Abstract.Evaluatable (HasPrelude)
import           Data.Graph.ControlFlowVertex (VertexDeclaration')
import           Data.Language
import           Data.Kind (Constraint)
import qualified Data.Map as Map
import           Data.Sum
import qualified Data.Syntax as Syntax
import           Data.Term
import           Foreign.Ptr
import qualified Language.Go.Assignment as Go
import qualified Language.Java as PreciseJava
import qualified Language.JSON as PreciseJSON
import qualified Language.PHP.Assignment as PHP
import qualified Language.Python as PrecisePython
import qualified Language.Python.Assignment as Python
import qualified Language.Ruby.Assignment as Ruby
import qualified Language.TSX.Assignment as TSX
import qualified Language.TypeScript.Assignment as TypeScript
import           Prelude hiding (fail)
import           Prologue
import           TreeSitter.Go
import qualified TreeSitter.Language as TS (Language, Symbol)
import           TreeSitter.PHP
import           TreeSitter.Python
import           TreeSitter.Ruby (tree_sitter_ruby)
import           TreeSitter.TSX
import           TreeSitter.TypeScript
import           TreeSitter.Unmarshal


-- | A parser, suitable for program analysis, for some specific language, producing 'Term's whose syntax satisfies a list of typeclass constraints.
data SomeAnalysisParser (constraint :: (* -> *) -> Constraint) ann where
  SomeAnalysisParser :: ( constraint (Sum fs)
                        , Apply (VertexDeclaration' (Sum fs)) fs
                        , HasPrelude lang
                        )
                     => Parser (Term (Sum fs) ann)
                     -> Proxy lang
                     -> SomeAnalysisParser constraint ann

-- | A parser for some specific language, producing 'Term's whose syntax satisfies a list of typeclass constraints.
someAnalysisParser :: ( constraint (Sum Go.Syntax)
                      , constraint (Sum PHP.Syntax)
                      , constraint (Sum Python.Syntax)
                      , constraint (Sum Ruby.Syntax)
                      , constraint (Sum TypeScript.Syntax)
                      )
                   => proxy constraint                  -- ^ A proxy for the constraint required, e.g. @(Proxy \@Show1)@.
                   -> Language                          -- ^ The 'Language' to select.
                   -> SomeAnalysisParser constraint Loc -- ^ A 'SomeAnalysisParser' abstracting the syntax type to be produced.
someAnalysisParser _ Go         = SomeAnalysisParser goParser         (Proxy @'Go)
someAnalysisParser _ JavaScript = SomeAnalysisParser typescriptParser (Proxy @'JavaScript)
someAnalysisParser _ PHP        = SomeAnalysisParser phpParser        (Proxy @'PHP)
someAnalysisParser _ Python     = SomeAnalysisParser pythonParser     (Proxy @'Python)
someAnalysisParser _ Ruby       = SomeAnalysisParser rubyParser       (Proxy @'Ruby)
someAnalysisParser _ TypeScript = SomeAnalysisParser typescriptParser (Proxy @'TypeScript)
someAnalysisParser _ TSX        = SomeAnalysisParser typescriptParser (Proxy @'TSX)
someAnalysisParser _ l          = error $ "Analysis not supported for: " <> show l


-- | A parser from 'Source' onto some term type.
data Parser term where
  -- | A parser 'Unmarshal'ing to a precise AST type using a 'TS.Language'.
  UnmarshalParser :: Unmarshal t => Ptr TS.Language -> Parser (t Loc)
  -- | A parser producing an à la carte term given an 'AST'-producing parser and an 'Assignment' onto 'Term's in some syntax type.
  AssignmentParser :: (TS.Symbol grammar, Syntax.Error :< fs, Apply Foldable fs, Apply Functor fs)
                   => Ptr TS.Language                        -- ^ A parser producing AST.
                   -> Assignment grammar (Term (Sum fs) Loc) -- ^ An assignment from AST onto 'Term's.
                   -> Parser (Term (Sum fs) Loc)             -- ^ A parser producing 'Term's.


goParser :: Parser Go.Term
goParser = AssignmentParser tree_sitter_go Go.assignment

rubyParser :: Parser Ruby.Term
rubyParser = AssignmentParser tree_sitter_ruby Ruby.assignment

phpParser :: Parser PHP.Term
phpParser = AssignmentParser tree_sitter_php PHP.assignment

pythonParser :: Parser Python.Term
pythonParser = AssignmentParser tree_sitter_python Python.assignment

typescriptParser :: Parser TypeScript.Term
typescriptParser = AssignmentParser tree_sitter_typescript TypeScript.assignment

tsxParser :: Parser TSX.Term
tsxParser = AssignmentParser tree_sitter_tsx TSX.assignment

javaParserPrecise :: Parser (PreciseJava.Term Loc)
javaParserPrecise = UnmarshalParser PreciseJava.tree_sitter_java

jsonParserPrecise :: Parser (PreciseJSON.Term Loc)
jsonParserPrecise = UnmarshalParser PreciseJSON.tree_sitter_json

pythonParserPrecise :: Parser (PrecisePython.Term Loc)
pythonParserPrecise = UnmarshalParser PrecisePython.tree_sitter_python


-- $abstract
-- Most of our features are intended to operate over multiple languages, each represented by disjoint term types. Thus, we typically implement them using typeclasses, allowing us to share a single interface to invoke the feature, while specializing the implementation(s) as appropriate for each distinct term type.
--
-- In order to accomplish this, we employ 'SomeParser', which abstracts over parsers of various term types, while ensuring that some desired constraint holds. Constructing a @'SomeParser' c@ requires satisfiyng the constraint @c@ against the underlying 'Parser'’s term type, and so it can be used to parse with any of a map of parsers whose terms support @c@.
--
-- In practice, this means using 'Control.Effect.Parse.parseWith', and passing in a map of parsers to select from for your feature. It is recommended to define the map as a concrete top-level binding using the abstract parsers or ideally the canonical maps of parsers, below; using the abstracted parsers or canonical maps directly with 'Control.Effect.Parse.parseWith' will lead to significantly slower compiles.
--
-- Bad:
--
-- @
-- isFancy :: (Carrier sig m, Member Parse sig) => Blob -> m Bool
-- isFancy = parseWith (preciseParsers @Fancy) (pure . isTermFancy) -- slow compiles!
-- @
--
-- Good:
--
-- @
-- fancyParsers :: 'Map' 'Language' ('SomeParser' Fancy 'Loc')
-- fancyParsers = preciseParsers
--
-- isFancy :: (Carrier sig m, Member Parse sig) => Blob -> m Bool
-- isFancy = parseWith fancyParsers (pure . isTermFancy) -- much faster compiles
-- @


-- | A parser producing terms of existentially-quantified type under some constraint @c@.
--
--   This can be used to perform actions on terms supporting some feature abstracted using a typeclass, without knowing (or caring) what the specific term types are.
data SomeParser c a where
  SomeParser :: c t => Parser (t a) -> SomeParser c a

goParser' :: c (Term (Sum Go.Syntax)) => (Language, SomeParser c Loc)
goParser' = (Go, SomeParser goParser)

javaParser' :: c PreciseJava.Term => (Language, SomeParser c Loc)
javaParser' = (Java, SomeParser javaParserPrecise)

javascriptParser' :: c (Term (Sum TSX.Syntax)) => (Language, SomeParser c Loc)
javascriptParser' = (JavaScript, SomeParser tsxParser)

jsonParserPrecise' :: c PreciseJSON.Term => (Language, SomeParser c Loc)
jsonParserPrecise' = (JSON, SomeParser jsonParserPrecise)

jsxParser' :: c (Term (Sum TSX.Syntax)) => (Language, SomeParser c Loc)
jsxParser' = (JSX, SomeParser tsxParser)

phpParser' :: c (Term (Sum PHP.Syntax)) => (Language, SomeParser c Loc)
phpParser' = (PHP, SomeParser phpParser)

pythonParserALaCarte' :: c (Term (Sum Python.Syntax)) => (Language, SomeParser c Loc)
pythonParserALaCarte' = (Python, SomeParser pythonParser)

pythonParserPrecise' :: c PrecisePython.Term => (Language, SomeParser c Loc)
pythonParserPrecise' = (Python, SomeParser pythonParserPrecise)

pythonParser' :: (c (Term (Sum Python.Syntax)), c PrecisePython.Term) => PerLanguageModes -> (Language, SomeParser c Loc)
pythonParser' modes = case pythonMode modes of
  ALaCarte -> (Python, SomeParser pythonParser)
  Precise  -> (Python, SomeParser pythonParserPrecise)

rubyParser' :: c (Term (Sum Ruby.Syntax)) => (Language, SomeParser c Loc)
rubyParser' = (Ruby, SomeParser rubyParser)

tsxParser' :: c (Term (Sum TSX.Syntax)) => (Language, SomeParser c Loc)
tsxParser' = (TSX, SomeParser tsxParser)

typescriptParser' :: c (Term (Sum TypeScript.Syntax)) => (Language, SomeParser c Loc)
typescriptParser' = (TypeScript, SomeParser typescriptParser)


-- | The canonical set of parsers producing à la carte terms.
aLaCarteParsers
  :: ( c (Term (Sum Go.Syntax))
     , c (Term (Sum PHP.Syntax))
     , c (Term (Sum Python.Syntax))
     , c (Term (Sum Ruby.Syntax))
     , c (Term (Sum TSX.Syntax))
     , c (Term (Sum TypeScript.Syntax))
     )
  => Map Language (SomeParser c Loc)
aLaCarteParsers = Map.fromList
  [ goParser'
  , javascriptParser'
  , jsxParser'
  , phpParser'
  , pythonParserALaCarte'
  , rubyParser'
  , typescriptParser'
  , tsxParser'
  ]

-- | The canonical set of parsers producing precise terms.
preciseParsers
  :: ( c PreciseJava.Term
     , c PreciseJSON.Term
     , c PrecisePython.Term
     )
  => Map Language (SomeParser c Loc)
preciseParsers = Map.fromList
  [ javaParser'
  , jsonParserPrecise'
  , pythonParserPrecise'
  ]

-- | The canonical set of all parsers for the passed per-language modes.
allParsers
  :: ( c (Term (Sum Go.Syntax))
     , c PreciseJava.Term
     , c PreciseJSON.Term
     , c (Term (Sum PHP.Syntax))
     , c (Term (Sum Python.Syntax))
     , c PrecisePython.Term
     , c (Term (Sum Ruby.Syntax))
     , c (Term (Sum TSX.Syntax))
     , c (Term (Sum TypeScript.Syntax))
     )
  => PerLanguageModes
  -> Map Language (SomeParser c Loc)
allParsers modes = Map.fromList
  [ goParser'
  , javaParser'
  , javascriptParser'
  , jsonParserPrecise'
  , jsxParser'
  , phpParser'
  , pythonParser' modes
  , rubyParser'
  , typescriptParser'
  , tsxParser'
  ]
