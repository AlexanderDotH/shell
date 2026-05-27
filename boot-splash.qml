//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1

import "modules/startup"
import Quickshell

ShellRoot {
    settings.watchFiles: false

    BootSplash {}
}
