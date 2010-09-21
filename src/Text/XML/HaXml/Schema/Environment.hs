{-# LANGUAGE PatternGuards #-}
module Text.XML.HaXml.Schema.Environment
  ( module Text.XML.HaXml.Schema.Environment
  ) where

import Text.XML.HaXml.Types (QName(..),Name(..),Namespace(..))
import Text.XML.HaXml.Schema.XSDTypeModel
import Text.XML.HaXml.Schema.NameConversion (wordsBy)

import qualified Data.Map as Map
import Data.Map (Map)
import Data.List (foldl')

-- Some things we probably want to do.
-- * Build Maps from :
--       typename        to definition
--       element name    to definition
--       attribute name  to definition
--       (element) group to definition
--       attribute group to definition
-- * XSD types become top-level types in Haskell.
-- * XSD element decls also become top-level types in Haskell.
-- * Element groups get their own Haskell types too.
-- * Attributes and attribute groups do not become types, they are
--   simply constituent parts of an element.
-- * Resolve element/attribute references by inlining their names.

-- If a complextype definition includes nested in-line decls of other
-- types, we need to be able to lift them out to the top-level, then
-- refer to them by name only at the nested position.

data Environment =  Environment
    { env_type      :: Map QName (Either SimpleType ComplexType)
    , env_element   :: Map QName ElementDecl
    , env_attribute :: Map QName AttributeDecl
    , env_group     :: Map QName Group
    , env_attrgroup :: Map QName AttrGroup
    , env_namespace :: Map String{-URI-} String{-Prefix-}
    }

-- | An empty environment of XSD type mappings.
emptyEnv :: Environment
emptyEnv = Environment Map.empty Map.empty Map.empty
                       Map.empty Map.empty Map.empty

-- | Combine two environments (e.g. read from different interface files)
combineEnv :: Environment -> Environment -> Environment
combineEnv e1 e0 = Environment
    { env_type      = Map.union (env_type e1)      (env_type e0)
    , env_element   = Map.union (env_element e1)   (env_element e0)
    , env_attribute = Map.union (env_attribute e1) (env_attribute e0)
    , env_group     = Map.union (env_group e1)     (env_group e0)
    , env_attrgroup = Map.union (env_attrgroup e1) (env_attrgroup e0)
    , env_namespace = Map.union (env_namespace e1) (env_namespace e0)
    }

-- | Build an environment of XSD type mappings from a schema module.
mkEnvironment :: Schema -> Environment -> Environment
mkEnvironment s init = foldl' item (addNS init (schema_namespaces s))
                                   (schema_items s)
  where
    -- think about qualification, w.r.t targetNamespace, elementFormDefault, etc
    item env (Include _ _)       = env
    item env (Import _ _ _)      = env
    item env (Redefine _ _)      = env	-- revisit this
    item env (Annotation _)      = env
    item env (Simple st)         = simple env st
    item env (Complex ct)        = complex env ct
    item env (SchemaElement e)   = elementDecl env e
    item env (SchemaAttribute a) = attributeDecl env a
    item env (AttributeGroup g)  = attrGroup env g
    item env (SchemaGroup g)     = group env g

    simple env s@(Restricted _ (Just n) _ _)
                                 = env{env_type=Map.insert (mkN n) (Left s)
                                                           (env_type env)}
    simple env s@(ListOf _ (Just n) _ _)
                                 = env{env_type=Map.insert (mkN n) (Left s)
                                                           (env_type env)}
    simple env s@(UnionOf _ (Just n) _ _ _)
                                 = env{env_type=Map.insert (mkN n) (Left s)
                                                           (env_type env)}
    simple env   _               = env

    -- Only toplevel names have global scope.
    -- Should we lift local names to toplevel with prefixed names?
    -- Or thread the environment explicitly through every tree-walker?
    -- Or resolve every reference to its referent in a single resolution pass?
    -- (Latter not good, because it potentially duplicates exprs?)
    complex env c
      | Nothing <- complex_name c = env
      | Just n  <- complex_name c = env{env_type=Map.insert (mkN n) (Right c)
                                                            (env_type env)}
    elementDecl env e
      | Right r <- elem_nameOrRef e = env
      | Left nt <- elem_nameOrRef e = env{env_element=Map.insert
                                                            (mkN $ theName nt) e
                                                            (env_element env)}
    attributeDecl env a
      | Right r <- attr_nameOrRef a = env
      | Left nt <- attr_nameOrRef a = env{env_attribute=
                                            Map.insert (mkN $ theName nt) a
                                                       (env_attribute env)}
    attrGroup env g
      | Right r <- attrgroup_nameOrRef g = env
      | Left n  <- attrgroup_nameOrRef g = env{env_attrgroup=Map.insert (mkN n) g
                                                           (env_attrgroup env)}
    group env g
      | Right r <- group_nameOrRef g = env
      | Left n  <- group_nameOrRef g = env{env_group=Map.insert (mkN n) g
                                                           (env_group env)}
    mkN = N . last . wordsBy (==':')

    addNS env nss = env{env_namespace = foldr newNS (env_namespace env) nss}
              where newNS ns env = Map.insert (nsURI ns) (nsPrefix ns) env

-- | Find all direct module dependencies.
gatherImports :: Schema -> [FilePath]
gatherImports s = [ f | (Include f _)  <- schema_items s ] ++
                  [ f | (Import _ f _) <- schema_items s ]

