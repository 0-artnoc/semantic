{-# LANGUAGE DataKinds, GADTs, GeneralizedNewtypeDeriving, MultiParamTypeClasses, StandaloneDeriving, TypeOperators #-}
module Renderer
( DiffRenderer(..)
, TermRenderer(..)
, SomeRenderer(..)
, renderPatch
, renderSExpressionDiff
, renderSExpressionTerm
, renderJSONDiff
, renderJSONTerm
, renderToCDiff
, renderToCTerm
, declarationAlgebra
, markupSectionAlgebra
, identifierAlgebra
, Summaries(..)
, File(..)
) where

import Control.Comonad.Cofree (Cofree, unwrap)
import Control.Comonad.Trans.Cofree (CofreeF(..))
import Control.DeepSeq
import Data.Aeson (Value, (.=))
import Data.ByteString (ByteString)
import Data.Foldable (asum)
import qualified Data.Map as Map
import Data.Output
import Data.Syntax.Algebra (RAlgebra)
import Data.Text (Text)
import Renderer.JSON as R
import Renderer.Patch as R
import Renderer.SExpression as R
import Renderer.TOC as R
import Syntax as S

-- | Specification of renderers for diffs, producing output in the parameter type.
data DiffRenderer output where
  -- | Render to git-diff-compatible textual output.
  PatchDiffRenderer :: DiffRenderer File
  -- | Compute a table of contents for the diff & encode it as JSON.
  ToCDiffRenderer :: DiffRenderer Summaries
  -- | Render to JSON with the format documented in docs/json-format.md
  JSONDiffRenderer :: DiffRenderer (Map.Map Text Value)
  -- | Render to a 'ByteString' formatted as nested s-expressions with patches indicated.
  SExpressionDiffRenderer :: DiffRenderer ByteString

deriving instance Eq (DiffRenderer output)
deriving instance Show (DiffRenderer output)

-- | Specification of renderers for terms, producing output in the parameter type.
data TermRenderer output where
  -- | Compute a table of contents for the term & encode it as JSON.
  ToCTermRenderer :: TermRenderer Summaries
  -- | Render to JSON with the format documented in docs/json-format.md under “Term.”
  JSONTermRenderer :: TermRenderer [Value]
  -- | Render to a 'ByteString' formatted as nested s-expressions.
  SExpressionTermRenderer :: TermRenderer ByteString

deriving instance Eq (TermRenderer output)
deriving instance Show (TermRenderer output)


-- | Abstraction of some renderer to some 'Monoid'al output which can be serialized to a 'ByteString'.
--
--   This type abstracts the type indices of 'DiffRenderer' and 'TermRenderer' s.t. multiple renderers can be present in a single list, alternation, etc., while retaining the ability to render and serialize. (Without 'SomeRenderer', the different output types of individual term/diff renderers prevent them from being used in a homogeneously typed setting.)
data SomeRenderer f where
  SomeRenderer :: (Output output, Show (f output)) => f output -> SomeRenderer f

deriving instance Show (SomeRenderer f)

identifierAlgebra :: RAlgebra (CofreeF Syntax a) (Cofree Syntax a) (Maybe Identifier)
identifierAlgebra (_ :< syntax) = case syntax of
  S.Assignment f _ -> identifier f
  S.Class f _ _ -> identifier f
  S.Export f _ -> f >>= identifier
  S.Function f _ _ -> identifier f
  S.FunctionCall f _ _ -> identifier f
  S.Import f _ -> identifier f
  S.Method _ f _ _ _ -> identifier f
  S.MethodCall _ f _ _ -> identifier f
  S.Module f _ -> identifier f
  S.OperatorAssignment f _ -> identifier f
  S.SubscriptAccess f _  -> identifier f
  S.TypeDecl f _ -> identifier f
  S.VarAssignment f _ -> asum $ identifier <$> f
  _ -> Nothing
  where identifier = fmap Identifier . extractLeafValue . unwrap . fst

newtype Identifier = Identifier Text
  deriving (Eq, NFData, Show)

instance ToJSONFields Identifier where
  toJSONFields (Identifier i) = ["identifier" .= i]
