module Data.Functor.Classes.Eq.Generic
( genericLiftEq
) where

import GHC.Generics
import Prologue

-- | Generically-derivable lifting of the 'Eq' class to unary type constructors.
class GEq1 f where
  -- | Lift an equality test through the type constructor.
  --
  --   The function will usually be applied to an equality function, but the more general type ensures that the implementation uses it to compare elements of the first container with elements of the second.
  gliftEq :: (a -> b -> Bool) -> f a -> f b -> Bool

-- | A suitable implementation of Eq1’s liftEq for Generic1 types.
genericLiftEq :: (Generic1 f, GEq1 (Rep1 f)) => (a -> b -> Bool) -> f a -> f b -> Bool
genericLiftEq f a b = gliftEq f (from1 a) (from1 b)


-- Generics

instance GEq1 U1 where
  gliftEq _ _ _ = True

instance GEq1 Par1 where
  gliftEq f (Par1 a) (Par1 b) = f a b

instance Eq c => GEq1 (K1 i c) where
  gliftEq _ (K1 a) (K1 b) = a == b
