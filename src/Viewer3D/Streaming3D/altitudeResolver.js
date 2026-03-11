(function (root, factory) {
    if (typeof module === "object" && typeof module.exports === "object") {
        module.exports = factory();
        return;
    }

    root.__qgcAltitudeResolver = factory();
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
    const AltitudeSources = Object.freeze({
        unknown: "unknown",
        amslTerrain: "amsl_terrain",
        relativeTerrain: "relative_terrain",
        relative: "relative",
        amslHome: "amsl_home",
        fallbackZero: "fallback_zero"
    });

    function toFiniteNumber(value) {
        const numericValue = Number(value);
        return Number.isFinite(numericValue) ? numericValue : Number.NaN;
    }

    function resolveAltitudeMetrics(input) {
        const sourceInput = input || {};
        const altitudeAmsl = toFiniteNumber(sourceInput.altitudeAmsl);
        const altitudeRelative = toFiniteNumber(sourceInput.altitudeRelative);
        const homeAltitudeAmsl = toFiniteNumber(sourceInput.homeAltitudeAmsl);
        const terrainAltitudeAmsl = toFiniteNumber(sourceInput.terrainAltitudeAmsl);
        const mismatchToleranceMeters = Number.isFinite(Number(sourceInput.mismatchToleranceMeters))
            ? Math.max(0, Number(sourceInput.mismatchToleranceMeters))
            : 20.0;

        const hasAmsl = Number.isFinite(altitudeAmsl);
        const hasRelative = Number.isFinite(altitudeRelative);
        const hasHome = Number.isFinite(homeAltitudeAmsl);
        const hasTerrain = Number.isFinite(terrainAltitudeAmsl);

        const amslFromRelative = (hasRelative && hasHome)
            ? (homeAltitudeAmsl + altitudeRelative)
            : Number.NaN;
        const resolvedAmsl = hasAmsl
            ? altitudeAmsl
            : amslFromRelative;
        const resolvedRelative = hasRelative
            ? altitudeRelative
            : (Number.isFinite(resolvedAmsl) && hasHome
                ? (resolvedAmsl - homeAltitudeAmsl)
                : Number.NaN);

        let aglMeters = Number.NaN;
        let source = AltitudeSources.unknown;

        if (hasTerrain) {
            const aglFromAmsl = Number.isFinite(resolvedAmsl)
                ? (resolvedAmsl - terrainAltitudeAmsl)
                : Number.NaN;
            const aglFromRelative = Number.isFinite(amslFromRelative)
                ? (amslFromRelative - terrainAltitudeAmsl)
                : Number.NaN;

            if (Number.isFinite(aglFromAmsl) && Number.isFinite(aglFromRelative)) {
                if (Math.abs(aglFromAmsl - aglFromRelative) > mismatchToleranceMeters) {
                    aglMeters = aglFromRelative;
                    source = AltitudeSources.relativeTerrain;
                } else {
                    aglMeters = aglFromAmsl;
                    source = hasAmsl ? AltitudeSources.amslTerrain : AltitudeSources.relativeTerrain;
                }
            } else if (Number.isFinite(aglFromRelative)) {
                aglMeters = aglFromRelative;
                source = AltitudeSources.relativeTerrain;
            } else if (Number.isFinite(aglFromAmsl)) {
                aglMeters = aglFromAmsl;
                source = hasAmsl ? AltitudeSources.amslTerrain : AltitudeSources.relativeTerrain;
            }
        }

        if (!Number.isFinite(aglMeters)) {
            if (hasRelative) {
                aglMeters = altitudeRelative;
                source = AltitudeSources.relative;
            } else if (hasAmsl && hasHome) {
                aglMeters = altitudeAmsl - homeAltitudeAmsl;
                source = AltitudeSources.amslHome;
            } else {
                aglMeters = 0.0;
                source = AltitudeSources.fallbackZero;
            }
        }

        aglMeters = Math.max(0.0, aglMeters);

        return {
            aglMeters: aglMeters,
            amslMeters: Number.isFinite(resolvedAmsl) ? resolvedAmsl : Number.NaN,
            relativeMeters: Number.isFinite(resolvedRelative) ? resolvedRelative : Number.NaN,
            homeAmslMeters: hasHome ? homeAltitudeAmsl : Number.NaN,
            terrainAmslMeters: hasTerrain ? terrainAltitudeAmsl : Number.NaN,
            source: source
        };
    }

    return {
        AltitudeSources: AltitudeSources,
        toFiniteNumber: toFiniteNumber,
        resolveAltitudeMetrics: resolveAltitudeMetrics
    };
});
