# WoW Forever transport reference (2026 beta/launch data)

Compiled 2026-11-15 from third-party sites; no Blizzard primary data read directly. Coordinates are zone-map x, y.
Important: bytetavern gives DIRECT connections ONLY for the new nodes. Classic nodes are listed with location and NO route lists. For classic adjacency use the classic flight graph, modified by the changes below.

Sources:
- BT-FP = https://bytetavern.com/wow-forever-flight-paths/
- BT-RG = https://bytetavern.com/wow-forever-riverglades/
- BT-HY = https://bytetavern.com/wow-forever-mount-hyjal/
- BT-ZL = https://bytetavern.com/wow-forever-zones-by-level/
- WFI-RG = https://wowforeverinfo.com/guides/riverglades-35-45/

## 1. Flight nodes (source: BT-FP)

### Eastern Kingdoms - Alliance
Aerie Peak (Hinterlands) 11.1,46.1; Booty Bay (STV) 27.5,77.7; Chillwind Camp (W. Plaguelands) 43.0,85.0; Darkshire (Duskwood) 77.6,44.4;
**Farholde Keep (Riverglades, NEW) 60.6,81.6 -> Lakeshire, Thelsamar, Morgan's Vigil**;
Ironforge 55.9,47.9; Lakeshire (Redridge) 25.3,59.0; Light's Hope Chapel (E. Plaguelands) 71.7,49.6; Menethil Harbor (Wetlands) 9.5,59.7;
Morgan's Vigil (Burning Steppes) 84.4,68.3; Nethergarde Keep (Blasted Lands) 65.5,24.4; Refuge Pointe (Arathi) 45.8,46.1;
Sentinel Hill (Westfall) 56.6,52.7; Southshore (Hillsbrad) 49.4,52.1; Stormwind 71.6,72.2; Thelsamar (Loch Modan) 33.9,50.8; Thorium Point (Searing Gorge) 37.9,30.4.
Counts stated: 17 nodes (Classic 16), 38 routes (Classic 35). The list above has 18 entries incl. no-route Powderfuse Port listed under neutral; page does not explain the count (uncertain).

### Eastern Kingdoms - Horde
Booty Bay 26.8,77.0; **Flame Crest (Burning Steppes) 65.6,24.2 -> Rog'mar** (plus classic routes); Grom'gol (STV) 32.5,29.3;
**Hammerfall (Arathi) 73.1,32.6 -> Rog'mar**; **Kargath (Badlands) 4.1,44.9 -> Rog'mar**; Light's Hope Chapel 70.5,47.6; Revantusk Village (Hinterlands) 81.7,81.9;
**Rog'mar (Riverglades, NEW) 59.6,45.1 -> Stonard, Kargath, Flame Crest, Hammerfall**; The Sepulcher (Silverpine) 45.6,42.4;
**Stonard (Swamp of Sorrows) 46.0,54.7 -> Rog'mar**; Tarren Mill (Hillsbrad) 60.2,18.8; Thorium Point 34.8,30.6; Undercity 63.1,48.3.
Counts stated: 13 nodes (Classic 12), 26 routes (Classic 22). (The "+ -> Rog'mar" notes mean that route is added to each node's classic routes.)

### Eastern Kingdoms - neutral / unassigned
- **Powderfuse Port (Riverglades, NEW) 76.8,53.0 (gryphon; WFI-RG/BT-RG say wind rider master at 79.0,52.3)**: flight masters present, NO routes in live client, no faction flag. The beta's only route (Alliance hop to Farholde Keep) was removed Nov 5. Whether it gains a route is listed as unknown.
- Tidegear Coast (Dun Morogh): unused flight point, no routes, no faction flag.
- A one-way Dalaran -> Stormwind gryphon flight exists in path data with no flight point tied to it (provider unknown).

### Kalimdor - Alliance
Astranaar (Ashenvale) 34.5,48.0; Auberdine (Darkshore) 36.4,45.6; Cenarion Hold (Silithus) 50.7,34.6; Everlook (Winterspring) 62.3,36.6;
Feathermoon (Feralas) 30.3,43.3; Gadgetzan (Tanaris) 51.0,29.3; Moonglade 47.9,67.1; Nijel's Point (Desolace) 64.7,10.4; Rut'theran Village (Teldrassil) 58.4,93.9;
Stonetalon Peak 36.5,7.2; **Summit of Eternity (Mt Hyjal, NEW) 68.6,44.1 -> Tainted Foothills only**; **Tainted Foothills (Mt Hyjal, NEW) 55.1,82.5 -> Everlook, Summit of Eternity**;
Talonbranch Glade (Felwood) 62.5,24.2; Talrendis Point (Azshara) 11.9,77.5; Thalanaar (Feralas) 89.5,45.9; Theramore (Dustwallow) 67.5,51.2.
Counts stated: 18 nodes (Classic 16), 32 routes (Classic 30).

### Kalimdor - Horde
Bloodvenom Post (Felwood) 34.4,53.9; Brackenwall Village (Dustwallow) 35.6,31.8; Camp Mojache (Feralas) 75.4,44.3; Camp Taurajo (Barrens) 44.5,59.1;
Cenarion Hold 48.8,36.7; Crossroads (Barrens) 51.5,30.4; Everlook 60.5,36.3; Freewind Post (Thousand Needles) 45.0,49.1; Gadgetzan 51.6,25.5; Moonglade 32.1,66.3;
Orgrimmar 45.3,63.8; Shadowprey Village (Desolace) 21.6,74.0; Splintertree Post (Ashenvale) 73.3,61.7; **Summit of Eternity (NEW) 68.6,44.1**; Sun Rock Retreat (Stonetalon) 45.2,59.9;
**Tainted Foothills (NEW) 55.1,82.5**; Thunder Bluff 46.6,49.9; Valormok (Azshara) 21.9,49.7; Zoram'gar Outpost (Ashenvale) 12.2,33.8.
Counts stated: 21 nodes (Classic 19), 48 routes (Classic 46). Hyjal routes for Horde are the same as Alliance (nodes shared by both factions).

### Kalimdor - neutral
Marshal's Refuge (Un'Goro) 45.3,6.0; Ratchet (Barrens) 63.1,37.1. Summit of Eternity and Tainted Foothills are shared by both factions.

### Complete list of NEW routes (10 stated)
Farholde Keep<->Lakeshire/Thelsamar/Morgan's Vigil (3); Rog'mar<->Stonard/Kargath/Flame Crest/Hammerfall (4); Tainted Foothills<->Everlook, Tainted Foothills<->Summit of Eternity (2); plus Summit of Eternity (1 listed one-way entry). Page does not say whether routes are bidirectional listings; treat as two-way (uncertain). Route counts rising by 2-4 per faction/continent are consistent with only additions; page lists NO removed classic routes.

### Absences / notes (BT-FP)
- No Horde flight points in Wetlands, Westfall, Duskwood, Redridge, Loch Modan; Hammerfall is the closest Horde option to Wetlands (Horde reaches Wetlands by road from Hammerfall).
- Darnassus has no flight master (land at Rut'theran, portal up). Dalaran has no flight master (nearest FP: Southshore). Shen'dralas and Zephras Isle have no flight point.
- Flight speed unchanged (expected, untested). Frequent Flier legacy perk: flights 50% cheaper, 20% faster. No flying mounts.
- Untested in beta: Riverglades and Mt Hyjal flight points at levels 30-60.

## 2. Boats / zeppelins / skyships (source: BT-FP unless noted)

| Line | Faction | Status | Coordinates |
|---|---|---|---|
| Stormwind Harbor <-> Auberdine | Alliance | NEW (Blizzard confirmed; "an early path between the Eastern Kingdoms and Kalimdor") | Stormwind dock 21.8,56.8 |
| Menethil Harbor (north pier) <-> Southshore <-> Auberdine | Alliance | NEW Southshore stop (confirmed); path ~7,100 yd vs ~3,900 yd old direct | Southshore stop Hillsbrad 50.7,70.5 |
| Menethil Harbor (south pier) <-> Theramore | Alliance | Classic | none given |
| Auberdine <-> Rut'theran Village | Alliance | Classic | none given |
| Feralas coast <-> Feathermoon | Alliance | Classic | none given |
| Booty Bay <-> Ratchet | Neutral | Classic | none given |
| Steamwheedle Port (Tanaris) <-> Powderfuse Port (Riverglades) | Neutral (both) | NEW (confirmed) | Tanaris 68.6,23.0; Riverglades 80.6,54.6 |
| Orgrimmar <-> Tirisfal Glades (Undercity) | Horde | Classic zeppelin | none given |
| Orgrimmar <-> Grom'gol | Horde | Classic zeppelin | none given |
| Tirisfal Glades <-> Grom'gol | Horde | Classic zeppelin | none given |
| Valanaar (Zephras Isle) -> Dalaran | Alliance Skyborne, lvl 12+ | NEW skyship (beta-tested) | Dalaran dock Alterac Mtns 12.8,51.2 (north side) |
| Valanaar (Zephras Isle) -> Skywatcher Plateau, Mulgore | Horde Skyborne, lvl 12+ | NEW skyship | Mulgore 34.3,26.1 (north of Thunder Bluff) |

- No Thunder Bluff zeppelin (stated). Deeprun Tram Stormwind<->Ironforge unchanged.
- Dalaran Violet Citadel portal near the dock reportedly leads to Stormwind Mage Tower (Warcraft Tavern report; Skyborne-only assumed; uncertain).
- Powderfuse Port ship: WFI-RG says quickest route into Riverglades from Kalimdor; players ~lvl 44-45 can return Powderfuse -> Tanaris by it.
- Original-source discrepancy: Powderfuse dock 80.6,54.6 vs flight node 76.8,53.0 / 79.0,52.3 (different objects, not an error).
Source: https://bytetavern.com/wow-forever-flight-paths/ , BT-RG, WFI-RG

## 3. Zones: land borders and layout

### Riverglades (NEW, 35/36-44/45; ~Stranglethorn-sized; ~200 quests) - BT-RG, WFI-RG, BT-ZL
- East coast of Eastern Kingdoms, south of Badlands, east of Burning Steppes and Redridge, north of Swamp of Sorrows.
- Borders (WFI-RG): Redridge (west, main entrance), Burning Steppes, Badlands, Swamp of Sorrows. BT-ZL: "borders the Badlands and Swamp of Sorrows".
- Entrances on foot:
  - Redridge -> Blackrock Pass (road toward Burning Steppes, near Morgan's Vigil; WFI-RG: fork toward Steppes, turn right before reaching it) or Redridge Pass further south; gnolls at the entrance (lvl 36-38) hit hard. Western gnoll entrance ~17-31,56-68.
  - Swamp of Sorrows: Stonard -> north through Redridge Pass into SW of zone, NE to Rog'mar (BT-RG; name "Redridge Pass" as given, uncertain).
  - Badlands (Horde, lvl 40+): Kargath east; entrance north of Twilight's Shroud near Krol'dok walls.
  - Burning Steppes: Blackrock Pass only (Flame Crest route crosses lvl 50-58 zone).
  - By sea: Tanaris boat to Powderfuse Port (see section 2).
- Hubs: Farholde Keep (Alliance, SE, ~64,83), Rog'mar (Horde, centre on river ~59,45), Powderfuse Port (neutral goblin town, E coast ~78,53), Bolder'ok (ogres, north ~66,20, lvl 42), Sunnyglade (43-55,41-56) and Twilight's Shroud (28-36,37-55) in the west (Twilight's Hammer), Eastwind Shore (79-89,31-50), Krol'dok Stronghold dungeon (40-45; entrance cave ~37.5,37.5, unverified).
- Levels by area: 36 Meadowsbrook/Southern Watch/Wheeler's Grange; 37 Bristle Hills; 38 Ashwood's Fall/Elbrim's Farm/Farholde/Powderfuse/Rog'mar/Sunnyglade/Terral's Watch/Turner's Logging Camp; 40 Eastwind Shore; 41 Twilight Hollow/Windstead; 42 Bolder'ok/Krol'dok; 44 Forlorn Pit/Twilight's Shroud. Lower levels south and west.
- Closest FP: Alliance Lakeshire (via Redridge), Horde Stonard. WFI-RG advises not entering much below 35.
- Redridge Mountains map was redrawn for the Riverglades border (BT-ZL); Forever also redrew Redridge and Stormwind so classic coordinates are inaccurate there (BT-FP).
- Entrance routes were taken from Warcraft Wiki and are unverified in live game (BT-RG).

### Mount Hyjal (NEW, Group Finder 55-60) - BT-HY, BT-ZL
- Northern Kalimdor between Felwood and Winterspring (BT-ZL adds Azshara; BT-HY says only Felwood and Winterspring; discrepancy, uncertain).
- Entrance only from Winterspring via Darkwhisper Gorge (lvl 60 area) at its southern end; from Everlook ~2,300 yd SW in straight line. Road enters SE corner ~87,74 ("through the druidic wards"). No attunement needed.
- Second road in NE ends at an undocumented gate symbol.
- Subzones (x,y): Tainted Foothills (71,73), Felblood Scar (46,77), Malorne's Retreat (29,71), Mourning's Rest (24,53), Elderwild (14,50), Cradle of Tranquility (34,42), Dae'gun (55,37), Shrine of Aviana (51,59), Summit of Eternity (78,35). Main road runs W from entrance, N, then E to Summit. Hyjal Summit raid ~250 yd from Summit of Eternity FP; Barrow Deeps (10-man) has several entrances incl. Hyjal, Winterspring, Blackmaw Hold (positions unpublished).

### Shen'dralas (NEW, ~38-43 by quests) - BT-ZL
- Kalimdor, south of Desolace; Mulgore east, Feralas south-west. Road south from Desolace via Valley of Bones (now part of Shen'dralas). On foot only, no FP/boat. Alliance fly Nijel's Point, Horde Shadowprey Village.

### Zephras Isle (NEW) - BT-ZL
- Floating island in Skywall, Skyborne only, levels 1-12; Valanaar skyships at 12 (section 2).

### Other redrawn / changed (BT-ZL)
- Tirisfal Glades (Ruins of Lordaeron dungeon 15-20; next to Silverpine per low-level route picks), Alterac Mountains (Dalaran, city again, hostile to Horde since Oct 15 build; dungeon 28-33), Mulgore (Skywatcher Plateau), Redridge, plus Stormwind and Eastern Plaguelands (no details published). Wetlands: Excavation Site dungeon (~24-31); only faster respawns noted, no map change stated.
- Other zone layouts: page gives no detail on differences.

## 4. Gaps (not in sources)
- Classic-node adjacency lists (not given); any removed classic routes (none stated); boat/zeppelin coordinates for classic lines; Powderfuse Port routes; whether Mt Hyjal borders Azshara; exact Stormwind/Eastern Plaguelands changes.
