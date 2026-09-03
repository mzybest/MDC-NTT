@echo off
setlocal

cd /d "%~dp0\.."
set "QUESTA_BIN=D:\modeltech64_2020.4\win64"
set "WORK=questa_work_q64_core_control"
set "LOG_DIR=reports\dual_forward_dsp_reduction\q64_core_control_localization\sim"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

python scripts\gen_psi.py > "%LOG_DIR%\gen_psi.log"
if errorlevel 1 exit /b 1
python scripts\validate_fused_post_factors.py > "%LOG_DIR%\validate_factors.log"
if errorlevel 1 exit /b 1
findstr /c:"FUSED_POST_FACTOR_VALIDATION=PASS" "%LOG_DIR%\validate_factors.log" >nul
if errorlevel 1 exit /b 1
python scripts\gen_twiddle_ntt_only.py > "%LOG_DIR%\gen_twiddle_ntt_only.log"
if errorlevel 1 exit /b 1
python scripts\natural_ab_mapping_model.py > "%LOG_DIR%\mapping_n16.txt"
if errorlevel 1 exit /b 1
findstr /c:"N16_MAPPING_CHECK=PASS" "%LOG_DIR%\mapping_n16.txt" >nul
if errorlevel 1 exit /b 1

if not exist "%WORK%" "%QUESTA_BIN%\vlib.exe" "%WORK%"
"%QUESTA_BIN%\vlog.exe" -sv -work "%WORK%" ^
  rtl\params_pkg.sv rtl\mod_add.sv rtl\mod_sub.sv ^
  rtl\delay_line.sv rtl\delay_memory.sv ^
  rtl\mont_mul.sv rtl\intmul_64x64_24x17.sv rtl\wlmont_round16.sv ^
  rtl\mont_mul_wl.sv rtl\mont_mul_select.sv rtl\gs_butterfly.sv ^
  rtl\peripheral_mont_pool.sv ^
  rtl\twiddle_rom.sv rtl\twiddle_rom_stage.sv ^
  rtl\twiddle_rom_stage_ntt.sv rtl\psi_rom.sv rtl\psi_post_rom.sv ^
  rtl\mdc_stage.sv rtl\gs_mdc_core.sv rtl\gs_mdc_core_ntt_only.sv ^
  rtl\dual_port_ram.sv rtl\top_data_bram.sv rtl\pointwise_mul.sv rtl\poly_mul_top.sv ^
  rtl\mdc_reorder_context.sv rtl\mdc_stage_dualctx.sv ^
  rtl\gs_mdc_core_dualctx.sv rtl\poly_mul_top_wavefront.sv ^
  rtl\poly_mul_top_dual_forward.sv ^
  sim\tb_mont_mul_wl.sv sim\tb_gs_butterfly.sv sim\tb_gs_mdc_core.sv ^
  sim\tb_gs_mdc_core_ntt_only.sv sim\tb_poly_mul_top_wavefront.sv ^
  sim\tb_poly_mul_top_dual_forward.sv sim\tb_top_data_bram.sv ^
  sim\tb_poly_mul_top_dual_forward_natural_ab.sv ^
  -l "%LOG_DIR%\vlog.log"
if errorlevel 1 exit /b 1

for %%T in (tb_top_data_bram tb_mont_mul_wl tb_gs_butterfly tb_gs_mdc_core tb_gs_mdc_core_ntt_only tb_poly_mul_top_wavefront) do (
  "%QUESTA_BIN%\vsim.exe" -c -lib "%WORK%" %%T ^
    -l "%LOG_DIR%\%%T.log" -do "run -all; quit -f"
  if errorlevel 1 exit /b 1
  findstr /c:"%%T PASS" "%LOG_DIR%\%%T.log" >nul
  if errorlevel 1 exit /b 1
)

"%QUESTA_BIN%\vsim.exe" -c -lib "%WORK%" ^
  -gUSE_LOAD_PREPROCESS=0 -gFUSE_INTT_SCALE_IN_POST=1 ^
  -gUSE_FINAL_UNIT_TWIDDLE_BYPASS=1 -gUSE_TOP_DATA_BRAM=1 ^
  -gUSE_SHARED_PERIPH_MONT=1 tb_poly_mul_top_dual_forward ^
  -l "%LOG_DIR%\tb_dual_forward_bram_shared.log" -do "run -all; quit -f"
if errorlevel 1 exit /b 1
findstr /c:"tb_poly_mul_top_dual_forward PASS" "%LOG_DIR%\tb_dual_forward_bram_shared.log" >nul
if errorlevel 1 exit /b 1

"%QUESTA_BIN%\vsim.exe" -c -lib "%WORK%" ^
  tb_poly_mul_top_dual_forward_natural_ab ^
  -l "%LOG_DIR%\tb_natural_ab.log" -do "run -all; quit -f"
if errorlevel 1 exit /b 1
findstr /c:"tb_poly_mul_top_dual_forward_natural_ab PASS" "%LOG_DIR%\tb_natural_ab.log" >nul
if errorlevel 1 exit /b 1

echo QW64 core-control localization regression PASS
exit /b 0
