{-# LANGUAGE OverloadedStrings #-}

module Cardano.Tracer.Handlers.Logs.Utils
  ( createOrUpdateEmptyLog
  , createEmptyLogRotation
  , getTimeStampFromLog
  , isItLog
  , logExtension
  , logPrefix
  , timeStampFormat
  ) where

import           Cardano.Tracer.Configuration (LogFormat (..), LoggingParams (..))
import           Cardano.Tracer.Types (HandleRegistry, NodeName)
import           Cardano.Tracer.Utils (modifyRegistry_)

import           Control.Concurrent.Extra (Lock, withLock)
import           Data.Foldable (for_)
import qualified Data.Map as Map
import           Data.Maybe (isJust)
import qualified Data.Text as T
import           Data.Time.Clock (UTCTime)
import           Data.Time.Clock.System (getSystemTime, systemToUTCTime)
import           Data.Time.Format (defaultTimeLocale, formatTime, parseTimeM)
import           System.Directory (createDirectoryIfMissing)
import           System.FilePath (takeBaseName, takeExtension, takeFileName, (<.>), (</>))
import           System.IO (IOMode (WriteMode), hClose, openFile)

logPrefix :: String
logPrefix = "node-"

logExtension :: LogFormat -> String
logExtension ForHuman   = ".log"
logExtension ForMachine = ".json"

-- | An example of the valid log name: 'node-2021-11-29T09-55-04.json'.
isItLog :: LogFormat -> FilePath -> Bool
isItLog format pathToLog = hasProperPrefix && hasTimestamp && hasProperExt
 where
  fileName = takeFileName pathToLog
  hasProperPrefix = T.pack logPrefix `T.isPrefixOf` T.pack fileName
  hasTimestamp = isJust timeStamp
  hasProperExt = takeExtension fileName == logExtension format

  timeStamp :: Maybe UTCTime
  timeStamp = parseTimeM True defaultTimeLocale timeStampFormat $ T.unpack maybeTimestamp

  maybeTimestamp = T.drop (length logPrefix) . T.pack . takeBaseName $ fileName

createEmptyLogRotation
  :: Lock
  -> NodeName
  -> LoggingParams
  -> HandleRegistry
  -> FilePath
  -> LogFormat
  -> IO ()
createEmptyLogRotation currentLogLock nodeName loggingParams registry subDirForLogs format = do
  -- The root directory (as a parent for subDirForLogs) will be created as well if needed.
  createDirectoryIfMissing True subDirForLogs
  createOrUpdateEmptyLog currentLogLock nodeName loggingParams registry subDirForLogs format

-- | Create an empty log file (with the current timestamp in the name).
createOrUpdateEmptyLog :: Lock -> NodeName -> LoggingParams -> HandleRegistry -> FilePath -> LogFormat -> IO ()
createOrUpdateEmptyLog currentLogLock nodeName loggingParams registry subDirForLogs format = do
  withLock currentLogLock do
    ts <- formatTime defaultTimeLocale timeStampFormat . systemToUTCTime <$> getSystemTime
    let pathToLog = subDirForLogs </> logPrefix <> ts <.> logExtension format

    modifyRegistry_ registry \handles -> do

      for_ @Maybe (Map.lookup (nodeName, loggingParams) handles) \(handle, _filePath) ->
        hClose handle

      newHandle <- openFile pathToLog WriteMode
      let newMap = Map.insert (nodeName, loggingParams) (newHandle, pathToLog) handles
      pure newMap

getTimeStampFromLog :: FilePath -> Maybe UTCTime
getTimeStampFromLog pathToLog =
  parseTimeM True defaultTimeLocale timeStampFormat timeStamp
 where
  timeStamp = drop (length logPrefix) . takeBaseName . takeFileName $ pathToLog

timeStampFormat :: String
timeStampFormat = "%Y-%m-%dT%H-%M-%S"
