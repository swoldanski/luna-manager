module Luna.Manager.Command.Install where

import Prologue hiding (txt)

import Luna.Manager.System.Host
import Luna.Manager.System.Env
import Luna.Manager.Component.Repository
import Luna.Manager.Component.Version
import Luna.Manager.Network
import Luna.Manager.Component.Pretty
import Luna.Manager.Shell.Question
import           Luna.Manager.Command.Options (InstallOpts)
import qualified Luna.Manager.Command.Options as Opts

import Control.Lens.Aeson
import Control.Monad.Raise
import Control.Monad.State.Layered

import qualified Data.Map as Map


-- FIXME FIXME FIXME FIXME FIXME FIXME FIXME FIXME FIXME FIXME FIXME
-- FIXME: Remove it as fast as we upload config yaml to the server
hardcodedRepo :: Repo
hardcodedRepo = Repo defapps deflibs "studio" where
    deflibs = mempty
    defapps = mempty & at "studio"   .~ Just (Package "studio synopsis"   $ fromList [ (Version 1 0 0 (Just $ RC 5), fromList [(SysDesc Linux X64, PackageDesc [PackageDep "bar" (Version 1 0 0 (Just $ RC 5))] $ "foo")] )
                                                                                     , (Version 1 0 0 (Just $ RC 6), fromList [(SysDesc Linux X64, PackageDesc [PackageDep "bar" (Version 1 0 0 (Just $ RC 5))] $ "foo")] )
                                                                                     , (Version 1 1 0 Nothing      , fromList [(SysDesc Linux X64, PackageDesc [PackageDep "bar" (Version 1 0 0 (Just $ RC 5))] $ "foo")] )
                                                                                     ])

                     & at "compiler" .~ Just (Package "compiler synopsis" $ fromList [(Version 1 0 0 (Just $ RC 5), fromList [(SysDesc Linux X64, PackageDesc [PackageDep "bar" (Version 1 0 0 (Just $ RC 5))] $ "foo")] )])
                     & at "manager"  .~ Just (Package "manager synopsis"  $ fromList [(Version 1 0 0 (Just $ RC 5), fromList [(SysDesc Linux X64, PackageDesc [PackageDep "bar" (Version 1 0 0 (Just $ RC 5))] $ "foo")] )])




---------------------------------
-- === Installation config === --
---------------------------------

-- === Definition === --

data InstallConfig = InstallConfig { _execName        :: Text
                                   , _defaultConfPath :: FilePath
                                   , _defaultBinPath  :: FilePath
                                   , _localName       :: Text
                                   }
makeLenses ''InstallConfig


-- === Instances === --

instance {-# OVERLAPPABLE #-} Monad m => MonadHostConfig InstallConfig sys arch m where
    defaultHostConfig = return $ InstallConfig
        { _execName        = "luna-studio"
        , _defaultConfPath = "~/.luna"
        , _defaultBinPath  = "~/.luna-bin"
        , _localName       = "local"
        }

instance Monad m => MonadHostConfig InstallConfig 'Darwin arch m where
    defaultHostConfig = reconfig <$> defaultHostConfigFor @Linux where
        reconfig cfg = cfg & execName       .~ "LunaStudio"
                           & defaultBinPath .~ "~/Applications"

instance Monad m => MonadHostConfig InstallConfig 'Windows arch m where
    defaultHostConfig = reconfig <$> defaultHostConfigFor @Linux where
        reconfig cfg = cfg & execName       .~ "LunaStudio"
                           & defaultBinPath .~ "C:\\ProgramFiles"



-----------------------
-- === Installer === --
-----------------------

-- === Running === --

type MonadInstall m = (MonadStates '[EnvConfig, InstallConfig, RepoConfig] m, MonadNetwork m)

runInstaller :: MonadInstall m => InstallOpts -> m ()
runInstaller opts = do
    let repo = hardcodedRepo
    -- repo <- getRepo -- FIXME[WD]: this should be enabled instead of line above

    (appName, appPkg) <- askOrUse (opts ^. Opts.selectedComponent)
        $ question "Select component to be installed" (\t -> choiceValidator' "component" t $ (t,) <$> Map.lookup t (repo ^. apps))
        & help   .~ choiceHelp "components" (Map.keys $ repo ^. apps)
        & defArg .~ Just (repo ^. defaultApp)

    let vmap = Map.mapMaybe (Map.lookup currentSysDesc) $ appPkg ^. versions
        vss  = sort . Map.keys $ vmap
    (appVersion, appPkgDesc) <- askOrUse (opts ^. Opts.selectedComponent)
        $ question "Select version to be installed" (\t -> choiceValidator "version" t . sequence $ fmap (t,) . flip Map.lookup vmap <$> readPretty t)
        & help   .~ choiceHelp (appName <> " versions") vss
        & defArg .~ fmap showPretty (maybeLast vss)



    --   allLunaIds = map Main.id lunaVersions
    --   lastLunaId = maximum allLunaIds
    -- absDefault       <- mkPathWithHome [defaultInstallFolderName]
    -- location         <- ask (Text.pack "Where to install Luna-Studio?") (Text.pack absDefault) -- defaultBinPath
    --
    -- let address = mapM (getAddress versionToinstall) lunaVersions -- dla konkretnej wersji
    --   justAddressesList = failIfNothing "cannot read URI" address
    --   justAddress = failIfNothing "cannot read URI" $ listToMaybe justAddressesList
    -- --installation
    -- locWithVersion <- mkPathWithHome [location, (Text.pack $ show versionToinstall)]
    -- createDirectory locWithVersion
    -- setCurrentDirectory locWithVersion
    -- downloadWithProgressBar justAddress
    -- let name = fromMaybe "cannot read URI" $ takeFileName justAddress
    -- appimage <- mkRelativePath [(Text.pack locWithVersion), name]
    -- makeExecutable appimage
    -- appimageToLunaStudio <- mkRelativePath [location, studioName]
    -- binPath <- mkPathWithHome [".local/bin", studioName]
    -- createFileLink appimage appimageToLunaStudio
    -- createFileLink appimageToLunaStudio binPath
    -- checkShell
    return ()