if(NOT QGC_VIEWER3D)
    return()
endif()

# Keep this compile definition so Viewer3D settings remain exposed through SettingsManager.
# Legacy local OSM/Quick3D implementation has been removed.
target_compile_definitions(${CMAKE_PROJECT_NAME} PRIVATE QGC_VIEWER3D)
