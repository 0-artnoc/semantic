{-# LANGUAGE DeriveAnyClass #-}
module Data.Syntax.Expression where

import Algorithm
import Data.Align.Generic
import Data.Functor.Classes.Eq.Generic
import Data.Functor.Classes.Pretty.Generic
import Data.Functor.Classes.Show.Generic
import GHC.Generics

-- | Typical prefix function application, like `f(x)` in many languages, or `f x` in Haskell.
data Call a = Call { callFunction :: !a, callParams :: ![a], callBlock :: !a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Show, Traversable)

instance Eq1 Call where liftEq = genericLiftEq
instance Show1 Call where liftShowsPrec = genericLiftShowsPrec
instance Pretty1 Call where liftPretty = genericLiftPretty


data Comparison a
  = LessThan !a !a
  | LessThanEqual !a !a
  | GreaterThan !a !a
  | GreaterThanEqual !a !a
  | Equal !a !a
  | Comparison !a !a
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Show, Traversable)

instance Eq1 Comparison where liftEq = genericLiftEq
instance Show1 Comparison where liftShowsPrec = genericLiftShowsPrec
instance Pretty1 Comparison where liftPretty = genericLiftPretty


-- | Binary arithmetic operators.
data Arithmetic a
  = Plus !a !a
  | Minus !a !a
  | Times !a !a
  | DividedBy !a !a
  | Modulo !a !a
  | Power !a !a
  | Negate !a
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Show, Traversable)

instance Eq1 Arithmetic where liftEq = genericLiftEq
instance Show1 Arithmetic where liftShowsPrec = genericLiftShowsPrec
instance Pretty1 Arithmetic where liftPretty = genericLiftPretty

-- | Boolean operators.
data Boolean a
  = Or !a !a
  | And !a !a
  | Not !a
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Show, Traversable)

instance Eq1 Boolean where liftEq = genericLiftEq
instance Show1 Boolean where liftShowsPrec = genericLiftShowsPrec
instance Pretty1 Boolean where liftPretty = genericLiftPretty

-- | Bitwise operators.
data Bitwise a
  = BOr !a !a
  | BAnd !a !a
  | BXOr !a !a
  | LShift !a !a
  | RShift !a !a
  | Complement a
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Show, Traversable)

instance Eq1 Bitwise where liftEq = genericLiftEq
instance Show1 Bitwise where liftShowsPrec = genericLiftShowsPrec
instance Pretty1 Bitwise where liftPretty = genericLiftPretty

-- | Member Access (e.g. a.b)
data MemberAccess a
  = MemberAccess !a !a
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Show, Traversable)

instance Eq1 MemberAccess where liftEq = genericLiftEq
instance Show1 MemberAccess where liftShowsPrec = genericLiftShowsPrec
instance Pretty1 MemberAccess where liftPretty = genericLiftPretty

-- | Subscript (e.g a[1])
data Subscript a
  = Subscript !a ![a]
  | Member !a !a
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Show, Traversable)

instance Eq1 Subscript where liftEq = genericLiftEq
instance Show1 Subscript where liftShowsPrec = genericLiftShowsPrec
instance Pretty1 Subscript where liftPretty = genericLiftPretty

-- | Enumeration (e.g. a[1:10:1] in Python (start at index 1, stop at index 10, step 1 element from start to stop))
data Enumeration a = Enumeration { enumerationStart :: !a, enumerationEnd :: !a, enumerationStep :: !a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Show, Traversable)

instance Eq1 Enumeration where liftEq = genericLiftEq
instance Show1 Enumeration where liftShowsPrec = genericLiftShowsPrec
instance Pretty1 Enumeration where liftPretty = genericLiftPretty

-- | ScopeResolution (e.g. import a.b in Python or a::b in C++)
data ScopeResolution a
  = ScopeResolution ![a]
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Show, Traversable)

instance Eq1 ScopeResolution where liftEq = genericLiftEq
instance Show1 ScopeResolution where liftShowsPrec = genericLiftShowsPrec
instance Pretty1 ScopeResolution where liftPretty = genericLiftPretty
