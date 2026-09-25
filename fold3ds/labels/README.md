# Cartridge labels (3DS theme)

The 3DS theme's top screen floats a 3D Game Boy Color / Advance cartridge
for the selected game, in that game's shell colour, with the game's label
on its front. By default the label is the launcher's own art
(`assets/labels/<version>.png` from upstream).

To use your own label art, drop a PNG here named after the game:
`red.png`, `blue.png`, `yellow.png`, `gold.png`, `silver.png`,
`crystal.png`, `firered.png`, `leafgreen.png`. Any size works; it is fitted
into the label recess keeping its proportions (GB labels are about 8:7,
GBA labels about 2:1). Rebuild the APK to include them.

## Photos shipped here

`<version>.png` (English) and `<version>_jp.png` (Japanese) are label crops
from cartridge photos: red, blue, yellow, gold, silver, crystal, firered,
leafgreen, ruby, sapphire and emerald in English; red, gold, silver,
crystal, green, firered, leafgreen, ruby, sapphire and emerald in Japanese.
There's no English Green (it was only released in Japan), so `green` falls back to the launcher's own label. No
Japanese Blue or Yellow photo was found yet.

The photos come from the LaunchBox Games Database's "Cart - Front" images,
collected by `.github/workflows/fetch-cartridges.yml` (branch
`cartridge-art`, with Bulbagarden Archives' Game cartridges category as the
other source). Credit to the LaunchBox Games Database and Bulbagarden
Archives contributors who scanned them. The label art itself is © Nintendo,
Creatures Inc. and GAME FREAK inc.
