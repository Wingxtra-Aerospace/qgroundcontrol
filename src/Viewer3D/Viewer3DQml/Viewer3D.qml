import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Controllers
import QGroundControl.FactSystem
import QGroundControl.FlightDisplay
import QGroundControl.FlightMap
import QGroundControl.Palette
import QGroundControl.ScreenTools
import QGroundControl.Vehicle

import QGroundControl.Viewer3D
import Viewer3D.Models3D

/// @author Omid Esrafilian <esrafilian.omid@gmail.com>

Item {
    id: viewer3DBody

    // FlyView expects these to exist and behave consistently
    property bool isOpen: false

    // Existing setting: Fly View -> 3D View enabled
    property bool _viewer3DEnabled: QGroundControl.settingsManager.viewer3DSettings.enabled.rawValue

    // New streaming feature flag (C++ global you added)
    // Must be true to use the streaming loader
    property bool _streaming3DEnabled: QGroundControl.streaming3DEnabled

    // Error shown over the 3D area if streaming fails to load
    property string _streamingLoadError: ""

    function _setLegacyActive(active) {
        // Legacy OSM viewer path
        view3DManagerLoader.active = active
        if (!active) {
            view3DLoader.active = false
        }
    }

    function _setStreamingActive(active) {
        streaming3DLoader.active = active
        if (!active) {
            _streamingLoadError = ""
        }
    }

    function _sync2DMapToStreaming3D() {
        if (_streaming3DEnabled !== true) {
            return
        }

        if (streaming3DLoader.status === Loader.Ready &&
                streaming3DLoader.item &&
                typeof streaming3DLoader.item.syncFrom2DMapTo3D === "function") {
            streaming3DLoader.item.syncFrom2DMapTo3D()
        }
    }

    function _finalizeClose(forceUnloadStreaming) {
        isOpen = false
        _setLegacyActive(false)

        // Keep streaming view alive across 2D/3D toggles to avoid full reload.
        // Unload only when explicitly requested (for example, disabling 3D).
        if (forceUnloadStreaming === true || _streaming3DEnabled !== true) {
            _setStreamingActive(false)
        }

        _streamingLoadError = ""
    }

    function open() {
        // Only open if the setting is enabled
        if (_viewer3DEnabled !== true) {
            return
        }

        isOpen = true

        console.log("[Viewer3D] open() enabled=", _viewer3DEnabled, "streaming=", _streaming3DEnabled)

        // Choose one path ONLY
        if (_streaming3DEnabled === true) {
            _setLegacyActive(false)
            _setStreamingActive(true)
        } else {
            _setStreamingActive(false)
            _setLegacyActive(true)
        }
    }

    function close() {
        if (_streaming3DEnabled === true &&
                streaming3DLoader.status === Loader.Ready &&
                streaming3DLoader.item &&
                typeof streaming3DLoader.item.syncFrom3DTo2DMap === "function") {
            streaming3DLoader.item.syncFrom3DTo2DMap(function() {
                _finalizeClose()
            })
            return
        }

        _finalizeClose()
    }

    visible: isOpen
    enabled: isOpen

    // If user disables 3D in Settings while open, close everything cleanly
    on_Viewer3DEnabledChanged: {
        if (_viewer3DEnabled === false) {
            _finalizeClose(true)
        }
    }

    // If streaming flag flips while open, swap implementations immediately
    on_Streaming3DEnabledChanged: {
        if (!isOpen) {
            return
        }

        console.log("[Viewer3D] streaming flag changed ->", _streaming3DEnabled)

        if (_streaming3DEnabled === true) {
            _setLegacyActive(false)
            _setStreamingActive(true)
        } else {
            _setStreamingActive(false)
            _setLegacyActive(true)
        }
    }

    // -----------------------------
    // Legacy (OSM) viewer path
    // -----------------------------
    Component {
        id: viewer3DManagerComponent

        Viewer3DManager {
            id: _viewer3DManager
        }
    }

    Loader {
        id: view3DManagerLoader
        active: false
        sourceComponent: viewer3DManagerComponent

        onLoaded: {
            // Only proceed if legacy path is active
            if (_streaming3DEnabled !== true) {
                view3DLoader.active = true
            }
        }
    }

    Loader {
        id: view3DLoader
        anchors.fill: parent
        active: false
        source: "Models3D/Viewer3DModel.qml"

        onLoaded: {
            item.viewer3DManager = view3DManagerLoader.item
        }
    }

    Binding {
        target: view3DLoader.item
        property: "isViewer3DOpen"
        value: isOpen
        when: (_streaming3DEnabled !== true) && (view3DLoader.status === Loader.Ready)
    }

    // -----------------------------
    // Streaming viewer path
    // -----------------------------
    Loader {
        id: streaming3DLoader
        anchors.fill: parent
        active: false

        // Must be in the same folder as this file
        source: "Viewer3DStreaming.qml"

        onStatusChanged: {
            if (status === Loader.Loading) {
                _streamingLoadError = ""
            } else if (status === Loader.Error) {
                // Show actual failure reason (very helpful)
                _streamingLoadError = "Streaming 3D failed to load: " + errorString()
                console.log("[Streaming3D] Loader.Error:", errorString())
            } else if (status === Loader.Ready) {
                console.log("[Streaming3D] Loader.Ready")
                _streamingLoadError = ""
                _sync2DMapToStreaming3D()
            }
        }
    }

    // Error overlay
    Rectangle {
        anchors.fill: parent
        color: "#99000000"
        visible: isOpen && (_streamingLoadError.length > 0)
        z: 1000

        QGCLabel {
            anchors.centerIn: parent
            width: parent.width * 0.8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: _streamingLoadError
        }
    }
}
