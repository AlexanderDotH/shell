#pragma once

#include <qglobal.h>
#include <qvariant.h>

namespace caelestia::services::codexratewindows {

struct RateWindow {
    bool available = false;
    qreal usedPercent = 0.0;
    int windowMinutes = 0;
    qint64 resetsAt = 0;

    [[nodiscard]] QVariantMap toMap() const;
};

struct RateWindows {
    RateWindow fiveHour;
    RateWindow weekly;

    [[nodiscard]] qint64 nextResetAt(qint64 now) const;
};

[[nodiscard]] RateWindows normalize(const RateWindow& primary, const RateWindow& secondary);

} // namespace caelestia::services::codexratewindows
