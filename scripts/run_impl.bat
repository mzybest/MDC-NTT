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
set "IMPL_DRIVE=V:"
set "USING_IMPL_DRIVE=0"
if not exist "%IMPL_DRIVE%\" (
  subst %IMPL_DRIVE% "%ORIGINAL_ROOT%" >nul 2>nul
  if not errorlevel 1 (
    set "USING_IMPL_DRIVE=1"
    cd /d "%IMPL_DRIVE%\"
  )
)

call "%VIVADO_CMD%" -mode batch -source scripts/run_impl.tcl -tclargs %*
set "IMPL_RESULT=%errorlevel%"

if "%USING_IMPL_DRIVE%"=="1" (
  cd /d "%ORIGINAL_ROOT%"
  subst %IMPL_DRIVE% /d >nul 2>nul
)

exit /b %IMPL_RESULT%
