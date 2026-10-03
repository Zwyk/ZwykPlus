# ZwykPlus

A small quality-of-life addon for **WoW Forever**, with a compact English/French setup panel and account-wide saved settings.

Current version: **1.4.1**. Interface version: **16001**.

## Features

- Hide UI error messages while keeping quest progress and other information visible.
- Increase the maximum camera distance, with optional full zoom out on login.
- Enable available mineral, herb and fish tracking on login when inactive.
- Show the caster of a buff or debuff in its tooltip, with player names in their class color.
- Left-click a default player buff or debuff icon to target its caster outside combat using a secure click button.
- Optionally replace native 2D portraits with head-focused 3D portraits using the idle animation, with a 2D fallback.
- Show icons beside linked items in chat.
- Show separate class and race icons beside linked player names when WoW provides the information.

The setup has five categories: **Interface, Automation, Auras, Frames and Chat**. The opaque 600 × 390 window remembers the selected category. Every option has a saved checkbox. Existing settings are preserved when updating; 3D portraits start disabled and can be enabled under Frames.

## Changes in 1.4.1

- Fixed a silent portrait loading problem: models are shown transparently before loading, kept across hides, and checked until ready. The original 2D portrait remains visible during loading. Missing readable GUIDs no longer prevent loading a public unit token.
- Explicitly set head zoom and looping Stand/idle animation. Added a copyable report under **Frames → Portrait diagnostics**, also available with `/zp portraits`.
- Portrait-mode changes are saved immediately and applied on reload. **Apply enabled features** reloads only when the saved portrait mode differs from the current session; a small warning appears beside it. Combat blocks reload and requires another click afterward. Other options stay live; model failures never trigger reload loops.
- Corrected two-part player names using Forever's native surname formatter, retaining the space in `Zwyk Zw`.
- Added source hooks for public unit-frame aura tooltip setters, including target/focus/party and instance-ID tooltips. **Forever's private native target aura tooltip remains unsupported**: its tooltip and aura metadata are forbidden to addons, so this update cannot safely add a source line there. Public addon tooltips using normal aura setters are supported.

If portraits still stay in 2D, open `/zp portraits`, copy the report with Ctrl+C, and include it with a screenshot. The report shows each native frame's loading/fallback reason, model visibility and head/idle configuration without logging GUIDs.

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

The addon targets Forever Interface 16001 and has no addon or library dependencies. Unknown or restricted aura/player information is omitted. Aura source lines require an addon-accessible tooltip; private forbidden native target aura tooltips cannot be extended. Caster targeting has a separate saved checkbox under the aura source option and supports the default player aura icons outside combat. It preserves tooltip hover and right-click cancellation and skips weapon enchants, missing casters and restricted information. Compact party/raid layouts without portraits are unaffected. Chat icons support the default chat windows, including temporary windows; separate third-party chat windows are not integrated.

Feature behavior, saved settings, class colors, secure click attributes/state transitions, hidden/asynchronous model loading, idle animation, 2D fallback, reload decisions, public aura setter coverage, surname formatting, links/history, asynchronous item loading and restricted information were checked in a mocked Lua runtime. English/French panel layouts were checked with rendered widget positions. The strengthened portrait test fails against 1.4.0 and passes against 1.4.1. Actual secure hardware clicks, reload permission and portrait rendering still need validation inside Forever.

See [the detailed README](ZwykPlus/README.txt) for behavior, limitations and API source references.
