(function () {
    const statusElement = document.getElementById("status");
    const homeButton = document.getElementById("home-button");

    function safeStringify(value) {
        const seen = new WeakSet();
        return JSON.stringify(value, function (key, nestedValue) {
            if (nestedValue instanceof Error) {
                return {
                    name: nestedValue.name,
                    message: nestedValue.message,
                    stack: nestedValue.stack
                };
            }
            if (nestedValue && typeof nestedValue === "object") {
                if (seen.has(nestedValue)) {
                    return "[Circular]";
                }
                seen.add(nestedValue);
            }
            return nestedValue;
        });
    }

    function formatConsoleArg(arg) {
        if (arg instanceof Error) {
            return arg.stack || arg.message || String(arg);
        }
        if (arg && typeof arg === "object") {
            try {
                const serialized = safeStringify(arg);
                if (serialized && serialized !== "{}") {
                    return serialized;
                }
            } catch (jsonError) {
                // Fall through.
            }
            return Object.prototype.toString.call(arg);
        }
        return String(arg);
    }

    let map = null;
    let mapLoaded = false;
    let mapInitializing = false;
    let streamingConfig = {
        token: ""
    };
    let activeStatusType = "";
    let pendingMapViewState = null;
    let pendingVehicleState = null;
    let pendingMissionData = null;
    let pendingCenterOnVehicleRequest = null;
    let followVehicleEnabled = false;
    let autoPanEnabled = false;
    let followVehicleId = "";
    let followTrackingSuppressUntilMs = 0;
    let autoPanTrackingSuppressUntilMs = 0;
    let interactionTrackingSuppressUntilMs = 0;
    let declutterEnabled = false;
    let defaultMapViewState = {
        latitude: 0.0,
        longitude: 0.0,
        zoom: 3.0
    };
    let hasUserInteractedSinceExternalSync = false;
    let isApplyingExternalMapView = false;
    let hasReceivedExternalConfig = false;
    let hasReceivedExternalMapView = false;
    let vehicleMarkers = new Map();
    let mission3DLayer = null;
    let missionLayerNeedsUpload = false;
    let missionLayerState = null;
    let missionDebugMarkers = [];
    let missionDirectionMarkers = [];
    let vehicleTrailHistories = new Map();
    let mapDeclutterLayerVisibilityCache = new Map();

    const MIN_MAP_ZOOM = 2.0;
    const MAX_MAP_ZOOM = 20.0;
    const DEFAULT_PITCH_DEGREES = 65.0;
    const DEFAULT_BEARING_DEGREES = 0.0;
    const DEFAULT_STYLE_URL = "mapbox://styles/mapbox/standard-satellite";
    const WHEEL_ZOOM_RATE = 1 / 1500;
    const TRACKPAD_ZOOM_RATE = 1 / 260;
    // Delay before follow mode re-centers after the last manual camera interaction.
    // Keep this short so manual override feels responsive without a long dead period.
    const FOLLOW_USER_PAN_HOLDOFF_MS = 2000;
    // Delay before auto-pan re-engages after manual interaction.
    const AUTO_PAN_USER_HOLDOFF_MS = 1200;
    // Vehicle should remain inside this inset in auto-pan mode.
    const AUTO_PAN_VIEWPORT_MARGIN_PX = 48;
    const AUTO_PAN_CENTER_DEADBAND_X_RATIO = 0.14;
    const AUTO_PAN_CENTER_DEADBAND_Y_RATIO = 0.12;
    // Ignore move/moveend events caused by programmatic recenter operations.
    const PROGRAMMATIC_MOVE_EVENT_SUPPRESS_MS = 180;
    const PROGRAMMATIC_EASE_MOVE_EVENT_SUPPRESS_MS = 620;
    const PAN_MAX_SPEED = 760;
    const PAN_DECELERATION = 9800;
    const ROTATE_MAX_SPEED = 210;
    const ROTATE_DECELERATION = 4800;
    // Keep terrain scale physically correct so mission altitude geometry remains true-to-meters.
    const TERRAIN_EXAGGERATION = 1.0;
    const ENABLE_ATMOSPHERIC_FOG = false;
    const BUILDING_LAYER_OPACITY = 0.6;
    const BUILDING_VECTOR_SOURCE_ID = "qgc-buildings-source";
    const BUILDING_VECTOR_SOURCE_URL = "mapbox://mapbox.mapbox-streets-v8";
    const BUILDING_GROWTH_START_ZOOM = 14.6;
    const BUILDING_GROWTH_END_ZOOM = 16.0;
    const BUILDING_GROWTH_CURVE = 1.6;
    const MISSING_TOKEN_MESSAGE = "Mapbox token is required for streamed 3D mode.";
    const DEFAULT_VEHICLE_ICON_SOURCE = "/qmlimages/vehicleArrowOpaque.svg";
    const DEFAULT_VEHICLE_ICON_COLOR = "#FFFFFF";
    const VEHICLE_MARKER_SIZE_PX = 56;
    const VEHICLE_ALTITUDE_MISMATCH_TOLERANCE_METERS = 20.0;
    const MISSION_3D_LAYER_ID = "qgc-mission-3d";
    // Matches QGroundControl.globalPalette.mapMissionTrajectory (#be781c).
    const MISSION_ROUTE_COLOR = [0.7451, 0.4706, 0.1098, 0.96];
    const MISSION_ALTITUDE_COLOR = [1.0, 1.0, 1.0, 0.96];
    const MISSION_ALTITUDE_FALLBACK_COLOR = [1.0, 1.0, 1.0, 0.62];
    const MISSION_TUBE_RADIAL_SEGMENTS = 12;
    const MISSION_POINT_SIZE_PX = 11.0;
    // Keep cylindrical mission lines at fixed world size (not zoom-dependent).
    const MISSION_LINE_DIAMETER_METERS = 1.224;
    const MISSION_LABEL_OFFSET_X_PX = 10;
    const MISSION_DIRECTION_ARROW_COLOR = "#ffffff";
    const MISSION_DIRECTION_ARROW_FRACTION = 0.75;
    const MISSION_ARROW_ROUTE_MATCH_TOLERANCE_METERS = 120.0;
    const MISSION_DIRECTION_CONE_LENGTH_METERS = 7.28;
    const MISSION_DIRECTION_CONE_RADIUS_METERS = 2.21;
    const MISSION_DIRECTION_CONE_RADIAL_SEGMENTS = 12;
    const MISSION_RTL_DASH_LENGTH_METERS = 6.0;
    const MISSION_RTL_DASH_GAP_METERS = 4.0;
    const VEHICLE_TRAIL_LINE_DIAMETER_METERS = 1.35;
    const VEHICLE_TRAIL_MAX_AGE_MS = 85000;
    const VEHICLE_TRAIL_MAX_POINTS = 300;
    const VEHICLE_TRAIL_MIN_HORIZONTAL_STEP_METERS = 0.7;
    const VEHICLE_TRAIL_MIN_VERTICAL_STEP_METERS = 0.45;
    const VEHICLE_TRAIL_COLOR_PALETTE = [
        [0.976, 0.392, 0.259, 0.95], // warm red-orange
        [0.235, 0.757, 0.996, 0.95], // sky blue
        [0.392, 0.875, 0.447, 0.95], // green
        [0.988, 0.780, 0.278, 0.95], // amber
        [0.761, 0.510, 0.980, 0.95], // violet
        [0.149, 0.878, 0.788, 0.95], // aqua
        [0.984, 0.525, 0.765, 0.95], // pink
        [0.612, 0.875, 0.251, 0.95]  // lime
    ];
    const VEHICLE_ICON_COLOR_PALETTE = [
        "#F96442", // warm red-orange
        "#3CC1FE", // sky blue
        "#64DF72", // green
        "#FCC747", // amber
        "#C282FA", // violet
        "#26E0C9", // aqua
        "#FB86C3", // pink
        "#9CDF40"  // lime
    ];
    const EARTH_CIRCUMFERENCE_METERS = 40075016.686;
    const GROUND_ATTACH_EPSILON_METERS = 0.12;

    function isNoisyWebGLWarning(message) {
        if (!message) {
            return false;
        }

        return message.indexOf("PERFORMANCE WARNING: Attribute 0 is disabled") !== -1 ||
            message.indexOf("WebGL: too many errors, no more errors will be reported") !== -1;
    }

    const originalConsoleError = console.error.bind(console);
    const originalConsoleWarn = console.warn.bind(console);
    console.error = function (...args) {
        originalConsoleError(args.map(formatConsoleArg).join(" | "));
    };
    console.warn = function (...args) {
        const line = args.map(formatConsoleArg).join(" | ");
        if (isNoisyWebGLWarning(line)) {
            return;
        }
        originalConsoleWarn(line);
    };

    function clampValue(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value));
    }

    function normalizeLongitude(longitude) {
        if (!Number.isFinite(longitude)) {
            return 0.0;
        }
        return (((longitude + 180.0) % 360.0) + 360.0) % 360.0 - 180.0;
    }

    function normalizeDeltaLongitude(longitudeDelta) {
        if (!Number.isFinite(longitudeDelta)) {
            return 0.0;
        }
        return (((longitudeDelta + 180.0) % 360.0) + 360.0) % 360.0 - 180.0;
    }

    function clampLatitude(latitude) {
        if (!Number.isFinite(latitude)) {
            return 0.0;
        }
        return clampValue(latitude, -85.0, 85.0);
    }

    function clampZoomLevel(zoom) {
        if (!Number.isFinite(zoom)) {
            return MIN_MAP_ZOOM;
        }
        return clampValue(zoom, MIN_MAP_ZOOM, MAX_MAP_ZOOM);
    }

    function metersToMercatorUnits(meters, latitude) {
        const clampedLatitude = clampValue(Number(latitude), -85.0, 85.0);
        const cosLatitude = Math.max(Math.cos((clampedLatitude * Math.PI) / 180.0), 1e-6);
        return Number(meters) / (EARTH_CIRCUMFERENCE_METERS * cosLatitude);
    }

    function matrixWithTranslation(matrix, tx, ty, tz) {
        const out = new Float32Array(16);
        out[0] = matrix[0];
        out[1] = matrix[1];
        out[2] = matrix[2];
        out[3] = matrix[3];
        out[4] = matrix[4];
        out[5] = matrix[5];
        out[6] = matrix[6];
        out[7] = matrix[7];
        out[8] = matrix[8];
        out[9] = matrix[9];
        out[10] = matrix[10];
        out[11] = matrix[11];
        out[12] = (matrix[0] * tx) + (matrix[4] * ty) + (matrix[8] * tz) + matrix[12];
        out[13] = (matrix[1] * tx) + (matrix[5] * ty) + (matrix[9] * tz) + matrix[13];
        out[14] = (matrix[2] * tx) + (matrix[6] * ty) + (matrix[10] * tz) + matrix[14];
        out[15] = (matrix[3] * tx) + (matrix[7] * ty) + (matrix[11] * tz) + matrix[15];
        return out;
    }

    function bearingDegrees(fromLatitude, fromLongitude, toLatitude, toLongitude) {
        const fromLatRad = (clampLatitude(fromLatitude) * Math.PI) / 180.0;
        const toLatRad = (clampLatitude(toLatitude) * Math.PI) / 180.0;
        const deltaLonRad = (normalizeDeltaLongitude(toLongitude - fromLongitude) * Math.PI) / 180.0;
        const y = Math.sin(deltaLonRad) * Math.cos(toLatRad);
        const x =
            Math.cos(fromLatRad) * Math.sin(toLatRad) -
            Math.sin(fromLatRad) * Math.cos(toLatRad) * Math.cos(deltaLonRad);
        if (!Number.isFinite(x) || !Number.isFinite(y) || (Math.abs(x) < 1e-10 && Math.abs(y) < 1e-10)) {
            return 0.0;
        }
        const brng = (Math.atan2(y, x) * 180.0) / Math.PI;
        return ((brng % 360.0) + 360.0) % 360.0;
    }

    function midpointLongitude(fromLongitude, toLongitude) {
        const start = normalizeLongitude(fromLongitude);
        const delta = normalizeDeltaLongitude(toLongitude - start);
        return normalizeLongitude(start + (delta * 0.5));
    }

    function interpolateGreatCircle(fromLatitude, fromLongitude, toLatitude, toLongitude, fraction) {
        const f = clampValue(Number(fraction), 0.0, 1.0);
        const lat1 = (clampLatitude(fromLatitude) * Math.PI) / 180.0;
        const lon1 = (normalizeLongitude(fromLongitude) * Math.PI) / 180.0;
        const lat2 = (clampLatitude(toLatitude) * Math.PI) / 180.0;
        const lon2 = (normalizeLongitude(toLongitude) * Math.PI) / 180.0;

        const sinHalfDeltaLat = Math.sin((lat2 - lat1) * 0.5);
        const sinHalfDeltaLon = Math.sin((lon2 - lon1) * 0.5);
        const haversine =
            sinHalfDeltaLat * sinHalfDeltaLat +
            Math.cos(lat1) * Math.cos(lat2) * sinHalfDeltaLon * sinHalfDeltaLon;
        const angularDistance = 2.0 * Math.asin(Math.min(1.0, Math.sqrt(Math.max(0.0, haversine))));

        if (!Number.isFinite(angularDistance) || angularDistance < 1e-9) {
            return {
                latitude: clampLatitude((fromLatitude + toLatitude) * 0.5),
                longitude: midpointLongitude(fromLongitude, toLongitude)
            };
        }

        const sinAngularDistance = Math.sin(angularDistance);
        if (Math.abs(sinAngularDistance) < 1e-12) {
            return {
                latitude: clampLatitude((fromLatitude + toLatitude) * 0.5),
                longitude: midpointLongitude(fromLongitude, toLongitude)
            };
        }

        const a = Math.sin((1.0 - f) * angularDistance) / sinAngularDistance;
        const b = Math.sin(f * angularDistance) / sinAngularDistance;

        const x = a * Math.cos(lat1) * Math.cos(lon1) + b * Math.cos(lat2) * Math.cos(lon2);
        const y = a * Math.cos(lat1) * Math.sin(lon1) + b * Math.cos(lat2) * Math.sin(lon2);
        const z = a * Math.sin(lat1) + b * Math.sin(lat2);

        const latitude = (Math.atan2(z, Math.sqrt((x * x) + (y * y))) * 180.0) / Math.PI;
        const longitude = (Math.atan2(y, x) * 180.0) / Math.PI;

        return {
            latitude: clampLatitude(latitude),
            longitude: normalizeLongitude(longitude)
        };
    }

    function greatCircleDistanceMeters(fromLatitude, fromLongitude, toLatitude, toLongitude) {
        const lat1 = (clampLatitude(fromLatitude) * Math.PI) / 180.0;
        const lat2 = (clampLatitude(toLatitude) * Math.PI) / 180.0;
        const dLat = lat2 - lat1;
        const dLon = (normalizeDeltaLongitude(toLongitude - fromLongitude) * Math.PI) / 180.0;
        const sinHalfLat = Math.sin(dLat * 0.5);
        const sinHalfLon = Math.sin(dLon * 0.5);
        const haversine =
            (sinHalfLat * sinHalfLat) +
            (Math.cos(lat1) * Math.cos(lat2) * sinHalfLon * sinHalfLon);
        const centralAngle = 2.0 * Math.asin(Math.min(1.0, Math.sqrt(Math.max(0.0, haversine))));
        const EARTH_RADIUS_METERS = 6371008.8;
        return EARTH_RADIUS_METERS * centralAngle;
    }

    function findBestRouteSegmentForArrow(routeSegments, arrowSegment) {
        if (!Array.isArray(routeSegments) || routeSegments.length === 0 || !arrowSegment) {
            return null;
        }

        let bestSegment = null;
        let bestScore = Number.POSITIVE_INFINITY;
        for (const segment of routeSegments) {
            if (!segment) {
                continue;
            }

            const startErrorMeters = greatCircleDistanceMeters(
                arrowSegment.coord1Latitude,
                arrowSegment.coord1Longitude,
                segment.startLatitude,
                segment.startLongitude
            );
            const endErrorMeters = greatCircleDistanceMeters(
                arrowSegment.coord2Latitude,
                arrowSegment.coord2Longitude,
                segment.endLatitude,
                segment.endLongitude
            );
            const score = startErrorMeters + endErrorMeters;
            if (score < bestScore) {
                bestScore = score;
                bestSegment = segment;
            }
        }

        if (!bestSegment || !Number.isFinite(bestScore)) {
            return null;
        }

        const maxAllowedScore = MISSION_ARROW_ROUTE_MATCH_TOLERANCE_METERS * 2.0;
        if (bestScore > maxAllowedScore) {
            return null;
        }

        return bestSegment;
    }

    function normalizeMapViewState(mapViewState) {
        if (!mapViewState) {
            return null;
        }

        const latitude = Number(mapViewState.latitude);
        const longitude = Number(mapViewState.longitude);
        const zoom = Number(mapViewState.zoom);
        if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || !Number.isFinite(zoom)) {
            return null;
        }

        return {
            latitude: clampLatitude(latitude),
            longitude: normalizeLongitude(longitude),
            zoom: clampZoomLevel(zoom)
        };
    }

    function normalizeConfig(config) {
        const tokenValue = config && config.token !== undefined && config.token !== null
            ? String(config.token).trim()
            : "";

        return {
            token: tokenValue
        };
    }

    function normalizeHeadingDegrees(headingDegrees) {
        const heading = Number(headingDegrees);
        if (!Number.isFinite(heading)) {
            return 0.0;
        }

        return ((heading % 360.0) + 360.0) % 360.0;
    }

    function toWebResourceUrl(resourcePath) {
        const normalizedPath = resourcePath !== undefined && resourcePath !== null
            ? String(resourcePath).trim()
            : "";
        if (!normalizedPath) {
            return DEFAULT_VEHICLE_ICON_SOURCE;
        }

        if (/^(https?:|data:|blob:|qrc:|file:)/i.test(normalizedPath)) {
            return normalizedPath;
        }

        if (normalizedPath.charAt(0) === "/") {
            return normalizedPath;
        }

        return "/" + normalizedPath;
    }

    function vehicleColorHash(vehicleId) {
        const key = String(vehicleId || "active");
        let hash = 0;
        for (let i = 0; i < key.length; i++) {
            hash = ((hash * 31) + key.charCodeAt(i)) >>> 0;
        }
        return hash >>> 0;
    }

    function vehicleIconColorForId(vehicleId) {
        const palette = VEHICLE_ICON_COLOR_PALETTE;
        if (!Array.isArray(palette) || palette.length === 0) {
            return DEFAULT_VEHICLE_ICON_COLOR;
        }
        return palette[vehicleColorHash(vehicleId) % palette.length];
    }

    function normalizeVehicleIconColor(iconColor, vehicleId) {
        const normalizedColor = iconColor !== undefined && iconColor !== null
            ? String(iconColor).trim()
            : "";
        return normalizedColor || vehicleIconColorForId(vehicleId);
    }

    function normalizeVehicleState(vehicleState) {
        if (!vehicleState) {
            return null;
        }

        const latitude = Number(vehicleState.latitude);
        const longitude = Number(vehicleState.longitude);
        if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
            return null;
        }

        const altitudeAmsl = Number(vehicleState.altitudeAmsl);
        const altitudeRelative = Number(vehicleState.altitudeRelative);
        const homeAltitudeAmsl = Number(vehicleState.homeAltitudeAmsl);
        const vehicleId = vehicleState.id !== undefined && vehicleState.id !== null
            ? String(vehicleState.id)
            : "active";

        return {
            id: vehicleId,
            latitude: clampLatitude(latitude),
            longitude: normalizeLongitude(longitude),
            heading: normalizeHeadingDegrees(vehicleState.heading),
            iconSource: toWebResourceUrl(vehicleState.iconSource),
            iconColor: normalizeVehicleIconColor(vehicleState.iconColor, vehicleId),
            altitudeAmsl: Number.isFinite(altitudeAmsl) ? altitudeAmsl : Number.NaN,
            altitudeRelative: Number.isFinite(altitudeRelative) ? altitudeRelative : Number.NaN,
            homeAltitudeAmsl: Number.isFinite(homeAltitudeAmsl) ? homeAltitudeAmsl : Number.NaN
        };
    }

    function normalizeVehiclesState(vehicleStates) {
        if (!Array.isArray(vehicleStates)) {
            return [];
        }

        const normalizedStates = [];
        for (const vehicleState of vehicleStates) {
            const normalized = normalizeVehicleState(vehicleState);
            if (normalized) {
                normalizedStates.push(normalized);
            }
        }
        return normalizedStates;
    }

    function normalizeVehicleCenterRequest(centerRequest) {
        if (centerRequest === undefined || centerRequest === null) {
            return null;
        }

        if (typeof centerRequest === "string" || typeof centerRequest === "number") {
            return {
                id: String(centerRequest),
                latitude: Number.NaN,
                longitude: Number.NaN,
                animate: true
            };
        }

        const id = centerRequest.id !== undefined && centerRequest.id !== null
            ? String(centerRequest.id)
            : "";
        const latitude = Number(centerRequest.latitude);
        const longitude = Number(centerRequest.longitude);
        const animate = centerRequest.animate === false ? false : true;

        return {
            id: id,
            latitude: Number.isFinite(latitude) ? clampLatitude(latitude) : Number.NaN,
            longitude: Number.isFinite(longitude) ? normalizeLongitude(longitude) : Number.NaN,
            animate: animate
        };
    }

    function findVehicleStateById(vehicleStates, vehicleId) {
        if (!Array.isArray(vehicleStates) || !vehicleId) {
            return null;
        }

        const targetId = String(vehicleId);
        for (const vehicleState of vehicleStates) {
            if (!vehicleState) {
                continue;
            }
            if (String(vehicleState.id || "") === targetId) {
                return vehicleState;
            }
        }
        return null;
    }

    function centerMapOnCoordinate(latitude, longitude, animate) {
        if (!map || !mapLoaded) {
            return false;
        }
        if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
            return false;
        }

        const zoom = Number.isFinite(map.getZoom()) ? map.getZoom() : defaultMapViewState.zoom;
        const pitch = Number.isFinite(map.getPitch()) ? map.getPitch() : DEFAULT_PITCH_DEGREES;
        const bearing = Number.isFinite(map.getBearing()) ? map.getBearing() : DEFAULT_BEARING_DEGREES;

        const targetOptions = {
            center: [normalizeLongitude(longitude), clampLatitude(latitude)],
            zoom: zoom,
            pitch: pitch,
            bearing: bearing
        };

        suppressInteractionTrackingTemporarily(
            animate === true
                ? PROGRAMMATIC_EASE_MOVE_EVENT_SUPPRESS_MS
                : PROGRAMMATIC_MOVE_EVENT_SUPPRESS_MS
        );
        isApplyingExternalMapView = true;
        try {
            if (animate === true && typeof map.easeTo === "function") {
                map.easeTo({
                    center: targetOptions.center,
                    zoom: targetOptions.zoom,
                    pitch: targetOptions.pitch,
                    bearing: targetOptions.bearing,
                    duration: 420,
                    essential: true
                });
            } else {
                map.jumpTo(targetOptions);
            }
        } finally {
            isApplyingExternalMapView = false;
        }

        map.triggerRepaint();
        return true;
    }

    function centerOnVehicle(centerRequest) {
        const normalizedRequest = normalizeVehicleCenterRequest(centerRequest);
        if (!normalizedRequest) {
            return false;
        }

        pendingCenterOnVehicleRequest = normalizedRequest;
        if (!map || !mapLoaded) {
            return false;
        }

        const normalizedStates = normalizeVehiclesState(
            window.__qgcVehiclesState ||
            pendingVehicleState ||
            (window.__qgcVehicleState ? [window.__qgcVehicleState] : [])
        );

        let focusLatitude = normalizedRequest.latitude;
        let focusLongitude = normalizedRequest.longitude;
        let targetVehicleId = normalizedRequest.id ? String(normalizedRequest.id) : "";

        if (normalizedRequest.id) {
            const matchedState = findVehicleStateById(normalizedStates, normalizedRequest.id);
            if (matchedState) {
                focusLatitude = matchedState.latitude;
                focusLongitude = matchedState.longitude;
                targetVehicleId = matchedState.id ? String(matchedState.id) : targetVehicleId;
            }
        }

        if (!Number.isFinite(focusLatitude) || !Number.isFinite(focusLongitude)) {
            const fallbackState = normalizedStates.length > 0 ? normalizedStates[0] : null;
            if (fallbackState) {
                focusLatitude = fallbackState.latitude;
                focusLongitude = fallbackState.longitude;
                if (!targetVehicleId && fallbackState.id) {
                    targetVehicleId = String(fallbackState.id);
                }
            }
        }

        if (!Number.isFinite(focusLatitude) || !Number.isFinite(focusLongitude)) {
            return false;
        }

        const centered = centerMapOnCoordinate(
            focusLatitude,
            focusLongitude,
            normalizedRequest.animate === true
        );
        if (centered) {
            pendingCenterOnVehicleRequest = null;
            if (targetVehicleId) {
                followVehicleId = targetVehicleId;
            }
        }
        return centered;
    }

    function isVehicleStateWithinViewport(vehicleState, viewportMarginPx) {
        if (!map || !mapLoaded || !vehicleState) {
            return true;
        }

        const latitude = Number(vehicleState.latitude);
        const longitude = Number(vehicleState.longitude);
        if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
            return true;
        }

        let projectedPoint = null;
        try {
            projectedPoint = map.project([longitude, latitude]);
        } catch (projectionError) {
            return true;
        }

        if (!projectedPoint ||
                !Number.isFinite(Number(projectedPoint.x)) ||
                !Number.isFinite(Number(projectedPoint.y))) {
            return true;
        }

        const canvas = map.getCanvas();
        const canvasWidth = canvas
            ? Number.isFinite(Number(canvas.clientWidth)) && Number(canvas.clientWidth) > 0
                ? Number(canvas.clientWidth)
                : Number(canvas.width)
            : Number.NaN;
        const canvasHeight = canvas
            ? Number.isFinite(Number(canvas.clientHeight)) && Number(canvas.clientHeight) > 0
                ? Number(canvas.clientHeight)
                : Number(canvas.height)
            : Number.NaN;

        if (!Number.isFinite(canvasWidth) || !Number.isFinite(canvasHeight) ||
                canvasWidth <= 0 || canvasHeight <= 0) {
            return true;
        }

        const maxMargin = Math.max(0, (Math.min(canvasWidth, canvasHeight) * 0.33));
        const margin = clampValue(Number(viewportMarginPx), 0, maxMargin);
        const x = Number(projectedPoint.x);
        const y = Number(projectedPoint.y);
        const withinViewportBounds = x >= margin &&
            x <= (canvasWidth - margin) &&
            y >= margin &&
            y <= (canvasHeight - margin);
        if (!withinViewportBounds) {
            return false;
        }

        const centerX = canvasWidth * 0.5;
        const centerY = canvasHeight * 0.5;
        const maxCenterOffsetX = Math.max(40, canvasWidth * AUTO_PAN_CENTER_DEADBAND_X_RATIO);
        const maxCenterOffsetY = Math.max(28, canvasHeight * AUTO_PAN_CENTER_DEADBAND_Y_RATIO);
        return Math.abs(x - centerX) <= maxCenterOffsetX &&
            Math.abs(y - centerY) <= maxCenterOffsetY;
    }

    function resolveVehicleAltitudeAboveGround(normalizedVehicleState) {
        if (!normalizedVehicleState) {
            return 0.0;
        }

        const terrainRenderedAmsl = sampleTerrainAltitudeAmsl(
            normalizedVehicleState.longitude,
            normalizedVehicleState.latitude,
            true
        );
        const hasAmsl = Number.isFinite(normalizedVehicleState.altitudeAmsl);
        const hasRelative = Number.isFinite(normalizedVehicleState.altitudeRelative);
        const hasHome = Number.isFinite(normalizedVehicleState.homeAltitudeAmsl);
        const hasTerrain = Number.isFinite(terrainRenderedAmsl);
        const amslFromRelative = (hasRelative && hasHome)
            ? (normalizedVehicleState.homeAltitudeAmsl + normalizedVehicleState.altitudeRelative)
            : Number.NaN;
        const aglFromAmsl = (hasAmsl && hasTerrain)
            ? (normalizedVehicleState.altitudeAmsl - terrainRenderedAmsl)
            : Number.NaN;
        const aglFromRelative = (Number.isFinite(amslFromRelative) && hasTerrain)
            ? (amslFromRelative - terrainRenderedAmsl)
            : Number.NaN;

        if (Number.isFinite(aglFromAmsl) && Number.isFinite(aglFromRelative)) {
            if (Math.abs(aglFromAmsl - aglFromRelative) > VEHICLE_ALTITUDE_MISMATCH_TOLERANCE_METERS) {
                return Math.max(0.0, aglFromRelative);
            }
            return Math.max(0.0, aglFromAmsl);
        }

        if (Number.isFinite(aglFromRelative)) {
            return Math.max(0.0, aglFromRelative);
        }

        if (Number.isFinite(aglFromAmsl)) {
            return Math.max(0.0, aglFromAmsl);
        }

        if (hasRelative) {
            return Math.max(0.0, normalizedVehicleState.altitudeRelative);
        }

        if (hasAmsl && hasHome) {
            return Math.max(0.0, normalizedVehicleState.altitudeAmsl - normalizedVehicleState.homeAltitudeAmsl);
        }

        return 0.0;
    }

    function normalizeMissionWaypoint(rawWaypoint) {
        if (!rawWaypoint) {
            return null;
        }

        const latitude = Number(rawWaypoint.latitude);
        const longitude = Number(rawWaypoint.longitude);
        const altitudeAmsl = Number(
            rawWaypoint.altitudeAmsl !== undefined ? rawWaypoint.altitudeAmsl : rawWaypoint.altitudeAMSL_m
        );
        const rawGroundAltitudeAmsl = Number(
            rawWaypoint.groundAltitudeAmsl !== undefined ? rawWaypoint.groundAltitudeAmsl : rawWaypoint.groundAMSL_m
        );
        const groundAltitudeAmsl = Number.isFinite(rawGroundAltitudeAmsl) ? rawGroundAltitudeAmsl : Number.NaN;
        const inputAltitudeMeters = Number(
            rawWaypoint.altitudeInputMeters !== undefined ? rawWaypoint.altitudeInputMeters : rawWaypoint.inputAltitudeMeters
        );
        if (!Number.isFinite(latitude) ||
                !Number.isFinite(longitude) ||
                !Number.isFinite(altitudeAmsl)) {
            return null;
        }

        const rawFrameType = rawWaypoint.frameType !== undefined && rawWaypoint.frameType !== null
            ? String(rawWaypoint.frameType).toUpperCase()
            : "AMSL";
        const frameType = rawFrameType === "RELATIVE" || rawFrameType === "AGL"
            ? rawFrameType
            : "AMSL";

        return {
            visualIndex: Number.isFinite(Number(rawWaypoint.visualIndex)) ? Number(rawWaypoint.visualIndex) : 0,
            sequenceNumber: Number.isFinite(Number(rawWaypoint.sequenceNumber)) ? Number(rawWaypoint.sequenceNumber) : 0,
            label: rawWaypoint.label !== undefined && rawWaypoint.label !== null ? String(rawWaypoint.label) : "",
            frameType: frameType,
            validTerrain: rawWaypoint.validTerrain === true,
            syntheticReturnHome: rawWaypoint.syntheticReturnHome === true,
            latitude: clampLatitude(latitude),
            longitude: normalizeLongitude(longitude),
            inputAltitudeMeters: Number.isFinite(inputAltitudeMeters) ? inputAltitudeMeters : Number.NaN,
            altitudeAmsl: altitudeAmsl,
            groundAltitudeAmsl: groundAltitudeAmsl
        };
    }

    function normalizeMissionDirectionArrow(rawDirectionArrow) {
        if (!rawDirectionArrow) {
            return null;
        }

        const coord1Latitude = Number(rawDirectionArrow.coord1Latitude);
        const coord1Longitude = Number(rawDirectionArrow.coord1Longitude);
        const coord2Latitude = Number(rawDirectionArrow.coord2Latitude);
        const coord2Longitude = Number(rawDirectionArrow.coord2Longitude);
        if (!Number.isFinite(coord1Latitude) ||
                !Number.isFinite(coord1Longitude) ||
                !Number.isFinite(coord2Latitude) ||
                !Number.isFinite(coord2Longitude)) {
            return null;
        }

        const coord1AltitudeAmsl = Number(rawDirectionArrow.coord1AltitudeAmsl);
        const coord2AltitudeAmsl = Number(rawDirectionArrow.coord2AltitudeAmsl);

        return {
            coord1Latitude: clampLatitude(coord1Latitude),
            coord1Longitude: normalizeLongitude(coord1Longitude),
            coord2Latitude: clampLatitude(coord2Latitude),
            coord2Longitude: normalizeLongitude(coord2Longitude),
            coord1AltitudeAmsl: Number.isFinite(coord1AltitudeAmsl) ? coord1AltitudeAmsl : Number.NaN,
            coord2AltitudeAmsl: Number.isFinite(coord2AltitudeAmsl) ? coord2AltitudeAmsl : Number.NaN
        };
    }

    function normalizeMissionData(missionData) {
        if (!missionData || !Array.isArray(missionData.waypoints)) {
            return {
                vehicleId: missionData && missionData.vehicleId !== undefined && missionData.vehicleId !== null
                    ? String(missionData.vehicleId)
                    : "mission",
                altitudeBiasMeters: 0.0,
                homeAltitudeAmsl: Number.NaN,
                waypoints: []
            };
        }

        const waypoints = [];
        const directionArrows = [];
        for (const rawWaypoint of missionData.waypoints) {
            const normalizedWaypoint = normalizeMissionWaypoint(rawWaypoint);
            if (normalizedWaypoint) {
                waypoints.push(normalizedWaypoint);
            }
        }
        if (Array.isArray(missionData.directionArrows)) {
            for (const rawDirectionArrow of missionData.directionArrows) {
                const normalizedDirectionArrow = normalizeMissionDirectionArrow(rawDirectionArrow);
                if (normalizedDirectionArrow) {
                    directionArrows.push(normalizedDirectionArrow);
                }
            }
        }

        return {
            vehicleId: missionData.vehicleId !== undefined && missionData.vehicleId !== null
                ? String(missionData.vehicleId)
                : "mission",
            altitudeBiasMeters: Number.isFinite(Number(missionData.altitudeBiasMeters)) ? Number(missionData.altitudeBiasMeters) : 0.0,
            homeAltitudeAmsl: Number.isFinite(Number(missionData.homeAltitudeAmsl)) ? Number(missionData.homeAltitudeAmsl) : Number.NaN,
            waypoints: waypoints,
            directionArrows: directionArrows
        };
    }

    function normalizeMissionsData(missionsData) {
        if (!Array.isArray(missionsData)) {
            return [];
        }

        const normalizedMissions = [];
        for (const missionData of missionsData) {
            const normalized = normalizeMissionData(missionData);
            if (normalized) {
                normalizedMissions.push(normalized);
            }
        }
        return normalizedMissions;
    }

    function formatMeters(value, decimals) {
        const safeDecimals = Number.isFinite(decimals) ? decimals : 1;
        if (!Number.isFinite(value)) {
            return "--";
        }
        return value.toFixed(safeDecimals);
    }

    function sampleTerrainAltitudeAmsl(longitude, latitude, exaggerated) {
        if (!map || !mapLoaded || typeof map.queryTerrainElevation !== "function") {
            return Number.NaN;
        }

        try {
            const value = map.queryTerrainElevation([longitude, latitude], {
                exaggerated: exaggerated === true
            });
            return Number.isFinite(value) ? Number(value) : Number.NaN;
        } catch (error) {
            return Number.NaN;
        }
    }

    function resolveGroundAltitudeAmsl(waypoint, homeAltitudeAmsl) {
        const missionGroundAmsl = Number.isFinite(waypoint.groundAltitudeAmsl)
            ? Number(waypoint.groundAltitudeAmsl)
            : Number.NaN;
        const terrainRawAmsl = sampleTerrainAltitudeAmsl(waypoint.longitude, waypoint.latitude, false);
        const terrainRenderedAmsl = TERRAIN_EXAGGERATION !== 1.0
            ? sampleTerrainAltitudeAmsl(waypoint.longitude, waypoint.latitude, true)
            : terrainRawAmsl;

        let logicalGroundAmsl = Number.NaN;
        let validTerrain = false;

        if (waypoint.validTerrain === true && Number.isFinite(missionGroundAmsl)) {
            logicalGroundAmsl = missionGroundAmsl;
            validTerrain = true;
        } else if (Number.isFinite(terrainRawAmsl)) {
            logicalGroundAmsl = terrainRawAmsl;
            validTerrain = true;
        } else if (Number.isFinite(homeAltitudeAmsl)) {
            logicalGroundAmsl = homeAltitudeAmsl;
        } else {
            logicalGroundAmsl = 0.0;
        }

        const renderedGroundAmsl = Number.isFinite(terrainRenderedAmsl)
            ? terrainRenderedAmsl
            : logicalGroundAmsl;

        return {
            groundAltitudeAmsl: logicalGroundAmsl,
            groundRenderAltitudeAmsl: renderedGroundAmsl,
            validTerrain: validTerrain
        };
    }

    function resolveWaypointRelativeAltitudeMeters(waypoint, homeAltitudeAmsl) {
        if (waypoint && waypoint.frameType === "AGL") {
            if (Number.isFinite(waypoint.inputAltitudeMeters)) {
                return waypoint.inputAltitudeMeters;
            }
            if (Number.isFinite(waypoint.altitudeAmsl) && Number.isFinite(waypoint.groundAltitudeAmsl)) {
                return waypoint.altitudeAmsl - waypoint.groundAltitudeAmsl;
            }
        }
        if (waypoint && waypoint.frameType === "RELATIVE") {
            if (Number.isFinite(waypoint.inputAltitudeMeters)) {
                return waypoint.inputAltitudeMeters;
            }
            if (Number.isFinite(waypoint.altitudeAmsl) && Number.isFinite(homeAltitudeAmsl)) {
                return waypoint.altitudeAmsl - homeAltitudeAmsl;
            }
        }
        if (waypoint && waypoint.frameType === "AMSL") {
            if (Number.isFinite(waypoint.altitudeAmsl)) {
                return waypoint.altitudeAmsl;
            }
            if (Number.isFinite(waypoint.inputAltitudeMeters)) {
                return waypoint.inputAltitudeMeters;
            }
        }
        if (Number.isFinite(waypoint.altitudeAmsl)) {
            return waypoint.altitudeAmsl;
        }
        if (Number.isFinite(waypoint.inputAltitudeMeters)) {
            return waypoint.inputAltitudeMeters;
        }
        return Number.NaN;
    }

    function missionDebugText(waypoint, homeAltitudeAmsl) {
        const seqText = Number.isFinite(waypoint.sequenceNumber)
            ? String(Math.round(waypoint.sequenceNumber))
            : (waypoint.label && waypoint.label.length > 0 ? waypoint.label : "?");
        const relativeAltitude = resolveWaypointRelativeAltitudeMeters(waypoint, homeAltitudeAmsl);
        const relativeAltitudeText = formatMeters(relativeAltitude, 1);
        return [
            "WP " + seqText,
            (relativeAltitudeText === "--" ? relativeAltitudeText : (relativeAltitudeText + "m"))
        ].join("\n");
    }

    function createMissionDebugMarkerElement(text) {
        const element = document.createElement("div");
        element.className = "qgc-waypoint-label";
        element.style.pointerEvents = "none";

        element.textContent = text;

        return element;
    }

    function createMissionDirectionMarkerElement() {
        const element = document.createElement("div");
        element.className = "qgc-mission-direction-arrow";
        element.style.pointerEvents = "none";

        const svgNS = "http://www.w3.org/2000/svg";
        const svg = document.createElementNS(svgNS, "svg");
        svg.setAttribute("viewBox", "0 0 24 24");
        svg.setAttribute("width", "22");
        svg.setAttribute("height", "22");
        svg.classList.add("qgc-mission-direction-cone");

        const coneBody = document.createElementNS(svgNS, "path");
        coneBody.setAttribute("d", "M12 2 L17.4 16.2 L6.6 16.2 Z");
        coneBody.setAttribute("fill", MISSION_DIRECTION_ARROW_COLOR);
        coneBody.setAttribute("fill-opacity", "0.96");

        const coneHighlight = document.createElementNS(svgNS, "path");
        coneHighlight.setAttribute("d", "M12 3.6 L14.7 15.3 L12 15.3 Z");
        coneHighlight.setAttribute("fill", "#ffffff");
        coneHighlight.setAttribute("fill-opacity", "0.45");

        const coneBase = document.createElementNS(svgNS, "ellipse");
        coneBase.setAttribute("cx", "12");
        coneBase.setAttribute("cy", "16.7");
        coneBase.setAttribute("rx", "5.3");
        coneBase.setAttribute("ry", "1.9");
        coneBase.setAttribute("fill", MISSION_DIRECTION_ARROW_COLOR);
        coneBase.setAttribute("fill-opacity", "0.82");

        const coneRim = document.createElementNS(svgNS, "ellipse");
        coneRim.setAttribute("cx", "12");
        coneRim.setAttribute("cy", "16.7");
        coneRim.setAttribute("rx", "5.1");
        coneRim.setAttribute("ry", "1.6");
        coneRim.setAttribute("fill", "none");
        coneRim.setAttribute("stroke", "rgba(255,255,255,0.75)");
        coneRim.setAttribute("stroke-width", "0.45");

        svg.appendChild(coneBody);
        svg.appendChild(coneHighlight);
        svg.appendChild(coneBase);
        svg.appendChild(coneRim);
        element.appendChild(svg);

        return element;
    }

    function clearMissionDebugMarkers() {
        for (const marker of missionDebugMarkers) {
            if (marker && typeof marker.remove === "function") {
                marker.remove();
            }
        }
        missionDebugMarkers = [];
    }

    function clearMissionDirectionMarkers() {
        for (const marker of missionDirectionMarkers) {
            if (marker && typeof marker.remove === "function") {
                marker.remove();
            }
        }
        missionDirectionMarkers = [];
    }

    function setMarkerCollectionVisibility(markerCollection, visible) {
        if (!Array.isArray(markerCollection)) {
            return;
        }

        const displayValue = visible ? "" : "none";
        for (const marker of markerCollection) {
            if (!marker || typeof marker.getElement !== "function") {
                continue;
            }
            const markerElement = marker.getElement();
            if (!markerElement) {
                continue;
            }
            markerElement.style.display = displayValue;
        }
    }

    function shouldDeclutterMapLayer(layer) {
        if (!layer || !layer.id) {
            return false;
        }

        if (layer.id === MISSION_3D_LAYER_ID) {
            return false;
        }

        // In streamed 3D, declutter primarily means removing map label/icon noise.
        return layer.type === "symbol";
    }

    function applyBaseMapDeclutterState() {
        if (!map || !mapLoaded || typeof map.getStyle !== "function") {
            return;
        }

        const style = map.getStyle();
        if (!style || !Array.isArray(style.layers)) {
            return;
        }

        for (const layer of style.layers) {
            if (!shouldDeclutterMapLayer(layer)) {
                continue;
            }

            const layerId = layer.id;
            if (!mapDeclutterLayerVisibilityCache.has(layerId)) {
                let initialVisibility = "visible";
                try {
                    const currentVisibility = map.getLayoutProperty(layerId, "visibility");
                    initialVisibility = currentVisibility ? String(currentVisibility) : "visible";
                } catch (error) {
                    initialVisibility = "visible";
                }
                mapDeclutterLayerVisibilityCache.set(layerId, initialVisibility);
            }

            const restoredVisibility = mapDeclutterLayerVisibilityCache.get(layerId) || "visible";
            const targetVisibility = declutterEnabled ? "none" : restoredVisibility;
            try {
                if (map.getLayoutProperty(layerId, "visibility") !== targetVisibility) {
                    map.setLayoutProperty(layerId, "visibility", targetVisibility);
                }
            } catch (error) {
                // Ignore layers that reject runtime visibility changes.
            }
        }
    }

    function applyDeclutterState() {
        // Declutter keeps core mission geometry (routes/points) and hides
        // auxiliary mission overlays (labels/direction markers).
        const showMissionOverlays = !declutterEnabled;
        setMarkerCollectionVisibility(missionDebugMarkers, showMissionOverlays);
        setMarkerCollectionVisibility(missionDirectionMarkers, showMissionOverlays);
        applyBaseMapDeclutterState();
        if (map && mapLoaded) {
            map.triggerRepaint();
        }
    }

    function updateMissionDebugLayer(debugLabels) {
        if (!map || !mapLoaded || !window.mapboxgl) {
            return;
        }

        clearMissionDebugMarkers();
        if (!Array.isArray(debugLabels) || debugLabels.length === 0) {
            return;
        }

        for (const label of debugLabels) {
            if (!label || !Number.isFinite(label.longitude) || !Number.isFinite(label.latitude)) {
                continue;
            }

            const labelAltitude = Number.isFinite(label.altitudeAboveGround)
                ? Math.max(0.0, label.altitudeAboveGround)
                : 0.0;
            const marker = new mapboxgl.Marker({
                element: createMissionDebugMarkerElement(label.text || ""),
                anchor: "left",
                offset: [MISSION_LABEL_OFFSET_X_PX, 0],
                pitchAlignment: "viewport",
                rotationAlignment: "viewport",
                altitude: labelAltitude
            });
            marker.setLngLat([label.longitude, label.latitude]);
            if (typeof marker.setAltitude === "function") {
                marker.setAltitude(labelAltitude);
            }
            marker.addTo(map);
            missionDebugMarkers.push(marker);
        }

        applyDeclutterState();
    }

    function updateMissionDirectionLayer(directionArrows) {
        if (!map || !mapLoaded || !window.mapboxgl) {
            return;
        }

        clearMissionDirectionMarkers();
        if (!Array.isArray(directionArrows) || directionArrows.length === 0) {
            return;
        }

        for (const directionArrow of directionArrows) {
            if (!directionArrow ||
                    !Number.isFinite(directionArrow.longitude) ||
                    !Number.isFinite(directionArrow.latitude)) {
                continue;
            }

            const altitude = Number.isFinite(directionArrow.altitudeAboveGround)
                ? Math.max(0.0, directionArrow.altitudeAboveGround)
                : 0.0;
            const marker = new mapboxgl.Marker({
                element: createMissionDirectionMarkerElement(),
                anchor: "center",
                pitchAlignment: "map",
                rotationAlignment: "map",
                altitude: altitude
            });
            marker.setLngLat([directionArrow.longitude, directionArrow.latitude]);
            if (typeof marker.setRotation === "function") {
                marker.setRotation(Number.isFinite(directionArrow.bearingDegrees) ? directionArrow.bearingDegrees : 0.0);
            }
            if (typeof marker.setAltitude === "function") {
                marker.setAltitude(altitude);
            }
            marker.addTo(map);
            missionDirectionMarkers.push(marker);
        }

        applyDeclutterState();
    }

    function removeMissionDebugLayer() {
        clearMissionDebugMarkers();
    }

    function removeMissionDirectionLayer() {
        clearMissionDirectionMarkers();
    }

    function applyStreamingConfig(config) {
        streamingConfig = normalizeConfig(config);
    }

    function setStatus(message, statusType) {
        if (!statusElement) {
            return;
        }

        if (!message) {
            statusElement.textContent = "";
            statusElement.classList.add("hidden");
            statusElement.classList.remove("error");
            statusElement.classList.remove("warning");
            activeStatusType = "";
            return;
        }

        statusElement.textContent = message;
        statusElement.classList.remove("hidden");
        statusElement.classList.toggle("error", statusType === "error");
        statusElement.classList.toggle("warning", statusType === "warning");
        activeStatusType = statusType || "";
    }

    function setError(message) {
        setStatus(message, "error");
    }

    function setWarning(message) {
        if (activeStatusType === "error") {
            return;
        }
        setStatus(message, "warning");
    }

    function clearWarning() {
        if (activeStatusType === "warning") {
            setStatus("", "");
        }
    }

    function validateToken(showMessage) {
        if (!streamingConfig.token || streamingConfig.token.length === 0) {
            if (showMessage === true) {
                setError(MISSING_TOKEN_MESSAGE);
            }
            return false;
        }

        return true;
    }

    function hasInitialMapViewState() {
        return normalizeMapViewState(window.__qgcMapViewState || pendingMapViewState) !== null;
    }

    function maybeCreateMapIfReady() {
        if (map || mapInitializing) {
            return;
        }

        if (!validateToken(false)) {
            return;
        }

        if (!hasInitialMapViewState()) {
            return;
        }

        createMap();
    }

    function installMapboxTerrainAndBuildings() {
        if (!map || !mapLoaded) {
            return;
        }

        if (!map.getSource("mapbox-dem")) {
            map.addSource("mapbox-dem", {
                type: "raster-dem",
                url: "mapbox://mapbox.mapbox-terrain-dem-v1",
                tileSize: 512,
                maxzoom: 14
            });
        }

        map.setTerrain({
            source: "mapbox-dem",
            exaggeration: TERRAIN_EXAGGERATION
        });

        if (map.getLayer("qgc-3d-buildings")) {
            map.removeLayer("qgc-3d-buildings");
        }

        if (!map.getSource(BUILDING_VECTOR_SOURCE_ID)) {
            map.addSource(BUILDING_VECTOR_SOURCE_ID, {
                type: "vector",
                url: BUILDING_VECTOR_SOURCE_URL
            });
        }

        const style = map.getStyle();
        const firstLabelLayerId = style && style.layers
            ? style.layers.find(function (layer) { return layer.type === "symbol"; })
            : null;
        const buildingTargetHeight = ["to-number", ["get", "height"], 0];
        const buildingTargetBase = ["to-number", ["get", "min_height"], 0];

        try {
            map.addLayer({
                id: "qgc-3d-buildings",
                source: BUILDING_VECTOR_SOURCE_ID,
                "source-layer": "building",
                // Capture both old/new schema variants so buildings appear consistently.
                filter: [
                    "any",
                    ["==", ["get", "extrude"], "true"],
                    ["==", ["get", "extrude"], true],
                    ["has", "height"],
                    ["has", "render_height"],
                    ["has", "levels"]
                ],
                type: "fill-extrusion",
                // Keep layer active slightly before growth start so we avoid a hard layer pop.
                minzoom: BUILDING_GROWTH_START_ZOOM - 1.0,
                paint: {
                    "fill-extrusion-color": "#aaa",
                    "fill-extrusion-height": [
                        "interpolate", ["exponential", BUILDING_GROWTH_CURVE], ["zoom"],
                        BUILDING_GROWTH_START_ZOOM, 0,
                        BUILDING_GROWTH_END_ZOOM, buildingTargetHeight
                    ],
                    "fill-extrusion-base": [
                        "interpolate", ["exponential", BUILDING_GROWTH_CURVE], ["zoom"],
                        BUILDING_GROWTH_START_ZOOM, 0,
                        BUILDING_GROWTH_END_ZOOM, buildingTargetBase
                    ],
                    "fill-extrusion-opacity": BUILDING_LAYER_OPACITY
                }
            }, firstLabelLayerId ? firstLabelLayerId.id : undefined);

            console.warn("[Streaming3D] Buildings layer added source:", BUILDING_VECTOR_SOURCE_ID, "zoom:", BUILDING_GROWTH_START_ZOOM, "->", BUILDING_GROWTH_END_ZOOM);
        } catch (buildingLayerError) {
            console.warn("building layer setup failed:", buildingLayerError);
        }

        if (ENABLE_ATMOSPHERIC_FOG && typeof map.setFog === "function") {
            try {
                map.setFog({
                    range: [-1.0, 2.0],
                    color: "rgba(186, 210, 235, 0.32)",
                    "high-color": "rgba(36, 92, 158, 0.12)",
                    "space-color": "rgba(10, 18, 32, 1)",
                    "horizon-blend": 0.2
                });
            } catch (fogError) {
                console.warn("fog setup skipped:", fogError);
            }
        }
    }

    function logGlRendererInfo() {
        if (!map) {
            return;
        }

        try {
            const canvas = map.getCanvas();
            if (!canvas) {
                return;
            }

            const gl =
                canvas.getContext("webgl2") ||
                canvas.getContext("webgl") ||
                canvas.getContext("experimental-webgl");
            if (!gl) {
                return;
            }

            let renderer = gl.getParameter(gl.RENDERER) || "unknown";
            let vendor = gl.getParameter(gl.VENDOR) || "unknown";
            const dbgExt = gl.getExtension("WEBGL_debug_renderer_info");
            if (dbgExt) {
                renderer = gl.getParameter(dbgExt.UNMASKED_RENDERER_WEBGL) || renderer;
                vendor = gl.getParameter(dbgExt.UNMASKED_VENDOR_WEBGL) || vendor;
            }

            console.warn("[Streaming3D] WebGL renderer:", renderer, "vendor:", vendor);
        } catch (error) {
            console.warn("renderer diagnostics failed:", error);
        }
    }

    function configureInteractionHandlers() {
        if (!map) {
            return;
        }

        // Tune interaction inertia for desktop mouse usage in QWebEngine.
        try {
            if (map.scrollZoom && typeof map.scrollZoom.enable === "function") {
                map.scrollZoom.enable({ around: "center" });
            }
            if (map.scrollZoom && typeof map.scrollZoom.setWheelZoomRate === "function") {
                map.scrollZoom.setWheelZoomRate(WHEEL_ZOOM_RATE);
            }
            if (map.scrollZoom && typeof map.scrollZoom.setZoomRate === "function") {
                map.scrollZoom.setZoomRate(TRACKPAD_ZOOM_RATE);
            }
        } catch (zoomTuningError) {
            console.warn("scroll zoom tuning skipped:", zoomTuningError);
        }

        try {
            if (map.dragPan && typeof map.dragPan.enable === "function") {
                map.dragPan.enable({
                    linearity: 0.10,
                    easing: function (t) { return t; },
                    maxSpeed: PAN_MAX_SPEED,
                    deceleration: PAN_DECELERATION
                });
            }
        } catch (panTuningError) {
            console.warn("drag pan tuning skipped:", panTuningError);
        }

        try {
            if (map.dragRotate && typeof map.dragRotate.enable === "function") {
                map.dragRotate.enable({
                    linearity: 0.10,
                    easing: function (t) { return t; },
                    maxSpeed: ROTATE_MAX_SPEED,
                    deceleration: ROTATE_DECELERATION
                });
            }
        } catch (rotateTuningError) {
            console.warn("drag rotate tuning skipped:", rotateTuningError);
        }
    }

    function createVehicleMarkerElement(vehicleId) {
        const markerElement = document.createElement("div");
        markerElement.className = "qgc-vehicle-marker";
        markerElement.dataset.vehicleId = String(vehicleId || "active");
        markerElement.style.width = VEHICLE_MARKER_SIZE_PX + "px";
        markerElement.style.height = VEHICLE_MARKER_SIZE_PX + "px";
        markerElement.style.pointerEvents = "none";
        markerElement.style.userSelect = "none";
        markerElement.style.transformOrigin = "50% 50%";
        markerElement.style.backgroundRepeat = "no-repeat";
        markerElement.style.backgroundPosition = "center";
        markerElement.style.backgroundSize = "contain";

        return markerElement;
    }

    function updateVehicleMarkerIcon(markerElement, iconSource, iconColor) {
        if (!markerElement) {
            return;
        }

        const resolvedIconSource = toWebResourceUrl(iconSource);
        const vehicleId = markerElement.dataset && markerElement.dataset.vehicleId
            ? markerElement.dataset.vehicleId
            : "active";
        const resolvedIconColor = normalizeVehicleIconColor(iconColor, vehicleId);
        const urlValue = "url(\"" + resolvedIconSource.replace(/"/g, "\\\"") + "\")";
        const supportsMaskImage =
            markerElement.style && (
                ("maskImage" in markerElement.style) ||
                ("webkitMaskImage" in markerElement.style)
            );

        if (supportsMaskImage) {
            if (markerElement.style.maskImage !== urlValue) {
                markerElement.style.maskImage = urlValue;
                markerElement.style.webkitMaskImage = urlValue;
                markerElement.style.maskRepeat = "no-repeat";
                markerElement.style.webkitMaskRepeat = "no-repeat";
                markerElement.style.maskPosition = "center";
                markerElement.style.webkitMaskPosition = "center";
                markerElement.style.maskSize = "contain";
                markerElement.style.webkitMaskSize = "contain";
            }
            if (markerElement.style.backgroundColor !== resolvedIconColor) {
                markerElement.style.backgroundColor = resolvedIconColor;
            }
            markerElement.style.backgroundImage = "none";
        } else {
            // Fallback path for environments that do not support CSS masking.
            markerElement.style.backgroundColor = "transparent";
            if (markerElement.style.backgroundImage !== urlValue) {
                markerElement.style.backgroundImage = urlValue;
            }
        }
    }

    function removeVehicleMarkerById(vehicleId) {
        const marker = vehicleMarkers.get(vehicleId);
        if (!marker) {
            return;
        }
        marker.remove();
        vehicleMarkers.delete(vehicleId);
    }

    function removeAllVehicleMarkers() {
        for (const marker of vehicleMarkers.values()) {
            marker.remove();
        }
        vehicleMarkers.clear();
    }

    function vehicleTrailColorForId(vehicleId) {
        const paletteIndex = vehicleColorHash(vehicleId) % VEHICLE_TRAIL_COLOR_PALETTE.length;
        return VEHICLE_TRAIL_COLOR_PALETTE[paletteIndex].slice();
    }

    function clearVehicleTrailHistory() {
        vehicleTrailHistories.clear();
        if (missionLayerState) {
            setMissionTrailGeometry([]);
        }
    }

    function resolveVehicleRenderAltitudeAmsl(normalizedVehicleState) {
        if (!normalizedVehicleState) {
            return 0.0;
        }

        const terrainRenderedAmsl = sampleTerrainAltitudeAmsl(
            normalizedVehicleState.longitude,
            normalizedVehicleState.latitude,
            true
        );
        const altitudeAgl = resolveVehicleAltitudeAboveGround(normalizedVehicleState);
        if (Number.isFinite(terrainRenderedAmsl)) {
            return terrainRenderedAmsl + altitudeAgl;
        }
        if (Number.isFinite(normalizedVehicleState.altitudeAmsl)) {
            return normalizedVehicleState.altitudeAmsl;
        }
        if (Number.isFinite(normalizedVehicleState.homeAltitudeAmsl) &&
                Number.isFinite(normalizedVehicleState.altitudeRelative)) {
            return normalizedVehicleState.homeAltitudeAmsl + normalizedVehicleState.altitudeRelative;
        }
        if (Number.isFinite(altitudeAgl)) {
            return altitudeAgl;
        }
        return 0.0;
    }

    function pruneVehicleTrailSamples(samples, nowMs) {
        if (!Array.isArray(samples)) {
            return;
        }

        const cutoffTime = nowMs - VEHICLE_TRAIL_MAX_AGE_MS;
        while (samples.length > 0 && samples[0].timestampMs < cutoffTime) {
            samples.shift();
        }
        if (samples.length > VEHICLE_TRAIL_MAX_POINTS) {
            samples.splice(0, samples.length - VEHICLE_TRAIL_MAX_POINTS);
        }
    }

    function recordVehicleTrailSample(normalizedVehicleState, nowMs) {
        if (!normalizedVehicleState || !window.mapboxgl) {
            return;
        }

        const latitude = normalizedVehicleState.latitude;
        const longitude = normalizedVehicleState.longitude;
        if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
            return;
        }

        const renderAltitudeAmsl = resolveVehicleRenderAltitudeAmsl(normalizedVehicleState);
        const mercatorPoint = mapboxgl.MercatorCoordinate.fromLngLat(
            { lng: longitude, lat: latitude },
            renderAltitudeAmsl
        );
        if (!mercatorPoint) {
            return;
        }

        const vehicleId = normalizedVehicleState.id || "active";
        if (!vehicleTrailHistories.has(vehicleId)) {
            vehicleTrailHistories.set(vehicleId, {
                id: vehicleId,
                color: vehicleTrailColorForId(vehicleId),
                samples: []
            });
        }
        const history = vehicleTrailHistories.get(vehicleId);
        const sample = {
            x: mercatorPoint.x,
            y: mercatorPoint.y,
            z: mercatorPoint.z,
            latitude: latitude,
            longitude: longitude,
            renderAltitudeAmsl: renderAltitudeAmsl,
            timestampMs: nowMs
        };

        const samples = history.samples;
        if (samples.length > 0) {
            const lastSample = samples[samples.length - 1];
            const horizontalStepMeters = greatCircleDistanceMeters(
                lastSample.latitude,
                lastSample.longitude,
                sample.latitude,
                sample.longitude
            );
            const verticalStepMeters = Math.abs(sample.renderAltitudeAmsl - lastSample.renderAltitudeAmsl);
            if (horizontalStepMeters < VEHICLE_TRAIL_MIN_HORIZONTAL_STEP_METERS &&
                    verticalStepMeters < VEHICLE_TRAIL_MIN_VERTICAL_STEP_METERS) {
                lastSample.x = sample.x;
                lastSample.y = sample.y;
                lastSample.z = sample.z;
                lastSample.latitude = sample.latitude;
                lastSample.longitude = sample.longitude;
                lastSample.renderAltitudeAmsl = sample.renderAltitudeAmsl;
                lastSample.timestampMs = nowMs;
                pruneVehicleTrailSamples(samples, nowMs);
                return;
            }
        }

        samples.push(sample);
        pruneVehicleTrailSamples(samples, nowMs);
    }

    function ensureVehicleMarker(vehicleId) {
        if (!map || !mapLoaded || !window.mapboxgl) {
            return null;
        }

        const existingMarker = vehicleMarkers.get(vehicleId);
        if (existingMarker) {
            return existingMarker;
        }

        const markerElement = createVehicleMarkerElement(vehicleId);
        updateVehicleMarkerIcon(
            markerElement,
            DEFAULT_VEHICLE_ICON_SOURCE,
            vehicleIconColorForId(vehicleId)
        );

        const marker = new mapboxgl.Marker({
            element: markerElement,
            anchor: "center",
            pitchAlignment: "map",
            rotationAlignment: "map"
        });
        vehicleMarkers.set(vehicleId, marker);
        return marker;
    }

    function applySingleVehicleState(normalizedVehicleState) {
        if (!normalizedVehicleState) {
            return false;
        }

        const vehicleId = normalizedVehicleState.id || "active";
        const marker = ensureVehicleMarker(vehicleId);
        if (!marker) {
            return false;
        }

        updateVehicleMarkerIcon(
            marker.getElement ? marker.getElement() : null,
            normalizedVehicleState.iconSource,
            normalizedVehicleState.iconColor
        );
        marker.setLngLat([normalizedVehicleState.longitude, normalizedVehicleState.latitude]);
        if (typeof marker.setRotation === "function") {
            marker.setRotation(normalizedVehicleState.heading);
        }
        if (typeof marker.setAltitude === "function") {
            marker.setAltitude(resolveVehicleAltitudeAboveGround(normalizedVehicleState));
        }
        if (!marker._map) {
            marker.addTo(map);
        }

        return true;
    }

    function applyVehiclesState(vehicleStates) {
        const normalizedStates = normalizeVehiclesState(vehicleStates);
        pendingVehicleState = normalizedStates;

        if (!map || !mapLoaded) {
            return normalizedStates.length > 0;
        }

        const activeIds = new Set();
        const nowMs = Date.now();
        for (const normalizedState of normalizedStates) {
            const vehicleId = normalizedState.id || "active";
            activeIds.add(vehicleId);
            applySingleVehicleState(normalizedState);
            recordVehicleTrailSample(normalizedState, nowMs);
        }

        for (const markerId of Array.from(vehicleMarkers.keys())) {
            if (!activeIds.has(markerId)) {
                removeVehicleMarkerById(markerId);
            }
        }

        for (const trailVehicleId of Array.from(vehicleTrailHistories.keys())) {
            if (!activeIds.has(trailVehicleId)) {
                vehicleTrailHistories.delete(trailVehicleId);
            }
        }

        if (activeIds.size === 0) {
            setMissionTrailGeometry([]);
        } else {
            refreshVehicleTrailsInLayer();
        }

        pendingVehicleState = null;
        if (pendingCenterOnVehicleRequest) {
            centerOnVehicle(pendingCenterOnVehicleRequest);
        } else if (followVehicleEnabled === true && normalizedStates.length > 0) {
            if (Date.now() < followTrackingSuppressUntilMs) {
                map.triggerRepaint();
                return true;
            }
            const followState = findVehicleStateById(normalizedStates, followVehicleId);
            const fallbackState = followState || normalizedStates[0];
            centerOnVehicle({
                id: fallbackState && fallbackState.id ? String(fallbackState.id) : "",
                animate: false
            });
        } else if (autoPanEnabled === true && normalizedStates.length > 0) {
            if (Date.now() < autoPanTrackingSuppressUntilMs) {
                map.triggerRepaint();
                return true;
            }
            const autoPanState = findVehicleStateById(normalizedStates, followVehicleId) || normalizedStates[0];
            if (autoPanState && !isVehicleStateWithinViewport(autoPanState, AUTO_PAN_VIEWPORT_MARGIN_PX)) {
                centerOnVehicle({
                    id: autoPanState.id ? String(autoPanState.id) : "",
                    animate: false
                });
            }
        }
        map.triggerRepaint();
        return true;
    }

    function setFollowVehicleEnabled(enabled) {
        followVehicleEnabled = (enabled === true);
        followTrackingSuppressUntilMs = 0;
        autoPanTrackingSuppressUntilMs = 0;

        if (!followVehicleEnabled) {
            return true;
        }

        const normalizedStates = normalizeVehiclesState(
            window.__qgcVehiclesState ||
            pendingVehicleState ||
            (window.__qgcVehicleState ? [window.__qgcVehicleState] : [])
        );

        if (normalizedStates.length === 0) {
            return true;
        }

        const followState = findVehicleStateById(normalizedStates, followVehicleId);
        const fallbackState = followState || normalizedStates[0];
        return centerOnVehicle({
            id: fallbackState && fallbackState.id ? String(fallbackState.id) : "",
            animate: false
        });
    }

    function setAutoPanEnabled(enabled) {
        autoPanEnabled = (enabled === true);
        autoPanTrackingSuppressUntilMs = 0;

        if (!autoPanEnabled || followVehicleEnabled === true) {
            return true;
        }

        const normalizedStates = normalizeVehiclesState(
            window.__qgcVehiclesState ||
            pendingVehicleState ||
            (window.__qgcVehicleState ? [window.__qgcVehicleState] : [])
        );
        if (normalizedStates.length === 0) {
            return true;
        }

        const autoPanState = findVehicleStateById(normalizedStates, followVehicleId) || normalizedStates[0];
        if (!autoPanState) {
            return true;
        }

        if (isVehicleStateWithinViewport(autoPanState, AUTO_PAN_VIEWPORT_MARGIN_PX)) {
            return true;
        }

        return centerOnVehicle({
            id: autoPanState.id ? String(autoPanState.id) : "",
            animate: false
        });
    }

    function setDeclutterEnabled(enabled) {
        declutterEnabled = (enabled === true);
        applyDeclutterState();
        return true;
    }

    function applyVehicleState(vehicleState) {
        if (!vehicleState) {
            pendingVehicleState = [];
            removeAllVehicleMarkers();
            clearVehicleTrailHistory();
            return false;
        }

        return applyVehiclesState([vehicleState]);
    }

    function removeVehicleMarker() {
        removeAllVehicleMarkers();
        clearVehicleTrailHistory();
    }

    function createMissionShader(gl, shaderType, source) {
        const shader = gl.createShader(shaderType);
        gl.shaderSource(shader, source);
        gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
            const errorMessage = gl.getShaderInfoLog(shader);
            gl.deleteShader(shader);
            throw new Error("Mission layer shader compile failed: " + errorMessage);
        }
        return shader;
    }

    function createMissionProgram(gl) {
        const vertexSource = [
            "precision highp float;",
            "uniform mat4 u_matrix;",
            "uniform float u_pointSize;",
            "attribute vec3 a_position;",
            "void main() {",
            "    gl_Position = u_matrix * vec4(a_position, 1.0);",
            "    gl_PointSize = u_pointSize;",
            "}"
        ].join("\n");

        const fragmentSource = [
            "precision highp float;",
            "uniform vec4 u_color;",
            "uniform float u_renderMode;",
            "void main() {",
            "    if (u_renderMode > 0.5) {",
            "        vec2 uv = (gl_PointCoord * 2.0) - 1.0;",
            "        float radial = dot(uv, uv);",
            "        if (radial > 1.0) {",
            "            discard;",
            "        }",
            "        float nz = sqrt(max(0.0, 1.0 - radial));",
            "        vec3 normal = normalize(vec3(uv.x, uv.y, nz));",
            "        vec3 lightDirection = normalize(vec3(-0.45, -0.65, 0.75));",
            "        float diffuse = 0.32 + (0.68 * max(dot(normal, lightDirection), 0.0));",
            "        float rim = 0.2 * pow(1.0 - nz, 2.0);",
            "        vec3 shaded = (u_color.rgb * diffuse) + vec3(rim);",
            "        gl_FragColor = vec4(shaded, u_color.a);",
            "    } else {",
            "        gl_FragColor = u_color;",
            "    }",
            "}"
        ].join("\n");

        const vertexShader = createMissionShader(gl, gl.VERTEX_SHADER, vertexSource);
        const fragmentShader = createMissionShader(gl, gl.FRAGMENT_SHADER, fragmentSource);
        const program = gl.createProgram();
        gl.attachShader(program, vertexShader);
        gl.attachShader(program, fragmentShader);
        gl.bindAttribLocation(program, 0, "a_position");
        gl.linkProgram(program);
        if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
            const errorMessage = gl.getProgramInfoLog(program);
            gl.deleteProgram(program);
            gl.deleteShader(vertexShader);
            gl.deleteShader(fragmentShader);
            throw new Error("Mission layer program link failed: " + errorMessage);
        }

        gl.deleteShader(vertexShader);
        gl.deleteShader(fragmentShader);
        return {
            program: program,
            positionAttribute: 0,
            matrixUniform: gl.getUniformLocation(program, "u_matrix"),
            colorUniform: gl.getUniformLocation(program, "u_color"),
            pointSizeUniform: gl.getUniformLocation(program, "u_pointSize"),
            renderModeUniform: gl.getUniformLocation(program, "u_renderMode")
        };
    }

    function resetMissionLayerState() {
        missionLayerState = {
            gl: null,
            program: null,
            positionAttribute: 0,
            matrixUniform: null,
            colorUniform: null,
            pointSizeUniform: null,
            renderModeUniform: null,
            routeBuffer: null,
            verticalBuffer: null,
            verticalFallbackBuffer: null,
            directionBuffer: null,
            waypointBuffer: null,
            trailBuffers: [],
            routeVertices: new Float32Array(0),
            verticalVertices: new Float32Array(0),
            verticalFallbackVertices: new Float32Array(0),
            directionVertices: new Float32Array(0),
            waypointVertices: new Float32Array(0),
            trailBatches: [],
            routeVertexCount: 0,
            verticalVertexCount: 0,
            verticalFallbackVertexCount: 0,
            directionVertexCount: 0,
            waypointVertexCount: 0,
            originX: 0.0,
            originY: 0.0,
            originZ: 0.0
        };
    }

    function uploadMissionLayerBuffers() {
        if (!missionLayerState || !missionLayerState.gl) {
            return;
        }

        const gl = missionLayerState.gl;
        gl.bindBuffer(gl.ARRAY_BUFFER, missionLayerState.routeBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, missionLayerState.routeVertices, gl.DYNAMIC_DRAW);

        gl.bindBuffer(gl.ARRAY_BUFFER, missionLayerState.verticalBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, missionLayerState.verticalVertices, gl.DYNAMIC_DRAW);

        gl.bindBuffer(gl.ARRAY_BUFFER, missionLayerState.verticalFallbackBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, missionLayerState.verticalFallbackVertices, gl.DYNAMIC_DRAW);

        gl.bindBuffer(gl.ARRAY_BUFFER, missionLayerState.directionBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, missionLayerState.directionVertices, gl.DYNAMIC_DRAW);

        gl.bindBuffer(gl.ARRAY_BUFFER, missionLayerState.waypointBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, missionLayerState.waypointVertices, gl.DYNAMIC_DRAW);

        while (missionLayerState.trailBuffers.length < missionLayerState.trailBatches.length) {
            missionLayerState.trailBuffers.push(gl.createBuffer());
        }
        while (missionLayerState.trailBuffers.length > missionLayerState.trailBatches.length) {
            const bufferToDelete = missionLayerState.trailBuffers.pop();
            if (bufferToDelete) {
                gl.deleteBuffer(bufferToDelete);
            }
        }

        for (let i = 0; i < missionLayerState.trailBatches.length; i++) {
            const batch = missionLayerState.trailBatches[i];
            const buffer = missionLayerState.trailBuffers[i];
            if (!batch || !buffer) {
                continue;
            }
            gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
            gl.bufferData(gl.ARRAY_BUFFER, batch.vertices, gl.DYNAMIC_DRAW);
        }

        missionLayerNeedsUpload = false;
    }

    function setMissionLayerGeometry(routeVertices, verticalVertices, verticalFallbackVertices, directionVertices, waypointVertices, origin) {
        if (!missionLayerState) {
            resetMissionLayerState();
        }

        missionLayerState.routeVertices = routeVertices;
        missionLayerState.verticalVertices = verticalVertices;
        missionLayerState.verticalFallbackVertices = verticalFallbackVertices;
        missionLayerState.directionVertices = directionVertices;
        missionLayerState.waypointVertices = waypointVertices;
        missionLayerState.routeVertexCount = Math.floor(routeVertices.length / 3);
        missionLayerState.verticalVertexCount = Math.floor(verticalVertices.length / 3);
        missionLayerState.verticalFallbackVertexCount = Math.floor(verticalFallbackVertices.length / 3);
        missionLayerState.directionVertexCount = Math.floor(directionVertices.length / 3);
        missionLayerState.waypointVertexCount = Math.floor(waypointVertices.length / 3);
        missionLayerState.originX = origin && Number.isFinite(origin.x) ? origin.x : 0.0;
        missionLayerState.originY = origin && Number.isFinite(origin.y) ? origin.y : 0.0;
        missionLayerState.originZ = origin && Number.isFinite(origin.z) ? origin.z : 0.0;
        missionLayerNeedsUpload = true;

        if (missionLayerState.gl) {
            uploadMissionLayerBuffers();
        }
    }

    function setMissionTrailGeometry(trailBatches) {
        if (!missionLayerState) {
            resetMissionLayerState();
        }

        missionLayerState.trailBatches = Array.isArray(trailBatches) ? trailBatches : [];
        missionLayerNeedsUpload = true;
        if (missionLayerState.gl) {
            uploadMissionLayerBuffers();
        }
    }

    function hasStaticMissionGeometry() {
        return !!missionLayerState &&
            (missionLayerState.routeVertexCount > 0 ||
             missionLayerState.verticalVertexCount > 0 ||
             missionLayerState.verticalFallbackVertexCount > 0 ||
             missionLayerState.directionVertexCount > 0 ||
             missionLayerState.waypointVertexCount > 0);
    }

    function firstTrailSample() {
        for (const history of vehicleTrailHistories.values()) {
            if (!history || !Array.isArray(history.samples) || history.samples.length === 0) {
                continue;
            }
            return history.samples[0];
        }
        return null;
    }

    function resolveTrailOrigin() {
        if (!missionLayerState) {
            resetMissionLayerState();
        }

        if (hasStaticMissionGeometry()) {
            return {
                x: missionLayerState.originX,
                y: missionLayerState.originY,
                z: missionLayerState.originZ
            };
        }

        const sample = firstTrailSample();
        if (!sample) {
            return {
                x: missionLayerState.originX,
                y: missionLayerState.originY,
                z: missionLayerState.originZ
            };
        }

        missionLayerState.originX = sample.x;
        missionLayerState.originY = sample.y;
        missionLayerState.originZ = sample.z;
        return {
            x: sample.x,
            y: sample.y,
            z: sample.z
        };
    }

    function buildVehicleTrailBatches(origin) {
        const batches = [];
        for (const history of vehicleTrailHistories.values()) {
            if (!history || !Array.isArray(history.samples) || history.samples.length < 2) {
                continue;
            }

            const samples = history.samples;
            const referenceSample = samples[Math.floor(samples.length * 0.5)];
            const referenceLatitude = referenceSample && Number.isFinite(referenceSample.latitude)
                ? referenceSample.latitude
                : 0.0;
            const halfWidthWorld = Math.max(
                metersToMercatorUnits(0.5 * VEHICLE_TRAIL_LINE_DIAMETER_METERS, referenceLatitude),
                1e-10
            );

            const trailVertices = [];
            for (let i = 1; i < samples.length; i++) {
                const prev = samples[i - 1];
                const next = samples[i];
                const start = {
                    x: prev.x - origin.x,
                    y: prev.y - origin.y,
                    z: prev.z - origin.z
                };
                const end = {
                    x: next.x - origin.x,
                    y: next.y - origin.y,
                    z: next.z - origin.z
                };
                appendTubeSegmentTriangles(
                    trailVertices,
                    start,
                    end,
                    halfWidthWorld,
                    MISSION_TUBE_RADIAL_SEGMENTS
                );
            }

            if (trailVertices.length < 9) {
                continue;
            }

            batches.push({
                color: Array.isArray(history.color) ? history.color.slice() : MISSION_ALTITUDE_COLOR.slice(),
                vertices: new Float32Array(trailVertices),
                vertexCount: Math.floor(trailVertices.length / 3)
            });
        }
        return batches;
    }

    function refreshVehicleTrailsInLayer() {
        if (!missionLayerState) {
            resetMissionLayerState();
        }

        if (!map || !mapLoaded || !map.getLayer(MISSION_3D_LAYER_ID)) {
            return;
        }

        const origin = resolveTrailOrigin();
        const trailBatches = buildVehicleTrailBatches(origin);
        setMissionTrailGeometry(trailBatches);
    }

    function appendTubeSegmentTriangles(triangleVertices, start, end, radiusWorld, radialSegments) {
        const deltaX = end.x - start.x;
        const deltaY = end.y - start.y;
        const deltaZ = end.z - start.z;
        const length = Math.sqrt((deltaX * deltaX) + (deltaY * deltaY) + (deltaZ * deltaZ));
        if (!Number.isFinite(length) || length <= 1e-12) {
            return;
        }

        const safeRadius = Math.max(radiusWorld, 1e-10);
        const segments = Math.max(3, Math.floor(radialSegments));
        const invLength = 1.0 / length;
        const dirX = deltaX * invLength;
        const dirY = deltaY * invLength;
        const dirZ = deltaZ * invLength;

        let refX = 0.0;
        let refY = 0.0;
        let refZ = 1.0;
        if (Math.abs(dirZ) > 0.92) {
            refX = 0.0;
            refY = 1.0;
            refZ = 0.0;
        }

        let uX = (dirY * refZ) - (dirZ * refY);
        let uY = (dirZ * refX) - (dirX * refZ);
        let uZ = (dirX * refY) - (dirY * refX);
        const uLength = Math.sqrt((uX * uX) + (uY * uY) + (uZ * uZ));
        if (!Number.isFinite(uLength) || uLength <= 1e-12) {
            return;
        }

        uX /= uLength;
        uY /= uLength;
        uZ /= uLength;

        let vX = (dirY * uZ) - (dirZ * uY);
        let vY = (dirZ * uX) - (dirX * uZ);
        let vZ = (dirX * uY) - (dirY * uX);
        const vLength = Math.sqrt((vX * vX) + (vY * vY) + (vZ * vZ));
        if (!Number.isFinite(vLength) || vLength <= 1e-12) {
            return;
        }

        vX /= vLength;
        vY /= vLength;
        vZ /= vLength;

        for (let segmentIndex = 0; segmentIndex < segments; segmentIndex++) {
            const angle0 = (segmentIndex / segments) * Math.PI * 2.0;
            const angle1 = ((segmentIndex + 1) / segments) * Math.PI * 2.0;
            const cos0 = Math.cos(angle0);
            const sin0 = Math.sin(angle0);
            const cos1 = Math.cos(angle1);
            const sin1 = Math.sin(angle1);

            const off0X = (uX * cos0 + vX * sin0) * safeRadius;
            const off0Y = (uY * cos0 + vY * sin0) * safeRadius;
            const off0Z = (uZ * cos0 + vZ * sin0) * safeRadius;
            const off1X = (uX * cos1 + vX * sin1) * safeRadius;
            const off1Y = (uY * cos1 + vY * sin1) * safeRadius;
            const off1Z = (uZ * cos1 + vZ * sin1) * safeRadius;

            const start0X = start.x + off0X;
            const start0Y = start.y + off0Y;
            const start0Z = start.z + off0Z;
            const start1X = start.x + off1X;
            const start1Y = start.y + off1Y;
            const start1Z = start.z + off1Z;
            const end0X = end.x + off0X;
            const end0Y = end.y + off0Y;
            const end0Z = end.z + off0Z;
            const end1X = end.x + off1X;
            const end1Y = end.y + off1Y;
            const end1Z = end.z + off1Z;

            triangleVertices.push(
                start0X, start0Y, start0Z,
                start1X, start1Y, start1Z,
                end0X, end0Y, end0Z,
                end0X, end0Y, end0Z,
                start1X, start1Y, start1Z,
                end1X, end1Y, end1Z
            );
        }
    }

    function appendDashedTubeSegmentTriangles(
            triangleVertices,
            start,
            end,
            radiusWorld,
            radialSegments,
            dashLengthWorld,
            dashGapWorld) {
        const deltaX = end.x - start.x;
        const deltaY = end.y - start.y;
        const deltaZ = end.z - start.z;
        const length = Math.sqrt((deltaX * deltaX) + (deltaY * deltaY) + (deltaZ * deltaZ));
        if (!Number.isFinite(length) || length <= 1e-12) {
            return;
        }

        const safeDashLength = Math.max(Number(dashLengthWorld), 1e-9);
        const safeDashGap = Math.max(Number(dashGapWorld), 0.0);
        const stepLength = safeDashLength + safeDashGap;
        if (!Number.isFinite(stepLength) || stepLength <= 1e-12) {
            appendTubeSegmentTriangles(triangleVertices, start, end, radiusWorld, radialSegments);
            return;
        }

        const invLength = 1.0 / length;
        const dirX = deltaX * invLength;
        const dirY = deltaY * invLength;
        const dirZ = deltaZ * invLength;

        let cursor = 0.0;
        while (cursor < length - 1e-12) {
            const dashStart = cursor;
            const dashEnd = Math.min(length, dashStart + safeDashLength);
            if (dashEnd - dashStart > 1e-12) {
                const segStart = {
                    x: start.x + (dirX * dashStart),
                    y: start.y + (dirY * dashStart),
                    z: start.z + (dirZ * dashStart)
                };
                const segEnd = {
                    x: start.x + (dirX * dashEnd),
                    y: start.y + (dirY * dashEnd),
                    z: start.z + (dirZ * dashEnd)
                };
                appendTubeSegmentTriangles(
                    triangleVertices,
                    segStart,
                    segEnd,
                    radiusWorld,
                    radialSegments
                );
            }
            cursor += stepLength;
        }
    }

    function buildMissionRouteTriangles(triangleVertices, points, halfWidthWorld) {
        for (let index = 1; index < points.length; index++) {
            appendTubeSegmentTriangles(
                triangleVertices,
                points[index - 1],
                points[index],
                halfWidthWorld,
                MISSION_TUBE_RADIAL_SEGMENTS
            );
        }
    }

    function appendSegmentArrayTriangles(triangleVertices, segmentArray, halfWidthWorld, origin) {
        for (const segment of segmentArray) {
            const start = {
                x: segment.sx - origin.x,
                y: segment.sy - origin.y,
                z: segment.sz - origin.z
            };
            const end = {
                x: segment.ex - origin.x,
                y: segment.ey - origin.y,
                z: segment.ez - origin.z
            };
            appendTubeSegmentTriangles(
                triangleVertices,
                start,
                end,
                halfWidthWorld,
                MISSION_TUBE_RADIAL_SEGMENTS
            );
        }
    }

    function appendDashedSegmentArrayTriangles(triangleVertices, segmentArray, halfWidthWorld, origin) {
        for (const segment of segmentArray) {
            const start = {
                x: segment.sx - origin.x,
                y: segment.sy - origin.y,
                z: segment.sz - origin.z
            };
            const end = {
                x: segment.ex - origin.x,
                y: segment.ey - origin.y,
                z: segment.ez - origin.z
            };
            const latitudeForScale = Number.isFinite(Number(segment.latitude))
                ? Number(segment.latitude)
                : 0.0;
            const dashLengthWorld = Math.max(
                metersToMercatorUnits(MISSION_RTL_DASH_LENGTH_METERS, latitudeForScale),
                halfWidthWorld * 1.2
            );
            const dashGapWorld = Math.max(
                metersToMercatorUnits(MISSION_RTL_DASH_GAP_METERS, latitudeForScale),
                halfWidthWorld * 0.9
            );
            appendDashedTubeSegmentTriangles(
                triangleVertices,
                start,
                end,
                halfWidthWorld,
                MISSION_TUBE_RADIAL_SEGMENTS,
                dashLengthWorld,
                dashGapWorld
            );
        }
    }

    function appendConeTriangles(triangleVertices, center, direction, coneLengthWorld, coneRadiusWorld, radialSegments) {
        if (!center || !direction) {
            return;
        }

        const length = Math.max(Number(coneLengthWorld), 1e-12);
        const radius = Math.max(Number(coneRadiusWorld), 1e-12);
        const segments = Math.max(6, Math.floor(radialSegments));

        const dirLength = Math.sqrt(
            (direction.x * direction.x) +
            (direction.y * direction.y) +
            (direction.z * direction.z)
        );
        if (!Number.isFinite(dirLength) || dirLength <= 1e-12) {
            return;
        }

        const dirX = direction.x / dirLength;
        const dirY = direction.y / dirLength;
        const dirZ = direction.z / dirLength;

        let refX = 0.0;
        let refY = 0.0;
        let refZ = 1.0;
        if (Math.abs(dirZ) > 0.92) {
            refX = 0.0;
            refY = 1.0;
            refZ = 0.0;
        }

        let uX = (dirY * refZ) - (dirZ * refY);
        let uY = (dirZ * refX) - (dirX * refZ);
        let uZ = (dirX * refY) - (dirY * refX);
        const uLength = Math.sqrt((uX * uX) + (uY * uY) + (uZ * uZ));
        if (!Number.isFinite(uLength) || uLength <= 1e-12) {
            return;
        }
        uX /= uLength;
        uY /= uLength;
        uZ /= uLength;

        let vX = (dirY * uZ) - (dirZ * uY);
        let vY = (dirZ * uX) - (dirX * uZ);
        let vZ = (dirX * uY) - (dirY * uX);
        const vLength = Math.sqrt((vX * vX) + (vY * vY) + (vZ * vZ));
        if (!Number.isFinite(vLength) || vLength <= 1e-12) {
            return;
        }
        vX /= vLength;
        vY /= vLength;
        vZ /= vLength;

        const halfLength = 0.5 * length;
        const tip = {
            x: center.x + (dirX * halfLength),
            y: center.y + (dirY * halfLength),
            z: center.z + (dirZ * halfLength)
        };
        const baseCenter = {
            x: center.x - (dirX * halfLength),
            y: center.y - (dirY * halfLength),
            z: center.z - (dirZ * halfLength)
        };

        for (let segmentIndex = 0; segmentIndex < segments; segmentIndex++) {
            const angle0 = (segmentIndex / segments) * Math.PI * 2.0;
            const angle1 = ((segmentIndex + 1) / segments) * Math.PI * 2.0;

            const cos0 = Math.cos(angle0);
            const sin0 = Math.sin(angle0);
            const cos1 = Math.cos(angle1);
            const sin1 = Math.sin(angle1);

            const ring0 = {
                x: baseCenter.x + ((uX * cos0 + vX * sin0) * radius),
                y: baseCenter.y + ((uY * cos0 + vY * sin0) * radius),
                z: baseCenter.z + ((uZ * cos0 + vZ * sin0) * radius)
            };
            const ring1 = {
                x: baseCenter.x + ((uX * cos1 + vX * sin1) * radius),
                y: baseCenter.y + ((uY * cos1 + vY * sin1) * radius),
                z: baseCenter.z + ((uZ * cos1 + vZ * sin1) * radius)
            };

            // Cone side
            triangleVertices.push(
                tip.x, tip.y, tip.z,
                ring0.x, ring0.y, ring0.z,
                ring1.x, ring1.y, ring1.z
            );

            // Base cap
            triangleVertices.push(
                baseCenter.x, baseCenter.y, baseCenter.z,
                ring1.x, ring1.y, ring1.z,
                ring0.x, ring0.y, ring0.z
            );
        }
    }

    function _emptyMissionGeometry() {
        return {
            routeVertices: new Float32Array(0),
            verticalVertices: new Float32Array(0),
            verticalFallbackVertices: new Float32Array(0),
            directionVertices: new Float32Array(0),
            waypointVertices: new Float32Array(0),
            debugLabels: [],
            directionArrows: [],
            origin: { x: 0.0, y: 0.0, z: 0.0 }
        };
    }

    function buildMissionGeometry(missionDataOrList) {
        const routeVertices = [];
        const verticalVertices = [];
        const verticalFallbackVertices = [];
        const directionVertices = [];
        const waypointVertices = [];
        const debugLabels = [];
        const directionArrows = [];
        const missionLineRadiusMeters = 0.5 * MISSION_LINE_DIAMETER_METERS;
        let origin = null;
        let hasAnyGeometry = false;

        if (!map || !window.mapboxgl) {
            return _emptyMissionGeometry();
        }

        const missions = Array.isArray(missionDataOrList) ? missionDataOrList : [missionDataOrList];
        for (const missionData of missions) {
            if (!missionData || !Array.isArray(missionData.waypoints) || missionData.waypoints.length === 0) {
                continue;
            }

            const altitudeBiasMeters = Number.isFinite(Number(missionData.altitudeBiasMeters))
                ? Number(missionData.altitudeBiasMeters)
                : 0.0;
            const homeAltitudeAmsl = Number.isFinite(Number(missionData.homeAltitudeAmsl))
                ? Number(missionData.homeAltitudeAmsl)
                : 0.0;
            const routePointsWorld = [];
            const routePointsMeta = [];
            const verticalSegments = [];
            const verticalFallbackSegments = [];
            const verticalDashedSegments = [];
            const verticalDashedFallbackSegments = [];
            const directionConesWorld = [];

            for (const waypoint of missionData.waypoints) {
                const isSyntheticReturnHome = waypoint.syntheticReturnHome === true;
                const renderAltitudeAmsl = waypoint.altitudeAmsl + altitudeBiasMeters;
                const groundResolution = resolveGroundAltitudeAmsl(waypoint, homeAltitudeAmsl);
                const groundRenderAltitudeAmsl = groundResolution.groundRenderAltitudeAmsl;
                const groundLineRenderAltitudeAmsl = groundRenderAltitudeAmsl + GROUND_ATTACH_EPSILON_METERS;
                const mercatorPoint = mapboxgl.MercatorCoordinate.fromLngLat(
                    { lng: waypoint.longitude, lat: waypoint.latitude },
                    renderAltitudeAmsl
                );
                const groundPoint = mapboxgl.MercatorCoordinate.fromLngLat(
                    { lng: waypoint.longitude, lat: waypoint.latitude },
                    groundLineRenderAltitudeAmsl
                );
                if (!mercatorPoint || !groundPoint) {
                    continue;
                }

                routePointsWorld.push({
                    x: mercatorPoint.x,
                    y: mercatorPoint.y,
                    z: mercatorPoint.z
                });
                routePointsMeta.push({
                    latitude: waypoint.latitude,
                    longitude: waypoint.longitude,
                    x: mercatorPoint.x,
                    y: mercatorPoint.y,
                    z: mercatorPoint.z,
                    renderAltitudeAmsl: renderAltitudeAmsl,
                    groundRenderAltitudeAmsl: groundRenderAltitudeAmsl,
                    syntheticReturnHome: isSyntheticReturnHome
                });

                if (groundResolution.validTerrain) {
                    const targetSegments = isSyntheticReturnHome ? verticalDashedSegments : verticalSegments;
                    targetSegments.push({
                        sx: groundPoint.x,
                        sy: groundPoint.y,
                        sz: groundPoint.z,
                        ex: mercatorPoint.x,
                        ey: mercatorPoint.y,
                        ez: mercatorPoint.z,
                        latitude: waypoint.latitude
                    });
                } else {
                    const targetSegments = isSyntheticReturnHome ? verticalDashedFallbackSegments : verticalFallbackSegments;
                    targetSegments.push({
                        sx: groundPoint.x,
                        sy: groundPoint.y,
                        sz: groundPoint.z,
                        ex: mercatorPoint.x,
                        ey: mercatorPoint.y,
                        ez: mercatorPoint.z,
                        latitude: waypoint.latitude
                    });
                }

                if (!isSyntheticReturnHome) {
                    debugLabels.push({
                        longitude: waypoint.longitude,
                        latitude: waypoint.latitude,
                        altitudeAboveGround: Math.max(0.0, renderAltitudeAmsl - groundRenderAltitudeAmsl),
                        text: missionDebugText(waypoint, homeAltitudeAmsl)
                    });
                }
            }

            const routeSegments = [];
            if (routePointsMeta.length >= 2) {
                for (let routeIndex = 1; routeIndex < routePointsMeta.length; routeIndex++) {
                    const startPoint = routePointsMeta[routeIndex - 1];
                    const endPoint = routePointsMeta[routeIndex];
                    if (!startPoint || !endPoint) {
                        continue;
                    }
                    routeSegments.push({
                        startLatitude: startPoint.latitude,
                        startLongitude: startPoint.longitude,
                        endLatitude: endPoint.latitude,
                        endLongitude: endPoint.longitude,
                        startX: startPoint.x,
                        startY: startPoint.y,
                        startZ: startPoint.z,
                        endX: endPoint.x,
                        endY: endPoint.y,
                        endZ: endPoint.z,
                        startAltitudeAmsl: startPoint.renderAltitudeAmsl,
                        endAltitudeAmsl: endPoint.renderAltitudeAmsl,
                        startGroundAmsl: startPoint.groundRenderAltitudeAmsl,
                        endGroundAmsl: endPoint.groundRenderAltitudeAmsl
                    });
                }
            }

            if (Array.isArray(missionData.directionArrows) && routeSegments.length > 0) {
                for (const arrowSegment of missionData.directionArrows) {
                    if (!arrowSegment) {
                        continue;
                    }

                    const coord1Latitude = Number(arrowSegment.coord1Latitude);
                    const coord1Longitude = Number(arrowSegment.coord1Longitude);
                    const coord2Latitude = Number(arrowSegment.coord2Latitude);
                    const coord2Longitude = Number(arrowSegment.coord2Longitude);
                    if (!Number.isFinite(coord1Latitude) ||
                            !Number.isFinite(coord1Longitude) ||
                            !Number.isFinite(coord2Latitude) ||
                            !Number.isFinite(coord2Longitude)) {
                        continue;
                    }

                    const matchedSegment = findBestRouteSegmentForArrow(routeSegments, {
                        coord1Latitude: coord1Latitude,
                        coord1Longitude: coord1Longitude,
                        coord2Latitude: coord2Latitude,
                        coord2Longitude: coord2Longitude
                    });
                    if (!matchedSegment) {
                        continue;
                    }

                    const t = MISSION_DIRECTION_ARROW_FRACTION;
                    const interpolatedMercatorX = matchedSegment.startX + (t * (matchedSegment.endX - matchedSegment.startX));
                    const interpolatedMercatorY = matchedSegment.startY + (t * (matchedSegment.endY - matchedSegment.startY));
                    let arrowLatitude = Number.NaN;
                    let arrowLongitude = Number.NaN;

                    try {
                        const mercatorCoordinate = new mapboxgl.MercatorCoordinate(interpolatedMercatorX, interpolatedMercatorY, 0.0);
                        const lngLat = mercatorCoordinate.toLngLat();
                        if (lngLat && Number.isFinite(Number(lngLat.lat)) && Number.isFinite(Number(lngLat.lng))) {
                            arrowLatitude = clampLatitude(Number(lngLat.lat));
                            arrowLongitude = normalizeLongitude(Number(lngLat.lng));
                        }
                    } catch (_error) {
                        // Fall through to geographic interpolation fallback.
                    }

                    if (!Number.isFinite(arrowLatitude) || !Number.isFinite(arrowLongitude)) {
                        const fallbackCoordinate = interpolateGreatCircle(
                            matchedSegment.startLatitude,
                            matchedSegment.startLongitude,
                            matchedSegment.endLatitude,
                            matchedSegment.endLongitude,
                            t
                        );
                        arrowLatitude = fallbackCoordinate.latitude;
                        arrowLongitude = fallbackCoordinate.longitude;
                    }

                    const arrowAltitudeAmsl = matchedSegment.startAltitudeAmsl +
                        (t * (matchedSegment.endAltitudeAmsl - matchedSegment.startAltitudeAmsl));
                    const arrowX = matchedSegment.startX + (t * (matchedSegment.endX - matchedSegment.startX));
                    const arrowY = matchedSegment.startY + (t * (matchedSegment.endY - matchedSegment.startY));
                    const arrowZ = matchedSegment.startZ + (t * (matchedSegment.endZ - matchedSegment.startZ));
                    const sampledGroundAmsl = sampleTerrainAltitudeAmsl(
                        arrowLongitude,
                        arrowLatitude,
                        true
                    );
                    const fallbackGroundAmsl = matchedSegment.startGroundAmsl +
                        (t * (matchedSegment.endGroundAmsl - matchedSegment.startGroundAmsl));
                    const arrowGroundAmsl = Number.isFinite(sampledGroundAmsl)
                        ? sampledGroundAmsl
                        : (Number.isFinite(fallbackGroundAmsl) ? fallbackGroundAmsl : homeAltitudeAmsl);
                    const arrowAltitudeAboveGround = Math.max(0.0, arrowAltitudeAmsl - arrowGroundAmsl);
                    const arrowBearing = bearingDegrees(
                        matchedSegment.startLatitude,
                        matchedSegment.startLongitude,
                        matchedSegment.endLatitude,
                        matchedSegment.endLongitude
                    );

                    directionArrows.push({
                        latitude: arrowLatitude,
                        longitude: arrowLongitude,
                        altitudeAboveGround: arrowAltitudeAboveGround,
                        bearingDegrees: arrowBearing
                    });

                    directionConesWorld.push({
                        x: arrowX,
                        y: arrowY,
                        z: arrowZ,
                        latitude: arrowLatitude,
                        direction: {
                            x: matchedSegment.endX - matchedSegment.startX,
                            y: matchedSegment.endY - matchedSegment.startY,
                            z: matchedSegment.endZ - matchedSegment.startZ
                        }
                    });
                }
            }

            if (routePointsWorld.length < 1) {
                continue;
            }

            if (!origin) {
                origin = {
                    x: routePointsWorld[0].x,
                    y: routePointsWorld[0].y,
                    z: routePointsWorld[0].z
                };
            }

            const routePointsLocal = routePointsWorld.map(function (point) {
                return {
                    x: point.x - origin.x,
                    y: point.y - origin.y,
                    z: point.z - origin.z
                };
            });

            const referenceLatitude = missionData.waypoints.length > 0
                ? missionData.waypoints[0].latitude
                : 0.0;
            const lineHalfWidthWorld = Math.max(
                metersToMercatorUnits(missionLineRadiusMeters, referenceLatitude),
                1e-10
            );

            for (let pointIndex = 0; pointIndex < routePointsLocal.length; pointIndex++) {
                const point = routePointsLocal[pointIndex];
                const pointMeta = routePointsMeta[pointIndex];
                if (pointMeta && pointMeta.syntheticReturnHome === true) {
                    continue;
                }
                waypointVertices.push(point.x, point.y, point.z);
            }

            for (let routeIndex = 1; routeIndex < routePointsLocal.length; routeIndex++) {
                const startPoint = routePointsLocal[routeIndex - 1];
                const endPoint = routePointsLocal[routeIndex];
                const startMeta = routePointsMeta[routeIndex - 1];
                const endMeta = routePointsMeta[routeIndex];
                if (!startPoint || !endPoint || !startMeta || !endMeta) {
                    continue;
                }

                const isRtlReturnSegment = endMeta.syntheticReturnHome === true;
                if (isRtlReturnSegment) {
                    const latitudeForScale = 0.5 * (Number(startMeta.latitude) + Number(endMeta.latitude));
                    const dashLengthWorld = Math.max(
                        metersToMercatorUnits(MISSION_RTL_DASH_LENGTH_METERS, latitudeForScale),
                        lineHalfWidthWorld * 1.2
                    );
                    const dashGapWorld = Math.max(
                        metersToMercatorUnits(MISSION_RTL_DASH_GAP_METERS, latitudeForScale),
                        lineHalfWidthWorld * 0.9
                    );
                    appendDashedTubeSegmentTriangles(
                        routeVertices,
                        startPoint,
                        endPoint,
                        lineHalfWidthWorld,
                        MISSION_TUBE_RADIAL_SEGMENTS,
                        dashLengthWorld,
                        dashGapWorld
                    );
                } else {
                    appendTubeSegmentTriangles(
                        routeVertices,
                        startPoint,
                        endPoint,
                        lineHalfWidthWorld,
                        MISSION_TUBE_RADIAL_SEGMENTS
                    );
                }
            }

            appendSegmentArrayTriangles(verticalVertices, verticalSegments, lineHalfWidthWorld, origin);
            appendSegmentArrayTriangles(verticalFallbackVertices, verticalFallbackSegments, lineHalfWidthWorld, origin);
            appendDashedSegmentArrayTriangles(verticalVertices, verticalDashedSegments, lineHalfWidthWorld, origin);
            appendDashedSegmentArrayTriangles(verticalFallbackVertices, verticalDashedFallbackSegments, lineHalfWidthWorld, origin);

            for (const coneWorld of directionConesWorld) {
                const coneCenterLocal = {
                    x: coneWorld.x - origin.x,
                    y: coneWorld.y - origin.y,
                    z: coneWorld.z - origin.z
                };
                const coneLengthWorld = Math.max(
                    metersToMercatorUnits(MISSION_DIRECTION_CONE_LENGTH_METERS, coneWorld.latitude),
                    lineHalfWidthWorld * 3.0
                );
                const coneRadiusWorld = Math.max(
                    metersToMercatorUnits(MISSION_DIRECTION_CONE_RADIUS_METERS, coneWorld.latitude),
                    lineHalfWidthWorld * 1.2
                );
                appendConeTriangles(
                    directionVertices,
                    coneCenterLocal,
                    coneWorld.direction,
                    coneLengthWorld,
                    coneRadiusWorld,
                    MISSION_DIRECTION_CONE_RADIAL_SEGMENTS
                );
            }

            hasAnyGeometry = true;
        }

        if (!hasAnyGeometry || !origin) {
            return _emptyMissionGeometry();
        }

        return {
            routeVertices: new Float32Array(routeVertices),
            verticalVertices: new Float32Array(verticalVertices),
            verticalFallbackVertices: new Float32Array(verticalFallbackVertices),
            directionVertices: new Float32Array(directionVertices),
            waypointVertices: new Float32Array(waypointVertices),
            debugLabels: debugLabels,
            directionArrows: directionArrows,
            origin: origin
        };
    }

    function ensureMission3DLayer() {
        if (!map || !mapLoaded || !window.mapboxgl) {
            return false;
        }

        if (map.getLayer(MISSION_3D_LAYER_ID)) {
            return true;
        }

        resetMissionLayerState();

        mission3DLayer = {
            id: MISSION_3D_LAYER_ID,
            type: "custom",
            renderingMode: "3d",
            onAdd: function (_map, gl) {
                try {
                    const shaderProgram = createMissionProgram(gl);
                    missionLayerState.gl = gl;
                    missionLayerState.program = shaderProgram.program;
                    missionLayerState.positionAttribute = shaderProgram.positionAttribute;
                    missionLayerState.matrixUniform = shaderProgram.matrixUniform;
                    missionLayerState.colorUniform = shaderProgram.colorUniform;
                    missionLayerState.pointSizeUniform = shaderProgram.pointSizeUniform;
                    missionLayerState.renderModeUniform = shaderProgram.renderModeUniform;
                    missionLayerState.routeBuffer = gl.createBuffer();
                    missionLayerState.verticalBuffer = gl.createBuffer();
                    missionLayerState.verticalFallbackBuffer = gl.createBuffer();
                    missionLayerState.directionBuffer = gl.createBuffer();
                    missionLayerState.waypointBuffer = gl.createBuffer();
                    uploadMissionLayerBuffers();
                } catch (error) {
                    console.warn("mission layer onAdd failed:", error);
                }
            },
            render: function (gl, matrix) {
                if (!missionLayerState || !missionLayerState.program) {
                    return;
                }

                if (missionLayerNeedsUpload) {
                    uploadMissionLayerBuffers();
                }

                const drawMatrix = matrixWithTranslation(
                    matrix,
                    missionLayerState.originX,
                    missionLayerState.originY,
                    missionLayerState.originZ
                );

                gl.useProgram(missionLayerState.program);
                gl.uniformMatrix4fv(missionLayerState.matrixUniform, false, drawMatrix);
                gl.enable(gl.BLEND);
                gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
                gl.enable(gl.DEPTH_TEST);
                gl.depthMask(true);
                gl.enableVertexAttribArray(missionLayerState.positionAttribute);

                if (missionLayerState.routeVertexCount >= 3) {
                    gl.bindBuffer(gl.ARRAY_BUFFER, missionLayerState.routeBuffer);
                    gl.vertexAttribPointer(missionLayerState.positionAttribute, 3, gl.FLOAT, false, 0, 0);
                    gl.uniform4f(
                        missionLayerState.colorUniform,
                        MISSION_ROUTE_COLOR[0],
                        MISSION_ROUTE_COLOR[1],
                        MISSION_ROUTE_COLOR[2],
                        MISSION_ROUTE_COLOR[3]
                    );
                    gl.uniform1f(missionLayerState.renderModeUniform, 0.0);
                    gl.uniform1f(missionLayerState.pointSizeUniform, 1.0);
                    gl.drawArrays(gl.TRIANGLES, 0, missionLayerState.routeVertexCount);
                }

                if (missionLayerState.verticalVertexCount >= 3) {
                    gl.bindBuffer(gl.ARRAY_BUFFER, missionLayerState.verticalBuffer);
                    gl.vertexAttribPointer(missionLayerState.positionAttribute, 3, gl.FLOAT, false, 0, 0);
                    gl.uniform4f(
                        missionLayerState.colorUniform,
                        MISSION_ALTITUDE_COLOR[0],
                        MISSION_ALTITUDE_COLOR[1],
                        MISSION_ALTITUDE_COLOR[2],
                        MISSION_ALTITUDE_COLOR[3]
                    );
                    gl.uniform1f(missionLayerState.renderModeUniform, 0.0);
                    gl.uniform1f(missionLayerState.pointSizeUniform, 1.0);
                    gl.drawArrays(gl.TRIANGLES, 0, missionLayerState.verticalVertexCount);
                }

                if (missionLayerState.verticalFallbackVertexCount >= 3) {
                    gl.bindBuffer(gl.ARRAY_BUFFER, missionLayerState.verticalFallbackBuffer);
                    gl.vertexAttribPointer(missionLayerState.positionAttribute, 3, gl.FLOAT, false, 0, 0);
                    gl.uniform4f(
                        missionLayerState.colorUniform,
                        MISSION_ALTITUDE_FALLBACK_COLOR[0],
                        MISSION_ALTITUDE_FALLBACK_COLOR[1],
                        MISSION_ALTITUDE_FALLBACK_COLOR[2],
                        MISSION_ALTITUDE_FALLBACK_COLOR[3]
                    );
                    gl.uniform1f(missionLayerState.renderModeUniform, 0.0);
                    gl.uniform1f(missionLayerState.pointSizeUniform, 1.0);
                    gl.drawArrays(gl.TRIANGLES, 0, missionLayerState.verticalFallbackVertexCount);
                }

                if (missionLayerState.directionVertexCount >= 3) {
                    gl.bindBuffer(gl.ARRAY_BUFFER, missionLayerState.directionBuffer);
                    gl.vertexAttribPointer(missionLayerState.positionAttribute, 3, gl.FLOAT, false, 0, 0);
                    gl.uniform4f(
                        missionLayerState.colorUniform,
                        MISSION_ALTITUDE_COLOR[0],
                        MISSION_ALTITUDE_COLOR[1],
                        MISSION_ALTITUDE_COLOR[2],
                        MISSION_ALTITUDE_COLOR[3]
                    );
                    gl.uniform1f(missionLayerState.renderModeUniform, 0.0);
                    gl.uniform1f(missionLayerState.pointSizeUniform, 1.0);
                    gl.drawArrays(gl.TRIANGLES, 0, missionLayerState.directionVertexCount);
                }

                if (!declutterEnabled &&
                        Array.isArray(missionLayerState.trailBatches) &&
                        missionLayerState.trailBatches.length > 0) {
                    for (let trailIndex = 0; trailIndex < missionLayerState.trailBatches.length; trailIndex++) {
                        const trailBatch = missionLayerState.trailBatches[trailIndex];
                        const trailBuffer = missionLayerState.trailBuffers[trailIndex];
                        if (!trailBatch || !trailBuffer || !Number.isFinite(trailBatch.vertexCount) || trailBatch.vertexCount < 3) {
                            continue;
                        }

                        const color = Array.isArray(trailBatch.color) && trailBatch.color.length >= 4
                            ? trailBatch.color
                            : MISSION_ALTITUDE_COLOR;
                        gl.bindBuffer(gl.ARRAY_BUFFER, trailBuffer);
                        gl.vertexAttribPointer(missionLayerState.positionAttribute, 3, gl.FLOAT, false, 0, 0);
                        gl.uniform4f(
                            missionLayerState.colorUniform,
                            Number(color[0]),
                            Number(color[1]),
                            Number(color[2]),
                            Number(color[3])
                        );
                        gl.uniform1f(missionLayerState.renderModeUniform, 0.0);
                        gl.uniform1f(missionLayerState.pointSizeUniform, 1.0);
                        gl.drawArrays(gl.TRIANGLES, 0, trailBatch.vertexCount);
                    }
                }

                if (missionLayerState.waypointVertexCount >= 1) {
                    gl.bindBuffer(gl.ARRAY_BUFFER, missionLayerState.waypointBuffer);
                    gl.vertexAttribPointer(missionLayerState.positionAttribute, 3, gl.FLOAT, false, 0, 0);
                    gl.uniform4f(
                        missionLayerState.colorUniform,
                        MISSION_ALTITUDE_COLOR[0],
                        MISSION_ALTITUDE_COLOR[1],
                        MISSION_ALTITUDE_COLOR[2],
                        MISSION_ALTITUDE_COLOR[3]
                    );
                    gl.uniform1f(missionLayerState.renderModeUniform, 1.0);
                    gl.uniform1f(missionLayerState.pointSizeUniform, MISSION_POINT_SIZE_PX);
                    gl.drawArrays(gl.POINTS, 0, missionLayerState.waypointVertexCount);
                }

                gl.depthMask(true);
                gl.enable(gl.DEPTH_TEST);
            },
            onRemove: function (mapInstance, gl) {
                if (missionLayerState && missionLayerState.program) {
                    gl.deleteProgram(missionLayerState.program);
                }
                if (missionLayerState && missionLayerState.routeBuffer) {
                    gl.deleteBuffer(missionLayerState.routeBuffer);
                }
                if (missionLayerState && missionLayerState.verticalBuffer) {
                    gl.deleteBuffer(missionLayerState.verticalBuffer);
                }
                if (missionLayerState && missionLayerState.verticalFallbackBuffer) {
                    gl.deleteBuffer(missionLayerState.verticalFallbackBuffer);
                }
                if (missionLayerState && missionLayerState.directionBuffer) {
                    gl.deleteBuffer(missionLayerState.directionBuffer);
                }
                if (missionLayerState && missionLayerState.waypointBuffer) {
                    gl.deleteBuffer(missionLayerState.waypointBuffer);
                }
                if (missionLayerState && Array.isArray(missionLayerState.trailBuffers)) {
                    for (const trailBuffer of missionLayerState.trailBuffers) {
                        if (trailBuffer) {
                            gl.deleteBuffer(trailBuffer);
                        }
                    }
                }
                resetMissionLayerState();
                mission3DLayer = null;
            }
        };

        try {
            map.addLayer(mission3DLayer);
            return true;
        } catch (error) {
            console.warn("failed to add mission 3D layer:", error);
            mission3DLayer = null;
            resetMissionLayerState();
            return false;
        }
    }

    function removeMission3DLayer() {
        if (!map) {
            pendingMissionData = null;
            return;
        }

        if (map.getLayer(MISSION_3D_LAYER_ID)) {
            map.removeLayer(MISSION_3D_LAYER_ID);
        }
        mission3DLayer = null;
        resetMissionLayerState();
        removeMissionDebugLayer();
        removeMissionDirectionLayer();
        pendingMissionData = null;
        map.triggerRepaint();
    }

    function applyMissionsData(missionsData) {
        const normalizedMissions = normalizeMissionsData(missionsData);
        const hasWaypoints = normalizedMissions.some(function (mission) {
            return mission && Array.isArray(mission.waypoints) && mission.waypoints.length > 0;
        });
        if (!hasWaypoints) {
            removeMission3DLayer();
            return false;
        }

        pendingMissionData = normalizedMissions;
        if (!map || !mapLoaded) {
            return false;
        }

        if (!ensureMission3DLayer()) {
            return false;
        }

        const geometry = buildMissionGeometry(normalizedMissions);
        setMissionLayerGeometry(
            geometry.routeVertices,
            geometry.verticalVertices,
            geometry.verticalFallbackVertices,
            geometry.directionVertices,
            geometry.waypointVertices,
            geometry.origin
        );
        refreshVehicleTrailsInLayer();
        updateMissionDebugLayer(geometry.debugLabels);
        removeMissionDirectionLayer();
        pendingMissionData = null;
        map.triggerRepaint();
        return true;
    }

    function applyMissionData(missionData) {
        if (!missionData) {
            removeMission3DLayer();
            return false;
        }
        return applyMissionsData([missionData]);
    }

    function getCurrentMapViewState() {
        if (!map || !mapLoaded) {
            return null;
        }

        const center = map.getCenter();
        const zoom = map.getZoom();
        if (!center || !Number.isFinite(center.lat) || !Number.isFinite(center.lng) || !Number.isFinite(zoom)) {
            return null;
        }

        return {
            latitude: clampLatitude(center.lat),
            longitude: normalizeLongitude(center.lng),
            zoom: clampZoomLevel(zoom)
        };
    }

    function getScaleLineMeters(scaleLinePixelLength, yPixel) {
        if (!map || !mapLoaded) {
            return null;
        }

        const pixelLength = Number(scaleLinePixelLength);
        const y = Number(yPixel);
        if (!Number.isFinite(pixelLength) || pixelLength <= 0 || !Number.isFinite(y)) {
            return null;
        }

        const canvas = map.getCanvas();
        const canvasHeight = canvas && Number.isFinite(Number(canvas.height))
            ? Number(canvas.height)
            : Number.NaN;
        const clampedY = Number.isFinite(canvasHeight) ? clampValue(y, 0, canvasHeight) : y;

        const leftCoord = map.unproject([0, clampedY]);
        const rightCoord = map.unproject([pixelLength, clampedY]);
        if (!leftCoord || !rightCoord) {
            return null;
        }

        const leftLat = Number(leftCoord.lat);
        const leftLon = Number(leftCoord.lng);
        const rightLat = Number(rightCoord.lat);
        const rightLon = Number(rightCoord.lng);
        if (!Number.isFinite(leftLat) ||
                !Number.isFinite(leftLon) ||
                !Number.isFinite(rightLat) ||
                !Number.isFinite(rightLon)) {
            return null;
        }

        return greatCircleDistanceMeters(leftLat, leftLon, rightLat, rightLon);
    }

    function applyMapViewState(mapViewState) {
        const normalized = normalizeMapViewState(mapViewState);
        if (!normalized) {
            return false;
        }

        if (!map || !mapLoaded) {
            pendingMapViewState = normalized;
            return false;
        }

        const pitch = Number.isFinite(map.getPitch()) ? map.getPitch() : DEFAULT_PITCH_DEGREES;
        const bearing = Number.isFinite(map.getBearing()) ? map.getBearing() : DEFAULT_BEARING_DEGREES;

        suppressInteractionTrackingTemporarily(PROGRAMMATIC_MOVE_EVENT_SUPPRESS_MS);
        isApplyingExternalMapView = true;
        try {
            map.jumpTo({
                center: [normalized.longitude, normalized.latitude],
                zoom: normalized.zoom,
                pitch: pitch,
                bearing: bearing
            });
        } finally {
            isApplyingExternalMapView = false;
        }

        pendingMapViewState = null;
        hasUserInteractedSinceExternalSync = false;
        map.triggerRepaint();
        return true;
    }

    function suppressFollowTrackingTemporarily(holdoffMs) {
        if (followVehicleEnabled !== true) {
            return;
        }

        const durationMs = Number(holdoffMs);
        const effectiveHoldoffMs =
            Number.isFinite(durationMs) && durationMs > 0
                ? durationMs
                : FOLLOW_USER_PAN_HOLDOFF_MS;
        const untilMs = Date.now() + effectiveHoldoffMs;
        if (!Number.isFinite(followTrackingSuppressUntilMs) || untilMs > followTrackingSuppressUntilMs) {
            followTrackingSuppressUntilMs = untilMs;
        }
    }

    function suppressAutoPanTrackingTemporarily(holdoffMs) {
        if (autoPanEnabled !== true || followVehicleEnabled === true) {
            return;
        }

        const durationMs = Number(holdoffMs);
        const effectiveHoldoffMs =
            Number.isFinite(durationMs) && durationMs > 0
                ? durationMs
                : AUTO_PAN_USER_HOLDOFF_MS;
        const untilMs = Date.now() + effectiveHoldoffMs;
        if (!Number.isFinite(autoPanTrackingSuppressUntilMs) || untilMs > autoPanTrackingSuppressUntilMs) {
            autoPanTrackingSuppressUntilMs = untilMs;
        }
    }

    function suppressInteractionTrackingTemporarily(durationMs) {
        const requestedMs = Number(durationMs);
        if (!Number.isFinite(requestedMs) || requestedMs <= 0) {
            return;
        }

        const untilMs = Date.now() + requestedMs;
        if (!Number.isFinite(interactionTrackingSuppressUntilMs) || untilMs > interactionTrackingSuppressUntilMs) {
            interactionTrackingSuppressUntilMs = untilMs;
        }
    }

    function markUserInteraction(potentialCenterChange) {
        hasUserInteractedSinceExternalSync = true;
        // Manual interaction should temporarily override both follow and auto-pan.
        // Mapbox can emit rotate/pitch gestures without a reliable center delta,
        // so suppress recentering on all gesture starts and move events.
        suppressFollowTrackingTemporarily(FOLLOW_USER_PAN_HOLDOFF_MS);
        suppressAutoPanTrackingTemporarily(AUTO_PAN_USER_HOLDOFF_MS);
    }

    function setupInteractionTracking() {
        if (!map) {
            return;
        }

        const onManualInteraction = function (potentialCenterChange, guaranteedUserInput) {
            if (isApplyingExternalMapView) {
                return;
            }
            if (guaranteedUserInput !== true && Date.now() < interactionTrackingSuppressUntilMs) {
                return;
            }
            markUserInteraction(potentialCenterChange);
        };

        const immediateOverrideEvents = [
            "mousedown",
            "touchstart",
            "dragstart",
            "rotatestart",
            "pitchstart",
            "zoomstart",
            "wheel"
        ];
        for (const eventName of immediateOverrideEvents) {
            map.on(eventName, function () {
                onManualInteraction(true, true);
            });
        }

        map.on("movestart", function () {
            onManualInteraction(false, false);
        });

        map.on("move", function () {
            onManualInteraction(true, false);
        });

        map.on("moveend", function () {
            onManualInteraction(true, false);
        });
    }

    window.__qgcApplyStreaming3DConfig = function (config) {
        hasReceivedExternalConfig = true;
        applyStreamingConfig(config);
        if (!validateToken(false)) {
            setError(MISSING_TOKEN_MESSAGE);
            return;
        }

        if (activeStatusType === "error") {
            setStatus("", "");
        }

        // Wait for both token and initial 2D map state before creating the map.
        maybeCreateMapIfReady();
    };

    window.__qgcOnViewerActivated = function () {
        if (!map) {
            return;
        }

        map.resize();
        map.triggerRepaint();
    };

    window.__qgcSetMapViewState = function (mapViewState) {
        const normalized = normalizeMapViewState(mapViewState);
        if (!normalized) {
            return false;
        }

        hasReceivedExternalMapView = true;
        pendingMapViewState = normalized;
        if (!map || !mapLoaded) {
            maybeCreateMapIfReady();
            return false;
        }

        return applyMapViewState(normalized);
    };

    window.__qgcSetVehicleState = function (vehicleState) {
        window.__qgcVehicleState = vehicleState || null;
        window.__qgcVehiclesState = window.__qgcVehicleState ? [window.__qgcVehicleState] : [];
        return applyVehicleState(window.__qgcVehicleState);
    };

    window.__qgcSetVehiclesState = function (vehicleStates) {
        window.__qgcVehiclesState = Array.isArray(vehicleStates) ? vehicleStates : [];
        if ((!window.__qgcVehiclesState || window.__qgcVehiclesState.length === 0) && window.__qgcVehicleState) {
            window.__qgcVehiclesState = [window.__qgcVehicleState];
        }
        return applyVehiclesState(window.__qgcVehiclesState);
    };

    window.__qgcCenterOnVehicle = function (centerRequest) {
        return centerOnVehicle(centerRequest);
    };

    window.__qgcSetFollowVehicleEnabled = function (enabled) {
        return setFollowVehicleEnabled(enabled);
    };

    window.__qgcSetAutoPanEnabled = function (enabled) {
        return setAutoPanEnabled(enabled);
    };

    window.__qgcSetDeclutterEnabled = function (enabled) {
        return setDeclutterEnabled(enabled);
    };

    window.__qgcClearVehicleState = function () {
        window.__qgcVehiclesState = [];
        window.__qgcVehicleState = null;
        pendingVehicleState = null;
        removeVehicleMarker();
        return true;
    };

    window.__qgcSetMissionData = function (missionData) {
        window.__qgcMissionData = missionData || null;
        window.__qgcMissionsData = window.__qgcMissionData ? [window.__qgcMissionData] : [];
        return applyMissionData(window.__qgcMissionData);
    };

    window.__qgcSetMissionsData = function (missionsData) {
        window.__qgcMissionsData = Array.isArray(missionsData) ? missionsData : [];
        window.__qgcMissionData = (window.__qgcMissionsData.length > 0)
            ? window.__qgcMissionsData[0]
            : null;
        return applyMissionsData(window.__qgcMissionsData);
    };

    window.__qgcClearMissionData = function () {
        window.__qgcMissionsData = [];
        window.__qgcMissionData = null;
        removeMission3DLayer();
        return true;
    };

    window.__qgcGetMapViewState = function () {
        return getCurrentMapViewState();
    };

    window.__qgcGetStableMapViewState = function () {
        return getCurrentMapViewState();
    };

    window.__qgcGetScaleLineMeters = function (scaleLinePixelLength, yPixel) {
        return getScaleLineMeters(scaleLinePixelLength, yPixel);
    };

    window.__qgcConsumeMapViewStateIfInteracted = function () {
        if (!hasUserInteractedSinceExternalSync) {
            return null;
        }

        const mapViewState = getCurrentMapViewState();
        hasUserInteractedSinceExternalSync = false;
        return mapViewState;
    };

    function setupHomeButton() {
        if (!homeButton) {
            return;
        }

        homeButton.addEventListener("click", function () {
            const targetState = normalizeMapViewState(window.__qgcMapViewState || pendingMapViewState || defaultMapViewState);
            if (targetState) {
                applyMapViewState(targetState);
            }
        });
    }

    function createMap() {
        if (map || mapInitializing) {
            return;
        }

        if (!window.mapboxgl) {
            setError("Could not load Mapbox GL JS from the internet source.");
            return;
        }

        try {
            mapInitializing = true;
            applyStreamingConfig(window.__qgcStreaming3DConfig || {});
            if (!validateToken(false)) {
                if (hasReceivedExternalConfig) {
                    setError(MISSING_TOKEN_MESSAGE);
                }
                mapInitializing = false;
                return;
            }

            if (!hasInitialMapViewState()) {
                if (hasReceivedExternalMapView) {
                    console.warn("initial map view state is invalid");
                }
                mapInitializing = false;
                return;
            }

            mapboxgl.accessToken = streamingConfig.token;

            const initialMapViewState =
                normalizeMapViewState(window.__qgcMapViewState || pendingMapViewState) ||
                defaultMapViewState;
            defaultMapViewState = initialMapViewState;

            map = new mapboxgl.Map({
                container: "globe",
                style: DEFAULT_STYLE_URL,
                center: [initialMapViewState.longitude, initialMapViewState.latitude],
                zoom: initialMapViewState.zoom,
                pitch: DEFAULT_PITCH_DEGREES,
                bearing: DEFAULT_BEARING_DEGREES,
                projection: "mercator",
                minZoom: MIN_MAP_ZOOM,
                maxZoom: MAX_MAP_ZOOM,
                maxPitch: 85,
                antialias: false,
                attributionControl: false,
                hash: false,
                fadeDuration: 0,
                renderWorldCopies: false
            });

            configureInteractionHandlers();

            map.on("load", function () {
                mapLoaded = true;
                mapInitializing = false;
                mapDeclutterLayerVisibilityCache.clear();
                clearWarning();
                setStatus("", "");
                configureInteractionHandlers();
                installMapboxTerrainAndBuildings();
                applyDeclutterState();
                setupInteractionTracking();
                if (pendingMapViewState) {
                    applyMapViewState(pendingMapViewState);
                }
                if ((window.__qgcVehiclesState && window.__qgcVehiclesState.length > 0) ||
                        (window.__qgcVehicleState) ||
                        (pendingVehicleState && pendingVehicleState.length > 0)) {
                    applyVehiclesState(window.__qgcVehiclesState || pendingVehicleState || (window.__qgcVehicleState ? [window.__qgcVehicleState] : []));
                }
                if (pendingCenterOnVehicleRequest) {
                    centerOnVehicle(pendingCenterOnVehicleRequest);
                }
                if ((window.__qgcMissionsData && window.__qgcMissionsData.length > 0) ||
                        Array.isArray(window.__qgcMissionsData) ||
                        (pendingMissionData && pendingMissionData.length > 0)) {
                    const missionsPayload = Array.isArray(window.__qgcMissionsData)
                        ? window.__qgcMissionsData
                        : (pendingMissionData || (window.__qgcMissionData ? [window.__qgcMissionData] : []));
                    applyMissionsData(missionsPayload);
                }
                logGlRendererInfo();
                window.__qgcOnViewerActivated();
            });

            map.on("style.load", function () {
                if (mapLoaded) {
                    installMapboxTerrainAndBuildings();
                    mapDeclutterLayerVisibilityCache.clear();
                    applyDeclutterState();
                    if ((window.__qgcMissionsData && window.__qgcMissionsData.length > 0) ||
                            Array.isArray(window.__qgcMissionsData) ||
                            (pendingMissionData && pendingMissionData.length > 0)) {
                        const missionsPayload = Array.isArray(window.__qgcMissionsData)
                            ? window.__qgcMissionsData
                            : (pendingMissionData || (window.__qgcMissionData ? [window.__qgcMissionData] : []));
                        applyMissionsData(missionsPayload);
                    }
                }
            });

            map.on("error", function (event) {
                const errorDetail = event && event.error ? event.error : event;
                console.warn("map error:", errorDetail);
                const message = String(errorDetail && errorDetail.message ? errorDetail.message : errorDetail || "");
                const status = Number(errorDetail && (errorDetail.status || errorDetail.statusCode));
                if (status === 401 || /access token|unauthorized|forbidden/i.test(message)) {
                    setError("Mapbox access token is invalid or unauthorized.");
                }
            });
        } catch (error) {
            mapInitializing = false;
            const message = error && (error.stack || error.message) ? (error.stack || error.message) : String(error);
            console.warn("createMap failed:", message);
            setError("Unable to initialize streamed 3D map view.");
        }
    }

    window.addEventListener("error", function (event) {
        const errorSummary = {
            message: event && event.message ? event.message : "",
            filename: event && event.filename ? event.filename : "",
            lineno: event && Number.isFinite(event.lineno) ? event.lineno : 0,
            colno: event && Number.isFinite(event.colno) ? event.colno : 0,
            error: event && event.error ? event.error : null
        };
        console.warn("window error:", errorSummary);
        setError("An unexpected error occurred while running streamed 3D view.");
    });

    window.addEventListener("unhandledrejection", function (event) {
        const reason = event && event.reason ? event.reason : "unknown";
        console.warn("unhandled rejection:", reason);
    });

    resetMissionLayerState();
    setupHomeButton();
    maybeCreateMapIfReady();
})();
