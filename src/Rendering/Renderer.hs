{-# LANGUAGE DataKinds, GADTs, MultiParamTypeClasses, StandaloneDeriving, TypeOperators #-}
module Rendering.Renderer
( DiffRenderer(..)
, TermRenderer(..)
, SomeRenderer(..)
, renderJSONDiff
, renderJSONTerm
, renderJSONAST
, renderToCDiff
, renderToCTerm
, renderSymbolTerms
, renderToSymbols
, ImportSummary(..)
, renderToImports
, renderToTags
, renderTreeGraph
, Summaries(..)
, SymbolFields(..)
, defaultSymbolFields
) where

import Data.Aeson (Value)
import Data.ByteString.Builder
import Data.Output
import Rendering.Graph as R
import Rendering.Imports as R
import Rendering.JSON as R
import Rendering.Symbol as R
import Rendering.TOC as R

-- | Specification of renderers for diffs, producing output in the parameter type.
data DiffRenderer output where
  -- | Compute a table of contents for the diff & encode it as JSON.
  ToCDiffRenderer :: DiffRenderer Summaries
  -- | Render to JSON with the format documented in docs/json-format.md
  JSONDiffRenderer :: DiffRenderer JSONOutput
  -- | Render to a 'ByteString' formatted as nested s-expressions with patches indicated.
  SExpressionDiffRenderer :: DiffRenderer Builder
  -- | Render to a 'ByteString' formatted as a DOT description of the diff.
  DOTDiffRenderer :: DiffRenderer Builder

deriving instance Eq (DiffRenderer output)
deriving instance Show (DiffRenderer output)

-- | Specification of renderers for terms, producing output in the parameter type.
data TermRenderer output where
  -- | Render to JSON with the format documented in docs/json-format.md under “Term.”
  JSONTermRenderer :: TermRenderer JSONTerms
  -- | Render to a 'ByteString' formatted as nested s-expressions.
  SExpressionTermRenderer :: TermRenderer Builder
  -- | Render to a list of tags (deprecated).
  TagsTermRenderer :: TermRenderer [Value]
  -- | Render to a list of symbols.
  SymbolsTermRenderer :: SymbolFields -> TermRenderer JSONOutput
  -- | Render to a list of modules that represent the import graph.
  ImportsTermRenderer :: TermRenderer ImportSummary
  -- | Render to a 'ByteString' formatted as a DOT description of the term.
  DOTTermRenderer :: TermRenderer Builder

deriving instance Eq (TermRenderer output)
deriving instance Show (TermRenderer output)


-- | Abstraction of some renderer to some 'Monoid'al output which can be serialized to a 'ByteString'.
--
--   This type abstracts the type indices of 'DiffRenderer', 'TermRenderer', and 'GraphRenderer' s.t. multiple renderers can be present in a single list, alternation, etc., while retaining the ability to render and serialize. (Without 'SomeRenderer', the different output types of individual term/diff renderers prevent them from being used in a homogeneously typed setting.)
data SomeRenderer f where
  SomeRenderer :: (Output output, Show (f output)) => f output -> SomeRenderer f

deriving instance Show (SomeRenderer f)
