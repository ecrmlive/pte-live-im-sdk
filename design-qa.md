**Comparison Target**

- Source visual truth: `/Users/daniel/Downloads/私域直播SDK设计图/亮色/亮色-会话列表.png`, `亮色-联系人.png`, and `亮色-聊天.png`.
- Rendered implementation: `/private/tmp/pte-im-ios-conversations-v2.png`, `/private/tmp/pte-im-ios-contacts-v1.png`, and `/private/tmp/pte-im-ios-chat-time-v1.png`.
- Full-view comparison evidence: `/private/tmp/pte-im-ios-chat-time-comparison.png` combines the chat design and the iPhone 15 Pro simulator capture in one image.
- Viewport/state: iPhone 15 Pro, iOS 17.0, light skin, Chinese UI; deterministic offline conversation/contact/chat fixtures.

**Findings**

- [P1] Rich message cards do not yet match the supplied chat design.
  Location: `PteIMUIMessageCell`.
  Evidence: the source has distinct location-map, image, video, red-packet, reaction, and order-card presentations; the rendered page shows text, location, voice, and order through the generic bubble renderer.
  Impact: the message-type UI is materially less informative than the design and cannot be visually accepted.
  Fix: add built-in specialized UIKit cells for image, video, location, red packet, gift, order, and file; use the provided PteIMUIKit-owned cut assets where the design supplies them.

- [P1] Conversation/contact asset and row fidelity is incomplete.
  Location: list chrome and cells.
  Evidence: screenshots use a text `P` mark and SF Symbols; the design supplies a product logo and specific cut icons. The contact capture also predates the latest lavender row-token correction.
  Impact: branded visual details and the finished light skin remain inconsistent.
  Fix: place only shared list/chat cut assets in `PteIMUIKit/Resources`, load them through a replaceable image provider, capture the revised conversation/contact pages, then repeat comparison.

- [P2] Chat content density differs from the reference.
  Location: chat timeline.
  Evidence: date separators, incoming/outgoing external timestamps, and outgoing read marks now match the reference hierarchy. Reactions and varied media-card heights are still absent.
  Impact: the core flow works, but the visual rhythm is not yet the supplied design.
  Fix: add date separators, receipt/reaction renderers and fixture coverage after the specialized cells are in place.

**Required Fidelity Surfaces**

- Fonts and typography: native UIKit Dynamic Type is used; title hierarchy and bilingual wrapping are legible, but rich-card typography remains unimplemented.
- Spacing and layout rhythm: the oversized/incorrect list header width was fixed; chat now hides the root tab bar and the composer owns the lower safe area. List row/card rhythm needs a new capture after the lavender token update.
- Colors and visual tokens: light skin uses the required blue–purple outgoing gradient and lavender canvas. The latest list-cell token correction is pending capture.
- Image quality and asset fidelity: no source asset has been faked for the new review. Required shared cut assets have not yet been moved into UIKit, so the visible brand mark and rich message art are outstanding.
- Copy and content: Chinese/English labels and deterministic fixture content render; design-specific reactions and business-card labels remain outstanding.

**Comparison History**

1. Initial runtime was blocked by a preview path that opened the protected local cache. Fixed by making `PteIMSDK.preview` use an in-memory Core Data store and temporary local cipher.
2. Initial conversation capture had a narrow table header. Fixed by frame-driven `tableHeaderView` layout; revised evidence is `pte-im-ios-conversations-v2.png`.
3. Initial chat capture retained the root tab bar. Fixed by `PteIMUIChatViewController.hidesBottomBarWhenPushed`.
4. Initial chat timestamps appeared inside bubbles and lacked a day grouping. Fixed with day-based table sections, reference-style line separators, external incoming/outgoing timestamps and outgoing read marks; revised evidence is `pte-im-ios-chat-time-v1.png` and `pte-im-ios-chat-time-comparison.png`.

**Implementation Checklist**

1. Add the remaining specialized message cells and shared UIKit cut assets.
2. Re-capture conversation/contact after the latest list skin change.
3. Capture light/dark, emoji panel, and more panel states; compare each with the matching source state.
4. Only after iOS has no actionable P1/P2 findings, port the confirmed design tokens and interactions to Android, HarmonyOS, and UTS.

final result: blocked
