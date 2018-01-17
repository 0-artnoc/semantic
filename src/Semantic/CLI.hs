{-# LANGUAGE TemplateHaskell #-}
module Semantic.CLI
( main
-- Testing
, runDiff
, runParse
) where

import Control.Monad ((<=<))
import Data.ByteString (ByteString)
import Data.Foldable (find)
import Data.Functor.Both hiding (fst, snd)
import Data.Language
import Data.List (intercalate)
import Data.List.Split (splitWhen)
import Data.Semigroup ((<>))
import Data.Version (showVersion)
import Development.GitRev
import Options.Applicative hiding (action)
import Rendering.Renderer
import qualified Paths_semantic_diff as Library (version)
import Semantic.IO (languageForFilePath)
import qualified Semantic.Log as Log
import qualified Semantic.Task as Task
import System.IO (Handle, stdin, stdout)
import qualified Semantic (parseBlobs, diffBlobPairs)
import Text.Read


main :: IO ()
main = customExecParser (prefs showHelpOnEmpty) arguments >>= uncurry Task.runTaskWithOptions

runDiff :: SomeRenderer DiffRenderer -> Either Handle [Both (FilePath, Maybe Language)] -> Task.Task ByteString
runDiff (SomeRenderer diffRenderer) = Semantic.diffBlobPairs diffRenderer <=< Task.readBlobPairs

runParse :: SomeRenderer TermRenderer -> Either Handle [(FilePath, Maybe Language)] -> Task.Task ByteString
runParse (SomeRenderer parseTreeRenderer) = Semantic.parseBlobs parseTreeRenderer <=< Task.readBlobs

-- | A parser for the application's command-line arguments.
--
--   Returns a 'Task' to read the input, run the requested operation, and write the output to the specified output path or stdout.
arguments :: ParserInfo (Log.Options, Task.Task ())
arguments = info (version <*> helper <*> ((,) <$> optionsParser <*> argumentsParser)) description
  where
    version = infoOption versionString (long "version" <> short 'v' <> help "Output the version of the program")
    versionString = "semantic version " <> showVersion Library.version <> " (" <> $(gitHash) <> ")"
    description = fullDesc <> header "semantic -- Parse and diff semantically"

    optionsParser = Log.Options
      <$> (not <$> switch (long "disable-colour" <> long "disable-color" <> help "Disable ANSI colors in log messages even if the terminal is a TTY."))
      <*> options [("error", Just Log.Error), ("warning", Just Log.Warning), ("info", Just Log.Info), ("debug", Just Log.Debug), ("none", Nothing)]
            (long "log-level" <> value (Just Log.Warning) <> help "Log messages at or above this level, or disable logging entirely.")
      <*> optional (strOption (long "request-id" <> help "A string to use as the request identifier for any logged messages." <> metavar "id"))
      -- The rest of the logging options are set automatically at runtime.
      <*> pure False -- IsTerminal
      <*> pure False -- PrintSource
      <*> pure Log.logfmtFormatter -- Formatter
      <*> pure 0 -- ProcessID
    argumentsParser = (. Task.writeToOutput) . (>>=)
      <$> hsubparser (diffCommand <> parseCommand)
      <*> (   Right <$> strOption (long "output" <> short 'o' <> help "Output path, defaults to stdout")
          <|> pure (Left stdout) )

    diffCommand = command "diff" (info diffArgumentsParser (progDesc "Show changes between commits or paths"))
    diffArgumentsParser = runDiff
      <$> (   flag  (SomeRenderer SExpressionDiffRenderer) (SomeRenderer SExpressionDiffRenderer) (long "sexpression" <> help "Output s-expression diff tree")
          <|> flag'                                        (SomeRenderer JSONDiffRenderer)        (long "json" <> help "Output JSON diff trees")
          <|> flag'                                        (SomeRenderer ToCDiffRenderer)         (long "toc" <> help "Output JSON table of contents diff summary")
          <|> flag'                                        (SomeRenderer DOTDiffRenderer)         (long "dot" <> help "Output the diff as a DOT graph"))
      <*> (   Right <$> some (both
          <$> argument filePathReader (metavar "FILE_A")
          <*> argument filePathReader (metavar "FILE_B"))
          <|> pure (Left stdin) )

    parseCommand = command "parse" (info parseArgumentsParser (progDesc "Print parse trees for path(s)"))
    parseArgumentsParser = runParse
      <$> (   flag  (SomeRenderer SExpressionTermRenderer) (SomeRenderer SExpressionTermRenderer) (long "sexpression" <> help "Output s-expression parse trees (default)")
          <|> flag'                                        (SomeRenderer JSONTermRenderer)        (long "json" <> help "Output JSON parse trees")
          <|> flag'                                        (SomeRenderer ToCTermRenderer)         (long "toc" <> help "Output JSON table of contents summary")
          <|> flag'                                        (SomeRenderer . TagsTermRenderer)      (long "tags" <> help "Output JSON tags/symbols")
              <*> (   option tagFieldsReader (  long "fields"
                                             <> help "Comma delimited list of specific fields to return (tags output only)."
                                             <> metavar "FIELDS")
                  <|> pure defaultTagFields)
          <|> flag'                                        (SomeRenderer DOTTermRenderer)         (long "dot" <> help "Output the term as a DOT graph"))
      <*> (   Right <$> some (argument filePathReader (metavar "FILES..."))
          <|> pure (Left stdin) )

    filePathReader = eitherReader parseFilePath
    parseFilePath arg = case splitWhen (== ':') arg of
        [a, b] | Just lang <- readMaybe a -> Right (b, Just lang)
               | Just lang <- readMaybe b -> Right (a, Just lang)
        [path] -> Right (path, languageForFilePath path)
        _ -> Left ("cannot parse `" <> arg <> "`\nexpecting LANGUAGE:FILE or just FILE")

    optionsReader options = eitherReader $ \ str -> maybe (Left ("expected one of: " <> intercalate ", " (fmap fst options))) (Right . snd) (find ((== str) . fst) options)
    options options fields = option (optionsReader options) (fields <> showDefaultWith (findOption options) <> metavar (intercalate "|" (fmap fst options)))
    findOption options value = maybe "" fst (find ((== value) . snd) options)

    -- Example: semantic parse --tags --fields=symbol,path,language,kind,line,span
    tagFieldsReader = eitherReader parseTagFields
    parseTagFields arg = let fields = splitWhen (== ',') arg in
                      Right $ TagFields
                        { tagFieldsShowSymbol = (elem "symbol" fields)
                        , tagFieldsShowPath = (elem "path" fields)
                        , tagFieldsShowLanguage = (elem "language" fields)
                        , tagFieldsShowKind = (elem "kind" fields)
                        , tagFieldsShowLine = (elem "line" fields)
                        , tagFieldsShowSpan = (elem "span" fields)
                        }
