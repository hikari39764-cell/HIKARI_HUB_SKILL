# The HIKARI Production Hub's commit-msg hook. Keep this file ASCII-only (Windows PowerShell 5.1).
# "hub" copies it, with lib/hub-common.ps1, lib/hub-git-rules.ps1 and lib/git-check.json, into
# <git dir>/hooks/hikari-hub/; hooks/commit-msg runs it as: hub-git-check.ps1 commit-msg <message file>
# (git starts hooks at the top of the work tree).
#
# Exit 0: the commit may go on. Exit 3: it breaks the hub's Git rules (the reasons go to stderr, the hook rejects it).
# Anything else means the check itself failed; the hook then lets the commit through.
param([string]$Mode = "", [string]$Path = "")

try {
    . (Join-Path $PSScriptRoot "hub-common.ps1")
    . (Join-Path $PSScriptRoot "hub-git-rules.ps1")
    if ($Mode -ne "commit-msg" -or -not $Path) { exit 0 }
    $root = Find-RepoRoot (Get-Location).Path
    if (-not $root) { exit 0 }
    $gitDir = Get-GitDir $root
    $rules = Get-GitCheckRules $root (Read-Json (Join-Path $PSScriptRoot "git-check.json"))
    if (-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path (Get-Location).Path $Path }

    $branch = Get-Branch $gitDir
    $author = ((Invoke-Git $root @("var", "GIT_AUTHOR_IDENT")).text.Trim() -replace '\s+\d+\s+[+-]\d{4}$', '')
    $context = @{ branch = $branch; merge = (Test-Path -LiteralPath (Join-Path $gitDir "MERGE_HEAD")); author = $author }
    $problems = New-Object Collections.ArrayList
    foreach ($p in (Test-CommitMessage (Read-Text $Path) $context $rules)) { [void]$problems.Add($p) }
    $why = Test-BranchName $branch $rules
    if ($why) { [void]$problems.Add($why) }
    if (-not $problems.Count) { exit 0 }

    $text = (Format-GitCheck $rules "head") + "`n" + (($problems | ForEach-Object { "- " + $_ }) -join "`n") + "`n"
    $bytes = $utf8.GetBytes($text)
    $stderr = [Console]::OpenStandardError()
    $stderr.Write($bytes, 0, $bytes.Length)
    $stderr.Flush()
    exit 3
} catch {
    [Console]::Error.WriteLine("hikari-hub commit check: " + $_.Exception.Message)
    exit 0
}
