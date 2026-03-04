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
    let defaultMapViewState = {
        latitude: 0.0,
        longitude: 0.0,
        zoom: 3.0
    };
    let hasUserInteractedSinceExternalSync = false;
    let isApplyingExternalMapView = false;
    let hasReceivedExternalConfig = false;
    let hasReceivedExternalMapView = false;

    const MIN_MAP_ZOOM = 2.0;
    const MAX_MAP_ZOOM = 20.0;
    const DEFAULT_PITCH_DEGREES = 65.0;
    const DEFAULT_BEARING_DEGREES = 0.0;
    const DEFAULT_STYLE_URL = "mapbox://styles/mapbox/standard-satellite";
    const WHEEL_ZOOM_RATE = 1 / 1500;
    const TRACKPAD_ZOOM_RATE = 1 / 260;
    const PAN_MAX_SPEED = 760;
    const PAN_DECELERATION = 9800;
    const ROTATE_MAX_SPEED = 210;
    const ROTATE_DECELERATION = 4800;
    const TERRAIN_EXAGGERATION = 1.08;
    const ENABLE_ATMOSPHERIC_FOG = false;
    const BUILDING_LAYER_OPACITY = 0.6;
    const BUILDING_VECTOR_SOURCE_ID = "qgc-buildings-source";
    const BUILDING_VECTOR_SOURCE_URL = "mapbox://mapbox.mapbox-streets-v8";
    const BUILDING_GROWTH_START_ZOOM = 14.6;
    const BUILDING_GROWTH_END_ZOOM = 16.0;
    const BUILDING_GROWTH_CURVE = 1.6;
    const MISSING_TOKEN_MESSAGE = "Mapbox token is required for streamed 3D mode.";

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

    function markUserInteraction(potentialCenterChange) {
        hasUserInteractedSinceExternalSync = true;
    }

    function setupInteractionTracking() {
        if (!map) {
            return;
        }

        map.on("movestart", function () {
            if (isApplyingExternalMapView) {
                return;
            }
            markUserInteraction(false);
        });

        map.on("move", function () {
            if (isApplyingExternalMapView) {
                return;
            }
            markUserInteraction(true);
        });

        map.on("moveend", function () {
            if (isApplyingExternalMapView) {
                return;
            }
            markUserInteraction(true);
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

    window.__qgcGetMapViewState = function () {
        return getCurrentMapViewState();
    };

    window.__qgcGetStableMapViewState = function () {
        return getCurrentMapViewState();
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
                clearWarning();
                setStatus("", "");
                configureInteractionHandlers();
                installMapboxTerrainAndBuildings();
                setupInteractionTracking();
                if (pendingMapViewState) {
                    applyMapViewState(pendingMapViewState);
                }
                logGlRendererInfo();
                window.__qgcOnViewerActivated();
            });

            map.on("style.load", function () {
                if (mapLoaded) {
                    installMapboxTerrainAndBuildings();
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

    setupHomeButton();
    maybeCreateMapIfReady();
})();
