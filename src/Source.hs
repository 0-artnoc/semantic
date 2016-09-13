{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Source where

import Prologue hiding (uncons)
import Data.Text (unpack, pack)
import Data.String
import qualified Data.Vector as Vector
import Numeric
import Range
import SourceSpan

-- | The source, oid, path, and Maybe SourceKind of a blob in a Git repo.
data SourceBlob = SourceBlob { source :: Source Char, oid :: String, path :: FilePath, blobKind :: Maybe SourceKind }
  deriving (Show, Eq)

-- | The contents of a source file, backed by a vector for efficient slicing.
newtype Source a = Source { getVector :: Vector.Vector a  }
  deriving (Eq, Show, Foldable, Functor, Traversable)

-- | The kind of a blob, along with it's file mode.
data SourceKind = PlainBlob Word32  | ExecutableBlob Word32 | SymlinkBlob Word32
  deriving (Show, Eq)

modeToDigits :: SourceKind -> String
modeToDigits (PlainBlob mode) = showOct mode ""
modeToDigits (ExecutableBlob mode) = showOct mode ""
modeToDigits (SymlinkBlob mode) = showOct mode ""


-- | The default plain blob mode
defaultPlainBlob :: SourceKind
defaultPlainBlob = PlainBlob 0o100644

emptySourceBlob :: FilePath -> SourceBlob
emptySourceBlob filepath = SourceBlob (Source.fromList "")  Source.nullOid filepath Nothing

sourceBlob :: Source Char -> FilePath -> SourceBlob
sourceBlob source filepath = SourceBlob source Source.nullOid filepath (Just defaultPlainBlob)

-- | Map blobs with Nothing blobKind to empty blobs.
idOrEmptySourceBlob :: SourceBlob -> SourceBlob
idOrEmptySourceBlob blob = if isNothing (blobKind blob)
                           then blob { oid = nullOid, blobKind = Nothing }
                           else blob

nullOid :: String
nullOid = "0000000000000000000000000000000000000000"

-- | Return a Source from a list of items.
fromList :: [a] -> Source a
fromList = Source . Vector.fromList

-- | Return a Source of Chars from a Text.
fromText :: Text -> Source Char
fromText = Source . Vector.fromList . unpack

-- | Return a Source that contains a slice of the given Source.
slice :: Range -> Source a -> Source a
slice range = Source . Vector.slice (start range) (rangeLength range) . getVector

-- | Return a String with the contents of the Source.
toString :: Source Char -> String
toString = toList

-- | Return a text with the contents of the Source.
toText :: Source Char -> Text
toText = pack . toList

-- | Return the item at the given  index.
at :: Source a -> Int -> a
at = (Vector.!) . getVector

-- | Remove the first item and return it with the rest of the source.
uncons :: Source a -> Maybe (a, Source a)
uncons (Source vector) = if null vector then Nothing else Just (Vector.head vector, Source $ Vector.tail vector)

-- | Split the source into the longest prefix of elements that do not satisfy the predicate and the rest without copying.
break :: (a -> Bool) -> Source a -> (Source a, Source a)
break predicate (Source vector) = let (start, remainder) = Vector.break predicate vector in (Source start, Source remainder)

-- | Split the contents of the source after newlines.
actualLines :: Source Char -> [Source Char]
actualLines source | null source = [ source ]
actualLines source = case Source.break (== '\n') source of
  (l, lines') -> case uncons lines' of
    Nothing -> [ l ]
    Just (_, lines') -> (l <> fromList "\n") : actualLines lines'

-- | Compute the line ranges within a given range of a string.
actualLineRanges :: Range -> Source Char -> [Range]
actualLineRanges range = drop 1 . scanl toRange (Range (start range) (start range)) . actualLines . slice range
  where toRange previous string = Range (end previous) $ end previous + length string

-- | Compute the character range corresponding to a given SourceSpan within a Source.
sourceSpanToRange :: Source Char -> SourceSpan -> Range
sourceSpanToRange source SourceSpan{..} = Range start end
  where start = sumLengths leadingRanges + column spanStart
        end = start + sumLengths (take (line spanEnd - line spanStart) remainingRanges) + column spanEnd
        (leadingRanges, remainingRanges) = splitAt (line spanStart) (actualLineRanges (totalRange source) source)
        sumLengths = sum . fmap (\ Range{..} -> end - start)


instance Monoid (Source a) where
  mempty = fromList []
  mappend = (Source .) . (Vector.++) `on` getVector
