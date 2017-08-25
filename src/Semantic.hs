{-# LANGUAGE DataKinds, GADTs, TypeOperators #-}
module Semantic
( parseBlobs
, parseBlob
, diffBlobPairs
, diffBlobPair
, diffTermPair
) where

import Algorithm hiding (diff)
import Control.Applicative ((<|>))
import Control.Monad ((<=<))
import Data.Align.Generic (GAlign)
import Data.Blob
import Data.ByteString (ByteString)
import Data.Functor.Both as Both
import Data.Functor.Classes (Eq1, Show1)
import Data.Output
import Data.Record
import qualified Data.Syntax.Declaration as Declaration
import Data.Union
import Decorators
import Diff
import Info
import Interpreter
import qualified Language
import Patch
import Parser
import Renderer
import Semantic.Task as Task
import Term

-- This is the primary interface to the Semantic library which provides two
-- major classes of functionality: semantic parsing and diffing of source code
-- blobs.
--
-- Design goals:
--   - No knowledge of the filesystem or Git.
--   - Built in concurrency where appropriate.
--   - Easy to consume this interface from other application (e.g a cmdline or web server app).

parseBlobs :: Output output => TermRenderer output -> [Blob] -> Task ByteString
parseBlobs renderer = fmap toOutput . distributeFoldMap (parseBlob renderer) . filter blobExists

-- | A task to parse a 'Blob' and render the resulting 'Term'.
parseBlob :: TermRenderer output -> Blob -> Task output
parseBlob renderer blob@Blob{..} = case (renderer, blobLanguage) of
  (ToCTermRenderer, Just Language.Markdown) -> parse markdownParser blob >>= decorate (markupSectionAlgebra blob) >>= render (renderToCTerm blob)
  (ToCTermRenderer, Just Language.Python) -> parse pythonParser blob >>= decorate (declarationAlgebra blob) >>= render (renderToCTerm blob)
  (ToCTermRenderer, Just Language.Ruby) -> parse rubyParser blob >>= decorate (declarationAlgebra blob) >>= render (renderToCTerm blob)
  (ToCTermRenderer, _) -> parse syntaxParser blob >>= decorate (syntaxDeclarationAlgebra blob) >>= render (renderToCTerm blob)
  (JSONTermRenderer, Just Language.JSON) -> parse jsonParser blob >>= decorate constructorLabel >>= render (renderJSONTerm blob)
  (JSONTermRenderer, Just Language.Markdown) -> parse markdownParser blob >>= decorate constructorLabel >>= render (renderJSONTerm blob)
  (JSONTermRenderer, Just Language.Python) -> parse pythonParser blob >>= decorate constructorLabel >>= render (renderJSONTerm blob)
  (JSONTermRenderer, Just Language.Ruby) -> parse rubyParser blob >>= decorate constructorLabel >>= render (renderJSONTerm blob)
  (JSONTermRenderer, _) -> parse syntaxParser blob >>= decorate identifierAlgebra >>= render (renderJSONTerm blob)
  (SExpressionTermRenderer, Just Language.JSON) -> parse jsonParser blob >>= decorate constructorLabel >>= render renderSExpressionTerm . fmap keepConstructorLabel
  (SExpressionTermRenderer, Just Language.Markdown) -> parse markdownParser blob >>= decorate constructorLabel >>= render renderSExpressionTerm . fmap keepConstructorLabel
  (SExpressionTermRenderer, Just Language.Python) -> parse pythonParser blob >>= decorate constructorLabel >>= render renderSExpressionTerm . fmap keepConstructorLabel
  (SExpressionTermRenderer, Just Language.Ruby) -> parse rubyParser blob >>= decorate constructorLabel >>= render renderSExpressionTerm . fmap keepConstructorLabel
  (SExpressionTermRenderer, _) -> parse syntaxParser blob >>= render renderSExpressionTerm . fmap keepCategory
  (IdentityTermRenderer, Just Language.Markdown) -> pure Nothing
  (IdentityTermRenderer, _) -> Just <$> parse syntaxParser blob
  where syntaxParser = parserForLanguage blobLanguage



diffBlobPairs :: Output output => DiffRenderer output -> [Both Blob] -> Task ByteString
diffBlobPairs renderer = fmap toOutput . distributeFoldMap (diffBlobPair renderer) . filter (any blobExists)

-- | A task to parse a pair of 'Blob's, diff them, and render the 'Diff'.
diffBlobPair :: DiffRenderer output -> Both Blob -> Task output
diffBlobPair renderer blobs = case (renderer, effectiveLanguage) of
  (ToCDiffRenderer, Just Language.Markdown) -> run (\ blob -> parse markdownParser blob >>= decorate (markupSectionAlgebra blob)) diffRecursively (renderToCDiff blobs)
  (ToCDiffRenderer, Just Language.Python) -> run (\ blob -> parse pythonParser blob >>= decorate (declarationAlgebra blob)) diffRecursively (renderToCDiff blobs)
  (ToCDiffRenderer, Just Language.Ruby) -> run (\ blob -> parse rubyParser blob >>= decorate (declarationAlgebra blob)) diffRecursively (renderToCDiff blobs)
  (ToCDiffRenderer, _) -> run (\ blob -> parse syntaxParser blob >>= decorate (syntaxDeclarationAlgebra blob)) diffTerms (renderToCDiff blobs)
  (JSONDiffRenderer, Just Language.JSON) -> run (parse jsonParser) diffRecursively (renderJSONDiff blobs)
  (JSONDiffRenderer, Just Language.Markdown) -> run (parse markdownParser) diffRecursively (renderJSONDiff blobs)
  (JSONDiffRenderer, Just Language.Python) -> run (parse pythonParser) diffRecursively (renderJSONDiff blobs)
  (JSONDiffRenderer, Just Language.Ruby) -> run (parse rubyParser) diffRecursively (renderJSONDiff blobs)
  (JSONDiffRenderer, _) -> run (decorate identifierAlgebra <=< parse syntaxParser) diffTerms (renderJSONDiff blobs)
  (PatchDiffRenderer, Just Language.JSON) -> run (parse jsonParser) diffRecursively (renderPatch blobs)
  (PatchDiffRenderer, Just Language.Markdown) -> run (parse markdownParser) diffRecursively (renderPatch blobs)
  (PatchDiffRenderer, Just Language.Python) -> run (parse pythonParser) diffRecursively (renderPatch blobs)
  (PatchDiffRenderer, Just Language.Ruby) -> run (parse rubyParser) diffRecursively (renderPatch blobs)
  (PatchDiffRenderer, _) -> run (parse syntaxParser) diffTerms (renderPatch blobs)
  (SExpressionDiffRenderer, Just Language.JSON) -> run (decorate constructorLabel <=< parse jsonParser) diffRecursively (renderSExpressionDiff . mapAnnotations keepConstructorLabel)
  (SExpressionDiffRenderer, Just Language.Markdown) -> run (decorate constructorLabel <=< parse markdownParser) diffRecursively (renderSExpressionDiff . mapAnnotations keepConstructorLabel)
  (SExpressionDiffRenderer, Just Language.Python) -> run (decorate constructorLabel <=< parse pythonParser) diffRecursively (renderSExpressionDiff . mapAnnotations keepConstructorLabel)
  (SExpressionDiffRenderer, Just Language.Ruby) -> run (decorate constructorLabel <=< parse rubyParser) diffRecursively (renderSExpressionDiff . mapAnnotations keepConstructorLabel)
  (SExpressionDiffRenderer, _) -> run (parse syntaxParser) diffTerms (renderSExpressionDiff . mapAnnotations keepCategory)
  (IdentityDiffRenderer, _) -> run (\ blob -> parse syntaxParser blob >>= decorate (syntaxDeclarationAlgebra blob)) diffTerms Just
  where effectiveLanguage = runBothWith (<|>) (blobLanguage <$> blobs)
        syntaxParser = parserForLanguage effectiveLanguage

        run :: Functor f => (Blob -> Task (Term f a)) -> (Both (Term f a) -> Diff f a) -> (Diff f a -> output) -> Task output
        run parse diff renderer = distributeFor blobs parse >>= diffTermPair blobs diff >>= render renderer

        diffRecursively :: (Declaration.Method :< fs, Apply1 Eq1 fs, Apply1 GAlign fs, Apply1 Show1 fs, Apply1 Foldable fs, Apply1 Functor fs, Apply1 Traversable fs, Apply1 Diffable fs) => Both (Term (Union fs) (Record fields)) -> Diff (Union fs) (Record fields)
        diffRecursively = decoratingWith constructorNameAndConstantFields (diffTermsWith algorithmForTerms comparableByConstructor)

-- | A task to diff a pair of 'Term's, producing insertion/deletion 'Patch'es for non-existent 'Blob's.
diffTermPair :: Functor f => Both Blob -> Differ f a -> Both (Term f a) -> Task (Diff f a)
diffTermPair blobs differ terms = case runJoin (blobExists <$> blobs) of
  (True, False) -> pure (deleting (Both.fst terms))
  (False, True) -> pure (inserting (Both.snd terms))
  _ -> time "diff" logInfo $ diff differ terms
  where
    logInfo = let (a, b) = runJoin blobs in
            [ ("before_path", blobPath a)
            , ("before_language", maybe "" show (blobLanguage a))
            , ("after_path", blobPath b)
            , ("after_language", maybe "" show (blobLanguage b)) ]


keepCategory :: HasField fields Category => Record fields -> Record '[Category]
keepCategory = (:. Nil) . category

keepConstructorLabel :: Record (ConstructorLabel ': fields) -> Record '[ConstructorLabel]
keepConstructorLabel = (:. Nil) . rhead
