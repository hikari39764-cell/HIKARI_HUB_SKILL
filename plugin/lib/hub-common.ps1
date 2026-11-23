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
