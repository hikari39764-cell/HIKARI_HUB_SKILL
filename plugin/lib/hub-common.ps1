# Shared by the guard hook (hooks/hub-hook.ps1) and the agent tool (tools/hub.ps1).
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts in the system code page.
#
# A repository belongs to the hub when its "origin" remote (owner/name) is the repository of a project
# in the person's project directory on the hub (directory/<e-mail>/projects). "hub projects" (also run by
# login, whoami and sync) keeps a copy in %USERPROFILE%\.hikari-hub\projects.json, which is all this reads.

$utf8 = New-Object System.Text.UTF8Encoding($false)
$pluginRoot = Split-Path -Path $PSScriptRoot -Parent
$directoryPath = Join-Path $env:USERPROFILE ".hikari-hub\projects.json"

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

# Quotes one argument for the Windows command line (CommandLineToArgvW rules).
function ConvertTo-Argument([string]$text) {
    if ($text -and $text -notmatch '[\s"]') { return $text }
    $out = New-Object Text.StringBuilder
    [void]$out.Append('"')
    $slashes = 0
    foreach ($ch in $text.ToCharArray()) {
        if ($ch -eq '\') { $slashes += 1; continue }
        if ($ch -eq '"') { [void]$out.Append('\' * ($slashes * 2 + 1)).Append('"') }
        else { [void]$out.Append('\' * $slashes).Append($ch) }
        $slashes = 0
    }
    [void]$out.Append('\' * ($slashes * 2)).Append('"')
    return $out.ToString()
}

# Runs git in $root and returns its output decoded as UTF-8 (PowerShell's own pipe would use the console code page).
function Invoke-Git([string]$root, [string[]]$arguments) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = "git"
    $info.Arguments = ((@("-C", $root, "-c", "core.quotepath=off") + $arguments) | ForEach-Object { ConvertTo-Argument $_ }) -join " "
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $utf8
    $process = [Diagnostics.Process]::Start($info)
    $errors = $process.StandardError.ReadToEndAsync()
    $text = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    return @{ code = $process.ExitCode; text = $text; errors = $errors.Result }
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

# The git dir shared by every worktree of the repository (holds config and info/exclude).
function Get-CommonGitDir([string]$gitDir) {
    $pointer = (Read-Text (Join-Path $gitDir "commondir")).Trim()
    if (-not $pointer) { return $gitDir }
    if ([IO.Path]::IsPathRooted($pointer)) { return $pointer }
    return (Join-Path $gitDir $pointer)
}

# The checked-out branch ("" on a detached HEAD).
function Get-Branch([string]$gitDir) {
    if ((Read-Text (Join-Path $gitDir "HEAD")) -match 'ref:\s*refs/heads/(\S+)') { return $Matches[1] }
    return ""
}

# The agent's working folder (.hikari-hub) of a checkout: its own, or the main checkout's for a linked worktree.
function Find-HubFolder([string]$root) {
    $own = Join-Path $root ".hikari-hub"
    if (Test-Path -LiteralPath $own) { return $own }
    $common = Get-CommonGitDir (Get-GitDir $root)
    $main = Join-Path (Split-Path -Path $common -Parent) ".hikari-hub"
    if (Test-Path -LiteralPath $main) { return $main }
    return $own
}

# The commit message check (lib/hub-git-rules.ps1) as the repository's commit-msg hook. Its files are copied into
# <common git dir>/hooks/hikari-hub/ (again whenever this plugin's copy differs) and hooks/commit-msg runs them, so the
# check keeps working for every commit, by agents and people alike, and nothing enters the repository itself.
# Returns "" when the hook is in place, "hooksPath:<folder>" when git reads hooks from elsewhere, and "other" when
# a commit-msg hook that is not the hub's is already there (both are left alone).
$gitCheckFiles = @("lib/hub-common.ps1", "lib/hub-git-rules.ps1", "lib/hub-git-check.ps1", "lib/git-check.json")
$gitCheckHook = "#!/bin/sh`n" +
    "# hikari-hub: checks the commit message and branch name against the hub's Git rules.`n" +
    "# Written by the HIKARI hub tool. Exit 1 rejects the commit; when the check cannot run, the commit goes through.`n" +
    "check=`"`$(dirname `"`$0`")/hikari-hub/hub-git-check.ps1`"`n" +
    "[ -f `"`$check`" ] || exit 0`n" +
    "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"`$check`" commit-msg `"`$1`"`n" +
    "[ `$? -eq 3 ] && exit 1`n" +
    "exit 0`n"
function Install-GitCheck([string]$root) {
    $hooksPath = (Invoke-Git $root @("config", "--get", "core.hooksPath")).text.Trim()
    if ($hooksPath) { return ("hooksPath:" + $hooksPath) }
    $hooks = Join-Path (Get-CommonGitDir (Get-GitDir $root)) "hooks"
    $folder = Join-Path $hooks "hikari-hub"
    [void][IO.Directory]::CreateDirectory($folder)
    foreach ($file in $gitCheckFiles) {
        $text = Read-Text (Join-Path $pluginRoot $file)
        $target = Join-Path $folder (Split-Path -Path $file -Leaf)
        if ((Read-Text $target) -ne $text) { [IO.File]::WriteAllText($target, $text, $utf8) }
    }
    $hook = Join-Path $hooks "commit-msg"
    $current = Read-Text $hook
    if ($current -and -not $current.Contains("# hikari-hub:")) { return "other" }
    if ($current -ne $gitCheckHook) { [IO.File]::WriteAllText($hook, $gitCheckHook, $utf8) }
    return ""
}

# "owner/name" of the origin remote, lower-cased; empty when there is none.
function Get-RepoKey([string]$gitDir) {
    if ((Read-Text (Join-Path (Get-CommonGitDir $gitDir) "config")) -notmatch '(?s)\[remote "origin"\][^\[]*?url\s*=\s*(\S+)') { return "" }
    $url = $Matches[1] -replace '\.git$', ''
    if ($url -match '([^/:]+)/([^/]+)$') { return ($Matches[1] + "/" + $Matches[2]).ToLowerInvariant() }
    return ""
}

# The project directory entry ({id, name, repo}) of this repository, or $null.
function Find-Project([string]$gitDir) {
    $key = Get-RepoKey $gitDir
    if (-not $key) { return $null }
    $directory = Read-Json $directoryPath
    if (-not $directory) { return $null }
    # Assign before looping: Windows PowerShell 5.1 emits a JSON array as one object, so @(...) would hold the
    # whole list as a single item.
    $projects = $directory.projects
    foreach ($project in $projects) {
        if ($project -and ([string]$project.repo).ToLowerInvariant() -eq $key) { return $project }
    }
    return $null
}

# How old the directory copy is, in hours (a large number when there is none).
function Get-DirectoryAge {
    if (-not (Test-Path -LiteralPath $directoryPath)) { return 100000 }
    return ([DateTime]::UtcNow - (Get-Item -LiteralPath $directoryPath).LastWriteTimeUtc).TotalHours
}

# How the agent calls the tool, and where the project's page is (hub.json holds the site address).
function Get-ToolPath { return (Join-Path $pluginRoot "tools/hub.cmd").Replace("\", "/") }
function Get-ProjectUrl([string]$id) {
    $hub = Read-Json (Join-Path $pluginRoot "hub.json")
    if (-not $hub) { return "" }
    return ([string]$hub.site) + "?p=" + $id
}
