@echo off
setlocal

set "VIVADO=D:\Vivado\2026.1\Vivado\bin\vivado.bat"
set "PERIOD=%~1"
set "LABEL=%~2"

if "%PERIOD%"=="" set "PERIOD=6.250"
if "%LABEL%"=="" set "LABEL=160mhz"

call scripts\run_dual_forward_dsp_reduction_regression.bat
if errorlevel 1 exit /b 1

"%VIVADO%" -mode batch -source scripts\run_synth_dual_forward_dsp_reduction.tcl ^
  -tclargs bram_raw_pre xc7vx330tffg1157-1 %PERIOD% ^
  bram_ac_scratch/virtex7_v2026_1/synth_%LABEL%
if errorlevel 1 exit /b 1

"%VIVADO%" -mode batch -source scripts\run_impl_dual_forward_dsp_reduction.tcl ^
  -tclargs bram_ac_scratch/virtex7_v2026_1/synth_%LABEL% ^
  bram_ac_scratch/virtex7_v2026_1/impl_%LABEL%
if errorlevel 1 exit /b 1

echo Virtex-7 BRAM A/C scratch Scheme A PASS: %LABEL% (%PERIOD% ns)
exit /b 0
