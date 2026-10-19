@echo off
rem Cortex Terminal launcher for Windows (cmd.exe, double-click, PATH).
rem It finds a Python in a fixed order and hands over to cortex.py. It installs nothing and downloads nothing.
rem   1. %CORTEX_PYTHON%                       an explicit override, always wins
rem   2. <root>\python\python.exe              the private runtime shipped in the terminal archive
rem   3. <root>\.venv\Scripts\python.exe       a source checkout set up by SETUP.bat
rem   4. py -3 / python on PATH, 3.10 or newer a developer convenience, never a requirement
setlocal
set "HERE=%~dp0"
for %%I in ("%HERE%..") do set "ROOT=%%~fI"
if exist "%HERE%cortex.py" set "ROOT=%HERE%"
if not exist "%ROOT%\cortex.py" goto incomplete

set "PY="
if defined CORTEX_PYTHON goto envpy
if exist "%ROOT%\python\python.exe" goto bundled
if exist "%ROOT%\.venv\Scripts\python.exe" set "PY="%ROOT%\.venv\Scripts\python.exe"" & goto run
py -3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" >nul 2>nul
if not errorlevel 1 set "PY=py -3" & goto run
python -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" >nul 2>nul
if not errorlevel 1 set "PY=python" & goto run
echo cortex: no usable Python found. 1>&2
echo.       This archive carries its own runtime in python\: it is missing from this install. Reinstall the archive, 1>&2
echo.       or set CORTEX_PYTHON to a Python 3.10 or newer. 1>&2
exit /b 5

:envpy
if not exist "%CORTEX_PYTHON%" goto badenv
set "PY="%CORTEX_PYTHON%""
goto run

:bundled
rem the private runtime: nothing from the user's site-packages or from PYTHONHOME/PYTHONPATH may leak in
set "PYTHONNOUSERSITE=1"
set "PYTHONHOME="
set "PYTHONPATH="
set "PY="%ROOT%\python\python.exe""
goto run

:run
%PY% "%ROOT%\cortex.py" %*
exit /b %errorlevel%

:badenv
echo cortex: CORTEX_PYTHON=%CORTEX_PYTHON% does not exist 1>&2
exit /b 5

:incomplete
echo cortex: cannot find cortex.py next to "%HERE%" or its parent; the installation looks incomplete 1>&2
exit /b 5
