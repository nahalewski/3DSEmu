# cartdb — cartridge artwork for every game, six systems

`cartdb.sqlite` maps each game in [`tools/romdb`](../romdb) to its cartridge
artwork, for Game Boy, Game Boy Color, Game Boy Advance, DS, 3DS and Switch. It
holds **URLs and metadata, never image bytes** — the same rule as `romdb`.

It feeds the 3DS theme's top screen, where `fold3ds/cart3d.lua` floats a 3D
cartridge for the selected game with that game's label on its front. Today
`fold3ds/labels/` holds eight hand-named Pokémon labels; this is the database
behind all of them.

```
python3 build_cartdb.py              # build (downloads Metadata.zip if absent, ~3 min)
python3 build_cartdb.py --coverage   # re-print the numbers
python3 build_cartdb.py --report-unmatched 20
python3 probe_gametdb.py --sample 60 # GameTDB's DS carts, keyed on romdb serials
```

## Coverage (2026-09-25)

| system | titles | official | +fanart | backs | coverage |
|---|---|---|---|---|---|
| GB | 971 | 345 | **587** | 0 | **60.5%** |
| GBC | 1057 | 136 | **539** | 0 | **51.0%** |
| GBA | 1392 | 977 | **995** | 1 | **71.5%** |
| NDS | 2760 | 1997 | **2036** | 1 | **73.8%** |
| 3DS | 628 | 420 | **437** | 2 | **69.6%** |
| SWITCH | 6576 | 526 | **661** | 3 | **10.1%** |
| **TOTAL** | 13384 | | **5255** | | **39.3%** |

`titles` is distinct romdb **retail** titles — not romdb rows, because romdb
lists each regional release separately (1,240 GB rows are 971 titles) and one
label serves a game's regional copies. For Switch the denominator is LaunchBox's
own game count, since romdb does not cover Switch.

14,312 art rows: 10,452 official, 3,860 fanart. 24 of 24 sampled URLs resolve to
real images.

## What the sources actually are

Probed, not assumed. Three of these findings contradict the team plan.

| Source | Covers | Keyed by |
|---|---|---|
| **LaunchBox Games Database** (`Metadata.zip`, 103 MB) | all six | game name → title matching |
| **GameTDB** | **DS only** | the 4-char serial romdb already stores |

* **GameTDB has no 3DS cart art.** The plan says "GameTDB carts already used for
  3DS". `art.gametdb.com/3ds/cart/US/ECLP.png` is **404**; only `box` exists. The
  old `fetch-cartridges.yml` looped over every art kind and logged what landed,
  so the intent was there and the carts never were.
* **GameTDB has no Switch art at all** — `art.gametdb.com/switch/` does not
  exist — and **Switch is absent from romdb**, because the No-Intro DATs libretro
  mirrors do not include it. For Switch, LaunchBox is both the game list and the
  art.
* **GameTDB throttles.** After a burst it stops answering with
  `SSL: UNEXPECTED_EOF` instead of a status code. `probe_gametdb.py` counts 404
  (absent) and "could not tell" (unknown) in **separate columns** for exactly
  this reason — the first version of that measurement treated any exception as
  "no art" and produced a confident number that was simply wrong.

## Two things that decide the numbers

**Fanart is most of the art for Game Boy Color.** `Fanart - Cart - Front` holds
597 GBC fronts against the official 335, and 658 GB against 701. Ignoring it
reads GBC at 12.9%; including it reads 51.0%. It is tagged `quality = 'fanart'`
and ranked below official so a consumer can prefer scans and fall back — and so
nobody mistakes a fanart label for a photograph of the real cartridge.

**There is no back-of-cart art anywhere.** `Cart - Back` is 0 to 3 images *per
platform* across the whole database. The plan wants models "front and back"; the
backs have to come from Photography Dev's reference photos.

## Why 2,745 art titles match no game

~88% of them are **Japanese-only releases, romhacks and demos** — `Captain
Tsubasa VS`, `Simple DS Series Vol. 18`, `Pokémon Blue Full Color Hack`,
`Game Boy Color Promotional Demo`. `romdb` catalogues **English-language retail**
by design (see its README), and LaunchBox does not. That gap is intended, not a
matching failure. Measured by sampling 150 unmatched titles per system and
testing each against every romdb title by prefix and by token overlap.

Only ~11% are real matching misses, which is why title matching was stopped
where it is rather than pushed further.

## Title matching

GB and GBC force the issue: romdb has serials for **3 of 1,240** GB games and
**31 of 1,375** GBC, so for those the title is the only join. GBA (1,940/2,191),
NDS (4,170/4,257) and 3DS (1,135/1,140) do have serials, which is what
`probe_gametdb.py` uses.

Two passes, both in `build_cartdb.py`:

1. `normalise()` — case, accents, `&`, punctuation, roman numerals, parenthesised
   tags, trailing `Edition`/`Version`. The rule that matters most is the comma
   article: No-Intro writes `Legend of Zelda, The - Link's Awakening` where
   LaunchBox writes `The Legend of Zelda: Link's Awakening`. Anchoring that at
   end-of-string matches only the games with no subtitle and misses every Zelda,
   Flintstones, Urbz and Fairly OddParents title.
2. `loose()` — the primary title only, no subtitle, no licensor prefix
   (`Disney's Aladdin` vs `Aladdin`), and **only where that primary title is
   unique on the platform**, or `Arcade Classic No. 3` art lands on No. 4.

Ambiguity is judged on distinct normalised **titles**, not on game ids: romdb
gives one game several ids for its regional releases, so comparing ids marks
almost every title as colliding with itself. That bug left 556 of GBA's 1,392
titles usable and made the second pass worth 72 matches instead of 196.

## Schema

```sql
art(platform, game_id, title, kind, quality, region, source, source_id, url)
--  kind: front | back | 3d        quality: official | fanart
--  game_id -> romdb games.id, NULL for Switch and for unmatched art
platform_games(platform, games)   -- the source's own count, for denominators
unmatched(platform, title, norm, source_id)
```

```sql
-- the best front label for one game, official preferred
SELECT url FROM art WHERE game_id = ? AND kind = 'front'
ORDER BY quality = 'official' DESC LIMIT 1;
```

## Not done yet

* **Fetching and cropping.** The renderer wants a *label*, and a cart scan is the
  whole cartridge. GameTDB's DS renders are consistent enough to crop
  deterministically; LaunchBox scans are not, so this needs looking at.
* **GameTDB DS carts are not in the database yet.** `probe_gametdb.py --all
  --into-db` adds them, exactly keyed by serial, but it is thousands of polite
  requests against a host that throttles. Run it deliberately, not in a build.
* **Switch's 10.1% is a floor.** Its denominator is every game LaunchBox lists,
  and many are eShop-only titles that never had a cartridge to photograph.
  Narrowing it needs a physical-release list we do not have.
