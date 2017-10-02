{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE CPP                 #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TupleSections       #-}

module Main
       ( main
       ) where

import           Universum

import           Data.Maybe           (fromJust)
import           Formatting           (sformat, shown, (%))
import           Mockable             (Production, currentTime, runProduction)
import           System.Wlog          (logInfo)

import           NodeOptions          (ExplorerArgs (..), ExplorerNodeArgs (..),
                                       getExplorerNodeOptions)
import           Pos.Binary           ()
import           Pos.Client.CLI       (CommonNodeArgs (..), NodeArgs (..), getNodeParams)
import qualified Pos.Client.CLI       as CLI
import           Pos.Communication    (OutSpecs, WorkerSpec)
import           Pos.Core             (gdStartTime, genesisData)
import           Pos.Explorer         (runExplorerBListener)
import           Pos.Explorer.Socket  (NotifierSettings (..))
import           Pos.Explorer.Web     (ExplorerProd, explorerPlugin, notifierPlugin)
import           Pos.Launcher         (ConfigurationOptions (..), HasConfigurations,
                                       NodeParams (..), NodeResources (..),
                                       bracketNodeResources, hoistNodeResources, runNode,
                                       runRealBasedMode, withConfigurations)
import           Pos.Ssc.GodTossing   (SscGodTossing)
import           Pos.Ssc.SscAlgo      (SscAlgo (..))
import           Pos.Types            (Timestamp (Timestamp))
import           Pos.Update           (updateTriggerWorker)
import           Pos.Util             (mconcatPair)
import           Pos.Util.CompileInfo (HasCompileInfo, retrieveCompileTimeInfo,
                                       withCompileInfo)
import           Pos.Util.UserSecret  (usVss)

----------------------------------------------------------------------------
-- Main action
----------------------------------------------------------------------------

main :: IO ()
main = do
    args <- getExplorerNodeOptions
    CLI.printFlags
    putText "[Attention] Software is built with explorer part"
    runProduction $ action args

action :: ExplorerNodeArgs -> Production ()
action (ExplorerNodeArgs (cArgs@CommonNodeArgs{..}) ExplorerArgs{..}) =
    withConfigurations conf $
    withCompileInfo $(retrieveCompileTimeInfo) $ do
        let systemStart = gdStartTime genesisData
        logInfo $ sformat ("System start time is " % shown) systemStart
        t <- currentTime
        logInfo $ sformat ("Current time is " % shown) (Timestamp t)
        currentParams <- getNodeParams cArgs nodeArgs
        putText $ "Explorer is enabled!"
        logInfo $ sformat ("Using configs and genesis:\n"%shown) conf

        let vssSK = fromJust $ npUserSecret currentParams ^. usVss
        let gtParams = CLI.gtSscParams cArgs vssSK (npBehaviorConfig currentParams)

        let plugins :: HasConfigurations => ([WorkerSpec ExplorerProd], OutSpecs)
            plugins = mconcatPair
                [ explorerPlugin webPort
                , notifierPlugin NotifierSettings{ nsPort = notifierPort }
                , updateTriggerWorker
                ]

        bracketNodeResources currentParams gtParams $ \nr@NodeResources {..} ->
            runExplorerRealMode
                (hoistNodeResources (lift . runExplorerBListener) nr)
                (runNode @SscGodTossing nr plugins)
  where

    conf :: ConfigurationOptions
    conf = CLI.configurationOptions $ CLI.commonArgs cArgs

    runExplorerRealMode
        :: (HasConfigurations,HasCompileInfo)
        => NodeResources SscGodTossing ExplorerProd
        -> (WorkerSpec ExplorerProd, OutSpecs)
        -> Production ()
    runExplorerRealMode = runRealBasedMode runExplorerBListener lift

    nodeArgs :: NodeArgs
    nodeArgs = NodeArgs { sscAlgo = GodTossingAlgo, behaviorConfigPath = Nothing }
