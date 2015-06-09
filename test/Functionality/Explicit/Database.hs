{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}

module Functionality.Explicit.Database where

import           Control.Applicative              ((<$>))
import           Data.Function                    (($))
import qualified Database.Couch.Explicit.Database as Database (exists)
import           Database.Couch.Types             (Context, CouchError (..))
import           Functionality.Util               (dbContext, runTests,
                                                   testAgainstFailure,
                                                   testAgainstSchema,
                                                   withDb)
import           Network.HTTP.Client              (Manager)
import           System.IO                        (IO)
import           Test.Tasty                       (TestTree, testGroup)

_main :: IO ()
_main = runTests tests

tests :: Manager -> TestTree
tests manager = testGroup "Tests of the database interface" $
  ($ dbContext manager) <$> [databaseExists]

-- Database-oriented functions
databaseExists :: IO Context -> TestTree
databaseExists getContext =
  testGroup "Database existence"
    [
      testAgainstFailure "Randomly named database should not exist" Database.exists NotFound getContext,
      withDb getContext $ testAgainstSchema "Check for an existing database" Database.exists "head--db.json"
    ]