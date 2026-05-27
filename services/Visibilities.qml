pragma Singleton

import Quickshell
import qs.components
import qs.services

Singleton {
    property var screens: new Map()
    property var bars: new Map()

    function load(screen: ShellScreen, visibilities: DrawerVisibilities): void {
        const mon = Hypr.safeMonitorFor(screen);
        if (!mon)
            return;
        screens.set(mon, visibilities);
    }

    function getForActive(): DrawerVisibilities {
        return screens.get(Hypr.focusedMonitor);
    }
}
