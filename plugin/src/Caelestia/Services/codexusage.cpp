#include "codexusage.hpp"

#include "../Config/barconfig.hpp"
#include "../Config/config.hpp"

#include <algorithm>
#include <cmath>
#include <optional>
#include <qdir.h>
#include <qfile.h>
#include <qfileinfo.h>
#include <qjsonarray.h>
#include <qjsondocument.h>
#include <qjsonobject.h>
#include <qprocess.h>
#include <qset.h>
#include <qsqldatabase.h>
#include <qsqlquery.h>
#include <qsqlerror.h>
#include <qtimezone.h>

namespace {

constexpr qint64 kWeeklyWindowSeconds = 7 * 24 * 60 * 60;
constexpr qreal kPerMillion = 1'000'000.0;

struct Pricing {
    QString pricedModel;
    qreal input = 0.0;
    qreal cachedInput = 0.0;
    qreal output = 0.0;
    bool hasCachedInput = true;
    bool mapped = false;
};

qint64 jsonLong(const QJsonValue& value) {
    if (value.isDouble()) {
        return qRound64(value.toDouble());
    }
    if (value.isString()) {
        return value.toString().toLongLong();
    }
    return 0;
}

qreal jsonReal(const QJsonValue& value) {
    if (value.isDouble()) {
        return value.toDouble();
    }
    if (value.isString()) {
        return value.toString().toDouble();
    }
    return 0.0;
}

QDateTime parseTimestamp(const QString& value) {
    auto parsed = QDateTime::fromString(value, Qt::ISODateWithMs);
    if (parsed.isValid()) {
        return parsed;
    }
    return QDateTime::fromString(value, Qt::ISODate);
}

QString titleCasePlan(QString plan) {
    if (plan.isEmpty()) {
        return {};
    }
    plan.replace(u'_', u' ');
    plan.replace(u'-', u' ');
    const auto parts = plan.split(u' ', Qt::SkipEmptyParts);
    QStringList out;
    out.reserve(parts.size());
    for (const auto& part : parts) {
        out.append(part.left(1).toUpper() + part.mid(1));
    }
    return out.join(u' ');
}

QString maskEmail(const QString& email) {
    const auto at = email.indexOf(u'@');
    if (at <= 0) {
        return {};
    }
    const QString local = email.left(at);
    const QString domain = email.mid(at + 1);
    return local.left(std::min<qsizetype>(3, local.size())) + QStringLiteral("***@") + domain;
}

QJsonObject decodeJwtPayload(const QString& jwt) {
    const auto parts = jwt.split(u'.');
    if (parts.size() < 2) {
        return {};
    }

    QByteArray payload = parts.at(1).toLatin1();
    payload.replace('-', '+');
    payload.replace('_', '/');
    while (payload.size() % 4 != 0) {
        payload.append('=');
    }

    const auto decoded = QByteArray::fromBase64(payload);
    const auto doc = QJsonDocument::fromJson(decoded);
    return doc.isObject() ? doc.object() : QJsonObject {};
}

QString firstDefaultOrgTitle(const QJsonArray& organizations) {
    QString first;
    for (const auto& value : organizations) {
        const auto org = value.toObject();
        if (first.isEmpty()) {
            first = org.value(QStringLiteral("title")).toString();
        }
        if (org.value(QStringLiteral("is_default")).toBool()) {
            return org.value(QStringLiteral("title")).toString();
        }
    }
    return first;
}

QString normalizeModel(QString model) {
    model = model.trimmed().toLower();
    const auto paren = model.indexOf(QStringLiteral(" ("));
    if (paren > 0) {
        model = model.left(paren);
    }
    return model;
}

std::optional<Pricing> pricingForModel(const QString& rawModel) {
    const QString model = normalizeModel(rawModel);

    static const QHash<QString, Pricing> table {
        { QStringLiteral("gpt-5.5"), { QStringLiteral("gpt-5.5"), 5.0, 0.5, 30.0 } },
        { QStringLiteral("gpt-5.5-pro"), { QStringLiteral("gpt-5.5-pro"), 30.0, 0.0, 180.0, false } },
        { QStringLiteral("gpt-5.4"), { QStringLiteral("gpt-5.4"), 2.5, 0.25, 15.0 } },
        { QStringLiteral("gpt-5.4-mini"), { QStringLiteral("gpt-5.4-mini"), 0.75, 0.075, 4.5 } },
        { QStringLiteral("gpt-5.4-nano"), { QStringLiteral("gpt-5.4-nano"), 0.2, 0.02, 1.25 } },
        { QStringLiteral("gpt-5.4-pro"), { QStringLiteral("gpt-5.4-pro"), 30.0, 0.0, 180.0, false } },
        { QStringLiteral("gpt-5.3-codex"), { QStringLiteral("gpt-5.3-codex"), 1.75, 0.175, 14.0 } },
        { QStringLiteral("gpt-5.2-codex"), { QStringLiteral("gpt-5.2-codex"), 1.75, 0.175, 14.0 } },
        { QStringLiteral("gpt-5.1-codex-max"), { QStringLiteral("gpt-5.1-codex-max"), 1.25, 0.125, 10.0 } },
        { QStringLiteral("gpt-5.1-codex"), { QStringLiteral("gpt-5.1-codex"), 1.25, 0.125, 10.0 } },
        { QStringLiteral("gpt-5-codex"), { QStringLiteral("gpt-5-codex"), 1.25, 0.125, 10.0 } },
        { QStringLiteral("gpt-5.1-codex-mini"), { QStringLiteral("gpt-5.1-codex-mini"), 0.25, 0.025, 2.0 } },
        { QStringLiteral("codex-mini-latest"), { QStringLiteral("codex-mini-latest"), 1.5, 0.375, 6.0 } },
        { QStringLiteral("gpt-5.2"), { QStringLiteral("gpt-5.2"), 1.75, 0.175, 14.0 } },
        { QStringLiteral("gpt-5.1"), { QStringLiteral("gpt-5.1"), 1.25, 0.125, 10.0 } },
        { QStringLiteral("gpt-5"), { QStringLiteral("gpt-5"), 1.25, 0.125, 10.0 } },
        { QStringLiteral("gpt-5-mini"), { QStringLiteral("gpt-5-mini"), 0.25, 0.025, 2.0 } },
        { QStringLiteral("gpt-5-nano"), { QStringLiteral("gpt-5-nano"), 0.05, 0.005, 0.4 } },
    };

    if (table.contains(model)) {
        return table.value(model);
    }
    if (model == QStringLiteral("gpt-5.3-codex-spark")) {
        auto pricing = table.value(QStringLiteral("gpt-5.3-codex"));
        pricing.mapped = true;
        return pricing;
    }
    return std::nullopt;
}

} // namespace

namespace caelestia::services {

void CodexUsage::TokenUsage::add(const TokenUsage& other) {
    input += other.input;
    cachedInput += other.cachedInput;
    output += other.output;
    reasoningOutput += other.reasoningOutput;
    total += other.total;
}

QVariantMap CodexUsage::TokenUsage::toMap() const {
    return {
        { QStringLiteral("inputTokens"), QVariant::fromValue(input) },
        { QStringLiteral("cachedInputTokens"), QVariant::fromValue(cachedInput) },
        { QStringLiteral("outputTokens"), QVariant::fromValue(output) },
        { QStringLiteral("reasoningOutputTokens"), QVariant::fromValue(reasoningOutput) },
        { QStringLiteral("totalTokens"), QVariant::fromValue(total) },
    };
}

QVariantMap CodexUsage::RateWindow::toMap() const {
    return {
        { QStringLiteral("available"), available },
        { QStringLiteral("usedPercent"), usedPercent },
        { QStringLiteral("windowMinutes"), windowMinutes },
        { QStringLiteral("resetsAt"), resetsAt },
    };
}

CodexUsage::CodexUsage(QObject* parent)
    : Service(parent)
    , m_timer(new QTimer(this)) {
    m_timer->setSingleShot(false);
    QObject::connect(m_timer, &QTimer::timeout, this, &CodexUsage::refresh);

    auto* cfg = caelestia::config::GlobalConfig::instance()->bar()->codexUsage();
    QObject::connect(cfg, &caelestia::config::BarCodexUsage::refreshIntervalSecondsChanged, this, &CodexUsage::applyInterval);
    QObject::connect(cfg, &caelestia::config::BarCodexUsage::codexHomeChanged, this, &CodexUsage::refresh);
    QObject::connect(cfg, &caelestia::config::BarCodexUsage::monthlyWindowChanged, this, &CodexUsage::refresh);
    QObject::connect(cfg, &caelestia::config::BarCodexUsage::accountDisplayChanged, this, &CodexUsage::refresh);
    QObject::connect(cfg, &caelestia::config::BarCodexUsage::pricingBasisChanged, this, &CodexUsage::refresh);
}

bool CodexUsage::available() const {
    return m_available;
}

QString CodexUsage::status() const {
    return m_status;
}

qint64 CodexUsage::lastUpdated() const {
    return m_lastUpdated;
}

QString CodexUsage::authMode() const {
    return m_authMode;
}

QString CodexUsage::accountLabel() const {
    return m_accountLabel;
}

QString CodexUsage::planLabel() const {
    return m_planLabel;
}

QString CodexUsage::workspaceLabel() const {
    return m_workspaceLabel;
}

QVariantMap CodexUsage::fiveHour() const {
    return m_fiveHour;
}

QVariantMap CodexUsage::weekly() const {
    return m_weekly;
}

QVariantMap CodexUsage::monthlyTokens() const {
    return m_monthlyTokens;
}

qreal CodexUsage::monthlyApiDollars() const {
    return m_monthlyApiDollars;
}

QString CodexUsage::monthlyApiDollarsText() const {
    return m_monthlyApiDollarsText;
}

QVariantList CodexUsage::modelCostBreakdown() const {
    return m_modelCostBreakdown;
}

QString CodexUsage::pricingSource() const {
    return QStringLiteral("OpenAI API pricing, fetched 2026-06-29 from developers.openai.com/api/docs/pricing");
}

void CodexUsage::start() {
    m_running = true;
    applyInterval();
    refresh();
}

void CodexUsage::stop() {
    m_running = false;
    m_timer->stop();
}

void CodexUsage::applyInterval() {
    const auto seconds = std::max(5, caelestia::config::GlobalConfig::instance()
                                         ->bar()
                                         ->codexUsage()
                                         ->refreshIntervalSeconds());
    if (m_running) {
        m_timer->start(seconds * 1000);
    }
}

void CodexUsage::refresh() {
    const QString codexHome = resolveCodexHome();
    refreshAuth(codexHome);
    refreshUsage(codexHome);
    m_lastUpdated = QDateTime::currentSecsSinceEpoch();
    emit changed();
}

QString CodexUsage::resolveCodexHome() const {
    const QString configured = caelestia::config::GlobalConfig::instance()->bar()->codexUsage()->codexHome().trimmed();
    if (!configured.isEmpty()) {
        return QDir::cleanPath(configured);
    }

    const QByteArray env = qgetenv("CODEX_HOME");
    if (!env.isEmpty()) {
        return QDir::cleanPath(QString::fromLocal8Bit(env));
    }

    return QDir::home().filePath(QStringLiteral(".codex"));
}

qint64 CodexUsage::monthStartMs() const {
    const QString mode = caelestia::config::GlobalConfig::instance()->bar()->codexUsage()->monthlyWindow();
    const auto now = QDateTime::currentDateTime();
    if (mode == QStringLiteral("rolling30Days")) {
        return now.addDays(-30).toMSecsSinceEpoch();
    }

    const QDate firstDay(now.date().year(), now.date().month(), 1);
    return QDateTime(firstDay, QTime(0, 0), now.timeZone()).toMSecsSinceEpoch();
}

void CodexUsage::refreshAuth(const QString& codexHome) {
    m_authMode.clear();
    m_accountLabel.clear();
    m_planLabel.clear();
    m_workspaceLabel.clear();

    QFile file(QDir(codexHome).filePath(QStringLiteral("auth.json")));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_authMode = QStringLiteral("unknown");
        return;
    }

    const auto doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject()) {
        m_authMode = QStringLiteral("unknown");
        return;
    }

    const auto auth = doc.object();
    m_authMode = auth.value(QStringLiteral("auth_mode")).toString(QStringLiteral("unknown"));

    const auto tokens = auth.value(QStringLiteral("tokens")).toObject();
    const auto claims = decodeJwtPayload(tokens.value(QStringLiteral("id_token")).toString());
    const QString email = claims.value(QStringLiteral("email")).toString();
    const QString accountDisplay = caelestia::config::GlobalConfig::instance()->bar()->codexUsage()->accountDisplay();
    if (accountDisplay == QStringLiteral("planOnly")) {
        m_accountLabel = m_authMode == QStringLiteral("chatgpt") ? QStringLiteral("ChatGPT") : QStringLiteral("API key mode");
    } else if (accountDisplay == QStringLiteral("fullEmail") && !email.isEmpty()) {
        m_accountLabel = email;
    } else if (!email.isEmpty()) {
        m_accountLabel = maskEmail(email);
    } else if (m_authMode == QStringLiteral("apikey") || m_authMode == QStringLiteral("api")) {
        m_accountLabel = QStringLiteral("API key mode");
    }

    const auto openaiAuth = claims.value(QStringLiteral("https://api.openai.com/auth")).toObject();
    m_planLabel = titleCasePlan(openaiAuth.value(QStringLiteral("chatgpt_plan_type")).toString());
    m_workspaceLabel = firstDefaultOrgTitle(openaiAuth.value(QStringLiteral("organizations")).toArray());
}

void CodexUsage::refreshUsage(const QString& codexHome) {
    const QString stateDb = QDir(codexHome).filePath(QStringLiteral("state_5.sqlite"));
    if (!QFileInfo::exists(stateDb)) {
        m_available = false;
        m_status = QStringLiteral("No Codex state database");
        m_fiveHour = RateWindow {}.toMap();
        m_weekly = RateWindow {}.toMap();
        m_monthlyTokens = TokenUsage {}.toMap();
        m_modelCostBreakdown = {};
        m_monthlyApiDollars = 0.0;
        m_monthlyApiDollarsText = QStringLiteral("$0.00");
        return;
    }

    const qint64 startMs = monthStartMs();
    const qint64 querySince = std::min(startMs / 1000, QDateTime::currentSecsSinceEpoch() - kWeeklyWindowSeconds);
    const QString connection = QStringLiteral("caelestia-codex-usage-%1").arg(reinterpret_cast<quintptr>(this));

    QList<std::pair<QString, QString>> rollouts;
    QString dbError;
    {
        auto db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connection);
        db.setDatabaseName(stateDb);
        db.setConnectOptions(QStringLiteral("QSQLITE_OPEN_READONLY;QSQLITE_BUSY_TIMEOUT=1000"));
        if (!db.open()) {
            dbError = db.lastError().text();
        } else {
            QSqlQuery query(db);
            query.prepare(QStringLiteral(
                "SELECT rollout_path, COALESCE(model, '') FROM threads "
                "WHERE updated_at >= ? OR created_at >= ? ORDER BY updated_at DESC"));
            query.addBindValue(querySince);
            query.addBindValue(querySince);
            if (!query.exec()) {
                dbError = query.lastError().text();
            } else {
                while (query.next()) {
                    rollouts.append({ query.value(0).toString(), query.value(1).toString() });
                }
            }
        }
        db.close();
    }
    QSqlDatabase::removeDatabase(connection);

    if (!dbError.isEmpty()) {
        m_available = false;
        m_status = QStringLiteral("Codex database error: %1").arg(dbError);
        return;
    }

    TokenUsage totalUsage;
    QHash<QString, TokenUsage> usageByModel;
    RateWindow primary;
    RateWindow secondary;
    qint64 latestRate = 0;
    QSet<QString> visited;
    qsizetype parsedFiles = 0;

    for (const auto& rollout : rollouts) {
        if (rollout.first.isEmpty()) {
            continue;
        }
        visited.insert(rollout.first);
        auto parsed = parseRollout(rollout.first, rollout.second, startMs);
        if (!parsed.ok) {
            continue;
        }

        ++parsedFiles;
        totalUsage.add(parsed.monthUsage);
        for (auto it = parsed.usageByModel.constBegin(); it != parsed.usageByModel.constEnd(); ++it) {
            usageByModel[it.key()].add(it.value());
        }
        if (parsed.latestRateEventMs > latestRate) {
            latestRate = parsed.latestRateEventMs;
            primary = parsed.primary;
            secondary = parsed.secondary;
        }
    }

    QList<QString> stale;
    for (auto it = m_rolloutCache.constBegin(); it != m_rolloutCache.constEnd(); ++it) {
        if (!visited.contains(it.key())) {
            stale.append(it.key());
        }
    }
    for (const auto& key : stale) {
        m_rolloutCache.remove(key);
    }

    qreal dollars = 0.0;
    m_modelCostBreakdown = buildCostBreakdown(usageByModel, &dollars);
    m_monthlyApiDollars = dollars;
    m_monthlyApiDollarsText = QStringLiteral("$%1").arg(dollars, 0, 'f', dollars < 10.0 ? 2 : 0);
    m_monthlyTokens = totalUsage.toMap();
    m_fiveHour = primary.toMap();
    m_weekly = secondary.toMap();
    m_available = parsedFiles > 0;
    m_status = parsedFiles > 0 ? QStringLiteral("OK") : QStringLiteral("No Codex token-count events");
}

CodexUsage::RolloutCache CodexUsage::parseRollout(const QString& path, const QString& fallbackModel, qint64 startMs) {
    const QFileInfo info(path);
    if (!info.exists() || !info.isFile()) {
        return {};
    }

    const qint64 mtimeMs = info.lastModified().toMSecsSinceEpoch();
    const qint64 size = info.size();
    const auto cached = m_rolloutCache.constFind(path);
    if (cached != m_rolloutCache.constEnd() && cached->mtimeMs == mtimeMs && cached->size == size &&
        cached->monthStartMs == startMs) {
        return cached.value();
    }

    RolloutCache parsed;
    parsed.mtimeMs = mtimeMs;
    parsed.size = size;
    parsed.monthStartMs = startMs;

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return parsed;
    }

    QString currentModel = fallbackModel.isEmpty() ? QStringLiteral("unknown") : fallbackModel;
    while (!file.atEnd()) {
        const auto line = file.readLine();
        if (!line.contains("\"token_count\"")) {
            continue;
        }

        const auto doc = QJsonDocument::fromJson(line);
        if (!doc.isObject()) {
            continue;
        }

        const auto root = doc.object();
        const auto payload = root.value(QStringLiteral("payload")).toObject();
        if (payload.value(QStringLiteral("type")).toString() != QStringLiteral("token_count")) {
            continue;
        }

        const auto eventTime = parseTimestamp(root.value(QStringLiteral("timestamp")).toString());
        const qint64 eventMs = eventTime.isValid() ? eventTime.toMSecsSinceEpoch() : 0;
        const auto infoObj = payload.value(QStringLiteral("info")).toObject();
        const auto lastUsage = infoObj.value(QStringLiteral("last_token_usage")).toObject();
        TokenUsage usage {
            static_cast<quint64>(std::max<qint64>(0, jsonLong(lastUsage.value(QStringLiteral("input_tokens"))))),
            static_cast<quint64>(std::max<qint64>(0, jsonLong(lastUsage.value(QStringLiteral("cached_input_tokens"))))),
            static_cast<quint64>(std::max<qint64>(0, jsonLong(lastUsage.value(QStringLiteral("output_tokens"))))),
            static_cast<quint64>(std::max<qint64>(0, jsonLong(lastUsage.value(QStringLiteral("reasoning_output_tokens"))))),
            static_cast<quint64>(std::max<qint64>(0, jsonLong(lastUsage.value(QStringLiteral("total_tokens"))))),
        };

        if (eventMs >= startMs) {
            parsed.monthUsage.add(usage);
            parsed.usageByModel[normalizeModel(currentModel)].add(usage);
        }

        const auto rateLimits = payload.value(QStringLiteral("rate_limits")).toObject();
        if (!rateLimits.isEmpty() && eventMs >= parsed.latestRateEventMs) {
            const auto primary = rateLimits.value(QStringLiteral("primary")).toObject();
            const auto secondary = rateLimits.value(QStringLiteral("secondary")).toObject();
            parsed.primary = {
                !primary.isEmpty(),
                jsonReal(primary.value(QStringLiteral("used_percent"))),
                static_cast<int>(jsonLong(primary.value(QStringLiteral("window_minutes")))),
                jsonLong(primary.value(QStringLiteral("resets_at"))),
            };
            parsed.secondary = {
                !secondary.isEmpty(),
                jsonReal(secondary.value(QStringLiteral("used_percent"))),
                static_cast<int>(jsonLong(secondary.value(QStringLiteral("window_minutes")))),
                jsonLong(secondary.value(QStringLiteral("resets_at"))),
            };
            parsed.latestRateEventMs = eventMs;
        }
    }

    parsed.ok = parsed.monthUsage.total > 0 || parsed.primary.available || parsed.secondary.available;
    m_rolloutCache.insert(path, parsed);
    return parsed;
}

QVariantList CodexUsage::buildCostBreakdown(const QHash<QString, TokenUsage>& usageByModel, qreal* total) const {
    QVariantList rows;
    if (total != nullptr) {
        *total = 0.0;
    }

    QList<QString> models = usageByModel.keys();
    std::sort(models.begin(), models.end());

    for (const auto& model : models) {
        const auto usage = usageByModel.value(model);
        const QString basis = caelestia::config::GlobalConfig::instance()->bar()->codexUsage()->pricingBasis();
        QString comparisonModel = model;
        if (basis == QStringLiteral("gpt-5.5")) {
            comparisonModel = QStringLiteral("gpt-5.5");
        } else if (basis == QStringLiteral("codexModel")) {
            comparisonModel = QStringLiteral("gpt-5.3-codex");
        }

        const auto pricing = pricingForModel(comparisonModel);
        qreal dollars = 0.0;
        QString pricedModel;
        bool mapped = false;
        bool priced = false;

        if (pricing.has_value()) {
            const qreal uncachedInput = static_cast<qreal>(usage.input > usage.cachedInput ? usage.input - usage.cachedInput : 0);
            const qreal cachedInput = static_cast<qreal>(usage.cachedInput);
            const qreal output = static_cast<qreal>(usage.output);
            const qreal cachedRate = pricing->hasCachedInput ? pricing->cachedInput : pricing->input;
            dollars = (uncachedInput * pricing->input + cachedInput * cachedRate + output * pricing->output) / kPerMillion;
            pricedModel = pricing->pricedModel;
            mapped = pricing->mapped || pricedModel != model;
            priced = true;
            if (total != nullptr) {
                *total += dollars;
            }
        }

        rows.append(QVariantMap {
            { QStringLiteral("model"), model },
            { QStringLiteral("pricedModel"), pricedModel },
            { QStringLiteral("priced"), priced },
            { QStringLiteral("mapped"), mapped },
            { QStringLiteral("inputTokens"), QVariant::fromValue(usage.input) },
            { QStringLiteral("cachedInputTokens"), QVariant::fromValue(usage.cachedInput) },
            { QStringLiteral("outputTokens"), QVariant::fromValue(usage.output) },
            { QStringLiteral("reasoningOutputTokens"), QVariant::fromValue(usage.reasoningOutput) },
            { QStringLiteral("totalTokens"), QVariant::fromValue(usage.total) },
            { QStringLiteral("dollars"), dollars },
            { QStringLiteral("dollarsText"), QStringLiteral("$%1").arg(dollars, 0, 'f', dollars < 10.0 ? 2 : 0) },
        });
    }

    return rows;
}

} // namespace caelestia::services
