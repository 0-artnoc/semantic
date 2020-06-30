{-# LANGUAGE OverloadedStrings #-}
module Main
( main
) where

import Tags.Tagging.Precise
import Source.Source as Source
import Source.Loc
import Source.Span
import Test.Tasty as Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain $ testGroup "semantic-tags" [ testTree ]

-- Range start = 13 + *num bytes in char inside ''*
-- Span start col = 5 + *num bytes in char*

testTree :: Tasty.TestTree
testTree = Tasty.testGroup "Tags.Tagging.Precise"
  [ Tasty.testGroup "firstLineAndSpans"
    [ testCase "one line" $
        let src = Source.fromText "def foo;end"
            loc = Loc (Range 4 7) (Span (Pos 0 4) (Pos 0 7))
        in ( "def foo;end"
           , OneIndexedSpan $ Span (Pos 1 5) (Pos 1 8) -- one indexed, counting bytes
           , UTF16CodeUnitSpan $ Span (Pos 0 4) (Pos 0 7) -- zero-indexed, counting utf16 code units (lsp-style column offset)
           ) @=? calculateLineAndSpans src loc

    , testCase "ascii" $
        let src = Source.fromText "def foo\n  'a'.hi\nend\n"
            loc = Loc (Range 14 16) (Span (Pos 1 6) (Pos 1 8))
        in ( "'a'.hi"
           , OneIndexedSpan $ Span (Pos 2 7) (Pos 2 9) -- one indexed, counting bytes
           , UTF16CodeUnitSpan $ Span (Pos 1 6) (Pos 1 8) -- zero-indexed, counting utf16 code units (lsp-style column offset)
           ) @=? calculateLineAndSpans src loc

    , testCase "unicode" $
        let src = Source.fromText "def foo\n  'à'.hi\nend\n"
            loc = Loc (Range 15 17) (Span (Pos 1 7) (Pos 1 9))
        in ( "'à'.hi"
           , OneIndexedSpan $ Span (Pos 2 8) (Pos 2 10) -- one indexed, counting bytes
           , UTF16CodeUnitSpan $ Span (Pos 1 6) (Pos 1 8)  -- zero-indexed, counting utf16 code units (lsp-style column offset)
           ) @=? calculateLineAndSpans src loc

    , testCase "multi code point unicode" $
        let src = Source.fromText "def foo\n  '💀'.hi\nend\n"
            loc = Loc (Range 17 19) (Span (Pos 1 9) (Pos 1 11))
        in ( "'💀'.hi"
           , OneIndexedSpan $ Span (Pos 2 10) (Pos 2 12) -- one indexed, counting bytes
           , UTF16CodeUnitSpan $ Span (Pos 1 7) (Pos 1 9)   -- zero-indexed, counting utf16 code units (lsp-style column offset)
           ) @=? calculateLineAndSpans src loc

    -- NB: This emoji (:man-woman-girl-girl:) cannot be entered into a string literal in haskell for some reason, you'll get:
    --   > lexical error in string/character literal at character '\8205'
    -- The work around is to enter the unicode directly (7 code points).
    -- utf-8: 25 bytes to represent
    -- utf-16: 23 bytes to represent
    , testCase "multi code point unicode :man-woman-girl-girl:" $
        let src = Source.fromText "def foo\n  '\128104\8205\128105\8205\128103\8205\128103'.hi\nend\n"
            loc = Loc (Range 38 40) (Span (Pos 1 30) (Pos 1 32))
        in ( "'\128104\8205\128105\8205\128103\8205\128103'.hi"
           , OneIndexedSpan $ Span (Pos 2 31) (Pos 2 33)  -- one indexed, counting bytes
           , UTF16CodeUnitSpan $ Span (Pos 1 16) (Pos 1 18)  -- zero-indexed, counting utf16 code units (lsp-style column offset)
           ) @=? calculateLineAndSpans src loc
    ]
  ]
