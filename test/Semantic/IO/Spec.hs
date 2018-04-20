module Semantic.IO.Spec (spec) where

import Prelude hiding (readFile)
import Semantic.IO
import System.Exit (ExitCode(..))
import System.IO (IOMode(..), openFile)

import SpecHelpers


spec :: Spec
spec = parallel $ do
  describe "readFile" $ do
    it "returns a blob for extant files" $ do
      Just blob <- readFile "semantic.cabal" Nothing
      blobPath blob `shouldBe` "semantic.cabal"

    it "throws for absent files" $ do
      readFile "this file should not exist" Nothing `shouldThrow` anyIOException

  describe "readBlobPairsFromHandle" $ do
    let a = sourceBlob "method.rb" (Just Ruby) "def foo; end"
    let b = sourceBlob "method.rb" (Just Ruby) "def bar(x); end"
    it "returns blobs for valid JSON encoded diff input" $ do
      blobs <- blobsFromFilePath "test/fixtures/cli/diff.json"
      blobs `shouldBe` [blobPairDiffing a b]

    it "returns blobs when there's no before" $ do
      blobs <- blobsFromFilePath "test/fixtures/cli/diff-no-before.json"
      blobs `shouldBe` [blobPairInserting b]

    it "returns blobs when there's null before" $ do
      blobs <- blobsFromFilePath "test/fixtures/cli/diff-null-before.json"
      blobs `shouldBe` [blobPairInserting b]

    it "returns blobs when there's no after" $ do
      blobs <- blobsFromFilePath "test/fixtures/cli/diff-no-after.json"
      blobs `shouldBe` [blobPairDeleting a]

    it "returns blobs when there's null after" $ do
      blobs <- blobsFromFilePath "test/fixtures/cli/diff-null-after.json"
      blobs `shouldBe` [blobPairDeleting a]


    it "returns blobs for unsupported language" $ do
      h <- openFile "test/fixtures/cli/diff-unsupported-language.json" ReadMode
      blobs <- readBlobPairsFromHandle h
      let b' = sourceBlob "test.kt" Nothing "fun main(args: Array<String>) {\nprintln(\"hi\")\n}\n"
      blobs `shouldBe` [blobPairInserting b']

    it "detects language based on filepath for empty language" $ do
      blobs <- blobsFromFilePath "test/fixtures/cli/diff-empty-language.json"
      blobs `shouldBe` [blobPairDiffing a b]

    it "throws on blank input" $ do
      h <- openFile "test/fixtures/cli/blank.json" ReadMode
      readBlobPairsFromHandle h `shouldThrow` (== ExitFailure 1)

    it "throws if language field not given" $ do
      h <- openFile "test/fixtures/cli/diff-no-language.json" ReadMode
      readBlobsFromHandle h `shouldThrow` (== ExitFailure 1)

    it "throws if null on before and after" $ do
      h <- openFile "test/fixtures/cli/diff-null-both-sides.json" ReadMode
      readBlobPairsFromHandle h `shouldThrow` (== ExitFailure 1)

  describe "readBlobsFromHandle" $ do
    it "returns blobs for valid JSON encoded parse input" $ do
      h <- openFile "test/fixtures/cli/parse.json" ReadMode
      blobs <- readBlobsFromHandle h
      let a = sourceBlob "method.rb" (Just Ruby) "def foo; end"
      blobs `shouldBe` [a]

    it "throws on blank input" $ do
      h <- openFile "test/fixtures/cli/blank.json" ReadMode
      readBlobsFromHandle h `shouldThrow` (== ExitFailure 1)

  where blobsFromFilePath path = do
          h <- openFile path ReadMode
          blobs <- readBlobPairsFromHandle h
          pure blobs
