-- The words of each recomp game's electronic manual (fold3ds.manual shows
-- them on the bottom screen when the HOME menu's Manual is pressed).
--
-- Written for this app, not copied from the printed manuals: the game's own
-- basics (story, menus, battles, version differences) and what is different
-- here -- the controls on the Fold, gen1recomp's options, rulesets, mods,
-- online play and saves.  Scans of your own printed manual can sit in front
-- of these pages (fold3ds/manuals/<version>/, see fold3ds.manual).
--
-- A manual is { name, color, chapters = { { title, sections = { { title,
-- blocks } } } } }; a block is one of
--   { "h", text }          a heading
--   { "p", text }          a paragraph
--   { "k", key, text }     a control: the button, what it does
--   { "tip", text }        a note in a box
local T = {}

local function h(s) return { "h", s } end
local function p(s) return { "p", s } end
local function k(a, b) return { "k", a, b } end
local function tip(s) return { "tip", s } end

local INFO = {
  red = { name = "Pokémon Red", color = { 232, 52, 60 }, gen = 1 },
  blue = { name = "Pokémon Blue", color = { 52, 110, 232 }, gen = 1 },
  green = { name = "Pokémon Green", color = { 60, 170, 80 }, gen = 1 },
  yellow = { name = "Pokémon Yellow", color = { 232, 180, 10 }, gen = 1 },
  gold = { name = "Pokémon Gold", color = { 214, 150, 40 }, gen = 2 },
  silver = { name = "Pokémon Silver", color = { 150, 158, 172 }, gen = 2 },
  crystal = { name = "Pokémon Crystal", color = { 80, 170, 215 }, gen = 2 },
  firered = { name = "Pokémon FireRed", color = { 220, 60, 40 }, gen = 3 },
  leafgreen = { name = "Pokémon LeafGreen", color = { 60, 170, 90 }, gen = 3 },
}

---------------------------------------------------------------- shared

local function gettingStarted(v, info)
  local blocks = {
    h("Before you play"),
    p("gen1recomp is a native re-creation of the game, written in Lua.  It does not emulate a Game Boy "
      .. "and ships no game data: the first time you play, it asks for your own legally obtained US "
      .. "cartridge ROM, checks it against the one known copy, builds its own data from it and lets it go."),
    p("After that the game starts straight from its icon on the HOME menu.  The ROM is never asked for again "
      .. "and is not kept."),
    h("Starting the game"),
    k("Open / A", "start the selected game"),
    k("Tap the top screen", "start it too, once it is ready"),
    k("Manual", "this manual"),
    p("On the title screen choose NEW GAME to begin, or CONTINUE to carry on from your last save."),
  }
  if info.gen == 1 then
    blocks[#blocks + 1] = tip("Red, Blue and Yellow keep separate saves, so all three can be played side by side.")
  else
    blocks[#blocks + 1] = tip("Every version keeps its own save, so the games can be played side by side.")
  end
  return { title = "Getting Started", sections = { { title = "Getting Started", blocks = blocks } } }
end

local function controls(v, info)
  local move = {
    h("On the Fold"),
    k("Circle Pad / + Pad", "walk, move the cursor"),
    k("A", "talk, check, confirm"),
    k("B", info.gen == 3 and "cancel; hold while walking to run" or "cancel, go back"),
    k("START", "the menu"),
    k("SELECT", "in lists: move an item or move to a new place.  On the map: opens the mod manager (SELECT again closes it)"),
    k("ZL / ZR", "game speed: slower / faster"),
    k("C-Stick", "change how the screens are laid out"),
    k("HOME", "back to the HOME menu (the game waits for you)"),
  }
  local keys = {
    h("With a keyboard or controller"),
    k("Arrows / WASD", "move"),
    k("Z / Enter / Space", "A"),
    k("X / Backspace", "B"),
    k("Escape", "START"),
    k("Tab / Shift", "SELECT"),
    k("- / =", "zoom out / in on the map"),
    k("1", "cycle game speed"),
    k("2", "cycle colours"),
    k("3 / 4", "cycle tilt / zoom (free-roam map)"),
    k("F1 / F2", "save / load"),
    k("F10", "open / close the mod manager"),
    tip("Any control can be changed in the game under OPTIONS > CONTROLS."),
  }
  return { title = "Controls", sections = {
    { title = "Controls", blocks = move },
    { title = "Keyboard & Controller", blocks = keys },
  } }
end

local function recomp(v, info)
  local opts = {
    h("Options"),
    p("The game's OPTION menu has the original settings (text speed, battle animation, battle style) and the "
      .. "recomp's own.  All are kept between sessions."),
    k("COLORS", "the palette: original shades or colour schemes"),
    k("TILT / ZOOM", "a 3D tilt and a wider view of the map"),
    k("SHADER FX", "screen effects"),
    k("GAME SPEED", "play faster (ZL / ZR too)"),
    k("VOID FILL", "what shows past the edge of the map"),
    k("PERFORMANCE", "AUTO, HIGH, BALANCED or LOW, for slower devices.  Only the look changes, never the game"),
  }
  local rules = {
    h("Rulesets"),
    p("OPTIONS > RULESET picks which battle rules run.  Both use the same damage formulas."),
    k("gen1_faithful", "the original cartridge, famous bugs included: the 1-in-256 miss, Focus Energy "
      .. "lowering the critical-hit rate, enemies that never run out of PP, Hyper Beam skipping its recharge "
      .. "after a knock-out"),
    k("modern_clean", "the same game with those quirks fixed"),
    p("gen1_faithful is the default.  Mods can add rulesets of their own."),
  }
  if info.gen ~= 1 then
    rules[#rules + 1] = tip("Rulesets are written for the Gen 1 battle engine; later versions may not offer them yet.")
  end
  local mods = {
    h("Mods"),
    p("Mods change or add to the game: new graphics, rules, features and whole adventures."),
    k("SELECT (on the map)", "the mod manager: turn mods on and off"),
    k("Mods", "the HOME menu's applet: your installed mods"),
    k("Find Mods", "browse the community catalogue and install"),
    k("Import", "bring in mods and saves from elsewhere"),
    tip("Every online room names the game, version and ruleset it runs, vanilla or a custom cart, so both sides always play the same thing."),
  }
  local online = {
    h("Playing together"),
    p("The Online applet opens a lobby: see who is around and with which game and rules, host a battle or "
      .. "join one, watch live matches, run a tournament, or trade Pokémon between saves."),
    p("Picking a battle starts the game straight into it and brings you back when it ends."),
    p("The game's own LINK / Cable Club still works too, over the local network."),
    h("Saving"),
    p("Save from START > SAVE as in the original (F1 with a keyboard).  Save Sync on the applet bar keeps "
      .. "your saves on other devices up to date."),
  }
  return { title = "gen1recomp", sections = {
    { title = "Options", blocks = opts },
    { title = "Rulesets", blocks = rules },
    { title = "Mods", blocks = mods },
    { title = "Online & Saving", blocks = online },
  } }
end

---------------------------------------------------------------- Gen 1

local GEN1_ONLY = {
  red = { "Ekans / Arbok", "Oddish / Gloom / Vileplume", "Mankey / Primeape", "Growlithe / Arcanine",
          "Scyther", "Electabuzz" },
  blue = { "Sandshrew / Sandslash", "Vulpix / Ninetales", "Meowth / Persian",
           "Bellsprout / Weepinbell / Victreebel", "Pinsir", "Magmar" },
}
GEN1_ONLY.green = GEN1_ONLY.blue

local function gen1(v, info)
  local story = {
    h("A world of Pokémon"),
    p("Pokémon are creatures that live everywhere: in tall grass, caves, the sea.  People catch them, raise "
      .. "them and battle with them."),
    p("You start in Pallet Town, the day you are old enough to set out.  Professor Oak gives you your first "
      .. "Pokémon and a Pokédex, an encyclopaedia that fills as you see and catch new ones, and asks you to "
      .. "complete it.  Your rival, Oak's grandson, sets out the same day."),
    p("Across Kanto are eight Gyms.  Beat each Gym Leader for a Badge; with all eight you may take on the "
      .. "Elite Four at Indigo Plateau and become Champion."),
  }
  if v == "yellow" then
    story[#story + 1] = h("Pikachu")
    story[#story + 1] = p("In Yellow your first Pokémon is Pikachu, and it would rather not live in a Poké Ball.  "
      .. "It walks behind you.  Talk to it (face it and press A) to see how it feels about you: good care and "
      .. "battles make it happier.  Your rival takes Eevee.")
    story[#story + 1] = tip("Bulbasaur, Charmander and Squirtle can still join you: keep an eye out along the way.")
  else
    story[#story + 1] = h("Your first Pokémon")
    story[#story + 1] = p("In Oak's lab choose Bulbasaur (Grass), Charmander (Fire) or Squirtle (Water).  "
      .. "Your rival takes the one strong against yours.")
  end
  local menu = {
    h("The START menu"),
    k("POKéDEX", "every Pokémon you have seen and caught"),
    k("POKéMON", "your party (up to six): stats, moves, field moves, switching order"),
    k("ITEM", "your bag: use, toss, move items"),
    k("(your name)", "your Trainer Card and Badges"),
    k("SAVE", "save your progress"),
    k("OPTION", "text speed, animations, battle style, the recomp's options"),
    h("Places"),
    k("Pokémon Center", "heals your party for free; its PC stores items and Pokémon"),
    k("Poké Mart", "buy Poké Balls, Potions and more"),
    k("Gym", "the town's Gym Leader waits at the back"),
    tip("Pokémon you catch with a full party go to the PC.  A Box holds 20; change Boxes there before one fills."),
  }
  local battle = {
    h("Battles"),
    p("Walk into tall grass, caves or water and wild Pokémon appear.  A Trainer who sees you walks up to battle."),
    k("FIGHT", "use one of up to four moves"),
    k("PKMN", "switch Pokémon"),
    k("ITEM", "use an item; throw a Poké Ball at a wild one"),
    k("RUN", "leave a wild battle (not a Trainer's)"),
    h("Types"),
    p("Every Pokémon and move has a type.  Water puts out Fire, Fire burns Grass, Grass drinks Water, "
      .. "Electric hits Water and flying things, Ground stops Electric, Psychic is strong against Fighting "
      .. "and Poison.  A move of the Pokémon's own type hits harder."),
    h("Status"),
    k("PSN", "loses HP each turn"),
    k("BRN", "loses HP and hits weaker"),
    k("PAR", "slow, sometimes cannot move"),
    k("SLP", "cannot move until it wakes"),
    k("FRZ", "cannot move until thawed"),
    p("Stats are HP, Attack, Defense, Speed and Special (one stat for special attack and defence)."),
  }
  local catching = {
    h("Catching Pokémon"),
    p("Weaken a wild Pokémon first: the less HP it has, the easier it is to catch.  Sleep or paralysis "
      .. "helps even more.  Then throw a Poké Ball from ITEM.  Great Balls and Ultra Balls do better."),
    h("Growing"),
    p("Pokémon gain experience in battle and level up.  Many evolve: some at a level, some with an "
      .. "evolution stone, some only when traded."),
    h("Hidden Machines"),
    p("Some places need an HM move taught to a Pokémon, and the right Badge, to pass:"),
    k("CUT", "small trees"),
    k("FLY", "to a town you have visited"),
    k("SURF", "across water"),
    k("STRENGTH", "push boulders"),
    k("FLASH", "light dark caves"),
  }
  local only = GEN1_ONLY[v]
  local ver = { h("Only in this version") }
  if only then
    ver[#ver + 1] = p("Some Pokémon live only in one version.  In " .. info.name .. " you can find:")
    for _, n in ipairs(only) do ver[#ver + 1] = k("•", n) end
    ver[#ver + 1] = p("The others come by trading: the Online applet trades between saves, yours included.")
  elseif v == "yellow" then
    ver[#ver + 1] = p("Yellow follows the Pokémon anime: Pikachu at your side, Jessie and James of Team Rocket, "
      .. "and Gym Leaders with teams to match.  Which Pokémon live where is different too, and some can only "
      .. "be traded in from Red or Blue.")
    ver[#ver + 1] = p("The Online applet trades between saves, yours included.")
  end
  return {
    { title = "The Adventure", sections = { { title = "The Story", blocks = story }, { title = "Menus & Places", blocks = menu } } },
    { title = "Battles", sections = { { title = "Battles", blocks = battle }, { title = "Catching & Growing", blocks = catching } } },
    { title = "This Version", sections = { { title = "This Version", blocks = ver } } },
  }
end

---------------------------------------------------------------- Gen 2

local function gen2(v, info)
  local story = {
    h("Johto"),
    p("Three years after Red's journey, a new region.  You start in New Bark Town, next door to Professor "
      .. "Elm's lab.  He gives you your first Pokémon -- Chikorita (Grass), Cyndaquil (Fire) or Totodile "
      .. "(Water) -- and an errand that becomes a journey through Johto's eight Gyms, the Elite Four, and on "
      .. "to Kanto."),
    h("What is new"),
    k("Time", "a real clock: morning, day and night, and days of the week.  Some Pokémon and people only appear at certain times"),
    k("Pokégear", "clock, map, phone and radio"),
    k("Types", "Dark and Steel join the others"),
    k("Stats", "Special splits into Special Attack and Special Defense"),
    k("Items", "a Pokémon can hold an item, like a Berry it eats when it needs to"),
    k("Eggs", "two Pokémon left at the Day-Care may leave an Egg"),
  }
  local ver = { h("This version") }
  if v == "gold" then
    ver[#ver + 1] = p("Gold's legend is Ho-Oh, the rainbow bird said to rest on Tin Tower.")
  elseif v == "silver" then
    ver[#ver + 1] = p("Silver's legend is Lugia, said to sleep under the sea at the Whirl Islands.")
  else
    ver[#ver + 1] = p("Crystal lets you play as a boy or a girl, follows Suicune and a mysterious trainer "
      .. "named Eusine, and adds the Battle Tower.  Pokémon move when they enter a battle.")
  end
  ver[#ver + 1] = p("Some Pokémon live only in one version; the others come by trading.")
  ver[#ver + 1] = tip("Gen 2 in gen1recomp is still being built: some of the game may not be there yet.")
  return {
    { title = "The Adventure", sections = { { title = "Johto", blocks = story }, { title = "This Version", blocks = ver } } },
  }
end

---------------------------------------------------------------- Gen 3

local function gen3(v, info)
  local story = {
    h("Back to Kanto"),
    p("The first adventure retold.  You set out from Pallet Town with Bulbasaur, Charmander or Squirtle "
      .. "from Professor Oak, a Pokédex to fill, eight Gyms and the Elite Four, and the Sevii Islands beyond."),
    h("What is new"),
    k("Running", "hold B to run"),
    k("Abilities", "every Pokémon has one, working in and out of battle"),
    k("Natures", "each Pokémon's nature raises one stat and lowers another"),
    k("Bag", "pockets for Items, Key Items, Poké Balls, the TM Case and the Berry Pouch"),
    k("Double battles", "two against two"),
    k("Vs. Seeker", "call Trainers you have beaten for a rematch"),
    tip("SELECT on the map opens gen1recomp's mod manager, not a registered item."),
  }
  local ver = {
    h("This version"),
    p((v == "firered" and "FireRed" or "LeafGreen") .. " and "
      .. (v == "firered" and "LeafGreen" or "FireRed") .. " differ in which Pokémon live in the wild; "
      .. "the others come by trading."),
    tip("FireRed and LeafGreen are in beta in gen1recomp."),
  }
  return {
    { title = "The Adventure", sections = { { title = "Kanto Again", blocks = story }, { title = "This Version", blocks = ver } } },
  }
end

---------------------------------------------------------------- the manual

local cache = {}
function T.get(v)
  if cache[v] then return cache[v] end
  local info = INFO[v]
  if not info then return nil end
  local chapters = { gettingStarted(v, info), controls(v, info) }
  local own = info.gen == 1 and gen1(v, info) or info.gen == 2 and gen2(v, info) or gen3(v, info)
  for _, c in ipairs(own) do chapters[#chapters + 1] = c end
  chapters[#chapters + 1] = recomp(v, info)
  local m = { id = v, name = info.name, color = info.color, chapters = chapters }
  cache[v] = m
  return m
end

function T.has(v) return INFO[v] ~= nil end

return T
