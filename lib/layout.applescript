-- lib/layout.applescript
-- Usage: osascript lib/layout.applescript <project_dir> <idealyze_lib_dir> <broot_conf_path>
-- Outputs: JSON with terminal IDs for session.json

on run argv
    set projectDir to item 1 of argv
    set libDir to item 2 of argv
    set brootConf to item 3 of argv

    tell application "Ghostty"
        activate

        -- Create surface config with project working directory
        set cfg to new surface configuration
        set initial working directory of cfg to projectDir

        -- Create main window (this becomes the tree pane)
        set win to new window with configuration cfg

        -- Get reference to the first terminal (will be tree pane)
        set treeTerminal to terminal 1 of selected tab of win

        -- Split right to create the combined center+right area
        set rightArea to split treeTerminal direction right with configuration cfg

        -- rightArea is now the right pane, treeTerminal is the left pane
        -- Split rightArea to create viewer (left of right) and claude (right of right)
        set claudeTerminal to split rightArea direction right with configuration cfg

        -- Now: treeTerminal | rightArea (viewer) | claudeTerminal
        set viewerTerminal to rightArea

        -- Get IDs for session tracking
        set treeId to id of treeTerminal
        set viewerId to id of viewerTerminal
        set claudeId to id of claudeTerminal
        set winId to id of win

        -- Resize: make tree narrow (~18%) using perform action
        -- Note: resize_split amount is in pixels. Repeat to achieve desired proportion.
        -- Shrink tree pane by moving the divider left (in pixel increments)
        repeat 15 times
            perform action "resize_split:left,20" on viewerTerminal
        end repeat

        -- Grow claude pane slightly
        repeat 3 times
            perform action "resize_split:right,20" on claudeTerminal
        end repeat

        -- Launch broot in tree pane (no --force needed; broot auto-cleans stale sockets)
        input text "broot --conf " & brootConf & " --listen idealyze " & projectDir & "\n" to treeTerminal

        -- Launch bat welcome in viewer pane
        input text "clear && echo 'idealize: waiting for claude activity...'\n" to viewerTerminal

        -- Launch claude in claude pane
        input text "claude\n" to claudeTerminal

        -- Output JSON with terminal IDs (id may be integer, coerce to string)
        return "{\"window_id\":\"" & (winId as text) & "\",\"tree_id\":\"" & (treeId as text) & "\",\"viewer_id\":\"" & (viewerId as text) & "\",\"claude_id\":\"" & (claudeId as text) & "\"}"
    end tell
end run
