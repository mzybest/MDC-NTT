@echo off
setlocal
call D:\Vivado\2022.2\bin\vivado.bat -mode batch -source scripts/run_postroute_physopt_dual_forward_dsp_reduction_oc9p8.tcl
exit /b %errorlevel%
