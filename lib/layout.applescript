-- lib/layout.applescript
-- Usage: osascript lib/layout.applescript <project_dir> <idealyze_lib_dir> <broot_conf_path>
-- Outputs: JSON with terminal IDs for session.json
--
-- Layout: tree | viewer | claude
-- Strategy: split right twice from the initial pane, then resize.
-- Split returns the NEW pane; the original stays in place.

on run argv
    set projectDir to item 1 of argv
    set libDir to item 2 of argv
    set brootConf to item 3 of argv

    tell application "Ghostty"
        activate

        set cfg to new surface configuration
        set initial working directory of cfg to projectDir

        -- Create window → initial pane becomes claude (rightmost)
        set win to new window with configuration cfg
        set claudeTerminal to terminal 1 of selected tab of win

        -- Split left from claude → viewer (middle)
        set viewerTerminal to split claudeTerminal direction left with configuration cfg

        -- Split left from viewer → tree (leftmost)
        set treeTerminal to split viewerTerminal direction left with configuration cfg

        -- Layout: treeTerminal | viewerTerminal | claudeTerminal
        -- Equalize all splits first
        perform action "equalize_splits" on treeTerminal

        -- Shrink tree to sidebar width
        repeat 13 times
            perform action "resize_split:left,10" on treeTerminal
        end repeat

        -- Get IDs after all splits and resizing
        set treeId to id of treeTerminal
        set viewerId to id of viewerTerminal
        set claudeId to id of claudeTerminal
        set winId to id of win

        -- Launch broot in tree pane
        input text "broot --conf " & brootConf & " --listen idealyze " & projectDir & "\n" to treeTerminal

        -- Launch viewer loop (handles resize + command updates)
        input text libDir & "/viewer-loop.sh " & projectDir & "\n" to viewerTerminal

        -- Launch claude in claude pane
        input text "claude\n" to claudeTerminal

        return "{\"window_id\":\"" & (winId as text) & "\",\"tree_id\":\"" & (treeId as text) & "\",\"viewer_id\":\"" & (viewerId as text) & "\",\"claude_id\":\"" & (claudeId as text) & "\"}"
    end tell
end run
