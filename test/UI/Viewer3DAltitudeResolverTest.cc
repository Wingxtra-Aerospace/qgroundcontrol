/****************************************************************************
 *
 * (c) 2009-2026 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#include "Viewer3DAltitudeResolverTest.h"

#include <QtCore/QFile>
#include <QtQml/QJSEngine>
#include <QtQml/QJSValue>
#include <QtTest/QTest>

#include <cmath>
#include <limits>

namespace {

constexpr double kEpsilon = 1e-6;

bool fuzzyEqual(double lhs, double rhs, double epsilon = kEpsilon)
{
    return std::fabs(lhs - rhs) <= epsilon;
}

bool loadAltitudeResolver(QJSEngine &engine, QString &errorMessage)
{
    QFile resolverSource(QStringLiteral(":/streaming3d/altitudeResolver.js"));
    if (!resolverSource.open(QIODevice::ReadOnly | QIODevice::Text)) {
        errorMessage = QStringLiteral("Could not open altitudeResolver.js from qrc.");
        return false;
    }

    const QString script = QString::fromUtf8(resolverSource.readAll());
    const QJSValue evaluationResult = engine.evaluate(script, QStringLiteral("altitudeResolver.js"));
    if (evaluationResult.isError()) {
        errorMessage = QStringLiteral("JS evaluate error at line %1: %2")
            .arg(evaluationResult.property(QStringLiteral("lineNumber")).toInt())
            .arg(evaluationResult.toString());
        return false;
    }

    const QJSValue resolver = engine.globalObject().property(QStringLiteral("__qgcAltitudeResolver"));
    if (!resolver.isObject()) {
        errorMessage = QStringLiteral("__qgcAltitudeResolver object was not created.");
        return false;
    }

    const QJSValue resolveFn = resolver.property(QStringLiteral("resolveAltitudeMetrics"));
    if (!resolveFn.isCallable()) {
        errorMessage = QStringLiteral("resolveAltitudeMetrics function is missing.");
        return false;
    }

    return true;
}

QJSValue resolveAltitudeMetrics(
    QJSEngine &engine,
    double altitudeAmsl,
    double altitudeRelative,
    double homeAltitudeAmsl,
    double terrainAltitudeAmsl,
    double mismatchToleranceMeters = 20.0)
{
    const QJSValue resolver = engine.globalObject().property(QStringLiteral("__qgcAltitudeResolver"));
    const QJSValue resolveFn = resolver.property(QStringLiteral("resolveAltitudeMetrics"));

    QJSValue input = engine.newObject();
    input.setProperty(QStringLiteral("altitudeAmsl"), altitudeAmsl);
    input.setProperty(QStringLiteral("altitudeRelative"), altitudeRelative);
    input.setProperty(QStringLiteral("homeAltitudeAmsl"), homeAltitudeAmsl);
    input.setProperty(QStringLiteral("terrainAltitudeAmsl"), terrainAltitudeAmsl);
    input.setProperty(QStringLiteral("mismatchToleranceMeters"), mismatchToleranceMeters);

    return resolveFn.call(QList<QJSValue>{input});
}

}

void Viewer3DAltitudeResolverTest::init()
{
    UnitTest::init();
}

void Viewer3DAltitudeResolverTest::cleanup()
{
    UnitTest::cleanup();
}

void Viewer3DAltitudeResolverTest::_testConsistentAmslAndRelative()
{
    QJSEngine engine;
    QString errorMessage;
    QVERIFY2(loadAltitudeResolver(engine, errorMessage), qPrintable(errorMessage));

    const QJSValue metrics = resolveAltitudeMetrics(
        engine,
        604.1,  // altitudeAmsl
        20.0,   // altitudeRelative
        584.1,  // homeAltitudeAmsl
        588.5   // terrainAltitudeAmsl
    );
    QVERIFY(metrics.isObject());

    QCOMPARE(metrics.property(QStringLiteral("source")).toString(), QStringLiteral("amsl_terrain"));
    QVERIFY(fuzzyEqual(metrics.property(QStringLiteral("aglMeters")).toNumber(), 15.6));
    QVERIFY(fuzzyEqual(metrics.property(QStringLiteral("amslMeters")).toNumber(), 604.1));
    QVERIFY(fuzzyEqual(metrics.property(QStringLiteral("relativeMeters")).toNumber(), 20.0));
    QVERIFY(fuzzyEqual(metrics.property(QStringLiteral("homeAmslMeters")).toNumber(), 584.1));
}

void Viewer3DAltitudeResolverTest::_testMismatchPrefersRelativeTerrain()
{
    QJSEngine engine;
    QString errorMessage;
    QVERIFY2(loadAltitudeResolver(engine, errorMessage), qPrintable(errorMessage));

    const QJSValue metrics = resolveAltitudeMetrics(
        engine,
        640.0,  // deliberately inconsistent AMSL
        20.0,
        584.1,
        588.5
    );
    QVERIFY(metrics.isObject());

    QCOMPARE(metrics.property(QStringLiteral("source")).toString(), QStringLiteral("relative_terrain"));
    QVERIFY(fuzzyEqual(metrics.property(QStringLiteral("aglMeters")).toNumber(), 15.6));
    QVERIFY(fuzzyEqual(metrics.property(QStringLiteral("relativeMeters")).toNumber(), 20.0));
}

void Viewer3DAltitudeResolverTest::_testFallbackSources()
{
    const double nan = std::numeric_limits<double>::quiet_NaN();

    QJSEngine engine;
    QString errorMessage;
    QVERIFY2(loadAltitudeResolver(engine, errorMessage), qPrintable(errorMessage));

    const QJSValue relativeFallback = resolveAltitudeMetrics(
        engine,
        nan,    // no AMSL
        12.0,   // relative available
        580.0,
        nan     // no terrain
    );
    QVERIFY(relativeFallback.isObject());
    QCOMPARE(relativeFallback.property(QStringLiteral("source")).toString(), QStringLiteral("relative"));
    QVERIFY(fuzzyEqual(relativeFallback.property(QStringLiteral("aglMeters")).toNumber(), 12.0));

    const QJSValue amslHomeFallback = resolveAltitudeMetrics(
        engine,
        604.1,  // AMSL available
        nan,    // no relative
        584.1,  // home available
        nan     // no terrain
    );
    QVERIFY(amslHomeFallback.isObject());
    QCOMPARE(amslHomeFallback.property(QStringLiteral("source")).toString(), QStringLiteral("amsl_home"));
    QVERIFY(fuzzyEqual(amslHomeFallback.property(QStringLiteral("aglMeters")).toNumber(), 20.0));

    const QJSValue zeroFallback = resolveAltitudeMetrics(
        engine,
        nan,
        nan,
        nan,
        nan
    );
    QVERIFY(zeroFallback.isObject());
    QCOMPARE(zeroFallback.property(QStringLiteral("source")).toString(), QStringLiteral("fallback_zero"));
    QVERIFY(fuzzyEqual(zeroFallback.property(QStringLiteral("aglMeters")).toNumber(), 0.0));
}

void Viewer3DAltitudeResolverTest::_testPerVehicleHomeIsolation()
{
    const double nan = std::numeric_limits<double>::quiet_NaN();

    QJSEngine engine;
    QString errorMessage;
    QVERIFY2(loadAltitudeResolver(engine, errorMessage), qPrintable(errorMessage));

    const QJSValue vehicleAMetrics = resolveAltitudeMetrics(
        engine,
        604.1,  // shared AMSL
        nan,    // force home-based fallback
        584.1,  // vehicle A home
        nan
    );
    const QJSValue vehicleBMetrics = resolveAltitudeMetrics(
        engine,
        604.1,  // shared AMSL
        nan,    // force home-based fallback
        577.4,  // vehicle B home
        nan
    );

    QVERIFY(vehicleAMetrics.isObject());
    QVERIFY(vehicleBMetrics.isObject());
    QCOMPARE(vehicleAMetrics.property(QStringLiteral("source")).toString(), QStringLiteral("amsl_home"));
    QCOMPARE(vehicleBMetrics.property(QStringLiteral("source")).toString(), QStringLiteral("amsl_home"));

    const double vehicleAAgl = vehicleAMetrics.property(QStringLiteral("aglMeters")).toNumber();
    const double vehicleBAgl = vehicleBMetrics.property(QStringLiteral("aglMeters")).toNumber();
    QVERIFY(fuzzyEqual(vehicleAAgl, 20.0));
    QVERIFY(fuzzyEqual(vehicleBAgl, 26.7));
    QVERIFY(!fuzzyEqual(vehicleAAgl, vehicleBAgl));
}
