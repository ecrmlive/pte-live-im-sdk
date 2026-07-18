import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { PteIMBaseConfig, PteIMLanguage, PteIMSDK, PteIMThemeMode } from '@ptelive/pte-im-sdk'

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('pteDemoContext', this.context)
    // The SDK itself requires a secure public API origin. Demo authentication
    // can fall back to the local development service when the public endpoint
    // is unavailable (handled by Index.ets).
    const apiDomain = 'https://api-im.ptelive.com'
    const base = new PteIMBaseConfig(
      apiDomain, 'wss://wss.ptelive.com/ws', 'https://cos.ptelive.com',
      PteIMThemeMode.SYSTEM, PteIMLanguage.EN_US,
    )
    base.validate()
    AppStorage.setOrCreate('pteDemoApiDomain', apiDomain)
    AppStorage.setOrCreate('pteDemoBootstrap', PteIMSDK.configure(this.context, base))
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Page code owns the live colour; retaining the stage lets it keep the
    // system status bar exactly aligned with each page navigation bar.
    AppStorage.setOrCreate('pteDemoWindowStage', windowStage)
    windowStage.loadContent('pages/Index', (error) => { if (error.code) console.error(`load PteIMUIDemo failed: ${error.code}`) })
  }
}
