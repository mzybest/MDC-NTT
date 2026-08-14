@echo off
setlocal
set VIVADO=D:\Vivado\2022.2\bin\vivado.bat
set PART=xc7a200tsbg484-1

call "%VIVADO%" -mode batch -source scripts/run_synth_dual_forward_dsp_reduction.tcl -tclargs load_pre %PART% 10.000 artix_synth/load_pre
if errorlevel 1 exit /b 1
call "%VIVADO%" -mode batch -source scripts/run_synth_dual_forward_dsp_reduction.tcl -tclargs fused_post %PART% 10.000 artix_synth/fused_post
if errorlevel 1 exit /b 1
call "%VIVADO%" -mode batch -source scripts/run_synth_dual_forward_dsp_reduction.tcl -tclargs combined %PART% 10.000 artix_synth/combined
if errorlevel 1 exit /b 1
call "%VIVADO%" -mode batch -source scripts/run_impl_dual_forward_dsp_reduction.tcl -tclargs artix_synth/combined artix_impl/combined_100mhz
exit /b %errorlevel%
