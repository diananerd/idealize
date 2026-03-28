-- lib/layout.applescript
-- Usage: osascript lib/layout.applescript <project_dir> <idealyze_lib_dir> <broot_conf_path> [no-claude]
-- Outputs: JSON with terminal IDs for session.json
--
-- Layout: tree | viewer [| claude]
-- Strategy: split left from initial pane, then resize tree.

on run argv
    set projectDir to item 1 of argv
    set libDir to item 2 of argv
    set brootConf to item 3 of argv
    set withClaude to true
    if (count of argv) > 3 then
        if item 4 of argv is "no-claude" then
            set withClaude to false
        end if
    end if

    tell application "Ghostty"
        activate

        set cfg to new surface configuration
        set initial working directory of cfg to projectDir

        if withClaude then
            -- 3-pane: tree | viewer | claude
            set win to new window with configuration cfg
            set claudeTerminal to terminal 1 of selected tab of win

            set viewerTerminal to split claudeTerminal direction left with configuration cfg
            set treeTerminal to split viewerTerminal direction left with configuration cfg

            perform action "equalize_splits" on treeTerminal

            repeat 13 times
                perform action "resize_split:left,10" on treeTerminal
            end repeat

            set treeId to id of treeTerminal
            set viewerId to id of viewerTerminal
            set claudeId to id of claudeTerminal
            set winId to id of win

            input text "broot --conf " & brootConf & " --listen idealyze " & projectDir & "\n" to treeTerminal
            input text libDir & "/viewer-loop.sh " & projectDir & "\n" to viewerTerminal
            input text "claude\n" to claudeTerminal

            return "{\"window_id\":\"" & (winId as text) & "\",\"tree_id\":\"" & (treeId as text) & "\",\"viewer_id\":\"" & (viewerId as text) & "\",\"claude_id\":\"" & (claudeId as text) & "\"}"
        else
            -- 2-pane: tree | viewer (viewer gets all remaining space)
            set win to new window with configuration cfg
            set viewerTerminal to terminal 1 of selected tab of win

            set treeTerminal to split viewerTerminal direction left with configuration cfg

            -- Shrink tree: split starts at 50/50, shrink to sidebar
            repeat 30 times
                perform action "resize_split:left,10" on treeTerminal
            end repeat

            set treeId to id of treeTerminal
            set viewerId to id of viewerTerminal
            set winId to id of win

            input text "broot --conf " & brootConf & " --listen idealyze " & projectDir & "\n" to treeTerminal
            input text libDir & "/viewer-loop.sh " & projectDir & "\n" to viewerTerminal

            return "{\"window_id\":\"" & (winId as text) & "\",\"tree_id\":\"" & (treeId as text) & "\",\"viewer_id\":\"" & (viewerId as text) & "\",\"claude_id\":\"\"}"
        end if
    end tell
end run
