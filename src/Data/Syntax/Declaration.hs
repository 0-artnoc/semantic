{-# LANGUAGE DeriveAnyClass, MultiParamTypeClasses, ScopedTypeVariables, UndecidableInstances #-}
module Data.Syntax.Declaration where

import qualified Data.Abstract.Environment as Env
import Data.Abstract.Evaluatable
import Diffing.Algorithm
import Prologue

data Function a = Function { functionContext :: ![a], functionName :: !a, functionParameters :: ![a], functionBody :: !a }
  deriving (Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Diffable Function where
  equivalentBySubterm = Just . functionName

instance Eq1 Function where liftEq = genericLiftEq
instance Ord1 Function where liftCompare = genericLiftCompare
instance Show1 Function where liftShowsPrec = genericLiftShowsPrec

-- TODO: Filter the closed-over environment by the free variables in the term.
-- TODO: How should we represent function types, where applicable?

instance Evaluatable Function where
  eval Function{..} = do
    name <- either (throwEvalError . FreeVariablesError) pure (freeVariable $ subterm functionName)
    (v, addr) <- letrec name (lambda (paramNames functionParameters) functionBody)
    modifyEnv (Env.insert name addr)
    pure v
    where paramNames = foldMap (freeVariables . subterm)


data Method a = Method { methodContext :: ![a], methodReceiver :: !a, methodName :: !a, methodParameters :: ![a], methodBody :: !a }
  deriving (Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Diffable Method where
  equivalentBySubterm = Just . methodName

instance Eq1 Method where liftEq = genericLiftEq
instance Ord1 Method where liftCompare = genericLiftCompare
instance Show1 Method where liftShowsPrec = genericLiftShowsPrec

-- Evaluating a Method creates a closure and makes that value available in the
-- local environment.
instance Evaluatable Method where
  eval Method{..} = do
    name <- either (throwEvalError . FreeVariablesError) pure (freeVariable $ subterm methodName)
    (v, addr) <- letrec name (lambda (paramNames methodParameters) methodBody)
    modifyEnv (Env.insert name addr)
    pure v
    where paramNames = foldMap (freeVariables . subterm)


-- | A method signature in TypeScript or a method spec in Go.
data MethodSignature a = MethodSignature { _methodSignatureContext :: ![a], _methodSignatureName :: !a, _methodSignatureParameters :: ![a] }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Eq1 MethodSignature where liftEq = genericLiftEq
instance Ord1 MethodSignature where liftCompare = genericLiftCompare
instance Show1 MethodSignature where liftShowsPrec = genericLiftShowsPrec

-- TODO: Implement Eval instance for MethodSignature
instance Evaluatable MethodSignature


newtype RequiredParameter a = RequiredParameter { requiredParameter :: a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Eq1 RequiredParameter where liftEq = genericLiftEq
instance Ord1 RequiredParameter where liftCompare = genericLiftCompare
instance Show1 RequiredParameter where liftShowsPrec = genericLiftShowsPrec

-- TODO: Implement Eval instance for RequiredParameter
instance Evaluatable RequiredParameter


newtype OptionalParameter a = OptionalParameter { optionalParameter :: a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Eq1 OptionalParameter where liftEq = genericLiftEq
instance Ord1 OptionalParameter where liftCompare = genericLiftCompare
instance Show1 OptionalParameter where liftShowsPrec = genericLiftShowsPrec

-- TODO: Implement Eval instance for OptionalParameter
instance Evaluatable OptionalParameter


-- TODO: Should we replace this with Function and differentiate by context?
-- TODO: How should we distinguish class/instance methods?
-- TODO: It would be really nice to have a more meaningful type contained in here than [a]
-- | A declaration of possibly many variables such as var foo = 5, bar = 6 in JavaScript.
newtype VariableDeclaration a = VariableDeclaration { variableDeclarations :: [a] }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Eq1 VariableDeclaration where liftEq = genericLiftEq
instance Ord1 VariableDeclaration where liftCompare = genericLiftCompare
instance Show1 VariableDeclaration where liftShowsPrec = genericLiftShowsPrec

instance Evaluatable VariableDeclaration where
  eval (VariableDeclaration [])   = unit
  eval (VariableDeclaration decs) = multiple =<< traverse subtermValue decs

-- | A TypeScript/Java style interface declaration to implement.
data InterfaceDeclaration a = InterfaceDeclaration { interfaceDeclarationContext :: ![a], interfaceDeclarationIdentifier :: !a, interfaceDeclarationBody :: !a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Eq1 InterfaceDeclaration where liftEq = genericLiftEq
instance Ord1 InterfaceDeclaration where liftCompare = genericLiftCompare
instance Show1 InterfaceDeclaration where liftShowsPrec = genericLiftShowsPrec

-- TODO: Implement Eval instance for InterfaceDeclaration
instance Evaluatable InterfaceDeclaration


-- | A public field definition such as a field definition in a JavaScript class.
data PublicFieldDefinition a = PublicFieldDefinition { publicFieldContext :: ![a], publicFieldPropertyName :: !a, publicFieldValue :: !a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Eq1 PublicFieldDefinition where liftEq = genericLiftEq
instance Ord1 PublicFieldDefinition where liftCompare = genericLiftCompare
instance Show1 PublicFieldDefinition where liftShowsPrec = genericLiftShowsPrec

-- TODO: Implement Eval instance for PublicFieldDefinition
instance Evaluatable PublicFieldDefinition


data Variable a = Variable { variableName :: !a, variableType :: !a, variableValue :: !a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Eq1 Variable where liftEq = genericLiftEq
instance Ord1 Variable where liftCompare = genericLiftCompare
instance Show1 Variable where liftShowsPrec = genericLiftShowsPrec

-- TODO: Implement Eval instance for Variable
instance Evaluatable Variable

data Class a = Class { classContext :: ![a], classIdentifier :: !a, classSuperclasses :: ![a], classBody :: !a }
  deriving (Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Diffable Class where
  equivalentBySubterm = Just . classIdentifier

instance Eq1 Class where liftEq = genericLiftEq
instance Ord1 Class where liftCompare = genericLiftCompare
instance Show1 Class where liftShowsPrec = genericLiftShowsPrec

instance Evaluatable Class where
  eval Class{..} = do
    name <- either (throwEvalError . FreeVariablesError) pure (freeVariable $ subterm classIdentifier)
    supers <- traverse subtermValue classSuperclasses
    (v, addr) <- letrec name $ do
      void $ subtermValue classBody
      classEnv <- Env.head <$> getEnv
      klass name supers classEnv
    v <$ modifyEnv (Env.insert name addr)

-- | A decorator in Python
data Decorator a = Decorator { decoratorIdentifier :: !a, decoratorParamaters :: ![a], decoratorBody :: !a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Eq1 Decorator where liftEq = genericLiftEq
instance Ord1 Decorator where liftCompare = genericLiftCompare
instance Show1 Decorator where liftShowsPrec = genericLiftShowsPrec

-- TODO: Implement Eval instance for Decorator
instance Evaluatable Decorator

-- TODO: Generics, constraints.


-- | An ADT, i.e. a disjoint sum of products, like 'data' in Haskell, or 'enum' in Rust or Swift.
data Datatype a = Datatype { datatypeName :: !a, datatypeConstructors :: ![a] }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Eq1 Data.Syntax.Declaration.Datatype where liftEq = genericLiftEq
instance Ord1 Data.Syntax.Declaration.Datatype where liftCompare = genericLiftCompare
instance Show1 Data.Syntax.Declaration.Datatype where liftShowsPrec = genericLiftShowsPrec

-- TODO: Implement Eval instance for Datatype
instance Evaluatable Data.Syntax.Declaration.Datatype


-- | A single constructor in a datatype, or equally a 'struct' in C, Rust, or Swift.
data Constructor a = Constructor { constructorName :: !a, constructorFields :: ![a] }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Eq1 Data.Syntax.Declaration.Constructor where liftEq = genericLiftEq
instance Ord1 Data.Syntax.Declaration.Constructor where liftCompare = genericLiftCompare
instance Show1 Data.Syntax.Declaration.Constructor where liftShowsPrec = genericLiftShowsPrec

-- TODO: Implement Eval instance for Constructor
instance Evaluatable Data.Syntax.Declaration.Constructor


-- | Comprehension (e.g. ((a for b in c if a()) in Python)
data Comprehension a = Comprehension { comprehensionValue :: !a, comprehensionBody :: !a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Eq1 Comprehension where liftEq = genericLiftEq
instance Ord1 Comprehension where liftCompare = genericLiftCompare
instance Show1 Comprehension where liftShowsPrec = genericLiftShowsPrec

-- TODO: Implement Eval instance for Comprehension
instance Evaluatable Comprehension


-- | A declared type (e.g. `a []int` in Go).
data Type a = Type { typeName :: !a, typeKind :: !a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Eq1 Type where liftEq = genericLiftEq
instance Ord1 Type where liftCompare = genericLiftCompare
instance Show1 Type where liftShowsPrec = genericLiftShowsPrec

-- TODO: Implement Eval instance for Type
instance Evaluatable Type


-- | Type alias declarations in Javascript/Haskell, etc.
data TypeAlias a = TypeAlias { typeAliasContext :: ![a], typeAliasIdentifier :: !a, typeAliasKind :: !a }
  deriving (Diffable, Eq, Foldable, Functor, GAlign, Generic1, Mergeable, Ord, Show, Traversable, FreeVariables1)

instance Eq1 TypeAlias where liftEq = genericLiftEq
instance Ord1 TypeAlias where liftCompare = genericLiftCompare
instance Show1 TypeAlias where liftShowsPrec = genericLiftShowsPrec

-- TODO: Implement Eval instance for TypeAlias
instance Evaluatable TypeAlias
