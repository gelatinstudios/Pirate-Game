
@echo off

set RELEASE=%1
set DEV=%2

if %DEV% neq 0 (
  set DEVFLAG=-define:DEV=true
) else (
  set DEVFLAG=
)

if %RELEASE% equ 0 (
  odin run source -debug %DEVFLAG% -out:pirates.exe 
) else (
  odin build source -o:speed %DEVFLAG% -out:pirates.exe -show-timings
)

