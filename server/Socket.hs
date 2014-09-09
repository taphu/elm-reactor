{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE OverloadedStrings #-}
module Socket where

import Control.Monad.Trans (MonadIO(liftIO))
import Control.Concurrent (threadDelay, forkIO, killThread, ThreadId)
import Control.Exception (catch, SomeException)
import qualified Data.ByteString.Char8 as BSC
import qualified Filesystem.Path.CurrentOS as FP
import qualified Network.WebSockets as WS
import qualified System.FSNotify.Devel as NDevel
import qualified System.FSNotify as Notify

import qualified Generate

fileChangeApp :: FilePath -> WS.ServerApp
fileChangeApp watchedFile pendingConnection =
 do connection <- WS.acceptRequest pendingConnection
    Notify.withManager $ \notifyManager -> do
        _ <- NDevel.treeExtExists notifyManager "." "elm" (sendHotSwap watchedFile connection)
        keepAlive connection


sendHotSwap :: FilePath -> WS.Connection -> FP.FilePath -> IO ()
sendHotSwap watchedFile connection _ =
 do result <- liftIO (Generate.js watchedFile)
    WS.sendTextData connection (BSC.pack result)


keepAlive :: WS.Connection -> IO ()
keepAlive connection =
    loop
  where
    loop :: IO ()
    loop = do
      pingThread <- forkIO ping
      listen pingThread

    ping :: IO ()
    ping = do
      threadDelay (10 * 1000000) -- 10 seconds
      WS.sendPing connection ("ping" :: BSC.ByteString) `catch` connectionClosed

    connectionClosed :: SomeException -> IO ()
    connectionClosed _ = return ()

    listen :: ThreadId -> IO ()
    listen pingThread = do
      pong <- WS.receive connection
      case pong of
        WS.DataMessage _ -> listen pingThread
        WS.ControlMessage controlMessage ->
            case controlMessage of
              WS.Ping _ -> listen pingThread
              WS.Pong _ -> loop
              WS.Close _ ->
                  killThread pingThread >> return ()
