{-# LANGUAGE DataKinds, GADTs, RankNTypes, ScopedTypeVariables, TypeOperators #-}
module Parser
( Parser(..)
-- Syntax parsers
, parserForLanguage
, lineByLineParser
-- À la carte parsers
, goParser
, jsonParser
, markdownParser
, pythonParser
, rubyParser
) where

import qualified CMarkGFM
import Data.Functor.Classes (Eq1)
import Data.Ix
import Data.Record
import Data.Source as Source
import qualified Data.Syntax as Syntax
import Data.Syntax.Assignment
import Data.Union
import Foreign.Ptr
import Info hiding (Empty, Go)
import Language
import qualified Language.Go.Syntax as Go
import qualified Language.JSON.Syntax as JSON
import qualified Language.Markdown.Syntax as Markdown
import qualified Language.Python.Syntax as Python
import qualified Language.Ruby.Syntax as Ruby
import Syntax hiding (Go)
import Term
import qualified TreeSitter.Language as TS (Language, Symbol)
import TreeSitter.Go
import TreeSitter.Python
import TreeSitter.Ruby
import TreeSitter.TypeScript
import TreeSitter.JSON

-- | A parser from 'Source' onto some term type.
data Parser term where
  -- | A parser producing 'AST' using a 'TS.Language'.
  ASTParser :: (Bounded grammar, Enum grammar) => Ptr TS.Language -> Parser (AST [] grammar)
  -- | A parser producing an à la carte term given an 'AST'-producing parser and an 'Assignment' onto 'Term's in some syntax type.
  AssignmentParser :: (Enum grammar, Ix grammar, Show grammar, TS.Symbol grammar, Syntax.Error :< fs, Eq1 ast, Apply1 Foldable fs, Apply1 Functor fs, Foldable ast, Functor ast)
                   => Parser (Term ast (Node grammar))                           -- ^ A parser producing AST.
                   -> Assignment ast grammar (Term (Union fs) (Record Location)) -- ^ An assignment from AST onto 'Term's.
                   -> Parser (Term (Union fs) (Record Location))                 -- ^ A parser producing 'Term's.
  -- | A tree-sitter parser.
  TreeSitterParser :: Ptr TS.Language -> Parser (SyntaxTerm DefaultFields)
  -- | A parser for 'Markdown' using cmark.
  MarkdownParser :: Parser (Term (TermF [] CMarkGFM.NodeType) (Node Markdown.Grammar))
  -- | A parser which will parse any input 'Source' into a top-level 'Term' whose children are leaves consisting of the 'Source's lines.
  LineByLineParser :: Parser (SyntaxTerm DefaultFields)

-- | Return a 'Language'-specific 'Parser', if one exists, falling back to the 'LineByLineParser'.
parserForLanguage :: Maybe Language -> Parser (SyntaxTerm DefaultFields)
parserForLanguage Nothing = LineByLineParser
parserForLanguage (Just language) = case language of
  Go -> TreeSitterParser tree_sitter_go
  JavaScript -> TreeSitterParser tree_sitter_typescript
  JSON -> TreeSitterParser tree_sitter_json
  JSX -> TreeSitterParser tree_sitter_typescript
  Ruby -> TreeSitterParser tree_sitter_ruby
  TypeScript -> TreeSitterParser tree_sitter_typescript
  _ -> LineByLineParser

goParser :: Parser Go.Term
goParser = AssignmentParser (ASTParser tree_sitter_go) Go.assignment

rubyParser :: Parser Ruby.Term
rubyParser = AssignmentParser (ASTParser tree_sitter_ruby) Ruby.assignment

pythonParser :: Parser Python.Term
pythonParser = AssignmentParser (ASTParser tree_sitter_python) Python.assignment

jsonParser :: Parser JSON.Term
jsonParser = AssignmentParser (ASTParser tree_sitter_json) JSON.assignment

markdownParser :: Parser Markdown.Term
markdownParser = AssignmentParser MarkdownParser Markdown.assignment


-- | A fallback parser that treats a file simply as rows of strings.
lineByLineParser :: Source -> SyntaxTerm DefaultFields
lineByLineParser source = termIn (totalRange source :. Program :. totalSpan source :. Nil) (Indexed (zipWith toLine [1..] (sourceLineRanges source)))
  where toLine line range = termIn (range :. Program :. Span (Pos line 1) (Pos line (end range)) :. Nil) (Leaf (toText (slice range source)))
