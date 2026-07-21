@echo off
setlocal

cd /d "%~dp0\.."
set "QUESTA_BIN=D:\modeltech64_2020.4\win64"
set "WORK=questa_work_batch_wavefront"
set "LOG_DIR=reports\batch_wavefront_scheduler"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
python scripts\batch_wavefront_scheduler_model.py --n 16 --jobs 30 --buffers 1 2 3 > "%LOG_DIR%\model_n16_jobs30.log"
if errorlevel 1 exit /b 1
python scripts\batch_wavefront_scheduler_model.py --n 4096 --jobs 60 --buffers 1 2 3 > "%LOG_DIR%\model_n4096_jobs60.log"
if errorlevel 1 exit /b 1
python scripts\batch_wavefront_scheduler_model.py --n 4096 --jobs 60 --buffers 3 --result-latency 4318 > "%LOG_DIR%\model_n4096_jobs60_scheduler_boundary.log"
if errorlevel 1 exit /b 1
python scripts\gen_batch_wavefront_vectors.py --jobs 6
if errorlevel 1 exit /b 1

if not exist "%WORK%" "%QUESTA_BIN%\vlib.exe" "%WORK%"
"%QUESTA_BIN%\vlog.exe" -sv -work "%WORK%" ^
  rtl\params_pkg.sv rtl\mod_add.sv rtl\mod_sub.sv ^
  rtl\delay_line.sv rtl\delay_memory.sv ^
  rtl\mont_mul.sv rtl\intmul_64x64_24x17.sv rtl\wlmont_round16.sv ^
  rtl\mont_mul_wl.sv rtl\mont_mul_select.sv rtl\gs_butterfly.sv ^
  rtl\twiddle_rom.sv rtl\twiddle_rom_stage.sv rtl\psi_rom.sv ^
  rtl\mdc_reorder_context.sv rtl\mdc_stage_dualctx.sv ^
  rtl\gs_mdc_core_dualctx.sv rtl\pointwise_mul.sv ^
  rtl\batch_frame_scheduler.sv rtl\batch_sdp_ram.sv ^
  rtl\poly_mul_top_batch_wavefront.sv ^
  sim\tb_batch_frame_scheduler.sv ^
  sim\tb_poly_mul_top_batch_wavefront.sv
if errorlevel 1 exit /b 1

"%QUESTA_BIN%\vsim.exe" -c -lib "%WORK%" tb_batch_frame_scheduler ^
  -l "%LOG_DIR%\tb_batch_frame_scheduler.log" -do "run -all; quit -f"
if errorlevel 1 exit /b 1
findstr /c:"tb_batch_frame_scheduler PASS" "%LOG_DIR%\tb_batch_frame_scheduler.log" >nul
if errorlevel 1 exit /b 1

"%QUESTA_BIN%\vsim.exe" -c -lib "%WORK%" tb_poly_mul_top_batch_wavefront ^
  -l "%LOG_DIR%\tb_poly_mul_top_batch_wavefront.log" -do "run -all; quit -f"
if errorlevel 1 exit /b 1
findstr /c:"tb_poly_mul_top_batch_wavefront PASS" "%LOG_DIR%\tb_poly_mul_top_batch_wavefront.log" >nul
if errorlevel 1 exit /b 1

echo Batch wavefront regression PASS
exit /b 0