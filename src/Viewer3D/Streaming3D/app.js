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

    const originalConsoleError = console.error.bind(console);
    const originalConsoleWarn = console.warn.bind(console);
    console.error = function (...args) {
        originalConsoleError(args.map(formatConsoleArg).join(" | "));
    };
    console.warn = function (...args) {
        originalConsoleWarn(args.map(formatConsoleArg).join(" | "));
    };

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

    const MIN_MAP_ZOOM = 2.0;
    const MAX_MAP_ZOOM = 20.0;
    const DEFAULT_PITCH_DEGREES = 65.0;
    const DEFAULT_BEARING_DEGREES = 0.0;
    const DEFAULT_STYLE_URL = "mapbox://styles/mapbox/standard-satellite";

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
                setError("Mapbox token is required for streamed 3D mode.");
            }
            return false;
        }

        return true;
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
            exaggeration: 1.12
        });

        if (typeof map.setConfigProperty === "function") {
            try {
                map.setConfigProperty("basemap", "show3dObjects", true);
            } catch (configError) {
                console.warn("basemap 3d object config skipped:", configError);
            }
        }

        if (!map.getLayer("qgc-3d-buildings") && map.getSource("composite")) {
            const style = map.getStyle();
            const firstLabelLayerId = style && style.layers
                ? style.layers.find(function (layer) { return layer.type === "symbol"; })
                : null;

            map.addLayer({
                id: "qgc-3d-buildings",
                source: "composite",
                "source-layer": "building",
                filter: ["==", ["get", "extrude"], "true"],
                type: "fill-extrusion",
                minzoom: 15,
                paint: {
                    "fill-extrusion-color": "#d7dbe2",
                    "fill-extrusion-height": [
                        "interpolate", ["linear"], ["zoom"],
                        15, 0,
                        16, ["coalesce", ["get", "height"], 10]
                    ],
                    "fill-extrusion-base": [
                        "interpolate", ["linear"], ["zoom"],
                        15, 0,
                        16, ["coalesce", ["get", "min_height"], 0]
                    ],
                    "fill-extrusion-opacity": 0.72
                }
            }, firstLabelLayerId ? firstLabelLayerId.id : undefined);
        }

        if (typeof map.setFog === "function") {
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
        applyStreamingConfig(config);
        // Token may arrive after initial startup attempt. Retry map init automatically.
        if (!map && !mapInitializing && validateToken(false)) {
            createMap();
        }
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

        pendingMapViewState = normalized;
        if (!map || !mapLoaded) {
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
            if (!validateToken(true)) {
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
                minZoom: MIN_MAP_ZOOM,
                maxZoom: MAX_MAP_ZOOM,
                maxPitch: 85,
                antialias: true,
                attributionControl: false,
                hash: false
            });

            map.on("load", function () {
                mapLoaded = true;
                mapInitializing = false;
                clearWarning();
                setStatus("", "");
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
    createMap();
})();
