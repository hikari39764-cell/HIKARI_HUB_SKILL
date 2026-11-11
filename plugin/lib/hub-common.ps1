# Shared by the guard hook (hooks/hub-hook.ps1) and the agent tool (tools/hub.ps1).
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts in the system code page.
#
# A repository belongs to the hub when its "origin" remote (owner/name) is listed in ../projects.json.

$utf8 = New-Object System.Text.UTF8Encoding($false)
$pluginRoot = Split-Path -Path $PSScriptRoot -Parent

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

# The projects.json entry ({repo, name, id}) of this repository, or $null.
function Find-Project([string]$gitDir) {
    $key = Get-RepoKey $gitDir
    if (-not $key) { return $null }
    # Assign before looping: Windows PowerShell 5.1 emits a JSON array as one object, so @(Read-Json ...) holds the
    # whole list as a single item and no entry matches once projects.json lists two or more projects.
    $projects = Read-Json (Join-Path $pluginRoot "projects.json")
    foreach ($project in $projects) {
        if ($project -and ([string]$project.repo).ToLowerInvariant() -eq $key) { return $project }
    }
    return $null
}

# How the agent calls the tool, and where the project's page is (hub.json holds the site address).
function Get-ToolPath { return (Join-Path $pluginRoot "tools/hub.cmd").Replace("\", "/") }
function Get-ProjectUrl([string]$id) {
    $hub = Read-Json (Join-Path $pluginRoot "hub.json")
    if (-not $hub) { return "" }
    return ([string]$hub.site) + "?p=" + $id
}
