# PteIMUIDemo visual QA

## Comparison target

- Source visual truth: `/var/folders/yn/8j0yr4gs2pzg508td1q42cv00000gn/T/codex-clipboard-d0405a2a-70b9-4022-a5e7-e154524309b3.png` (Harmony registration page supplied by the user).
- Implementation capture: `/private/tmp/pte-h5-register-current.png`.
- Full-view comparison: `/private/tmp/pte-register-reference-vs-h5.png`.
- Viewport: 390 × 844 H5; the source includes its native phone frame and status bar.
- State: dark English registration, server-generated CAPTCHA, password hidden, top-left navigation back action visible, no secondary bottom action.

## Comparison history

1. The first H5 registration capture included a bottom `Back to login` action.
   - Fix: registration now uses the shared 44 px navigation component in back mode; the bottom secondary action has been removed.
   - Pending capture: verify the registration back action and removed bottom control in both H5 and WeChat simulator.
2. The first local auth attempt could not load a CAPTCHA because the H5 runtime attempted to replace the read-only native Web Crypto object.
   - Fix: retain native Web Crypto when `getRandomValues` is available; only install the mini-program bridge when it is missing.
   - Post-fix: H5 displays a fresh API CAPTCHA (for example `A4LM`) rather than the fallback image.
3. The language selector created its menu but the shared navigation shell clipped it at the 44 px navigation boundary.
   - Fix: the shared navigation shell now has visible overflow and a menu layer above the authentication scroll layer.
   - Post-fix: H5 at 390 × 844 shows both language choices; selecting English closes the menu and updates the login copy.
4. The language label was left-aligned inside its visual pill because the cross-platform text node filled only the old padded content area.
   - Fix: the shared language button now uses a centered flex layout and a full-width centered text node.
   - Post-fix: H5 at 390 × 844 measures zero center-point difference between the language label and its button; the same generated CSS is used by WeChat Mini Program.

## Findings

- [P2] Native status-bar frame and browser frame cannot be compared as one crop.
  - Location: above the fixed 44 px navigation on the source device versus H5 browser capture.
  - Evidence: the source includes Harmony system chrome; the H5 capture starts at the application navigation bar. The application navigation height, dark token and left/right controls are present in both.
  - Impact: direct full-frame vertical coordinates are not a valid pixel measurement until a Harmony capture is rebuilt from the updated source.
  - Fix: rebuild and capture the updated Harmony module at the same logical viewport, then make a content-region-only contact sheet for login and registration.

- [P2] WeChat simulator visual acceptance is pending after the new capsule-safe right inset.
  - Location: authentication navigation right-side theme action.
  - Evidence: the generated mini-program bundle contains the `rightInset` property and the dynamic capsule calculation, but the developer tool session was closed before a fresh simulator screenshot could be captured.
  - Impact: the intended layout fix is compiled but not yet visually accepted in the WeChat simulator.
  - Fix: reopen the local mini-program build and capture login plus open-language-menu states on the iPhone 12/13 Pro simulator.

- [P2] Registration back control and password-eye theme treatment need a fresh runtime capture.
  - Location: registration navigation and password field.
  - Evidence: source now selects the shared navigation component's `showBack` mode, removes `Back to login`, and applies the supplied eye asset in black for light mode and white treatment for dark mode. The generated mini-program bundle contains the same shared source behavior.
  - Impact: source and generated mini-program agree; visual acceptance awaits a refreshed H5/WeChat capture.
  - Fix: capture both themes in H5 and WeChat after developer-tool login is restored.

- [P2] The real registration-to-friend-to-message route still needs the final send/receive assertion.
  - Location: Demo business auth and contact flow.
  - Evidence: two independent H5 accounts were registered through the visible local CAPTCHA, both logged in, the second account appeared in the first account's registered-user list, and the real `/demo/friends/add` call completed. The contact opened a single-chat route. The browser reload discarded the pre-persistence in-memory demo sessions before the final text-message assertion.
  - Impact: registration, authentication, friend creation and chat routing are verified against the local service; one send/receive evidence capture remains.
  - Fix: re-enter either visible CAPTCHA once, then use the persisted credential session to send and receive a text message without re-authenticating on browser reload.

## Required fidelity surfaces

- Fonts and typography: the 29 px PrivateChat title, 14 px subtitle, 13 px labels, 15 px inputs and 16 px primary actions match the source hierarchy; platform rasterization differs between Harmony and browser.
- Spacing and layout rhythm: 30 px page inset, 24 px card radius, 46 px inputs, 50 px primary action and 46 px switch action are implemented. The post-fix registration primary action and switch action are in-frame.
- Colors and visual tokens: dark navigation/status token `#0E111C`, auth surface `#0D0D21`, panel `#11102A`, field `#201E4C`, border `#39345A` and purple action gradient are used consistently.
- Image quality and asset fidelity: Harmony logo, lock, password visibility and theme assets are raster source assets; CAPTCHA comes from the local service in runtime.
- Copy and content: login uses `Create demo account`; registration has no bottom return action and returns via the top navigation button.

## Primary interactions checked

- H5: navigation into registration; password visibility asset state; real CAPTCHA load; two real registrations, two logins, registered-user retrieval, real friend creation and single-chat opening. The revised top-return registration state awaits a fresh capture.
- Mini-program build: compilation contains capsule-safe `rightInset`, real local auth origin and friend endpoint bridge.
- Shared auth session: a successful real login now stores only the issued demo credential (never the password), restores the IM client after an H5/mini-program restart, and clears it explicitly on logout.

## Implementation checklist

1. Capture rebuilt Harmony login and registration, then repeat the content-region parity check.
2. Capture the rebuilt WeChat simulator with the capsule-safe right inset.
3. Complete the two-account local auth, add-friend and message exchange test.

final result: blocked
