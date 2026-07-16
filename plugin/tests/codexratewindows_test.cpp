#include "codexratewindows.hpp"

#include <cmath>
#include <iostream>

namespace {

using caelestia::services::codexratewindows::normalize;
using caelestia::services::codexratewindows::RateWindow;

bool expect(bool condition, const char* message) {
    if (condition) {
        return true;
    }

    std::cerr << "FAIL: " << message << '\n';
    return false;
}

RateWindow window(int minutes, qreal usedPercent = 25.0, qint64 resetsAt = 1'800'000'000) {
    return {
        true,
        usedPercent,
        minutes,
        resetsAt,
    };
}

} // namespace

int main() {
    bool ok = true;

    const auto both = normalize(window(300), window(10'080));
    ok &= expect(both.fiveHour.available, "300-minute primary is the five-hour limit");
    ok &= expect(both.weekly.available, "10080-minute secondary is the weekly limit");

    const auto weeklyOnly = normalize(window(10'080, 11.0, 1'784'834'527), {});
    ok &= expect(!weeklyOnly.fiveHour.available, "weekly-only primary does not create a five-hour limit");
    ok &= expect(weeklyOnly.weekly.available, "weekly-only primary remains visible as weekly");
    ok &= expect(std::abs(weeklyOnly.weekly.usedPercent - 11.0) < 0.000'001, "weekly-only usage percent is preserved");
    ok &= expect(weeklyOnly.weekly.resetsAt == 1'784'834'527, "weekly-only reset time is preserved");

    const auto fiveHourOnly = normalize(window(300), {});
    ok &= expect(fiveHourOnly.fiveHour.available, "five-hour-only primary remains visible as five-hour");
    ok &= expect(!fiveHourOnly.weekly.available, "five-hour-only primary does not create a weekly limit");

    const auto secondaryOnly = normalize({}, window(10'080));
    ok &= expect(!secondaryOnly.fiveHour.available, "weekly-only secondary does not create a five-hour limit");
    ok &= expect(secondaryOnly.weekly.available, "weekly-only secondary remains visible as weekly");

    const auto swapped = normalize(window(10'080), window(300));
    ok &= expect(swapped.fiveHour.windowMinutes == 300, "swapped five-hour window is classified by duration");
    ok &= expect(swapped.weekly.windowMinutes == 10'080, "swapped weekly window is classified by duration");

    const auto legacy = normalize(window(0), window(0));
    ok &= expect(legacy.fiveHour.available, "duration-less primary keeps legacy five-hour fallback");
    ok &= expect(legacy.weekly.available, "duration-less secondary keeps legacy weekly fallback");

    const auto staggeredResets = normalize(window(300, 20.0, 1'800'000'000), window(10'080, 40.0, 1'750'000'000));
    ok &= expect(
        staggeredResets.nextResetAt(1'700'000'000) == 1'750'000'000, "next reset returns the earliest future boundary");
    ok &= expect(both.nextResetAt(1'900'000'000) == 0, "past reset boundaries are ignored");

    return ok ? 0 : 1;
}
