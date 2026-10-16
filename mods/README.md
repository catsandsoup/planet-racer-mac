# Bundled Quick Race mods

Choose **MODS** on the title screen, then choose a pack. Quick Race opens on planet 6 with Everett, Easy, 80 HP, sports chassis, high-grip tires and the 5-litre afterburner. Returning to the title restores the base game and preserves career state. Use these packs for Quick Race; career modding is not supported.

Each folder contains a complete `data/` resource tree. The first five planets, parts, rivals and dialogue retain their original data. Planet 6 keeps its ID and selects a new handmade map. The original sample map is retained. Assets are shared with the main app and must be baked from your own `planetracer.swf`.

| Pack | Gravity | Length | Car changes |
|---|---:|---:|---|
| [Moonshot](moonshot/data/planets.json) | 0.12 | 5000 | Stock car; long, floaty launches |
| [Jelly Racer](jelly-racer/data/planets.json) | 0.24 | 4000 | Spring stiffness 0.40 instead of 0.55; flexible body over shallow ridges |
| [Big Wheels](big-wheels/data/planets.json) | 0.24 | 4000 | Rear/front wheel radii 35/26 instead of 23/17; oversized buggy stance |

No physics algorithms are changed. Jelly Racer preserves the original seven points, 17 springs and crash-angle thresholds. Big Wheels preserves the original point geometry, spring stiffness and crash rules. Both car changes apply globally to both racers while their pack is active.

To tune a pack, edit its `data/planets.json`, `data/maps/<pack-name>.json` or `data/cars/default.json`, then relaunch the app. Rebuild the app bundle after editing repository data if running the packaged app. Map points must have strictly increasing x coordinates; keep a flat spawn strip and extend the finish flat beyond the line. Keep each pack's full data tree together when packaging. See the main [README](../README.md) for controls, screenshots and the asset-baking/build instructions.

Successful recommended-loadout runs measured roughly 8–13 seconds. The longer 30–75 second design aspiration was not met. Automated core checks establish finishability and finite physics, but do not replace a player's assessment of handling and replay appeal.
