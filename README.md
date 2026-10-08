# ZwykPlus

A small quality-of-life addon for **WoW Forever**, with a compact English/French setup panel and account-wide saved settings.

Current version: **1.13.0**. Interface version: **16001**.

## Features

- Hide UI error messages while keeping quest progress and other information visible.
- Increase the maximum camera distance, with optional full zoom out on login.
- Enable available mineral, herb and fish tracking on login when inactive.
- Show the caster of a buff or debuff in its tooltip, with player names in their class color.
- Left-click a default player buff or debuff icon to target its caster outside combat using a secure click button.
- Optionally left-click simple unfinished kill objectives in the native quest tracker to target the exact monster name outside combat.
- Optionally highlight native spell buttons shortly before supported class buffs on the player expire, with a configurable warning threshold.
- Optionally replace native 2D portraits with head-focused 3D portraits using the idle animation, with a 2D fallback.
- Optionally color player names on native unit frames by class, retaining normal NPC name colors.
- Optionally show small binding chain icons on native bags, BetterBags and loot-roll item icons.
- Optionally show an eye above existing visible, accessible nameplates for units currently targeting you.
- Optionally show a movable healer mana summary while in a party or raid, with individual percentages and a group average.
- Optionally show a movable taxi-flight progress bar, with estimated destination and intermediate-stop countdowns.
- Show icons beside linked items in chat.
- Show separate class and race icons beside linked player names when WoW provides the information.

The setup has six categories: **Interface, Automation, Auras, Frames, Travel and Chat**. The opaque 600 × 390 window remembers the selected category. Feature toggles and appearance settings are saved. Existing settings are preserved when updating; 3D portraits, nameplate targeting eyes and healer mana summaries start disabled and can be enabled under Frames. Item binding icons also start disabled, under Interface; flight progress starts disabled, under Travel. Quest objective targeting starts disabled under Automation, and buff reminders start disabled under Auras.

## Changes in 1.13.0

- Add **After expiration** to buff reminder configuration, from 0 to 100% of the buff's total duration, default 20%. For a 30-second seal, 20% keeps the reminder for 6 seconds after its recorded expiration. Set 0% to disable continuation. A readable refresh replaces the timer; removal before expiration cancels it. Only buffs observed while active with readable duration and expiration can start this timer. Restricted or ambiguous aura data, disabling the feature, or removing its mapped spell buttons discards remembered timers.
- Replace the fixed gold border with an **animated gold glow**, with a soft halo, pulsing edge and eight moving lights. Anchor the bright edge directly to the native spell icon's bounds, so a larger action button does not enlarge the outline. Create glow frames only for supported spell buttons, keep native proc effects independent, and animate only public candidate displays or the five-second preview.
- Preserve the native gold **!** fallback for wholly private auras. Blizzard's native aura display ends when an aura disappears; no secret duration or visibility is read back to infer a post-expiration timer. Duration objects with accessible handles can still drive the public glow through the client's alpha display API.
- Add the post-expiration percentage to **/zp buffs** diagnostics, update English/French help, and expand the configuration panel for both sliders. Existing settings remain preserved.

Regression checks cover natural expiration, timer bounds, refreshing, early removal, disabled continuation, inaccessible timing, mapping changes, icon alignment, animated lights in combat and native private display isolation. Actual glow appearance still needs confirmation in the Forever client.

## Changes in 1.12.0

- Restore quest objective clicks reliably after combat. The addon retries during the transition until combat lockdown has actually cleared, cancels stale callbacks when a new combat starts or the option is disabled, and refreshes when the native tracker or recycled rows become visible again.
- Change buff reminders to a **remaining percentage of the buff's total duration**, from 5 to 100%, default 20%. For example, 20% means the final 6 seconds of a 30-second seal or the final minute of a 5-minute blessing. Existing enable choices are preserved; the old seconds setting is removed. Permanent buffs do not trigger an expiration reminder.
- Expand Paladin support to **Seals of Fury, Righteousness, Command, Justice, Light, Wisdom and the Crusader**, **Righteous Fury**, **Blessings of Freedom, Protection and Sacrifice**, **Divine Protection**, **Divine Shield**, **Holy Shield** and **Templar's Bulwark**, in addition to existing blessings. Include Classic ranks and the new Forever Fury ranks. Reminders track buffs on the player; casting a blessing on another unit does not create a reminder for that unit.
- Remove an unnecessary second action-slot check that could reject overridden or ranked spells. Use Blizzard's current paged action slot to match direct spell buttons. Native spell-proc glows remain independent; macros and third-party action bars remain outside the supported scope.
- Keep the gold border for accessible aura data. Also configure a gold **!** on the native spell button through Blizzard's custom aura display API, with the client selecting the aura and applying the percentage threshold. This supports private aura display without inspecting hidden spell identities or comparing secret countdown values in addon Lua. Configuration changes that require setup in combat wait until combat ends.
- Add **Preview** in the buff reminder configuration, or **/zp test buffs**, to show the gold border for five seconds without casting or changing the saved option. **Buff diagnostics**, or **/zp buffs**, prints mapped button counts, public timing availability and native renderer setup status in chat. The diagnostic does not inspect private aura state.

Regression checks cover delayed combat release, tracker visibility, percentage thresholds, Paladin spell families, secret rendering sinks, native renderer configuration and preview cleanup. Actual native marker appearance still needs confirmation in the Forever client.

## Changes in 1.11.1

- Replace the flight route's Unicode arrow with `->`, which displays correctly with the native font.
- Add a small close button to the flight progress bar. It hides the window for the current flight only, without disabling the option or interrupting route-time learning. The bar returns on the next flight. Closing a preview ends that preview.

## Changes in 1.11.0

- Add **Automation → Click kill objectives to target**. Left-click compatible unfinished monster objectives in the native quest tracker to run `/targetexact` for their name. Simple English `X slain` and French kill-objective wording are supported. The click layer disappears in combat, and recycled/completed lines clear their old targeting association. Header actions and item objectives retain their native behavior. Targeting uses the game's normal range and name matching; it does not locate arbitrary units across the map.
- Add **Auras → Highlight buffs before expiration → Configure**. A separate gold border highlights native spell buttons before a supported buff on the player expires. The warning threshold defaults to 30 seconds and can be set from 5 to 120 seconds. Refreshing or removing a buff clears the warning. Another player's buff also counts.
- Initially support paladin blessings, priest Fortitude/Spirit, mage Intellect and druid Mark, with ranks and group versions. Match the buff family to the spell buttons; macros and third-party action bars are outside this first version. Unavailable aura identities or timing access are skipped. Secret countdowns use the client's supported duration-to-alpha display API; no protected duration is compared in addon Lua.
- Questie-assisted item-to-monster targeting is deferred. Target aura countdowns are also deferred: no supported way was found to enable numbers directly on Forever's forbidden native target aura icons, and no replacement aura display is added.

The new modules have focused regression checks for combat restrictions, recycled quest rows, buff refresh/removal, action changes and unavailable aura data. Visual appearance and restricted behavior still require confirmation in the Forever client.

## Changes in 1.10.0

- Add **Travel → Flight progress**, an optional bar shown during taxi flights, with destination, elapsed time and estimated remaining time. Intermediate stops show their names and countdowns when route data is available. Gray stops indicate their estimated passing time, rather than confirmed arrival. Use the mouse wheel to scroll long routes.
- Use initial Classic flight observations as estimates on Forever, adjusted for the 20% Frequent Flier speed bonus when its rank is readable. Completed flights refine the full ordered route's duration; learned timings are saved for the account, separately by faction and direction. Only normal completed flights with confirmed taxi exit and regained control are learned. Early landing, death, reloads and disabling the feature do not record a duration.
- Unknown routes, including new Forever routes without initial data, show **?** and elapsed time until a valid complete flight is learned. Intermediate countdowns remain **?** where segment durations are unknown, even if the whole route's duration has been learned. Intermediate points describe the route; they are not a guarantee that landing is allowed at each point.
- Hold **Alt** and drag with the left mouse button to move the bar. Position is saved per character. **Preview** or **/zp flight** shows a short demonstration for positioning, and **Reset position** returns it to its default location.
- **Land at next stop** requests early landing through the native client API. WoW chooses the next allowed stopping point; the addon does not select an arbitrary stop or request landing automatically. After a request, overall remaining time becomes **?**, since the actual stopping point is unknown; intermediate countdowns continue as estimates.
- Reloading during a flight hides the bar until the next takeoff. It does not resume an old timer that could include time spent outside the client.

Initial timings comprise 879 directed Classic observations adapted from [InFlight's data](https://github.com/LudiusMaximus/InFlight/blob/310f5fa167c6171ec2858561077ec441989541ae/Defaults.lua). Attribution and the full MIT license are included in `FlightData.lua`. These observations are a starting estimate, not verified Forever timings.

## Changes in 1.9.0

- Add **Frames → Healer mana summary**, an optional frame showing healer mana percentages and a group average while in a party or raid. Enabling or disabling it applies immediately.
- Place the summary above the native party/raid frames by default. Hold **Alt** and drag with the left mouse button to move it. Its position is saved per character; **Reset position** returns it above the native group frames.
- Use assigned healer roles automatically. If the group has no assigned roles, right-click the summary or use **/zp healers** to choose members. Manual choices are saved per character; **Use assigned roles** clears those overrides. Healers are not inferred from class alone.
- Average readable mana percentages of alive, connected healers equally. Dead, offline or unreadable values do not contribute to the average. Restricted percentages can still appear individually through the client's supported text display API; otherwise unavailable percentages display **?**.

## Changes in 1.8.5

- Remove **Eyes with nameplates hidden** and its replacement names. Keep the original targeting-eye option on existing visible, accessible nameplates without changing their appearance or enabling additional nameplate categories.
- Updating restores visibility settings previously changed by the removed option. Restoration waits until combat ends if necessary. Floating world names without an accessible nameplate cannot display the eye.

## Changes in 1.8.4

- Fix BetterBags binding chains changing size after login or a vendor redraw. Size follows the current item decoration rather than an unfinished icon-texture width, and updates when the layout resizes. Grid icons use 14-pixel chains; small list-row icons use 10-pixel chains.

## Changes in 1.8.3

- Give **Eyes with nameplates hidden** compact shadowed names, complete readable unit names and reaction colors, closer to WoW's floating names. An optional smaller guild line respects WoW's guild-name setting. Names remain centered without the native label's width restriction.
- Use the fallback only where the original nameplate visibility settings would hide a plate. Full nameplates retain their normal appearance; native automatic visibility keeps its combat and confirmed-current-target exceptions. Names and guilds respect WoW's display settings.
- The fallback still needs an accessible, game-provided nameplate. It cannot extend nameplate range or attach an eye to floating world names alone beyond that range. Restricted names or frames and other nameplate addons can limit the result; final appearance needs an in-game check.

## Changes in 1.8.2

- Add **Frames → Nameplates → Eyes with nameplates hidden**, an optional setting beneath the targeting-eye checkbox. It activates disabled friendly/enemy player, NPC, minion and minor-unit nameplate categories internally, hides their native bars and keeps accessible native names. Enabled categories retain their normal bars. Automatic visibility uses hidden bars outside combat, except a confirmed current target in an enabled category.
- Restore previous visibility settings and native visual state when disabled. Visibility changes wait until combat ends; pending restores are saved per character across combat reloads. Frame reuse and native opacity updates retain the correct original visual state.
- This still uses WoW's nameplate anchors: range, restricted frames and unavailable target data limit coverage. Minion classification and automatic-display exceptions depend on client behavior. Other nameplate addons or inaccessible native children can prevent complete visual hiding; verify the result in game.

## Changes in 1.8.1

- Support BetterBags item binding icons automatically using the existing checkbox, including inventory/bank items, merged groups, list rows and themed decorations. Chains sit at the top-right of BetterBags icons, leaving upgrade arrows, item levels and counts available; small row icons use a smaller chain.
- Clear markers before pooled items are reused or become empty/browser entries. Query the represented physical slots and omit inconsistent merged binding states. Late loading, theme changes, live toggles and item-data updates refresh existing icons.
- Audited against the supplied BetterBags 0.5.14 source; both addons' upgrade arrows and chains use independent overlays without changing BetterBags' selected upgrade provider.

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

Version 1.8.1 checks BetterBags' actual message dispatcher, inventory/bank bindings, represented merged groups, grid/list/theme decorations, clearing/reuse, late initialization and live settings. Native bag and roll checks still pass. Final placement with installed BetterBags themes needs in-game confirmation.

Version 1.8.2 checks category ownership, hidden bars with retained names, selection highlights, native opacity updates, pooled frame reuse, live settings, combat deferral, failed writes and pending restoration across reloads. Secret alpha is passed directly back to its rendering API without inspection. English/French layouts pass; actual client restrictions and other nameplate addons need in-game confirmation.

See [the detailed README](README.txt) for behavior, limitations and API source references.
