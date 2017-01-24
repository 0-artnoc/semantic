{-# LANGUAGE DataKinds, GADTs #-}
module Language.Go where

import Prologue
import Info
import Source
import Term
import qualified Syntax as S

termAssignment
  :: Source Char -- ^ The source of the term.
  -> Category -- ^ The category for the term.
  -> [ SyntaxTerm Text '[Range, Category, SourceSpan] ] -- ^ The child nodes of the term.
  -> Maybe (S.Syntax Text (SyntaxTerm Text '[Range, Category, SourceSpan])) -- ^ The resulting term, in IO.
termAssignment source category children = case (category, children) of
  (Module, [moduleName]) -> Just $ S.Module moduleName []
  (Import, [importName]) -> Just $ S.Import importName []
  (Function, [id, params, block]) -> Just $ S.Function id (toList $ unwrap params) (toList $ unwrap block)
  (For, [body]) | Other "block" <- Info.category (extract body) -> Just $ S.For [] (toList (unwrap body))
  (For, [forClause, body]) | Other "for_clause" <- Info.category (extract forClause) -> Just $ S.For (toList (unwrap forClause)) (toList (unwrap body))
  (For, [rangeClause, body]) | Other "range_clause" <- Info.category (extract rangeClause) -> Just $ S.For (toList (unwrap rangeClause)) (toList (unwrap body))
  (TypeDecl, [identifier, ty]) -> Just $ S.TypeDecl identifier ty
  (StructTy, _) -> Just (S.Ty children)
  (FieldDecl, [idList]) | [ident] <- toList (unwrap idList)
                        -> Just (S.FieldDecl ident Nothing Nothing)
  (FieldDecl, [idList, ty]) | [ident] <- toList (unwrap idList)
                            -> Just $ case Info.category (extract ty) of
                                StringLiteral -> S.FieldDecl ident Nothing (Just ty)
                                _ -> S.FieldDecl ident (Just ty) Nothing
  (FieldDecl, [idList, ty, tag]) | [ident] <- toList (unwrap idList)
                                 -> Just (S.FieldDecl ident (Just ty) (Just tag))
  (ParameterDecl, param : ty) -> Just $ S.ParameterDecl (listToMaybe ty) param
  (Assignment, [identifier, expression]) -> Just $ S.VarAssignment identifier expression
  (Select, _) -> Just $ S.Select (children >>= toList . unwrap)
  (Go, [expr]) -> Just $ S.Go expr
  (Defer, [expr]) -> Just $ S.Defer expr
  (SubscriptAccess, [a, b]) -> Just $ S.SubscriptAccess a b
  (IndexExpression, [a, b]) -> Just $ S.SubscriptAccess a b
  (Slice, [a, rest]) -> Just $ S.SubscriptAccess a rest
  (Other "composite_literal", [ty, values]) | ArrayTy <- Info.category (extract ty)
                                            -> Just $ S.Array (Just ty) (toList (unwrap values))
                                            | DictionaryTy <- Info.category (extract ty)
                                            -> Just $ S.Object (Just ty) (toList (unwrap values))
                                            | SliceTy <- Info.category (extract ty)
                                            -> Just $ S.SubscriptAccess ty values
  (Other "composite_literal", []) -> Just $ S.Struct Nothing []
  (Other "composite_literal", [ty]) -> Just $ S.Struct (Just ty) []
  (Other "composite_literal", [ty, values]) -> Just $ S.Struct (Just ty) (toList (unwrap values))
  (TypeAssertion, [a, b]) -> Just $ S.TypeAssertion a b
  (TypeConversion, [a, b]) -> Just $ S.TypeConversion a b
  -- TODO: Handle multiple var specs
  (VarAssignment, [identifier, expression]) -> Just $ S.VarAssignment identifier expression
  (VarDecl, [idList, ty]) | Identifier <- Info.category (extract ty) -> Just $ S.VarDecl idList (Just ty)
  (FunctionCall, id : rest) -> Just $ S.FunctionCall id rest
  (AnonymousFunction, [params, _, body]) | [params'] <- toList (unwrap params)
                                         -> Just $ S.AnonymousFunction (toList (unwrap params')) (toList (unwrap body))
  (PointerTy, _) -> Just $ S.Ty children
  (ChannelTy, _) -> Just $ S.Ty children
  (Send, [channel, expr]) -> Just $ S.Send channel expr
  (Operator, _) -> Just $ S.Operator children
  (FunctionTy, _) -> Just $ S.Ty children
  (IncrementStatement, _) ->
    Just $ S.Leaf $ toText source
  (DecrementStatement, _) ->
    Just $ S.Leaf $ toText source
  (QualifiedIdentifier, _) ->
    Just $ S.Leaf $ toText source
  (Method, [params, name, fun]) -> Just (S.Method name Nothing (toList (unwrap params)) (toList (unwrap fun)))
  (Method, [params, name, outParams, fun]) -> Just (S.Method name Nothing (toList (unwrap params) <> toList (unwrap outParams)) (toList (unwrap fun)))
  (Method, [params, name, outParams, ty, fun]) -> Just (S.Method name (Just ty) (toList (unwrap params) <> toList (unwrap outParams)) (toList (unwrap fun)))
  _ -> Nothing

categoryForGoName :: Text -> Category
categoryForGoName = \case
  "identifier" -> Identifier
  "int_literal" -> NumberLiteral
  "float_literal" -> FloatLiteral
  "comment" -> Comment
  "return_statement" -> Return
  "interpreted_string_literal" -> StringLiteral
  "raw_string_literal" -> StringLiteral
  "binary_expression" -> RelationalOperator
  "function_declaration" -> Function
  "func_literal" -> AnonymousFunction
  "call_expression" -> FunctionCall
  "selector_expression" -> SubscriptAccess
  "index_expression" -> IndexExpression
  "slice_expression" -> Slice
  "parameters" -> Args
  "short_var_declaration" -> VarDecl
  "var_spec" -> VarAssignment
  "const_spec" -> VarAssignment
  "assignment_statement" -> Assignment
  "source_file" -> Program
  "package_clause" -> Module
  "if_statement" -> If
  "for_statement" -> For
  "expression_switch_statement" -> Switch
  "type_switch_statement" -> Switch
  "expression_case_clause" -> Case
  "type_case_clause" -> Case
  "select_statement" -> Select
  "communication_case" -> Case
  "defer_statement" -> Defer
  "go_statement" -> Go
  "type_assertion_expression" -> TypeAssertion
  "type_conversion_expression" -> TypeConversion
  "keyed_element" -> Pair
  "struct_type" -> StructTy
  "map_type" -> DictionaryTy
  "array_type" -> ArrayTy
  "implicit_length_array_type" -> ArrayTy
  "parameter_declaration" -> ParameterDecl
  "expression_case" -> Case
  "type_spec" -> TypeDecl
  "field_declaration" -> FieldDecl
  "pointer_type" -> PointerTy
  "slice_type" -> SliceTy
  "element" -> Element
  "literal_value" -> Literal
  "channel_type" -> ChannelTy
  "send_statement" -> Send
  "unary_expression" -> Operator
  "function_type" -> FunctionTy
  "inc_statement" -> IncrementStatement
  "dec_statement" -> DecrementStatement
  "qualified_identifier" -> QualifiedIdentifier
  "break_statement" -> Break
  "continue_statement" -> Continue
  "rune_literal" -> RuneLiteral
  "method_declaration" -> Method
  "import_spec" -> Import
  "block" -> ExpressionStatements
  s -> Other (toS s)
