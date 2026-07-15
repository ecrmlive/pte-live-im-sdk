import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('pteDemoContext', this.context)
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (error) => { if (error.code) console.error(`load PteLive IM demo failed: ${error.code}`) })
  }
}
