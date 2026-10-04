ZwykPlus 1.7.0 - WoW Forever

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
The compact, opaque setup has Interface, Automation, Auras, Frames and Chat
categories. It remembers the last selected category.
Features are enabled initially except 3D portraits and class-colored frame
names (opt-in under Frames), and item binding icons (opt-in under Interface).
Updates preserve every existing setting.
Every checkbox is saved automatically for all characters on this WoW account.
Most changes take effect immediately. Portrait mode applies on a UI reload;
the warning beside Apply appears only when the saved mode differs from the
current session. Apply reapplies live features and reloads for that pending
portrait change. During combat it asks for another click outside combat;
it never queues an automatic reload. Reverting to the current mode clears
the warning. Model loading failures do not trigger reloads.
WoW writes SavedVariables to disk during
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
on addon-accessible default tooltips, including public unit-frame aura setters.
Native name formatting preserves Forever's two-part surname with a space.
This identifies the caster; it does not infer item, talent,
proc or environmental origins when WoW supplies no caster.
Player caster names use their class color when that information is accessible.
NPCs and unavailable class colors use the neutral source color.
Unknown, out-of-range/unresolvable and restricted caster information is
omitted. Combat aura restrictions are respected; this feature cannot reveal
information the client does not expose. Third-party aura displays work when
they use WoW's standard aura tooltip functions.
Version 1.4.1 hooks public setters even when TooltipDataProcessor is available,
covering target, focus, party, raid and pet tooltips built through those APIs.
LIMITATION: Forever's native target aura display uses a private forbidden
AuraButtonTooltip. Its aura button API also keeps source metadata private
and prohibits focus queries. ZwykPlus cannot safely add a line to that tooltip
or infer its current caster from the icon. These forbidden native target
tooltips remain unsupported; no protection or secret-data checks are bypassed.
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
Version 1.4.0 replaces the direct TargetUnit call that caused the reported
ADDON_ACTION_FORBIDDEN error. A transparent SecureActionButtonTemplate handles
the hardware click through Blizzard's secure OnClick. Addon code prepares
its target attributes outside combat and rechecks the current aura in PreClick.
The overlay passes hover motion and right-clicks to the native aura button.
Its position uses numerical UIParent coordinates, avoiding a protected anchor
dependency on moving aura buttons. A secure combat state driver hides the
overlay and clears its target action as combat begins. There is no addon
TargetUnit call, and Blizzard's aura button OnClick remains unchanged.
Clicks made in combat do nothing and are never queued for later. A caster that
cannot be targeted by the client will not change your target. Clients missing
the required secure/mouse pass-through APIs leave click targeting inactive.
Actual secure hardware clicks still require an in-game check on Forever.

Native 3D portraits
Enable "3D portraits" in Frames for animated native player, target, focus,
pet and portrait-style party portraits. This option starts disabled.
Click Apply to reload after changing the option. The 3D model replaces the
visible 2D portrait in the same location, uses head zoom 1 and loops the
Stand/idle animation (0), unpaused.
Uses native PlayerModel frames without intercepting unit-frame mouse actions.
Models stay behind native borders. No ZPerl code, assets or dependencies are
bundled. Compact party/raid layouts without portrait textures are unaffected.
Unavailable, invisible, dead or restricted units retain their 2D portrait.
Version 1.4.1 shows the model transparently before SetUnit so a hidden frame
does not postpone loading. It keeps model data across hides and polls loading
for up to five seconds, retaining 2D until ready. Apply retries a failed load
without a reload when portrait mode is unchanged. Readable GUIDs are optional.
Unit/model events refresh the model. New model frames are created only outside
combat. Disabling the option and reloading restores the original 2D portrait.
Native model framing and border
appearance still need visual validation in the Forever client.
Version 1.5.1 uses Adapt's visual layering approach: a circular backdrop below
the model and a soft circular overlay above it, with a centered viewport at
76.5% of the portrait's smaller dimension (up from 68% in 1.5.0). This gives
the head more room and blends square edges into the circular background.
Readable player classes use muted class colors; NPCs and unavailable class
colors use neutral gray. The bundled radial textures are generated for
ZwykPlus; Adapt is not required. Both layers hide during loading and fallback.
PlayerModel cannot use the circular mask supported by native 2D textures.
The overlay is cosmetic and cannot guarantee that all model geometry stays
inside the circle. The native portrait texture and border are unchanged.
When updating, copy the whole ZwykPlus folder including Textures and restart
the client once to load the new texture files.
Version 1.6.0 fixes the transparency attempt in 1.5.2: the final color update
also sets the requested opacity, and at 100% transparency both added textures
are hidden. Setting alpha only at creation could be undone by later tinting.
The shading overlay is not a true clipping mask; it follows the same opacity
as the background. The model and native portrait border remain visible.
Open Frames > Configure beside Enable 3D portraits for saved appearance options:
- Model size: 50 to 100 percent of the native portrait, in 0.5-percent steps.
  Default 76.5 percent. Larger models can extend outside the circular border.
- Background transparency: 0 is opaque, 100 is fully transparent (the default).
- Class-colored background: enabled initially. When off, use black. NPCs and
  inaccessible class colors also use black.
Appearance settings apply live without restarting idle animations. Model size
changes made in combat apply after combat. Enabling/disabling 3D mode still
requires a reload. Apply preserves unchanged models and retries failed loads.
Target/focus changes update only their own models. Unchanged readable unit
identities keep their idle animation; a newly assigned target starts its
own idle. Actual unit-model changes still refresh the affected unit.
For a silent failure, open Frames > Portrait diagnostics or /zp portraits.
The copyable report shows saved/current mode, pending reload, fallback reason,
SetUnit result, model readiness, visibility, dimensions/layers and head/idle
configuration. It does not log GUIDs. Copy with Ctrl+C and include a screenshot
when reporting a rendering problem.

Class-colored frame names
Enable this saved option under Frames to color player names on accessible
native unit frames by class. It starts disabled and applies immediately.
NPC names retain native colors. Disabling the option restores native colors;
unknown or restricted class information is not inferred. Name text and
Forever surnames are unchanged. Third-party replacement frames are not styled.

Item binding icons (Interface > Items)
Adds a small transparent chain at the lower-left of native bag and loot-roll
item icons, including combined bags. A closed chain marks a currently
soulbound bag item; an open chain marks an unbound Bind on Equip item. In
loot rolls, closed means Bind on Pickup, since ownership has not been awarded.
Binding is checked per bag slot, so two copies of the same item can differ.
Moving, equipping, replacing items and delayed item data refresh the marker.
Unknown/restricted binding, quest items and account-bound items are omitted.
Account-until-equip items show closed only after the client confirms that the
instance is no longer account-bound. Counts, item clicks and loot-roll actions
are unchanged. Separate third-party bags and loot-roll replacements are not
integrated. The saved option starts off and applies immediately without reload.
Include Textures/BindingChainClosed.tga and Textures/BindingChainOpen.tga when
updating, and restart the client to load the new texture files.

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

"Apply enabled features" reapplies live options and reloads when portrait mode
has changed. The warning beside the button indicates that it will reload.

INTERFACE VERSION
The TOC targets Interface 16001, matching the published Forever 1.60.1 UI
source (build 70170, exported October 1, 2026), rather than the earlier addons'
11507 Classic placeholder. Source:
https://github.com/Gethe/wow-ui-source/blob/forever/version.txt
Source commit: 9a789c074b8e73c5d604ef2d6af3bb5b3aefb348
The 1.4.1 fixes also checked source e3ecc27b64d30fdc735a3f6579b866858f9f9df1,
Forever 1.60.1 build 70205. Interface remains 16001.

If your particular beta build uses a different interface number, check it with:
/dump select(4, GetBuildInfo())
Replace 16001 in ZwykPlus.toc with that number and restart WoW.
No addon can update its own TOC before WoW performs the version check.
No version-check setting is disabled by ZwykPlus.

VALIDATION
The addon uses native WoW widgets and has no addon/library dependencies.
Saved settings, feature activation/deactivation, error/info event handling,
camera restoration, tracking selection, buff/debuff source tooltips and class
colors, secure click attributes/current aura resolution/combat transitions,
native portrait hidden/asynchronous loading/2D fallback, idle/head setup,
portrait reload decisions, copy report UI, public aura setter coverage and
surname formatting, chat icons, unchanged links/history,
asynchronous item loading and restricted/unknown information were checked in
a mocked Lua runtime. Widget positions for all five categories were rendered
and inspected in English and French.
This version has not yet been tested inside the Forever client; a mocked
runtime cannot establish that the client's secure hardware click path works
or that native portrait clipping and borders look correct. It also cannot
prove the client accepts a reload from the addon Apply hardware click.
The expanded hidden-model lifecycle test fails with the old 1.4.0 module
and passes with 1.4.1.
Version 1.5.0 additionally checks viewport corner bounds, unchanged native
portrait dimensions, isolated target/focus events, cached-unit animation
retention, public/restricted identity changes, and immediate name colors with
native color restoration on player/NPC frame reuse and option changes.
Version 1.5.1 checks the enlarged viewport, background/model/overlay ordering,
layer visibility through loading and fallback, safe background class colors,
retained animations and uncompressed TGA dimensions/alpha. The viewport's
corners are no longer guaranteed to lie within the native portrait circle.
Version 1.6.0 models shared alpha between SetAlpha and SetVertexColor, rather
than assuming those values are independent. Checks cover hidden transparent
textures, partial/opaque/class/black backgrounds, real reported alpha, live
size changes, combat deferral, validated saved settings and animation retention.
The English/French appearance panels were rendered and interaction checked.
Version 1.6.1 places both auxiliary windows above the main options panel and
its controls. Opening before the main panel and repeated reopening are checked.
Version 1.7.0 checks per-slot binding, pooled bag and roll reuse, delayed item
data, restricted values, live toggling and transparent chain assets. Actual
icon placement still needs validation inside Forever.

Item binding implementation references (Forever source pin above):
https://github.com/Gethe/wow-ui-source/blob/e3ecc27b64d30fdc735a3f6579b866858f9f9df1/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua
https://github.com/Gethe/wow-ui-source/blob/e3ecc27b64d30fdc735a3f6579b866858f9f9df1/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/GroupLootFrame.lua
https://github.com/Gethe/wow-ui-source/blob/e3ecc27b64d30fdc735a3f6579b866858f9f9df1/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua
https://github.com/Gethe/wow-ui-source/blob/e3ecc27b64d30fdc735a3f6579b866858f9f9df1/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua

Aura tooltip implementation references (Forever UI source):
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_BuffFrame/BuffFrame.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleScriptRegionAPIDocumentation.lua

Portrait implementation references (Forever UI source):
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UnitFrame/Shared/UnitFrame.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleModelAPIDocumentation.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleRegionAPIDocumentation.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameAPICharacterModelBaseDocumentation.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_FrameXML/TalkingHeadUI.lua

Native name-color implementation references (same Forever source pin above):
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UnitFrame/Mainline/UnitFrame.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UnitFrame/Mainline/TargetFrame.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UnitFrame/Shared/CompactUnitFrame.lua

Surname and forbidden target aura evidence (source pin above):
https://github.com/Gethe/wow-ui-source/blob/e3ecc27b64d30fdc735a3f6579b866858f9f9df1/Interface/AddOns/Blizzard_FrameXMLUtil/Camelot/NameUtil.lua
https://github.com/Gethe/wow-ui-source/blob/e3ecc27b64d30fdc735a3f6579b866858f9f9df1/Interface/AddOns/Blizzard_AuraContainer/Classic/Blizzard_AuraButtonTooltip.xml
https://github.com/Gethe/wow-ui-source/blob/e3ecc27b64d30fdc735a3f6579b866858f9f9df1/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraButton.xml
https://github.com/Gethe/wow-ui-source/blob/e3ecc27b64d30fdc735a3f6579b866858f9f9df1/Interface/AddOns/Blizzard_UnitFrame/Shared/TargetFrameAuraButton.xml
https://github.com/Gethe/wow-ui-source/blob/e3ecc27b64d30fdc735a3f6579b866858f9f9df1/Interface/AddOns/Blizzard_UnitFrame/Shared/TargetFrameAuraShared.lua

Chat implementation references (Forever UI source):
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/ScrollingMessageFrame.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua
https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua
