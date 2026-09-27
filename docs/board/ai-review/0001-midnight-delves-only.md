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
