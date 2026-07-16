#include "codexratewindows.hpp"

#include <algorithm>
#include <array>

namespace {

constexpr int kLongWindowMinimumMinutes = 24 * 60;

enum class WindowKind {
    Unknown,
    FiveHour,
    Weekly,
};

WindowKind classify(const caelestia::services::codexratewindows::RateWindow& window) {
    if (!window.available || window.windowMinutes <= 0) {
        return WindowKind::Unknown;
    }
    if (window.windowMinutes < kLongWindowMinimumMinutes) {
        return WindowKind::FiveHour;
    }
    return WindowKind::Weekly;
}

bool assignByDuration(caelestia::services::codexratewindows::RateWindows& normalized,
    const caelestia::services::codexratewindows::RateWindow& window) {
    switch (classify(window)) {
    case WindowKind::FiveHour:
        if (!normalized.fiveHour.available) {
            normalized.fiveHour = window;
        }
        return true;
    case WindowKind::Weekly:
        if (!normalized.weekly.available) {
            normalized.weekly = window;
        }
        return true;
    case WindowKind::Unknown:
        return false;
    }
    return false;
}

void assignFallback(caelestia::services::codexratewindows::RateWindows& normalized,
    const caelestia::services::codexratewindows::RateWindow& window, bool preferFiveHour) {
    if (!window.available) {
        return;
    }
    if (preferFiveHour && !normalized.fiveHour.available) {
        normalized.fiveHour = window;
        return;
    }
    if (!normalized.weekly.available) {
        normalized.weekly = window;
        return;
    }
    if (!normalized.fiveHour.available) {
        normalized.fiveHour = window;
    }
}

} // namespace

namespace caelestia::services::codexratewindows {

QVariantMap RateWindow::toMap() const {
    return {
        { QStringLiteral("available"), available },
        { QStringLiteral("usedPercent"), usedPercent },
        { QStringLiteral("windowMinutes"), windowMinutes },
        { QStringLiteral("resetsAt"), resetsAt },
    };
}

qint64 RateWindows::nextResetAt(qint64 now) const {
    qint64 next = 0;
    for (const auto& window : std::array{ fiveHour, weekly }) {
        if (!window.available || window.resetsAt <= now) {
            continue;
        }
        next = next == 0 ? window.resetsAt : std::min(next, window.resetsAt);
    }
    return next;
}

RateWindows normalize(const RateWindow& primary, const RateWindow& secondary) {
    RateWindows normalized;
    const bool primaryClassified = assignByDuration(normalized, primary);
    const bool secondaryClassified = assignByDuration(normalized, secondary);

    if (!primaryClassified) {
        assignFallback(normalized, primary, true);
    }
    if (!secondaryClassified) {
        assignFallback(normalized, secondary, false);
    }
    return normalized;
}

} // namespace caelestia::services::codexratewindows
