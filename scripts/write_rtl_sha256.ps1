param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$rows = Get-ChildItem rtl -Filter *.sv | Sort-Object Name | ForEach-Object {
    $stream = [System.IO.File]::OpenRead($_.FullName)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hash = ($sha.ComputeHash($stream) | ForEach-Object {
                $_.ToString('x2')
            }) -join ''
        } finally {
            $sha.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
    '{0}  {1}' -f $hash, $_.Name
}

$fullPath = [System.IO.Path]::GetFullPath($OutputPath)
[System.IO.Directory]::CreateDirectory(
    [System.IO.Path]::GetDirectoryName($fullPath)
) | Out-Null
[System.IO.File]::WriteAllLines(
    $fullPath, $rows, [System.Text.Encoding]::ASCII
)
