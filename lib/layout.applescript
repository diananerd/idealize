-- lib/layout.applescript
-- Usage: osascript layout.applescript <project_dir> <lib_dir> <broot_conf> <agent_cmd> <shrink_count> <resize_step> <broot_socket> [env_prefix]

on run argv
    set projectDir to item 1 of argv
    set libDir to item 2 of argv
    set brootConf to item 3 of argv
    set agentCmd to item 4 of argv
    set shrinkCount to (item 5 of argv) as integer
    set resizeStep to (item 6 of argv) as integer
    set brootSocket to item 7 of argv
    set envPrefix to ""
    if (count of argv) > 7 then
        set envPrefix to item 8 of argv
    end if

    tell application "Ghostty"
        activate

        set cfg to new surface configuration
        set initial working directory of cfg to projectDir

        if agentCmd is not "no-agent" then
            -- 3-pane: tree | viewer | agent
            set win to new window with configuration cfg
            set agentTerminal to terminal 1 of selected tab of win

            set viewerTerminal to split agentTerminal direction left with configuration cfg
            set treeTerminal to split viewerTerminal direction left with configuration cfg

            perform action "equalize_splits" on treeTerminal

            repeat shrinkCount times
                perform action ("resize_split:left," & resizeStep) on treeTerminal
            end repeat

            set treeId to id of treeTerminal
            set viewerId to id of viewerTerminal
            set agentId to id of agentTerminal
            set winId to id of win

            input text "broot --conf " & brootConf & " --listen " & brootSocket & " " & projectDir & "\n" to treeTerminal
            input text envPrefix & libDir & "/viewer-loop.sh " & projectDir & "\n" to viewerTerminal
            input text agentCmd & "\n" to agentTerminal

            return "{\"window_id\":\"" & (winId as text) & "\",\"tree_id\":\"" & (treeId as text) & "\",\"viewer_id\":\"" & (viewerId as text) & "\",\"agent_id\":\"" & (agentId as text) & "\"}"
        else
            -- 2-pane: tree | viewer
            set win to new window with configuration cfg
            set viewerTerminal to terminal 1 of selected tab of win

            set treeTerminal to split viewerTerminal direction left with configuration cfg

            repeat shrinkCount times
                perform action ("resize_split:left," & resizeStep) on treeTerminal
            end repeat

            set treeId to id of treeTerminal
            set viewerId to id of viewerTerminal
            set winId to id of win

            input text "broot --conf " & brootConf & " --listen " & brootSocket & " " & projectDir & "\n" to treeTerminal
            input text envPrefix & libDir & "/viewer-loop.sh " & projectDir & "\n" to viewerTerminal

            return "{\"window_id\":\"" & (winId as text) & "\",\"tree_id\":\"" & (treeId as text) & "\",\"viewer_id\":\"" & (viewerId as text) & "\",\"agent_id\":\"\"}"
        end if
    end tell
end run
