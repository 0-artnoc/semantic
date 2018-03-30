{-# LANGUAGE ConstrainedClassMethods, DataKinds, FunctionalDependencies, TypeFamilies, UndecidableInstances #-}
module Control.Abstract.Evaluator
  ( MonadEvaluator(..)
  , MonadEnvironment(..)
  , modifyEnv
  , modifyExports
  , addExport
  , fullEnvironment
  , MonadHeap(..)
  , modifyHeap
  , localize
  , lookupHeap
  , assign
  , MonadModuleTable(..)
  , modifyModuleTable
  , MonadControl(..)
  , MonadThrow(..)
  -- Type synonyms specialized for location types
  , CellFor
  , ConfigurationFor
  , EnvironmentFor
  , ExportsFor
  , HeapFor
  , LiveFor
  , AbstractValue(..)
  ) where

import Control.Effect
import Control.Monad.Effect.Resumable
import Data.Abstract.Address
import Data.Abstract.Configuration
import qualified Data.Abstract.Environment as Env
import qualified Data.Abstract.Exports as Export
import Data.Abstract.FreeVariables
import Data.Abstract.Heap
import Data.Abstract.Live
import Data.Abstract.Module
import Data.Abstract.ModuleTable
import Data.Semigroup.Reducer
import Prologue hiding (throwError)

-- | A 'Monad' providing the basic essentials for evaluation.
--
--   These presently include:
--   - environments binding names to addresses
--   - a heap mapping addresses to (possibly sets of) values
--   - tables of modules available for import
class ( MonadControl term m
      , MonadEnvironment value m
      , MonadFail m
      , MonadModuleTable term value m
      , MonadHeap (LocationFor value) value m
      )
      => MonadEvaluator term value m | m -> term, m -> value where
  -- | Get the current 'Configuration' with a passed-in term.
  getConfiguration :: Ord (LocationFor value) => term -> m (ConfigurationFor term value)

  -- | Retrieve the stack of modules currently being evaluated.
  --
  --   With great power comes great responsibility. If you 'evaluateModule' any of these, you probably deserve what you get.
  askModuleStack :: m [Module term]


-- | A 'Monad' abstracting local and global environments.
class Monad m => MonadEnvironment value m | m -> value where
  -- | Retrieve the environment.
  getEnv :: m (EnvironmentFor value)
  -- | Set the environment.
  putEnv :: EnvironmentFor value -> m ()
  -- | Sets the environment for the lifetime of the given action.
  withEnv :: EnvironmentFor value -> m a -> m a

  -- | Retrieve the default environment.
  defaultEnvironment :: m (EnvironmentFor value)

  -- | Set the default environment for the lifetime of an action.
  --   Usually only invoked in a top-level evaluation function.
  withDefaultEnvironment :: EnvironmentFor value -> m a -> m a

  -- | Get the global export state.
  getExports :: m (ExportsFor value)
  -- | Set the global export state.
  putExports :: ExportsFor value -> m ()
  -- | Sets the global export state for the lifetime of the given action.
  withExports :: ExportsFor value -> m a -> m a

  -- | Run an action with a locally-modified environment.
  localEnv :: (EnvironmentFor value -> EnvironmentFor value) -> m a -> m a

  -- | Look a 'Name' up in the current environment, trying the default environment if no value is found.
  lookupEnv :: Name -> m (Maybe (Address (LocationFor value) value))
  lookupEnv name = (<|>) <$> (Env.lookup name <$> getEnv) <*> (Env.lookup name <$> defaultEnvironment)

  -- | Look up a 'Name' in the environment, running an action with the resolved address (if any).
  lookupWith :: (Address (LocationFor value) value -> m value) -> Name -> m (Maybe value)
  lookupWith with name = do
    addr <- lookupEnv name
    maybe (pure Nothing) (fmap Just . with) addr

-- | Run a computation in a new local environment.
localize :: MonadEnvironment value m => m a -> m a
localize = localEnv id

-- | Update the global environment.
modifyEnv :: MonadEnvironment value m => (EnvironmentFor value -> EnvironmentFor value) -> m ()
modifyEnv f = do
  env <- getEnv
  putEnv $! f env

-- | Update the global export state.
modifyExports :: MonadEnvironment value m => (ExportsFor value -> ExportsFor value) -> m ()
modifyExports f = do
  exports <- getExports
  putExports $! f exports

-- | Add an export to the global export state.
addExport :: MonadEnvironment value m => Name -> Name -> Maybe (Address (LocationFor value) value) -> m ()
addExport name alias = modifyExports . Export.insert name alias

-- | Obtain an environment that is the composition of the current and default environments.
--   Useful for debugging.
fullEnvironment :: MonadEnvironment value m => m (EnvironmentFor value)
fullEnvironment = mappend <$> getEnv <*> defaultEnvironment

-- | A 'Monad' abstracting a heap of values.
class Monad m => MonadHeap location value m | m -> value, m -> location where
  -- | Retrieve the heap.
  getHeap :: m (Heap location value)
  -- | Set the heap.
  putHeap :: Heap location value -> m ()

-- | Update the heap.
modifyHeap :: MonadHeap location value m => (Heap location value -> Heap location value) -> m ()
modifyHeap f = do
  s <- getHeap
  putHeap $! f s

-- | Look up the cell for the given 'Address' in the 'Heap'.
lookupHeap :: (MonadHeap location value m, Ord location) => Address location value -> m (Maybe (Cell location value))
lookupHeap = flip fmap getHeap . heapLookup

-- | Write a value to the given 'Address' in the 'Store'.
assign :: ( Ord location
          , MonadHeap location value m
          , Reducer value (Cell location value)
          )
       => Address location value
       -> value
       -> m ()
assign address = modifyHeap . heapInsert address


-- | A 'Monad' abstracting tables of modules available for import.
class Monad m => MonadModuleTable term value m | m -> term, m -> value where
  -- | Retrieve the table of evaluated modules.
  getModuleTable :: m (ModuleTable (EnvironmentFor value, value))
  -- | Set the table of evaluated modules.
  putModuleTable :: ModuleTable (EnvironmentFor value, value) -> m ()

  -- | Retrieve the table of unevaluated modules.
  askModuleTable :: m (ModuleTable [Module term])
  -- | Run an action with a locally-modified table of unevaluated modules.
  localModuleTable :: (ModuleTable [Module term] -> ModuleTable [Module term]) -> m a -> m a

-- | Update the evaluated module table.
modifyModuleTable :: MonadModuleTable term value m => (ModuleTable (EnvironmentFor value, value) -> ModuleTable (EnvironmentFor value, value)) -> m ()
modifyModuleTable f = do
  table <- getModuleTable
  putModuleTable $! f table


-- | A 'Monad' abstracting jumps in imperative control.
class Monad m => MonadControl term m where
  -- | Allocate a 'Label' for the given @term@.
  --
  --   Labels must be allocated before being jumped to with 'goto', but are suitable for nonlocal jumps; thus, they can be used to implement coroutines, exception handling, call with current continuation, and other esoteric control mechanisms.
  label :: term -> m Label
  -- | “Jump” to a previously-allocated 'Label' (retrieving the @term@ at which it points, which can then be evaluated in e.g. a 'MonadAnalysis' instance).
  goto :: Label -> m term


-- | 'Monad's which can throw exceptions of type @exc v@ which can be resumed with a value of type @v@.
class Monad m => MonadThrow exc m where
  throwException :: exc v -> m v

instance (Effectful m, Members '[Resumable exc] effects, Monad (m effects)) => MonadThrow exc (m effects) where
  throwException = raise . throwError


-- | The cell for an abstract value type.
type CellFor value = Cell (LocationFor value) value

-- | The configuration for term and abstract value types.
type ConfigurationFor term value = Configuration (LocationFor value) term value

-- | The environment for an abstract value type.
type EnvironmentFor value = Env.Environment (LocationFor value) value

-- | The exports for an abstract value type.
type ExportsFor value = Export.Exports (LocationFor value) value

-- | The 'Heap' for an abstract value type.
type HeapFor value = Heap (LocationFor value) value

-- | The address set type for an abstract value type.
type LiveFor value = Live (LocationFor value) value

class AbstractValue value where
  -- | The location type (the body of 'Address'es) which should be used for an abstract value type.
  type LocationFor value :: *
