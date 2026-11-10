# HIKARI Production Hub guard hook (keep this file ASCII-only: Windows PowerShell 5.1 reads
# BOM-less scripts in the system code page; all user-facing text lives in hub-messages.json).
#
#   session : SessionStart - tells the agent this repository is a hub project and what to do first.
#   edit    : PreToolUse (Edit / Write / MultiEdit / NotebookEdit) - no card, no edit; no edits on the
#             base branch; protected files and files outside the card's scope need the human's OK.
#
# The guard fails open: if the hook itself breaks, work is not blocked.
param([string]$Mode = "edit")

$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Out([string]$text) {
    $bytes = $utf8.GetBytes($text)
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
}

function Read-Json([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return [IO.File]::ReadAllText($path, $utf8) | ConvertFrom-Json
}

# Walks up from $start to the folder that holds .hikari-hub.toml.
function Find-HubRoot([string]$start) {
    $dir = $start
    while ($dir) {
        if (Test-Path -LiteralPath (Join-Path $dir ".hikari-hub.toml")) { return $dir }
        $parent = Split-Path -Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { return $null }
        $dir = $parent
    }
    return $null
}

# Current branch read from .git (no git process): handles a normal checkout and a worktree.
function Get-Branch([string]$root) {
    $git = Join-Path $root ".git"
    if (-not (Test-Path -LiteralPath $git)) { return "" }
    if (-not (Test-Path -LiteralPath $git -PathType Container)) {
        $pointer = [IO.File]::ReadAllText($git, $utf8)
        if ($pointer -notmatch 'gitdir:\s*(.+)') { return "" }
        $git = $Matches[1].Trim()
        if (-not [IO.Path]::IsPathRooted($git)) { $git = Join-Path $root $git }
    }
    $head = Join-Path $git "HEAD"
    if (-not (Test-Path -LiteralPath $head)) { return "" }
    if ([IO.File]::ReadAllText($head, $utf8) -match 'ref:\s*refs/heads/(\S+)') { return $Matches[1] }
    return ""
}

# A pattern is a file, a folder ("Assets/Scenes/" or "Assets/Scenes"), or a wildcard ("*.psd").
function Test-PathMatch([string]$rel, $patterns) {
    foreach ($pattern in @($patterns)) {
        if (-not $pattern) { continue }
        $p = ([string]$pattern).Trim().Replace("\", "/") -replace '^\./', ''
        if (-not $p) { continue }
        if ($p.Contains("*")) {
            if ($rel -like $p) { return $true }
        } elseif ($p.EndsWith("/")) {
            if ($rel.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        } elseif ($rel -ieq $p -or $rel.StartsWith($p + "/", [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Send-Decision([string]$decision, [string]$reason) {
    $out = @{ hookSpecificOutput = @{ hookEventName = "PreToolUse"; permissionDecision = $decision; permissionDecisionReason = $reason } }
    Write-Out ($out | ConvertTo-Json -Depth 4 -Compress)
    exit 0
}

try {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $utf8)
    $raw = $reader.ReadToEnd()
    $event = $null
    if ($raw.Trim()) { $event = $raw | ConvertFrom-Json }
    $msg = Read-Json (Join-Path $PSScriptRoot "hub-messages.json")
    if (-not $msg) { exit 0 }

    if ($Mode -eq "session") {
        $start = (Get-Location).Path
        if ($event -and $event.cwd) { $start = [string]$event.cwd }
        $root = Find-HubRoot $start
        if (-not $root) { exit 0 }
        $name = ""
        if ([IO.File]::ReadAllText((Join-Path $root ".hikari-hub.toml"), $utf8) -match 'name\s*=\s*"([^"]*)"') { $name = $Matches[1] }
        $active = Read-Json (Join-Path $root ".hikari-hub/active.json")
        if ($active -and $active.card) {
            Write-Out ($msg.session_active -f $name, [string]$active.title, [string]$active.branch)
        } else {
            Write-Out ($msg.session_idle -f $name)
        }
        exit 0
    }

    if (-not $event -or -not $event.tool_input) { exit 0 }
    $file = [string]$event.tool_input.file_path
    if (-not $file) { $file = [string]$event.tool_input.notebook_path }
    if (-not $file) { exit 0 }
    $root = Find-HubRoot (Split-Path -Path $file -Parent)
    if (-not $root) { exit 0 }
    $rel = $file.Substring($root.Length).TrimStart('\', '/').Replace("\", "/")
    # The agent's own working files (cache, active card, pending notes) are always writable.
    if ($rel.StartsWith(".hikari-hub/", [StringComparison]::OrdinalIgnoreCase)) { exit 0 }

    $project = Read-Json (Join-Path $root ".hikari-hub/cache/settings/project.json")
    if (-not $project) { Send-Decision "deny" $msg.no_sync }

    $requireCard = $true
    if ($null -ne $project.require_card) { $requireCard = [bool]$project.require_card }
    $active = Read-Json (Join-Path $root ".hikari-hub/active.json")
    $hasCard = [bool]($active -and $active.card)

    if ($requireCard) {
        if (-not $hasCard) { Send-Decision "deny" $msg.no_card }
        $base = "main"
        if ($project.base_branch) { $base = [string]$project.base_branch }
        $branch = Get-Branch $root
        if ($branch -and $branch -eq $base) { Send-Decision "deny" ($msg.on_base -f $base, [string]$active.branch) }
    }
    if (Test-PathMatch $rel $project.protected_paths) { Send-Decision "ask" ($msg.protected -f $rel) }
    if ($hasCard -and $active.paths -and @($active.paths).Count -gt 0 -and -not (Test-PathMatch $rel $active.paths)) {
        Send-Decision "ask" ($msg.out_of_scope -f $rel, [string]$active.title)
    }
    exit 0
} catch {
    [Console]::Error.WriteLine("hub-hook: " + $_.Exception.Message)
    exit 0
}
