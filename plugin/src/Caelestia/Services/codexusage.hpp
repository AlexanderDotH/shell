#pragma once

#include "codexresetcredits.hpp"
#include "codexratewindows.hpp"
#include "service.hpp"

#include <qbytearray.h>
#include <qdatetime.h>
#include <qhash.h>
#include <qprocess.h>
#include <qqmlintegration.h>
#include <qstring.h>
#include <qtimer.h>
#include <qvariant.h>

namespace caelestia::services {

class CodexUsage : public Service {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(qint64 lastUpdated READ lastUpdated NOTIFY changed)
    Q_PROPERTY(QString authMode READ authMode NOTIFY changed)
    Q_PROPERTY(QString accountLabel READ accountLabel NOTIFY changed)
    Q_PROPERTY(QString planLabel READ planLabel NOTIFY changed)
    Q_PROPERTY(QString workspaceLabel READ workspaceLabel NOTIFY changed)
    Q_PROPERTY(QVariantMap fiveHour READ fiveHour NOTIFY changed)
    Q_PROPERTY(QVariantMap weekly READ weekly NOTIFY changed)
    Q_PROPERTY(QVariantMap rateLimitResets READ rateLimitResets NOTIFY changed)
    Q_PROPERTY(QVariantMap monthlyTokens READ monthlyTokens NOTIFY changed)
    Q_PROPERTY(qreal monthlyApiDollars READ monthlyApiDollars NOTIFY changed)
    Q_PROPERTY(QString monthlyApiDollarsText READ monthlyApiDollarsText NOTIFY changed)
    Q_PROPERTY(QVariantList modelCostBreakdown READ modelCostBreakdown NOTIFY changed)
    Q_PROPERTY(QString pricingSource READ pricingSource CONSTANT)

public:
    explicit CodexUsage(QObject* parent = nullptr);

    [[nodiscard]] bool available() const;
    [[nodiscard]] QString status() const;
    [[nodiscard]] qint64 lastUpdated() const;
    [[nodiscard]] QString authMode() const;
    [[nodiscard]] QString accountLabel() const;
    [[nodiscard]] QString planLabel() const;
    [[nodiscard]] QString workspaceLabel() const;
    [[nodiscard]] QVariantMap fiveHour() const;
    [[nodiscard]] QVariantMap weekly() const;
    [[nodiscard]] QVariantMap rateLimitResets() const;
    [[nodiscard]] QVariantMap monthlyTokens() const;
    [[nodiscard]] qreal monthlyApiDollars() const;
    [[nodiscard]] QString monthlyApiDollarsText() const;
    [[nodiscard]] QVariantList modelCostBreakdown() const;
    [[nodiscard]] QString pricingSource() const;

    Q_INVOKABLE void refresh();

signals:
    void changed();

private:
    struct TokenUsage {
        quint64 input = 0;
        quint64 cachedInput = 0;
        quint64 output = 0;
        quint64 reasoningOutput = 0;
        quint64 total = 0;

        void add(const TokenUsage& other);
        [[nodiscard]] QVariantMap toMap() const;
    };

    struct RolloutCache {
        qint64 mtimeMs = 0;
        qint64 size = 0;
        qint64 monthStartMs = 0;
        qint64 latestRateEventMs = 0;
        bool ok = false;
        TokenUsage monthUsage;
        QHash<QString, TokenUsage> usageByModel;
        codexratewindows::RateWindow primary;
        codexratewindows::RateWindow secondary;
    };

    void start() override;
    void stop() override;
    void applyInterval();
    void scheduleResetRefresh(const codexratewindows::RateWindows& windows);
    void startAppServer();
    void stopAppServer();
    void initializeAppServer();
    void requestRateLimitResets();
    void handleAppServerOutput();
    void setResetCreditsState(const QString& state);
    void refreshAuth(const QString& codexHome);
    void refreshUsage(const QString& codexHome);

    [[nodiscard]] QString resolveCodexHome() const;
    [[nodiscard]] qint64 monthStartMs() const;
    [[nodiscard]] RolloutCache parseRollout(const QString& path, const QString& fallbackModel, qint64 monthStartMs);
    [[nodiscard]] QVariantList buildCostBreakdown(const QHash<QString, TokenUsage>& usageByModel, qreal* total) const;

    QTimer* m_timer;
    QTimer* m_resetTimer;
    QProcess* m_appServer;
    QHash<QString, RolloutCache> m_rolloutCache;
    QByteArray m_appServerBuffer;

    bool m_running = false;
    bool m_appServerInitialized = false;
    bool m_resetCreditsPending = false;
    qint64 m_nextAppServerRequestId = 1;
    qint64 m_initializeRequestId = 0;
    qint64 m_rateLimitsRequestId = 0;
    bool m_available = false;
    QString m_status;
    qint64 m_lastUpdated = 0;
    QString m_authMode;
    QString m_accountLabel;
    QString m_planLabel;
    QString m_workspaceLabel;
    QVariantMap m_fiveHour;
    QVariantMap m_weekly;
    QVariantMap m_rateLimitResets {
        { QStringLiteral("state"), QStringLiteral("loading") },
        { QStringLiteral("availableCount"), 0 },
        { QStringLiteral("credits"), QVariantList {} },
    };
    QVariantMap m_monthlyTokens;
    qreal m_monthlyApiDollars = 0.0;
    QString m_monthlyApiDollarsText = QStringLiteral("$0.00");
    QVariantList m_modelCostBreakdown;
};

} // namespace caelestia::services
