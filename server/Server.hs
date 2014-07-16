{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE OverloadedStrings, DeriveDataTypeable #-}
module Main where

import Control.Applicative ((<$>),(<|>))
import Control.Monad (guard)
import Control.Monad.Trans (MonadIO(liftIO))
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Version as Version
import qualified Network.WebSockets.Snap as WSS
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html.Renderer.Utf8 as BlazeBS
import System.Console.CmdArgs
import System.Directory
import System.FilePath
import System.Process
import System.IO (hGetContents)
import Paths_elm_server (getDataFileName, version)
import qualified Elm.Internal.Paths as Elm
import Snap.Core
import Snap.Http.Server
import Snap.Util.FileServe

import Index
import qualified Debugger
import qualified Generate
import qualified Socket

data Flags = Flags
  { port :: Int
  , runtime :: Maybe FilePath
  } deriving (Data,Typeable,Show,Eq)

flags :: Flags
flags = Flags
  { port = 8000 &= help "set the port of the server"
  , runtime = Nothing &= typFile
              &= help "Specify a custom location for Elm's runtime system."
  } &= help "Quickly reload Elm projects in your browser. Just refresh to recompile.\n\
            \It serves static files and freshly recompiled Elm files."
    &= helpArg [explicit, name "help", name "h"]
    &= versionArg [ explicit, name "version", name "v"
                  , summary (Version.showVersion version)
                  ]
    &= summary ("Elm Server " ++ Version.showVersion version ++
                ", (c) Evan Czaplicki 2011-2014")


config :: Config Snap a
config = setAccessLog ConfigNoLog (setErrorLog ConfigNoLog defaultConfig)

-- | Set up the server.
main :: IO ()
main = do
  cargs <- cmdArgs flags
  (_,Just h,_,_) <- createProcess $ (shell "elm --version") { std_out = CreatePipe }
  elmVer <- hGetContents h
  putStr $ "Elm Server " ++ Version.showVersion version ++ " serving Elm " ++ elmVer
  putStrLn "Just refresh a page to recompile it!"
  httpServe (setPort (port cargs) config) $
      serveRuntime (maybe Elm.runtime id (runtime cargs))
      <|> serveElm
      <|> route [ ("debug", debug)
                , ("socket", socket)
                , ("debug.png", serveAsset "resources/debug.png")
                , ("elm-debugger.html", serveAsset "resources/elm-debugger.html")
                ]
      <|> serveDirectoryWith simpleDirectoryConfig "resources"
      <|> serveDirectoryWith simpleDirectoryConfig "build"
      <|> serveDirectoryWith directoryConfig "."
      <|> error404

directoryConfig :: MonadSnap m => DirectoryConfig m
directoryConfig = fancyDirectoryConfig {indexGenerator = elmIndexGenerator}

runtimeName :: String
runtimeName = "elm-runtime.js"

serveRuntime :: FilePath -> Snap ()
serveRuntime runtimePath =
  do file <- BSC.unpack . rqPathInfo <$> getRequest
     guard (file == runtimeName)
     serveFileAs "application/javascript" runtimePath

socket :: Snap ()
socket = WSS.runWebSocketsSnap Socket.fileChangeApp

debug :: Snap()
debug = withFile Debugger.ide 

withFile :: (FilePath -> H.Html) -> Snap ()
withFile handler = do
  filePath <- BSC.unpack . rqPathInfo <$> getRequest
  exists <- liftIO (doesFileExist filePath)
  if not exists then error404 else
      serveHtml $ handler filePath

error404 :: Snap ()
error404 =
    do errorPath <- liftIO $ getDataFileName "resources/Error404.elm"
       serveFileAs "text/html; charset=UTF-8" errorPath
       modifyResponse $ setResponseStatus 404 "Not Found"

serveHtml :: MonadSnap m => H.Html -> m ()
serveHtml html =
    do _ <- setContentType "text/html" <$> getResponse
       writeLBS (BlazeBS.renderHtml html)

serveElm :: Snap ()
serveElm =
  do file <- BSC.unpack . rqPathInfo <$> getRequest
     exists <- liftIO $ doesFileExist file
     guard (exists && takeExtension file == ".elm")
     result <- liftIO $ Generate.html file
     serveHtml result

serveAsset :: String -> Snap ()
serveAsset assetPath =
  do dataPath <- liftIO $ getDataFileName assetPath
     serveFile dataPath
