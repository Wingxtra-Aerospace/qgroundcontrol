import QGroundControl
import QtQuick
import QtQuick.Controls
import QtPositioning
import QtWebEngine

Item {
    id: root

    property bool _isLoading: true
    property string _errorText: ""
    property var _viewer3DSettings: QGroundControl.settingsManager.viewer3DSettings
    property var _streamingProviderFact: _viewer3DSettings ? _viewer3DSettings.streamingProvider : null
    property var _streamingProviderTokenFact: _viewer3DSettings ? _viewer3DSettings.streamingProviderToken : null

    function _stringValue(value) {
        if (value === undefined || value === null) {
            return "";
        }

        return String(value);
    }

    function _pushStreamingConfigToPage() {
        if (!webView || webView.loading) {
            return;
        }

        const config = {
            provider: _stringValue(_streamingProviderFact ? _streamingProviderFact.rawValue : ""),
            token: _stringValue(_streamingProviderTokenFact ? _streamingProviderTokenFact.rawValue : "")
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

    function syncFrom2DMapTo3D() {
        _pushMapViewToPage();
    }

    function activate() {
        if (!webView) {
            return;
        }

        webView.forceActiveFocus();
        webView.runJavaScript(
            "if (typeof window.__qgcOnViewerActivated === 'function') {" +
            "window.__qgcOnViewerActivated();" +
            "}"
        );
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
        focus: root.visible

        onLoadingChanged: function(loadRequest) {
            if (loadRequest.status === WebEngineView.LoadStartedStatus) {
                root._isLoading = true;
                root._errorText = "";
            } else if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                root._isLoading = false;
                root._pushStreamingConfigToPage();
                root._pushMapViewToPage();
                root.activate();
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
        if (visible) {
            activate();
        }
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
        target: root._streamingProviderFact
        ignoreUnknownSignals: true

        function onRawValueChanged() {
            root._pushStreamingConfigToPage();
        }

        function onValueChanged() {
            root._pushStreamingConfigToPage();
        }
    }

    Connections {
        target: root._streamingProviderTokenFact
        ignoreUnknownSignals: true

        function onRawValueChanged() {
            root._pushStreamingConfigToPage();
        }

        function onValueChanged() {
            root._pushStreamingConfigToPage();
        }
    }

}
