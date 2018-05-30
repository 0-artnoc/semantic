module Control.Abstract.Exports
( Exports
, getExports
, putExports
, modifyExports
, addExport
, withExports
) where

import Control.Abstract.Evaluator
import Data.Abstract.Exports
import Data.Abstract.Name

-- | Get the global export state.
getExports :: Member (State (Exports location)) effects => Evaluator location value effects (Exports location)
getExports = get

-- | Set the global export state.
putExports :: Member (State (Exports location)) effects => Exports location -> Evaluator location value effects ()
putExports = put

-- | Update the global export state.
modifyExports :: Member (State (Exports location)) effects => (Exports location -> Exports location) -> Evaluator location value effects ()
modifyExports = modify'

-- | Add an export to the global export state.
addExport :: Member (State (Exports location)) effects => Name -> Name -> Maybe location -> Evaluator location value effects ()
addExport name alias = modifyExports . insert name alias

-- | Sets the global export state for the lifetime of the given action.
withExports :: Member (State (Exports location)) effects => Exports location -> Evaluator location value effects a -> Evaluator location value effects a
withExports = localState . const
