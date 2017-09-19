{-# LANGUAGE DeriveAnyClass #-}
module Data.Syntax.Type where

import Algorithm
import Data.Align.Generic
import Data.Functor.Classes.Eq.Generic
import Data.Functor.Classes.Show.Generic
import GHC.Generics

data Annotation a = Annotation { annotationSubject :: !a, annotationType :: !a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Show, Traversable)

instance Eq1 Annotation where liftEq = genericLiftEq
instance Show1 Annotation where liftShowsPrec = genericLiftShowsPrec

newtype Product a = Product { productElements :: [a] }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Show, Traversable)

instance Eq1 Product where liftEq = genericLiftEq
instance Show1 Product where liftShowsPrec = genericLiftShowsPrec

data Array a = Array { arraySize :: Maybe a, arrayElementType :: a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Show, Traversable)

instance Eq1 Array where liftEq = genericLiftEq
instance Show1 Array where liftShowsPrec = genericLiftShowsPrec

data BiDirectionalChannel a = BiDirectionalChannel { biDirectionalChannelName :: a, biDirectionalChannelElementType :: a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Show, Traversable)

instance Eq1 BiDirectionalChannel where liftEq = genericLiftEq
instance Show1 BiDirectionalChannel where liftShowsPrec = genericLiftShowsPrec

data ReceiveChannel a = ReceiveChannel { receiveChannelName :: a, receiveChannelElementType :: a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Show, Traversable)

instance Eq1 ReceiveChannel where liftEq = genericLiftEq
instance Show1 ReceiveChannel where liftShowsPrec = genericLiftShowsPrec

data SendChannel a = SendChannel { sendChannelName :: a, sendChannelElementType :: a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Show, Traversable)

instance Eq1 SendChannel where liftEq = genericLiftEq
instance Show1 SendChannel where liftShowsPrec = genericLiftShowsPrec
