# HIKARI Production Hub guard hook (keep this file ASCII-only: Windows PowerShell 5.1 reads
# BOM-less scripts in the system code page; all user-facing text lives in hub-messages.json).
#
# A repository belongs to a hub when its "origin" remote (owner/name) is listed in ../projects.json.
# Everywhere else this hook does nothing. Nothing is ever committed to the game repository: the
# agent's working files live in <repo>/.hikari-hub/, which the skill adds to .git/info/exclude.
#
#   session : SessionStart - tells the agent this repository is a hub project and what to do first.
#   edit    : PreToolUse (Edit / Write / MultiEdit / NotebookEdit) - no registered work, no edit;
#             no edits on the base branch; owner-protected files need the human's OK.
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

function Read-Text([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return "" }
    return [IO.File]::ReadAllText($path, $utf8)
}

function Read-Json([string]$path) {
    $text = Read-Text $path
    if (-not $text.Trim()) { return $null }
    return $text | ConvertFrom-Json
}

# Walks up from $start to the folder that holds .git (a folder, or a pointer file in a worktree).
function Find-RepoRoot([string]$start) {
    $dir = $start
    while ($dir) {
        if (Test-Path -LiteralPath (Join-Path $dir ".git")) { return $dir }
        $parent = Split-Path -Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { return $null }
        $dir = $parent
    }
    return $null
}

# This checkout's git dir: .git itself, or the dir a worktree's .git file points at.
function Get-GitDir([string]$root) {
    $git = Join-Path $root ".git"
    if (Test-Path -LiteralPath $git -PathType Container) { return $git }
    if ((Read-Text $git) -notmatch 'gitdir:\s*(.+)') { return "" }
    $target = $Matches[1].Trim()
    if (-not [IO.Path]::IsPathRooted($target)) { $target = Join-Path $root $target }
    return $target
}

# "owner/name" of the origin remote, lower-cased; empty when there is none.
function Get-RepoKey([string]$gitDir) {
    $common = $gitDir
    $pointer = (Read-Text (Join-Path $gitDir "commondir")).Trim()
    if ($pointer) {
        if ([IO.Path]::IsPathRooted($pointer)) { $common = $pointer } else { $common = Join-Path $gitDir $pointer }
    }
    if ((Read-Text (Join-Path $common "config")) -notmatch '(?s)\[remote "origin"\][^\[]*?url\s*=\s*(\S+)') { return "" }
    $url = $Matches[1] -replace '\.git$', ''
    if ($url -match '([^/:]+)/([^/]+)$') { return ($Matches[1] + "/" + $Matches[2]).ToLowerInvariant() }
    return ""
}

function Find-Project([string]$gitDir) {
    $key = Get-RepoKey $gitDir
    if (-not $key) { return $null }
    foreach ($project in @(Read-Json (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "projects.json"))) {
        if ($project -and ([string]$project.repo).ToLowerInvariant() -eq $key) { return $project }
    }
    return $null
}

function Get-Branch([string]$gitDir) {
    if ((Read-Text (Join-Path $gitDir "HEAD")) -match 'ref:\s*refs/heads/(\S+)') { return $Matches[1] }
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

    $start = (Get-Location).Path
    $file = ""
    if ($Mode -eq "session") {
        if ($event -and $event.cwd) { $start = [string]$event.cwd }
    } else {
        if (-not $event -or -not $event.tool_input) { exit 0 }
        $file = [string]$event.tool_input.file_path
        if (-not $file) { $file = [string]$event.tool_input.notebook_path }
        if (-not $file) { exit 0 }
        $start = Split-Path -Path $file -Parent
    }
    $root = Find-RepoRoot $start
    if (-not $root) { exit 0 }
    $gitDir = Get-GitDir $root
    if (-not $gitDir) { exit 0 }
    $hub = Find-Project $gitDir
    if (-not $hub) { exit 0 }
    $active = Read-Json (Join-Path $root ".hikari-hub/active.json")
    $hasWork = [bool]($active -and $active.card)

    if ($Mode -eq "session") {
        if ($hasWork) {
            Write-Out ($msg.session_active -f [string]$hub.name, [string]$active.title, [string]$active.branch)
        } else {
            Write-Out ($msg.session_idle -f [string]$hub.name)
        }
        exit 0
    }

    $rel = $file.Substring($root.Length).TrimStart('\', '/').Replace("\", "/")
    # The agent's own working files (cache, active work, pending notes) are always writable.
    if ($rel.StartsWith(".hikari-hub/", [StringComparison]::OrdinalIgnoreCase)) { exit 0 }

    $project = Read-Json (Join-Path $root ".hikari-hub/cache/settings/project.json")
    if (-not $project) { Send-Decision "deny" $msg.no_sync }

    $requireCard = $true
    if ($null -ne $project.require_card) { $requireCard = [bool]$project.require_card }
    if ($requireCard) {
        if (-not $hasWork) { Send-Decision "deny" $msg.no_card }
        $base = "main"
        if ($project.base_branch) { $base = [string]$project.base_branch }
        $branch = Get-Branch $gitDir
        if ($branch -and $branch -eq $base) { Send-Decision "deny" ($msg.on_base -f $base, [string]$active.branch) }
    }
    if (Test-PathMatch $rel $project.protected_paths) { Send-Decision "ask" ($msg.protected -f $rel) }
    exit 0
} catch {
    [Console]::Error.WriteLine("hub-hook: " + $_.Exception.Message)
    exit 0
}
