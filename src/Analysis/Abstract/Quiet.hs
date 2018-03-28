{-# LANGUAGE GeneralizedNewtypeDeriving, ScopedTypeVariables, TypeApplications, TypeFamilies #-}
module Analysis.Abstract.Quiet where

import Control.Abstract.Analysis
import Data.Abstract.Evaluatable
import Prologue

-- | An analysis which resumes exceptions instead of failing.
--
--   Use it by composing it onto an analysis:
--
--   > runAnalysis @(Quietly Evaluating term value) (…)
--
--   Note that exceptions thrown by other analyses may not be caught if 'Quietly' doesn’t know about them, i.e. if they’re not part of the generic 'MonadValue', 'MonadAddressable', etc. machinery.
newtype Quietly m term value (effects :: [* -> *]) a = Quietly (m term value effects a)
  deriving (Alternative, Applicative, Functor, Effectful, Monad, MonadFail, MonadFresh, MonadNonDet)

deriving instance MonadControl term (m term value effects) => MonadControl term (Quietly m term value effects)
deriving instance MonadEnvironment value (m term value effects) => MonadEnvironment value (Quietly m term value effects)
deriving instance MonadHeap value (m term value effects) => MonadHeap value (Quietly m term value effects)
deriving instance MonadModuleTable term value (m term value effects) => MonadModuleTable term value (Quietly m term value effects)
deriving instance MonadEvaluator term value (m term value effects) => MonadEvaluator term value (Quietly m term value effects)

instance ( Effectful (m term value)
         , Member (Resumable (Unspecialized value)) effects
         , MonadAnalysis term value (m term value effects)
         , MonadValue value (Quietly m term value effects)
         )
      => MonadAnalysis term value (Quietly m term value effects) where
  type RequiredEffects term value (Quietly m term value effects) = RequiredEffects term value (m term value effects)

  analyzeTerm eval term = resumeException @(Unspecialized value) (liftAnalyze analyzeTerm eval term) (\yield (Unspecialized _) -> unit >>= yield)

  analyzeModule = liftAnalyze analyzeModule
