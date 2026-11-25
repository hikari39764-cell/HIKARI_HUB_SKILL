# Builds the map of one branch for the hub's "map" collection (fields: schema/schema.json, collection "map").
# Keep this file ASCII-only (Windows PowerShell 5.1). Used by tools/hub.ps1 ("hub map").
#
# Everything is read from git objects, so nothing is checked out and any branch can be mapped from any checkout.
#   node : a folder cut to three levels (Source/Runtime/Boss, Assets/Vfx), a scene file (*.scene.json, with its
#          <name>.cells/ folder), or "." for files at the top. The asset meta folder is not a node.
#          Outside the repository: "@sdk" (the engine SDK) and "@type:<prefix>" (components of the engine or of a module).
#   edge : include   - a #include between two nodes, or "engine" for #include "HIKARI/..."
#          asset     - a file that names an asset GUID (the meta files map GUIDs to paths)
#          component - a scene or prefab that uses a component type a source file declares ("Project_X.Boss")
#   last : the newest change of the branch (one finished card is one squashed commit), for the page to highlight.

$script:MetaRoot = "ProjectSettings/AssetMeta/"
$script:CodeFile = '\.(h|hh|hpp|hxx|inl|ipp|c|cc|cpp|cxx|hlsl|hlsli)$'
$script:MaxChanged = 500
$script:MaxLast = 200
$script:MaxHeaders = 60

# "a/b/../c" -> "a/c"; $null when it climbs out of the repository.
function Resolve-RepoPath([string]$path) {
    $parts = New-Object Collections.ArrayList
    foreach ($part in $path.Replace("\", "/").Split("/")) {
        if (-not $part -or $part -eq ".") { continue }
        if ($part -eq "..") {
            if (-not $parts.Count) { return $null }
            $parts.RemoveAt($parts.Count - 1)
        } else { [void]$parts.Add($part) }
    }
    return ($parts -join "/")
}

function Get-NodeId([string]$path, $scenes) {
    if ($path.StartsWith($script:MetaRoot)) { return "" }
    if ($path.EndsWith(".scene.json")) { return $path }
    $dirs = $path.Split("/")
    if ($dirs.Length -eq 1) { return "." }
    $dirs = $dirs[0..($dirs.Length - 2)]
    for ($i = 0; $i -lt $dirs.Length; $i++) {
        if ($dirs[$i].EndsWith(".cells")) {
            $scene = (($dirs[0..$i] -join "/") -replace '\.cells$', '') + ".scene.json"
            if ($scenes.Contains($scene)) { return $scene }
        }
    }
    return ($dirs[0..([Math]::Min(3, $dirs.Length) - 1)] -join "/")
}

# git grep -z output: "<ref>:<path>\0<text>" per line. Calls $each with (path, text).
function Read-GrepLines([string]$text, [string]$ref, [scriptblock]$each) {
    $prefix = $ref + ":"
    foreach ($line in $text.Split([char]10)) {
        $cut = $line.IndexOf([char]0)
        if ($cut -lt 0 -or -not $line.StartsWith($prefix)) { continue }
        & $each $line.Substring($prefix.Length, $cut - $prefix.Length) $line.Substring($cut + 1)
    }
}

function Get-CommitInfo([string]$root, [string]$rev) {
    $log = (Invoke-Git $root @("log", "-1", "-z", "--format=%H%x1f%s%x1f%an%x1f%cI", $rev)).text.Trim([char]0, [char]10).Split([char]0x1f)
    return [ordered]@{ commit = $log[0]; subject = $log[1]; author = $log[2]; at = $log[3] }
}

# Files that differ between revisions ($revs: "a...b", or "a", "b"), most changed lines first: [{path, node, status, add, del}].
function Get-Changes([string]$root, [string[]]$revs, $nodeOf, $scenes) {
    $status = @{}
    $parts = (Invoke-Git $root (@("diff", "-z", "--no-renames", "--name-status") + $revs)).text.Split([char]0)
    for ($i = 0; $i + 1 -lt $parts.Length; $i += 2) { if ($parts[$i]) { $status[$parts[$i + 1]] = $parts[$i] } }
    $changed = New-Object Collections.ArrayList
    foreach ($entry in (Invoke-Git $root (@("diff", "-z", "--no-renames", "--numstat") + $revs)).text.Split([char]0)) {
        $cols = $entry.Split("`t")
        if ($cols.Length -lt 3) { continue }
        $path = $cols[2]
        $add = 0; $del = 0
        [void][int]::TryParse($cols[0], [ref]$add)
        [void][int]::TryParse($cols[1], [ref]$del)
        $node = $nodeOf[$path]
        if ($null -eq $node) { $node = Get-NodeId $path $scenes }
        [void]$changed.Add([ordered]@{ path = $path; node = $node; status = [string]$status[$path]; add = $add; del = $del })
    }
    return ($changed | Sort-Object -Property @{ Expression = { $_["add"] + $_["del"] }; Descending = $true }, @{ Expression = { $_["path"] } })
}

# The map of $ref; $compare (may be empty) is the branch it is measured against; $personal: someone's own branch.
function Get-BranchMap([string]$root, [string]$ref, [string]$compare, [bool]$personal) {
    $files = @{}
    $scenes = New-Object 'Collections.Generic.HashSet[string]'
    $byName = @{}
    $listing = (Invoke-Git $root @("ls-tree", "-r", "-l", "-z", $ref)).text
    foreach ($entry in $listing.Split([char]0)) {
        $tab = $entry.IndexOf("`t")
        if ($tab -lt 0) { continue }
        $path = $entry.Substring($tab + 1)
        $size = 0L
        [void][long]::TryParse(($entry.Substring(0, $tab) -split '\s+')[-1], [ref]$size)
        $files[$path] = $size
        if ($path.EndsWith(".scene.json")) { [void]$scenes.Add($path) }
        $name = $path.Substring($path.LastIndexOf("/") + 1)
        if (-not $byName.ContainsKey($name)) { $byName[$name] = New-Object Collections.ArrayList }
        [void]$byName[$name].Add($path)
    }

    $nodeOf = @{}
    $nodes = @{}
    foreach ($path in $files.Keys) {
        $id = Get-NodeId $path $scenes
        $nodeOf[$path] = $id
        if (-not $id) { continue }
        if (-not $nodes.ContainsKey($id)) { $nodes[$id] = @{ files = 0; bytes = 0L; code = 0 } }
        $nodes[$id].files += 1
        $nodes[$id].bytes += $files[$path]
        if ($path -match $script:CodeFile) { $nodes[$id].code += 1 }
    }

    $edges = @{}
    $addEdge = {
        param([string]$from, [string]$to, [string]$kind)
        if (-not $from -or -not $to -or $from -eq $to) { return }
        $key = $from + [char]1 + $to + [char]1 + $kind
        if ($edges.ContainsKey($key)) { $edges[$key] += 1 } else { $edges[$key] = 1 }
    }
    $headers = @{}

    # #include: "HIKARI/..." is the engine SDK; other quoted names resolve next to the file, else by a unique file name.
    $grep = Invoke-Git $root @("grep", "-z", "-I", "-E", '^\s*#\s*include\s*["<]', $ref, "--", "*.h", "*.hh", "*.hpp", "*.hxx", "*.inl", "*.ipp", "*.c", "*.cc", "*.cpp", "*.cxx", "*.hlsl", "*.hlsli")
    Read-GrepLines $grep.text $ref {
        param($path, $line)
        if ($line -notmatch '#\s*include\s*([<"])([^>"]+)[>"]') { return }
        $target = $Matches[2].Trim()
        if ($target.StartsWith("HIKARI/")) {
            & $addEdge $nodeOf[$path] "@sdk" "engine"
            if ($headers.ContainsKey($target)) { $headers[$target] += 1 } else { $headers[$target] = 1 }
            return
        }
        if ($Matches[1] -ne '"') { return }
        $dir = ""
        if ($path.Contains("/")) { $dir = $path.Substring(0, $path.LastIndexOf("/") + 1) }
        $hit = Resolve-RepoPath ($dir + $target)
        if (-not $hit -or -not $files.ContainsKey($hit)) {
            $hit = $null
            $name = $target.Substring($target.Replace("\", "/").LastIndexOf("/") + 1)
            if ($byName.ContainsKey($name)) {
                $found = @($byName[$name] | Where-Object { ("/" + $_).EndsWith("/" + $target.Replace("\", "/")) })
                if ($found.Count -eq 1) { $hit = $found[0] }
            }
        }
        if ($hit) { & $addEdge $nodeOf[$path] $nodeOf[$hit] "include" }
    }

    # Asset GUIDs: the meta files say which path each GUID belongs to.
    $guids = @{}
    $grep = Invoke-Git $root @("grep", "-z", "-I", "-E", '"(guid|sourcePath)"', $ref, "--", $script:MetaRoot)
    $pending = @{}
    Read-GrepLines $grep.text $ref {
        param($path, $line)
        if (-not $pending.ContainsKey($path)) { $pending[$path] = @{} }
        if ($line -match '"guid"\s*:\s*"([0-9a-fA-F]{32})"') { $pending[$path].guid = $Matches[1].ToLowerInvariant() }
        if ($line -match '"sourcePath"\s*:\s*"([^"]+)"') { $pending[$path].source = $Matches[1] }
    }
    foreach ($meta in $pending.Values) {
        if ($meta.guid -and $meta.source -and $nodeOf.ContainsKey($meta.source)) { $guids[$meta.guid] = $nodeOf[$meta.source] }
    }
    if ($guids.Count) {
        $grep = Invoke-Git $root @("grep", "-z", "-I", "-o", "-E", '[0-9a-f]{32}', $ref, "--", ".", (":(exclude)" + $script:MetaRoot))
        Read-GrepLines $grep.text $ref {
            param($path, $guid)
            if ($guids.ContainsKey($guid)) { & $addEdge $nodeOf[$path] $guids[$guid] "asset" }
        }
    }

    # Component types that scenes and prefabs use ("type": "Project_X.Boss") -> the source file that names them.
    $uses = New-Object Collections.ArrayList
    $grep = Invoke-Git $root @("grep", "-z", "-I", "-o", "-E", '"type"\s*:\s*"[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+"', $ref, "--", "Assets")
    Read-GrepLines $grep.text $ref {
        param($path, $match)
        if ($match -match '"([^"]+)"\s*$') { [void]$uses.Add(@($path, $Matches[1])) }
    }
    if ($uses.Count) {
        $declared = @{}
        $names = @($uses | ForEach-Object { $_[1] } | Sort-Object -Unique)
        $arguments = @("grep", "-z", "-I", "-o", "-F")
        foreach ($name in $names) { $arguments += @("-e", ('"' + $name + '"')) }
        $arguments += @($ref, "--", "*.h", "*.hh", "*.hpp", "*.inl", "*.c", "*.cc", "*.cpp", "*.cxx")
        $grep = Invoke-Git $root $arguments
        Read-GrepLines $grep.text $ref {
            param($path, $match)
            $name = $match.Trim('"')
            if (-not $declared.ContainsKey($name)) { $declared[$name] = $nodeOf[$path] }
        }
        foreach ($use in $uses) {
            $to = $declared[$use[1]]
            if (-not $to) { $to = "@type:" + $use[1].Substring(0, $use[1].LastIndexOf(".")) }
            & $addEdge $nodeOf[$use[0]] $to "component"
        }
    }

    # Outside nodes that something points at.
    foreach ($key in @($edges.Keys)) {
        $to = $key.Split([char]1)[1]
        if ($to.StartsWith("@") -and -not $nodes.ContainsKey($to)) { $nodes[$to] = @{ files = 0; bytes = 0L; code = 0 } }
    }

    $map = [Collections.Specialized.OrderedDictionary]::new()
    $map["head"] = Get-CommitInfo $root $ref
    $map["ahead"] = 0
    $map["behind"] = 0
    $changed = @()
    if ($compare) {
        $counts = (Invoke-Git $root @("rev-list", "--left-right", "--count", ($compare + "..." + $ref))).text.Trim() -split '\s+'
        $map["behind"] = [int]$counts[0]
        $map["ahead"] = [int]$counts[1]
        $changed = @(Get-Changes $root @($compare + "..." + $ref) $nodeOf $scenes)
    }
    $map["changed_total"] = $changed.Count
    $map["changed"] = @($changed | Select-Object -First $script:MaxChanged)

    # The last change: on someone's own branch, the newest own commit not yet in the compared branch (merges that only
    # caught up with develop are skipped); on develop and main, the newest commit against its first parent.
    $pick = @("log", "-1", "--first-parent", "--format=%H")
    if ($personal -and $compare) { $pick += @("--no-merges", ($compare + ".." + $ref)) } else { $pick += $ref }
    $commit = (Invoke-Git $root $pick).text.Trim()
    $map["last"] = $null
    if ($commit -and (Invoke-Git $root @("rev-parse", "--verify", "--quiet", ($commit + "^1"))).code -eq 0) {
        $files = @(Get-Changes $root @(($commit + "^1"), $commit) $nodeOf $scenes)
        $last = Get-CommitInfo $root $commit
        $last["changed_total"] = $files.Count
        $last["changed"] = @($files | Select-Object -First $script:MaxLast)
        $map["last"] = $last
    }
    $map["nodes"] = @($nodes.Keys | Sort-Object | ForEach-Object {
            $n = $nodes[$_]
            $kind = "other"
            if ($_.StartsWith("@")) { $kind = "outside" }
            elseif ($_.EndsWith(".scene.json")) { $kind = "scene" }
            elseif ($n.code * 2 -ge $n.files -and $n.code) { $kind = "code" }
            elseif ($_.StartsWith("Assets")) { $kind = "asset" }
            [ordered]@{ id = $_; kind = $kind; files = $n.files; bytes = $n.bytes }
        })
    $map["edges"] = @($edges.Keys | Sort-Object | ForEach-Object {
            $p = $_.Split([char]1)
            [ordered]@{ from = $p[0]; to = $p[1]; kind = $p[2]; n = $edges[$_] }
        })
    $map["sdk"] = @($headers.Keys | Sort-Object -Property @{ Expression = { $headers[$_] }; Descending = $true }, @{ Expression = { $_ } } | Select-Object -First $script:MaxHeaders | ForEach-Object { [ordered]@{ header = $_; n = $headers[$_] } })
    return $map
}
