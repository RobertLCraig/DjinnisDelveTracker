---
waiting_on: Rob, an in-game /reload on a character that showed the 13 rows
---
# 0001 The delve list shows War Within delves

**Goal.** The Character and Warband tabs list the ten Midnight Delver's Call quests and nothing
else.

**Found 2026-09-27** (Rob's screenshot): 13 rows. Fungal Folly (83758), The Skittering Breach
(83768) and Tak-Rethan Abyss (83771) are War Within delves. D1's title match let them in because
they share the `Delver's Call:` prefix.

**Built (32f9918, v0.6.6, deployed).** `Catalogue:Belongs` refuses any quest ID below the lowest
seed (93372). `Catalogue:PruneOlderExpansions` runs at load and removes the three from the
catalogue, `questXP` and every character's `quests`. Decision D14.

## Acceptance

1. After `/reload`, the Character tab lists 10 delves. The three names above are gone.
2. The Warband tab shows no row or count for them.
3. The "measured quest XP growth" figure moves up from +0.78% per level. Their flat 1,300 XP was
   the drag, so it should now sit near the +1.08% measured on Midnight quests.
4. Accepting a War Within Delver's Call quest does not add it back.

Nothing here can run a game client, so all four are unverified.

## Also built: group by zone (37e6b37, v0.6.7, deployed)

Rob asked the same day for the list to be grouped by zone. At login the addon reads the delve
POIs of the four Midnight zone maps (`ns.ZONE_MAPS`: 2395, 2437, 2413, 2405) and stores the zone
on each catalogue entry as `zone`. The Character tab puts a heading above each zone, in levelling
order.

5. The Character tab shows zone headings: Eversong Woods, Zul'Aman, Harandar, Voidstorm.
6. Each delve sits under the correct zone. A delve under "Zone not read yet" means its POI name
   did not match its quest title. Say which delve it is.
7. The window is tall enough for the extra heading rows. No row is cut off at the bottom.
