{-# LANGUAGE GADTs, RankNTypes, ScopedTypeVariables #-}
module Renderer.SExpression
( renderSExpressionDiff
, renderSExpressionTerm
) where

import Data.Bifunctor.Join
import Data.ByteString.Char8 hiding (foldr, spanEnd)
import Data.Record
import Data.Semigroup
import Diff
import Patch
import Prelude hiding (replicate)
import Term

-- | Returns a ByteString SExpression formatted diff.
renderSExpressionDiff :: (ConstrainAll Show fields, Foldable f) => Diff f (Record fields) -> ByteString
renderSExpressionDiff diff = printDiff diff 0 <> "\n"

-- | Returns a ByteString SExpression formatted term.
renderSExpressionTerm :: (ConstrainAll Show fields, Foldable f) => Term f (Record fields) -> ByteString
renderSExpressionTerm term = printTerm term 0 <> "\n"

printDiff :: (ConstrainAll Show fields, Foldable f) => Diff f (Record fields) -> Int -> ByteString
printDiff diff level = case unDiff diff of
  Patch patch -> case patch of
    Insert term -> pad (level - 1) <> "{+" <> printTerm term level <> "+}"
    Delete term -> pad (level - 1) <> "{-" <> printTerm term level <> "-}"
    Replace a b -> pad (level - 1) <> "{ " <> printTerm a level <> pad (level - 1) <> "->" <> printTerm b level <> " }"
  Copy (Join (_, annotation)) syntax -> pad' level <> "(" <> showAnnotation annotation <> foldr (\d acc -> printDiff d (level + 1) <> acc) "" syntax <> ")"
  where
    pad' :: Int -> ByteString
    pad' n = if n < 1 then "" else pad n
    pad :: Int -> ByteString
    pad n | n < 0 = ""
          | n < 1 = "\n"
          | otherwise = "\n" <> replicate (2 * n) ' '

printTerm :: (ConstrainAll Show fields, Foldable f) => Term f (Record fields) -> Int -> ByteString
printTerm term level = go term level 0
  where
    pad :: Int -> Int -> ByteString
    pad p n | n < 1 = ""
            | otherwise = "\n" <> replicate (2 * (p + n)) ' '
    go :: (ConstrainAll Show fields, Foldable f) => Term f (Record fields) -> Int -> Int -> ByteString
    go (Term (annotation :< syntax)) parentLevel level =
      pad parentLevel level <> "(" <> showAnnotation annotation <> foldr (\t acc -> go t parentLevel (level + 1) <> acc) "" syntax <> ")"

showAnnotation :: ConstrainAll Show fields => Record fields -> ByteString
showAnnotation Nil = ""
showAnnotation (only :. Nil) = pack (show only)
showAnnotation (first :. rest) = pack (show first) <> " " <> showAnnotation rest
