# ZwykPlus

A small quality-of-life addon for **WoW Forever**, with a simple English/French setup panel and account-wide saved settings.

Current version: **1.2.0**. Interface version: **16001**.

## Features

- Hide UI error messages while keeping quest progress and other information visible.
- Increase the maximum camera distance, with optional full zoom out on login.
- Enable available mineral, herb and fish tracking on login when inactive.
- Show the caster of a buff or debuff in its tooltip when available.
- Show icons beside linked items in chat.
- Show separate class and race icons beside linked player names when WoW provides the information.

Every option has a saved checkbox. Existing settings are preserved when updating.

## Install or update

1. Download this repository using **Code → Download ZIP**.
2. Extract it and copy the inner `ZwykPlus` folder into your Forever client's `Interface/AddOns` directory.
3. Confirm that `Interface/AddOns/ZwykPlus/ZwykPlus.toc` exists.
4. Enable ZwykPlus and restart WoW or run `/reload`.
5. Open the setup with `/zp` or `/zwykplus`, or through **Settings → AddOns → ZwykPlus**.

Disable the old standalone HideUIErrors, MaxZoomForever and FindMineralsOnLogin addons. Disable ChatLinkIcons if installed to avoid duplicate chat icons.

WoW saves settings to disk on normal logout, exit or `/reload`.

## Compatibility and validation

The addon targets Forever Interface 16001 and has no addon or library dependencies. Unknown or restricted aura/player information is omitted. Chat icons support the default chat windows, including temporary windows; separate third-party chat windows are not integrated.

Feature behavior, saved settings, links/history, asynchronous item loading and restricted information were checked in a mocked Lua runtime. In-game validation in Forever is still needed.

See [the detailed README](ZwykPlus/README.txt) for behavior, limitations and API source references.
