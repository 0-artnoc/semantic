{-# LANGUAGE DeriveAnyClass #-}
module Data.Syntax.Comment where

import Algorithm
import Data.Align.Generic
import Data.ByteString (ByteString)
import Data.Functor.Classes.Eq.Generic
import Data.Functor.Classes.Pretty.Orphans
import Data.Functor.Classes.Show.Generic
import GHC.Generics

-- | An unnested comment (line or block).
newtype Comment a = Comment { commentContent :: ByteString }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Pretty1, Show, Traversable)

instance Eq1 Comment where liftEq = genericLiftEq
instance Show1 Comment where liftShowsPrec = genericLiftShowsPrec

-- TODO: nested comment types
-- TODO: documentation comment types
-- TODO: literate programming comment types? alternatively, consider those as markup
-- TODO: Differentiate between line/block comments?
