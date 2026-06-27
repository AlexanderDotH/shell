pragma Singleton

import Quickshell
import Caelestia.Config

Singleton {
    id: root

    // Hypr can expose null/dangling placeholders in Quickshell.screens during hotplug.
    readonly property list<ShellScreen> validScreens: {
        const out = [];
        for (let i = 0; i < Quickshell.screens.length; ++i) {
            const s = Quickshell.screens[i];
            if (!s)
                continue;
            if (!s.name)
                continue;
            out.push(s);
        }
        return out;
    }

    readonly property list<ShellScreen> screens: root.validScreens.filter(s => GlobalConfig.forScreen(s.name).enabled)

    function isExcluded(screen: ShellScreen): bool {
        return !GlobalConfig.forScreen(screen.name).enabled;
    }
}
