@echo off
setlocal

cd /d "%~dp0\.."
set "QUESTA_BIN=D:\modeltech64_2020.4\win64"
set "WORK=questa_work_twiddle_bram"
set "LOG_DIR=reports\twiddle_bram_experiment\sim"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
if not exist "%WORK%" "%QUESTA_BIN%\vlib.exe" "%WORK%"

"%QUESTA_BIN%\vlog.exe" -sv -work "%WORK%" ^
  rtl\params_pkg.sv rtl\mod_add.sv rtl\mod_sub.sv ^
  rtl\delay_line.sv rtl\delay_memory.sv ^
  rtl\mont_mul.sv rtl\intmul_64x64_24x17.sv rtl\wlmont_round16.sv ^
  rtl\mont_mul_wl.sv rtl\mont_mul_select.sv rtl\gs_butterfly.sv ^
  rtl\twiddle_rom.sv rtl\twiddle_rom_stage.sv rtl\psi_rom.sv ^
  rtl\mdc_stage.sv rtl\gs_mdc_core.sv rtl\dual_port_ram.sv ^
  rtl\pointwise_mul.sv rtl\poly_mul_top.sv ^
  sim\tb_twiddle_rom_stage.sv sim\tb_twiddle_prefetch_equiv.sv ^
  sim\tb_mont_mul_wl.sv sim\tb_delay_memory.sv sim\tb_gs_butterfly.sv ^
  sim\tb_gs_mdc_core.sv sim\tb_gs_mdc_core_roundtrip.sv ^
  sim\tb_poly_mul_top.sv sim\tb_poly_mul_top_phase_cycles.sv
if errorlevel 1 exit /b 1

for %%T in (tb_twiddle_rom_stage tb_twiddle_prefetch_equiv tb_mont_mul_wl tb_delay_memory tb_gs_butterfly tb_gs_mdc_core tb_gs_mdc_core_roundtrip tb_poly_mul_top tb_poly_mul_top_phase_cycles) do (
  "%QUESTA_BIN%\vsim.exe" -c -lib "%WORK%" %%T -l "%LOG_DIR%\%%T.log" -do "run -all; quit -f"
  if errorlevel 1 exit /b 1
  findstr /c:"%%T PASS" "%LOG_DIR%\%%T.log" >nul
  if errorlevel 1 (
    echo Missing PASS marker for %%T
    exit /b 1
  )
)

"%QUESTA_BIN%\vsim.exe" -c -lib "%WORK%" tb_poly_mul_top ^
  -gUSE_STAGE_LOCAL_TWIDDLE=0 ^
  -l "%LOG_DIR%\tb_poly_mul_top_legacy_twiddle.log" ^
  -do "run -all; quit -f"
if errorlevel 1 exit /b 1
findstr /c:"tb_poly_mul_top PASS" "%LOG_DIR%\tb_poly_mul_top_legacy_twiddle.log" >nul
if errorlevel 1 exit /b 1

echo Twiddle BRAM regression PASS
exit /b 0
