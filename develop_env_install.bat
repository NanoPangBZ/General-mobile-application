@echo off
py -3 "%~dp0tooling\dev_env.py" %*
exit /b %ERRORLEVEL%
