#include "codexpricing.hpp"

#include <cmath>
#include <iostream>

namespace {

using caelestia::services::codexpricing::calculateCost;
using caelestia::services::codexpricing::pricingForModel;

bool expect(bool condition, const char* message) {
    if (condition) {
        return true;
    }

    std::cerr << "FAIL: " << message << '\n';
    return false;
}

bool fuzzyEqual(qreal actual, qreal expected) {
    return std::abs(actual - expected) < 0.000'001;
}

} // namespace

int main() {
    bool ok = true;

    const auto sol = pricingForModel(QStringLiteral("gpt-5.6-sol"));
    ok &= expect(sol.has_value(), "GPT-5.6 Sol is priced");
    if (sol.has_value()) {
        ok &= expect(sol->pricedModel == QStringLiteral("gpt-5.6-sol"), "Sol keeps its canonical model ID");
        ok &= expect(fuzzyEqual(sol->input, 5.0), "Sol input price is $5/MTok");
        ok &= expect(fuzzyEqual(sol->cachedInput, 0.5), "Sol cached input price is $0.50/MTok");
        ok &= expect(fuzzyEqual(sol->output, 30.0), "Sol output price is $30/MTok");
    }

    const auto terra = pricingForModel(QStringLiteral("GPT-5.6-Terra (xhigh)"));
    ok &= expect(terra.has_value(), "decorated GPT-5.6 Terra model IDs are normalized");
    if (terra.has_value()) {
        ok &= expect(fuzzyEqual(terra->input, 2.5), "Terra input price is $2.50/MTok");
        ok &= expect(fuzzyEqual(terra->cachedInput, 0.25), "Terra cached input price is $0.25/MTok");
        ok &= expect(fuzzyEqual(terra->output, 15.0), "Terra output price is $15/MTok");
    }

    const auto luna = pricingForModel(QStringLiteral("gpt-5.6-luna"));
    ok &= expect(luna.has_value(), "GPT-5.6 Luna is priced");
    if (luna.has_value()) {
        ok &= expect(fuzzyEqual(luna->input, 1.0), "Luna input price is $1/MTok");
        ok &= expect(fuzzyEqual(luna->cachedInput, 0.1), "Luna cached input price is $0.10/MTok");
        ok &= expect(fuzzyEqual(luna->output, 6.0), "Luna output price is $6/MTok");
    }

    const auto latestAlias = pricingForModel(QStringLiteral("gpt-5.6"));
    ok &= expect(latestAlias.has_value(), "GPT-5.6 alias is priced");
    if (latestAlias.has_value()) {
        ok &= expect(latestAlias->pricedModel == QStringLiteral("gpt-5.6-sol"), "GPT-5.6 alias maps to Sol");
        ok &= expect(latestAlias->mapped, "GPT-5.6 alias is marked as mapped");
    }

    const auto spark = pricingForModel(QStringLiteral("gpt-5.3-codex-spark"));
    ok &= expect(spark.has_value(), "Codex Spark remains priced through its comparison model");
    if (spark.has_value()) {
        ok &= expect(spark->pricedModel == QStringLiteral("gpt-5.3-codex"), "Codex Spark maps to GPT-5.3-Codex");
    }

    ok &= expect(!pricingForModel(QStringLiteral("codex-auto-review")).has_value(), "unpublished models remain unpriced");

    if (sol.has_value()) {
        const qreal cost = calculateCost(*sol, 2'000'000, 500'000, 100'000);
        ok &= expect(fuzzyEqual(cost, 10.75), "cached input is subtracted from full-rate input");
    }

    return ok ? 0 : 1;
}
