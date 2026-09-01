@echo off
setlocal

cd /d "%~dp0\.."
set "QUESTA_BIN=D:\modeltech64_2020.4\win64"
set "WORK=questa_work_dual_forward_dsp"
set "LOG_DIR=reports\dual_forward_dsp_reduction\natural_ab_dual_loader\sim"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

call scripts\run_dual_forward_dsp_reduction_regression.bat
if errorlevel 1 exit /b 1

python scripts\natural_ab_mapping_model.py > "%LOG_DIR%\mapping_n16.txt"
if errorlevel 1 exit /b 1
findstr /c:"N16_MAPPING_CHECK=PASS" "%LOG_DIR%\mapping_n16.txt" >nul
if errorlevel 1 exit /b 1

"%QUESTA_BIN%\vlog.exe" -sv -work "%WORK%" ^
  sim\tb_poly_mul_top_dual_forward_natural_ab.sv ^
  -l "%LOG_DIR%\vlog_natural_ab.log"
if errorlevel 1 exit /b 1

"%QUESTA_BIN%\vsim.exe" -c -lib "%WORK%" ^
  tb_poly_mul_top_dual_forward_natural_ab ^
  -l "%LOG_DIR%\tb_natural_ab.log" ^
  -do "run -all; quit -f"
if errorlevel 1 exit /b 1

findstr /c:"tb_poly_mul_top_dual_forward_natural_ab PASS" ^
  "%LOG_DIR%\tb_natural_ab.log" >nul
if errorlevel 1 exit /b 1

echo Natural A/B dual-loader regression PASS
exit /b 0
