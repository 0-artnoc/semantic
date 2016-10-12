{-# LANGUAGE StrictData #-}
module Arguments (Arguments(..), CmdLineOptions(..), DiffMode(..), ExtraArg(..), programArguments, args) where

import Data.Functor.Both
import Data.Maybe
import Data.Text
import Prologue hiding ((<>))
import Prelude
import System.Environment
import System.Directory
import System.IO.Error (IOError)

import qualified Renderer as R

data ExtraArg = ShaPair (Both (Maybe String))
              | FileArg FilePath
              deriving (Show)

data DiffMode = PathDiff (Both FilePath)
              | CommitDiff
              deriving (Show)

-- | The command line options to the application (arguments for optparse-applicative).
data CmdLineOptions = CmdLineOptions
  { outputFormat :: R.Format
  , maybeTimeout :: Maybe Float
  , outputFilePath :: Maybe FilePath
  , noIndex :: Bool
  , extraArgs :: [ExtraArg]
  , developmentMode' :: Bool
  }

-- | Arguments for the program (includes command line, environment, and defaults).
data Arguments = Arguments
  { gitDir :: FilePath
  , alternateObjectDirs :: [Text]
  , format :: R.Format
  , timeoutInMicroseconds :: Int
  , output :: Maybe FilePath
  , diffMode :: DiffMode
  , shaRange :: Both (Maybe String)
  , filePaths :: [FilePath]
  , developmentMode :: Bool
  } deriving (Show)

-- | Returns Arguments for the program from parsed command line arguments.
programArguments :: CmdLineOptions -> IO Arguments
programArguments CmdLineOptions{..} = do
  pwd <- getCurrentDirectory
  gitDir <- fromMaybe pwd <$> lookupEnv "GIT_DIR"
  eitherObjectDirs <- try $ parseObjectDirs . toS <$> getEnv "GIT_ALTERNATE_OBJECT_DIRECTORIES"
  let alternateObjectDirs = case (eitherObjectDirs :: Either IOError [Text]) of
                              (Left _) -> []
                              (Right objectDirs) -> objectDirs

  let filePaths = fetchPaths extraArgs
  pure Arguments
    { gitDir = gitDir
    , alternateObjectDirs = alternateObjectDirs
    , format = outputFormat
    , timeoutInMicroseconds = maybe defaultTimeout toMicroseconds maybeTimeout
    , output = outputFilePath
    , diffMode = case (noIndex, filePaths) of
      (True, [fileA, fileB]) -> PathDiff (both fileA fileB)
      (_, _) -> CommitDiff
    , shaRange = fetchShas extraArgs
    , filePaths = filePaths
    , developmentMode = developmentMode'
    }
  where
    fetchPaths :: [ExtraArg] -> [FilePath]
    fetchPaths [] = []
    fetchPaths (FileArg x:xs) = x : fetchPaths xs
    fetchPaths (_:xs) = fetchPaths xs

    fetchShas :: [ExtraArg] -> Both (Maybe String)
    fetchShas [] = both Nothing Nothing
    fetchShas (ShaPair x:_) = x
    fetchShas (_:xs) = fetchShas xs

-- | Quickly assemble an Arguments data record with defaults.
args :: FilePath -> String -> String -> [String] -> R.Format -> Arguments
args gitDir sha1 sha2 filePaths format = Arguments
  { gitDir =  gitDir
  , alternateObjectDirs = []
  , format = format
  , timeoutInMicroseconds = defaultTimeout
  , output = Nothing
  , diffMode = CommitDiff
  , shaRange = Just <$> both sha1 sha2
  , filePaths = filePaths
  , developmentMode = False
  }

-- | 7 seconds
defaultTimeout :: Int
defaultTimeout = 7 * 1000000

toMicroseconds :: Float -> Int
toMicroseconds num = floor $ num * 1000000

parseObjectDirs :: Text -> [Text]
parseObjectDirs = split (== ':')
