module Luna.Manager.Shell.Commands where

import Prologue hiding (FilePath)

import Control.Monad.Raise
import Control.Monad.State.Layered

import qualified Luna.Manager.Shell.Shelly as Shelly
import           Luna.Manager.Shell.Shelly (MonadSh)
import qualified Data.Text as Text
default (Text.Text)

newtype CmdError = CmdError Text deriving (Show)
instance Exception CmdError where
    displayException (CmdError t) = convert $ "External command error: " <> t


cmdEither :: (MonadSh m, MonadException SomeException m) => Shelly.FilePath -> [Text] -> m (Either CmdError Text)
cmdEither name args = do
    out <- Shelly.run name args
    err <- Shelly.lastStderr
    return $ if err /= "" then Left $ CmdError err
                            else Right out

cmd :: (MonadSh m, MonadException SomeException m) => Shelly.FilePath -> [Text] -> m Text
cmd name args = tryRight' =<< cmdEither name args