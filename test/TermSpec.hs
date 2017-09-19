{-# LANGUAGE DataKinds #-}
module TermSpec where

import Category
import Data.Functor.Listable
import Data.Record
import Syntax
import Term
import Test.Hspec (Spec, describe, parallel)
import Test.Hspec.Expectations.Pretty
import Test.Hspec.LeanCheck

spec :: Spec
spec = parallel $ do
  describe "Term" $ do
    prop "equality is reflexive" $
      \ a -> unListableF a `shouldBe` (unListableF a :: Term Syntax (Record '[Category]))
