@echo off
setlocal
cd /d "%~dp0\.."

set "VIVADO_CMD=vivado"
where vivado >nul 2>nul
if errorlevel 1 set "VIVADO_CMD=D:\Vivado\2022.2\bin\vivado.bat"
if not exist "D:\Vivado\2022.2\bin\vivado.bat" where vivado >nul 2>nul || exit /b 1

if not exist "reports\dual_forward_bfu_selective_pipe\impl_e06" mkdir "reports\dual_forward_bfu_selective_pipe\impl_e06"
call "%VIVADO_CMD%" -mode batch ^
  -log reports\dual_forward_bfu_selective_pipe\impl_e06\vivado.log ^
  -journal reports\dual_forward_bfu_selective_pipe\impl_e06\vivado.jou ^
  -source scripts\run_impl_dual_forward_selective_pipe_e06.tcl
exit /b %errorlevel%
