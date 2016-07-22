{-# LANGUAGE RankNTypes, ScopedTypeVariables #-}
module Alignment
( hasChanges
, numberedRows
, alignDiff
, alignBranch
, applyThese
, modifyJoin
) where

import Control.Arrow ((***))
import Data.Align
import Data.Biapplicative
import Data.Bifunctor.Join
import Data.Function
import Data.Functor.Both as Both
import Data.Functor.Foldable (hylo)
import Data.List (partition)
import Data.Maybe (fromJust)
import Data.Record
import Data.These
import Diff
import Info
import Patch
import Prologue hiding (fst, snd)
import Range
import Source hiding (break, fromList, uncons, (++))
import SplitDiff
import Syntax
import Term

-- | Assign line numbers to the lines on each side of a list of rows.
numberedRows :: [Join These a] -> [Join These (Int, a)]
numberedRows = countUp (both 1 1)
  where countUp _ [] = []
        countUp from (row : rows) = numberedLine from row : countUp (nextLineNumbers from row) rows
        numberedLine from row = fromJust ((,) <$> modifyJoin (uncurry These) from `applyThese` row)
        nextLineNumbers from row = modifyJoin (fromThese identity identity) (succ <$ row) <*> from

-- | Determine whether a line contains any patches.
hasChanges :: SplitDiff leaf annotation -> Bool
hasChanges = or . (True <$)

-- | Align a Diff into a list of Join These SplitDiffs representing the (possibly blank) lines on either side.
alignDiff :: HasField fields Range => Both (Source Char) -> Diff leaf (Record fields) -> [Join These (SplitDiff leaf (Record fields))]
alignDiff sources diff = iter (alignSyntax (runBothWith ((Join .) . These)) wrap getRange sources) (alignPatch sources <$> diff)

-- | Align the contents of a patch into a list of lines on the corresponding side(s) of the diff.
alignPatch :: forall fields leaf. HasField fields Range => Both (Source Char) -> Patch (Term leaf (Record fields)) -> [Join These (SplitDiff leaf (Record fields))]
alignPatch sources patch = case patch of
  Delete term -> fmap (pure . SplitDelete) <$> alignSyntax' this (fst sources) term
  Insert term -> fmap (pure . SplitInsert) <$> alignSyntax' that (snd sources) term
  Replace term1 term2 -> fmap (pure . SplitReplace) <$> alignWith (fmap (these identity identity const . runJoin) . Join)
    (alignSyntax' this (fst sources) term1)
    (alignSyntax' that (snd sources) term2)
  where getRange = characterRange . extract
        alignSyntax' :: (forall a. Identity a -> Join These a) -> Source Char -> Term leaf (Record fields) -> [Join These (Term leaf (Record fields))]
        alignSyntax' side source term = hylo (alignSyntax side cofree getRange (Identity source)) runCofree (Identity <$> term)
        this = Join . This . runIdentity
        that = Join . That . runIdentity

-- | The Applicative instance f is either Identity or Both. Identity is for Terms in Patches, Both is for Diffs in unchanged portions of the diff.
alignSyntax :: (Applicative f, HasField fields Range) => (forall a. f a -> Join These a) -> (CofreeF (Syntax leaf) (Record fields) term -> term) -> (term -> Range) -> f (Source Char) -> CofreeF (Syntax leaf) (f (Record fields)) [Join These term] -> [Join These term]
alignSyntax toJoinThese toNode getRange sources (infos :< syntax) = case syntax of
  Leaf s -> catMaybes $ wrapInBranch (const (Leaf s)) <$> alignBranch getRange [] bothRanges
  Comment a -> catMaybes $ wrapInBranch (const (Comment a)) <$> alignBranch getRange [] bothRanges
  Indexed children ->
    catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (join children) bothRanges
  Syntax.Function id params body -> catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (fromMaybe [] id <> fromMaybe []  params <> body) bothRanges
  -- Align FunctionCalls like Indexed nodes by appending identifier to its children.
  Syntax.FunctionCall identifier children ->
    catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (join (identifier : children)) bothRanges
  Syntax.Assignment assignmentId value ->
    catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (assignmentId <> value) bothRanges
  Syntax.MemberAccess memberId property ->
    catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (memberId <> property) bothRanges
  Syntax.MethodCall targetId methodId args ->
    catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (targetId <> methodId <> args) bothRanges
  Syntax.Args children ->
    catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (join children) bothRanges
  Syntax.VarDecl decl ->
    catMaybes $ wrapInBranch Indexed <$> alignBranch getRange decl bothRanges
  Syntax.VarAssignment id value ->
    catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (id <> value) bothRanges
  Switch expr cases ->
    catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (expr <> join cases) bothRanges
  Case expr body ->
    catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (expr <> body) bothRanges
  Fixed children ->
    catMaybes $ wrapInBranch Fixed <$> alignBranch getRange (join children) bothRanges
  Pair a b -> catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (a <> b) bothRanges
  Object children -> catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (join children) bothRanges
  Commented cs expr -> catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (join cs <> join (maybeToList expr)) bothRanges
  Ternary expr cases -> catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (expr <> join cases) bothRanges
  Operator cases -> catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (join cases) bothRanges
  MathAssignment key value -> catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (key <> value) bothRanges
  SubscriptAccess key value -> catMaybes $ wrapInBranch Indexed <$> alignBranch getRange (key <> value) bothRanges
  where bothRanges = modifyJoin (fromThese [] []) lineRanges
        lineRanges = toJoinThese $ actualLineRanges <$> (characterRange <$> infos) <*> sources
        wrapInBranch constructor = applyThese $ toJoinThese ((\ info (range, children) -> toNode (setCharacterRange info range :< constructor children)) <$> infos)

-- | Given a function to get the range, a list of already-aligned children, and the lists of ranges spanned by a branch, return the aligned lines.
alignBranch :: (term -> Range) -> [Join These term] -> Both [Range] -> [Join These (Range, [term])]
-- There are no more ranges, so we’re done.
alignBranch _ _ (Join ([], [])) = []
-- There are no more children, so we can just zip the remaining ranges together.
alignBranch _ [] ranges = runBothWith (alignWith Join) (fmap (flip (,) []) <$> ranges)
-- There are both children and ranges, so we need to proceed line by line
alignBranch getRange children ranges = case intersectingChildren of
  -- No child intersects the current ranges on either side, so advance.
  [] -> (flip (,) [] <$> headRanges) : alignBranch getRange children (drop 1 <$> ranges)
  -- At least one child intersects on at least one side.
  _ -> case intersectionsWithHeadRanges <$> listToMaybe symmetricalChildren of
    -- At least one child intersects on both sides, so align symmetrically.
    Just (True, True) -> let (line, remaining) = lineAndRemaining intersectingChildren (Just headRanges) in
      line $ alignBranch getRange (remaining <> nonIntersectingChildren) (drop 1 <$> ranges)
    -- A symmetrical child intersects on the right, so align asymmetrically on the left.
    Just (False, True) -> alignAsymmetrically leftRange first
    -- A symmetrical child intersects on the left, so align asymmetrically on the right.
    Just (True, False) -> alignAsymmetrically rightRange second
    -- No symmetrical child intersects, so align asymmetrically, picking the left side first to match the deletion/insertion order convention in diffs.
    _ -> if any (isThis . runJoin) asymmetricalChildren
         then alignAsymmetrically leftRange first
         else alignAsymmetrically rightRange second
  where (intersectingChildren, nonIntersectingChildren) = partition (or . intersects getRange headRanges) children
        (symmetricalChildren, asymmetricalChildren) = partition (isThese . runJoin) intersectingChildren
        intersectionsWithHeadRanges = fromThese True True . runJoin . intersects getRange headRanges
        Just headRanges = Join <$> bisequenceL (runJoin (listToMaybe <$> Join (runBothWith These ranges)))
        (leftRange, rightRange) = splitThese headRanges
        alignAsymmetrically range advanceBy = let (line, remaining) = lineAndRemaining asymmetricalChildren range in
          line $ alignBranch getRange (remaining <> symmetricalChildren <> nonIntersectingChildren) (modifyJoin (advanceBy (drop 1)) ranges)
        lineAndRemaining _ Nothing = (identity, [])
        lineAndRemaining children (Just ranges) = let (intersections, remaining) = alignChildren getRange children ranges in
          ((:) $ (,) <$> ranges `applyToBoth` (sortBy (compare `on` getRange) <$> intersections), remaining)

-- | Given a list of aligned children, produce lists of their intersecting first lines, and a list of the remaining lines/nonintersecting first lines.
alignChildren :: (term -> Range) -> [Join These term] -> Join These Range -> (Both [term], [Join These term])
alignChildren _ [] _ = (both [] [], [])
alignChildren getRange (first:rest) headRanges
  | ~(l, r) <- splitThese first
  = case intersectionsWithHeadRanges first of
    -- It intersects on both sides, so we can just take the first line whole.
    (True, True) -> ((<>) <$> toTerms first <*> firstRemaining, restRemaining)
    -- It only intersects on the left, so split it up.
    (True, False) -> ((<>) <$> toTerms (fromJust l) <*> firstRemaining, maybe identity (:) r restRemaining)
    -- It only intersects on the right, so split it up.
    (False, True) -> ((<>) <$> toTerms (fromJust r) <*> firstRemaining, maybe identity (:) l restRemaining)
    -- It doesn’t intersect at all, so skip it and move along.
    (False, False) -> (firstRemaining, first:restRemaining)
  | otherwise = alignChildren getRange rest headRanges
  where (firstRemaining, restRemaining) = alignChildren getRange rest headRanges
        toTerms line = modifyJoin (fromThese [] []) (pure <$> line)
        intersectionsWithHeadRanges = fromThese False False . runJoin . intersects getRange headRanges

-- | Test ranges and terms for intersection on either or both sides.
intersects :: (term -> Range) -> Join These Range -> Join These term -> Join These Bool
intersects getRange ranges line = intersectsRange <$> ranges `applyToBoth` modifyJoin (fromThese (Range (-1) (-1)) (Range (-1) (-1))) (getRange <$> line)

-- | Split a These value up into independent These values representing the left and right sides, if any.
splitThese :: Join These a -> (Maybe (Join These a), Maybe (Join These a))
splitThese these = fromThese Nothing Nothing $ bimap (Just . Join . This) (Just . Join . That) (runJoin these)

infixl 4 `applyThese`

-- | Like `<*>`, but it returns its result in `Maybe` since the result is the intersection of the shapes of the inputs.
applyThese :: Join These (a -> b) -> Join These a -> Maybe (Join These b)
applyThese (Join fg) (Join ab) = fmap Join . uncurry maybeThese $ uncurry (***) (bimap (<*>) (<*>) (unpack fg)) (unpack ab)
  where unpack = fromThese Nothing Nothing . bimap Just Just

infixl 4 `applyToBoth`

-- | Like `<*>`, but it takes a `Both` on the right to ensure that it can always return a value.
applyToBoth :: Join These (a -> b) -> Both a -> Join These b
applyToBoth (Join fg) (Join (a, b)) = Join $ these (This . ($ a)) (That . ($ b)) (\ f g -> These (f a) (g b)) fg

-- Map over the bifunctor inside a Join, producing another Join.
modifyJoin :: (p a a -> q b b) -> Join p a -> Join q b
modifyJoin f = Join . f . runJoin

-- | Given a pair of Maybes, produce a These containing Just their values, or Nothing if they haven’t any.
maybeThese :: Maybe a -> Maybe b -> Maybe (These a b)
maybeThese (Just a) (Just b) = Just (These a b)
maybeThese (Just a) _ = Just (This a)
maybeThese _ (Just b) = Just (That b)
maybeThese _ _ = Nothing
