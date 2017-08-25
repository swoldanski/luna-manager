{-# LANGUAGE CPP #-}

module Luna.Manager.System.Env where

import Prologue hiding (FilePath, fromText, toText)

import           Luna.Manager.System.Host
import qualified Luna.Manager.Shell.Shelly as Shelly
import           Luna.Manager.Shell.Shelly (MonadSh)
import           Filesystem.Path.CurrentOS
import           Control.Monad.State.Layered
import qualified System.Directory as System
import           Control.Monad.Raise
import           System.IO.Error

--------------------------
-- === EnvConfig === --
--------------------------

-- === Definition === --

data EnvConfig = EnvConfig { _localTempPath :: FilePath
                           }
makeLenses ''EnvConfig


-- === Utils === --

getHomePath :: MonadIO m => m FilePath
getHomePath = do
    home <- liftIO $ System.getHomeDirectory
    return $ fromText $ convert home

getCurrentPath :: MonadIO m => m FilePath
getCurrentPath = do
    current <- liftIO $ System.getCurrentDirectory
    return $ fromText $ convert current

getTmpPath, getDownloadPath :: (MonadIO m, MonadGetter EnvConfig m, MonadSh m) => m FilePath
getDownloadPath = getTmpPath
getTmpPath      = do
    tmp <- view localTempPath <$> get @EnvConfig
    Shelly.mkdir_p tmp
    return tmp


setTmpCwd :: (MonadGetter EnvConfig m, MonadIO m, MonadSh m) => m ()
setTmpCwd = liftIO . System.setCurrentDirectory . encodeString =<< getTmpPath

createSymLink ::  MonadIO m => FilePath -> FilePath -> m ()
createSymLink src dst = liftIO $  (System.createFileLink (encodeString src) (encodeString dst)) `catch` handler src dst where
    --TODO[SB->WD]: Can we do it nicer - to check if it already exist (not the target!)
    handler :: FilePath -> FilePath -> SomeException -> IO ()
    handler src dst ex = case ex of
        isAlreadyExistsError -> do
            System.removeFile $ encodeString dst
            createSymLink src dst
        otherwise -> return ()

createSymLinkDirectory ::  MonadIO m => FilePath -> FilePath -> m ()
createSymLinkDirectory src dst = liftIO $ (System.createDirectoryLink (encodeString src) (encodeString dst)) `catch` handler src dst where
    handler :: FilePath -> FilePath -> SomeException -> IO ()
    handler src dst ex = case ex of
        isAlreadyExistsError -> do
            System.removeDirectoryLink $ encodeString dst
            createSymLinkDirectory src dst
        otherwise -> return ()

copyDir :: Shelly.MonadSh m => FilePath -> FilePath -> m ()-- copy the content of the source directory
copyDir src dst = do
    isDir <- Shelly.test_d src
    if isDir then do
        listedDirectory <- Shelly.ls src
        mapM_ (flip Shelly.cp_r dst) listedDirectory
    else Shelly.cp src dst


-- === Instances === --

instance {-# OVERLAPPABLE #-} MonadIO m => MonadHostConfig EnvConfig sys arch m where
    defaultHostConfig = EnvConfig <$> tmp where
        tmp = (</> "luna") <$> decodeString <$> liftIO System.getTemporaryDirectory

instance {-# OVERLAPPABLE #-} MonadIO m => MonadHostConfig EnvConfig 'Windows arch m where
    -- | Too long paths are often problem on Windows, therefore we use C:\tmp to store temporary data
    defaultHostConfig = return $ EnvConfig "C:\\tmp\\luna"