#include "codexpricing.hpp"

#include <qhash.h>

namespace caelestia::services::codexpricing {

namespace {

constexpr qreal kPerMillion = 1'000'000.0;

const QHash<QString, ModelPricing>& pricingCatalog() {
    static const QHash<QString, ModelPricing> catalog{
        // Current frontier models.
        { QStringLiteral("gpt-5.6-sol"), { QStringLiteral("gpt-5.6-sol"), 5.0, 0.5, 30.0 } },
        { QStringLiteral("gpt-5.6-terra"), { QStringLiteral("gpt-5.6-terra"), 2.5, 0.25, 15.0 } },
        { QStringLiteral("gpt-5.6-luna"), { QStringLiteral("gpt-5.6-luna"), 1.0, 0.1, 6.0 } },
        { QStringLiteral("gpt-5.5"), { QStringLiteral("gpt-5.5"), 5.0, 0.5, 30.0 } },
        { QStringLiteral("gpt-5.5-pro"), { QStringLiteral("gpt-5.5-pro"), 30.0, 0.0, 180.0, false } },
        { QStringLiteral("gpt-5.4"), { QStringLiteral("gpt-5.4"), 2.5, 0.25, 15.0 } },
        { QStringLiteral("gpt-5.4-mini"), { QStringLiteral("gpt-5.4-mini"), 0.75, 0.075, 4.5 } },
        { QStringLiteral("gpt-5.4-nano"), { QStringLiteral("gpt-5.4-nano"), 0.2, 0.02, 1.25 } },
        { QStringLiteral("gpt-5.4-pro"), { QStringLiteral("gpt-5.4-pro"), 30.0, 0.0, 180.0, false } },

        // Codex-specific models.
        { QStringLiteral("gpt-5.3-codex"), { QStringLiteral("gpt-5.3-codex"), 1.75, 0.175, 14.0 } },
        { QStringLiteral("gpt-5.2-codex"), { QStringLiteral("gpt-5.2-codex"), 1.75, 0.175, 14.0 } },
        { QStringLiteral("gpt-5.1-codex-max"), { QStringLiteral("gpt-5.1-codex-max"), 1.25, 0.125, 10.0 } },
        { QStringLiteral("gpt-5.1-codex"), { QStringLiteral("gpt-5.1-codex"), 1.25, 0.125, 10.0 } },
        { QStringLiteral("gpt-5-codex"), { QStringLiteral("gpt-5-codex"), 1.25, 0.125, 10.0 } },
        { QStringLiteral("gpt-5.1-codex-mini"), { QStringLiteral("gpt-5.1-codex-mini"), 0.25, 0.025, 2.0 } },
        { QStringLiteral("codex-mini-latest"), { QStringLiteral("codex-mini-latest"), 1.5, 0.375, 6.0 } },

        // Previous general-purpose models still present in local rollouts.
        { QStringLiteral("gpt-5.2"), { QStringLiteral("gpt-5.2"), 1.75, 0.175, 14.0 } },
        { QStringLiteral("gpt-5.1"), { QStringLiteral("gpt-5.1"), 1.25, 0.125, 10.0 } },
        { QStringLiteral("gpt-5"), { QStringLiteral("gpt-5"), 1.25, 0.125, 10.0 } },
        { QStringLiteral("gpt-5-mini"), { QStringLiteral("gpt-5-mini"), 0.25, 0.025, 2.0 } },
        { QStringLiteral("gpt-5-nano"), { QStringLiteral("gpt-5-nano"), 0.05, 0.005, 0.4 } },
    };
    return catalog;
}

const QHash<QString, QString>& modelAliases() {
    static const QHash<QString, QString> aliases{
        { QStringLiteral("gpt-5.6"), QStringLiteral("gpt-5.6-sol") },
        { QStringLiteral("gpt-5.3-codex-spark"), QStringLiteral("gpt-5.3-codex") },
    };
    return aliases;
}

} // namespace

QString normalizeModel(QString model) {
    model = model.trimmed().toLower();
    const auto paren = model.indexOf(QStringLiteral(" ("));
    if (paren > 0) {
        model = model.left(paren);
    }
    return model;
}

std::optional<ModelPricing> pricingForModel(const QString& rawModel) {
    const QString model = normalizeModel(rawModel);
    const auto& catalog = pricingCatalog();
    const auto direct = catalog.constFind(model);
    if (direct != catalog.constEnd()) {
        return direct.value();
    }

    const auto& aliases = modelAliases();
    const auto alias = aliases.constFind(model);
    if (alias == aliases.constEnd()) {
        return std::nullopt;
    }

    auto pricing = catalog.value(alias.value());
    pricing.mapped = true;
    return pricing;
}

qreal calculateCost(const ModelPricing& pricing, quint64 input, quint64 cachedInput, quint64 output) {
    const quint64 uncachedInput = input > cachedInput ? input - cachedInput : 0;
    const qreal cachedRate = pricing.hasCachedInput ? pricing.cachedInput : pricing.input;
    return (static_cast<qreal>(uncachedInput) * pricing.input + static_cast<qreal>(cachedInput) * cachedRate +
               static_cast<qreal>(output) * pricing.output) /
           kPerMillion;
}

} // namespace caelestia::services::codexpricing
