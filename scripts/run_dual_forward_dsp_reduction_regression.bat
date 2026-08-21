@echo off
setlocal

cd /d "%~dp0\.."
set "QUESTA_BIN=D:\modeltech64_2020.4\win64"
set "WORK=questa_work_dual_forward_dsp"
set "LOG_DIR=reports\dual_forward_dsp_reduction\sim"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
python scripts\gen_psi.py > "%LOG_DIR%\gen_psi.log"
if errorlevel 1 exit /b 1
python scripts\validate_fused_post_factors.py > "%LOG_DIR%\validate_factors.log"
if errorlevel 1 exit /b 1
findstr /c:"FUSED_POST_FACTOR_VALIDATION=PASS" "%LOG_DIR%\validate_factors.log" >nul
if errorlevel 1 exit /b 1
python scripts\gen_twiddle_ntt_only.py > "%LOG_DIR%\gen_twiddle_ntt_only.log"
if errorlevel 1 exit /b 1

if not exist "%WORK%" "%QUESTA_BIN%\vlib.exe" "%WORK%"
"%QUESTA_BIN%\vlog.exe" -sv -work "%WORK%" ^
  rtl\params_pkg.sv rtl\mod_add.sv rtl\mod_sub.sv ^
  rtl\delay_line.sv rtl\delay_memory.sv ^
  rtl\mont_mul.sv rtl\intmul_64x64_24x17.sv rtl\wlmont_round16.sv ^
  rtl\mont_mul_wl.sv rtl\mont_mul_select.sv rtl\gs_butterfly.sv ^
  rtl\twiddle_rom.sv rtl\twiddle_rom_stage.sv ^
  rtl\twiddle_rom_stage_ntt.sv rtl\psi_rom.sv rtl\psi_post_rom.sv ^
  rtl\mdc_stage.sv rtl\gs_mdc_core.sv rtl\gs_mdc_core_ntt_only.sv ^
  rtl\dual_port_ram.sv rtl\pointwise_mul.sv rtl\poly_mul_top.sv ^
  rtl\mdc_reorder_context.sv rtl\mdc_stage_dualctx.sv ^
  rtl\gs_mdc_core_dualctx.sv rtl\poly_mul_top_wavefront.sv ^
  rtl\poly_mul_top_dual_forward.sv ^
  sim\tb_mont_mul_wl.sv sim\tb_gs_butterfly.sv sim\tb_gs_mdc_core.sv ^
  sim\tb_gs_mdc_core_ntt_only.sv sim\tb_poly_mul_top_wavefront.sv ^
  sim\tb_poly_mul_top_dual_forward.sv
if errorlevel 1 exit /b 1

for %%T in (tb_mont_mul_wl tb_gs_butterfly tb_gs_mdc_core tb_gs_mdc_core_ntt_only tb_poly_mul_top_wavefront) do (
  "%QUESTA_BIN%\vsim.exe" -c -lib "%WORK%" %%T ^
    -l "%LOG_DIR%\%%T.log" -do "run -all; quit -f"
  if errorlevel 1 exit /b 1
  findstr /c:"%%T PASS" "%LOG_DIR%\%%T.log" >nul
  if errorlevel 1 exit /b 1
)

call :run_bypass_test tb_gs_butterfly BYPASS_TWIDDLE_MUL
if errorlevel 1 exit /b 1
call :run_bypass_test tb_gs_mdc_core USE_FINAL_UNIT_TWIDDLE_BYPASS
if errorlevel 1 exit /b 1
call :run_bypass_test tb_gs_mdc_core_ntt_only USE_FINAL_UNIT_TWIDDLE_BYPASS
if errorlevel 1 exit /b 1

call :run_config baseline 0 0 0
if errorlevel 1 exit /b 1
call :run_config load_pre 1 0 0
if errorlevel 1 exit /b 1
call :run_config fused_post 0 1 0
if errorlevel 1 exit /b 1
call :run_config combined 1 1 0
if errorlevel 1 exit /b 1
call :run_config combined_unit_twiddle 1 1 1
if errorlevel 1 exit /b 1

echo Dual-forward DSP-reduction regression PASS
exit /b 0

:run_bypass_test
"%QUESTA_BIN%\vsim.exe" -c -lib "%WORK%" -g%2=1 %1 ^
  -l "%LOG_DIR%\%1_unit_twiddle.log" -do "run -all; quit -f"
if errorlevel 1 exit /b 1
findstr /c:"%1 PASS" "%LOG_DIR%\%1_unit_twiddle.log" >nul
if errorlevel 1 exit /b 1
exit /b 0

:run_config
"%QUESTA_BIN%\vsim.exe" -c -lib "%WORK%" ^
  -gUSE_LOAD_PREPROCESS=%2 -gFUSE_INTT_SCALE_IN_POST=%3 -gUSE_FINAL_UNIT_TWIDDLE_BYPASS=%4 ^
  tb_poly_mul_top_dual_forward -l "%LOG_DIR%\tb_%1.log" ^
  -do "run -all; quit -f"
if errorlevel 1 exit /b 1
findstr /c:"DSP_REDUCTION_CONFIG load_pre=%2 fused_post=%3 unit_twiddle=%4" "%LOG_DIR%\tb_%1.log" >nul
if errorlevel 1 exit /b 1
findstr /c:"tb_poly_mul_top_dual_forward PASS" "%LOG_DIR%\tb_%1.log" >nul
if errorlevel 1 exit /b 1
exit /b 0
