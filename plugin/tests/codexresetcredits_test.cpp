#include "codexresetcredits.hpp"

#include <iostream>
#include <qjsondocument.h>
#include <qjsonobject.h>

namespace {

using caelestia::services::codexresetcredits::parse;

bool expect(bool condition, const char* message) {
    if (condition) {
        return true;
    }

    std::cerr << "FAIL: " << message << '\n';
    return false;
}

} // namespace

int main() {
    bool ok = true;

    const auto document = QJsonDocument::fromJson(R"JSON({
        "availableCount": 4,
        "credits": [
            {
                "id": "reset-1",
                "resetType": "codexRateLimits",
                "status": "available",
                "grantedAt": 1784150000,
                "expiresAt": 1786750000,
                "title": "Full reset",
                "description": "Thanks for using Codex! You've been granted one free rate limit reset."
            },
            {
                "id": "reset-2",
                "resetType": "codexRateLimits",
                "status": "available",
                "grantedAt": 1784160000,
                "expiresAt": 1786751000,
                "title": "Full reset",
                "description": "A second reset."
            }
        ]
    })JSON");

    const auto summary = parse(document.object());
    ok &= expect(summary.reported, "a reset-credit response is reported");
    ok &= expect(summary.availableCount == 4, "the server-reported count is preserved");
    ok &= expect(summary.credits.size() == 2, "credit details are retained when present");
    ok &= expect(summary.credits.first().title == QStringLiteral("Full reset"), "the display title is preserved");
    ok &= expect(summary.credits.first().expiresAt == 1'786'750'000, "the expiry timestamp is preserved");

    const auto map = summary.toMap();
    ok &= expect(map.value(QStringLiteral("availableCount")).toLongLong() == 4, "the QML map exposes the count");
    const auto credits = map.value(QStringLiteral("credits")).toList();
    ok &= expect(credits.size() == 2, "the QML map exposes credit details");
    ok &= expect(credits.first()
                     .toMap()
                     .value(QStringLiteral("description"))
                     .toString()
                     .contains(QStringLiteral("free rate limit reset")),
        "the QML map exposes the backend description");

    const auto missing = parse(QJsonValue(QJsonValue::Null));
    ok &= expect(!missing.reported, "a null summary is unavailable rather than zero");
    ok &= expect(missing.toMap().value(QStringLiteral("state")).toString() == QStringLiteral("unavailable"),
        "an unavailable summary has an explicit UI state");

    return ok ? 0 : 1;
}
