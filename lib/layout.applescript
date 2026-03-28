-- lib/layout.applescript
-- Usage: osascript lib/layout.applescript <project_dir> <lib_dir> <broot_conf> [no-agent|agent_cmd]
-- Outputs: JSON with terminal IDs for session.json
--
-- Layout: tree | viewer [| agent]
-- Strategy: split left from initial pane, then resize tree.

on run argv
    set projectDir to item 1 of argv
    set libDir to item 2 of argv
    set brootConf to item 3 of argv
    set agentCmd to ""
    if (count of argv) > 3 then
        if item 4 of argv is "no-agent" then
            set agentCmd to ""
        else
            set agentCmd to item 4 of argv
        end if
    end if

    tell application "Ghostty"
        activate

        set cfg to new surface configuration
        set initial working directory of cfg to projectDir

        if agentCmd is not "" then
            -- 3-pane: tree | viewer | agent
            set win to new window with configuration cfg
            set agentTerminal to terminal 1 of selected tab of win

            -- Disable close confirmation for all panes in this window
            perform action "config:confirm-close-surface=false" on agentTerminal

            set viewerTerminal to split agentTerminal direction left with configuration cfg
            set treeTerminal to split viewerTerminal direction left with configuration cfg

            perform action "equalize_splits" on treeTerminal

            repeat 13 times
                perform action "resize_split:left,10" on treeTerminal
            end repeat

            set treeId to id of treeTerminal
            set viewerId to id of viewerTerminal
            set agentId to id of agentTerminal
            set winId to id of win

            input text "broot --conf " & brootConf & " --listen idealyze " & projectDir & "\n" to treeTerminal
            input text libDir & "/viewer-loop.sh " & projectDir & "\n" to viewerTerminal
            input text agentCmd & "\n" to agentTerminal

            return "{\"window_id\":\"" & (winId as text) & "\",\"tree_id\":\"" & (treeId as text) & "\",\"viewer_id\":\"" & (viewerId as text) & "\",\"agent_id\":\"" & (agentId as text) & "\"}"
        else
            -- 2-pane: tree | viewer
            set win to new window with configuration cfg
            set viewerTerminal to terminal 1 of selected tab of win

            -- Disable close confirmation for all panes in this window
            perform action "config:confirm-close-surface=false" on viewerTerminal

            set treeTerminal to split viewerTerminal direction left with configuration cfg

            repeat 30 times
                perform action "resize_split:left,10" on treeTerminal
            end repeat

            set treeId to id of treeTerminal
            set viewerId to id of viewerTerminal
            set winId to id of win

            input text "broot --conf " & brootConf & " --listen idealyze " & projectDir & "\n" to treeTerminal
            input text libDir & "/viewer-loop.sh " & projectDir & "\n" to viewerTerminal

            return "{\"window_id\":\"" & (winId as text) & "\",\"tree_id\":\"" & (treeId as text) & "\",\"viewer_id\":\"" & (viewerId as text) & "\",\"agent_id\":\"\"}"
        end if
    end tell
end run
