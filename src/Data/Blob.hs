module Data.Blob
( Blob(..)
, BlobKind(..)
, modeToDigits
, defaultPlainBlob
, emptyBlob
, nullBlob
, blobExists
, sourceBlob
, nullOid
) where

import Data.ByteString.Char8 (ByteString, pack)
import Data.Language
import Data.Maybe (isJust)
import Data.Source as Source
import Data.Word
import Numeric

-- | The source, oid, path, and Maybe BlobKind of a blob.
data Blob = Blob
  { blobSource :: Source -- ^ The UTF-8 encoded source text of the blob.
  , blobOid :: ByteString -- ^ The Git object ID (SHA-1) of the blob.
  , blobPath :: FilePath -- ^ The file path to the blob.
  , blobKind :: Maybe BlobKind -- ^ The kind of blob, Nothing denotes a blob that doesn't exist (e.g. on one side of a diff for adding a new file or deleting a file).
  , blobLanguage :: Maybe Language -- ^ The language of this blob. Nothing denotes a langauge we don't support yet.
  }
  deriving (Show, Eq)

-- | The kind and file mode of a 'Blob'.
data BlobKind = PlainBlob Word32 | ExecutableBlob Word32 | SymlinkBlob Word32
  deriving (Show, Eq)

modeToDigits :: BlobKind -> ByteString
modeToDigits (PlainBlob mode) = pack $ showOct mode ""
modeToDigits (ExecutableBlob mode) = pack $ showOct mode ""
modeToDigits (SymlinkBlob mode) = pack $ showOct mode ""

-- | The default plain blob mode
defaultPlainBlob :: BlobKind
defaultPlainBlob = PlainBlob 0o100644

emptyBlob :: FilePath -> Blob
emptyBlob filepath = Blob mempty nullOid filepath Nothing Nothing

nullBlob :: Blob -> Bool
nullBlob Blob{..} = blobOid == nullOid || nullSource blobSource

blobExists :: Blob -> Bool
blobExists Blob{..} = isJust blobKind

sourceBlob :: FilePath -> Maybe Language -> Source -> Blob
sourceBlob filepath language source = Blob source nullOid filepath (Just defaultPlainBlob) language

nullOid :: ByteString
nullOid = "0000000000000000000000000000000000000000"
