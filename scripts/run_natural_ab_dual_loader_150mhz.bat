@echo off
setlocal EnableExtensions

cd /d "%~dp0\.."
set "VIVADO=D:\Vivado\2026.1\Vivado\bin\vivado.bat"
set "PART=xc7vx485tffg1761-2"
set "ROOT=reports\dual_forward_dsp_reduction\natural_ab_dual_loader\xc7vx485t_150mhz"
set "SYNTH_SUBDIR=natural_ab_dual_loader/xc7vx485t_150mhz/synth"
set "IMPL_SUBDIR=natural_ab_dual_loader/xc7vx485t_150mhz/impl"

if not exist "%VIVADO%" (
  echo Missing Vivado launcher: %VIVADO%
  exit /b 1
)
if not exist "%ROOT%\synth" mkdir "%ROOT%\synth"
if not exist "%ROOT%\impl" mkdir "%ROOT%\impl"

git branch --show-current > "%ROOT%\git_branch.txt"
git rev-parse HEAD > "%ROOT%\git_commit.txt"
git status --short > "%ROOT%\git_status_before.txt"
powershell.exe -NoProfile -Command "Get-ChildItem rtl -Filter *.sv | Sort-Object Name | ForEach-Object { $h=Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName; '{0}  {1}' -f $h.Hash,$_.Name }" > "%ROOT%\rtl_hash_before.txt"

call "%VIVADO%" -mode batch ^
  -log "%ROOT%\synth\vivado_driver.log" ^
  -journal "%ROOT%\synth\vivado_driver.jou" ^
  -source scripts\run_synth_dual_forward_dsp_reduction.tcl ^
  -tclargs natural_ab_raw_pre_shared %PART% 6.667 %SYNTH_SUBDIR%
if errorlevel 1 exit /b 1

powershell.exe -NoProfile -ExecutionPolicy Bypass ^
  -File scripts\check_natural_ab_synth_resources.ps1 ^
  -ReportPath "%ROOT%\synth\utilization.rpt" ^
  -ExpectedBram 59 -ExpectedDsp 520
if errorlevel 1 exit /b 3

call "%VIVADO%" -mode batch ^
  -log "%ROOT%\impl\vivado_driver.log" ^
  -journal "%ROOT%\impl\vivado_driver.jou" ^
  -source scripts\run_impl_bram_ac_overconstraint.tcl ^
  -tclargs %SYNTH_SUBDIR% %IMPL_SUBDIR% 6.667 6.400
if errorlevel 1 exit /b 1

powershell.exe -NoProfile -Command "Get-ChildItem rtl -Filter *.sv | Sort-Object Name | ForEach-Object { $h=Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName; '{0}  {1}' -f $h.Hash,$_.Name }" > "%ROOT%\rtl_hash_after.txt"
fc /b "%ROOT%\rtl_hash_before.txt" "%ROOT%\rtl_hash_after.txt" > "%ROOT%\rtl_hash_compare.txt"
if errorlevel 1 (
  echo ERROR: rtl/*.sv SHA256 changed during synthesis or implementation.
  exit /b 2
)

git status --short > "%ROOT%\git_status_after.txt"
echo Natural A/B dual-loader XC7VX485T 150 MHz implementation PASS
exit /b 0
