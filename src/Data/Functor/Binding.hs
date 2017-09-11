{-# LANGUAGE DerivingStrategies, GADTs, GeneralizedNewtypeDeriving, NoStrictData, RankNTypes #-}
module Data.Functor.Binding
( Metavar(..)
-- Abstract binding trees
, BindingF(..)
, bindings
, freeMetavariables
, maxBoundMetavariable
, letBind
, hoistBindingF
-- Environments
, Env(..)
, envExtend
, envLookup
) where

import Data.Aeson (KeyValue(..), ToJSON(..), object, pairs)
import Data.Foldable (fold)
import Data.Functor.Classes
import Data.Functor.Foldable hiding (fold)
import Data.JSON.Fields
import qualified Data.Set as Set
import Data.Text.Prettyprint.Doc

newtype Metavar = Metavar Int
  deriving (Eq, Ord, Show)
  deriving newtype (Enum, ToJSON)


data BindingF f recur
  = Let [(Metavar, recur)] (f recur)
  | Var Metavar
  deriving (Foldable, Functor, Traversable)

bindings :: BindingF f recur -> [(Metavar, recur)]
bindings (Let vars _) = vars
bindings _            = []


freeMetavariables :: (Foldable syntax, Functor syntax, Recursive t, Base t ~ BindingF syntax) => t -> Set.Set Metavar
freeMetavariables = cata $ \ diff -> case diff of
  Let bindings body -> foldMap snd bindings <> foldr Set.delete (fold body) (fst <$> bindings)
  Var v -> Set.singleton v

maxBoundMetavariable :: (Foldable syntax, Functor syntax, Recursive t, Base t ~ BindingF syntax) => t -> Maybe Metavar
maxBoundMetavariable = cata $ \ diff -> case diff of
  Let bindings _ -> foldMaxMap (Just . fst) bindings
  Var _ -> Nothing

foldMaxMap :: (Foldable t, Ord b) => (a -> Maybe b) -> t a -> Maybe b
foldMaxMap f = foldr (max . f) Nothing


letBind :: (Foldable syntax, Functor syntax, Corecursive t, Recursive t, Base t ~ BindingF syntax) => t -> (Metavar -> syntax t) -> t
letBind diff f = embed (Let [(n, diff)] body)
  where body = f n
        n = maybe (Metavar 0) succ (foldMaxMap maxBoundMetavariable body)


hoistBindingF :: (forall a. f a -> g a) -> BindingF f a -> BindingF g a
hoistBindingF f (Let vars body) = Let vars (f body)
hoistBindingF _ (Var v) = Var v


newtype Env a = Env { unEnv :: [(Metavar, a)] }
  deriving (Eq, Foldable, Functor, Monoid, Ord, Show, Traversable)

envExtend :: Metavar -> a -> Env a -> Env a
envExtend var val (Env m) = Env ((var, val) : m)

envLookup :: Metavar -> Env a -> Maybe a
envLookup var = lookup var . unEnv


instance Eq1 f => Eq1 (BindingF f) where
  liftEq eq (Let v1 b1) (Let v2 b2) = liftEq (liftEq eq) v1 v2 && liftEq eq b1 b2
  liftEq _  (Var v1)    (Var v2)    = v1 == v2
  liftEq _  _           _           = False

instance (Eq1 f, Eq a) => Eq (BindingF f a) where
  (==) = eq1


instance Show1 f => Show1 (BindingF f) where
  liftShowsPrec sp sl d (Let vars body) = showsBinaryWith (const (liftShowList sp sl)) (liftShowsPrec sp sl) "Let" d vars body
  liftShowsPrec _  _  d (Var var)       = showsUnaryWith showsPrec "Var" d var

instance (Show1 f, Show a) => Show (BindingF f a) where
  showsPrec = showsPrec1


instance Pretty Metavar where
  pretty (Metavar v) = pretty v

instance Pretty1 f => Pretty1 (BindingF f) where
  liftPretty p pl (Let vars body) = pretty ("let" :: String) <+> align (vsep (prettyKV <$> vars)) <> line
                                 <> pretty ("in" :: String)  <+> liftPretty p pl body
    where prettyKV (var, val) = pretty var <+> pretty '=' <+> p val
  liftPretty _ _  (Var metavar)   = pretty metavar

instance (Pretty1 f, Pretty a) => Pretty (BindingF f a) where
  pretty = liftPretty pretty prettyList


instance ToJSONFields1 f => ToJSONFields1 (BindingF f) where
  toJSONFields1 (Let vars body) = [ "vars" .= vars ] <> toJSONFields1 body
  toJSONFields1 (Var v)         = [ "metavar" .= v ]

instance (ToJSONFields1 f, ToJSON a) => ToJSONFields (BindingF f a) where
  toJSONFields = toJSONFields1

instance (ToJSON a, ToJSONFields1 f) => ToJSON (BindingF f a) where
  toJSON = object . toJSONFields1
  toEncoding = pairs . mconcat . toJSONFields1
