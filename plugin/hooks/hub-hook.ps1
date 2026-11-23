# HIKARI Production Hub guard hook (keep this file ASCII-only: Windows PowerShell 5.1 reads
# BOM-less scripts in the system code page; all user-facing text lives in hub-messages.json).
#
# A repository belongs to a hub when its "origin" remote (owner/name) is a project in the person's project
# directory (the copy "hub projects" keeps in %USERPROFILE%\.hikari-hub\projects.json). Everywhere else this hook
# does nothing, except at the start of a session in a HIKARI game repository (Project.hikari) on a PC that has no
# hub key yet: then it says how to connect. Nothing is ever committed to the game repository: the
# agent's working files live in <repo>/.hikari-hub/, which the hub tool lists in .git/info/exclude.
#
#   session : SessionStart - tells the agent this repository is a hub project and what to do first.
#   edit    : PreToolUse (Edit / Write / MultiEdit / NotebookEdit) - no registered work, no edit;
#             no edits on the base / release branch or on anybody's own branch (work happens on work
#             branches); owner-protected files need the human's OK.
#   git     : PreToolUse (Bash / PowerShell) - merging or pushing into:
#               the person's own branch (members/<uid>.branch) - free;
#               somebody else's own branch                   - refused;
#               the base (default develop) or release branch (default main) - the owner only, and
#               the human's OK every time (refused for the others).
#
# Whose branch is whose comes from the synced members (.hikari-hub/cache/members) and from
# .hikari-hub/me.json, which "hub whoami" / "hub sync" write. Without me.json the base and release
# branches fall back to asking.
#
# The guard fails open: if the hook itself breaks, work is not blocked.
param([string]$Mode = "edit")

. (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "lib/hub-common.ps1")

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
    } elseif ($Mode -eq "git") {
        if (-not $event -or -not $event.tool_input) { exit 0 }
        $command = [string]$event.tool_input.command
        if (-not $command) { exit 0 }
        if ($event.cwd) { $start = [string]$event.cwd }
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
    if (-not $hub -and $Mode -eq "session") {
        $keyFile = Join-Path $env:USERPROFILE ".hikari-hub\key.json"
        $age = Get-DirectoryAge
        if (-not (Test-Path -LiteralPath $keyFile)) {
            if (Test-Path -LiteralPath (Join-Path $root "Project.hikari")) { Write-Out ($msg.session_nokey -f (Get-ToolPath)) }
            exit 0
        }
        # Refresh the copy of the project directory: wait for it when there is none, in the background when it is old.
        $tool = Join-Path $pluginRoot "tools/hub.ps1"
        $refresh = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ('"' + $tool + '"'), "projects")
        if ($age -gt 99999) {
            $child = Start-Process -FilePath "powershell" -ArgumentList $refresh -WindowStyle Hidden -PassThru
            if ($child.WaitForExit(12000)) { $hub = Find-Project $gitDir }
        } elseif ($age -gt 12) {
            Start-Process -FilePath "powershell" -ArgumentList $refresh -WindowStyle Hidden | Out-Null
        }
    }
    if (-not $hub) { exit 0 }
    $active = Read-Json (Join-Path $root ".hikari-hub/active.json")
    $hasWork = [bool]($active -and $active.card)

    if ($Mode -eq "session") {
        $intro = $msg.session -f [string]$hub.name, (Get-ProjectUrl ([string]$hub.id)), (Get-ToolPath)
        if ($hasWork) {
            Write-Out ($intro + ($msg.session_active -f [string]$active.title, [string]$active.branch))
        } else {
            Write-Out ($intro + $msg.session_idle)
        }
        exit 0
    }

    $project = Read-Json (Join-Path $root ".hikari-hub/cache/settings/project.json")
    $base = "develop"
    if ($project -and $project.base_branch) { $base = [string]$project.base_branch }
    $release = "main"
    if ($project -and $project.release_branch) { $release = [string]$project.release_branch }
    $branch = Get-Branch $gitDir
    $me = Read-Json (Join-Path $root ".hikari-hub/me.json")
    $mine = ""
    if ($me -and $me.branch) { $mine = [string]$me.branch }
    # Everybody's own branch -> whose it is.
    $personal = @{}
    $folder = Join-Path $root ".hikari-hub/cache/members"
    if (Test-Path -LiteralPath $folder) {
        foreach ($item in (Get-ChildItem -LiteralPath $folder -Filter "*.json")) {
            $member = Read-Json $item.FullName
            if ($member -and $member.branch) { $personal[[string]$member.branch] = [string]$member.handle }
        }
    }
    if ($mine) { $personal[$mine] = [string]$me.handle }
    $guarded = @($release, $base) + @($personal.Keys | Where-Object { $_ -ne $base -and $_ -ne $release })

    if ($Mode -eq "git") {
        $target = ""
        if ($command -match '\bgh\s+pr\s+merge\b') { $target = "PR" }
        foreach ($m in [regex]::Matches($command, '\bgit\s[^;&|\r\n]*?\b(merge|push)(?![-\w])([^;&|\r\n]*)')) {
            if ($target) { break }
            $rest = $m.Groups[2].Value
            if ($m.Groups[1].Value -eq "merge") {
                if ($guarded -contains $branch) { $target = $branch }
            } else {
                foreach ($t in $guarded) {
                    if ($rest -match ('(^|[\s:+]|refs/heads/)' + [regex]::Escape($t) + '(\s|$)')) { $target = $t; break }
                }
                if (-not $target -and ($guarded -contains $branch) -and $rest -notmatch ':') { $target = $branch }
            }
        }
        if (-not $target) { exit 0 }
        if ($target -eq "PR") { Send-Decision "ask" ($msg.merge_pr -f $base, $release) }
        if ($target -eq $release -or $target -eq $base) {
            if ($me -and -not [bool]$me.owner) { Send-Decision "deny" ($msg.not_owner -f $target, $mine) }
            if ($target -eq $release) { Send-Decision "ask" ($msg.merge_release -f $release, $base) }
            Send-Decision "ask" ($msg.merge_base -f $base)
        }
        if ($target -eq $mine) { exit 0 }
        Send-Decision "deny" ($msg.others_branch -f $target, $personal[$target])
    }

    $rel = $file.Substring($root.Length).TrimStart('\', '/').Replace("\", "/")
    # The agent's own working files (cache, records to push, active work) are always writable.
    if ($rel.StartsWith(".hikari-hub/", [StringComparison]::OrdinalIgnoreCase)) { exit 0 }

    if (-not $project) { Send-Decision "deny" $msg.no_sync }

    $requireCard = $true
    if ($null -ne $project.require_card) { $requireCard = [bool]$project.require_card }
    if ($requireCard) {
        if (-not $hasWork) { Send-Decision "deny" $msg.no_card }
        if ($branch -and ($guarded -contains $branch)) { Send-Decision "deny" ($msg.on_base -f $branch, [string]$active.branch) }
    }
    if (Test-PathMatch $rel $project.protected_paths) { Send-Decision "ask" ($msg.protected -f $rel) }
    exit 0
} catch {
    [Console]::Error.WriteLine("hub-hook: " + $_.Exception.Message)
    exit 0
}
