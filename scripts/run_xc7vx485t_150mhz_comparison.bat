@echo off
setlocal EnableExtensions
cd /d "%~dp0.."

set "VIVADO=D:\Vivado\2026.1\Vivado\bin\vivado.bat"
set "PART=xc7vx485tffg1761-2"
set "TARGET=6.667"
set "IMPL=6.400"
set "ROOT=reports\proteus_xc7vx485t_150mhz"
if not exist "%ROOT%" mkdir "%ROOT%"

git branch --show-current > "%ROOT%\git_branch.txt"
git rev-parse HEAD > "%ROOT%\git_commit.txt"
git status --short > "%ROOT%\git_status_before.txt"
powershell.exe -NoProfile -Command "Get-ChildItem rtl -Filter *.sv | Sort-Object Name | ForEach-Object { $h=Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName; '{0}  {1}' -f $h.Hash,$_.Name }" > "%ROOT%\rtl_hash_before.txt"

for %%V in (full ntt_only dualctx) do (
  if not exist "%ROOT%\%%V" mkdir "%ROOT%\%%V"
  echo Running %%V on %PART% at 150 MHz
  call "%VIVADO%" -mode batch -log "%ROOT%\%%V\vivado.log" -journal "%ROOT%\%%V\vivado.jou" ^
    -source scripts\run_xc7vx485t_150mhz_comparison.tcl ^
    -tclargs %%V %PART% %TARGET% %IMPL% %%V
  if errorlevel 1 exit /b 1
)

powershell.exe -NoProfile -Command "Get-ChildItem rtl -Filter *.sv | Sort-Object Name | ForEach-Object { $h=Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName; '{0}  {1}' -f $h.Hash,$_.Name }" > "%ROOT%\rtl_hash_after.txt"
fc /b "%ROOT%\rtl_hash_before.txt" "%ROOT%\rtl_hash_after.txt" > "%ROOT%\rtl_hash_compare.txt"
if errorlevel 1 (
  echo ERROR: rtl/*.sv SHA256 changed during implementation.
  exit /b 2
)
git status --short > "%ROOT%\git_status_after.txt"
echo XC7VX485T 150 MHz comparison flow PASS
exit /b 0
