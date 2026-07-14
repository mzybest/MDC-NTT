@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0.."

set "PART=%~1"
if "%PART%"=="" set "PART=xc7a200tsbg484-1"
set "PERIOD=%~2"
if "%PERIOD%"=="" set "PERIOD=10.0"
set "REQUESTED=%~3"
if "%REQUESTED%"=="" set "REQUESTED=all"

set "VIVADO_CMD=vivado"
where vivado >nul 2>nul
if errorlevel 1 (
  if exist "D:\Vivado\2022.2\bin\vivado.bat" (
    set "VIVADO_CMD=D:\Vivado\2022.2\bin\vivado.bat"
  ) else (
    echo ERROR: Vivado was not found in PATH or D:\Vivado\2022.2\bin.
    exit /b 1
  )
)

set "SWEEP_ROOT=reports\directive_sweep"
if not exist "%SWEEP_ROOT%" mkdir "%SWEEP_ROOT%"

git branch --show-current > "%SWEEP_ROOT%\git_branch.txt"
git rev-parse HEAD > "%SWEEP_ROOT%\git_commit.txt"
git status --short > "%SWEEP_ROOT%\git_status_before.txt"
powershell.exe -NoProfile -Command "Get-ChildItem rtl -Filter *.sv | Sort-Object Name | ForEach-Object { $h = Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName; '{0}  {1}' -f $h.Hash, $_.Name }" > "%SWEEP_ROOT%\rtl_hash_before.txt"

set "EXPERIMENTS=e00_baseline e01_all_explore e02_extra_timing_aggressive e03_early_block_explore e04_wirelength_higher_delay e05_spread_low_explore e06_spread_medium_fanout e07_netdelay_no_relax e08_postroute_explore e09_remap_aggressive_post e10_timing_fanout_post e11_wirelength_post"
if /I not "%REQUESTED%"=="all" set "EXPERIMENTS=%REQUESTED%"

set "ANY_FAILED=0"
for %%E in (%EXPERIMENTS%) do (
  if not exist "%SWEEP_ROOT%\%%E" mkdir "%SWEEP_ROOT%\%%E"
  echo ============================================================
  echo Running directive experiment %%E
  echo ============================================================
  call "!VIVADO_CMD!" -mode batch ^
    -log "%SWEEP_ROOT%\%%E\vivado.log" ^
    -journal "%SWEEP_ROOT%\%%E\vivado.jou" ^
    -source scripts/run_impl_directive_sweep.tcl ^
    -tclargs "%PART%" "%PERIOD%" "%%E"
  if errorlevel 1 (
    echo ERROR: experiment %%E failed. See its vivado.log and FAILED.txt.
    set "ANY_FAILED=1"
  )
)

powershell.exe -NoProfile -Command "Get-ChildItem rtl -Filter *.sv | Sort-Object Name | ForEach-Object { $h = Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName; '{0}  {1}' -f $h.Hash, $_.Name }" > "%SWEEP_ROOT%\rtl_hash_after.txt"
git status --short > "%SWEEP_ROOT%\git_status_after.txt"
fc /b "%SWEEP_ROOT%\rtl_hash_before.txt" "%SWEEP_ROOT%\rtl_hash_after.txt" > "%SWEEP_ROOT%\rtl_hash_compare.txt"
if errorlevel 1 (
  echo ERROR: rtl/*.sv SHA256 changed during the sweep.
  exit /b 2
)

if "%ANY_FAILED%"=="1" exit /b 1
echo Directive sweep complete. RTL SHA256 files are identical.
exit /b 0
