@echo off
setlocal

cd /d "%~dp0\.."
set "VIVADO=D:\Vivado\2026.1\Vivado\bin\vivado.bat"
set "PART=xc7vx485tffg1761-2"
set "SYNTH_DIR=peripheral_mont_pool/xc7vx485t_150mhz/synth"
set "IMPL_DIR=peripheral_mont_pool/xc7vx485t_150mhz/impl"

if not exist "%VIVADO%" (
  echo Missing Vivado launcher: %VIVADO%
  exit /b 1
)

call "%VIVADO%" -mode batch ^
  -source scripts/run_synth_dual_forward_dsp_reduction.tcl ^
  -tclargs bram_raw_pre_shared %PART% 6.667 %SYNTH_DIR%
if errorlevel 1 exit /b 1

call "%VIVADO%" -mode batch ^
  -source scripts/run_impl_bram_ac_overconstraint.tcl ^
  -tclargs %SYNTH_DIR% %IMPL_DIR% 6.667 6.400
if errorlevel 1 exit /b 1

echo XC7VX485T peripheral Montgomery pool 150 MHz PASS
exit /b 0
