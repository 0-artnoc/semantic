{-# LANGUAGE ConstraintKinds, DataKinds, GADTs, KindSignatures, MultiParamTypeClasses, TypeFamilies, TypeOperators, UndecidableInstances #-}
module Data.Record where

import Control.DeepSeq
import Data.Kind
import Data.Functor.Listable
import Data.Semigroup
import Data.Text.Prettyprint.Doc

-- | A type-safe, extensible record structure.
-- |
-- | This is heavily inspired by Aaron Levin’s [Extensible Effects in the van Laarhoven Free Monad](http://aaronlevin.ca/post/136494428283/extensible-effects-in-the-van-laarhoven-free-monad).
data Record :: [*] -> * where
  Nil :: Record '[]
  (:.) :: h -> Record t -> Record (h ': t)

infixr 0 :.

-- | Get the first element of a non-empty record.
rhead :: Record (head ': tail) -> head
rhead (head :. _) = head

-- | Get the first element of a non-empty record.
rtail :: Record (head ': tail) -> Record tail
rtail (_ :. tail) = tail


-- Classes

-- | HasField enables indexing a Record by (phantom) type tags.
class HasField (fields :: [*]) (field :: *) where
  getField :: Record fields -> field
  setField :: Record fields -> field -> Record fields

type family ConstrainAll (toConstraint :: * -> Constraint) (fs :: [*]) :: Constraint where
  ConstrainAll toConstraint (f ': fs) = (toConstraint f, ConstrainAll toConstraint fs)
  ConstrainAll _ '[] = ()


-- Instances

-- OVERLAPPABLE is required for the HasField instances so that we can handle the two cases: either the head of the non-empty h-list is the requested field, or it isn’t. The third possible case (the h-list is empty) is rejected at compile-time.

instance {-# OVERLAPPABLE #-} HasField fields field => HasField (notIt ': fields) field where
  getField (_ :. t) = getField t
  setField (h :. t) f = h :. setField t f

instance {-# OVERLAPPABLE #-} HasField (field ': fields) field where
  getField (h :. _) = h
  setField (_ :. t) f = f :. t

instance (NFData h, NFData (Record t)) => NFData (Record (h ': t)) where
  rnf (h :. t) = rnf h `seq` rnf t `seq` ()

instance NFData (Record '[]) where
  rnf _ = ()

instance (Show h, Show (Record t)) => Show (Record (h ': t)) where
  showsPrec n (h :. t) = showParen (n > 0) $ showsPrec 1 h . (" :. " <>) . shows t

instance Show (Record '[]) where
  showsPrec n Nil = showParen (n > 0) ("Nil" <>)

instance (Eq h, Eq (Record t)) => Eq (Record (h ': t)) where
  (h1 :. t1) == (h2 :. t2) = h1 == h2 && t1 == t2

instance Eq (Record '[]) where
  _ == _ = True


instance (Ord h, Ord (Record t)) => Ord (Record (h ': t)) where
  (h1 :. t1) `compare` (h2 :. t2) = let h = h1 `compare` h2 in
    if h == EQ then t1 `compare` t2 else h

instance Ord (Record '[]) where
  _ `compare` _ = EQ


instance (Listable head, Listable (Record tail)) => Listable (Record (head ': tail)) where
  tiers = cons2 (:.)

instance Listable (Record '[]) where
  tiers = cons0 Nil


instance (Semigroup head, Semigroup (Record tail)) => Semigroup (Record (head ': tail)) where
  (h1 :. t1) <> (h2 :. t2) = (h1 <> h2) :. (t1 <> t2)

instance Semigroup (Record '[]) where
  _ <> _ = Nil


instance ConstrainAll Pretty ts => Pretty (Record ts) where
  pretty = tupled . collectPretty
    where collectPretty :: ConstrainAll Pretty ts => Record ts -> [Doc ann]
          collectPretty Nil = []
          collectPretty (first :. rest) = pretty first : collectPretty rest
