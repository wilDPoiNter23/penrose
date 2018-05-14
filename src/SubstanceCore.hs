-- | "SubstanceCore" contains the grammers and parser for the 
--    Substance Core language
--    Author: Dor Ma'ayan, May 2018

{-# OPTIONS_HADDOCK prune #-}

--module SubstanceCore where
module Main (main) where -- for debugging purposes

import System.Process
import Control.Monad (void)
import Data.Void
import Debug.Trace
import System.IO -- read/write to file
import System.Environment
import Control.Arrow ((>>>))
import System.Random
import Debug.Trace
import Data.List
import Data.Maybe (fromMaybe)
import Data.Typeable
import Text.Megaparsec
import Text.Megaparsec.Char
import Text.Megaparsec.Expr
--import Text.PrettyPrint
--import Text.PrettyPrint.HughesPJClass hiding (colon, comma, parens, braces)
import qualified Data.Map.Strict as M
import qualified Text.Megaparsec.Char.Lexer as L
--------------------------------------- Substance AST ---------------------------------------

data SubType = TypeConst String -- these are all names, e.g. “Set”
    deriving (Show, Eq, Typeable)

data ValConstructor = ValConst String    -- “Cons”, “Times”
    deriving (Show, Eq, Typeable)

data Operator' = OperatorConst String             -- “Intersection” 
    deriving (Show, Eq, Typeable)

data Predicate = PredicateConst String            -- “Intersect”
    deriving (Show, Eq, Typeable)

data TypeVar = TypeVarConst String
    deriving (Show, Eq, Typeable)

data Var = VarConst String
    deriving (Show, Eq, Typeable)



data Type = ApplyT SubType [Arg] | TypeT TypeVar
    deriving (Show, Eq, Typeable)

data Arg = VarA Var | TypeA Type
    deriving (Show, Eq, Typeable)

data Expr = VarE Var | ApplyV Operator' [Expr] | ApplyC ValConstructor [Expr]
    deriving (Show, Eq, Typeable)

data SubStmt = Decl Type Var | Bind Var Expr | ApplyP Predicate [Var]
    deriving (Show, Eq, Typeable)


-- | Program is a sequence of statements
type SubProg = [SubStmt]
type SubObjDiv = ([SubDecl], [SubConstr])

-- | Declaration of Substance objects
data SubDecl
    = SubDeclConst Type Var
    deriving (Show, Eq, Typeable)

-- | Declaration of Substance constaints
data SubConstr
    = SubConstrConst Predicate [Var]
    deriving (Show, Eq, Typeable)

-- --------------------------------------- Substance Lexer -------------------------------------
-- | TODO: Some of the lexing functions are alreadt implemented at Utils.hs, Merge it and avoid duplications!
type Parser = Parsec Void String

-- | 'lineComment' and 'blockComment' are the two styles of commenting in Penrose and in the DSLL
lineComment, blockComment :: Parser ()
lineComment  = L.skipLineComment "--"
blockComment = L.skipBlockComment "/*" "*/"


-- | A strict space consumer. 'sc' only eats space and tab characters. It does __not__ eat newlines.
sc :: Parser ()
sc = L.space (void $ takeWhile1P Nothing f) lineComment empty
  where
    f x = x == ' ' || x == '\t'

-- | A normal space consumer. 'scn' consumes all whitespaces __including__ newlines.
scn :: Parser ()
scn = L.space space1 lineComment blockComment

lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc

-- A warper to make sure that we comsume whitespace after every lexeme
symbol :: String -> Parser String
symbol = L.symbol sc


newline' :: Parser ()
newline' = newline >> scn

-- Pill out the left and right parens from the input and roll-out the parsing
parens :: Parser a -> Parser a
parens = between (symbol "(") (symbol ")")

listOut :: Parser a -> Parser a
listOut = between (symbol "[") (symbol "]")



-- Define characters wich are part of the syntax
colon, arrow, comma, rsbrac, lsbrac, lparen, rparen,eq :: Parser ()
colon  = void (symbol ":")
comma  = void (symbol ",")
arrow  = void (symbol "->")
lsbrac = void (symbol "[")
rsbrac = void (symbol "]")
lparen = void (symbol "(")
rparen = void (symbol ")")
eq  = void (symbol "=")



--Reserverd word handling
rword :: String -> Parser()
rword w = (lexeme . try) (string w *> notFollowedBy alphaNumChar)
rws :: [String] -- The list of reserved words in DSLL
rws = [] -- TODO: Doesn't seems like there is any reserved word here, should seperate reserved words in Utils.hs for each PL

--Identifiers handling
identifier :: Parser String
identifier = (lexeme . try) (p >>= check)
  where
    p       = (:) <$> letterChar <*> many alphaNumChar
    check x = if x `elem` rws
                then fail $ "keyword " ++ show x ++ " cannot be an identifier"
                else return x


--------------------------------------- DSLL Parser -------------------------------------
-- | 'substanceParser' is the top-level parser function. The parser contains a list of functions
--    that parse small parts of the language. When parsing a source program, these functions are invoked in a top-down manner.
substanceParser :: Parser [SubStmt]
substanceParser = between scn eof subProg -- Parse all the statemnts between the spaces to the end of the input file

-- |'subProg' parses the entire actual Substance Core language program which is a collection of statements
subProg :: Parser [SubStmt]
subProg = do 
  stml <- subStmt `sepEndBy` newline'
  return stml

typeVarParser :: Parser TypeVar
typeVarParser = do
    i <- identifier
    return (TypeVarConst i)

varParser :: Parser Var
varParser = do
    i <- identifier
    return (VarConst i)

typeConstructorParser :: Parser SubType
typeConstructorParser = do
    i <- identifier
    return (TypeConst i)

valConstructorParser :: Parser ValConstructor
valConstructorParser = do
    i <- identifier
    return (ValConst i)

operatorParser :: Parser Operator'
operatorParser = do
    i <- identifier
    return (OperatorConst i)

predicateParser :: Parser Predicate
predicateParser = do
    i <- identifier
    return (PredicateConst i)


typeParser, applyT, typeT :: Parser Type
typeParser = try applyT <|> typeT
applyT = do
  tc <- typeConstructorParser
  args <- listOut (argParser `sepBy1` comma)
  return (ApplyT tc args)
typeT = do
  i <- typeVarParser
  return (TypeT i)

argParser, varA , typeA :: Parser Arg
argParser = try varA <|> typeA
varA  = do
  i <- varParser
  return (VarA i)
typeA = do
  i <- typeParser
  return (TypeA i)

exprParser, varE, applyV, applyC :: Parser Expr
exprParser = try varE <|> try applyV <|> applyC
varE = do
  i <- varParser
  return (VarE i)
applyV = do
  tc <- operatorParser
  args <- parens (exprParser `sepBy1` comma)
  return (ApplyV tc args)
applyC = do
  tc <- valConstructorParser
  args <- parens (exprParser `sepBy1` comma)
  return (ApplyC tc args)

subStmt, decl, bind, applyP :: Parser SubStmt
subStmt = try decl <|> try bind <|> applyP
decl = do
  t' <- typeParser
  v' <- varParser
  return (Decl t' v')
bind = do
  v' <- varParser
  eq
  e' <- exprParser
  return (Bind v' e')
applyP = do
  p <- predicateParser
  v' <- parens (varParser `sepBy1` comma)
  return (ApplyP p v')

-- --------------------------------------- Test Driver -------------------------------------
-- | For testing: first uncomment the module definition to make this module the
-- Main module. Usage: ghc SubstanceCore.hs; ./SubstanceCore <substance core-file>

--parseFromFile p file = parseTest p file <$> readFile file

main :: IO ()
main = do
    [substanceCoreFile] <- getArgs
    substanceCoreIn <- readFile substanceCoreFile
    parseTest substanceParser substanceCoreIn
    --case (parse dsllParser dsllFile dsllIn) of
    --    Left err -> putStr (parseErrorPretty err)
    --    Right xs -> writeFile outputFile (show xs)
    --putStrLn "Parsing Done!"  
    --mapM_ print parsed
    return ()











