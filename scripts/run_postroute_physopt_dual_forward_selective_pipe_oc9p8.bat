@echo off
setlocal
set "REPO_ROOT=%~dp0.."
set "VIVADO=D:\Vivado\2022.2\bin\vivado.bat"
set "REPORT_DIR=%REPO_ROOT%\reports\dual_forward_bfu_selective_pipe\postroute_physopt_explore_oc9p8"
if not exist "%VIVADO%" exit /b 1
if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%"
pushd "%REPO_ROOT%"
call "%VIVADO%" -mode batch ^
  -source scripts\run_postroute_physopt_dual_forward_selective_pipe_oc9p8.tcl ^
  -log "%REPORT_DIR%\vivado.log" ^
  -journal "%REPORT_DIR%\vivado.jou"
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%
