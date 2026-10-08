# ZwykPlus

A small quality-of-life addon for **WoW Forever**, with a compact English/French setup panel and account-wide saved settings.

Current version: **1.18.0**. Interface version: **16001**.

## Features

- Hide UI error messages while keeping quest progress and other information visible.
- Increase the maximum camera distance, with optional full zoom out on login.
- Enable available mineral, herb and fish tracking on login when inactive.
- Show the caster of a buff or debuff in its tooltip, with player names in their class color.
- Add estimated spell DPS/HPS and damage/healing per resource cost to supported native spell tooltips, with periodic and AoE comparisons.
- Left-click a default player buff or debuff icon to target its caster outside combat using a secure click button.
- Show the rested XP reserve, as an amount and percentage of a level, on the native XP bar and its tooltip.
- Show average XP/hour, the rate without earned rested bonus, and estimated time to level on the native XP bar, with a click-to-reset confirmation.
- Optionally left-click unfinished objectives in the native quest tracker to target matching NPCs outside combat, with Questie-assisted item dropper matching and an optional raid marker.
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

## Changes in 1.18.0

- Fix two intermittent after-expiration reminder failures: unrelated aura events no longer supply another buff's removal time, and combat/encounter transitions preserve remembered timers when a fresh, complete public scan validates them. Early cancellation, dispels and consumed buffs still suppress the after-expiration glow. Restricted timing/identity data still clears history; entering the world resets the lifecycle.
- Expand **/zp buffs** diagnostics with public numeric timers, armed and active after-expiration reminders, validation state, last discarded spell/time and discard counts by reason. If a reminder still disappears, run this command shortly before and after expiration. `early-removal` identifies a removal before its recorded expiry; `restricted-*` and `missing-public-timing` identify data the addon cannot use; `expired-window` means the configured continuation has ended.
- Support **Consecration** as an AoE DoT with 1- and 4-target totals, effective duration DPS, cast/GCD output and efficiency. Include Forever's additional damage to the first four enemies. Each target is assumed to remain in the area for the full duration; caps apply to individual components.
- Give seals separate **Seal buff (full duration)** and **Judgement (one cast)** sections. Buff totals describe the seal's added output, using the current main-hand swing interval across its full duration, assuming all auto attacks land and excluding extra attacks. Judgement uses its own current spell cost and timing; its section does not consume or shorten the seal's assumed uptime. Command's normal Judgement assumes an unstunned target.
- Fury uses its displayed per-hit damage. Righteousness uses a pinned Forever rank/level/weapon/spell-power model rather than averaging its generic weapon-speed range; Improved Seals is included when its committed talent rank is readable, otherwise its bonus is explicitly excluded. Command applies its displayed weapon percentage to current weapon damage plus 29% of the player's Holy spell power, with a disclosed 7 base procs/min model. Proc chance uses base weapon delay and attack frequency uses the current swing interval. Its 1-second proc cooldown limits the estimated steady-state rate when swings are faster than one second. Target-only spell-power bonuses and unexposed Holy damage multipliers are excluded. Non-damage seals and unresolvable proc effects show why damage/healing rates are unavailable.
- Support explicit weapon-damage expressions. Holy Strike uses Forever's `percentage × (normalized weapon damage + flat bonus)` rule, current main-hand damage, attack power and the equipped item's base delay. Normalized delays are 1.7 s for daggers, 3.3 s for two-handed weapons and 2.4 s for other melee weapons. Physical-only damage multipliers are removed before the Holy conversion. Other explicit weapon expressions remain labelled estimates when their special normalization is unknown. Missing/private weapon data is not substituted with guessed numbers.
- Visible spell tooltips also refresh after player attack-speed, damage and attack-power changes, with the existing coalesced refresh and bounded text cache. Existing settings are preserved. Include **SpellSealModels.lua** when updating, then `/reload`.

Focused parser, tooltip/runtime, weapon/model and expiry regressions cover natural versus early removal, coalesced events, restricted data, combat/encounter transitions, independent seal/Judgement costs, current weapon changes, English/French wording and per-component AoE caps. Actual client rendering and live spell amounts still need an in-game check.

Model and API references are pinned to [Forever UI 1.60.1/70291](https://github.com/Gethe/wow-ui-source/tree/9465cb273b5513495d8ecc12fbb19930dd6b8957), including the native PaperDoll and aura update handling, and the current Forever simulation's [Holy Strike](https://github.com/ElliotWood/Forever/blob/56c11f4e2bc69caa5d7995aaf0ffb0e68466c730/sim/paladin/holy_strike.go), [Righteousness](https://github.com/ElliotWood/Forever/blob/56c11f4e2bc69caa5d7995aaf0ffb0e68466c730/sim/paladin/seal_of_righteousness.go), [Command](https://github.com/ElliotWood/Forever/blob/56c11f4e2bc69caa5d7995aaf0ffb0e68466c730/sim/paladin/seal_of_command.go) and [Consecration](https://github.com/ElliotWood/Forever/blob/56c11f4e2bc69caa5d7995aaf0ffb0e68466c730/sim/paladin/consecration.go). These are disclosed model estimates rather than measured combat DPS.

## Changes in 1.17.0

- Add **Auras → Spell DPS/HPS and efficiency**, enabled by default. Supported English/French spell tooltips show total damage/healing, output per cast, and damage/healing per point of mana, energy, rage or another named resource. Amount ranges use their average. These are estimates from the displayed tooltip, without adding Classic spell coefficients or spell power a second time; crits, misses, armor, resistances, overhealing and cooldowns are excluded.
- For DoTs/HoTs, show **Effective DPS/HPS (duration)** and **DPS/HPS (cast/GCD)** separately. For example, 120 damage over 12 seconds with a 3-second cast is 10 effective DPS and 40 DPS per cast time. Combined direct/periodic effects include both amounts, while each damage/healing rate uses its own effect duration. Channels use the full recognized channel duration. Instant casts use the client's available base GCD or an explicitly displayed 1.5-second reference; this is not a claim about real-time haste-adjusted rotational throughput. Off-GCD or unavailable timing keeps totals/efficiency and omits the undefined rate.
- For explicit AoE effects, display **1 target** and **4 targets** in two columns. The resource cost is paid once for the cast; four-target efficiency uses four targets' output divided by that same cost. An explicit smaller target cap limits the total and is shown in the column heading. Effects with chain falloff, shared damage, or mixed self/single/area scopes are omitted.
- Read the native spell-description lines when available, so those values take priority over a separate description getter. Support the native spellbook, spell action buttons and spell links, with guarded legacy setters. Resource efficiency uses public fixed current costs; variable, per-second, unavailable and inactive conditional costs are handled without inventing a flat mana/energy/rage amount. Unsupported weapon-percentage, reactive/proc, absorb, percentage-based, resource-restoration, delayed or otherwise ambiguous descriptions receive no calculation.
- Preserve native content and other addons' tooltip rows. Repeated native builds add one calculation block, live toggles rebuild through the original getter, and shown spell tooltips refresh after gear/spell/player-aura/haste updates with a coalesced callback. Parsed text is cached with a bounded size; no spellbook-wide scan or per-frame calculation is added.
- Include **SpellMetrics.lua** and **SpellTooltips.lua** when updating, then `/reload`. Existing preferences are preserved.

Validation covers 90 EN/FR parsing fixtures, direct/periodic/channel math, target caps, multi-resource and conditional costs, private data, duplicate hooks, live toggles, tooltip ownership, current description updates, delayed spell loading and coalesced refreshes. The English/French Auras page fits the existing window. Actual in-game descriptions and tooltip appearance still need a client check; unfamiliar wording is deliberately skipped.

The implementation was checked against Forever's [spell API](https://github.com/Gethe/wow-ui-source/blob/15666a6e67938a1ab5caf041406464251db111ca/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua), [resource-cost structure](https://github.com/Gethe/wow-ui-source/blob/15666a6e67938a1ab5caf041406464251db111ca/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellSharedDocumentation.lua), [spellbook API](https://github.com/Gethe/wow-ui-source/blob/15666a6e67938a1ab5caf041406464251db111ca/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua) and [tooltip processor](https://github.com/Gethe/wow-ui-source/blob/15666a6e67938a1ab5caf041406464251db111ca/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua). These APIs expose cast/cost information and rendered text, with no public numeric damage/healing effect structure.

## Changes in 1.16.0

- Add **Interface → Items and experience → XP/hour and time to level**, enabled by default. The native XP bar shows average earned XP/hour, XP/hour with the observed rested bonus removed, and estimated time to the next level. Other bonuses, including group and XP buffs, remain included. The tooltip adds elapsed time, total XP and rested bonus earned since reset.
- Left-click the native XP bar or its rested tick to open a **Reset / Cancel** confirmation. Only confirming starts a new average. Statistics persist per character across `/reload` and normal logout; the denominator counts online time, including idle time, and excludes time logged out. Recording continues when the display setting is off.
- Track actual player XP changes, including a one-level rollover, and use the client's localized combat XP messages to identify rested bonus and eligible mob XP. Reconcile quest rewards against the remaining native XP gain without counting an unnamed chat message and quest reward twice. Unsupported or private information leaves the affected rate or estimate as **--**, with an explanation in the tooltip. Missing player XP updates or an unobserved jump across several levels require a reset before another reliable average can be shown.
- Estimate the next level using the observed mix of eligible mob XP and other XP, the current remaining XP, and the remaining rested reserve. The estimate applies the rested boost only until that reserve runs out; it does not double quest XP or assume rested XP lasts to the next level. It assumes that your recent pace and mix of activities continue.
- Keep native hover behavior, text visibility and tooltip content. Live changes, repeated refreshes and resets update only the addon's text block; disabling both XP display options restores native text. Include **XPStats.lua** when updating, then `/reload`.

The native rested bar exposes a threshold spanning doubled XP, rather than a separately documented bonus capacity. The estimate initially uses half that threshold, following [XToLevel's implementation](https://github.com/dangard/XToLevel/blob/d0e1b98cd2dabc28b50830e391be47393d2db0b6/objects/Player.lua), and can validate the unit conversion against a fully classified bonus gain outside a resting area. The existing reserve display retains the same native threshold and percentage.

Focused runtime checks cover XP rates, finite-rest estimates, mixed quest/mob XP, localized formats, quest/chat deduplication, event ordering, persistence, reset confirmation, unavailable data and recording while hidden. Integration checks cover both native bar layouts, tooltip ownership, live toggles and late frames; English/French settings layouts are rendered and checked. Actual client rendering and XP message formats still need an in-game check.

Native behavior was checked against Forever's [XP bar](https://github.com/Gethe/wow-ui-source/blob/15666a6e67938a1ab5caf041406464251db111ca/Interface/AddOns/Blizzard_StatusTrackingBar/Shared/ExpBar.lua), [XP events](https://github.com/Gethe/wow-ui-source/blob/15666a6e67938a1ab5caf041406464251db111ca/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua) and [quest events](https://github.com/Gethe/wow-ui-source/blob/15666a6e67938a1ab5caf041406464251db111ca/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua).

## Changes in 1.15.0

- Add **Interface → Items and experience → Rested XP reserve**, enabled by default. Append the native rested XP threshold and its percentage of the current level's total XP to the native bar text and tooltip. For example, 15,000 rested XP with a 10,000 XP level displays 150%; this percentage describes the reserve, while the native tooltip's 200% describes the XP earning rate. Updates follow XP, resting and level changes; disabling restores native text. Max-level, XP-disabled and unavailable data are omitted.
- Add **Automation → Click objectives to target → Configure**. **Use Questie data when available** starts enabled and needs an installed, ready Questie. Match the native objective against Questie's own database wording or localized entity name rather than trusting row order. Quest items resolve to actual NPC droppers, excluding vendors, containers and world objects; verified monster, kill-credit and explicitly linked NPC event objectives are also supported. Unsupported or ambiguous objectives keep their native behavior, with simple English/French kill objectives available without Questie.
- When several NPC names match, prefer current-zone spawns and cycle through the names on successive clicks. The tooltip shows the next name and its position in the list. Each click runs one `/targetexact`, within WoW's normal targeting range; it does not locate distant units or choose an arbitrary world object.
- Add **Automatically mark the selected NPC**, disabled by default, with all eight native raid markers and Skull selected initially. Only the hardware quest click attempts marking, outside combat, after verifying the selected NPC's name and known database IDs. Existing markers are preserved; unavailable marker information, restricted targets or group permissions can prevent marking. No target-change event or delayed callback applies a marker.
- Preserve existing settings and quest click recovery after combat. Include both new Lua modules when updating, then `/reload`.

Focused mocked-runtime checks cover XP text and tooltip ownership, live updates and disabling, late native bars, Questie readiness and database matching, actual droppers, ambiguous objectives, localized counter layouts, multi-target cycling, pooled tracker rows, combat recovery and marker identity/permissions. English/French configuration layouts are rendered and checked. Native display and protected marker execution still need confirmation inside Forever.

The Questie adapter was checked against [QuestieDB](https://github.com/Questie/Questie/blob/42ee926c519ed5d23be4ffc3e3d36d746e4edd7a/Database/QuestieDB.lua), [objective construction](https://github.com/Questie/Questie/blob/42ee926c519ed5d23be4ffc3e3d36d746e4edd7a/Modules/Quest/QuestieQuest.lua) and [readiness callbacks](https://github.com/Questie/Questie/blob/42ee926c519ed5d23be4ffc3e3d36d746e4edd7a/Public/README.md). Questie has no stable public objective-to-NPC API, so unavailable or changed database methods fall back to native kill matching.

## Changes in 1.14.0

- Select an independent glow style for **Before expiration** and **After expiration**: **Pixel Glow**, **Action Button Glow**, **Autocast Shine** or **Proc Glow**. Defaults are Pixel before expiration and Action Button after expiration. Effects are anchored to the native spell icon; broad halos extend around that icon according to their original style. Native spell-proc effects remain independent.
- Use one **shared color and transparency** for both stages. Click the color swatch to open Blizzard's color picker, or use the transparency slider from 0% (fully visible) to 100% (invisible). Live changes preserve an active preview. **Cancel** or **Escape** restores both original values, including the client's hide-before-cancel behavior.
- Add separate five-second **Before** and **After** previews. Commands: **/zp test buffs** and **/zp test buffs after**. No spell is cast or simulated expired timer remembered by an appearance preview.
- Apply shared color and transparency to the native **!** fallback too. Fully private aura data retains that native marker and its existing duration limitations; glow-style choices apply to the public reminder display.
- Embed [LibCustomGlow minor 25](https://github.com/Stanzilla/LibCustomGlow/tree/4f8f5c2607d7384b26df9175bb99fa3df891b015) and LibStub 2, with their MIT/public-domain licenses and pinned source references in `Libs/`. The effect host contains only ordinary color/opacity values; the independent outer frame alone receives the client's opaque duration-to-alpha output.

Regression checks run the embedded library's four effects under a UI fixture and cover style switching, shared RGB/opacity, previews, protected duration isolation, native color rebinding, saved-setting migration and picker ownership/cancellation. English/French configuration layouts are rendered and checked. Final effect appearance still needs confirmation in the Forever client.

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

The addon targets Forever Interface 16001 and has no required external dependencies. LibCustomGlow and LibStub are bundled; Questie is optional for additional objective matching. Unknown or restricted aura/player information is omitted. Aura source lines require an addon-accessible tooltip; private forbidden native target aura tooltips cannot be extended. Caster targeting has a separate saved checkbox under the aura source option and supports the default player aura icons outside combat. It preserves tooltip hover and right-click cancellation and skips weapon enchants, missing casters and restricted information. Compact party/raid layouts without portraits are unaffected. Chat icons support the default chat windows, including temporary windows; separate third-party chat windows are not integrated.

Feature behavior, saved settings, class colors, secure click attributes/state transitions, hidden/asynchronous model loading, idle animation, 2D fallback, reload decisions, public aura setter coverage, surname formatting, links/history, asynchronous item loading and restricted information were checked in a mocked Lua runtime. English/French panel layouts were checked with rendered widget positions. The strengthened portrait test fails against 1.4.0 and passes against 1.4.1. Actual secure hardware clicks, reload permission and portrait rendering still need validation inside Forever.

Version 1.5.0 adds regression checks for viewport bounds, independent portrait animations during target/focus/portrait events, unit-identity caching, and native class-colored name restoration. In-game portrait appearance and animation continuity still need confirmation.

Version 1.5.1 checks the larger viewport, background/model/overlay ordering, texture visibility during loading and fallback, safe background colors, retained animations and the new TGA assets. Actual visual blending still needs confirmation inside Forever.

Version 1.6.0 uses a shared-alpha texture mock to catch color updates that restore opacity. Checks cover transparent, partial and opaque backgrounds, class/black colors, live resizing, combat deferral, settings validation and saved values, unchanged animations, 2D fallback and both localized configuration layouts. Final rendering still needs an in-game check.

Version 1.7.0 checks binding per item instance, bag/roll reuse, delayed item data, restricted values, live toggling and the two transparent chain textures. Final icon placement still needs an in-game check.

Version 1.8.0 checks exact player targets, independent target switches, plate reuse/removal, live toggling, bounded updates, safe secret-boolean rendering and the new eye texture. English/French Frames layouts are checked. Final eye placement and client-side secret rendering still need in-game confirmation.

Version 1.8.1 checks BetterBags' actual message dispatcher, inventory/bank bindings, represented merged groups, grid/list/theme decorations, clearing/reuse, late initialization and live settings. Native bag and roll checks still pass. Final placement with installed BetterBags themes needs in-game confirmation.

Version 1.8.2 checks category ownership, hidden bars with retained names, selection highlights, native opacity updates, pooled frame reuse, live settings, combat deferral, failed writes and pending restoration across reloads. Secret alpha is passed directly back to its rendering API without inspection. English/French layouts pass; actual client restrictions and other nameplate addons need in-game confirmation.

See [the detailed README](README.txt) for behavior, limitations and API source references.
