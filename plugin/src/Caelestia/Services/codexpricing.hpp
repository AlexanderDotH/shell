#pragma once

#include <optional>
#include <qstring.h>
#include <qtypes.h>

namespace caelestia::services::codexpricing {

struct ModelPricing {
    QString pricedModel;
    qreal input = 0.0;
    qreal cachedInput = 0.0;
    qreal output = 0.0;
    bool hasCachedInput = true;
    bool mapped = false;
};

[[nodiscard]] QString normalizeModel(QString model);
[[nodiscard]] std::optional<ModelPricing> pricingForModel(const QString& rawModel);
[[nodiscard]] qreal calculateCost(const ModelPricing& pricing, quint64 input, quint64 cachedInput, quint64 output);

} // namespace caelestia::services::codexpricing
