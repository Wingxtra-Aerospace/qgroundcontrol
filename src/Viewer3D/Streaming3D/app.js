(function () {
    const statusElement = document.getElementById("status");

    let viewer = null;
    let interactionHandler = null;
    let streamingConfig = {
        provider: "Cesium",
        token: ""
    };
    let activeStatusType = "";
    let pendingMapViewState = null;
    let hasUserInteractedSinceExternalSync = false;
    let hasPotentialCenterChangeSinceExternalSync = false;
    let lastSyncedMapCenter = null;

    const MIN_MAP_ZOOM = 2.0;
    const MAX_MAP_ZOOM = 20.0;
    const EARTH_METERS_PER_PIXEL_AT_Z0 = 156543.03392804097;
    const ZOOM_SYNC_CALIBRATION = 0.35;
    const DEFAULT_SYNC_PITCH_RAD = Cesium.Math.toRadians(-65.0);
    const MIN_SYNC_PITCH_ABS_RAD = Cesium.Math.toRadians(1.0);
    const RELIABLE_CENTER_PITCH_RAD = Cesium.Math.toRadians(-55.0);
    const MIN_DELIBERATE_CENTER_MOVE_KM = 0.02;
    const MAX_UNRELIABLE_CENTER_MOVE_KM = 3000.0;
    const CONTROLS_AUTO_HIDE_DELAY_MS = 1800;

    let controlsHideTimer = null;

    function clampValue(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value));
    }

    function normalizeLongitudeDelta(longitudeDelta) {
        if (!Number.isFinite(longitudeDelta)) {
            return 0;
        }

        return ((longitudeDelta + 540) % 360) - 180;
    }

    function distanceKmBetweenCoordinates(first, second) {
        if (!first || !second) {
            return Number.POSITIVE_INFINITY;
        }

        const firstLat = Number(first.latitude);
        const firstLon = Number(first.longitude);
        const secondLat = Number(second.latitude);
        const secondLon = Number(second.longitude);
        if (!Number.isFinite(firstLat) || !Number.isFinite(firstLon) ||
                !Number.isFinite(secondLat) || !Number.isFinite(secondLon)) {
            return Number.POSITIVE_INFINITY;
        }

        const earthRadiusKm = 6371.0088;
        const deltaLatRad = Cesium.Math.toRadians(secondLat - firstLat);
        const deltaLonRad = Cesium.Math.toRadians(normalizeLongitudeDelta(secondLon - firstLon));
        const lat1Rad = Cesium.Math.toRadians(firstLat);
        const lat2Rad = Cesium.Math.toRadians(secondLat);
        const halfChord =
            Math.sin(deltaLatRad / 2.0) * Math.sin(deltaLatRad / 2.0) +
            Math.cos(lat1Rad) * Math.cos(lat2Rad) *
            Math.sin(deltaLonRad / 2.0) * Math.sin(deltaLonRad / 2.0);
        const centralAngle = 2.0 * Math.atan2(Math.sqrt(halfChord), Math.sqrt(Math.max(1.0 - halfChord, 0.0)));

        return earthRadiusKm * centralAngle;
    }

    function normalizeConfig(config) {
        const providerValue = config && config.provider !== undefined && config.provider !== null
            ? String(config.provider).trim()
            : "";
        const tokenValue = config && config.token !== undefined && config.token !== null
            ? String(config.token).trim()
            : "";

        return {
            provider: providerValue.length > 0 ? providerValue : "Cesium",
            token: tokenValue
        };
    }

    function applyStreamingConfig(config) {
        streamingConfig = normalizeConfig(config);
        if (window.Cesium) {
            Cesium.Ion.defaultAccessToken = streamingConfig.token;
        }
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

    function setControlsVisible(visible) {
        if (!document || !document.body) {
            return;
        }

        document.body.classList.toggle("controls-visible", Boolean(visible));
    }

    function bumpControlsVisibility() {
        setControlsVisible(true);

        if (controlsHideTimer) {
            window.clearTimeout(controlsHideTimer);
        }

        controlsHideTimer = window.setTimeout(function () {
            setControlsVisible(false);
        }, CONTROLS_AUTO_HIDE_DELAY_MS);
    }

    function installControlsVisibilityHandlers() {
        const revealControls = function () {
            bumpControlsVisibility();
        };

        window.addEventListener("mousemove", revealControls, { passive: true });
        window.addEventListener("wheel", revealControls, { passive: true });
        window.addEventListener("touchstart", revealControls, { passive: true });
        window.addEventListener("keydown", revealControls);

        bumpControlsVisibility();
    }

    function onViewerActivated() {
        bumpControlsVisibility();
        if (viewer && viewer.scene) {
            viewer.scene.requestRender();
        }
    }

    function normalizeLongitude(longitude) {
        if (!Number.isFinite(longitude)) {
            return 0;
        }
        return (((longitude + 180) % 360) + 360) % 360 - 180;
    }

    function clampZoomLevel(zoom) {
        if (!Number.isFinite(zoom)) {
            return MIN_MAP_ZOOM;
        }
        return clampValue(zoom, MIN_MAP_ZOOM, MAX_MAP_ZOOM);
    }

    function clampLatitude(latitude) {
        if (!Number.isFinite(latitude)) {
            return 0;
        }
        return clampValue(latitude, -85.0, 85.0);
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

    function getCanvasHeight() {
        if (viewer && viewer.scene && viewer.scene.canvas && viewer.scene.canvas.clientHeight > 0) {
            return viewer.scene.canvas.clientHeight;
        }
        return 1080;
    }

    function getCameraVerticalFov() {
        if (!viewer || !viewer.scene || !viewer.scene.camera || !viewer.scene.camera.frustum) {
            return Cesium.Math.toRadians(60.0);
        }

        const frustum = viewer.scene.camera.frustum;
        if (Number.isFinite(frustum.fovy) && frustum.fovy > 0) {
            return frustum.fovy;
        }

        return Cesium.Math.toRadians(60.0);
    }

    function zoomToCameraHeightMeters(zoom, latitude) {
        const clampedZoom = clampZoomLevel(zoom);
        const adjustedZoom = clampedZoom + ZOOM_SYNC_CALIBRATION;
        const latRadians = clampLatitude(latitude) * Math.PI / 180.0;
        const metersPerPixel = EARTH_METERS_PER_PIXEL_AT_Z0 * Math.cos(latRadians) / Math.pow(2.0, adjustedZoom);
        const safeMetersPerPixel = Math.max(metersPerPixel, 0.01);
        const canvasHeight = getCanvasHeight();
        const verticalFov = getCameraVerticalFov();
        const range = (safeMetersPerPixel * canvasHeight) / (2.0 * Math.tan(verticalFov / 2.0));

        return Math.max(range, 50.0);
    }

    function cameraHeightMetersToZoom(heightMeters, latitude) {
        const safeHeight = Math.max(Number(heightMeters) || 0.0, 50.0);
        const latRadians = clampLatitude(latitude) * Math.PI / 180.0;
        const canvasHeight = getCanvasHeight();
        const verticalFov = getCameraVerticalFov();
        const metersPerPixel = (2.0 * safeHeight * Math.tan(verticalFov / 2.0)) / Math.max(canvasHeight, 1.0);
        const safeMetersPerPixel = Math.max(metersPerPixel, 0.0001);
        const numerator = EARTH_METERS_PER_PIXEL_AT_Z0 * Math.cos(latRadians);
        const zoom = Math.log2(Math.max(numerator / safeMetersPerPixel, 0.0001)) - ZOOM_SYNC_CALIBRATION;

        return clampZoomLevel(zoom);
    }

    function getCameraCenterCartographic() {
        if (!viewer || !viewer.scene || !viewer.scene.camera) {
            return null;
        }

        const scene = viewer.scene;
        const canvas = scene.canvas;
        if (canvas && canvas.clientWidth > 0 && canvas.clientHeight > 0) {
            // In horizon-tilted views, the exact viewport center can point above the globe.
            // Sample progressively lower vertical anchors to keep center sync stable.
            const sampleYFactors = [0.50, 0.62, 0.74, 0.84];
            const sampleX = canvas.clientWidth / 2.0;
            for (let i = 0; i < sampleYFactors.length; i++) {
                const samplePixel = new Cesium.Cartesian2(sampleX, canvas.clientHeight * sampleYFactors[i]);
                const ray = scene.camera.getPickRay(samplePixel);
                if (ray) {
                    const hit = scene.globe.pick(ray, scene);
                    if (hit) {
                        return Cesium.Cartographic.fromCartesian(hit);
                    }
                }

                const ellipsoidHit = scene.camera.pickEllipsoid(samplePixel, scene.globe.ellipsoid);
                if (ellipsoidHit) {
                    return Cesium.Cartographic.fromCartesian(ellipsoidHit);
                }
            }
        }

        return viewer.camera.positionCartographic;
    }

    function setMapViewState(mapViewState) {
        const normalized = normalizeMapViewState(mapViewState);
        if (!normalized) {
            return false;
        }

        if (!window.Cesium || !viewer || !viewer.camera) {
            pendingMapViewState = normalized;
            return false;
        }

        const heightMeters = zoomToCameraHeightMeters(normalized.zoom, normalized.latitude);
        const heading = Number.isFinite(viewer.camera.heading) ? viewer.camera.heading : 0.0;
        const existingPitch = Number.isFinite(viewer.camera.pitch) ? viewer.camera.pitch : DEFAULT_SYNC_PITCH_RAD;
        const clampedPitch = clampValue(existingPitch, Cesium.Math.toRadians(-89.0), Cesium.Math.toRadians(-1.0));
        const safePitchAbs = Math.max(Math.abs(clampedPitch), MIN_SYNC_PITCH_ABS_RAD);
        const safePitchSine = Math.max(Math.sin(safePitchAbs), 0.0001);
        const rangeMeters = Math.max(heightMeters / safePitchSine, 50.0);
        const target = Cesium.Cartesian3.fromDegrees(normalized.longitude, normalized.latitude, 0.0);

        viewer.camera.lookAt(target, new Cesium.HeadingPitchRange(heading, clampedPitch, rangeMeters));
        viewer.camera.lookAtTransform(Cesium.Matrix4.IDENTITY);
        viewer.scene.requestRender();
        pendingMapViewState = null;
        hasUserInteractedSinceExternalSync = false;
        hasPotentialCenterChangeSinceExternalSync = false;
        lastSyncedMapCenter = {
            latitude: normalized.latitude,
            longitude: normalized.longitude
        };

        return true;
    }

    function getCurrentCenterCandidate() {
        const centerCartographic = getCameraCenterCartographic();
        if (!centerCartographic) {
            return null;
        }

        return {
            latitude: clampLatitude(Cesium.Math.toDegrees(centerCartographic.latitude)),
            longitude: normalizeLongitude(Cesium.Math.toDegrees(centerCartographic.longitude))
        };
    }

    function getReliableCenterForSync(allowUnreliableUpdate) {
        if (!viewer || !viewer.camera) {
            return lastSyncedMapCenter;
        }

        const centerCandidate = getCurrentCenterCandidate();
        if (!centerCandidate) {
            return lastSyncedMapCenter;
        }

        if (isPitchReliableForMapSync() || allowUnreliableUpdate === true) {
            lastSyncedMapCenter = centerCandidate;
        }

        return lastSyncedMapCenter;
    }

    function isPitchReliableForMapSync() {
        if (!viewer || !viewer.camera) {
            return false;
        }

        const pitch = Number(viewer.camera.pitch);
        return Number.isFinite(pitch) && (pitch <= RELIABLE_CENTER_PITCH_RAD);
    }

    function getMapViewState(allowUnreliableCenterUpdate) {
        if (!viewer || !viewer.camera) {
            return null;
        }

        const center = getReliableCenterForSync(allowUnreliableCenterUpdate === true);
        if (!center) {
            return null;
        }
        const cameraCartographic = viewer.camera.positionCartographic;
        const heightMeters = cameraCartographic ? cameraCartographic.height : 1000.0;

        return {
            latitude: center.latitude,
            longitude: center.longitude,
            zoom: cameraHeightMetersToZoom(heightMeters, center.latitude)
        };
    }

    function setupInteractionTracking() {
        if (!viewer || !viewer.scene || !viewer.scene.canvas || !window.Cesium) {
            return;
        }

        if (interactionHandler) {
            interactionHandler.destroy();
            interactionHandler = null;
        }

        interactionHandler = new Cesium.ScreenSpaceEventHandler(viewer.scene.canvas);
        let activePointerButton = "";

        const markUserInteraction = function (potentialCenterChange) {
            hasUserInteractedSinceExternalSync = true;
            if (potentialCenterChange === true) {
                hasPotentialCenterChangeSinceExternalSync = true;
            }
        };

        interactionHandler.setInputAction(function () {
            activePointerButton = "left";
            markUserInteraction(false);
        }, Cesium.ScreenSpaceEventType.LEFT_DOWN);
        interactionHandler.setInputAction(function () {
            activePointerButton = "middle";
            markUserInteraction(false);
        }, Cesium.ScreenSpaceEventType.MIDDLE_DOWN);
        interactionHandler.setInputAction(function () {
            activePointerButton = "right";
            markUserInteraction(false);
        }, Cesium.ScreenSpaceEventType.RIGHT_DOWN);

        interactionHandler.setInputAction(function () {
            if (activePointerButton === "left" || activePointerButton === "middle") {
                markUserInteraction(true);
            }
        }, Cesium.ScreenSpaceEventType.MOUSE_MOVE);

        interactionHandler.setInputAction(function () {
            activePointerButton = "";
        }, Cesium.ScreenSpaceEventType.LEFT_UP);
        interactionHandler.setInputAction(function () {
            activePointerButton = "";
        }, Cesium.ScreenSpaceEventType.MIDDLE_UP);
        interactionHandler.setInputAction(function () {
            activePointerButton = "";
        }, Cesium.ScreenSpaceEventType.RIGHT_UP);

        interactionHandler.setInputAction(function () {
            markUserInteraction(false);
        }, Cesium.ScreenSpaceEventType.WHEEL);
        interactionHandler.setInputAction(function () {
            markUserInteraction(false);
        }, Cesium.ScreenSpaceEventType.PINCH_START);
    }

    window.__qgcSetMapViewState = function (mapViewState) {
        const normalized = normalizeMapViewState(mapViewState);
        if (!normalized) {
            return false;
        }

        if (!viewer) {
            pendingMapViewState = normalized;
            return false;
        }

        return setMapViewState(normalized);
    };

    window.__qgcGetMapViewState = function () {
        return getMapViewState(false);
    };

    window.__qgcGetStableMapViewState = function () {
        return getMapViewState(false);
    };

    window.__qgcConsumeMapViewStateIfInteracted = function () {
        if (!hasUserInteractedSinceExternalSync) {
            return null;
        }

        const allowUnreliableCenterUpdate = hasPotentialCenterChangeSinceExternalSync;
        const wasPitchReliable = isPitchReliableForMapSync();
        const previousCenter = lastSyncedMapCenter ? {
            latitude: lastSyncedMapCenter.latitude,
            longitude: lastSyncedMapCenter.longitude
        } : null;

        if (!wasPitchReliable && !allowUnreliableCenterUpdate) {
            hasUserInteractedSinceExternalSync = false;
            hasPotentialCenterChangeSinceExternalSync = false;
            return null;
        }

        const mapViewState = getMapViewState(allowUnreliableCenterUpdate);
        hasUserInteractedSinceExternalSync = false;
        hasPotentialCenterChangeSinceExternalSync = false;

        if (!mapViewState) {
            return null;
        }

        if (!wasPitchReliable && allowUnreliableCenterUpdate && previousCenter) {
            const centerDistanceKm = distanceKmBetweenCoordinates(previousCenter, mapViewState);
            if (!Number.isFinite(centerDistanceKm) ||
                    centerDistanceKm < MIN_DELIBERATE_CENTER_MOVE_KM ||
                    centerDistanceKm > MAX_UNRELIABLE_CENTER_MOVE_KM) {
                lastSyncedMapCenter = previousCenter;
                return null;
            }
        }

        return mapViewState;
    };

    function clearGlobeContainer() {
        const globeElement = document.getElementById("globe");
        if (globeElement) {
            globeElement.innerHTML = "";
        }
    }

    function buildViewerOptions(terrainProvider, compatibilityMode) {
        const options = {
            animation: false,
            baseLayerPicker: false,
            fullscreenButton: false,
            geocoder: false,
            homeButton: true,
            infoBox: false,
            navigationHelpButton: false,
            sceneModePicker: false,
            selectionIndicator: false,
            timeline: false,
            terrainProvider: terrainProvider,
            requestRenderMode: true
        };

        if (compatibilityMode === "webgl2-compat") {
            options.contextOptions = {
                webgl: {
                    antialias: false,
                    failIfMajorPerformanceCaveat: false,
                    powerPreference: "low-power"
                }
            };
        } else if (compatibilityMode === "webgl1-compat") {
            options.contextOptions = {
                requestWebgl1: true,
                webgl: {
                    antialias: false,
                    failIfMajorPerformanceCaveat: false,
                    powerPreference: "low-power"
                }
            };
        }

        return options;
    }

    function isWebGlInitializationError(error) {
        const message = String(error && error.message ? error.message : error || "");
        return /webgl|context|initialization failed|Error constructing CesiumWidget/i.test(message);
    }

    function createViewerInstance(terrainProvider, compatibilityMode) {
        clearGlobeContainer();
        return new Cesium.Viewer("globe", buildViewerOptions(terrainProvider, compatibilityMode));
    }

    function disableSkyVisualEffects() {
        if (!viewer || !viewer.scene) {
            return;
        }

        const scene = viewer.scene;
        if (scene.skyBox) {
            scene.skyBox.show = false;
        }
        if (scene.skyAtmosphere) {
            scene.skyAtmosphere.show = false;
        }
        if (scene.sun) {
            scene.sun.show = false;
        }
        if (scene.moon) {
            scene.moon.show = false;
        }
        if (scene.fog) {
            scene.fog.enabled = false;
        }
        if (scene.globe) {
            scene.globe.showGroundAtmosphere = false;
        }
        if (window.Cesium && Cesium.Color) {
            scene.backgroundColor = Cesium.Color.BLACK;
        }
    }

    async function installBaseImageryLayer() {
        if (!viewer) {
            return;
        }

        viewer.imageryLayers.removeAll();

        try {
            // NaturalEarthII is global coverage (including poles), used as underlay.
            const globalCoverageProvider = await Cesium.TileMapServiceImageryProvider.fromUrl(
                Cesium.buildModuleUrl("Assets/Textures/NaturalEarthII")
            );
            viewer.imageryLayers.addImageryProvider(globalCoverageProvider);
        } catch (globalCoverageError) {
            console.warn("Global fallback imagery error:", globalCoverageError);
        }

        const arcGisImageryProvider = new Cesium.UrlTemplateImageryProvider({
            url: "https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
            credit: "Esri"
        });

        viewer.imageryLayers.addImageryProvider(arcGisImageryProvider);
        viewer.scene.requestRender();
    }

    window.__qgcApplyStreaming3DConfig = function (config) {
        applyStreamingConfig(config);
    };

    window.__qgcOnViewerActivated = function () {
        onViewerActivated();
    };

    async function createViewer() {
        if (!window.Cesium) {
            setError("Could not load CesiumJS from the internet source.");
            return;
        }

        try {
            applyStreamingConfig(window.__qgcStreaming3DConfig || {});

            const terrainProvider = await Cesium.ArcGISTiledElevationTerrainProvider.fromUrl(
                "https://elevation3d.arcgis.com/arcgis/rest/services/WorldElevation3D/Terrain3D/ImageServer"
            );

            try {
                viewer = createViewerInstance(terrainProvider, false);
            } catch (primaryCreateError) {
                if (!isWebGlInitializationError(primaryCreateError)) {
                    throw primaryCreateError;
                }

                console.warn(primaryCreateError);
                setWarning("Primary WebGL path failed. Retrying in compatibility mode.");
                try {
                    viewer = createViewerInstance(terrainProvider, "webgl2-compat");
                } catch (secondaryCreateError) {
                    if (!isWebGlInitializationError(secondaryCreateError)) {
                        throw secondaryCreateError;
                    }

                    console.warn(secondaryCreateError);
                    setWarning("WebGL2 compatibility failed. Retrying with WebGL1 fallback.");
                    viewer = createViewerInstance(terrainProvider, "webgl1-compat");
                }
            }

            disableSkyVisualEffects();
            viewer.terrainProvider = terrainProvider;
            await installBaseImageryLayer();
            setupInteractionTracking();
            viewer.scene.globe.depthTestAgainstTerrain = true;
            const initialMapViewState = normalizeMapViewState(window.__qgcMapViewState || pendingMapViewState);
            if (!setMapViewState(initialMapViewState)) {
                viewer.camera.flyHome(0);
                viewer.scene.requestRender();
            }
            viewer.scene.requestRender();

            window.__qgcCesiumViewer = viewer;
            installControlsVisibilityHandlers();
        } catch (error) {
            console.error(error);
            setError("Unable to initialize streamed Cesium globe. WebGL/GPU initialization failed.");
        }
    }

    window.addEventListener("error", function () {
        setError("An unexpected error occurred while running streamed 3D view.");
    });
    window.addEventListener("focus", function () {
        onViewerActivated();
    });
    document.addEventListener("visibilitychange", function () {
        if (!document.hidden) {
            onViewerActivated();
        }
    });

    createViewer();
})();
