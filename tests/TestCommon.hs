{-# language PartialTypeSignatures #-}

module TestCommon where

import           GHC.Err                        ( errorWithoutStackTrace )
import           Control.Monad.Catch
import           Data.Time
import           Data.Text.IO as Text
import           Nix
import           Nix.Standard
import           Nix.Fresh.Basic
import           System.Environment
import           System.IO
import           System.PosixCompat.Files
import           System.PosixCompat.Temp
import           System.Process
import           Test.Tasty.HUnit

hnixEvalFile :: Options -> Path -> IO (StdValue (StandardT (StdIdT IO)))
hnixEvalFile opts file =
  do
    parseResult <- parseNixFileLoc file
    either
      (\ err -> fail $ "Parsing failed for file `" <> coerce file <> "`.\n" <> show err)
      (\ expr ->
        do
          setEnv "TEST_VAR" "foo"
          runWithBasicEffects opts $
            catch (evaluateExpression (pure $ coerce file) nixEvalExprLoc normalForm expr) $
            \case
              NixException frames ->
                errorWithoutStackTrace . show
                  =<< renderFrames
                        @(StdValue (StandardT (StdIdT IO)))
                        @(StdThunk (StandardT (StdIdT IO)))
                        frames
      )
      parseResult

hnixEvalText :: Options -> Text -> IO (StdValue (StandardT (StdIdT IO)))
hnixEvalText opts src =
  either
    (\ err -> fail $ toString $ "Parsing failed for expression `" <> src <> "`.\n" <> show err)
    (\ expr ->
      runWithBasicEffects opts $ normalForm =<< nixEvalExpr mempty expr
    )
    (parseNixText src)

nixEvalString :: Text -> IO Text
nixEvalString expr =
  do
    (coerce -> fp, h) <- mkstemp "nix-test-eval"
    Text.hPutStr h expr
    hClose h
    res <- nixEvalFile fp
    removeLink $ coerce fp
    pure res

nixEvalFile :: Path -> IO Text
nixEvalFile fp = fromString <$> readProcess "nix-instantiate" ["--eval", "--strict", coerce fp] mempty

assertEvalFileMatchesNix :: Path -> Assertion
assertEvalFileMatchesNix fp =
  do
    time    <- liftIO getCurrentTime
    hnixVal <- (<> "\n") . printNix <$> hnixEvalFile (defaultOptions time) fp
    nixVal  <- nixEvalFile fp
    assertEqual (coerce fp) nixVal hnixVal

assertEvalMatchesNix :: Text -> Assertion
assertEvalMatchesNix expr =
  do
    time    <- liftIO getCurrentTime
    hnixVal <- (<> "\n") . printNix <$> hnixEvalText (defaultOptions time) expr
    nixVal  <- nixEvalString expr
    assertEqual (toString expr) nixVal hnixVal
