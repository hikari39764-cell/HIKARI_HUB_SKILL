# HIKARI Production Hub: the agent's tool for reading and writing the hub database (Firestore).
# Keep this file ASCII-only (Windows PowerShell 5.1). Records are plain JSON files, UTF-8.
#
#   hub login                 take the member's key from the clipboard (copied on the hub site), check it, keep it on this PC
#   hub whoami                who the key belongs to, the project of this repository, the member's handle
#   hub sync [-All]           refresh <repo>/.hikari-hub/cache/<collection>/<id>.json (-All: every collection)
#   hub list <collection>     refresh one collection in the cache
#   hub get <collection>/<id> read one record (prints it, refreshes its cache file)
#   hub find <collection> <field> <value>   records whose field equals the value (prints them)
#   hub push                  send every <repo>/.hikari-hub/out/<collection>/<id>.json, then remove the sent files
#
# A pushed file is merged into the record (nested maps are merged, lists are replaced); the record is
# created when it does not exist. "_if_time": "<the _time read earlier>" makes the write fail when
# somebody else wrote the record in between. Keys that start with "_" are never stored.
#
# The key is the member's own sign-in (a refresh token). The database rules decide what it may do, so
# the agent can do exactly what the member can. It is stored encrypted for this Windows user in
# %USERPROFILE%\.hikari-hub\key.json and never inside a repository.
param(
    [Parameter(Position = 0)][string]$Command = "",
    [Parameter(Position = 1)][string]$A = "",
    [Parameter(Position = 2)][string]$B = "",
    [Parameter(Position = 3)][string]$C = "",
    [string]$Key = "",
    [string]$Project = "",
    [string]$Dir = "",
    [switch]$All
)

$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "lib/hub-common.ps1")
Add-Type -AssemblyName System.Web.Extensions
Add-Type -AssemblyName System.Security
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$serializer.MaxJsonLength = [int]::MaxValue
$hub = Read-Json (Join-Path $pluginRoot "hub.json")
$collections = Read-Json (Join-Path $pluginRoot "lib/collections.json")
$documents = "https://firestore.googleapis.com/v1/projects/" + $hub.firebase.projectId + "/databases/(default)/documents"
$keyPath = Join-Path $env:USERPROFILE ".hikari-hub\key.json"

function Say([string]$text) { Write-Out ($text + "`n") }
function Fail([string]$text) { Say $text; exit 1 }

# ---------- JSON ----------
function Read-Record([string]$path) {
    $text = (Read-Text $path).TrimStart([char]0xFEFF)
    return $serializer.DeserializeObject($text)
}

# The serializer escapes < > & ' as \u00xx; turn them back so the files stay readable.
function ConvertTo-JsonText($value) {
    $text = $serializer.Serialize($value)
    return [regex]::Replace($text, '(?<!\\)((?:\\\\)*)\\u00(3c|3e|26|27)', {
        param($m) $m.Groups[1].Value + [string][char][Convert]::ToInt32($m.Groups[2].Value, 16)
    }, "IgnoreCase")
}

# One field per line: easy to read and to grep.
function Format-Record($record) {
    $lines = New-Object Collections.ArrayList
    foreach ($name in $record.Keys) {
        [void]$lines.Add("  " + (ConvertTo-JsonText ([string]$name)) + ": " + (ConvertTo-JsonText $record[$name]))
    }
    return "{`n" + ($lines -join ",`n") + "`n}`n"
}

# ---------- Firestore values ----------
# Values are written straight into the container that holds them and never travel through function
# output: PowerShell wraps what a function returns, and the serializer cannot read wrapped values.

# Puts the Firestore form of $v into $target[$key], or appends it when $target is a list.
function Add-Typed($target, $key, $v) {
    $typed = @{}
    if ($null -eq $v) { $typed["nullValue"] = $null }
    elseif ($v -is [string]) { $typed["stringValue"] = $v }
    elseif ($v -is [bool]) { $typed["booleanValue"] = $v }
    elseif ($v -is [int] -or $v -is [long]) { $typed["integerValue"] = [string]$v }
    elseif ($v -is [decimal] -or $v -is [double] -or $v -is [single]) { $typed["doubleValue"] = [double]$v }
    elseif ($v -is [Collections.IDictionary]) {
        $fields = @{}
        Add-TypedFields $fields $v
        $typed["mapValue"] = @{ fields = $fields }
    } elseif ($v -is [Collections.IEnumerable]) {
        $values = [Collections.ArrayList]::new()
        foreach ($item in $v) { Add-Typed $values $null $item }
        $typed["arrayValue"] = @{ values = $values }
    } else { $typed["stringValue"] = [string]$v }
    if ($target -is [Collections.ArrayList]) { [void]$target.Add($typed) } else { $target[$key] = $typed }
}

# Keys that start with "_" (notes for this tool, such as _if_time) are never stored.
function Add-TypedFields($fields, $record) {
    foreach ($name in $record.Keys) {
        if (-not ([string]$name).StartsWith("_")) { Add-Typed $fields ([string]$name) $record[$name] }
    }
}

# Puts the plain form of the Firestore value $v into $target[$key], or appends it when $target is a list.
function Add-Plain($target, $key, $v) {
    $value = $null
    if ($v.ContainsKey("stringValue")) { $value = [string]$v["stringValue"] }
    elseif ($v.ContainsKey("booleanValue")) { $value = [bool]$v["booleanValue"] }
    elseif ($v.ContainsKey("integerValue")) { $value = [long]$v["integerValue"] }
    elseif ($v.ContainsKey("doubleValue")) { $value = [double]$v["doubleValue"] }
    elseif ($v.ContainsKey("timestampValue")) { $value = [string]$v["timestampValue"] }
    elseif ($v.ContainsKey("mapValue")) {
        $value = [Collections.Specialized.OrderedDictionary]::new()
        if ($v["mapValue"].ContainsKey("fields")) { Add-PlainFields $value $v["mapValue"]["fields"] }
    } elseif ($v.ContainsKey("arrayValue")) {
        $value = [Collections.ArrayList]::new()
        if ($v["arrayValue"].ContainsKey("values")) { foreach ($item in $v["arrayValue"]["values"]) { Add-Plain $value $null $item } }
    }
    if ($target -is [Collections.ArrayList]) { [void]$target.Add($value) } else { $target[$key] = $value }
}

function Add-PlainFields($record, $fields) {
    foreach ($name in @($fields.Keys | Sort-Object)) { Add-Plain $record ([string]$name) $fields[[string]$name] }
}

# A Firestore document as a plain record: "_time" (when it was last written) first, then its fields.
function ConvertFrom-Document($doc) {
    $record = [Collections.Specialized.OrderedDictionary]::new()
    $record["_time"] = [string]$doc["updateTime"]
    if ($doc.ContainsKey("fields")) { Add-PlainFields $record $doc["fields"] }
    return $record
}

function Get-DocumentId($doc) { return ([string]$doc["name"]).Split("/")[-1] }

# The update mask: every leaf of the pushed record, so nested maps are merged instead of replaced.
function Get-FieldPaths($record, [string]$prefix) {
    $paths = New-Object Collections.ArrayList
    foreach ($name in $record.Keys) {
        $segment = [string]$name
        if (-not $prefix -and $segment.StartsWith("_")) { continue }
        if ($segment -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { $segment = '`' + $segment.Replace('\', '\\').Replace('`', '\`') + '`' }
        $value = $record[$name]
        if ($value -is [Collections.IDictionary] -and $value.Count -gt 0) {
            foreach ($path in (Get-FieldPaths $value ($prefix + $segment + "."))) { [void]$paths.Add($path) }
        } else {
            [void]$paths.Add($prefix + $segment)
        }
    }
    return $paths
}

# ---------- HTTP ----------
function Invoke-Http([string]$method, [string]$url, [string]$body, [string]$token, [string]$contentType) {
    $request = [Net.HttpWebRequest]::Create($url)
    $request.Method = $method
    $request.Timeout = 30000
    $request.UserAgent = "hikari-hub"
    if ($token) { $request.Headers["Authorization"] = "Bearer " + $token }
    $response = $null
    try {
        if ($body) {
            $bytes = $utf8.GetBytes($body)
            $request.ContentType = $contentType
            $request.ContentLength = $bytes.Length
            $stream = $request.GetRequestStream()
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Close()
        }
        $response = $request.GetResponse()
    } catch {
        $problem = $_.Exception
        while ($problem -and -not ($problem -is [Net.WebException])) { $problem = $problem.InnerException }
        if (-not $problem -or -not $problem.Response) { return @{ status = 0; text = "" } }
        $response = $problem.Response
    }
    $reader = New-Object IO.StreamReader($response.GetResponseStream(), $utf8)
    $text = $reader.ReadToEnd()
    $reader.Close()
    $status = [int]$response.StatusCode
    $response.Close()
    return @{ status = $status; text = $text }
}

# "<status> <reason>" of a failed call, for the agent to read.
function Get-Problem($result) {
    if ($result.status -eq 0) { return "offline: cannot reach the hub (network). Nothing was lost; try again later." }
    $reason = ""
    try { $reason = [string]($serializer.DeserializeObject($result.text))["error"]["status"] } catch { }
    if ($result.status -eq 403) { return "denied: this person is not invited to the project, or the record is for the owner only." }
    if ($result.status -eq 401) { return "key_rejected: copy the key again on the hub site, then run 'hub login'." }
    if ($reason -eq "FAILED_PRECONDITION" -or $result.status -eq 409) { return "changed: somebody wrote this record first. Read it again (hub get), then decide." }
    return ("failed: " + $result.status + " " + $reason)
}

# ---------- the key ----------
function Protect-Text([string]$text) {
    return [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect($utf8.GetBytes($text), $null, "CurrentUser"))
}
function Unprotect-Text([string]$text) {
    return $utf8.GetString([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($text), $null, "CurrentUser"))
}
function Get-Now { return [long]([DateTime]::UtcNow - [DateTime]"1970-01-01").TotalSeconds }

# Trades the member's key for a one-hour sign-in and keeps both (encrypted for this Windows user).
function Update-Session([string]$refresh) {
    $result = Invoke-Http "POST" ("https://securetoken.googleapis.com/v1/token?key=" + $hub.firebase.apiKey) ("grant_type=refresh_token&refresh_token=" + [Uri]::EscapeDataString($refresh)) "" "application/x-www-form-urlencoded"
    if ($result.status -eq 0) { Fail (Get-Problem $result) }
    if ($result.status -ne 200) { Fail "key_rejected: the key is not valid (any more). Copy it again on the hub site (Members page), then run 'hub login'." }
    $answer = $serializer.DeserializeObject($result.text)
    $claims = [string]$answer["id_token"].Split(".")[1].Replace("-", "+").Replace("_", "/")
    $claims = $serializer.DeserializeObject($utf8.GetString([Convert]::FromBase64String($claims.PadRight($claims.Length + (4 - $claims.Length % 4) % 4, "="))))
    $session = @{ uid = [string]$answer["user_id"]; name = [string]$claims["name"]; token = [string]$answer["id_token"]; expires_at = (Get-Now) + [long]$answer["expires_in"] }
    $saved = @{ uid = $session.uid; name = $session.name; expires_at = $session.expires_at; key = (Protect-Text ([string]$answer["refresh_token"])); token = (Protect-Text $session.token) }
    [void][IO.Directory]::CreateDirectory((Split-Path -Path $keyPath -Parent))
    [IO.File]::WriteAllText($keyPath, $serializer.Serialize($saved), $utf8)
    return $session
}

function Get-Session {
    $saved = $null
    if (Test-Path -LiteralPath $keyPath) { $saved = Read-Record $keyPath }
    if (-not $saved -or -not $saved["key"]) { Fail "no_key: this PC has no hub key yet. Ask the person to press 'copy key' on the hub site (Members page), then run 'hub login'." }
    if ([long]$saved["expires_at"] -gt ((Get-Now) + 120)) {
        return @{ uid = [string]$saved["uid"]; name = [string]$saved["name"]; token = (Unprotect-Text ([string]$saved["token"])) }
    }
    return (Update-Session (Unprotect-Text ([string]$saved["key"])))
}

# ---------- the project of this repository ----------
function Get-Workspace {
    $root = Find-RepoRoot (Get-Location).Path
    $entry = $null
    if ($root) { $entry = Find-Project (Get-GitDir $root) }
    $id = $Project
    if (-not $id -and $entry) { $id = [string]$entry.id }
    if (-not $id) { Fail "no_project: this folder is not a repository of a hub project (see projects.json), and -Project was not given." }
    if ($id -notmatch '^[a-z0-9_-]{1,40}$') { Fail "no_project: a project id is lower-case letters, digits, - and _." }
    $local = ""
    if ($root -and ($entry -or $Project)) {
        $local = Join-Path $root ".hikari-hub"
        [void][IO.Directory]::CreateDirectory($local)
        # The working folder never goes into git: list it in the repository's own exclude file.
        $exclude = Join-Path (Get-CommonGitDir (Get-GitDir $root)) "info/exclude"
        if ((Read-Text $exclude) -notmatch '(?m)^\.hikari-hub/\s*$') {
            [void][IO.Directory]::CreateDirectory((Split-Path -Path $exclude -Parent))
            [IO.File]::AppendAllText($exclude, "`n.hikari-hub/`n", $utf8)
        }
    }
    return @{ id = $id; base = ($documents + "/projects/" + $id); local = $local }
}

function Save-Record([string]$folder, [string]$collection, $doc) {
    $id = Get-DocumentId $doc
    if ($id -notmatch '^[A-Za-z0-9._@-]+$') { return }
    $target = Join-Path (Join-Path $folder $collection) ($id + ".json")
    [void][IO.Directory]::CreateDirectory((Split-Path -Path $target -Parent))
    [IO.File]::WriteAllText($target, (Format-Record (ConvertFrom-Document $doc)), $utf8)
}

# Reads a whole collection, then replaces its folder (records deleted on the hub disappear here too).
function Sync-Collection($space, $session, [string]$folder, [string]$collection) {
    $docs = New-Object Collections.ArrayList
    $page = ""
    do {
        $url = $space.base + "/" + $collection + "?pageSize=300"
        if ($page) { $url += "&pageToken=" + [Uri]::EscapeDataString($page) }
        $result = Invoke-Http "GET" $url "" $session.token ""
        if ($result.status -ne 200) { Fail (Get-Problem $result) }
        $answer = $serializer.DeserializeObject($result.text)
        if ($answer.ContainsKey("documents")) { foreach ($doc in $answer["documents"]) { [void]$docs.Add($doc) } }
        $page = ""
        if ($answer.ContainsKey("nextPageToken")) { $page = [string]$answer["nextPageToken"] }
    } while ($page)
    $target = Join-Path $folder $collection
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    foreach ($doc in $docs) { Save-Record $folder $collection $doc }
    return $docs.Count
}

function Get-CacheFolder($space) {
    if ($Dir) { return $Dir }
    if (-not $space.local) { Fail "no_project: run this inside the project's repository (or give -Dir <folder>)." }
    return (Join-Path $space.local "cache")
}

# ---------- commands ----------
switch ($Command) {
    "login" {
        $text = $Key
        if (-not $text) { $text = [string](Get-Clipboard -Raw) }
        $text = $text.Trim()
        if ($text -notmatch '^hhk1\.(\S{20,})$') { Fail "no_key: the clipboard does not hold a hub key. Ask the person to press 'copy key' on the hub site (Members page), then run 'hub login' again." }
        $session = Update-Session $Matches[1]
        if (-not $Key) { cmd /c "echo off | clip" }
        Say ("connected: " + $session.name + " (uid " + $session.uid + ")")
    }
    "whoami" {
        $session = Get-Session
        Say ("name: " + $session.name)
        Say ("uid: " + $session.uid)
        # Only the owner (the e-mail named in the database rules) may read hub/owner; it holds nothing.
        $owner = Invoke-Http "GET" ($documents + "/hub/owner") "" $session.token ""
        if ($owner.status -eq 0) { Fail (Get-Problem $owner) }
        Say ("owner: " + ($owner.status -ne 403).ToString().ToLower())
        $space = Get-Workspace
        Say ("project: " + $space.id)
        Say ("page: " + (Get-ProjectUrl $space.id))
        $member = Invoke-Http "GET" ($space.base + "/members/" + $session.uid) "" $session.token ""
        if ($member.status -eq 200) { Say ("handle: " + [string]((ConvertFrom-Document ($serializer.DeserializeObject($member.text)))["handle"])) }
        elseif ($member.status -eq 404) { Say "handle: (not registered yet)" }
        else { Say (Get-Problem $member) }
    }
    "sync" {
        $session = Get-Session
        $space = Get-Workspace
        $folder = Get-CacheFolder $space
        $names = @($collections.all | Where-Object { $All -or ($collections.skip -notcontains $_) })
        if ($All) { $names += "files" }
        $counts = foreach ($name in $names) { $name + " " + (Sync-Collection $space $session $folder $name) }
        Say ("synced " + $space.id + " -> " + $folder)
        Say ($counts -join ", ")
    }
    "list" {
        if (-not $A) { Fail "usage: hub list <collection>" }
        $session = Get-Session
        $space = Get-Workspace
        Say ($A + " " + (Sync-Collection $space $session (Get-CacheFolder $space) $A))
    }
    "get" {
        if ($A -notmatch '^([a-z_]+)/([A-Za-z0-9._@-]+)$') { Fail "usage: hub get <collection>/<id>" }
        $session = Get-Session
        $space = Get-Workspace
        $result = Invoke-Http "GET" ($space.base + "/" + $A) "" $session.token ""
        if ($result.status -eq 404) { Fail ("not_found: " + $A) }
        if ($result.status -ne 200) { Fail (Get-Problem $result) }
        $doc = $serializer.DeserializeObject($result.text)
        if ($space.local -or $Dir) { Save-Record (Get-CacheFolder $space) $Matches[1] $doc }
        Write-Out (Format-Record (ConvertFrom-Document $doc))
    }
    "find" {
        if (-not $A -or -not $B) { Fail "usage: hub find <collection> <field> <value>" }
        $session = Get-Session
        $space = Get-Workspace
        $query = @{ structuredQuery = @{ from = @(@{ collectionId = $A }); limit = 100
                where = @{ fieldFilter = @{ field = @{ fieldPath = $B }; op = "EQUAL"; value = @{ stringValue = $C } } } } }
        $result = Invoke-Http "POST" ($space.base + ":runQuery") ($serializer.Serialize($query)) $session.token "application/json; charset=utf-8"
        if ($result.status -ne 200) { Fail (Get-Problem $result) }
        $found = 0
        foreach ($row in $serializer.DeserializeObject($result.text)) {
            if (-not $row.ContainsKey("document")) { continue }
            $found += 1
            if ($space.local -or $Dir) { Save-Record (Get-CacheFolder $space) $A $row["document"] }
            Say ("# " + $A + "/" + (Get-DocumentId $row["document"]))
            Write-Out (Format-Record (ConvertFrom-Document $row["document"]))
        }
        Say ("found " + $found)
    }
    "push" {
        $session = Get-Session
        $space = Get-Workspace
        if (-not $space.local) { Fail "no_project: run this inside the project's repository." }
        $out = Join-Path $space.local "out"
        $files = @()
        if (Test-Path -LiteralPath $out) { $files = @(Get-ChildItem -LiteralPath $out -Recurse -File -Filter "*.json" | Sort-Object FullName) }
        if (-not $files.Count) { Say "nothing to push"; exit 0 }
        $bad = 0
        foreach ($file in $files) {
            $collection = $file.Directory.Name
            $label = $collection + "/" + $file.BaseName
            if ($file.Directory.Parent.FullName -ne (Get-Item -LiteralPath $out).FullName -or $label -notmatch '^[a-z_]+/[A-Za-z0-9._@-]+$') {
                Say ("NG  " + $file.FullName + "  put files in .hikari-hub/out/<collection>/<id>.json"); $bad += 1; continue
            }
            $record = $null
            try { $record = Read-Record $file.FullName } catch { }
            if (-not ($record -is [Collections.IDictionary])) { Say ("NG  " + $label + "  the file is not a JSON object"); $bad += 1; continue }
            $query = @(Get-FieldPaths $record "" | ForEach-Object { "updateMask.fieldPaths=" + [Uri]::EscapeDataString($_) })
            if (-not $query.Count) { Say ("NG  " + $label + "  the file has no fields"); $bad += 1; continue }
            if ($record.ContainsKey("_if_time") -and $record["_if_time"]) { $query += "currentDocument.updateTime=" + [Uri]::EscapeDataString([string]$record["_if_time"]) }
            $fields = @{}
            Add-TypedFields $fields $record
            $body = $serializer.Serialize(@{ fields = $fields })
            $result = Invoke-Http "PATCH" ($space.base + "/" + $label + "?" + ($query -join "&")) $body $session.token "application/json; charset=utf-8"
            if ($result.status -eq 0) { Say (Get-Problem $result); Say "The files stay in .hikari-hub/out; run 'hub push' again later."; exit 1 }
            if ($result.status -ne 200) { Say ("NG  " + $label + "  " + (Get-Problem $result)); $bad += 1; continue }
            Save-Record (Join-Path $space.local "cache") $collection ($serializer.DeserializeObject($result.text))
            Remove-Item -LiteralPath $file.FullName -Force
            Say ("ok  " + $label)
        }
        if ($bad) { Say ($bad.ToString() + " file(s) were not sent. Fix or delete them in .hikari-hub/out, then push again."); exit 1 }
    }
    default {
        Say "usage: hub login | whoami | sync [-All] | list <collection> | get <collection>/<id> | find <collection> <field> <value> | push   (options: -Project <id>, -Dir <folder>)"
        if ($Command) { exit 1 }
    }
}
