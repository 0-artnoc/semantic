{-# LANGUAGE RankNTypes, ScopedTypeVariables, TypeFamilies, TypeOperators, UndecidableInstances #-}
module Rendering.Imports
( renderToImports
, ImportSummary(..)
) where

import Prologue
import Analysis.Declaration
import Analysis.PackageDef
import Data.Aeson
import Data.Blob
import Data.Record
import Data.Output
import Data.Span
import Data.Term
import System.FilePath.Posix (takeBaseName)
import qualified Data.Text as T
import qualified Data.Map as Map
import Rendering.TOC (termTableOfContentsBy, declaration, getDeclaration, toCategoryName)


newtype ImportSummary = ImportSummary (Map.Map T.Text Module) deriving (Eq, Show)

instance Semigroup ImportSummary where
  (<>) (ImportSummary m1) (ImportSummary m2) = ImportSummary (Map.unionWith mappend m1 m2)

instance Monoid ImportSummary where
  mempty = ImportSummary mempty
  mappend = (<>)

instance Output ImportSummary where
  toOutput = fromEncoding . toEncoding

instance ToJSON ImportSummary where
  toJSON (ImportSummary m) = object [ "modules" .= m ]

renderToImports :: (HasField fields (Maybe PackageDef), HasField fields (Maybe Declaration), HasField fields Span, Foldable f, Functor f) => Blob -> Term f (Record fields) -> ImportSummary
renderToImports blob term = ImportSummary $ toMap (termToModule blob term)
  where
    toMap m@Module{..} = Map.singleton moduleName m
    termToModule :: (HasField fields (Maybe PackageDef), HasField fields (Maybe Declaration), HasField fields Span, Foldable f, Functor f) => Blob -> Term f (Record fields) -> Module
    termToModule blob@Blob{..} term = makeModule detectModuleName blob declarations
      where
        declarations = termTableOfContentsBy declaration term
        defaultModuleName = T.pack (takeBaseName blobPath)
        detectModuleName = case termTableOfContentsBy moduleDef term of
          x:_ | Just PackageDef{..} <- getPackageDef x -> moduleDefIdentifier
          _ -> defaultModuleName

makeModule :: (HasField fields Span, HasField fields (Maybe Declaration)) => T.Text -> Blob -> [Record fields] -> Module
makeModule name Blob{..} ds = Module name [T.pack blobPath] (T.pack . show <$> blobLanguage) (mapMaybe importSummary ds) (mapMaybe (declarationSummary name) ds) (mapMaybe referenceSummary ds)


getPackageDef :: HasField fields (Maybe PackageDef) => Record fields -> Maybe PackageDef
getPackageDef = getField

-- | Produce the annotations of nodes representing moduleDefs.
moduleDef :: HasField fields (Maybe PackageDef) => TermF f (Record fields) a -> Maybe (Record fields)
moduleDef (In annotation _) = annotation <$ getPackageDef annotation

declarationSummary :: (HasField fields (Maybe Declaration), HasField fields Span) => Text -> Record fields -> Maybe SymbolDeclaration
declarationSummary module' record = case getDeclaration record of
  Just declaration | FunctionDeclaration{} <- declaration -> Just (makeSymbolDeclaration declaration)
                   | MethodDeclaration{} <- declaration -> Just (makeSymbolDeclaration declaration)
  _ -> Nothing
  where makeSymbolDeclaration declaration = SymbolDeclaration
          { declarationName = declarationIdentifier declaration
          , declarationKind = toCategoryName declaration
          , declarationSpan = getField record
          , declarationModule = module'
          }

importSummary :: (HasField fields (Maybe Declaration), HasField fields Span) => Record fields -> Maybe ImportStatement
importSummary record = case getDeclaration record of
  Just ImportDeclaration{..} -> Just $ ImportStatement declarationIdentifier declarationAlias (uncurry ImportSymbol <$> declarationSymbols) (getField record)
  _ -> Nothing

referenceSummary :: (HasField fields (Maybe Declaration), HasField fields Span) => Record fields -> Maybe CallExpression
referenceSummary record = case getDeclaration record of
  Just CallReference{..} -> Just  $ CallExpression declarationIdentifier declarationImportIdentifier (getField record)
  _ -> Nothing

data Module = Module
  { moduleName :: T.Text
  , modulePaths :: [T.Text]
  , moduleLanguage :: Maybe T.Text
  , moduleImports :: [ImportStatement]
  , moduleDeclarations :: [SymbolDeclaration]
  , moduleCalls :: [CallExpression]
  } deriving (Generic, Eq, Show)

instance Semigroup Module where
  (<>) (Module n1 p1 l1 i1 d1 r1) (Module _ p2 _ i2 d2 r2) = Module n1 (p1 <> p2) l1 (i1 <> i2) (d1 <> d2) (r1 <> r2)

instance Monoid Module where
  mempty = mempty
  mappend = (<>)

instance ToJSON Module where
  toJSON Module{..} = object
    [ "name" .= moduleName
    , "paths" .= modulePaths
    , "language" .= moduleLanguage
    , "imports" .= moduleImports
    , "declarations" .= moduleDeclarations
    , "calls" .= moduleCalls
    ]

data SymbolDeclaration = SymbolDeclaration
  { declarationName :: T.Text
  , declarationKind :: T.Text
  , declarationSpan :: Span
  , declarationModule :: T.Text
  } deriving (Generic, Eq, Show)

instance ToJSON SymbolDeclaration where
  toJSON SymbolDeclaration{..} = object
    [ "name" .= declarationName
    , "kind" .= declarationKind
    , "span" .= declarationSpan
    , "module" .= declarationModule
    ]

data ImportStatement = ImportStatement
  { importPath :: T.Text
  , importAlias :: T.Text
  , importSymbols :: [ImportSymbol]
  , importSpan :: Span
  } deriving (Generic, Eq, Show)

instance ToJSON ImportStatement where
  toJSON ImportStatement{..} = object
    [ "path" .= importPath
    , "alias" .= importAlias
    , "symbols" .= importSymbols
    , "span" .= importSpan
    ]

data ImportSymbol = ImportSymbol
  { importSymbolName :: T.Text
  , importSymbolAlias :: T.Text
  } deriving (Generic, Eq, Show)

instance ToJSON ImportSymbol where
  toJSON ImportSymbol{..} = object
    [ "name" .= importSymbolName
    , "alias" .= importSymbolAlias
    ]

data CallExpression = CallExpression
  { callSymbol :: T.Text
  , callTargets :: [T.Text]
  , callSpan :: Span
  } deriving (Generic, Eq, Show)

instance ToJSON CallExpression where
  toJSON CallExpression{..} = objectWithoutNulls
    [ "symbol" .= callSymbol
    , "targets" .= callTargets
    , "span" .= callSpan
    ]

objectWithoutNulls :: [(T.Text, Value)] -> Value
objectWithoutNulls = object . filter (\(_, v) -> v /= Null)
