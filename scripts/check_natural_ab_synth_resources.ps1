param(
    [Parameter(Mandatory = $true)]
    [string]$ReportPath,
    [int]$ExpectedBram = 59,
    [int]$ExpectedDsp = 520
)

$text = Get-Content -Raw -LiteralPath $ReportPath
$bramMatch = [regex]::Match(
    $text,
    '(?m)^\|\s*Block RAM Tile\s*\|\s*([0-9]+)\s*\|'
)
$dspMatch = [regex]::Match(
    $text,
    '(?m)^\|\s*DSP48E1\s*\|\s*([0-9]+)\s*\|'
)

if (-not $bramMatch.Success -or -not $dspMatch.Success) {
    Write-Error "Could not parse BRAM/DSP from $ReportPath"
    exit 2
}

$bram = [int]$bramMatch.Groups[1].Value
$dsp = [int]$dspMatch.Groups[1].Value
Write-Host "SYNTH_RESOURCE_GATE BRAM=$bram DSP=$dsp"

if ($bram -ne $ExpectedBram -or $dsp -ne $ExpectedDsp) {
    Write-Error ("Resource gate failed: BRAM=$bram expected=$ExpectedBram, " +
                 "DSP=$dsp expected=$ExpectedDsp. Implementation will not run.")
    exit 3
}

exit 0
