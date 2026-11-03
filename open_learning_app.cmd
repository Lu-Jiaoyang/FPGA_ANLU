@echo off
cd /d "%~dp0"
if exist "D:\ANACONDA\python.exe" (
    "D:\ANACONDA\python.exe" -m pc_learning.app
) else (
    python -m pc_learning.app
)
if errorlevel 1 pause
