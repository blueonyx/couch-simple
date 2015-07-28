{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections     #-}

{- |

Module      : Database.Couch.Explicit.Database
Description : Database-oriented requests to CouchDB
Copyright   : Copyright (c) 2015, Michael Alan Dorman
License     : MIT
Maintainer  : mdorman@jaunder.io
Stability   : experimental
Portability : POSIX

This module is intended to be @import qualified@.  /No attempt/ has
been made to keep names of types or functions from clashing with
obvious or otherwise commonly-used names.

The functions here are derived from (and presented in the same order
as) http://docs.couchdb.org/en/1.6.1/api/database/index.html.

-}

module Database.Couch.Explicit.Database where

import           Control.Monad                 (return, when, (>>=))
import           Control.Monad.IO.Class        (MonadIO)
import           Data.Aeson                    (FromJSON, ToJSON,
                                                Value (Object), object, toJSON)
import           Data.Bool                     (Bool (True))
import           Data.Either                   (Either)
import           Data.Function                 (($), (.))
import           Data.Functor                  (fmap)
import           Data.HashMap.Strict           (fromList)
import           Data.Maybe                    (Maybe (Just), catMaybes,
                                                fromJust, isJust)
import           Data.Text                     (Text)
import           Data.Text.Encoding            (encodeUtf8)
import           Database.Couch.Internal       (standardRequest,
                                                structureRequest)
import           Database.Couch.RequestBuilder (RequestBuilder, addPath,
                                                selectDb, selectDoc, setHeaders,
                                                setJsonBody, setMethod,
                                                setQueryParam)
import           Database.Couch.ResponseParser (checkStatusCode, failed, getKey,
                                                responseStatus, responseValue,
                                                toOutputType)
import           Database.Couch.Types          (Context,
                                                CouchError (NotFound, Unknown),
                                                DbAllDocs, DbBulkDocs,
                                                DbChanges, DocId,
                                                bdAllOrNothing, bdFullCommit,
                                                bdNewEdits, cLastEvent,
                                                toQueryParameters)
import           Network.HTTP.Client           (CookieJar)
import           Network.HTTP.Types            (statusCode)

-- | Check that the requested database exists.
--
-- <http://docs.couchdb.org/en/1.6.1/api/database/common.html#head--db API documentation>
--
-- Returns 'False' or 'True' as appropriate.
--
-- Status: __Complete__
exists :: (FromJSON a, MonadIO m) => Context -> m (Either CouchError (a, Maybe CookieJar))
exists =
  structureRequest request parse
  where
    request = do
      selectDb
      setMethod "HEAD"
    parse = do
      -- Check status codes by hand because we don't want 404 to be an error, just False
      s <- responseStatus
      case statusCode s of
        200 -> toOutputType $ object [("ok", toJSON True)]
        404 -> failed NotFound
        _   -> failed Unknown

-- | Get most basic meta-information.
--
-- <http://docs.couchdb.org/en/1.6.1/api/server/common.html#get--db API documentation>
--
-- The returned data is variable enough we content ourselves with just
-- returning a 'Value'.
--
-- Status: __Complete__
meta :: (FromJSON a, MonadIO m) => Context -> m (Either CouchError (a, Maybe CookieJar))
meta =
  standardRequest request
  where
    request =
      selectDb

-- | Create a database
--
-- <http://docs.couchdb.org/en/1.6.1/api/server/common.html#put--db API documentation>
--
-- The returned data is variable enough we content ourselves with just
-- returning a 'Value'.
--
-- Status: __Complete__
create :: (FromJSON a, MonadIO m) => Context -> m (Either CouchError (a, Maybe CookieJar))
create =
  standardRequest request
  where
    request = do
      selectDb
      setMethod "PUT"

-- | delete a database
--
-- <http://docs.couchdb.org/en/1.6.1/api/server/common.html#delete--db API documentation>
--
-- The returned data is variable enough we content ourselves with just
-- returning a 'Value'.
--
-- Status: __Complete__
delete :: (FromJSON a, MonadIO m) => Context -> m (Either CouchError (a, Maybe CookieJar))
delete =
  standardRequest request
  where
    request = do
      selectDb
      setMethod "DELETE"

-- | create a new document in a database
--
-- <http://docs.couchdb.org/en/1.6.1/api/server/common.html#post--db API documentation>
--
-- The constructor for the return type depends on whether the create
-- was done in batch mode, as there is no avenue for returning a
-- 'DocRev' in that circumstance.
--
-- Status: __Complete__
createDoc :: (FromJSON a, MonadIO m, ToJSON a) => Bool -> a -> Context -> m (Either CouchError (a, Maybe CookieJar))
createDoc batch doc =
  standardRequest request
  where
    request = do
      selectDb
      setMethod "POST"
      when batch (setQueryParam [("batch", Just "ok")])
      setJsonBody doc

-- | Get a list of all database documents.
--
-- <http://docs.couchdb.org/en/1.6.1/api/database/bulk-api.html#get--db-_all_docs API documentation>
--
-- The returned data is variable enough we content ourselves with just
-- a 'Value' for you to take apart.
--
-- Status: __Complete__
allDocs :: (FromJSON a, MonadIO m) => DbAllDocs -> Context -> m (Either CouchError (a, Maybe CookieJar))
allDocs param =
  standardRequest request
  where
    request = do
      selectDb
      addPath "_all_docs"
      setQueryParam $ toQueryParameters param

-- | Get a list of some database documents.
--
-- <http://docs.couchdb.org/en/1.6.1/api/database/bulk-api.html#post--db-_all_docs API documentation>
--
-- There's some ambiguity in the documentation as to whether this
-- accepts any query parameters.
--
-- The returned data is variable enough we content ourselves with just
-- returning a 'List' of 'Value'.
--
-- Status: __Limited?__
someDocs :: (FromJSON a, MonadIO m) => [DocId] -> Context -> m (Either CouchError (a, Maybe CookieJar))
someDocs ids =
  standardRequest request
  where
    request = do
      setMethod "POST"
      selectDb
      addPath "_all_docs"
      let parameters = Object (fromList [("keys", toJSON ids)])
      setJsonBody parameters

-- | Create or update a list of documents.
--
-- <http://docs.couchdb.org/en/1.6.1/api/database/bulk-api.html#post--db-_bulk_docs API documentation>
--
-- The returned data is variable enough we content ourselves with just
-- returning a 'List' of 'Value'.
--
-- Status: __Complete__
bulkDocs :: (FromJSON a, MonadIO m, ToJSON a) => DbBulkDocs -> [a] -> Context -> m (Either CouchError (a, Maybe CookieJar))
bulkDocs param docs =
  standardRequest request
  where
    request = do
      setMethod "POST"
      when (isJust $ bdFullCommit param)
        (setHeaders
           [("X-Couch-Full-Commit", if fromJust $ bdFullCommit param
                                      then "true"
                                      else "false")])
      selectDb
      addPath "_bulk_docs"
      let parameters = Object
                         ((fromList . catMaybes)
                            [ Just ("docs", toJSON docs)
                            , boolToParam "all_or_nothing" bdAllOrNothing
                            , boolToParam "new_edits" bdNewEdits
                            ])
      setJsonBody parameters
    boolToParam k s = do
      v <- s param
      return
        (k, if v
              then "true"
              else "false")

-- | Get a list of all document modifications .
--
-- <http://docs.couchdb.org/en/1.6.1/api/database/changes.html#get--db-_changes API documentation>
--
-- This call does not stream out results; therefore, it also doesn't
-- allow any specification of parameters for streaming.
--
-- The returned data is variable enough we content ourselves with just
-- returning a 'Value'.
--
-- Status: __Limited__
changes :: (FromJSON a, MonadIO m) => DbChanges -> Context -> m (Either CouchError (a, Maybe CookieJar))
changes param =
  standardRequest request
  where
    request = do
      when (isJust $ cLastEvent param)
        (setHeaders [("Last-Event-Id", encodeUtf8 . fromJust $ cLastEvent param)])
      selectDb
      addPath "_changes"

-- | Encode the common bits for our two compact calls
compactBase :: RequestBuilder ()
compactBase = do
  setMethod "POST"
  selectDb
  addPath "_compact"

-- | Compact a database
--
-- <http://docs.couchdb.org/en/1.6.1/api/database/compact.html#post--db-_compact API documentation>
--
-- Run the compaction process on an entire database
--
-- Status: __Complete__
compact :: (FromJSON a, MonadIO m) => Context -> m (Either CouchError (a, Maybe CookieJar))
compact =
  standardRequest request
  where
    request =
      compactBase

-- | Compact the views attached to a particular design document
--
-- <http://docs.couchdb.org/en/1.6.1/api/database/compact.html#post--db-_compact-ddoc API documentation>
--
-- Run the compaction process on the views associated with the specified design document
--
-- Status: __Complete__
compactDesignDoc :: (FromJSON a, MonadIO m) => DocId -> Context -> m (Either CouchError (a, Maybe CookieJar))
compactDesignDoc doc =
  standardRequest request
  where
    request = do
      compactBase
      selectDoc doc

-- | Ensure that all changes to the database have made it to disk
--
-- <http://docs.couchdb.org/en/1.6.1/api/database/compact.html#post--db-_ensure_full_commit API documentation>
--
-- The start time for the instance doesn't seem very interesting,
-- especially for this particular operation, so I haven't bothered to
-- try and return it.
--
-- Status: __Complete__
sync :: (FromJSON a, MonadIO m) => Context -> m (Either CouchError (a, Maybe CookieJar))
sync =
  standardRequest request
  where
    request = do
      setMethod "POST"
      selectDb
      addPath "_ensure_full_commit"

-- | Cleanup any stray view definitions
--
-- <http://docs.couchdb.org/en/1.6.1/api/database/compact.html#post--db-_view_cleanup API documentation>
--
-- Clean up out of data view indices, which follow from changes to the
-- view content.
--
-- Status: __Complete__
cleanup :: (FromJSON a, MonadIO m) => Context -> m (Either CouchError (a, Maybe CookieJar))
cleanup =
  standardRequest request
  where
    request = do
      setMethod "POST"
      selectDb
      addPath "_view_cleanup"

-- | Get security information for database
--
-- <http://docs.couchdb.org/en/1.6.1/api/database/security.html#get--db-_security API documentation>
--
-- Although there are base requirements for the content this returns
-- ("admin" and "members" keys, which each contain "users" and
-- "roles"), the system does not prevent you from adding (and even
-- using in validation functions) additional fields, so we keep the
-- return value general
--
-- Status: __Complete__
getSecurity :: (FromJSON a, MonadIO m) => Context -> m (Either CouchError (a, Maybe CookieJar))
getSecurity =
  standardRequest request
  where
    request = do
      setMethod "GET"
      selectDb
      addPath "_security"

-- | Set security information for database
--
-- <http://docs.couchdb.org/en/1.6.1/api/database/security.html#post--db-_security API documentation>
--
-- Although there are base requirements for the content this accepts
-- ("admin" and "members" keys, which each contain "users" and
-- "roles"), the system does not prevent you from adding (and even
-- using in validation functions) additional fields, so we keep the
-- input value general
--
-- Status: __Complete__
setSecurity :: (FromJSON b, MonadIO m, ToJSON a) => a -> Context -> m (Either CouchError (b, Maybe CookieJar))
setSecurity doc =
  standardRequest request
  where
    request = do
      setMethod "PUT"
      selectDb
      addPath "_security"
      setJsonBody doc

-- | Create a temporary view
--
-- <http://docs.couchdb.org/en/1.6.1/api/database/temp-views.html#post--db-_temp_view API documentation>
--
-- Create a temporary view and return its results.
--
-- Status: __Complete__
tempView :: (FromJSON a, MonadIO m) => Text -> Maybe Text -> Context -> m (Either CouchError (a, Maybe CookieJar))
tempView map reduce =
  standardRequest request
  where
    request = do
      setMethod "POST"
      selectDb
      let parameters = Object
                         (fromList $ catMaybes
                                       [ Just ("map", toJSON map)
                                       , fmap (("reduce",) . toJSON) reduce
                                       ])
      addPath "_temp_view"
      setJsonBody parameters
