# Commit message and branch name checks of the HIKARI Production Hub. Keep this file ASCII-only (Windows
# PowerShell 5.1); the words people read are in git-check.json. Needs lib/hub-common.ps1.
#
# Used by the repository's commit-msg hook (lib/hub-git-check.ps1, copied into .git/hooks/hikari-hub/), by the guard
# hook (the name of a branch being created) and by "hub check" (commits already made). What is checked comes from the
# hub's rule "rule-git-commit" as synced into .hikari-hub/cache (the owner edits it on the site): the list of types
# (the backquoted words on its line with U+7A2E U+5225) and the length limit of the first line (the number before
# U+5B57 on the template line). git-check.json holds the defaults for both.

# Everything the checks need about this repository, read from the hub folder (no network).
function Get-GitCheckRules([string]$root, $data) {
    $hub = Find-HubFolder $root
    $cache = Join-Path $hub "cache"
    $rules = @{ types = @($data.types); max = [int]$data.subject_max; data = $data; cards = $null
        requireCard = $true; guarded = @(); synced = (Test-Path -LiteralPath $cache) }
    $rule = Read-Json (Join-Path $cache "rules/rule-git-commit.json")
    if ($rule -and $rule.body) {
        $typeWord = [string][char]0x7A2E + [char]0x5225
        $limitWord = [string][char]0x5B57
        foreach ($line in ([string]$rule.body -split "`n")) {
            if (-not $line.Contains($typeWord)) { continue }
            $found = @([regex]::Matches($line, '`([a-z][a-z0-9-]*)`') | ForEach-Object { $_.Groups[1].Value })
            if ($found.Count -and -not $line.Contains("<")) { $rules.types = $found }
            if ($line.Contains("<") -and $line -match ('(\d+)\s*' + $limitWord)) { $rules.max = [int]$Matches[1] }
        }
    }
    $folder = Join-Path $cache "cards"
    if (Test-Path -LiteralPath $folder) {
        $rules.cards = @{}
        foreach ($file in (Get-ChildItem -LiteralPath $folder -Filter "*.json")) { $rules.cards[$file.BaseName] = $true }
    }
    $project = Read-Json (Join-Path $cache "settings/project.json")
    $base = "develop"; $release = "main"
    if ($project) {
        if ($project.base_branch) { $base = [string]$project.base_branch }
        if ($project.release_branch) { $release = [string]$project.release_branch }
        if ($null -ne $project.require_card) { $rules.requireCard = [bool]$project.require_card }
    }
    # The base, release and everybody's own branch are not work branches: their names are not checked.
    $guarded = New-Object Collections.ArrayList
    [void]$guarded.Add($base); [void]$guarded.Add($release)
    $members = Join-Path $cache "members"
    if (Test-Path -LiteralPath $members) {
        foreach ($file in (Get-ChildItem -LiteralPath $members -Filter "*.json")) {
            $member = Read-Json $file.FullName
            if ($member -and $member.branch) { [void]$guarded.Add([string]$member.branch) }
        }
    }
    $me = Read-Json (Join-Path $hub "me.json")
    if ($me -and $me.branch) { [void]$guarded.Add([string]$me.branch) }
    $rules.guarded = @($guarded)
    return $rules
}

function Format-GitCheck($rules, [string]$key, [object[]]$values) {
    $text = [string]$rules.data.messages.$key
    if ($values) { return ($text -f $values) }
    return $text
}

# Chinese characters and words in Japanese text (text in backquotes, such as paths and code, is skipped).
function Find-Hanzi([string]$text, $rules) {
    $plain = [regex]::Replace($text, '`[^`]*`', ' ')
    $found = New-Object Collections.ArrayList
    foreach ($word in $rules.data.hanzi_words.PSObject.Properties) {
        if ($plain.Contains($word.Name)) { [void]$found.Add($word.Name + " -> " + $word.Value) }
    }
    $chars = [string]$rules.data.hanzi_chars
    foreach ($ch in $plain.ToCharArray()) {
        if ($chars.IndexOf($ch) -ge 0 -and -not $found.Contains([string]$ch)) { [void]$found.Add([string]$ch) }
    }
    return @($found)
}

# Length in the Japanese way: a full-width character is 1, a half-width one (ASCII, half-width kana) is 0.5, rounded up.
function Get-JapaneseLength([string]$text) {
    $half = 0
    foreach ($ch in $text.ToCharArray()) { if ([int]$ch -lt 0x100 -or ([int]$ch -ge 0xFF61 -and [int]$ch -le 0xFF9F)) { $half += 1 } }
    return [int][Math]::Ceiling($text.Length - $half / 2.0)
}

# The card of a work branch ("" for any other branch).
function Get-BranchCard([string]$branch) {
    if ($branch -match '^[^/]+/(c-[0-9a-z]+)-') { return $Matches[1] }
    return ""
}

# Why a branch name breaks the rule ("" when it is fine, or when it is the base, release or somebody's own branch).
function Test-BranchName([string]$branch, $rules) {
    if (-not $branch -or ($rules.guarded -contains $branch)) { return "" }
    $why = ""
    if ($branch -notmatch '^([^/]+)/(c-[^-/]+)-([^/]+)$') {
        $why = Format-GitCheck $rules "branch_shape"
    } else {
        $type = $Matches[1]; $card = $Matches[2]; $name = $Matches[3]
        $parts = New-Object Collections.ArrayList
        if ($rules.types -cnotcontains $type) { [void]$parts.Add((Format-GitCheck $rules "branch_type" @($type, ($rules.types -join " / ")))) }
        if ($rules.cards) {
            if (-not $rules.cards.ContainsKey($card)) { [void]$parts.Add((Format-GitCheck $rules "branch_card" @($card))) }
        } elseif ($card -cnotmatch '^c-[0-9a-f]{6}$') {
            [void]$parts.Add((Format-GitCheck $rules "branch_id" @($card)))
        }
        if ($name -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { [void]$parts.Add((Format-GitCheck $rules "branch_name" @($name))) }
        $why = $parts -join " "
    }
    if (-not $why) { return "" }
    return (Format-GitCheck $rules "branch" @($branch, $why))
}

# Why a commit breaks the rules (an empty list when it is fine).
#   $context: @{ branch = the branch it goes on; merge = $true for a merge commit; author = "Name <mail>" }
function Test-CommitMessage([string]$text, $context, $rules) {
    $problems = New-Object Collections.ArrayList
    # What git keeps of the message: up to the scissors line, without comment lines, trimmed.
    $kept = New-Object Collections.ArrayList
    foreach ($line in ($text.Replace("`r`n", "`n") -split "`n")) {
        if ($line -match '^# -+ >8 -+$') { break }
        if ($line.StartsWith("#")) { continue }
        [void]$kept.Add($line.TrimEnd())
    }
    $lines = @(($kept -join "`n").Trim("`n").Split("`n"))
    if (-not ($lines -join "").Trim()) { return @() }

    foreach ($line in $lines) {
        if ($line -match '^\s*(co-authored-by\s*:.*|.*generated with \[?claude.*)$') { [void]$problems.Add((Format-GitCheck $rules "coauthor" @($line.Trim()))) }
    }
    if ($context.author -and $context.author -match $rules.data.bot_names) { [void]$problems.Add((Format-GitCheck $rules "author" @($context.author))) }

    $subject = $lines[0]
    # Messages git writes itself (a merge, a revert, fixups to squash later) keep git's own shape.
    if (($context.merge -and $subject.StartsWith("Merge ")) -or $subject -match '^(fixup|squash|amend)! |^Revert "') { return @($problems) }

    if ($subject -notmatch '^([A-Za-z]+)\(([^()]+)\): (\S.*)$') {
        [void]$problems.Add((Format-GitCheck $rules "subject" @(($rules.types -join " / "), $subject)))
    } else {
        $type = $Matches[1]; $summary = $Matches[3]
        if ($rules.types -cnotcontains $type) { [void]$problems.Add((Format-GitCheck $rules "type" @($type, ($rules.types -join " / ")))) }
        # "<Japanese> / <translation>": the Japanese part is what the rule is about.
        $japanese = ($summary -split ' / ', 2)[0].Trim()
        $length = Get-JapaneseLength $japanese
        if ($length -gt $rules.max) { [void]$problems.Add((Format-GitCheck $rules "long" @($length, $rules.max))) }
        if ($japanese -notmatch ('[' + [char]0x3040 + '-' + [char]0x30FF + ']')) { [void]$problems.Add((Format-GitCheck $rules "kana")) }
        $hanzi = Find-Hanzi $japanese $rules
        if ($hanzi.Count) { [void]$problems.Add((Format-GitCheck $rules "hanzi" @((Format-GitCheck $rules "in_subject"), ($hanzi -join ", ")))) }
    }
    if ($lines.Count -gt 1 -and $lines[1].Trim()) { [void]$problems.Add((Format-GitCheck $rules "blank")) }

    # The body is Japanese except for paragraphs headed as a translation (ZH: / CN: / [ZH] / U+3010 U+4E2D U+6587 U+3011 ...).
    $zh = '^\s*(ZH|CN|\[ZH\]|' + [char]0x3010 + [char]0x4E2D + [char]0x6587 + [char]0x3011 + '|' + [char]0x4E2D + [char]0x6587 + ')\s*[:' + [char]0xFF1A + ']?'
    $ja = '^\s*(JA|JP|\[JA\]|' + [char]0x3010 + [char]0x65E5 + [char]0x672C + [char]0x8A9E + [char]0x3011 + '|' + [char]0x65E5 + [char]0x672C + [char]0x8A9E + ')\s*[:' + [char]0xFF1A + ']?'
    $japaneseBody = New-Object Text.StringBuilder
    $inJapanese = $true
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match $zh) { $inJapanese = $false; continue }
        if ($line -match $ja) { $inJapanese = $true; $line = $line -replace $ja, '' }
        elseif ($line -match '^[A-Za-z-]+:\s') { continue }
        if ($inJapanese) { [void]$japaneseBody.Append($line).Append("`n") }
    }
    $hanzi = Find-Hanzi $japaneseBody.ToString() $rules
    if ($hanzi.Count) { [void]$problems.Add((Format-GitCheck $rules "hanzi" @((Format-GitCheck $rules "in_body"), ($hanzi -join ", ")))) }

    if ($rules.requireCard) {
        $branchCard = Get-BranchCard $context.branch
        $cards = @($lines | Where-Object { $_ -match '^Card:\s*\S+\s*$' } | ForEach-Object { ($_ -replace '^Card:\s*', '').Trim() })
        if (-not $cards.Count) {
            $hint = ""
            if ($branchCard) { $hint = Format-GitCheck $rules "card_now" @($branchCard) }
            [void]$problems.Add((Format-GitCheck $rules "card_missing" @($hint)))
        }
        foreach ($card in $cards) {
            if ($rules.cards -and -not $rules.cards.ContainsKey($card)) { [void]$problems.Add((Format-GitCheck $rules "card_unknown" @($card))) }
        }
        if ($cards.Count -and $branchCard -and ($cards -notcontains $branchCard)) { [void]$problems.Add((Format-GitCheck $rules "card_mismatch" @($cards[0], $branchCard))) }
    }
    return @($problems)
}
