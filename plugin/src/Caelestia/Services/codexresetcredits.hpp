#pragma once

#include <qjsonvalue.h>
#include <qstring.h>
#include <qvariant.h>
#include <qvector.h>

namespace caelestia::services::codexresetcredits {

struct ResetCredit {
    QString id;
    QString resetType;
    QString status;
    qint64 grantedAt = 0;
    qint64 expiresAt = 0;
    QString title;
    QString description;

    [[nodiscard]] QVariantMap toMap() const;
};

struct ResetCreditsSummary {
    bool reported = false;
    qint64 availableCount = 0;
    QVector<ResetCredit> credits;

    [[nodiscard]] QVariantMap toMap() const;
};

[[nodiscard]] ResetCreditsSummary parse(const QJsonValue& value);

} // namespace caelestia::services::codexresetcredits
