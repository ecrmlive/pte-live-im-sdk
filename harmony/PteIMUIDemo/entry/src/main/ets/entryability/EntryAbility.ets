import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { PteIMBaseConfig, PteIMLanguage, PteIMSDK, PteIMThemeMode } from '@ptelive/pte-im-sdk'

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('pteDemoContext', this.context)
    // Debug uses the same localhost origin as the other demo clients.
    // Production hosts replace these local development origins during their build.
    const apiDomain = 'http://127.0.0.1:11504'
    const base = new PteIMBaseConfig(
      apiDomain, 'ws://127.0.0.1:11510/ws', apiDomain,
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
