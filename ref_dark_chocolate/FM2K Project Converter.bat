@echo off
echo Converting files...
echo ----------------------------------------------------------
xcopy *.stx *.stage
xcopy *.fmx *.kgt
xcopy *.dmx *.demo
xcopy *.plx *.player
cls
del *.dmx
del *.fmx
del *.stx
del *.plx
echo Complete.
pause