--[[ CDS-PATCH: build stamp.

     This file is a PLACEHOLDER. deploy-bots.bat overwrites the copy inside your
     Dota install (not this one) with the current git hash and deploy time, so the
     version line the bots announce in chat tells you exactly which build is
     loaded. If you ever see "source - not deployed via deploy-bots.bat" in game,
     the files were copied across by hand and this stamp means nothing.

     Deliberately NOT generated from TypeScript, so `npm run build:lua` will not
     touch it, and deliberately overwritten at the destination rather than in the
     repo, so deploying does not leave your working tree dirty. ]]

local ____exports = {}
____exports.id = "source - not deployed via deploy-bots.bat"
return ____exports
