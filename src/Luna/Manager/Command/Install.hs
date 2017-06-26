module Luna.Manager.Command.Install where

import Prologue hiding (txt, FilePath, toText, fromText)

import Luna.Manager.System.Host
import Luna.Manager.System.Env
import Luna.Manager.Component.Repository as Repo
import Luna.Manager.Component.Version
import Luna.Manager.Network
import Luna.Manager.Component.Pretty
import Luna.Manager.Shell.Question
import           Luna.Manager.Command.Options (InstallOpts)
import qualified Luna.Manager.Command.Options as Opts
import Luna.Manager.System.Path
import Luna.Manager.System (makeExecutable, exportPath, checkShell)

import Control.Lens.Aeson
import Control.Monad.Raise
import Control.Monad.State.Layered

import qualified Data.Map as Map

import qualified Data.Yaml as Yaml

import Filesystem.Path.CurrentOS (FilePath, (</>), encodeString, toText, fromText)
import Shelly.Lifted (toTextIgnore)


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

instance Monad m => MonadHostConfig InstallConfig 'Linux arch m where
    defaultHostConfig = return $ InstallConfig
        { _execName        = "luna-studio"
        , _defaultConfPath = "~/.luna"
        , _defaultBinPath  = "~/.luna-bin" --TODO jak tylko bedzie poprawne expandowanie tyldy to przywrócic stara wersje
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

-- === Errors === --

newtype UnresolvedDepsError = UnresolvedDepsError [PackageHeader] deriving (Show)
makeLenses ''UnresolvedDepsError

instance Exception UnresolvedDepsError where
    displayException err = "Following dependencies were unable to be resolved: " <> show (showPretty <$> unwrap err)


-- === Running === --

type MonadInstall m = (MonadStates '[EnvConfig, InstallConfig, RepoConfig] m, MonadNetwork m)

runInstaller :: MonadInstall m => InstallOpts -> m ()
runInstaller opts = do
    repo <- getRepo

    (appName, appPkg) <- askOrUse (opts ^. Opts.selectedComponent)
        $ question "Select component to be installed" (\t -> choiceValidator' "component" t $ (t,) <$> Map.lookup t (repo ^. apps))
        & help   .~ choiceHelp "components" (Map.keys $ repo ^. apps)
        & defArg .~ Just (repo ^. defaultApp)

    let vmap = Map.mapMaybe (Map.lookup currentSysDesc) $ appPkg ^. versions
        vss  = sort . Map.keys $ vmap
    (appVersion, appPkgDesc) <- askOrUse (opts ^. Opts.selectedVersion)
        $ question "Select version to be installed" (\t -> choiceValidator "version" t . sequence $ fmap (t,) . flip Map.lookup vmap <$> readPretty t)
        & help   .~ choiceHelp (appName <> " versions") vss
        & defArg .~ fmap showPretty (maybeLast vss)

    let (unresolvedLibs, libsToInstall) = Repo.resolve repo appPkgDesc
    when (not $ null unresolvedLibs) . raise' $ UnresolvedDepsError unresolvedLibs

    installConfig <- get @InstallConfig
    appPath <- askOrUse (opts ^. Opts.selectedInstallationPath)
        $ question "Select installation path" plainTextReader
        & defArg .~ Just (toTextIgnore (installConfig ^. defaultBinPath)) --TODO uzyć toText i złapać tryRight'

    print $ "TODO: Install the app (with progress bar): "  <> appName

    let pkgPath = appPkgDesc ^. path

    case currentHost of
        Linux   -> do
            --TODO expand '~'
            home <- getHomePath
            installPath <- expand $ (fromText appPath) </> (fromText appName) </> (fromText appVersion)
            createDirIfMissingTrue installPath
            appimage <- downloadWithProgressBar pkgPath installPath
            makeExecutable appimage
            exec <- view execName <$> get @InstallConfig
            currentAppimage <- expand $ (fromText appPath) </> (fromText exec)
            let localBinDir = home </> ".local/bin"
                localBin = home </> ".local/bin" </> (fromText exec)
            createDirIfMissingTrue localBinDir
            createSymLink appimage currentAppimage
            createSymLink currentAppimage localBin
            shell <- checkShell
            exportPath localBinDir shell
        Darwin  ->return ()
        Windows ->return ()


    print $ "TODO: Install the libs (each with separate progress bar): " <> show libsToInstall -- w ogóle nie supportujemy przeciez instalowania osobnych komponentów i libów
    print $ "TODO: Add new exports to bashRC if not already present"
    print $ "TODO: IMPORTANT: be sure that installation of manager updates the manager in-place"
    -- TODO: powinnismy zrobic funckje "installPackage" i przemapowac ja przez app i libsToInstall
    --       i to powinien byc koniec "instalacji" - potem jeszcze dopisywanie do shelli sciezek etc


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

-- installPackageLinux :: MonadInstall m => Text -> Text -> Text -> m ()
-- installPackageLinux appPath appName appVersion = do
--     let fullLocation = appPath </> appName </> appVersion -- pełna ścieżka dla naszego
--     createDir fullLocation
--     -- setCurrentDir fullLocation
--     pkgPath <- view path <$> get @PackageDesc
--     downloadWithProgressBar pkgPath
--     appimage <- takeFileNameFromURL pkgPath
--     makeExecutable $ fullLocation </> appimage
--     let appimageToBinName = appPath </> execName
--         home = getHomePath
--         binPath = home </> (convert ".local/bin") </> execName
--     -- createSymLink appimage appimageToBinName
--     createSymLink appimageToBinName binPath
