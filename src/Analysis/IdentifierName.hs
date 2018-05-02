{-# LANGUAGE ScopedTypeVariables, TypeFamilies, TypeOperators, UndecidableInstances #-}
module Analysis.IdentifierName
( IdentifierName(..)
, IdentifierLabel(..)
, identifierLabel
) where

import           Data.Abstract.FreeVariables (Name (..))
import           Data.Aeson
import           Data.JSON.Fields
import           Data.Sum
import qualified Data.Syntax
import           Data.Term
import           Data.Text.Encoding (decodeUtf8)
import           Prologue

-- | Compute a 'IdentifierLabel' label for a 'Term'.
identifierLabel :: IdentifierName syntax => TermF syntax a b -> Maybe IdentifierLabel
identifierLabel (In _ s) = IdentifierLabel <$> identifierName s

newtype IdentifierLabel = IdentifierLabel ByteString
  deriving (Show)

instance ToJSONFields IdentifierLabel where
  toJSONFields (IdentifierLabel s) = [ "name" .= decodeUtf8 s ]


-- | A typeclass to retrieve the name of syntax identifiers.
--
--   This typeclass employs the Advanced Overlap techniques designed by Oleg Kiselyov & Simon Peyton Jones: https://wiki.haskell.org/GHC/AdvancedOverlap; see also src/Analysis/Declaration.hs for discussion of the details of the mechanism.
class IdentifierName syntax where
  identifierName :: syntax a -> Maybe ByteString

instance (IdentifierNameStrategy syntax ~ strategy, IdentifierNameWithStrategy strategy syntax) => IdentifierName syntax where
  identifierName = identifierNameWithStrategy (Proxy :: Proxy strategy)

class CustomIdentifierName syntax where
  customIdentifierName :: syntax a -> Maybe ByteString

instance Apply IdentifierName fs => CustomIdentifierName (Sum fs) where
  customIdentifierName = apply (Proxy :: Proxy IdentifierName) identifierName

instance CustomIdentifierName Data.Syntax.Identifier where
  customIdentifierName (Data.Syntax.Identifier (Name name)) = Just name

data Strategy = Default | Custom

type family IdentifierNameStrategy syntax where
  IdentifierNameStrategy (Sum _) = 'Custom
  IdentifierNameStrategy Data.Syntax.Identifier = 'Custom
  IdentifierNameStrategy syntax = 'Default

class IdentifierNameWithStrategy (strategy :: Strategy) syntax where
  identifierNameWithStrategy :: proxy strategy -> syntax a -> Maybe ByteString

instance IdentifierNameWithStrategy 'Default syntax where
  identifierNameWithStrategy _ _ = Nothing

instance (CustomIdentifierName syntax) => IdentifierNameWithStrategy 'Custom syntax where
  identifierNameWithStrategy _ = customIdentifierName
