# ZwykPlus

A small quality-of-life addon for **WoW Forever**, with a compact English/French setup panel and account-wide saved settings.

Current version: **1.4.0**. Interface version: **16001**.

## Features

- Hide UI error messages while keeping quest progress and other information visible.
- Increase the maximum camera distance, with optional full zoom out on login.
- Enable available mineral, herb and fish tracking on login when inactive.
- Show the caster of a buff or debuff in its tooltip, with player names in their class color.
- Left-click a default player buff or debuff icon to target its caster outside combat using a secure click button.
- Optionally show animated 3D portraits on native unit frames, with a 2D fallback.
- Show icons beside linked items in chat.
- Show separate class and race icons beside linked player names when WoW provides the information.

The setup has five categories: **Interface, Automation, Auras, Frames and Chat**. The opaque 600 × 390 window remembers the selected category. Every option has a saved checkbox. Existing settings are preserved when updating; 3D portraits start disabled and can be enabled under Frames.

## Changes in 1.4.0

- Replaced the tall setup window with compact categories and tooltip help.
- Added class colors for player aura casters, with a neutral color when class information is unavailable.
- Replaced the direct protected targeting call that caused `ADDON_ACTION_FORBIDDEN` with WoW's secure click template. The transparent button uses the current aura, passes right-clicks through and hides through a secure state driver when combat begins.
- Added optional native player, target, focus, pet and portrait-style party 3D portraits. Missing or inaccessible models keep the original 2D portrait.

## Install or update

1. Download this repository using **Code → Download ZIP**.
2. Extract it and copy the inner `ZwykPlus` folder into your Forever client's `Interface/AddOns` directory.
3. Confirm that `Interface/AddOns/ZwykPlus/ZwykPlus.toc` exists.
4. Enable ZwykPlus and restart WoW or run `/reload`.
5. Open the setup with `/zp` or `/zwykplus`, or through **Settings → AddOns → ZwykPlus**.

Disable the old standalone HideUIErrors, MaxZoomForever and FindMineralsOnLogin addons. Disable ChatLinkIcons if installed to avoid duplicate chat icons.

WoW saves settings to disk on normal logout, exit or `/reload`.

## Compatibility and validation

The addon targets Forever Interface 16001 and has no addon or library dependencies. Unknown or restricted aura/player information is omitted. Caster targeting has a separate saved checkbox under the aura source option and supports the default player aura icons outside combat. It preserves tooltip hover and right-click cancellation and skips weapon enchants, missing casters and restricted information. Compact party/raid layouts without portraits are unaffected. Chat icons support the default chat windows, including temporary windows; separate third-party chat windows are not integrated.

Feature behavior, saved settings, class colors, secure click attributes/state transitions, 3D model loading/fallback, links/history, asynchronous item loading and restricted information were checked in a mocked Lua runtime. English/French panel layouts were checked with rendered widget positions. Actual secure hardware clicks and portrait rendering still need validation inside Forever.

See [the detailed README](ZwykPlus/README.txt) for behavior, limitations and API source references.
