@echo off
setlocal
cd /d "%~dp0.."
set "ORIGINAL_ROOT=%CD%"

set "VIVADO_CMD=vivado"
where vivado >nul 2>nul
if errorlevel 1 (
  if exist "D:\Vivado\2022.2\bin\vivado.bat" (
    set "VIVADO_CMD=D:\Vivado\2022.2\bin\vivado.bat"
  ) else (
    echo ERROR: vivado was not found in PATH or D:\Vivado\2022.2\bin.
    echo Run this script from a Vivado command prompt or update VIVADO_CMD.
    exit /b 1
  )
)

rem Vivado 2022.2 can fail internally when the repository path contains
rem non-ASCII characters. Use an available temporary ASCII drive when possible.
set "SYNTH_DRIVE=V:"
set "USING_SYNTH_DRIVE=0"
if not exist "%SYNTH_DRIVE%\" (
  subst %SYNTH_DRIVE% "%ORIGINAL_ROOT%" >nul 2>nul
  if not errorlevel 1 (
    set "USING_SYNTH_DRIVE=1"
    cd /d "%SYNTH_DRIVE%\"
  )
)

call "%VIVADO_CMD%" -mode batch -source scripts/run_synth.tcl -tclargs %*
set "SYNTH_RESULT=%errorlevel%"

if "%USING_SYNTH_DRIVE%"=="1" (
  cd /d "%ORIGINAL_ROOT%"
  subst %SYNTH_DRIVE% /d >nul 2>nul
)

exit /b %SYNTH_RESULT%
