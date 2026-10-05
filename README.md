# ZwykPlus

A small quality-of-life addon for **WoW Forever**, with a compact English/French setup panel and account-wide saved settings.

Current version: **1.8.0**. Interface version: **16001**.

## Features

- Hide UI error messages while keeping quest progress and other information visible.
- Increase the maximum camera distance, with optional full zoom out on login.
- Enable available mineral, herb and fish tracking on login when inactive.
- Show the caster of a buff or debuff in its tooltip, with player names in their class color.
- Left-click a default player buff or debuff icon to target its caster outside combat using a secure click button.
- Optionally replace native 2D portraits with head-focused 3D portraits using the idle animation, with a 2D fallback.
- Optionally color player names on native unit frames by class, retaining normal NPC name colors.
- Optionally show small binding chain icons on native bag and loot-roll item icons.
- Optionally show an eye above visible nameplates of units currently targeting you.
- Show icons beside linked items in chat.
- Show separate class and race icons beside linked player names when WoW provides the information.

The setup has five categories: **Interface, Automation, Auras, Frames and Chat**. The opaque 600 × 390 window remembers the selected category. Feature toggles and appearance settings are saved. Existing settings are preserved when updating; 3D portraits and nameplate targeting eyes start disabled and can be enabled under Frames. Item binding icons also start disabled, under Interface.

## Changes in 1.8.0

- Add **Frames → Nameplates → Eye on units targeting you**, a saved option that applies immediately. A small pale gold eye appears above each visible, accessible nameplate whose unit currently targets the player. Enable the relevant nameplates in WoW's settings; the addon does not turn them on automatically.
- Refresh on target/nameplate events and every 0.2 seconds while enabled with active plates. Removed, hidden and reused plates clear old markers. This checks the actual target rather than threat or aggro.
- Use Forever's supported `SetAlphaFromBoolean` display API for secret target comparisons without inspecting the result. If this rendering API is unavailable, only readable comparisons are displayed. Missing targets and forbidden/private plates are omitted.
- Include `Textures/NameplateTargetEye.tga` when updating and restart WoW to load the new texture.

## Changes in 1.7.2

- Show open chains at 75% opacity to distinguish them from fully opaque closed chains.

## Changes in 1.7.1

- Move the open chain's break to the junction between its two links, keeping both outer ends closed.

## Changes in 1.7.0

- Add **Interface → Items → Item binding icons**, a saved option that applies immediately to native bags, combined bags and loot-roll icons. A small closed chain marks a currently soulbound bag item; an open chain marks an unbound Bind on Equip item. In rolls, closed means Bind on Pickup, since the item has not yet been awarded.
- Read binding separately for each bag slot, including after moving or equipping an item. Reused icons and delayed item data refresh the marker. Unknown, restricted, quest and account-bound states are omitted; account-until-equip items can show the closed chain after confirmed soulbinding. Item clicks, counts and roll actions are unchanged.
- Include both new chain textures when updating and restart the client so it can load the new files.

## Changes in 1.6.1

- Draw portrait configuration and diagnostics above the main options window and its controls, including after reopening either window.

## Changes in 1.6.0

- Fix portrait transparency after color updates: opacity is applied with the final vertex color, and both added textures are hidden at 100% transparency. The previous creation-time alpha could be overwritten by a later color update. The model and native border remain visible.
- Add **Frames → Enable 3D portraits → Configure** with saved sliders for **Model size** (50–100%, default 76.5%) and **Background transparency** (0–100%, default 100%), plus **Class-colored background**. Turning class coloring off uses black; NPCs and unavailable class colors also use black.
- Appearance settings apply live without rebinding models or restarting idle animations. Size changes made in combat apply afterward. Enabling or disabling 3D portraits still requires a reload. Apply preserves unchanged animations and retries failed models.
- Diagnostics now show the requested appearance settings and actual background/overlay alpha values.

## Changes in 1.5.2

- Set initial backdrop and overlay opacity to zero while preserving the larger viewport, border and animation. Later color updates could restore opacity; this is corrected in 1.6.0. Circular clipping remains unavailable.

## Changes in 1.5.1

- Use Adapt's portrait layering approach: a circular background below the 3D model and a soft circular overlay above it. The centered viewport grows from 68% to 76.5% of the portrait diameter for a larger head area. Backgrounds use muted class colors for readable player classes and neutral gray otherwise.
- Keep the existing head zoom, looping idle animation, unit-specific updates and 2D fallback. Both added textures stay hidden during loading or fallback. This softens the square edges visually; `PlayerModel` still has no true circular clipping, so some model geometry can extend beyond the circle.
- Include the new `Textures` folder when updating, then restart the client so it can load the new texture files.

## Changes in 1.5.0

- Fit each 3D model's rectangular viewport inside its native circular portrait border. Forever does not expose circular masking for `PlayerModel`, so the viewport is centered at 68% of the portrait diameter to keep its corners within the rim. The 3D head area is smaller; the native 2D texture and border remain unchanged.
- Scoped target, focus and unit-model updates to the affected portraits. Changing targets no longer restarts the player's or other unrelated idle animations. Unchanged readable unit identities retain their animation, including hiding and showing the same target; a newly assigned target model starts its own idle animation.
- Added **Frames → Class-colored player names**, a saved option that applies immediately. Player names use class colors; NPC names and disabling the option restore the native colors. Names and surnames are unchanged.

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

1. Clone this repository, or download it using **Code → Download ZIP**.
2. Copy the repository folder into your Forever client's `Interface/AddOns` directory, naming the folder `ZwykPlus`. If you downloaded the ZIP, extract it and rename `ZwykPlus-main` to `ZwykPlus` before copying.
3. Confirm that `Interface/AddOns/ZwykPlus/ZwykPlus.toc` exists.
4. Enable ZwykPlus and restart WoW or run `/reload`.
5. Open the setup with `/zp` or `/zwykplus`, or through **Settings → AddOns → ZwykPlus**.

Disable the old standalone HideUIErrors, MaxZoomForever and FindMineralsOnLogin addons. Disable ChatLinkIcons if installed to avoid duplicate chat icons.

WoW saves settings to disk on normal logout, exit or `/reload`.

## Compatibility and validation

The addon targets Forever Interface 16001 and has no addon or library dependencies. Unknown or restricted aura/player information is omitted. Aura source lines require an addon-accessible tooltip; private forbidden native target aura tooltips cannot be extended. Caster targeting has a separate saved checkbox under the aura source option and supports the default player aura icons outside combat. It preserves tooltip hover and right-click cancellation and skips weapon enchants, missing casters and restricted information. Compact party/raid layouts without portraits are unaffected. Chat icons support the default chat windows, including temporary windows; separate third-party chat windows are not integrated.

Feature behavior, saved settings, class colors, secure click attributes/state transitions, hidden/asynchronous model loading, idle animation, 2D fallback, reload decisions, public aura setter coverage, surname formatting, links/history, asynchronous item loading and restricted information were checked in a mocked Lua runtime. English/French panel layouts were checked with rendered widget positions. The strengthened portrait test fails against 1.4.0 and passes against 1.4.1. Actual secure hardware clicks, reload permission and portrait rendering still need validation inside Forever.

Version 1.5.0 adds regression checks for viewport bounds, independent portrait animations during target/focus/portrait events, unit-identity caching, and native class-colored name restoration. In-game portrait appearance and animation continuity still need confirmation.

Version 1.5.1 checks the larger viewport, background/model/overlay ordering, texture visibility during loading and fallback, safe background colors, retained animations and the new TGA assets. Actual visual blending still needs confirmation inside Forever.

Version 1.6.0 uses a shared-alpha texture mock to catch color updates that restore opacity. Checks cover transparent, partial and opaque backgrounds, class/black colors, live resizing, combat deferral, settings validation and saved values, unchanged animations, 2D fallback and both localized configuration layouts. Final rendering still needs an in-game check.

Version 1.7.0 checks binding per item instance, bag/roll reuse, delayed item data, restricted values, live toggling and the two transparent chain textures. Final icon placement still needs an in-game check.

Version 1.8.0 checks exact player targets, independent target switches, plate reuse/removal, live toggling, bounded updates, safe secret-boolean rendering and the new eye texture. English/French Frames layouts are checked. Final eye placement and client-side secret rendering still need in-game confirmation.

See [the detailed README](README.txt) for behavior, limitations and API source references.
