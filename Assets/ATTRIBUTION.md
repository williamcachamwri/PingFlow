# Asset attribution and licensing

## League of Legends assets

`Assets/textures` and `Assets/sounds` contain visual and audio assets from **League of Legends**,
© **Riot Games, Inc.** They are **not** MIT-licensed and are **not** owned by this project.

- They are included so the application reproduces the in-game ping wheel faithfully.
- Riot Games' [Terms of Use / IP Policy](https://www.riotgames.com/en/who-we-are/legal-fair-use-derivative-works-policy)
  govern any redistribution. A public build that ships these assets should either obtain Riot's
  permission or ask each user to run the extractor against their own install.
- **No ownership is claimed.** The About pane of the application states the same.
- The assets are kept modular: `AssetCatalog` resolves every file by name from a single directory,
  and `PingDefinition` carries the names. Replacing or removing them does not touch any other code.
  `PingFlow --no-assets` (or a missing asset directory) falls back to drawn placeholders.

Where the assets came from, in order of preference:

1. The extracted set committed in the reference repository
   [`darrenprx/lolPing`](https://github.com/darrenprx/lolPing) (`assets/textures`, `assets/sounds`),
   produced by `tools/extract-assets/extract_assets.py` from a local League of Legends install:
   WAD v3 entries (`Common.wad.client`), Wwise banks (`hud_global_events.bnk`,
   `hud_global_audio.bnk`) decoded with vgmstream and mixed with ffmpeg, plus DDS/`.tex`
   textures exported with Obsidian.
2. The same script run against a locally installed game client
   (`--league "…/League of Legends"`), which is the route for a build that must not redistribute them.

Colourblind variants (`*_cb*`, and the 128 px icons from `PingUpdate/Need/`) are deliberately
**not** copied: the reference project's asset notes say app code must never reference them.
`omw_cyan.png` and `enemy_missing_flipped.png` are derived files made by
`extract_assets.py --derived`, not raw game files.

## Code

The reference repository's own code is MIT © 2026 Danrui Meng. This application is a separate,
from-scratch Swift implementation. It reuses the reference's *geometry constants*, animation
timings and asset naming as a technical specification; no Electron/TypeScript source is
translated line by line and none of its architecture is wrapped.

`Support/ATTRIBUTION.txt` is copied into the built application bundle next to the resources.
