@echo off
setlocal

cd /d "%~dp0\.."
set "QUESTA_BIN=D:\modeltech64_2020.4\win64"
set "WORK=questa_work_dual_forward"
set "LOG_DIR=reports\dual_forward_core\sim"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
python scripts\gen_twiddle_ntt_only.py > "%LOG_DIR%\gen_twiddle_ntt_only.log"
if errorlevel 1 exit /b 1
findstr /c:"NTT_ONLY_TWIDDLE_GENERATION=PASS" "%LOG_DIR%\gen_twiddle_ntt_only.log" >nul
if errorlevel 1 exit /b 1

python scripts\dual_forward_core_feasibility.py --n 4096 ^
  --json reports\dual_forward_core_feasibility\model_n4096.json ^
  > "%LOG_DIR%\feasibility_model.log"
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
  rtl\dual_port_ram.sv rtl\pointwise_mul.sv rtl\poly_mul_top.sv ^
  rtl\mdc_reorder_context.sv rtl\mdc_stage_dualctx.sv ^
  rtl\gs_mdc_core_dualctx.sv rtl\poly_mul_top_wavefront.sv ^
  rtl\poly_mul_top_dual_forward.sv ^
  sim\tb_mont_mul_wl.sv sim\tb_gs_butterfly.sv sim\tb_gs_mdc_core.sv ^
  sim\tb_gs_mdc_core_ntt_only.sv sim\tb_poly_mul_top_wavefront.sv ^
  sim\tb_poly_mul_top_dual_forward.sv
if errorlevel 1 exit /b 1

for %%T in (tb_mont_mul_wl tb_gs_butterfly tb_gs_mdc_core tb_gs_mdc_core_ntt_only tb_poly_mul_top_wavefront tb_poly_mul_top_dual_forward) do (
  "%QUESTA_BIN%\vsim.exe" -c -lib "%WORK%" %%T ^
    -l "%LOG_DIR%\%%T.log" -do "run -all; quit -f"
  if errorlevel 1 exit /b 1
  findstr /c:"%%T PASS" "%LOG_DIR%\%%T.log" >nul
  if errorlevel 1 (
    echo Missing PASS marker for %%T
    exit /b 1
  )
)

echo Dual-forward core regression PASS
exit /b 0
