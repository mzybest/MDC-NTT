param([string]$DestinationParent = '')
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
if (-not $DestinationParent) {
    $DestinationParent = Join-Path $sourceRoot ('reports\remote_transfer\' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$snapshotRoot = Join-Path $DestinationParent 'MDC-NTT'
if (Test-Path -LiteralPath $snapshotRoot) { throw "Destination already exists: $snapshotRoot" }
New-Item -ItemType Directory -Path $snapshotRoot | Out-Null
foreach ($sourceDirectory in @('rtl', 'mem', 'scripts', 'sim', 'docs')) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot $sourceDirectory) -Destination $snapshotRoot -Recurse
}
foreach ($sourceFile in @('README.md', 'TODO_NEXT.md', '.gitignore')) {
    if (Test-Path -LiteralPath (Join-Path $sourceRoot $sourceFile)) {
        Copy-Item -LiteralPath (Join-Path $sourceRoot $sourceFile) -Destination $snapshotRoot
    }
}
$manifest = foreach ($copiedFile in Get-ChildItem -LiteralPath $snapshotRoot -File -Recurse) {
    $relativeName = $copiedFile.FullName.Substring($snapshotRoot.Length + 1)
    $sourceHash = (Get-FileHash -LiteralPath (Join-Path $sourceRoot $relativeName) -Algorithm SHA256).Hash
    $copiedHash = (Get-FileHash -LiteralPath $copiedFile.FullName -Algorithm SHA256).Hash
    if ($sourceHash -ne $copiedHash) { throw "Hash mismatch: $relativeName" }
    [pscustomobject]@{ Path=$relativeName; Bytes=$copiedFile.Length; SHA256=$copiedHash }
}
$manifest | Export-Csv -LiteralPath (Join-Path $snapshotRoot 'SOURCE_SHA256.csv') -NoTypeInformation -Encoding utf8
$metadata = [ordered]@{
    created=(Get-Date -Format o)
    source=$sourceRoot
    git_head=(& git -C $sourceRoot rev-parse HEAD)
    git_branch=(& git -C $sourceRoot branch --show-current)
    includes_uncommitted_source=$true
    included_directories=@('rtl', 'mem', 'scripts', 'sim', 'docs')
    excluded=@('.git', '.Xil', 'questa_work*', 'reports', 'tmp', 'old root logs')
    file_count=@($manifest).Count
    total_bytes=($manifest | Measure-Object Bytes -Sum).Sum
    note='Source snapshot, not a Git clone. The original local project is unchanged.'
}
$metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $snapshotRoot 'SOURCE_SNAPSHOT.json') -Encoding utf8
[pscustomobject]@{ Snapshot=$snapshotRoot; Files=$metadata.file_count; Bytes=$metadata.total_bytes; SHA256Verified=$true }
