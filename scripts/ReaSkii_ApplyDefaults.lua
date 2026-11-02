-- Run once from Actions after updating the theme, or use its standard adjuster.
local dir=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
local defaults=dofile(dir..'ReaSkii_Defaults.lua')
local ok,result=pcall(defaults.apply)
reaper.ShowMessageBox(ok and ('Reapertips defaults applied, with full-row names and smart indent ON.\nPrevious values saved in:\n'..result) or tostring(result),'ReaSkii',0)
