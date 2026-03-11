/****************************************************************************
 *
 * (c) 2009-2026 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#pragma once

#include "UnitTest.h"

class Viewer3DAltitudeResolverTest : public UnitTest
{
    Q_OBJECT

public:
    Viewer3DAltitudeResolverTest() = default;

private slots:
    void init() override;
    void cleanup() override;

    void _testConsistentAmslAndRelative();
    void _testMismatchPrefersRelativeTerrain();
    void _testFallbackSources();
    void _testPerVehicleHomeIsolation();
};
