#include "codexresetcredits.hpp"

#include <algorithm>
#include <qjsonarray.h>
#include <qjsonobject.h>

namespace {

qint64 jsonLong(const QJsonValue& value) {
    if (value.isDouble()) {
        return qRound64(value.toDouble());
    }
    if (value.isString()) {
        return value.toString().toLongLong();
    }
    return 0;
}

} // namespace

namespace caelestia::services::codexresetcredits {

QVariantMap ResetCredit::toMap() const {
    return {
        { QStringLiteral("id"), id },
        { QStringLiteral("resetType"), resetType },
        { QStringLiteral("status"), status },
        { QStringLiteral("grantedAt"), grantedAt },
        { QStringLiteral("expiresAt"), expiresAt },
        { QStringLiteral("title"), title },
        { QStringLiteral("description"), description },
    };
}

QVariantMap ResetCreditsSummary::toMap() const {
    QVariantList mappedCredits;
    mappedCredits.reserve(credits.size());
    for (const auto& credit : credits) {
        mappedCredits.append(credit.toMap());
    }

    return {
        { QStringLiteral("state"), reported ? QStringLiteral("ready") : QStringLiteral("unavailable") },
        { QStringLiteral("availableCount"), availableCount },
        { QStringLiteral("credits"), mappedCredits },
    };
}

ResetCreditsSummary parse(const QJsonValue& value) {
    ResetCreditsSummary summary;
    if (!value.isObject()) {
        return summary;
    }

    const auto object = value.toObject();
    summary.reported = true;
    summary.availableCount = std::max<qint64>(0, jsonLong(object.value(QStringLiteral("availableCount"))));

    const auto credits = object.value(QStringLiteral("credits"));
    if (!credits.isArray()) {
        return summary;
    }

    const auto creditEntries = credits.toArray();
    for (const auto& entry : creditEntries) {
        if (!entry.isObject()) {
            continue;
        }
        const auto credit = entry.toObject();
        summary.credits.append({
            credit.value(QStringLiteral("id")).toString(),
            credit.value(QStringLiteral("resetType")).toString(),
            credit.value(QStringLiteral("status")).toString(QStringLiteral("unknown")),
            jsonLong(credit.value(QStringLiteral("grantedAt"))),
            jsonLong(credit.value(QStringLiteral("expiresAt"))),
            credit.value(QStringLiteral("title")).toString(),
            credit.value(QStringLiteral("description")).toString(),
        });
    }

    return summary;
}

} // namespace caelestia::services::codexresetcredits
