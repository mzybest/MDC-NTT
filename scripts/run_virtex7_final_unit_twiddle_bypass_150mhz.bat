@echo off
setlocal
cd /d "%~dp0\.."
set "VIVADO=D:\Vivado\2026.1\Vivado\bin\vivado.bat"
set "PART=xc7vx330tffg1157-1"
set "REPORT_ROOT=final_unit_twiddle_bypass/virtex7_v2026_1"

call "%VIVADO%" -mode batch -source scripts/run_synth_dual_forward_dsp_reduction.tcl -tclargs combined_unit_twiddle %PART% 6.667 %REPORT_ROOT%/synth_150mhz
if errorlevel 1 exit /b 1
call "%VIVADO%" -mode batch -source scripts/run_impl_dual_forward_dsp_reduction.tcl -tclargs %REPORT_ROOT%/synth_150mhz %REPORT_ROOT%/impl_150mhz
exit /b %errorlevel%

