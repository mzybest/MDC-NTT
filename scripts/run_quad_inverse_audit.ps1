$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
$auditRoot = 'reports/quad_inverse_audit'
New-Item -ItemType Directory -Force -Path $auditRoot | Out-Null
$questaRoot = 'D:/modeltech64_2020.4/win64'
$auditLib = "$auditRoot/questa_work"
$rtlNames = @(
  'params_pkg', 'mod_add', 'mod_sub', 'delay_line', 'delay_memory',
  'mont_mul', 'intmul_64x64_24x17', 'wlmont_round16', 'mont_mul_wl',
  'mont_mul_select', 'gs_butterfly', 'peripheral_mont_pool',
  'twiddle_rom', 'twiddle_rom_stage', 'twiddle_rom_stage_ntt',
  'psi_rom', 'psi_post_rom', 'mdc_stage', 'gs_mdc_core',
  'gs_mdc_core_ntt_only', 'top_data_bram', 'pointwise_mul',
  'poly_mul_top_dual_forward'
)
$rtlSources = @($rtlNames | ForEach-Object { "rtl/$_.sv" })
$hashBefore = @($rtlSources | Get-FileHash -Algorithm SHA256)
if (!(Test-Path -LiteralPath $auditLib)) {
  & "$questaRoot/vlib.exe" $auditLib
  if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
}
& "$questaRoot/vlog.exe" -sv -work $auditLib @rtlSources `
  sim/tb_poly_mul_top_dual_forward_natural_ab.sv `
  sim/tb_quad_inverse_audit_monitor.sv -l "$auditRoot/vlog.log"
if ($LASTEXITCODE -ne 0) { throw 'vlog failed' }
& "$questaRoot/vsim.exe" -c -lib $auditLib `
  tb_poly_mul_top_dual_forward_natural_ab tb_quad_inverse_audit_monitor `
  -l "$auditRoot/questa.log" -do 'run -all; quit -f'
if ($LASTEXITCODE -ne 0) { throw 'vsim failed' }
if (!(Select-String -Path "$auditRoot/questa.log" -SimpleMatch 'tb_poly_mul_top_dual_forward_natural_ab PASS')) {
  throw 'Simulation PASS marker missing'
}
& python scripts/quad_inverse_layout_audit.py
if ($LASTEXITCODE -ne 0) { throw 'Trace/layout numerical audit failed' }
& python scripts/quad_inverse_cycle_model.py
if ($LASTEXITCODE -ne 0) { throw 'C2/value cycle model failed' }
& "$questaRoot/vlog.exe" -sv -work $auditLib sim/tb_gs_quad_inverse_audit.sv -l "$auditRoot/vlog_quad.log"
if ($LASTEXITCODE -ne 0) { throw 'Quad inverse vlog failed' }
& "$questaRoot/vsim.exe" -c -lib $auditLib tb_gs_quad_inverse_audit `
  -l "$auditRoot/questa_quad.log" -do 'run -all; quit -f'
if ($LASTEXITCODE -ne 0) { throw 'Quad inverse vsim failed' }
if (!(Select-String -Path "$auditRoot/questa_quad.log" -SimpleMatch 'tb_gs_quad_inverse_audit PASS')) {
  throw 'Quad inverse PASS marker missing'
}
$hashAfter = @($rtlSources | Get-FileHash -Algorithm SHA256)
if (Compare-Object ($hashBefore | ForEach-Object { $_.Hash }) ($hashAfter | ForEach-Object { $_.Hash })) {
  throw 'RTL hash changed during audit'
}
$hashAfter | Select-Object Path, Hash | ConvertTo-Json | Set-Content -Encoding UTF8 "$auditRoot/rtl_hashes.json"
Write-Output 'RTL_LAYOUT_AND_QUAD_DATAPATH_AUDIT=PASS; RTL_HASH_UNCHANGED=TRUE'
