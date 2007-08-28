-- ------------------------------------------------------------

{- |
   Module     : Text.XML.HXT.Arrow.XmlPickle
   Copyright  : Copyright (C) 2005 Uwe Schmidt
   License    : MIT

   Maintainer : Uwe Schmidt (uwe@fh-wedel.de)
   Stability  : experimental
   Portability: portable
   Version    : $Id$

Pickler functions for converting between user defined data types
and XmlTree data. Usefull for persistent storage and retreival
of arbitray data as XML documents

This module is an adaptation of the pickler combinators
developed by Andrew Kennedy
( http:\/\/research.microsoft.com\/~akenn\/fun\/picklercombinators.pdf )

The difference to Kennedys approach is that the target is not
a list of Chars but a list of XmlTrees. The basic picklers will
convert data into XML text nodes. New are the picklers for
creating elements and attributes.

One extension was neccessary: The unpickling may fail.
Therefore the unpickler has a Maybe result type.
Failure is used to unpickle optional elements
(Maybe data) and lists of arbitray length

There is an example program demonstrating the use
of the picklers for a none trivial data structure.
(see \"examples\/arrows\/pickle\" directory)

-}

-- ------------------------------------------------------------

module Text.XML.HXT.Arrow.XmlPickle
    ( PU(..)
    , xpZero
    , xpUnit
    , xpLift
    , xpLiftMaybe
    , xpCondSeq
    , xpSeq
    , xpList
    , xpText
    , xpText0
    , xpPrim
    , xpChoice
    , xpWrap
    , xpWrapMaybe
    , xpPair
    , xpTriple
    , xp4Tuple
    , xp5Tuple
    , xpOption
    , xpAlt
    , xpElem
    , xpAttr
    , xpTree
    , pickleDoc
    , unpickleDoc
    , XmlPickler
    , xpickle
    , xpickleDocument
    , xunpickleDocument
    )
where

import           Data.Maybe

import           Control.Arrow.ListArrows
import           Text.XML.HXT.Arrow.DOMInterface
import           Text.XML.HXT.Arrow.XmlArrow
import           Text.XML.HXT.Arrow.XmlIOStateArrow
import           Text.XML.HXT.Arrow.ReadDocument
import           Text.XML.HXT.Arrow.WriteDocument
import qualified Text.XML.HXT.Arrow.XmlNode as XN

-- ------------------------------------------------------------

data St		= St { attributes :: [XmlTree]
		     , contents   :: [XmlTree]
		     }

data PU a	= PU { appPickle   :: (a, St) -> St
		     , appUnPickle :: St -> (Maybe a, St)
		     }

emptySt		:: St
emptySt		=  St { attributes = []
		      , contents   = []
		      }

addAtt		:: XmlTree -> St -> St
addAtt x s	= s {attributes = x : attributes s}

addCont		:: XmlTree -> St -> St
addCont x s	= s {contents = x : contents s}

dropCont	:: St -> St
dropCont s	= s { contents = drop 1 (contents s) }

getAtt		:: String -> St -> Maybe XmlTree
getAtt name s
    = listToMaybe $
      runLA ( arrL attributes
	      >>>
	      isAttr >>> hasName name
	    ) s

getCont		:: St -> Maybe XmlTree
getCont s	= listToMaybe . contents $ s

-- ------------------------------------------------------------

{-
pickle	:: PU a -> a -> XmlTree
pickle p v = head . contents . appPickle p $ (v, emptySt)

unpickle :: PU a -> XmlTree -> Maybe a
unpickle p t = fst . appUnPickle p $ addCont t emptySt
-}

-- | conversion of an arbitrary value into an XML document tree.
--
-- The pickler, first parameter, controls the conversion process.
-- Result is a complete document tree including a root node

pickleDoc	:: PU a -> a -> XmlTree
pickleDoc p v
    = XN.mkRoot (attributes st) (contents st)
    where
    st = appPickle p (v, emptySt)

-- | Conversion of an XML document tree into an arbitrary data type
--
-- The inverse of 'pickleDoc'.
-- This law should hold for all picklers: @ unpickle px . pickle px $ v == Just v @.
-- Not every possible combination of picklers make sense.
-- For reconverting a value from an XML tree, is becomes neccessary,
-- to introduce \"enough\" markup for unpickling the value

unpickleDoc :: PU a -> XmlTree -> Maybe a
unpickleDoc p t
    | XN.isRoot t
	= fst . appUnPickle p $ St { attributes = fromJust . XN.getAttrl $  t
				   , contents   =            XN.getChildren t
				   }
    | otherwise
	= Nothing

-- ------------------------------------------------------------

-- | The zero pickler
--
-- Encodes othing, fails always during unpickling

xpZero			:: PU a
xpZero			=  PU { appPickle   = snd
			      , appUnPickle = \ s -> (Nothing, s)
			      }

-- unit pickler

xpUnit			:: PU ()
xpUnit			= xpLift ()

-- | Lift a value to a pickler
--
-- When pickling, nothing is encoded, when unpickling, the given value is inserted.
-- This pickler always succeeds.

xpLift			:: a -> PU a
xpLift x		=  PU { appPickle   = snd
			      , appUnPickle = \ s -> (Just x, s)
			      }

-- | Lift a Maybe value to a pickler.
--
-- @Nothing@ is mapped to the zero pickler, @Just x@ is pickled with @xpLift x@.

xpLiftMaybe		:: Maybe a -> PU a
xpLiftMaybe Nothing	= xpZero
xpLiftMaybe (Just x) 	= xpLift x


-- | pickle\/unpickle combinator for sequence and choice.
--
-- When the first unpickler fails,
-- the second one is taken, else the third one configured with the result from the first
-- is taken. This pickler is a generalisation for 'xpSeq' and 'xpChoice' .

xpCondSeq	:: PU b -> (b -> a) -> PU a -> (a -> PU b) -> PU b
xpCondSeq pd f pa k
    = PU { appPickle   = ( \ (b, s) ->
	                   let
			   a  = f b
			   pb = k a
			   in
			   appPickle pa (a, (appPickle pb (b, s)))
			 )
	 , appUnPickle = ( \ s ->
			   let
			   (a, s') = appUnPickle pa s
			   in
			   case a of
			   Nothing -> appUnPickle pd     s
			   Just a' -> appUnPickle (k a') s'
			 )
	 }


-- | Combine two picklers sequentially.
--
-- If the first fails during
-- unpickling, the whole unpickler fails

xpSeq	:: (b -> a) -> PU a -> (a -> PU b) -> PU b
xpSeq	= xpCondSeq xpZero


-- | combine tow picklers with a choice
--
-- Run two picklers in sequence like with xpSeq.
-- When during unpickling the first one fails,
-- an alternative pickler (first argument) is applied.
-- This pickler only is used as combinator for unpickling.
 
xpChoice		:: PU b -> PU a -> (a -> PU b) -> PU b
xpChoice pb	= xpCondSeq pb undefined


-- | map value into another domain and apply pickler there
--
-- One of the most often used picklers.

xpWrap			:: (a -> b, b -> a) -> PU a -> PU b
xpWrap (i, j) pa		= xpSeq j pa (xpLift . i)

-- | like 'xpWrap', but if the inverse mapping is undefined, the unpickler fails
--
-- Map a value into another domain. If the inverse mapping is
-- undefined (Nothing), the unpickler fails

xpWrapMaybe		:: (a -> Maybe b, b -> a) -> PU a -> PU b
xpWrapMaybe (i, j) pa	= xpSeq j pa (xpLiftMaybe . i)

-- | pickle a pair of values sequentially
--
-- Used for pairs or together with wrap for pickling
-- algebraic data types with two components

xpPair	:: PU a -> PU b -> PU (a, b)
xpPair pa pb
    = xpSeq fst pa (\ a ->
      xpSeq snd pb (\ b ->
      xpLift (a,b)))

-- | Like 'xpPair' but for triples

xpTriple	:: PU a -> PU b -> PU c -> PU (a, b, c)
xpTriple pa pb pc
    = xpWrap (toTriple, fromTriple) (xpPair pa (xpPair pb pc))
    where
    toTriple   ~(a, ~(b, c)) = (a,  b, c )
    fromTriple ~(a,   b, c ) = (a, (b, c))

-- | Like 'xpPair' and 'xpTriple' but for 4-tuples

xp4Tuple	:: PU a -> PU b -> PU c -> PU d -> PU (a, b, c, d)
xp4Tuple pa pb pc pd
    = xpWrap (toQuad, fromQuad) (xpPair pa (xpPair pb (xpPair pc pd)))
    where
    toQuad   ~(a, ~(b, ~(c, d))) = (a,  b,  c, d  )
    fromQuad ~(a,   b,   c, d  ) = (a, (b, (c, d)))

-- | Like 'xpPair' and 'xpTriple' but for 5-tuples

xp5Tuple	:: PU a -> PU b -> PU c -> PU d -> PU e -> PU (a, b, c, d, e)
xp5Tuple pa pb pc pd pe
    = xpWrap (toQuint, fromQuint) (xpPair pa (xpPair pb (xpPair pc (xpPair pd pe))))
    where
    toQuint   ~(a, ~(b, ~(c, ~(d, e)))) = (a,  b,  c,  d, e   )
    fromQuint ~(a,   b,   c,   d, e   ) = (a, (b, (c, (d, e))))

-- | Pickle a string into an XML text node
--
-- One of the most often used primitive picklers. Attention:
-- For pickling empty strings use 'xpText0'.

xpText	:: PU String
xpText	= PU { appPickle   = \ (s, st) -> addCont (XN.mkText s) st
	     , appUnPickle = \ st -> fromMaybe (Nothing, st) (unpickleString st)
	     }
    where
    unpickleString st
	= do
	  t <- getCont st
	  s <- XN.getText t
	  return (Just s, dropCont st)

-- | Pickle a possibly empty string into an XML node.
--
-- Must be used in all places, where empty strings are legal values.
-- If the content of an element can be an empty string, this string disapears
-- during storing the DOM into a document and reparse the document.
-- So the empty text node becomes nothing, and the pickler must deliver an empty string,
-- if there is no text node in the document.

xpText0	:: PU String
xpText0
    = xpWrap (fromMaybe "", emptyToNothing) $ xpOption xpText
    where
    emptyToNothing "" = Nothing
    emptyToNothing x  = Just x

-- | Pickle an arbitrary value by applyling show during pickling
-- and read during unpickling.
--
-- Real pickling is then done with 'xpString'.
-- One of the most often used pimitive picklers. Applicable for all
-- types which are instances of @Read@ and @Show@

xpPrim	:: (Read a, Show a) => PU a
xpPrim
    = xpWrapMaybe (readMaybe, show) xpText
    where
    readMaybe	:: Read a => String -> Maybe a
    readMaybe str
	= val (reads str)
	where
	val [(x,"")] = Just x
	val _        = Nothing

-- | Pickle an XmlTree by just adding it
--
-- Usefull for components of type XmlTree in other data structures

xpTree	:: PU XmlTree
xpTree	= PU { appPickle   = \ (s, st) -> addCont s st
	     , appUnPickle = \ st -> fromMaybe (Nothing, st) (unpickleTree st)
	     }
    where
    unpickleTree st
	= do
	  t <- getCont st
	  return (Just t, dropCont st)

-- | Encoding of optional data by ignoring the Nothing case during pickling
-- and relying on failure during unpickling to recompute the Nothing case
--
-- The default pickler for Maybe types

xpOption	:: PU a -> PU (Maybe a)
xpOption pa
    = PU { appPickle   = ( \ (a, st) ->
			   case a of
			   Nothing -> st
			   Just x  -> appPickle pa (x, st)
			 )

	 , appUnPickle = appUnPickle $
	                 xpChoice (xpLift Nothing) pa (xpLift . Just)
	 }

-- | Encoding of list values by pickling all list elements sequentially.
--
-- Unpickler relies on failure for detecting the end of the list.
-- The standard pickler for lists. Can also be used in compination with 'xpWrap'
-- for constructing set and map picklers

xpList	:: PU a -> PU [a]
xpList pa
    = PU { appPickle   = ( \ (a, st) ->
			   case a of
			   []  -> st
			   _:_ -> appPickle pc (a, st)
			 )
	 , appUnPickle = appUnPickle $
                         xpChoice (xpLift []) pa
	                   (\ x -> xpSeq id (xpList pa) (\xs -> xpLift (x:xs))
			 )
	 }
      where
      pc = xpSeq head  pa       (\ x ->
	   xpSeq tail (xpList pa) (\ xs ->
	   xpLift (x:xs)))

-- | Pickler for sum data types.
--
-- Every constructor is mapped to an index into the list of picklers.
-- The index is used only during pickling, not during unpickling, there the 1. match is taken

xpAlt	:: (a -> Int) -> [PU a] -> PU a
xpAlt tag ps
    = PU { appPickle   = ( \ (a, st) ->
			   let
			   pa = ps !! (tag a)
			   in
			   appPickle pa (a, st)
			 )
	 , appUnPickle = appUnPickle $
	                 ( case ps of
			   []     -> xpZero
			   pa:ps1 -> xpChoice (xpAlt tag ps1) pa xpLift
			 )
	 }

-- | Pickler for wrapping\/unwrapping data into an XML element
--
-- Extra parameter is the element name. THE pickler for constructing
-- nested structures

xpElem	:: String -> PU a -> PU a
xpElem name pa
    = PU { appPickle   = ( \ (a, st) ->
			   let
	                   st' = appPickle pa (a, emptySt)
			   in
			   addCont (XN.mkElement (mkName name) (attributes st') (contents st')) st
			 )
	 , appUnPickle = \ st -> fromMaybe (Nothing, st) (unpickleElement st)
	 }
      where
      unpickleElement st
	  = do
	    t <- getCont st
	    n <- XN.getElemName t
	    if qualifiedName n /= name
	       then fail "element name does not match"
	       else do
		    let cs = XN.getChildren t
		    al <- XN.getAttrl t
		    res <- fst . appUnPickle pa $ St {attributes = al, contents = cs}
		    return (Just res, dropCont st)

-- | Pickler for storing\/retreiving data into\/from an attribute value
--
-- The attribute is inserted in the surrounding element constructed by the 'xpElem' pickler

xpAttr	:: String -> PU a -> PU a
xpAttr name pa
    = PU { appPickle   = ( \ (a, st) ->
			   let
			   st' = appPickle pa (a, emptySt)
			   in
			   addAtt (XN.mkAttr (mkName name) (contents st')) st
			 )
	 , appUnPickle = \ st -> fromMaybe (Nothing, st) (unpickleAttr st)
	 }
      where
      unpickleAttr st
	  = do
	    a <- getAtt name st
	    let av = XN.getChildren a
	    res <- fst . appUnPickle pa $ St {attributes = [], contents = av}
	    return (Just res, st)	-- attribute is not removed from attribute list,
					-- attributes are selected by name

-- ------------------------------------------------------------

-- | The class for overloading 'xpickle', the default pickler

class XmlPickler a where
    xpickle :: PU a

instance XmlPickler Int where
    xpickle = xpPrim

instance XmlPickler Integer where
    xpickle = xpPrim

{-
  no instance of XmlPickler Char
  because then every text would be encoded
  char by char, because of the instance for lists

instance XmlPickler Char where
    xpickle = xpPrim
-}

instance XmlPickler () where
    xpickle = xpUnit

instance (XmlPickler a, XmlPickler b) => XmlPickler (a,b) where
    xpickle = xpPair xpickle xpickle

instance (XmlPickler a, XmlPickler b, XmlPickler c) => XmlPickler (a,b,c) where
    xpickle = xpTriple xpickle xpickle xpickle

instance (XmlPickler a, XmlPickler b, XmlPickler c, XmlPickler d) => XmlPickler (a,b,c,d) where
    xpickle = xp4Tuple xpickle xpickle xpickle xpickle

instance (XmlPickler a, XmlPickler b, XmlPickler c, XmlPickler d, XmlPickler e) => XmlPickler (a,b,c,d,e) where
    xpickle = xp5Tuple xpickle xpickle xpickle xpickle xpickle

instance XmlPickler a => XmlPickler [a] where
    xpickle = xpList xpickle

instance XmlPickler a => XmlPickler (Maybe a) where
    xpickle = xpOption xpickle

-- ------------------------------------------------------------

-- the arrow interface for pickling and unpickling

-- | store an arbitray value in a persistent XML document
--
-- The pickler converts a value into an XML tree, this is written out with
-- 'Text.XML.HXT.Arrow.writeDocument'. The option list is passed to 'Text.XML.HXT.Arrow.writeDocument'

xpickleDocument		:: PU a -> Attributes -> String -> IOStateArrow s a XmlTree
xpickleDocument xp al dest
    = arr (pickleDoc xp)
      >>>
      writeDocument al dest

-- | read an arbitray value from an XML document
--
-- The document is read with 'Text.XML.HXT.Arrow.readDocument'. Options are passed
-- to 'Text.XML.HXT.Arrow.readDocument'. The conversion from XmlTree is done with the
-- pickler.
--
-- @ xpickleDocument xp al dest >>> xunpickleDocument xp al' dest @ is the identity arrow
-- when applied with the appropriate options. When during pickling indentation is switched on,
-- the whitespace must be removed during unpickling.

xunpickleDocument	:: PU a -> Attributes -> String -> IOStateArrow s b a
xunpickleDocument xp al src
    = readDocument  al src
      >>>
      arrL (maybeToList . unpickleDoc xp)

-- ------------------------------------------------------------
