{-# LANGUAGE DataKinds, GADTs #-}
module Language.Ruby where

import Data.Record
import Data.List (partition)
import Info
import Prologue
import Source
import Language
import qualified Syntax as S
import Term

termAssignment
  :: Source Char -- ^ The source of the term.
  -> Record '[Range, Category, SourceSpan] -- ^ The proposed annotation for the term.
  -> [ SyntaxTerm Text '[Range, Category, SourceSpan] ] -- ^ The child nodes of the term.
  -> Maybe (S.Syntax Text (SyntaxTerm Text '[Range, Category, SourceSpan])) -- ^ The resulting term, in IO.
termAssignment source (_ :. category :. _ :. Nil) children
  = case (category, children) of
    (ArgumentPair, [ k, v ] ) -> Just $ S.Pair k v
    (KeywordParameter, [ k, v ] ) -> Just $ S.Pair k v
    -- NB: ("keyword_parameter", k) is a required keyword parameter, e.g.:
    --    def foo(name:); end
    -- Let it fall through to generate an Indexed syntax.
    (OptionalParameter, [ k, v ] ) -> Just $ S.Pair k v
    (ArrayLiteral, _ ) -> Just $ S.Array Nothing children
    (Assignment, [ identifier, value ]) -> Just $ S.Assignment identifier value
    (Begin, _ ) -> Just $ case partition (\x -> Info.category (extract x) == Rescue) children of
      (rescues, rest) -> case partition (\x -> Info.category (extract x) == Ensure || Info.category (extract x) == Else) rest of
        (ensureElse, body) -> case ensureElse of
          [ elseBlock, ensure ]
            | Else <- Info.category (extract elseBlock)
            , Ensure <- Info.category (extract ensure) -> S.Try body rescues (Just elseBlock) (Just ensure)
          [ ensure, elseBlock ]
            | Ensure <- Info.category (extract ensure)
            , Else <- Info.category (extract elseBlock) -> S.Try body rescues (Just elseBlock) (Just ensure)
          [ elseBlock ] | Else <- Info.category (extract elseBlock) -> S.Try body rescues (Just elseBlock) Nothing
          [ ensure ] | Ensure <- Info.category (extract ensure) -> S.Try body rescues Nothing (Just ensure)
          _ -> S.Try body rescues Nothing Nothing
    (Case, expr : body ) -> Just $ S.Switch (Just expr) body
    (When, condition : body ) -> Just $ S.Case condition body
    (Class, constant : rest ) -> Just $ case rest of
      ( superclass : body ) | Superclass <- Info.category (extract superclass) -> S.Class constant (Just superclass) body
      _ -> S.Class constant Nothing rest
    (SingletonClass, identifier : rest ) -> Just $ S.Class identifier Nothing rest
    (Comment, _ ) -> Just . S.Comment $ toText source
    (Ternary, condition : cases) -> Just $ S.Ternary condition cases
    (Constant, _ ) -> Just $ S.Fixed children
    (MethodCall, fn : args) | MemberAccess <- Info.category (extract fn)
                            , [target, method] <- toList (unwrap fn)
                            -> Just $ S.MethodCall target method (toList . unwrap =<< args)
                            | otherwise
                            -> Just $ S.FunctionCall fn (toList . unwrap =<< args)
    (Other "lambda", first : rest) | null rest -> Just $ S.AnonymousFunction [] [first]
                                   | otherwise -> Just $ S.AnonymousFunction (toList (unwrap first)) rest
    (Object, _ ) -> Just . S.Object Nothing $ foldMap toTuple children
    (Modifier If, [ lhs, condition ]) -> Just $ S.If condition [lhs]
    (Modifier Unless, [lhs, rhs]) -> Just $ S.If (withRecord (setCategory (extract rhs) Negate) (S.Negate rhs)) [lhs]
    (Unless, expr : rest) -> Just $ S.If (withRecord (setCategory (extract expr) Negate) (S.Negate expr)) rest
    (Modifier Until, [ lhs, rhs ]) -> Just $ S.While (withRecord (setCategory (extract rhs) Negate) (S.Negate rhs)) [lhs]
    (Until, expr : rest) -> Just $ S.While (withRecord (setCategory (extract expr) Negate) (S.Negate expr)) rest
    (Elsif, condition : body ) -> Just $ S.If condition body
    (SubscriptAccess, [ base, element ]) -> Just $ S.SubscriptAccess base element
    (For, lhs : expr : rest ) -> Just $ S.For [lhs, expr] rest
    (OperatorAssignment, [ identifier, value ]) -> Just $ S.OperatorAssignment identifier value
    (MemberAccess, [ base, property ]) -> Just $ S.MemberAccess base property
    (Method, identifier : first : rest) | Params <- Info.category (extract first)
                                        -> Just $ S.Method identifier Nothing (toList (unwrap first)) rest
                                        | null rest
                                        -> Just $ S.Method identifier Nothing [] [first]
    (Module, constant : body ) -> Just $ S.Module constant body
    (Modifier Rescue, [lhs, rhs] ) -> Just $ S.Rescue [lhs] [rhs]
    (Rescue, _ ) -> Just $ case children of
      exceptions : exceptionVar : rest
        | RescueArgs <- Info.category (extract exceptions)
        , RescuedException <- Info.category (extract exceptionVar) -> S.Rescue (toList (unwrap exceptions) <> [exceptionVar]) rest
      exceptionVar : rest | RescuedException <- Info.category (extract exceptionVar) -> S.Rescue [exceptionVar] rest
      exceptions : body | RescueArgs <- Info.category (extract exceptions) -> S.Rescue (toList (unwrap exceptions)) body
      body -> S.Rescue [] body
    (Return, _ ) -> Just $ S.Return children
    (Modifier While, [ lhs, condition ]) -> Just $ S.While condition [lhs]
    (While, expr : rest ) -> Just $ S.While expr rest
    (Yield, _ ) -> Just $ S.Yield children
    _ | category `elem` [ BeginBlock, EndBlock ] -> Just $ S.BlockStatement children
    _  -> Nothing
  where
    withRecord record syntax = cofree (record :< syntax)

categoryForRubyName :: Text -> Category
categoryForRubyName = \case
  "argument_list" -> Args
  "argument_pair" -> ArgumentPair
  "array" -> ArrayLiteral
  "assignment" -> Assignment
  "begin_block" -> BeginBlock
  "begin" -> Begin
  "binary" -> Binary
  "block_parameter" -> BlockParameter
  "boolean" -> Boolean
  "call" -> MemberAccess
  "case" -> Case
  "class"  -> Class
  "comment" -> Comment
  "conditional" -> Ternary
  "constant" -> Constant
  "element_reference" -> SubscriptAccess
  "else" -> Else
  "elsif" -> Elsif
  "end_block" -> EndBlock
  "ensure" -> Ensure
  "exception_variable" -> RescuedException
  "exceptions" -> RescueArgs
  "false" -> Boolean
  "float" -> NumberLiteral
  "for" -> For
  "formal_parameters" -> Params
  "hash_splat_parameter" -> HashSplatParameter
  "hash" -> Object
  "identifier" -> Identifier
  "if_modifier" -> Modifier If
  "if" -> If
  "instance_variable" -> Identifier
  "integer" -> IntegerLiteral
  "interpolation" -> Interpolation
  "keyword_parameter" -> KeywordParameter
  "method_call" -> MethodCall
  "method" -> Method
  "module"  -> Module
  "nil" -> Identifier
  "operator_assignment" -> OperatorAssignment
  "optional_parameter" -> OptionalParameter
  "pair" -> Pair
  "program" -> Program
  "range" -> RangeExpression
  "regex" -> Regex
  "rescue_modifier" -> Modifier Rescue
  "rescue" -> Rescue
  "return" -> Return
  "scope_resolution" -> ScopeOperator
  "self" -> Identifier
  "singleton_class"  -> SingletonClass
  "splat_parameter" -> SplatParameter
  "string" -> StringLiteral
  "subshell" -> Subshell
  "superclass" -> Superclass
  "symbol" -> SymbolLiteral
  "true" -> Boolean
  "unary" -> Unary
  "unless_modifier" -> Modifier Unless
  "unless" -> Unless
  "until_modifier" -> Modifier Until
  "until" -> Until
  "when" -> When
  "while_modifier" -> Modifier While
  "while" -> While
  "yield" -> Yield
  s -> Other s
