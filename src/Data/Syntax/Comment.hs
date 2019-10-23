{-# LANGUAGE DeriveAnyClass, DerivingVia, MultiParamTypeClasses #-}
{-# OPTIONS_GHC -Wno-missing-export-lists #-}
module Data.Syntax.Comment where

import Prologue

import Data.Abstract.Evaluatable
import Data.JSON.Fields
import Diffing.Algorithm

-- | An unnested comment (line or block).
newtype Comment a = Comment { commentContent :: Text }
  deriving (Diffable, Foldable, Functor, Generic1, Hashable1, Traversable, FreeVariables1, Declarations1, ToJSONFields1, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically Comment

instance Evaluatable Comment where
  eval _ _ _ = unit

-- TODO: nested comment types
-- TODO: documentation comment types
-- TODO: literate programming comment types? alternatively, consider those as markup
-- TODO: Differentiate between line/block comments?

-- | HashBang line (e.g. `#!/usr/bin/env node`)
newtype HashBang a = HashBang { value :: Text }
  deriving (Diffable, Foldable, Functor, Generic1, Hashable1, Traversable, FreeVariables1, Declarations1, ToJSONFields1, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically HashBang

-- TODO: Implement Eval instance for HashBang
instance Evaluatable HashBang
