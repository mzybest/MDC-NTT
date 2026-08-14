@echo off
setlocal
set VIVADO=D:\Vivado\2026.1\Vivado\bin\vivado.bat
set PART=xc7vx330tffg1157-1

call "%VIVADO%" -mode batch -source scripts/run_synth_dual_forward_dsp_reduction.tcl -tclargs combined %PART% 10.000 virtex7_v2026_1/synth_100mhz
if errorlevel 1 exit /b 1
call "%VIVADO%" -mode batch -source scripts/run_impl_dual_forward_dsp_reduction.tcl -tclargs virtex7_v2026_1/synth_100mhz virtex7_v2026_1/impl_100mhz
if errorlevel 1 exit /b 1

call "%VIVADO%" -mode batch -source scripts/run_synth_dual_forward_dsp_reduction.tcl -tclargs combined %PART% 8.333 virtex7_v2026_1/synth_120mhz
if errorlevel 1 exit /b 1
call "%VIVADO%" -mode batch -source scripts/run_impl_dual_forward_dsp_reduction.tcl -tclargs virtex7_v2026_1/synth_120mhz virtex7_v2026_1/impl_120mhz
if errorlevel 1 exit /b 1

call "%VIVADO%" -mode batch -source scripts/run_synth_dual_forward_dsp_reduction.tcl -tclargs combined %PART% 6.667 virtex7_v2026_1/synth_150mhz
if errorlevel 1 exit /b 1
call "%VIVADO%" -mode batch -source scripts/run_impl_dual_forward_dsp_reduction.tcl -tclargs virtex7_v2026_1/synth_150mhz virtex7_v2026_1/impl_150mhz
exit /b %errorlevel%
