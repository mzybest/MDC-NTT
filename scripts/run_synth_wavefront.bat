@echo off
setlocal
cd /d "%~dp0\.."

set "VIVADO_CMD=vivado"
where vivado >nul 2>nul
if errorlevel 1 set "VIVADO_CMD=D:\Vivado\2022.2\bin\vivado.bat"
if not exist "D:\Vivado\2022.2\bin\vivado.bat" where vivado >nul 2>nul || exit /b 1

if not exist "reports\dual_context_wavefront\synth" mkdir "reports\dual_context_wavefront\synth"
call "%VIVADO_CMD%" -mode batch ^
  -log reports\dual_context_wavefront\synth\vivado.log ^
  -journal reports\dual_context_wavefront\synth\vivado.jou ^
  -source scripts\run_synth_wavefront.tcl ^
  -tclargs xc7a200tsbg484-1 10.0
exit /b %errorlevel%
