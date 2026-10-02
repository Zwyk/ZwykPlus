ZwykPlus 1.3.0 - WoW Forever

INSTALL
1. Close WoW.
2. Disable or remove the old HideUIErrors, MaxZoomForever and
   FindMineralsOnLogin addons. Their behavior can override these settings.
   Disable ChatLinkIcons if installed, to avoid duplicate chat icons.
3. Extract ZwykPlus into the Forever client's Interface/AddOns folder.
4. Confirm Interface/AddOns/ZwykPlus/ZwykPlus.toc exists.
5. Start WoW, enable ZwykPlus and use /zp or /zwykplus to open the setup.
   You can also open it through Settings > AddOns > ZwykPlus.

SETTINGS
All features are enabled initially. Updates preserve every existing setting;
new options are enabled when first introduced.
Every checkbox is saved automatically for all characters on this WoW account.
Changes take effect immediately. WoW writes SavedVariables to disk during
normal logout, exit or /reload; a crash may lose changes made in that session.
The settings are kept in ZwykPlusDB through the TOC SavedVariables entry.

Hide UI error messages
Stops UI_ERROR_MESSAGE delivery to UIErrorsFrame. The frame remains visible
for quest progress, informational messages and system messages. Turning the
option off restores the frame's previous error-event registration.
Error speech handled by this event can also be suppressed by this option;
no sound settings are changed. Direct messages from other addons are not
filtered. Other addons may override the frame's behavior.

Increase maximum camera distance
Requests cameraDistanceMaxZoomFactor = 4; the client enforces its own maximum.
If that request fails, it tries 2.6. "Also zoom fully out on login" controls
whether the camera is automatically moved all the way out after login/reload.
Disabling the main camera option restores the previous distance-limit CVar.
You can zoom in and out normally afterward. Zoning does not reset the camera.

Enable profession tracking on login
Enables selected mineral, herb and fish tracking only if available and
inactive. Find Fish requires that the character has learned the tracking
ability. Unsupported tracking abilities are skipped. English and French
clients use their localized spell names, with spell-ID matching when available.
The initial tracking check runs shortly after login/reload. It waits until
combat ends or the character is alive if necessary. Turning automation off
cancels a pending check and leaves the character's current tracking unchanged.
Individual tracking checkboxes control which abilities are automatically
enabled; unchecking one does not turn off a manually selected tracking ability.
If the client supports simultaneous tracking, all selected available abilities
are enabled. If only one is permitted, the final priority is Minerals, then
Herbs, then Fish. Tracking rules may also replace other active tracking.
The addon does not continuously enforce tracking or reapply it when zoning.

Show buff and debuff sources
Adds a "Source: Name" line to buff and debuff tooltips if WoW supplies an
accessible caster unit and name. Supports both beneficial and harmful auras
on the default UI, including tooltips on unit frames. Realm names are included
when available. This identifies the caster; it does not infer item, talent,
proc or environmental origins when WoW supplies no caster.
Unknown, out-of-range/unresolvable and restricted caster information is
omitted. Combat aura restrictions are respected; this feature cannot reveal
information the client does not expose. Third-party aura displays work when
they use WoW's standard aura tooltip functions.
The saved checkbox takes effect on the next tooltip display or rebuild.
To update, replace the ZwykPlus folder and /reload; existing settings survive.

Left-click a buff or debuff to target its caster
This saved sub-option belongs to "Show buff and debuff sources" and is enabled
initially. Turning off the parent feature disables click targeting while
preserving the sub-option's saved choice.
Left-click a default player buff/debuff icon to target the caster when the
character is outside combat and WoW supplies an accessible, existing source
unit. The caster is resolved from the icon's current aura at click time; it
is not remembered from the previous tooltip or a recycled button.
Right-click buff cancellation keeps its normal behavior. Weapon enchants,
edit-mode sample icons, expired auras and unknown/restricted sources are
skipped. Target/focus/party aura icons and third-party aura displays are not
integrated with click targeting in this release.
Targeting is restricted during combat, so clicks made in combat do nothing
and are never queued for later. A caster that cannot be targeted by the client
will not change your target. No secure buttons or combat actions are replaced.

Chat item icons
Displays an item's icon immediately before its link in the default chat
windows, including loot messages. Item name, quality color, hyperlink payload
and click behavior are preserved. Missing icons are requested from the client
and displayed when the item data becomes available. Unknown items are omitted.

Chat player class and race icons
Displays class, then race icons before clickable player names in default chat.
The two icons have separate saved checkboxes. Race icons use the character's
male/female variant when that information and an atlas are available.
Player GUIDs are learned from incoming chat and from your character, group,
target, focus and mouseover units. Name/realm pairs are kept distinct. Icons
appear only when WoW exposes the player's information; unknown players,
restricted information, missing icon atlases and NPC names are skipped.
Battle.net account names do not identify a specific character and are skipped.
Icons apply to player links, including character names linked within messages.
An unlinked/plain name is not guessed or decorated.
Icons are inserted at display time: the original chat history and outgoing
messages are unchanged. Toggling a checkbox refreshes visible chat immediately.
New and temporary default chat windows are supported. Separate third-party
chat windows (such as WIM) are not integrated in this release.
These features are implemented in ZwykPlus itself, without requiring or
bundling ChatLinkIcons. Other link types from that addon are not included.

"Apply enabled features" reapplies the selected options when requested.

INTERFACE VERSION
The TOC targets Interface 16001, matching the published Forever 1.60.1 UI
source (build 70170, exported October 1, 2026), rather than the earlier addons'
11507 Classic placeholder. Source:
https://github.com/Gethe/wow-ui-source/blob/forever/version.txt
Source commit: 9a789c074b8e73c5d604ef2d6af3bb5b3aefb348

If your particular beta build uses a different interface number, check it with:
/dump select(4, GetBuildInfo())
Replace 16001 in ZwykPlus.toc with that number and restart WoW.
No addon can update its own TOC before WoW performs the version check.
No version-check setting is disabled by ZwykPlus.

VALIDATION
The addon uses native WoW widgets and has no addon/library dependencies.
Saved settings, feature activation/deactivation, error/info event handling,
camera restoration, tracking selection, buff/debuff source tooltips and clicks,
chat icons, unchanged links/history, asynchronous item loading and
restricted/unknown information were checked in a mocked Lua runtime.
It has not yet been tested inside the Forever client.

Aura tooltip implementation references (Forever UI source):
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_BuffFrame/BuffFrame.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TargetScriptDocumentation.lua

Chat implementation references (Forever UI source):
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/ScrollingMessageFrame.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua
