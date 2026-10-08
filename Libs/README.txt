Vendored dependencies for buff reminder effects:

LibCustomGlow-1.0, minor 25
Source: https://github.com/Stanzilla/LibCustomGlow
Pinned commit: 4f8f5c2607d7384b26df9175bb99fa3df891b015
License: MIT; see LibCustomGlow-1.0/LICENSE.
Lua source is unchanged apart from normalized line endings.

LibStub, minor 2
Source: https://github.com/WoWUIDev/Ace3/tree/40f4cc1356ae7fcc0cf71fc0a19dc7d50d6ae6c2/LibStub
Pinned commit: 40f4cc1356ae7fcc0cf71fc0a19dc7d50d6ae6c2
License: public domain; see LibStub/LICENSE.txt and its source header.

ZwykPlus uses an independent icon-sized child host for each effect.
The reminder's outer frame alone receives aura-controlled alpha; the library
only animates its own textures beneath that frame.
