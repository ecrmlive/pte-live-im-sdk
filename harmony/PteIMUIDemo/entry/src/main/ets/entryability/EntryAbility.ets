import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { PteIMBaseConfig, PteIMLanguage, PteIMSDK, PteIMThemeMode } from '@ptelive/pte-im-sdk'

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('pteDemoContext', this.context)
    // Domains belong to the application lifecycle, never to a login form.
    const base = new PteIMBaseConfig(
      'https://api-im.ptelive.com', 'wss://wss.ptelive.com/ws', 'https://cos.ptelive.com',
      PteIMThemeMode.SYSTEM, PteIMLanguage.EN_US,
    )
    base.validate()
    AppStorage.setOrCreate('pteDemoBootstrap', PteIMSDK.configure(this.context, base))
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Page code owns the live colour; retaining the stage lets it keep the
    // system status bar exactly aligned with each page navigation bar.
    AppStorage.setOrCreate('pteDemoWindowStage', windowStage)
    windowStage.loadContent('pages/Index', (error) => { if (error.code) console.error(`load PteIMUIDemo failed: ${error.code}`) })
  }
}
