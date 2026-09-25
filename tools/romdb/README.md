# romdb

`romdb.sqlite` catalogs English-language Game Boy, Game Boy Color, Game Boy
Advance, Nintendo DS and Nintendo 3DS releases. Its entries come from the No-Intro DAT
files mirrored by [libretro-database](https://github.com/libretro/libretro-database).
It holds only metadata (title, regions, languages, serial, revision, dump kind)
and the size, CRC32, MD5 and SHA-1 of each known-good dump. It holds no ROM
data and no download links.

A release counts as English if its language tag includes `En`. If it has no
language tag, it counts when its region is USA, Europe, World, UK, Australia,
Canada, Ireland or New Zealand.

* `python3 build_db.py`: rebuild from the latest DATs (`--dat-dir` for local copies)
* `python3 verify.py your.gb ...`: identify your own dumps by SHA-1, for example
  to check that the Red/Blue/Yellow cart you dumped for gen1recomp is clean

```sql
SELECT g.name, r.sha1 FROM games g JOIN roms r ON r.game_id = g.id
WHERE g.platform = 'GB' AND g.title LIKE 'Pokemon%' AND g.kind = 'retail';
```
