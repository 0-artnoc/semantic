module Source.Spec where

import qualified Prelude
import Prologue
import Range
import Source
import SourceSpan
import Test.Hspec
import Test.Hspec.QuickCheck

spec :: Spec
spec = parallel $ do
  describe "actualLineRanges" $ do
    prop "produces 1 more range than there are newlines" $
      \ s -> length (actualLineRanges (totalRange s) (fromList s)) `shouldBe` succ (length (filter (== '\n') s))

    prop "produces exhaustive ranges" $
      \ s -> let source = fromList s in
        foldMap (`slice` source) (actualLineRanges (totalRange s) source) `shouldBe` source

  describe "sourceSpanToRange" $ do
    prop "computes single-line ranges" $
      \ s -> let source = fromList s
                 spans = zipWith (\ i Range {..} -> SourceSpan "" (SourcePos i 0) (SourcePos i (end - start))) [0..] ranges
                 ranges = actualLineRanges (totalRange source) source in
        sourceSpanToRange source <$> spans `shouldBe` ranges

    prop "computes multi-line ranges" $
      \ s -> let source = fromList s
                 ranges = actualLineRanges (totalRange source) source in
        sourceSpanToRange source (totalSpan source) `shouldBe` totalRange source

  describe "totalSpan" $ do
    prop "covers single lines" $
      \ n -> totalSpan (fromList (replicate n '*')) `shouldBe` SourceSpan "" (SourcePos 0 0) (SourcePos 0 (max 0 n))

    prop "covers multiple lines" $
      \ n -> totalSpan (fromList (intersperse '\n' (replicate n '*'))) `shouldBe` SourceSpan "" (SourcePos 0 0) (SourcePos (max 0 (pred n)) (if n > 0 then 1 else 0))

totalSpan :: Source Char -> SourceSpan
totalSpan source = SourceSpan "" (SourcePos 0 0) (SourcePos (pred (length ranges)) (end lastRange - start lastRange))
  where ranges = actualLineRanges (totalRange source) source
        lastRange = Prelude.last ranges

insetSpan :: SourceSpan -> SourceSpan
insetSpan sourceSpan = sourceSpan { spanStart = (spanStart sourceSpan) { column = succ (column (spanStart sourceSpan)) }
                                  , spanEnd = (spanEnd sourceSpan) { column = pred (column (spanEnd sourceSpan)) } }

insetRange :: Range -> Range
insetRange Range {..} = Range (succ start) (pred end)
