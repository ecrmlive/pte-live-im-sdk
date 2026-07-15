import { PteIMThemeMode, PteIMSDK } from '@ptelive/pte-im-sdk'

/** Independently configurable colours for one PteIMUIkit appearance. */
export class PteIMUIThemePalette {
  background: string
  surface: string
  composer: string
  incoming: string
  outgoingStart: string
  outgoingEnd: string
  text: string
  muted: string
  incomingText: string
  outgoingText: string
  icon: string
  divider: string
  panel: string
  panelItem: string

  constructor(background: string, surface: string, composer: string, incoming: string, outgoingStart: string, outgoingEnd: string, text: string, muted: string, incomingText: string, outgoingText: string, icon: string, divider: string, panel: string, panelItem: string) {
    this.background = background; this.surface = surface; this.composer = composer; this.incoming = incoming
    this.outgoingStart = outgoingStart; this.outgoingEnd = outgoingEnd; this.text = text; this.muted = muted
    this.incomingText = incomingText; this.outgoingText = outgoingText; this.icon = icon; this.divider = divider
    this.panel = panel; this.panelItem = panelItem
  }
}

/** Light/dark are deliberate independent palettes; neither is derived from the other. */
export class PteIMUITheme {
  light: PteIMUIThemePalette
  dark: PteIMUIThemePalette

  constructor(light: PteIMUIThemePalette = PteIMUITheme.lightPalette(), dark: PteIMUIThemePalette = PteIMUITheme.darkPalette()) { this.light = light; this.dark = dark }
  static lightPalette(): PteIMUIThemePalette { return new PteIMUIThemePalette('#F7F9FF', '#FFFFFF', '#FFFFFF', '#EDF1FD', '#335EF4', '#7D40EF', '#171C2E', '#666D84', '#171C2E', '#FFFFFF', '#373E5A', '#DDE2F2', '#F4F6FF', '#FFFFFF') }
  static darkPalette(): PteIMUIThemePalette { return new PteIMUIThemePalette('#0E111C', '#141827', '#181D2F', '#252B43', '#4467FF', '#8F4CFF', '#EFF2FF', '#A4ADCB', '#EFF2FF', '#FFFFFF', '#CCD3F2', '#313854', '#191E30', '#262D46') }
  static resolve(client: PteIMSDK, theme: PteIMUITheme = new PteIMUITheme(), systemDark: boolean = false): PteIMUIThemePalette {
    const mode = client.currentAppearance().themeMode
    return mode === PteIMThemeMode.DARK || (mode === PteIMThemeMode.SYSTEM && systemDark) ? theme.dark : theme.light
  }
}
