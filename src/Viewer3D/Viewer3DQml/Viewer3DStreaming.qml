import QGroundControl
import QGroundControl.Controllers
import QtQuick
import QtQuick.Controls
import QtPositioning
import QtWebEngine

Item {
    id: root

    property bool _isLoading: true
    property string _errorText: ""
    property bool viewerOpen: false
    property var missionController: null
    property var _viewer3DSettings: QGroundControl.settingsManager.viewer3DSettings
    property var _streamingMapTokenFact: _viewer3DSettings ? _viewer3DSettings.streamingProviderToken : null
    property var _vehicleAltitudeBiasFact: _viewer3DSettings ? _viewer3DSettings.vehicleAltitudeBias : null
    property var _missionVisualItems: missionController ? missionController.visualItems : null
    property var _multiVehicleManager: QGroundControl.multiVehicleManager
    property var _vehiclesModel: _multiVehicleManager ? _multiVehicleManager.vehicles : null
    property var _activeVehicle: _multiVehicleManager ? _multiVehicleManager.activeVehicle : null
    property var _activeVehicleHeadingFact: _activeVehicle && _activeVehicle.heading ? _activeVehicle.heading : null
    property var _activeVehicleAltitudeAmslFact: _activeVehicle && _activeVehicle.altitudeAMSL ? _activeVehicle.altitudeAMSL : null
    property var _activeVehicleAltitudeRelativeFact: _activeVehicle && _activeVehicle.altitudeRelative ? _activeVehicle.altitudeRelative : null
    property bool _missionSyncPending: false
    property string _lastVehicleStatesJson: ""
    property bool _lastVehicleStateWasEmpty: false
    property bool followVehicleEnabled: false
    property bool autoPanEnabled: false
    property bool declutterEnabled: false
    property var _vehicleIconColorPalette: [
        "#F96442", // warm red-orange
        "#3CC1FE", // sky blue
        "#64DF72", // green
        "#FCC747", // amber
        "#C282FA", // violet
        "#26E0C9", // aqua
        "#FB86C3", // pink
        "#9CDF40"  // lime
    ]
    signal mapViewStatePolled(var mapViewState)

    function _stringValue(value) {
        if (value === undefined || value === null) {
            return "";
        }

        return String(value);
    }

    function _numberValue(value, fallbackValue) {
        const numericValue = Number(value);
        if (!isFinite(numericValue)) {
            return fallbackValue;
        }
        return numericValue;
    }

    function _finiteOrNaN(value) {
        const numericValue = Number(value);
        return isFinite(numericValue) ? numericValue : Number.NaN;
    }

    function _pushStreamingConfigToPage() {
        if (!webView || webView.loading) {
            return;
        }

        const config = {
            token: _stringValue(_streamingMapTokenFact ? _streamingMapTokenFact.rawValue : "")
        };

        const script =
            "window.__qgcStreaming3DConfig = " + JSON.stringify(config) + ";" +
            "if (typeof window.__qgcApplyStreaming3DConfig === 'function') {" +
            "window.__qgcApplyStreaming3DConfig(window.__qgcStreaming3DConfig);" +
            "}";

        webView.runJavaScript(script);
    }

    function _clampZoom(zoomValue) {
        const zoom = Number(zoomValue);
        if (!isFinite(zoom)) {
            return 2.0;
        }
        return Math.max(2.0, Math.min(20.0, zoom));
    }

    function _mapViewStateFrom2DMap() {
        const coordinate = QGroundControl.flightMapPosition;
        if (!coordinate || !coordinate.isValid) {
            return null;
        }

        return {
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            zoom: _clampZoom(QGroundControl.flightMapZoom)
        };
    }

    function _vehicleKeyForVehicle(vehicle, indexHint) {
        if (vehicle && isFinite(Number(vehicle.id))) {
            return String(Number(vehicle.id));
        }
        if (isFinite(Number(indexHint))) {
            return "idx-" + String(Number(indexHint));
        }
        return "unknown";
    }

    function _vehicleIconColorForId(vehicleId) {
        const key = String(vehicleId === undefined || vehicleId === null ? "active" : vehicleId)
        let hash = 0
        for (let i = 0; i < key.length; i++) {
            hash = ((hash * 31) + key.charCodeAt(i)) >>> 0
        }

        const palette = _vehicleIconColorPalette
        if (!palette || palette.length === 0) {
            return "#FFFFFF"
        }
        return palette[hash % palette.length]
    }

    function _isSameVehicleRef(lhsVehicle, rhsVehicle) {
        if (!lhsVehicle || !rhsVehicle) {
            return false;
        }
        if (lhsVehicle === rhsVehicle) {
            return true;
        }

        const lhsId = _finiteOrNaN(lhsVehicle.id);
        const rhsId = _finiteOrNaN(rhsVehicle.id);
        return isFinite(lhsId) && isFinite(rhsId) && (lhsId === rhsId);
    }

    function _homeAltitudeAmslForVehicle(vehicle, vehicleMissionController) {
        if (vehicle && vehicle.homePosition && vehicle.homePosition.isValid) {
            return _finiteOrNaN(vehicle.homePosition.altitude);
        }

        if (vehicleMissionController &&
                vehicleMissionController.plannedHomePosition &&
                vehicleMissionController.plannedHomePosition.isValid) {
            return _finiteOrNaN(vehicleMissionController.plannedHomePosition.altitude);
        }

        const missionControllerMatchesVehicle = _isSameVehicleRef(vehicle, _activeVehicle);
        if (missionControllerMatchesVehicle &&
                missionController &&
                missionController.plannedHomePosition &&
                missionController.plannedHomePosition.isValid) {
            return _finiteOrNaN(missionController.plannedHomePosition.altitude);
        }

        return 0;
    }

    function _homeCoordinateForTakeoffForVehicle(vehicle, vehicleMissionController) {
        if (vehicle && vehicle.homePosition && vehicle.homePosition.isValid) {
            return vehicle.homePosition;
        }

        if (vehicleMissionController &&
                vehicleMissionController.plannedHomePosition &&
                vehicleMissionController.plannedHomePosition.isValid) {
            return vehicleMissionController.plannedHomePosition;
        }

        const missionControllerMatchesVehicle = _isSameVehicleRef(vehicle, _activeVehicle);
        if (missionControllerMatchesVehicle &&
                missionController &&
                missionController.plannedHomePosition &&
                missionController.plannedHomePosition.isValid) {
            return missionController.plannedHomePosition;
        }

        if (vehicle && vehicle.coordinate && vehicle.coordinate.isValid) {
            return vehicle.coordinate;
        }

        return null;
    }

    function _vehicleStateFromVehicle(vehicle, vehicleMissionController, indexHint) {
        if (!vehicle) {
            return null;
        }

        const vehicleCoordinate = vehicle.coordinate;
        if (!vehicleCoordinate || !vehicleCoordinate.isValid) {
            return null;
        }

        const headingFact = vehicle.heading;
        const headingValue = headingFact ? headingFact.value : Number.NaN;
        const altitudeAmslFactValue = vehicle.altitudeAMSL ? vehicle.altitudeAMSL.rawValue : Number.NaN;
        const altitudeRelativeFactValue = vehicle.altitudeRelative ? vehicle.altitudeRelative.rawValue : Number.NaN;
        const coordinateAltitude = vehicleCoordinate ? vehicleCoordinate.altitude : Number.NaN;

        const altitudeAmsl = isFinite(_numberValue(altitudeAmslFactValue, Number.NaN))
            ? _numberValue(altitudeAmslFactValue, Number.NaN)
            : _numberValue(coordinateAltitude, Number.NaN);

        const vehicleKey = _vehicleKeyForVehicle(vehicle, indexHint)
        return {
            id: vehicleKey,
            latitude: _numberValue(vehicleCoordinate.latitude, Number.NaN),
            longitude: _numberValue(vehicleCoordinate.longitude, Number.NaN),
            heading: _numberValue(headingValue, 0),
            iconSource: "/qmlimages/vehicleArrowOpaque.svg",
            iconColor: _vehicleIconColorForId(vehicleKey),
            altitudeAmsl: altitudeAmsl,
            altitudeRelative: _numberValue(altitudeRelativeFactValue, Number.NaN),
            homeAltitudeAmsl: _homeAltitudeAmslForVehicle(vehicle, vehicleMissionController)
        };
    }

    function _homeAltitudeAmsl() {
        return _homeAltitudeAmslForVehicle(_activeVehicle, missionController);
    }

    function _vehicleStateFromActiveVehicle() {
        return _vehicleStateFromVehicle(_activeVehicle, missionController, 0);
    }

    function _allVehicleStates() {
        const states = [];
        const repeaterCount = vehicleMissionControllersRepeater ? Number(vehicleMissionControllersRepeater.count) : 0;
        if (isFinite(repeaterCount) && repeaterCount > 0) {
            for (let i = 0; i < repeaterCount; i++) {
                const controllerEntry = vehicleMissionControllersRepeater.itemAt(i);
                if (!controllerEntry) {
                    continue;
                }

                const vehicle = controllerEntry._vehicle
                    ? controllerEntry._vehicle
                    : (_vehiclesModel && _vehiclesModel.get ? _vehiclesModel.get(i) : null);
                if (!vehicle) {
                    continue;
                }

                const vehicleMissionController = controllerEntry._missionController;
                const state = _vehicleStateFromVehicle(vehicle, vehicleMissionController, i);
                if (!state ||
                        !isFinite(state.latitude) ||
                        !isFinite(state.longitude)) {
                    continue;
                }
                states.push(state);
            }
            if (states.length > 0) {
                return states;
            }
        }

        const vehicles = _vehiclesModel;
        if (!vehicles || !isFinite(Number(vehicles.count))) {
            return states;
        }

        for (let i = 0; i < vehicles.count; i++) {
            const vehicle = vehicles.get(i);
            if (!vehicle) {
                continue;
            }

            const state = _vehicleStateFromVehicle(vehicle, null, i);
            if (!state ||
                    !isFinite(state.latitude) ||
                    !isFinite(state.longitude)) {
                continue;
            }
            states.push(state);
        }

        return states;
    }

    function _altitudeModeToFrameType(altitudeMode) {
        const mode = Number(altitudeMode);
        if (!isFinite(mode)) {
            return "AMSL";
        }

        if (mode === Number(QGroundControl.AltitudeModeAbsolute)) {
            return "AMSL";
        }
        if (mode === Number(QGroundControl.AltitudeModeRelative)) {
            return "RELATIVE";
        }
        if (mode === Number(QGroundControl.AltitudeModeTerrainFrame)) {
            return "AGL";
        }
        if (mode === Number(QGroundControl.AltitudeModeCalcAboveTerrain)) {
            return "AGL";
        }

        return "AMSL";
    }

    function _waypointAltitudeInfo(item, homeAmsl) {
        const terrainAltitudeAmsl = _finiteOrNaN(item ? item.terrainAltitude : Number.NaN);
        const amslEntryAltitude = _finiteOrNaN(item ? item.amslEntryAlt : Number.NaN);
        const altitudeMode = _finiteOrNaN(item ? item.altitudeMode : Number.NaN);
        const rawAltitude = _finiteOrNaN(item && item.altitude ? item.altitude.rawValue : Number.NaN);
        const hasTerrain = isFinite(terrainAltitudeAmsl);
        const safeHomeAmsl = isFinite(homeAmsl) ? homeAmsl : 0;

        let frameType = _altitudeModeToFrameType(altitudeMode);
        let altitudeAmsl = Number.NaN;
        let validTerrain = hasTerrain;

        // amslEntryAlt is QGC's authoritative altitude conversion for each VisualMissionItem.
        // It already handles command-specific and mode-specific altitude semantics.
        if (isFinite(amslEntryAltitude)) {
            altitudeAmsl = amslEntryAltitude;
        }

        if (!isFinite(altitudeAmsl) && isFinite(altitudeMode) && isFinite(rawAltitude)) {
            if (altitudeMode === Number(QGroundControl.AltitudeModeAbsolute)) {
                altitudeAmsl = rawAltitude;
            } else if (altitudeMode === Number(QGroundControl.AltitudeModeRelative)) {
                altitudeAmsl = safeHomeAmsl + rawAltitude;
            } else if (altitudeMode === Number(QGroundControl.AltitudeModeTerrainFrame)) {
                if (hasTerrain) {
                    altitudeAmsl = terrainAltitudeAmsl + rawAltitude;
                } else {
                    // Terrain is unavailable: keep rendering stable with a home-relative fallback.
                    altitudeAmsl = safeHomeAmsl + rawAltitude;
                    validTerrain = false;
                }
            } else if (altitudeMode === Number(QGroundControl.AltitudeModeCalcAboveTerrain)) {
                // "Calc Above Terrain" stores AMSL in mission item param7 once terrain resolves.
                // If we only have the UI fact value, treat it as an above-terrain input fallback.
                if (hasTerrain) {
                    altitudeAmsl = terrainAltitudeAmsl + rawAltitude;
                } else {
                    altitudeAmsl = safeHomeAmsl + rawAltitude;
                    validTerrain = false;
                }
            }
        }

        if (!isFinite(altitudeAmsl) && isFinite(rawAltitude)) {
            if (frameType === "AMSL") {
                altitudeAmsl = rawAltitude;
            } else {
                altitudeAmsl = safeHomeAmsl + rawAltitude;
                frameType = "RELATIVE";
            }
        }

        return {
            frameType: frameType,
            inputAltitude: rawAltitude,
            altitudeAmsl: altitudeAmsl,
            groundAltitudeAmsl: hasTerrain ? terrainAltitudeAmsl : Number.NaN,
            validTerrain: validTerrain
        };
    }

    function _missionLabel(item, visualIndex) {
        if (item && item.homePosition === true) {
            return "H";
        }

        if (item && item.abbreviation !== undefined && item.abbreviation !== null && String(item.abbreviation).length > 0) {
            return String(item.abbreviation);
        }

        if (item && isFinite(Number(item.sequenceNumber))) {
            return String(Number(item.sequenceNumber));
        }

        return String(visualIndex + 1);
    }

    function _homeCoordinateForTakeoff() {
        return _homeCoordinateForTakeoffForVehicle(_activeVehicle, missionController);
    }

    function _coordinateForMissionItem(item, homeCoordinate, allowTakeoffHomeFallback) {
        if (!item) {
            return null;
        }

        if (item.specifiesCoordinate === true && item.coordinate && item.coordinate.isValid) {
            return item.coordinate;
        }

        // Some takeoff commands in QGC are altitude-only (no explicit lat/lon).
        // Render them in 3D at home coordinate so takeoff climb is visible.
        if (allowTakeoffHomeFallback &&
                item.isTakeoffItem === true &&
                homeCoordinate &&
                homeCoordinate.isValid) {
            return homeCoordinate;
        }

        return null;
    }

    function _missionHasExplicitCoordinateWaypoint(visualItems) {
        if (!visualItems || !isFinite(Number(visualItems.count))) {
            return false;
        }

        for (let i = 0; i < visualItems.count; i++) {
            const item = visualItems.get(i);
            if (!item || item.homePosition === true) {
                continue;
            }

            if (item.specifiesCoordinate === true &&
                    item.coordinate &&
                    item.coordinate.isValid === true) {
                return true;
            }
        }

        return false;
    }

    function _hasUploadedMissionItems(vehicleMissionController) {
        if (!vehicleMissionController) {
            return false;
        }

        const missionItemCount = Number(vehicleMissionController.missionItemCount);
        return isFinite(missionItemCount) && missionItemCount > 0;
    }

    function _directionArrowsFromModel(directionArrowsModel, altitudeBiasMeters) {
        const arrows = [];
        if (!directionArrowsModel || !isFinite(Number(directionArrowsModel.count))) {
            return arrows;
        }

        for (let i = 0; i < directionArrowsModel.count; i++) {
            const segment = directionArrowsModel.get(i);
            if (!segment) {
                continue;
            }

            const coord1 = segment.coordinate1;
            const coord2 = segment.coordinate2;
            if (!coord1 || !coord1.isValid || !coord2 || !coord2.isValid) {
                continue;
            }

            const coord1Latitude = _finiteOrNaN(coord1.latitude);
            const coord1Longitude = _finiteOrNaN(coord1.longitude);
            const coord2Latitude = _finiteOrNaN(coord2.latitude);
            const coord2Longitude = _finiteOrNaN(coord2.longitude);
            if (!isFinite(coord1Latitude) ||
                    !isFinite(coord1Longitude) ||
                    !isFinite(coord2Latitude) ||
                    !isFinite(coord2Longitude)) {
                continue;
            }

            const coord1AmslAlt = _finiteOrNaN(segment.coord1AMSLAlt);
            const coord2AmslAlt = _finiteOrNaN(segment.coord2AMSLAlt);
            const bias = isFinite(altitudeBiasMeters) ? altitudeBiasMeters : 0;

            arrows.push({
                coord1Latitude: coord1Latitude,
                coord1Longitude: coord1Longitude,
                coord2Latitude: coord2Latitude,
                coord2Longitude: coord2Longitude,
                coord1AltitudeAmsl: isFinite(coord1AmslAlt) ? coord1AmslAlt + bias : Number.NaN,
                coord2AltitudeAmsl: isFinite(coord2AmslAlt) ? coord2AmslAlt + bias : Number.NaN
            });
        }

        return arrows;
    }

    function _coordinatesClose(lat1, lon1, lat2, lon2, toleranceDegrees) {
        const tol = isFinite(Number(toleranceDegrees)) ? Math.max(0, Number(toleranceDegrees)) : 0.00001;
        return Math.abs(Number(lat1) - Number(lat2)) <= tol &&
            Math.abs(Number(lon1) - Number(lon2)) <= tol;
    }

    function _directionArrowExists(directionArrows, startLat, startLon, endLat, endLon) {
        if (!directionArrows || !isFinite(Number(directionArrows.length))) {
            return false;
        }

        for (let i = 0; i < directionArrows.length; i++) {
            const arrow = directionArrows[i];
            if (!arrow) {
                continue;
            }
            const startMatches = _coordinatesClose(
                arrow.coord1Latitude,
                arrow.coord1Longitude,
                startLat,
                startLon,
                0.00002
            );
            const endMatches = _coordinatesClose(
                arrow.coord2Latitude,
                arrow.coord2Longitude,
                endLat,
                endLon,
                0.00002
            );
            if (startMatches && endMatches) {
                return true;
            }
        }

        return false;
    }

    function _missionDataFromVisualItems(visualItems, homeAmsl, homeCoordinate, altitudeBiasMeters, vehicleId, directionArrowsModel, hasUploadedMissionItems) {
        const waypoints = [];
        const directionArrows = _directionArrowsFromModel(directionArrowsModel, altitudeBiasMeters);
        const allowTakeoffHomeFallback =
            _missionHasExplicitCoordinateWaypoint(visualItems) ||
            (hasUploadedMissionItems === true);
        const rtlCommand = 20; // MAV_CMD_NAV_RETURN_TO_LAUNCH
        let foundRTL = false;
        let linkEndToHome = false;
        let lastRouteWaypoint = null;

        if (!visualItems || !isFinite(Number(visualItems.count))) {
            return {
                vehicleId: _stringValue(vehicleId),
                altitudeBiasMeters: isFinite(altitudeBiasMeters) ? altitudeBiasMeters : 0,
                homeAltitudeAmsl: homeAmsl,
                waypoints: waypoints,
                directionArrows: directionArrows
            };
        }

        for (let i = 0; i < visualItems.count; i++) {
            const item = visualItems.get(i);
            if (!item) {
                continue;
            }

            if (item.isSimpleItem === true) {
                const command = _finiteOrNaN(item.command);
                if (isFinite(command) && command === rtlCommand) {
                    linkEndToHome = true;
                    foundRTL = true;
                }
            }

            // Match 2D mission line behavior: stop route at RTL and then add one return segment to home.
            if (foundRTL) {
                break;
            }

            if (item.homePosition === true) {
                // Do not include synthetic planned-home vertex in 3D mission route geometry.
                // This prevents WP1/takeoff from being forced to ground altitude.
                continue;
            }

            const coordinate = _coordinateForMissionItem(item, homeCoordinate, allowTakeoffHomeFallback);
            if (!coordinate || coordinate.isValid !== true) {
                continue;
            }

            const latitude = _finiteOrNaN(coordinate.latitude);
            const longitude = _finiteOrNaN(coordinate.longitude);
            if (!isFinite(latitude) || !isFinite(longitude)) {
                continue;
            }

            const altitudeInfo = _waypointAltitudeInfo(item, homeAmsl);
            if (!isFinite(altitudeInfo.altitudeAmsl)) {
                continue;
            }

            waypoints.push({
                visualIndex: i,
                sequenceNumber: isFinite(Number(item.sequenceNumber)) ? Number(item.sequenceNumber) : i,
                label: _missionLabel(item, i),
                latitude: latitude,
                longitude: longitude,
                altitudeInputMeters: altitudeInfo.inputAltitude,
                altitudeAmsl: altitudeInfo.altitudeAmsl,
                altitudeAMSL_m: altitudeInfo.altitudeAmsl,
                groundAltitudeAmsl: altitudeInfo.groundAltitudeAmsl,
                groundAMSL_m: altitudeInfo.groundAltitudeAmsl,
                frameType: altitudeInfo.frameType,
                validTerrain: altitudeInfo.validTerrain
            });
            lastRouteWaypoint = waypoints[waypoints.length - 1];
        }

        if (linkEndToHome &&
                lastRouteWaypoint &&
                homeCoordinate &&
                homeCoordinate.isValid === true) {
            const homeLatitude = _finiteOrNaN(homeCoordinate.latitude);
            const homeLongitude = _finiteOrNaN(homeCoordinate.longitude);
            const homeGroundAmsl = _finiteOrNaN(homeCoordinate.altitude);
            const returnAltitudeAmsl = isFinite(lastRouteWaypoint.altitudeAmsl)
                ? lastRouteWaypoint.altitudeAmsl
                : (isFinite(homeAmsl) ? homeAmsl : Number.NaN);

            if (isFinite(homeLatitude) && isFinite(homeLongitude) && isFinite(returnAltitudeAmsl)) {
                waypoints.push({
                    visualIndex: visualItems.count,
                    sequenceNumber: isFinite(lastRouteWaypoint.sequenceNumber) ? (lastRouteWaypoint.sequenceNumber + 1) : visualItems.count,
                    label: "H",
                    latitude: homeLatitude,
                    longitude: homeLongitude,
                    altitudeInputMeters: Number.NaN,
                    altitudeAmsl: returnAltitudeAmsl,
                    altitudeAMSL_m: returnAltitudeAmsl,
                    groundAltitudeAmsl: homeGroundAmsl,
                    groundAMSL_m: homeGroundAmsl,
                    frameType: "AMSL",
                    validTerrain: false,
                    syntheticReturnHome: true
                });

                // 2D always shows direction guidance on the final route segment.
                // Ensure 3D has the same arrow segment (last waypoint -> home) even if model data lags.
                if (!_directionArrowExists(
                            directionArrows,
                            lastRouteWaypoint.latitude,
                            lastRouteWaypoint.longitude,
                            homeLatitude,
                            homeLongitude)) {
                    const bias = isFinite(altitudeBiasMeters) ? altitudeBiasMeters : 0;
                    directionArrows.push({
                        coord1Latitude: lastRouteWaypoint.latitude,
                        coord1Longitude: lastRouteWaypoint.longitude,
                        coord2Latitude: homeLatitude,
                        coord2Longitude: homeLongitude,
                        coord1AltitudeAmsl: isFinite(lastRouteWaypoint.altitudeAmsl)
                            ? (lastRouteWaypoint.altitudeAmsl + bias)
                            : Number.NaN,
                        coord2AltitudeAmsl: returnAltitudeAmsl + bias
                    });
                }
            }
        }

        return {
            vehicleId: _stringValue(vehicleId),
            altitudeBiasMeters: isFinite(altitudeBiasMeters) ? altitudeBiasMeters : 0,
            homeAltitudeAmsl: homeAmsl,
            waypoints: waypoints,
            directionArrows: directionArrows
        };
    }

    function _missionDataFromController(vehicle, vehicleMissionController, indexHint) {
        const altitudeBiasMeters = _finiteOrNaN(_vehicleAltitudeBiasFact ? _vehicleAltitudeBiasFact.rawValue : 0);
        const controllerToUse = vehicleMissionController ? vehicleMissionController : null;
        const hasUploadedMissionItems = _hasUploadedMissionItems(controllerToUse);
        const vehicleId = _vehicleKeyForVehicle(vehicle, indexHint);
        if (!controllerToUse) {
            return {
                vehicleId: _stringValue(vehicleId),
                altitudeBiasMeters: isFinite(altitudeBiasMeters) ? altitudeBiasMeters : 0,
                homeAltitudeAmsl: _homeAltitudeAmslForVehicle(vehicle, missionController),
                waypoints: [],
                directionArrows: []
            };
        }

        const visualItems = controllerToUse ? controllerToUse.visualItems : null;
        const homeAmsl = _homeAltitudeAmslForVehicle(vehicle, controllerToUse);
        const homeCoordinate = _homeCoordinateForTakeoffForVehicle(vehicle, controllerToUse);

        return _missionDataFromVisualItems(
            visualItems,
            homeAmsl,
            homeCoordinate,
            altitudeBiasMeters,
            vehicleId,
            controllerToUse ? controllerToUse.directionArrows : null,
            hasUploadedMissionItems
        );
    }

    function _allMissionData() {
        const missions = [];

        const repeaterCount = vehicleMissionControllersRepeater ? Number(vehicleMissionControllersRepeater.count) : 0;
        if (isFinite(repeaterCount) && repeaterCount > 0) {
            for (let i = 0; i < repeaterCount; i++) {
                const controllerEntry = vehicleMissionControllersRepeater.itemAt(i);
                if (!controllerEntry) {
                    continue;
                }

                const vehicle = controllerEntry._vehicle
                    ? controllerEntry._vehicle
                    : (_vehiclesModel && _vehiclesModel.get ? _vehiclesModel.get(i) : null);
                if (!vehicle) {
                    continue;
                }

                const vehicleMissionController = controllerEntry._missionController;
                const missionData = _missionDataFromController(vehicle, vehicleMissionController, i);
                missions.push(missionData);
            }
            return missions;
        }

        return missions;
    }

    function _pushMapViewToPage() {
        if (!webView || webView.loading) {
            return;
        }

        const mapViewState = _mapViewStateFrom2DMap();
        if (!mapViewState) {
            return;
        }

        const script =
            "window.__qgcMapViewState = " + JSON.stringify(mapViewState) + ";" +
            "if (typeof window.__qgcSetMapViewState === 'function') {" +
            "window.__qgcSetMapViewState(window.__qgcMapViewState);" +
            "}";

        webView.runJavaScript(script);
    }

    function _pushVehicleStateToPage() {
        if (!webView || webView.loading) {
            return;
        }

        const vehicleStates = _allVehicleStates();
        if (!vehicleStates || vehicleStates.length === 0) {
            if (_lastVehicleStateWasEmpty) {
                return;
            }
            _lastVehicleStateWasEmpty = true;
            _lastVehicleStatesJson = "[]";
            webView.runJavaScript(
                "window.__qgcVehiclesState = [];" +
                "window.__qgcVehicleState = null;" +
                "if (typeof window.__qgcSetVehiclesState === 'function') {" +
                "window.__qgcSetVehiclesState(window.__qgcVehiclesState);" +
                "}" +
                "if (typeof window.__qgcClearVehicleState === 'function') {" +
                "window.__qgcClearVehicleState();" +
                "}"
            );
            return;
        }

        const vehiclesStateJson = JSON.stringify(vehicleStates);
        if (vehiclesStateJson === _lastVehicleStatesJson) {
            return;
        }

        _lastVehicleStatesJson = vehiclesStateJson;
        _lastVehicleStateWasEmpty = false;
        const script =
            "window.__qgcVehiclesState = " + vehiclesStateJson + ";" +
            "window.__qgcVehicleState = window.__qgcVehiclesState[0] || null;" +
            "if (typeof window.__qgcSetVehiclesState === 'function') {" +
            "window.__qgcSetVehiclesState(window.__qgcVehiclesState);" +
            "} else if (typeof window.__qgcSetVehicleState === 'function') {" +
            "window.__qgcSetVehicleState(window.__qgcVehicleState);" +
            "}";

        webView.runJavaScript(script);
    }

    function _centerMapOnActiveVehicle() {
        if (!webView || webView.loading) {
            return;
        }

        const activeVehicleState = _vehicleStateFromActiveVehicle();
        if (!activeVehicleState ||
                !isFinite(Number(activeVehicleState.latitude)) ||
                !isFinite(Number(activeVehicleState.longitude))) {
            return;
        }

        const centerRequest = {
            id: _stringValue(activeVehicleState.id),
            latitude: Number(activeVehicleState.latitude),
            longitude: Number(activeVehicleState.longitude)
        };

        const script =
            "if (typeof window.__qgcCenterOnVehicle === 'function') {" +
            "window.__qgcCenterOnVehicle(" + JSON.stringify(centerRequest) + ");" +
            "}";
        webView.runJavaScript(script);
    }

    function _pushMissionDataToPage() {
        if (!webView || webView.loading) {
            return;
        }

        const missionsData = _allMissionData();
        const script =
            "window.__qgcMissionsData = " + JSON.stringify(missionsData) + ";" +
            "window.__qgcMissionData = window.__qgcMissionsData.length > 0 ? window.__qgcMissionsData[0] : null;" +
            "if (typeof window.__qgcSetMissionsData === 'function') {" +
            "window.__qgcSetMissionsData(window.__qgcMissionsData);" +
            "} else if (typeof window.__qgcSetMissionData === 'function') {" +
            "window.__qgcSetMissionData(window.__qgcMissionData);" +
            "}";
        webView.runJavaScript(script);
    }

    function _pushFollowStateToPage() {
        if (!webView || webView.loading) {
            return;
        }

        const followEnabled = followVehicleEnabled === true;
        const script =
            "if (typeof window.__qgcSetFollowVehicleEnabled === 'function') {" +
            "window.__qgcSetFollowVehicleEnabled(" + (followEnabled ? "true" : "false") + ");" +
            "}";
        webView.runJavaScript(script);
    }

    function _pushAutoPanStateToPage() {
        if (!webView || webView.loading) {
            return;
        }

        const autoPanState = autoPanEnabled === true;
        const script =
            "if (typeof window.__qgcSetAutoPanEnabled === 'function') {" +
            "window.__qgcSetAutoPanEnabled(" + (autoPanState ? "true" : "false") + ");" +
            "}";
        webView.runJavaScript(script);
    }

    function _pushDeclutterStateToPage() {
        if (!webView || webView.loading) {
            return;
        }

        const declutterState = declutterEnabled === true;
        const script =
            "if (typeof window.__qgcSetDeclutterEnabled === 'function') {" +
            "window.__qgcSetDeclutterEnabled(" + (declutterState ? "true" : "false") + ");" +
            "}";
        webView.runJavaScript(script);
    }

    function _pushViewControlStateToPage() {
        _pushFollowStateToPage();
        _pushAutoPanStateToPage();
        _pushDeclutterStateToPage();
    }

    function _scheduleMissionSync() {
        if (_missionSyncPending) {
            return;
        }

        _missionSyncPending = true;
        missionSyncTimer.restart();
    }

    function syncFrom2DMapTo3D() {
        _pushMapViewToPage();
        _pushVehicleStateToPage();
        _scheduleMissionSync();
    }

    function getScaleLineMeters(scaleLinePixelLength, yPixel, onDone) {
        if (!webView || webView.loading) {
            if (onDone) {
                onDone(Number.NaN);
            }
            return false;
        }

        const pixelLength = Number(scaleLinePixelLength);
        const pixelY = Number(yPixel);
        if (!isFinite(pixelLength) || pixelLength <= 0 || !isFinite(pixelY)) {
            if (onDone) {
                onDone(Number.NaN);
            }
            return false;
        }

        const script =
            "(function() {" +
            "if (typeof window.__qgcGetScaleLineMeters !== 'function') { return null; }" +
            "return window.__qgcGetScaleLineMeters(" + pixelLength.toFixed(4) + ", " + pixelY.toFixed(4) + ");" +
            "})();";

        webView.runJavaScript(script, function(result) {
            const meters = Number(result);
            if (onDone) {
                onDone(isFinite(meters) ? meters : Number.NaN);
            }
        });
        return true;
    }

    function setZoomLevel(zoomValue) {
        if (!webView || webView.loading) {
            return false;
        }

        const targetZoom = _clampZoom(zoomValue);
        const script =
            "(function() {" +
            "var getMapViewState = (typeof window.__qgcGetStableMapViewState === 'function') ? window.__qgcGetStableMapViewState : window.__qgcGetMapViewState;" +
            "if (typeof getMapViewState !== 'function' || typeof window.__qgcSetMapViewState !== 'function') { return false; }" +
            "var currentState = getMapViewState();" +
            "if (!currentState || !isFinite(Number(currentState.latitude)) || !isFinite(Number(currentState.longitude))) { return false; }" +
            "return window.__qgcSetMapViewState({" +
            "latitude: Number(currentState.latitude)," +
            "longitude: Number(currentState.longitude)," +
            "zoom: " + Number(targetZoom).toFixed(4) +
            "});" +
            "})();";

        webView.runJavaScript(script);
        return true;
    }

    function _pollCurrentMapViewState() {
        if (!viewerOpen || !webView || webView.loading) {
            return;
        }

        const script =
            "(function() {" +
            "if (typeof window.__qgcGetStableMapViewState === 'function') { return window.__qgcGetStableMapViewState(); }" +
            "if (typeof window.__qgcGetMapViewState === 'function') { return window.__qgcGetMapViewState(); }" +
            "return null;" +
            "})();";

        webView.runJavaScript(script, function(result) {
            if (result === undefined || result === null) {
                return;
            }

            const latitude = Number(result.latitude);
            const longitude = Number(result.longitude);
            const zoom = _clampZoom(Number(result.zoom));
            if (!isFinite(latitude) || !isFinite(longitude) || !isFinite(zoom)) {
                return;
            }

            root.mapViewStatePolled({
                latitude: latitude,
                longitude: longitude,
                zoom: zoom
            });
        });
    }

    function activate() {
        if (!webView) {
            return;
        }

        webView.forceActiveFocus();
        _pushVehicleStateToPage();
        _pushMissionDataToPage();
        _scheduleMissionSync();
        webView.runJavaScript(
            "if (typeof window.__qgcOnViewerActivated === 'function') {" +
            "window.__qgcOnViewerActivated();" +
            "}"
        );
    }

    function setFollowVehicleEnabled(enabled) {
        followVehicleEnabled = (enabled === true);
        return true;
    }

    function setAutoPanEnabled(enabled) {
        autoPanEnabled = (enabled === true);
        return true;
    }

    function setDeclutterEnabled(enabled) {
        declutterEnabled = (enabled === true);
        return true;
    }

    function centerOnActiveVehicle() {
        _centerMapOnActiveVehicle();
        return true;
    }

    function syncFrom3DTo2DMap(onDone) {
        if (!webView || webView.loading) {
            if (onDone) {
                onDone(false);
            }
            return;
        }

        webView.runJavaScript(
            "(function() {" +
            "var interacted = (typeof window.__qgcConsumeMapViewStateIfInteracted === 'function') ? window.__qgcConsumeMapViewStateIfInteracted() : null;" +
            "if (interacted) { return interacted; }" +
            "if (typeof window.__qgcGetStableMapViewState === 'function') { return window.__qgcGetStableMapViewState(); }" +
            "if (typeof window.__qgcGetMapViewState === 'function') { return window.__qgcGetMapViewState(); }" +
            "return null;" +
            "})();",
            function(result) {
                let synced = false;

                if (result !== undefined && result !== null &&
                        isFinite(Number(result.latitude)) &&
                        isFinite(Number(result.longitude))) {
                    const latitude = Number(result.latitude);
                    const longitude = Number(result.longitude);
                    const zoom = _clampZoom(Number(result.zoom));

                    QGroundControl.flightMapPosition = QtPositioning.coordinate(latitude, longitude);
                    QGroundControl.flightMapZoom = zoom;
                    synced = true;
                }

                if (onDone) {
                    onDone(synced);
                }
            }
        );
    }

    WebEngineView {
        id: webView
        anchors.fill: parent
        visible: _errorText.length === 0
        url: "qrc:/streaming3d/index.html"

        settings.localContentCanAccessRemoteUrls: true
        settings.localContentCanAccessFileUrls: true
        settings.webGLEnabled: true
        focus: root.viewerOpen

        onJavaScriptConsoleMessage: function(level, message, lineNumber, sourceID) {
            const text = String(message || "");
            if (text.indexOf("PERFORMANCE WARNING: Attribute 0 is disabled") !== -1 ||
                    text.indexOf("WebGL: too many errors, no more errors will be reported") !== -1) {
                return;
            }

            if (level === WebEngineView.ErrorMessageLevel) {
                console.error(text);
            } else if (level === WebEngineView.WarningMessageLevel) {
                console.warn(text);
            } else {
                console.log(text);
            }
        }

        onLoadingChanged: function(loadRequest) {
            if (loadRequest.status === WebEngineView.LoadStartedStatus) {
                root._isLoading = true;
                root._errorText = "";
                root._lastVehicleStatesJson = "";
                root._lastVehicleStateWasEmpty = false;
            } else if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                root._isLoading = false;
                root._pushStreamingConfigToPage();
                root._pushMapViewToPage();
                root._pushViewControlStateToPage();
                root._pushVehicleStateToPage();
                root._scheduleMissionSync();
                if (root.viewerOpen) {
                    root.activate();
                }
            } else if (loadRequest.status === WebEngineView.LoadFailedStatus) {
                root._isLoading = false;
                root._errorText = qsTr("Could not load streamed 3D map content. Check internet connectivity and try again.");
            }
        }

        onRenderProcessTerminated: function(terminationStatus, exitCode) {
            root._isLoading = false;
            root._errorText = qsTr("3D web rendering could not initialize. Please restart QGroundControl.");
        }
    }

    onVisibleChanged: {
        if (visible && viewerOpen) {
            _pushViewControlStateToPage();
            _pushVehicleStateToPage();
            _scheduleMissionSync();
            activate();
        }
    }

    onFollowVehicleEnabledChanged: {
        _pushFollowStateToPage();
        if (followVehicleEnabled) {
            _centerMapOnActiveVehicle();
        }
    }

    onAutoPanEnabledChanged: {
        _pushAutoPanStateToPage();
    }

    onDeclutterEnabledChanged: {
        _pushDeclutterStateToPage();
    }

    Timer {
        id: mapViewStatePollTimer
        interval: 300
        repeat: true
        running: root.viewerOpen && !webView.loading && (root._errorText.length === 0)
        onTriggered: root._pollCurrentMapViewState()
    }

    onMissionControllerChanged: {
        _scheduleMissionSync();
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 12
        width: loadingRow.implicitWidth + 20
        height: loadingRow.implicitHeight + 12
        radius: 6
        color: "#AA202020"
        visible: root._isLoading && (root._errorText.length === 0)
        z: 1000

        Row {
            id: loadingRow
            anchors.centerIn: parent
            spacing: 8

            BusyIndicator {
                width: 18
                height: 18
                running: true
            }

            Label {
                text: qsTr("Loading 3D map...")
                color: "white"
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#99000000"
        visible: root._errorText.length > 0
        z: 1100

        Label {
            anchors.centerIn: parent
            width: parent.width * 0.7
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: "white"
            text: root._errorText
        }
    }

    Connections {
        target: root._streamingMapTokenFact
        ignoreUnknownSignals: true

        function onRawValueChanged() {
            root._pushStreamingConfigToPage();
        }

        function onValueChanged() {
            root._pushStreamingConfigToPage();
        }
    }

    Timer {
        id: vehicleStateUpdateTimer
        interval: 120
        repeat: true
        running: root.viewerOpen && !root._isLoading && (root._errorText.length === 0)
        onTriggered: root._pushVehicleStateToPage()
    }

    Timer {
        id: missionSyncTimer
        interval: 90
        repeat: false
        onTriggered: {
            root._missionSyncPending = false;
            root._pushMissionDataToPage();
        }
    }

    Connections {
        target: root._multiVehicleManager
        ignoreUnknownSignals: true

        function onActiveVehicleChanged() {
            root._pushVehicleStateToPage();
            root._centerMapOnActiveVehicle();
            root._scheduleMissionSync();
        }

        function onActiveVehicleAvailableChanged() {
            root._pushVehicleStateToPage();
            root._scheduleMissionSync();
        }

        function onVehicleAdded() {
            root._pushVehicleStateToPage();
            root._scheduleMissionSync();
        }

        function onVehicleRemoved() {
            root._pushVehicleStateToPage();
            root._scheduleMissionSync();
        }
    }

    Repeater {
        id: vehicleMissionControllersRepeater
        model: root._vehiclesModel
        onItemAdded: function(_index, _item) {
            root._pushVehicleStateToPage();
            root._scheduleMissionSync();
        }
        onItemRemoved: function(_index, _item) {
            root._pushVehicleStateToPage();
            root._scheduleMissionSync();
        }

        Item {
            width: 0
            height: 0
            visible: false

            // Match FlyViewMap pattern: QmlObjectListModel delegates expose `object`.
            property var _vehicle: (typeof object !== "undefined" && object !== null)
                ? object
                : ((typeof modelData !== "undefined") ? modelData : null)
            property var _missionController: _planController ? _planController.missionController : null
            property bool _controllerStarted: false
            property string _boundVehicleKey: ""

            function _vehicleBindingKey(vehicleValue) {
                return root._vehicleKeyForVehicle(vehicleValue, index);
            }

            function _controllerNeedsRebind() {
                if (!_vehicle || !_planController) {
                    return true;
                }

                const managerVehicle = _planController.managerVehicle;
                if (!managerVehicle) {
                    return true;
                }

                return _vehicleBindingKey(managerVehicle) !== _vehicleBindingKey(_vehicle);
            }

            function _startVehicleControllerIfReady() {
                if (!_vehicle || !_planController) {
                    return;
                }

                if (!_controllerNeedsRebind() &&
                        _controllerStarted &&
                        _boundVehicleKey === _vehicleBindingKey(_vehicle)) {
                    return;
                }

                _planController.startStaticActiveVehicle(_vehicle);
                _controllerStarted = true;
                _boundVehicleKey = _vehicleBindingKey(_vehicle);
                root._scheduleMissionSync();
            }

            PlanMasterController {
                id: _planController
                Component.onCompleted: _startVehicleControllerIfReady()
            }

            Timer {
                interval: 120
                repeat: true
                running: _controllerNeedsRebind()
                onTriggered: _startVehicleControllerIfReady()
            }

            Connections {
                target: _planController
                ignoreUnknownSignals: true

                function onManagerVehicleChanged() {
                    root._scheduleMissionSync();
                    _startVehicleControllerIfReady();
                }
            }

            Connections {
                target: _missionController
                ignoreUnknownSignals: true

                function onVisualItemsChanged() {
                    root._scheduleMissionSync();
                }

                function onPlannedHomePositionChanged() {
                    root._scheduleMissionSync();
                }
            }

            Repeater {
                model: _missionController ? _missionController.visualItems : null

                Item {
                    width: 0
                    height: 0
                    visible: false

                    property var _missionItem: (typeof object !== "undefined") ? object : null

                    Connections {
                        target: _missionItem
                        ignoreUnknownSignals: true

                        function onCoordinateChanged() {
                            root._scheduleMissionSync();
                        }

                        function onAmslEntryAltChanged() {
                            root._scheduleMissionSync();
                        }

                        function onTerrainAltitudeChanged() {
                            root._scheduleMissionSync();
                        }

                        function onAltitudeModeChanged() {
                            root._scheduleMissionSync();
                        }

                        function onSequenceNumberChanged() {
                            root._scheduleMissionSync();
                        }

                        function onSpecifiesCoordinateChanged() {
                            root._scheduleMissionSync();
                        }
                    }

                    Connections {
                        target: (_missionItem && _missionItem.altitude) ? _missionItem.altitude : null
                        ignoreUnknownSignals: true

                        function onRawValueChanged() {
                            root._scheduleMissionSync();
                        }

                        function onValueChanged() {
                            root._scheduleMissionSync();
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: root._activeVehicle
        ignoreUnknownSignals: true

        function onCoordinateChanged() {
            root._pushVehicleStateToPage();
        }

        function onVehicleImageOpaqueChanged() {
            root._pushVehicleStateToPage();
        }
    }

    Connections {
        target: root._activeVehicleHeadingFact
        ignoreUnknownSignals: true

        function onValueChanged() {
            root._pushVehicleStateToPage();
        }

        function onRawValueChanged() {
            root._pushVehicleStateToPage();
        }
    }

    Connections {
        target: root._activeVehicleAltitudeAmslFact
        ignoreUnknownSignals: true

        function onValueChanged() {
            root._pushVehicleStateToPage();
        }

        function onRawValueChanged() {
            root._pushVehicleStateToPage();
        }
    }

    Connections {
        target: root._activeVehicleAltitudeRelativeFact
        ignoreUnknownSignals: true

        function onValueChanged() {
            root._pushVehicleStateToPage();
        }

        function onRawValueChanged() {
            root._pushVehicleStateToPage();
        }
    }

    Connections {
        target: root.missionController
        ignoreUnknownSignals: true

        function onVisualItemsChanged() {
            root._scheduleMissionSync();
        }

        function onPlannedHomePositionChanged() {
            root._scheduleMissionSync();
        }
    }

    Connections {
        target: root._vehicleAltitudeBiasFact
        ignoreUnknownSignals: true

        function onRawValueChanged() {
            root._scheduleMissionSync();
        }

        function onValueChanged() {
            root._scheduleMissionSync();
        }
    }

    Repeater {
        model: root._missionVisualItems

        Item {
            width: 0
            height: 0
            visible: false

            property var _missionItem: (typeof object !== "undefined") ? object : null

            Connections {
                target: _missionItem
                ignoreUnknownSignals: true

                function onCoordinateChanged() {
                    root._scheduleMissionSync();
                }

                function onAmslEntryAltChanged() {
                    root._scheduleMissionSync();
                }

                function onTerrainAltitudeChanged() {
                    root._scheduleMissionSync();
                }

                function onAltitudeModeChanged() {
                    root._scheduleMissionSync();
                }

                function onSequenceNumberChanged() {
                    root._scheduleMissionSync();
                }

                function onSpecifiesCoordinateChanged() {
                    root._scheduleMissionSync();
                }
            }

            Connections {
                target: (_missionItem && _missionItem.altitude) ? _missionItem.altitude : null
                ignoreUnknownSignals: true

                function onRawValueChanged() {
                    root._scheduleMissionSync();
                }

                function onValueChanged() {
                    root._scheduleMissionSync();
                }
            }
        }
    }

}
