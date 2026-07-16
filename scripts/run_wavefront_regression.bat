@echo off
setlocal

cd /d "%~dp0\.."
set "QUESTA_BIN=D:\modeltech64_2020.4\win64"
set "WORK=questa_work_dualctx"
set "LOG_DIR=reports\dual_context_wavefront\sim"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
python scripts\dual_context_wavefront_model.py --n 16 --frames 4 > "%LOG_DIR%\cycle_model_n16.log"
if errorlevel 1 exit /b 1
python scripts\dual_context_wavefront_model.py --n 4096 --frames 4 > "%LOG_DIR%\cycle_model_n4096.log"
if errorlevel 1 exit /b 1

if not exist "%WORK%" "%QUESTA_BIN%\vlib.exe" "%WORK%"
"%QUESTA_BIN%\vlog.exe" -sv -work "%WORK%" ^
  rtl\params_pkg.sv rtl\mod_add.sv rtl\mod_sub.sv ^
  rtl\delay_line.sv rtl\delay_memory.sv ^
  rtl\mont_mul.sv rtl\intmul_64x64_24x17.sv rtl\wlmont_round16.sv ^
  rtl\mont_mul_wl.sv rtl\mont_mul_select.sv rtl\gs_butterfly.sv ^
  rtl\twiddle_rom.sv rtl\twiddle_rom_stage.sv rtl\psi_rom.sv ^
  rtl\mdc_stage.sv rtl\gs_mdc_core.sv rtl\dual_port_ram.sv ^
  rtl\pointwise_mul.sv rtl\poly_mul_top.sv ^
  rtl\mdc_reorder_context.sv rtl\mdc_stage_dualctx.sv ^
  rtl\gs_mdc_core_dualctx.sv rtl\poly_mul_top_wavefront.sv ^
  sim\tb_gs_mdc_core_dualctx.sv sim\tb_poly_mul_top_wavefront.sv
if errorlevel 1 exit /b 1

"%QUESTA_BIN%\vsim.exe" -c -lib "%WORK%" tb_gs_mdc_core_dualctx ^
  -l "%LOG_DIR%\tb_gs_mdc_core_dualctx.log" -do "run -all; quit -f"
if errorlevel 1 exit /b 1
findstr /c:"tb_gs_mdc_core_dualctx PASS" "%LOG_DIR%\tb_gs_mdc_core_dualctx.log" >nul
if errorlevel 1 exit /b 1

"%QUESTA_BIN%\vsim.exe" -c -lib "%WORK%" tb_poly_mul_top_wavefront ^
  -l "%LOG_DIR%\tb_poly_mul_top_wavefront.log" -do "run -all; quit -f"
if errorlevel 1 exit /b 1
findstr /c:"tb_poly_mul_top_wavefront PASS" "%LOG_DIR%\tb_poly_mul_top_wavefront.log" >nul
if errorlevel 1 exit /b 1

echo Dual-context wavefront regression PASS
exit /b 0
