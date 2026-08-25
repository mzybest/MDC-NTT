@echo off
setlocal EnableExtensions
cd /d "%~dp0.."

set "VIVADO=D:\Vivado\2026.1\Vivado\bin\vivado.bat"
set "ROOT=reports\dual_forward_dsp_reduction\bram_ac_scratch_overconstraint\virtex7_v2026_1"
if not exist "%ROOT%" mkdir "%ROOT%"

git branch --show-current > "%ROOT%\git_branch.txt"
git rev-parse HEAD > "%ROOT%\git_commit.txt"
git status --short > "%ROOT%\git_status_before.txt"
powershell.exe -NoProfile -Command "Get-ChildItem rtl -Filter *.sv | Sort-Object Name | ForEach-Object { $h=Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName; '{0}  {1}' -f $h.Hash,$_.Name }" > "%ROOT%\rtl_hash_before.txt"

set "OUT=%ROOT%\150mhz"
if not exist "%OUT%" mkdir "%OUT%"
echo Running 150mhz target=6.667 ns implementation=6.400 ns
"%VIVADO%" -mode batch -log "%OUT%\vivado.log" -journal "%OUT%\vivado.jou" ^
  -source scripts\run_impl_bram_ac_overconstraint.tcl ^
  -tclargs bram_ac_scratch/virtex7_v2026_1/synth_150mhz ^
  bram_ac_scratch_overconstraint/virtex7_v2026_1/150mhz 6.667 6.400
if errorlevel 1 exit /b 1

set "OUT=%ROOT%\155mhz"
if not exist "%OUT%" mkdir "%OUT%"
echo Running 155mhz target=6.452 ns implementation=6.200 ns
"%VIVADO%" -mode batch -log "%OUT%\vivado.log" -journal "%OUT%\vivado.jou" ^
  -source scripts\run_impl_bram_ac_overconstraint.tcl ^
  -tclargs bram_ac_scratch/virtex7_v2026_1/synth_155mhz ^
  bram_ac_scratch_overconstraint/virtex7_v2026_1/155mhz 6.452 6.200
if errorlevel 1 exit /b 1

set "OUT=%ROOT%\160mhz"
if not exist "%OUT%" mkdir "%OUT%"
echo Running 160mhz target=6.250 ns implementation=6.000 ns
"%VIVADO%" -mode batch -log "%OUT%\vivado.log" -journal "%OUT%\vivado.jou" ^
  -source scripts\run_impl_bram_ac_overconstraint.tcl ^
  -tclargs bram_ac_scratch/virtex7_v2026_1/synth_160mhz ^
  bram_ac_scratch_overconstraint/virtex7_v2026_1/160mhz 6.250 6.000
if errorlevel 1 exit /b 1

powershell.exe -NoProfile -Command "Get-ChildItem rtl -Filter *.sv | Sort-Object Name | ForEach-Object { $h=Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName; '{0}  {1}' -f $h.Hash,$_.Name }" > "%ROOT%\rtl_hash_after.txt"
fc /b "%ROOT%\rtl_hash_before.txt" "%ROOT%\rtl_hash_after.txt" > "%ROOT%\rtl_hash_compare.txt"
if errorlevel 1 (
  echo ERROR: rtl/*.sv SHA256 changed during implementation.
  exit /b 2
)
git status --short > "%ROOT%\git_status_after.txt"
echo BRAM A/C overconstraint implementation sweep PASS
exit /b 0
