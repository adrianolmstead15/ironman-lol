# Iron Man — remote suit-up prototype

A Rojo project implementing a cinematic, remote suit-up sequence using the **actual imported suit model**.

## Setup
1. Place the supplied Iron Man model in **ServerStorage**, named `IronManArmor`.
2. Keep Roblox Studio set to **R15** avatar mode.
3. From the repository directory, run `rojo serve` and connect the Rojo Studio plugin.
4. Play, then press **E** to summon armor. Repeat to reset the equipped armor and suit up again.

The approximately 2.25-second sequence uses blue motion trails and locks sections onto the avatar individually. As each section attaches, accessories mounted to that body part disappear; accessories on other sections stay visible until their turn. Pieces come from distant positions, move with the player, and weld onto the corresponding R15 body part. Visual-only descendants are cloned, not the original Humanoid or imported scripts.

**Notes:** The suit model in ServerStorage is a Studio asset and is *not* uploaded automatically by Rojo. Preserve the model in your saved `.rbxl` place or package it as a Roblox asset. This is an initial suit-up system, not yet a tested flight/combat game. Model-specific mesh offsets may require fine-tuning.
