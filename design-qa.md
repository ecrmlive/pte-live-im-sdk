**Comparison Target**

- Source visual truth: `/Users/daniel/Downloads/PTE Live IMSDK设计图/亮色/亮色-会话列表.png`, `亮色-联系人.png`, `亮色-聊天.png`, `亮色-聊天-功能.png`, and `亮色-聊天-表情.png`.
- Rendered implementation: `/private/tmp/pte-im-ios-conversations-v3.png`, `/private/tmp/pte-im-ios-contacts-v4.png`, `/private/tmp/pte-im-ios-chat-rich-v3.png`, `/private/tmp/pte-im-ios-chat-rich-dark-v1.png`, `/private/tmp/pte-im-ios-chat-media-v3.png`, `/private/tmp/pte-im-ios-chat-more-v7.png`, `/private/tmp/pte-im-ios-chat-more-dark-v2.png`, and `/private/tmp/pte-im-ios-chat-emoji-v3.png`.
- Full-view comparison evidence: `/private/tmp/pte-im-ios-chat-rich-comparison-v3.png`, `/private/tmp/pte-im-ios-chat-rich-dark-comparison-v1.png`, `/private/tmp/pte-im-ios-chat-media-comparison-v2.png`, and `/private/tmp/pte-im-ios-chat-more-comparison-v3.png` combine supplied source states with iPhone 15 Pro simulator captures.
- Viewport/state: iPhone 15 Pro, iOS 17.0, light skin, Chinese UI; deterministic offline conversation/contact/chat fixtures.
- Final iOS comparison: `/private/tmp/pte-im-demo-ios-login-comparison-qa3.png` places the supplied `亮色-登录.png` at left and the iPhone 15 Pro simulator capture at right.
- Final Android comparison: `/private/tmp/pte-im-demo-android-login-comparison-qa4-width.png` places the supplied `亮色-登录.png` at left and a real Android API 36 emulator capture at right. The capture is width-normalized without vertical stretching; the extra Android height is retained for its system navigation area.
- Dark Android comparison: `/private/tmp/pte-im-android-dark-login-comparison-qa2.png` places the supplied `暗黑-登录.png` at left and the Android API 36 capture at right. Both use the Simplified Chinese state.

**Findings**

- [P3] Conversation/contact asset and row fidelity is incomplete.
  Location: list chrome and cells.
  Evidence: the latest contacts capture includes the supplied product mark, search cut, personal/group headers, online dots and group rows. Minor differences remain in quick-action iconography and density versus the supplied capture.
  Impact: no core contact or visual hierarchy is missing; remaining work is visual polish.
  Fix: refine quick-action spacing/icons only after the blocking chat interaction state is complete.

- [P3] Chat content fixture density differs slightly from the reference.
  Location: chat timeline.
  Evidence: `pte-im-ios-chat-more-comparison-v3.png` verifies group title/member count, call/video/more navigation actions, day separator, text reactions, outgoing receipt, mint image thumbnail, compact expanded composer and the exact two-row action ordering. `pte-im-ios-chat-more-dark-v2.png` verifies the same component tree under the dark palette. The remaining difference is fixture scroll position and message amount, not an implementation surface.
  Impact: no interaction or required UIKit rendering surface is absent.
  Fix: optional final fixture/spacing polish only.

**Required Fidelity Surfaces**

- Fonts and typography: native UIKit Dynamic Type is used; rich-card title/subtitle/footer hierarchy now follows the supplied red-packet card in both light and dark modes.
- Spacing and layout rhythm: the oversized/incorrect list header width was fixed; chat now hides the root tab bar and the composer owns the lower safe area. Rich-card widths and the red-packet aspect ratio now follow the supplied reference. Conversation/contact pages have revised captures after the lavender token and compact list-style update.
- Colors and visual tokens: light skin uses the required blue–purple outgoing gradient and lavender canvas. The latest list-cell token correction is pending capture.
- Image quality and asset fidelity: the actual supplied red-packet/gift backgrounds, video play icon, image placeholder, business-star, product mark and search cut are packaged under `PteIMUIKit/Resources`; Core remains asset-free. Contact grouping/presence UI remains outstanding.
- Copy and content: Chinese/English labels, deterministic fixtures, group member count and host-fed message reactions render.

**Comparison History**

1. Initial runtime was blocked by a preview path that opened the protected local cache. Fixed by making `PteIMSDK.preview` use an in-memory Core Data store and temporary local cipher.
2. Initial conversation capture had a narrow table header. Fixed by frame-driven `tableHeaderView` layout; revised evidence is `pte-im-ios-conversations-v2.png`.
3. Initial chat capture retained the root tab bar. Fixed by `PteIMUIChatViewController.hidesBottomBarWhenPushed`.
4. Initial chat timestamps appeared inside bubbles and lacked a day grouping. Fixed with day-based table sections, reference-style line separators, external incoming/outgoing timestamps and outgoing read marks; revised evidence is `pte-im-ios-chat-time-v1.png` and `pte-im-ios-chat-time-comparison.png`.
5. Generic media/business bubbles did not match the supplied card hierarchy. Fixed with `PteIMUIRichMessageCell`, separate image/video/location/red-packet/gift/order/file layouts, resource-owned backgrounds and a replaceable icon provider. The latest light/dark comparisons are `pte-im-ios-chat-rich-comparison-v3.png` and `pte-im-ios-chat-rich-dark-comparison-v1.png`; image/location evidence is `pte-im-ios-chat-media-comparison-v2.png`.
6. The supplied chat-function and emoji states were then matched with a compact expanded composer, supplied two-row action artwork, emoji category icons, a host-fed reaction rail, group subtitle/call navigation controls and independent input-panel colour tokens. The final function-state comparison is `pte-im-ios-chat-more-comparison-v3.png`; light/dark and emoji captures are `pte-im-ios-chat-more-v7.png`, `pte-im-ios-chat-more-dark-v2.png` and `pte-im-ios-chat-emoji-v3.png`.

**Implementation Checklist**

1. Optional: make fixture scroll position exactly mirror the static source capture.
2. Optional: refine conversation/contact quick-action spacing.
3. iOS is the final visual source baseline: its brand spacing, card origin, credential field rhythm, UserSig-to-action gap, lock asset and English first-login state were compared against the supplied design at the same presentation state.
4. Android Demo is emulator-verified in both supplied login skins: the dark page now uses the independent dark card, border, input and text tokens instead of a light form on a dark canvas. Its shared navigation bar owns the status/navigation-bar appearance, current-language selector, dark/light artwork and the custom three-option language panel in the required order: 跟随系统、简体中文、English. `PteIMUIDemoApplication` owns the three domains at startup.
5. HarmonyOS and uni-app x now use the same application-config-first login architecture, English first-login state, credential-to-action spacing and business-shell layout. Harmony HAP/APP compilation is signed and successful; uni-app x H5/WeChat UTS lint is clean.
5. Direct runtime screenshot verification is still required for HarmonyOS and uni-app x because no target device/preview renderer was connected. This is a visual-evidence limitation only; it is not a compilation failure.

## Android Conversation List QA — 2026-07-17

**Comparison Target**

- Source visual truth: `/Users/daniel/Downloads/PTE Live IMSDK设计图/亮色/亮色-会话列表.png` and `/Users/daniel/Downloads/PTE Live IMSDK设计图/暗黑/暗黑-会话列表.png`.
- Implementation evidence: `/private/tmp/pte-im-android-conversations-light.png` and `/private/tmp/pte-im-android-conversations-dark-zh.png` from the Android API 36 emulator.
- Full-view comparison evidence: `/private/tmp/pte-im-android-conversations-light-comparison.png` and `/private/tmp/pte-im-android-conversations-dark-zh-comparison.png`; supplied source is left, width-normalized Android capture is right.
- Viewport/state: Android API 36 emulator, six real server-backed Demo conversations; light/English and dark/Simplified Chinese states.

**Findings**

- No actionable P0/P1/P2 difference remains for the Android conversation-list target. Android retains a taller bottom system-navigation area than the 384×812 iPhone artboard; the UIKit bottom tab bar itself is aligned above that system area and remains fully visible.

**Required Fidelity Surfaces**

- Fonts and typography: native Android text keeps the reference’s title/preview/time hierarchy and one-line truncation.
- Spacing and layout rhythm: 44 dp conversation header, search field, six 70 dp rows, 15–20 dp edge rhythm, separators, online dots, unread badges, and persistent tab bar are verified in both palettes.
- Colors and visual tokens: light lavender canvas/search surface and dark navy canvas/indigo search surface match the supplied two-mode hierarchy.
- Image quality and asset fidelity: supplied logo, search, language, theme, create-conversation and tab artwork are packaged in `android/pte-im-uikit`, not Core or Downloads-linked paths.
- Copy and content: title/search/tab copy switches with the selected language; the six Demo rows are backed by valid C2C/group conversation identifiers.

**Interaction checks**

- Search field renders and filters from the UIKit cache presentation.
- Theme control updates the persisted Demo preference and immediately redraws the UIKit list.
- Language popup selects `跟随系统`、`简体中文` or `English`; the host persists the override and UIKit redraws.
- The create control routes to the Demo group-creation flow; a row opens its retained Core conversation ID.

**Comparison History**

1. Initial Android list rebuild attached the reused search field to two containers and crashed. Fixed by detaching the field before reattaching on an appearance redraw; emulator relaunch has no fatal exception.
2. First runtime capture showed only four rows and header content against the status bar. Fixed with a six-conversation local Demo seed, a Demo presentation cap, and status-bar inset handling. The two final comparison images above verify the revision.

final result: passed

## Harmony Emoji Floating Controls QA — 2026-07-17

**Comparison Target**

- Source visual truth: `/var/folders/yn/8j0yr4gs2pzg508td1q42cv00000gn/T/codex-clipboard-deea6395-9f0a-4f3f-b069-7ab464337447.png`.
- Updated runtime: `/private/tmp/pte-emoji-after.jpeg` and `/private/tmp/pte-emoji-scroll.jpeg`, captured from the OpenHarmony emulator at `2210 × 2416`.
- State: dark chat, complete emoji picker, backspace and send controls visible at the lower-right corner.

**Comparison History**

1. The picker reserved 56vp as bottom padding for the controls. That removed a complete visible emoji row and left a large empty band at the lower left.
2. Removed that panel-level reserved row. Backspace and send remain 44vp floating controls, while the emoji scroll content retains a 58vp scroll-tail so its final items can be dragged above the two hit areas.
3. In `/private/tmp/pte-emoji-after.jpeg`, the grid now fills the former blank area. In `/private/tmp/pte-emoji-scroll.jpeg`, upward scrolling brings the remaining emoji rows fully above the floating controls, so every emoji can be tapped.

**Required Fidelity Surfaces**

- Fonts and typography: existing `SMILEYS` heading and emoji sizing are unchanged.
- Spacing and layout rhythm: the 338vp panel no longer devotes a full row to controls; controls remain anchored at the lower-right edge.
- Colors and visual tokens: panel, divider, backspace and send tokens remain the active dark-theme assets.
- Image quality and asset fidelity: existing supplied backspace/send image assets are retained at 44vp.
- Copy and content: emoji source and selection behavior are unchanged.

**Findings**

- No actionable P0/P1/P2 issue remains for the requested floating-control layout. The footer buttons no longer consume a full grid row, and the scroll-tail preserves access to the emoji that pass under the overlay.

final result: passed

## Harmony Chat Navigation and Emoji Anchoring QA — 2026-07-17

**Comparison Target**

- Source visual truth: `/var/folders/yn/8j0yr4gs2pzg508td1q42cv00000gn/T/codex-clipboard-b943a159-c96a-414d-a6e1-6fec28927555.png`, `codex-clipboard-39a98db6-835a-4a93-8684-14806f48550d.png`, and `codex-clipboard-8bfe9886-06f2-4bb0-a415-83390b73b796.png`.
- Runtime: `/private/tmp/pte-emoji-all-layout-revised.jpeg`, `/private/tmp/pte-emoji-common-top-revised.jpeg`, and `/private/tmp/pte-chat-outgoing-voice-revised.jpeg` from the OpenHarmony emulator at `2210 × 2416`.
- States compared in the same visual review: light navigation, full-expression panel, and recent-expression panel.

**Findings**

- [P1, fixed] Back and more now render from the chat navigation assets in 44 × 44 button slots. Back remains wired to the supplied navigation handler.
- [P1, fixed] Outgoing voice bubbles use the supplied white microphone artwork rendered at 16 × 16, matching the bubble waveform treatment.
- [P1, fixed] Expression backspace/send controls remain in the footer at the screen edge rather than taking a grid cell. The full-expression grid scrolls above them.
- [P1, fixed] The recent-expression row starts immediately below the `SMILEYS` heading; remaining vertical space stays below the row.

**Verification**

- `hvigorw --mode module -p module=entry@default -p product=default assembleHap`: passed.
- Signed HAP reinstalled and started on `127.0.0.1:5557`; light and dark visual states were inspected in the emulator.

final result: passed

## Harmony Chat Input Emoji Panel QA — 2026-07-17

**Comparison Target**

- Source: `/var/folders/yn/8j0yr4gs2pzg508td1q42cv00000gn/T/codex-clipboard-a927656c-8253-4e3e-b27c-1f282b122793.png`.
- Runtime: `/private/tmp/pte-input-emoji-light-final.jpeg`, `/private/tmp/pte-input-emoji-grid-final.jpeg`, and `/private/tmp/pte-input-more-toggle-final.jpeg` on the OpenHarmony emulator at `2210 × 2416`.
- The supplied light design and the light runtime panel were reviewed side by side in the same visual pass.

**Findings**

- [P1, fixed] Normal text input no longer renders an app-level Send button. Sending is now restricted to the keyboard submit action or the emoji panel footer send control.
- [P1, fixed] Emoji rows are now built as explicit 8-column grids. The picker exposes 48 supplied/fallback smileys across six rows, with the final row reachable by internal scrolling; common and all tabs remain available.
- [P1, fixed] Backspace removes a complete UTF-16 surrogate pair. The real-device insert-then-backspace check leaves an empty editor instead of a replacement `?` glyph.
- [P2, fixed] Emoji and function triggers swap between the supplied default/active images. The active function panel uses the matching close asset; the 44 × 44 footer backspace/send images fill their intended button frames.
- [P2, fixed] The editor is constrained to 200 characters, one to five lines (40–100vp), uses 10vp horizontal and 8vp vertical padding, and keeps excess content in its own text area.

**Verification**

- `hvigorw --mode module -p module=entry@default -p product=default assembleHap`: passed.
- Signed HAP reinstalled on `127.0.0.1:5557`; verified light/dark picker layouts, emoji insert/backspace, internal grid scroll, and function-panel icon switch on device.

final result: passed

## Harmony Chat Navigation and File Contrast QA — 2026-07-17

**Comparison Target**

- Source visual truth: `/var/folders/yn/8j0yr4gs2pzg508td1q42cv00000gn/T/codex-clipboard-7f25ddce-000b-495f-8b9a-5f63d0a8dd6b.png`.
- Runtime light evidence: `/private/tmp/pte-chat-light-file-final.jpeg` and `/private/tmp/pte-chat-back-light-final.jpeg` from the OpenHarmony emulator at `2210 × 2416`.
- Runtime dark evidence: `/private/tmp/pte-chat-file-dark-final.jpeg` from the same emulator.

**Findings**

- [P1, fixed] The header's inert triangle and plus glyph have been replaced with a standard back arrow and a dedicated vertical-more glyph. Both use a 44 × 44 hit target; pressing Back now returns the token-free chat preview to the Chats list.
- [P2, fixed] The outgoing file card now uses high-contrast title and size tokens for both palettes: white/lavender on the purple outgoing bubble, dark/slate text on a light incoming card, and appropriate muted values in dark mode.
- [P2, fixed] Demo conversations now invoke the supplied navigation handler, so the visual preview list remains usable after returning from chat.

**Required Fidelity Surfaces**

- Typography: `项目报价单.pdf` and `320 KB` preserve hierarchy and remain legible on the purple file bubble in both light and dark mode.
- Spacing/layout: navigation remains fixed at the top while scrolling; Back and More align to the 44-high header action slots.
- Colors/tokens: light mode uses black native navigation symbols and bright file text; dark mode uses supplied white cut assets and lavender secondary file text.
- Image/asset fidelity: dark Back and More are sourced from the supplied design cut assets; light symbols are standard OpenHarmony bar assets.

**Verification**

- `hvigorw --mode module -p module=entry@default -p product=default assembleHap`: passed.
- Signed HAP reinstalled on `127.0.0.1:5557`; Back navigated to Chats and the same file card was visually checked in light and dark modes: passed.

final result: passed

## Android Rich Message Cell Correction QA — 2026-07-17

**Comparison target**

- Source visual truth: `/Users/daniel/Downloads/PTE Live IMSDK设计图/暗黑/暗色-聊天.png`; voice artwork: `/Users/daniel/Downloads/PTE Live IMSDK设计图/切图/暗色-语言-对方-图标.png`, `暗色-语言-对方-波纹图片.png`, `暗色-语言-发送方-图标.png`, `暗色-语言-发送方-波纹图片.png`, plus their supplied light counterparts.
- Runtime evidence: `/private/tmp/pte_voice_cells_fixed_2.png` and `/private/tmp/pte_cells_fixed.png` from `emulator-5554`.
- Full-view comparison evidence: `/private/tmp/pte_voice_cells_comparison.png` and `/private/tmp/pte_business_cells_comparison.png`; the supplied source is left and Android runtime is right.
- Viewport/state: Android 1080×2400 emulator, dark skin, automatic Debug fixture.

**Findings and fixes**

- [P1, fixed] Red-packet and gift copy previously used a wrapping vertical layout over a precomposed background. The action text could drift into the divider/lower band and the card height varied. The Cell now uses the supplied 208 dp source width and fixed heights (红包 186 dp, 礼物 182 dp), with title, subtitle and CTA anchored to the background artwork's intended bands.
- [P1, fixed] Voice Cells previously drew a music glyph and Unicode bars, which did not match the supplied visual waveform and could overflow the bubble. They now use the provided 16×16 icon and 78×20 waveform raster for incoming/outgoing and dark/light states. The Cell has a deterministic 139 dp minimum content width; duration remains aligned to the trailing edge.

**Required Fidelity Surfaces**

- Fonts and typography: business-card title, subtitle and CTA each have fixed single-line positions; voice duration uses a 10 sp optical secondary label.
- Spacing and layout rhythm: red-packet/gift background aspect ratios, divider positions and lower-band CTAs are preserved by explicit 208×186/182 dp bounds. Voice content is 16 dp icon, 6 dp gap, 78 dp waveform, 4 dp gap, duration.
- Colors and image fidelity: all business-card background, voice icon and waveform artwork comes from the supplied cut assets packaged in `PteIMUIKit`; no text glyph or custom waveform remains.
- Copy and content: outgoing/incoming action copy remains unchanged and is centered within the source lower band.

**Verification**

- `./gradlew --no-daemon -Dorg.gradle.jvmargs= :pte-im-uikit:compileDebugKotlin :pte-im-ui-demo:assembleDebug`: passed. Kotlin daemon connection retries fell back to in-process compilation; the final APK was produced successfully.
- Debug APK installed on `emulator-5554`; red packet, gift, incoming voice and outgoing voice cells were visually captured and compared to the supplied dark design: passed.

final result: passed

## Android PteIMUIKit Input Composer QA — 2026-07-17

**Comparison target**

- Source visual truth: `/Users/daniel/Downloads/PTE Live IMSDK设计图/暗黑/暗色-聊天-语音.png`, `/Users/daniel/Downloads/PTE Live IMSDK设计图/暗黑/暗色-聊天-说话中.png`, `/Users/daniel/Downloads/PTE Live IMSDK设计图/暗黑/暗色-聊天-表情.png`, and `/Users/daniel/Downloads/PTE Live IMSDK设计图/暗黑/暗色-聊天-功能.png`.
- Runtime evidence: `/private/tmp/pte_input_auto_chat.png`, `/private/tmp/pte_input_emoji_panel_verified.png`, `/private/tmp/pte_input_emoji_selected.png`, `/private/tmp/pte_input_emoji_sent.png`, `/private/tmp/pte_input_more_panel_verified.png`, and `/private/tmp/pte_input_image_picker.png`, captured from `emulator-5554`.
- Full-view comparison evidence: `/private/tmp/pte_input_more_comparison.png`; source design is on the left and Android runtime is on the right. Both captures use the dark chat state; Android system chrome and the different message fixture are excluded from the component judgement.
- Focused-region comparison: the composer, 4×2 attachment grid and 44 dp emoji cells are fully visible in the same comparison image; no additional crop is required.
- Viewport/state: Android emulator 1080×2400, dark skin, automatic Debug entry into the isolated `Work Team 工作群` review conversation.

**Findings**

- No actionable P0/P1/P2 issue remains in the input-composer scope. The attachment panel uses the source artwork, four equal columns, 52 dp action images, 15 dp labels, 20 dp inter-row rhythm, and its closed-state input order is voice, multiline text, emoji, plus.
- The visual source’s provided screenshot is a different chat fixture and retains source-era call/video header controls. The current product requirement intentionally keeps only Back and More in the navigation header; it is not an input-composer drift.

**Required Fidelity Surfaces**

- Fonts and typography: native text respects the shared `PteIMUIThemePalette`; composer hint, 15 dp action labels, category labels, recording labels and IME send behavior retain the expected hierarchy. The multiline input uses 10 dp horizontal and 5 dp vertical padding, minimum 40 dp, maximum 100 dp and a 200-character filter.
- Spacing and layout rhythm: voice, emoji and plus hit areas are 40 dp; emoji cells are 44×44 dp with a 24×32 dp content slot. The function grid is 4 columns by up to 3 rows, with 8 defaults plus at most 4 host actions.
- Colors and visual tokens: normal, focused, panel, recording-gradient, disabled and receipt colors come from the current skin palette. The dark runtime reproduces the supplied deep navy surface and purple active treatment.
- Image quality and asset fidelity: supplied attachment and composer image assets are packaged by `PteIMUIKit`; no source image is read from Downloads at runtime. Image attachment launches Android DocumentsUI from the UIKit-owned picker bridge.
- Copy and content: Common/All emoji categories, `Hold to Record`, `Talking`, `Release to cancel`, Image, Camera, Video, Location, File, Red Packet, Gift and Order are localized by the active language.

**Interaction checks**

- Voice toggle changes text input into hold-to-record. Press starts recording state; leaving the control changes the label to `Release to cancel`/`松开手取消录音`; release outside emits cancel and release inside ends recording.
- Emoji opens Common/All; selection writes into the composer and moves the item to the bounded 32-item Common group. Backspace removes one code point; the panel send dispatches a message and clears the composer. The emulator evidence shows one selected emoji then an outgoing delivered bubble.
- `+` opens the two-row default grid and supports up to a third custom row. Image, Camera, Video, Location and File are implemented inside `PteIMUIKit`; Red Packet, Gift and Order are exposed only through host callbacks. Selecting Image opened the system picker from the UIKit bridge.
- Keyboard mode has no visible app send button: only `IME_ACTION_SEND`/hardware Enter submits text. Emoji-panel mode has the panel’s visible send button.
- Debug credential retrieval may be unavailable when the local Docker API is not running. In that case the Debug-only offline review client opens the isolated fixture automatically; it never persists a UserSig or enqueues server messages for that fixture. A reachable api-im credential still takes precedence.

**Verification**

- `./gradlew :pte-im-uikit:compileDebugKotlin :pte-im-ui-demo:assembleDebug`: passed.
- Debug APK install/launch on `emulator-5554`, automatic offline fixture entry, normal composer, voice mode, emoji selection/send, function grid and UIKit-owned DocumentsUI image picker: passed.

final result: passed

## Android PteIMUIKit Chat Panel Refinement QA — 2026-07-17

**Comparison target**

- Source visual truth: the supplied light/dark chat function and emoji states under `/Users/daniel/Downloads/PTE Live IMSDK设计图/亮色`, `/Users/daniel/Downloads/PTE Live IMSDK设计图/暗黑`, and `/Users/daniel/Downloads/PTE Live IMSDK设计图/切图`.
- Runtime evidence: `/private/tmp/pte-im-android-chat-auto-final.png`, `/private/tmp/pte-im-android-chat-more-panel.png`, `/private/tmp/pte-im-android-chat-emoji-panel-final.png`, `/private/tmp/pte-im-android-input-voice-final.png`, and `/private/tmp/pte-im-android-input-keyboard-inset-final.png` from `emulator-5554`.

**Verified refinement**

- Debug startup retains the application configuration, authenticates with the Demo flow, and immediately enters the deterministic `Work Team 工作群` chat fixture.
- The composer uses a 40 dp text/hold-to-talk surface and 40 dp voice, emoji, plus, send and close targets. In expanded states, emoji moves inside the input surface exactly as in the supplied function and emoji designs.
- The action sheet is a two-row 4×2 grid: each action cell is 75 dp tall, uses the supplied 52 dp artwork, and has a 20 dp inter-item rhythm. Image, camera, video, location, file, red packet, gift and order all use UIKit-owned assets.
- The emoji sheet provides a 10-item category rail, 44 dp Unicode emoji grid, and supplied light/dark backspace/send artwork. A selected standalone emoji dispatches as a Core emoji message; mixed text and emoji dispatch through the normal text path.
- Voice mode is the supplied minimal state: 40 dp chat/text switch, 40 dp hold-to-record surface and 40 dp plus control. Pressing holds a blue-violet recording surface with the supplied microphone artwork and `正在说话` / `Talking` state.
- When Android shows the IME, its inset resizes the chat host so the 40 dp composer remains immediately above the keyboard; the keyboard state embeds emoji in the text surface and retains the plus control. Both `IME_ACTION_SEND` and physical Enter dispatch text.
- `./gradlew :pte-im-uikit:compileDebugKotlin :pte-im-ui-demo:assembleDebug` and final APK install/launch on the Android emulator: passed.

final result: passed

## Android PteIMUIKit Chat QA — 2026-07-17

**Comparison target**

- Source visual truth: `/Users/daniel/Downloads/PTE Live IMSDK设计图/亮色/亮色-聊天.png`, `/Users/daniel/Downloads/PTE Live IMSDK设计图/亮色/亮色-聊天-功能.png`, `/Users/daniel/Downloads/PTE Live IMSDK设计图/亮色/亮色-聊天-表情.png`, and their `暗黑/暗色-聊天*.png` equivalents.
- Runtime evidence: `/private/tmp/pte-im-android-chat-auto-clean-final.png`, `/private/tmp/pte-im-android-chat-keyboard-send.png`, `/private/tmp/pte-im-android-chat-keyboard-send-dispatched-final.png`, `/private/tmp/pte-im-android-chat-auto-dark-final.png`, `/private/tmp/pte-im-android-chat-longpress-light-final.png`, and `/private/tmp/pte-im-android-chat-longpress-dark-final.png` from `emulator-5554`.

**Verified interaction and visual surfaces**

- The status bar uses the exact same white or deep-navy surface as the 44 dp chat navigation row; the secondary chat page has no bottom Tab.
- Header identity, group member subtitle, date divider, avatars, delivery state, text, image, video, location, file, red-packet, gift and order cells render in both supplied palettes. The chat header now only exposes Back and More; call and video actions are deliberately absent.
- The composer keeps the source order: voice, text field, plus, emoji, send. The soft keyboard shows its send action and dispatches the same text-send path as the visible send button; voice mode changes to a hold-to-record control.
- The supplied cut assets are packaged in `PteIMUIKit`: input controls, eight attachment actions, and red-packet/gift card artwork. No Downloads path is used at runtime.
- Plus opens the supplied 4×2 action grid; emoji opens a scrollable Emoji6-compatible Unicode grid; long press opens reactions and host-overridable Quote/Copy/Revoke/Delete actions.
- A fresh Debug login obtains a server-issued temporary UserSig and opens the complete `Work Team 工作群` fixture directly; Back returns to the normal business shell. This intentionally isolated review conversation uses a Demo-local outbound path for text and emoji, so keyboard send remains interactive without writing an invalid conversation ID into Core's server outbox. Real local messages take precedence over the visual fixture when present.

**Verification**

- Android API 36 emulator install, automatic Debug login, light/dark chat rendering, eight required message types, actual keyboard text dispatch, supplied read/unread receipt artwork, and long-press reaction/action menu: passed. `PteKeyboardVerify` was sent via the IME action and rendered as an outgoing receipt-bearing bubble without process termination.
- `./gradlew :pte-im-uikit:compileDebugKotlin :pte-im-ui-demo:assembleDebug`: passed.

final result: passed

## Android Conversation Fixed Chrome and Pull Refresh QA — 2026-07-17

**Runtime evidence**

- Before/after capture: `/private/tmp/pte-im-android-conversation-fixed.png`.
- Pull-refresh capture: `/private/tmp/pte-im-android-conversation-pull-refresh.png`, after an Android emulator down-swipe from the first conversation row.
- Viewport/state: Android API 36 emulator, valid retained Demo login, dark skin, six server-backed Demo conversations.

**Findings**

- The unread badge is now bound to the 24 dp icon frame’s top-right corner; it no longer lands in the centre of the Chats tab.
- The navigation bar and search field are outside the list scroll/pull container. Only conversation rows receive drag translation and the native progress indicator, so the fixed chrome stays in place.
- The default pull route invokes the SDK cursor synchronizer. A host can replace that route with `onPullToRefresh` and explicitly close the refresh UI via `finishPullRefresh()`.

**Verification**

- Emulator install, launch, normal conversation rendering, and a top-of-list downward swipe: passed.
- `./gradlew :pte-im-ui-demo:assembleDebug --no-daemon`: passed.

final result: passed

## Android My, Settings and Language QA — 2026-07-17

**Comparison Target**

- Source visual truth: `/Users/daniel/Downloads/PTE Live IMSDK设计图/亮色/亮色-我的.png`, `/Users/daniel/Downloads/PTE Live IMSDK设计图/暗黑/暗黑-我的.png`, `/Users/daniel/Downloads/PTE Live IMSDK设计图/亮色/亮色-设置.png`, and `/Users/daniel/Downloads/PTE Live IMSDK设计图/暗黑/暗黑-设置.png`.
- Implementation evidence: `/private/tmp/pte-im-android-me-light-final-v2.png`, `/private/tmp/pte-im-android-me-dark-final-v2.png`, `/private/tmp/pte-im-android-settings-light.png`, `/private/tmp/pte-im-android-settings-dark.png`, and `/private/tmp/pte-im-android-language-light-v2.png`, captured from the Android API 36 emulator.
- Full-view comparison evidence: `/private/tmp/pte-im-android-me-light-comparison-v2.png`, `/private/tmp/pte-im-android-me-dark-comparison-v2.png`, `/private/tmp/pte-im-android-settings-light-comparison-v2.png`, and `/private/tmp/pte-im-android-settings-dark-comparison-v2.png`; the supplied source is on the left and the Android runtime capture is on the right.
- Viewport/state: Android API 36 emulator, valid retained Demo login, Simplified Chinese, both light and dark skins.

**Findings**

- No actionable P0/P1/P2 visual or interaction difference remains for the My and Settings targets. Android system chrome is intentionally retained, so its status/navigation areas differ from the iPhone artboard while the application navigation bar remains directly below the status area.
- The supplied My header’s inline theme/language actions are intentionally absent. The current product requirement centralizes appearance and language in My-page settings; the My content rows and the Settings page are now the only entry points.

**Required Fidelity Surfaces**

- Fonts and typography: native Android preserves the hierarchy for profile, shortcuts, grouped preference titles, subtitles, and destructive logout action.
- Spacing and layout rhythm: the 44 dp in-app navigation bars start below the status area; supplied profile/settings artwork, 15 dp horizontal page rhythm, row dividers, cards, toggles, and bottom tab bar are verified in both palettes.
- Colors and image fidelity: all profile/settings/toggle/check/back artwork is copied into the Demo resource module. No image is loaded from Downloads at runtime; Core and UIKit do not package Demo-specific artwork.
- Copy and state: the language setting is an independent page with the required order `跟随系统` → `简体中文` → `English`; selection uses the supplied checked artwork and persists immediately.

**Interaction checks**

- My-page theme switch updates the retained skin and redraws My and Settings immediately.
- My-page language row and Settings language row open the independent language page; choosing an item persists the override and returns through the correct source screen.
- Chat and Contacts UIKit navigation bars no longer expose language or theme actions.
- Android 13+ predictive system back was exercised from Settings and returns to My instead of closing the Demo; the language page returns to its opening page.
- `./gradlew :pte-im-ui-demo:assembleDebug --no-daemon`: passed; the debug APK was installed and launched on `emulator-5554`.

**Comparison History**

1. The first language-page navigation bar overlapped the Android status region. Fixed with window-inset ownership on the page scroll root; `/private/tmp/pte-im-android-language-light-v2.png` verifies the corrected top edge.
2. Android 13+ predictive Back bypassed the legacy back override and could leave the Demo. Fixed by registering and unregistering an `OnBackInvokedCallback`; emulator verification confirms `设置 → 我的` returns correctly.

final result: passed

## Android Startup and Application Icon QA — 2026-07-17

**Comparison Target**

- Source visual truth: `/Users/daniel/Downloads/PTE Live IMSDK设计图/启动图/启动图.png`.
- Source Android icon: `/Users/daniel/Downloads/PTE Live IMLogo/android/playstore-icon.png`.
- Runtime evidence: `/private/tmp/pte-im-android-splash-art.png`, captured from the Android API 36 emulator after the system start surface hands off to the Demo startup activity.
- Side-by-side evidence: `/private/tmp/pte-im-android-splash-comparison.png`; supplied source is left and the real emulator capture is right.

**Findings**

- The runtime composition uses the supplied launch artwork without redrawing, stretching, or substituting its brand logo, background, text, or decorative particles. The only intentional platform difference is Android's system status and navigation indicators, which remain visible to avoid an immersive-mode confirmation prompt.
- The package manifest sets the supplied Android icon as both `android:icon` and `android:roundIcon`; it is Demo-owned and is absent from Core and UIKit modules.
- Android 12+ first shows a matching deep-violet system splash with the same app icon, then the full supplied launch artwork, and finally the business-login activity.

**Verification**

- `./gradlew :pte-im-ui-demo:assembleDebug --no-daemon`: passed.
- Debug APK installed and launched on `emulator-5554`; startup activity remained foregrounded, then handed off to `PteIMUIDemoActivity`: passed.

final result: passed

## Android Chats Tab Badge Alignment QA — 2026-07-17

**Comparison Target**

- Source: `/Users/daniel/Downloads/PTE Live IMSDK设计图/亮色/亮色-会话列表.png`.
- Runtime: `/private/tmp/pte-im-android-conversation-badge-v3.png` from `emulator-5554`.
- Side-by-side comparison: `/private/tmp/pte-im-android-conversation-badge-comparison-v3.png` (source left, Android runtime right).

**Findings**

- The unread badge now occupies a dedicated 32 dp tab-icon frame and stays fully visible at the visible chat-artwork upper-right, matching the supplied composition. It is no longer clipped by a negative margin or visually centered over the chat artwork.
- `./gradlew :pte-im-ui-demo:assembleDebug --no-daemon` and debug-APK install: passed.

final result: passed

## Android Navigation Surface and Tab Badge QA — 2026-07-17

**Comparison target**

- Source: `/var/folders/yn/8j0yr4gs2pzg508td1q42cv00000gn/T/codex-clipboard-71132fa7-4543-4a38-abc3-04da0a22edbc.png`.
- Runtime: `/private/tmp/pte-im-android-conversation-status-badge-final.png` and `/private/tmp/pte-im-android-conversation-dark-status-badge-final.png` from `emulator-5554`.

**Findings**

- `PteIMUINavigationBar.applySystemBars()` now applies the same palette `surface` to the Android status bar, gesture navigation bar and visible 44 dp navigation row. Profile, Settings and Language page headers use that same shared surface rather than a separate card color.
- The Chats badge retains its 16 dp red circle but its transparent icon frame is now 40 dp wide. This moves the badge 4 dp to the physical right without moving the chat artwork or clipping the badge. Runtime bounds moved from `[204,2263][246,2305]` to `[214,2263][256,2305]` on the API 36 emulator.

**Verification**

- Light and dark Chats pages show continuous status/navigation surfaces; the secondary chat page and root tabs remain unchanged.
- `./gradlew :pte-im-ui-demo:assembleDebug`, Debug install and emulator visual verification: passed.

final result: passed

## Harmony Chat Detail and Long-Press QA — 2026-07-17

**Comparison Target**

- Source visual truth: `/var/folders/yn/8j0yr4gs2pzg508td1q42cv00000gn/T/codex-clipboard-1d2153e0-b3aa-46f8-982d-ebedc37a321a.png`, `codex-clipboard-08cf99b1-8437-4c75-acaa-1182472d9174.png`, `codex-clipboard-709378f4-263b-47f3-8edf-075e626476da.png`, and `codex-clipboard-f2b44507-2b7d-4794-a433-4b450ee6ba1d.png`.
- Runtime: `/private/tmp/pte-chat-keyboard-fixed.jpeg`, `/private/tmp/pte-chat-rich-fixed.jpeg`, and `/private/tmp/pte-chat-longpress-final.jpeg` from the OpenHarmony emulator at `2210 × 2416`.
- States compared in the same visual review: keyboard-open navigation, voice/video/rich-card stream, and long-press reaction/actions above an outgoing red-packet card.

**Findings**

- [P1, fixed] The lower long-press action row previously expanded across the available parent width. `PteIMUIChat.messageActionBar()` now constrains it to a `360vp` independent card; the revised capture shows the reaction and Quote/Copy/Revoke/Delete cards directly above the selected message.
- [P2, fixed] Incoming voice mic artwork was dark and too small. It now uses a purple native 16 × 16 mic, while the outgoing mic remains white and both are centered with their waveform.
- [P2, fixed] Image/video/location use 16-radius clipping; red packets and gifts expose a claimed status footer; the order icon is placed on a muted rounded background.

**Required Fidelity Surfaces**

- Typography: header, member count, durations, filenames and claimed state are readable without truncation.
- Spacing/layout: fixed 44-high navigation, compressed content area when IME opens, and two distinct above-message action cards preserve hierarchy.
- Colors/tokens: purple incoming voice icon, outgoing white voice icon, red-packet/gift states, purple file bubble and order color treatments reflect the target semantics.
- Image/asset fidelity: supplied message assets remain in use for rich content; native system symbol is used only for the microphone control.
- Copy/content: all visible labels and actions remain consistent with the test conversation.

**Verification**

- `hvigorw --mode module -p module=entry@default -p product=default assembleHap`: passed.
- Signed HAP reinstalled and started on `127.0.0.1:5557`; long-press was manually exercised in the emulator.

final result: passed

## Harmony Chat Composer Dismissal QA — 2026-07-17

**Comparison Target**

- Source visual truth: `/var/folders/yn/8j0yr4gs2pzg508td1q42cv00000gn/T/codex-clipboard-f248a24d-7b41-4a6d-9db6-ba599554547c.png`.
- Runtime: `/private/tmp/pte-dismiss-more-open.jpeg` and `/private/tmp/pte-dismiss-more-closed.jpeg` from the OpenHarmony emulator at `2210 × 2416`.
- States compared: function panel visible and the same transcript immediately after tapping its content area.

**Findings**

- [P1, fixed] A touch-down in the transcript now clears input focus and closes the emoji or function panel. This applies to both a plain message-area tap and the first touch of an upward/downward scroll gesture.
- [P1, fixed] Focusing text closes an open picker; opening emoji/function closes the system input focus first, so keyboard and custom panels never overlap.
- [P2, verified] The transcript remains independently scrollable and the fixed input row stays visible after a panel closes.

**Verification**

- `hvigorw --mode module -p module=entry@default -p product=default assembleHap`: passed.
- Signed HAP reinstalled and started on `127.0.0.1:5557`; function panel open-to-close was exercised by tapping the chat content.

final result: passed

## Harmony Chat Emoji 338 and Rich Card Baseline QA — 2026-07-17

**Comparison Target**

- Source visual truth: `/var/folders/yn/8j0yr4gs2pzg508td1q42cv00000gn/T/codex-clipboard-6dfdc4bf-c5a5-4f2e-9b5c-4c27b52f6b80.png`.
- Runtime: `/private/tmp/pte-emoji-338-final.jpeg`, `/private/tmp/pte-dismiss-by-tap.jpeg`, and `/private/tmp/pte-rich-card-title-offset.jpeg` from the OpenHarmony emulator at `2210 × 2416`.
- States compared: 338vp dark emoji panel, tap-to-dismiss result, and red-packet/gift message-card baseline.

**Findings**

- [P1, fixed] The emoji panel now has a fixed 338vp height. Its category rail and title remain at the top, while the backspace and send controls float above the lower-right edge of the emoji grid, matching the supplied visual hierarchy.
- [P1, verified] A touch in the chat transcript closes the active emoji panel before the transcript receives the content interaction. The same touch-down path runs at the start of vertical scrolling.
- [P2, fixed] Red-packet and gift card title/subtitle content is shifted down by 7vp without changing the claimed/received footer alignment.

**Verification**

- `hvigorw --mode module -p module=entry@default -p product=default assembleHap`: passed.
- Signed HAP reinstalled and started on `127.0.0.1:5557`; emoji-open, chat-content tap-dismiss, and rich-card scrolling were visually verified.

final result: passed

## Harmony Rich Card Copy and Bottom Safe Area QA — 2026-07-17

**Comparison Target**

- Source visual truth: `/var/folders/yn/8j0yr4gs2pzg508td1q42cv00000gn/T/codex-clipboard-10cb5f55-3bb0-4000-8b31-a10928f32c06.png`.
- Runtime: `/private/tmp/pte-rich-copy-title-final.jpeg` and `/private/tmp/pte-top-bottom-final.jpeg` from the OpenHarmony emulator at `2210 × 2416`.
- States compared: dark red-packet/gift cards and the chat page’s bottom gesture safe area.

**Findings**

- [P1, fixed] Only the rich-card title and subtitle (`Alice` / `Starlight Box`) are offset down 7vp. The `Claimed` / `Received` footer remains on its original baseline.
- [P1, fixed] The root surface expands into the bottom system safe area, so the gesture region inherits the active chat theme instead of exposing a white platform backdrop.
- [P2, verified] Secondary chat navigation remains below the status bar after the safe-area change and the bottom composer remains fixed above the gesture indicator.

**Verification**

- `hvigorw --mode module -p module=entry@default -p product=default assembleHap`: passed.
- Signed HAP reinstalled and started on `127.0.0.1:5557`; chat and rich-card scroll states were visually compared against the supplied reference.

final result: passed
