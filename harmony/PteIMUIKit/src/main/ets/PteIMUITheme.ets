import { PteIMThemeMode, PteLiveIM } from '@ptelive/im'

/** Presentation values shared by the built-in ArkUI components. */
export class PteIMUITheme {
  background: string
  surface: string
  text: string
  muted: string
  outgoing: string
  incoming: string

  constructor(background: string, surface: string, text: string, muted: string, outgoing: string, incoming: string) {
    this.background = background
    this.surface = surface
    this.text = text
    this.muted = muted
    this.outgoing = outgoing
    this.incoming = incoming
  }
  static resolve(client: PteLiveIM): PteIMUITheme {
    const mode = client.currentAppearance().themeMode
    const dark = mode === PteIMThemeMode.DARK
    return dark ? new PteIMUITheme('#18181B', '#27272A', '#F5F5F5', '#C4C4CC', '#1E5F9E', '#3F3F46') : new PteIMUITheme('#F7F9FC', '#FFFFFF', '#191C21', '#606975', '#1976D2', '#EBEFF5')
  }
}
