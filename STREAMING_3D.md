# Streaming 3D Build Flag

This fork adds a CMake feature flag:

- `QGC_STREAMING_3D` (default: `ON` on Windows, `OFF` on other platforms)

When enabled, the build requires and links the following Qt modules:

- `Qt6::WebEngineQuick`
- `Qt6::WebChannel`

When disabled, no WebEngine/WebChannel components are required and behavior is unchanged.

## Enable

```bash
cmake -S . -B build/Desktop_Qt_6_8_3_MSVC2022_64bit-Debug -G Ninja -DQGC_STREAMING_3D=ON
cmake --build build/Desktop_Qt_6_8_3_MSVC2022_64bit-Debug --config Debug
```

## Notes

- You must have Qt WebEngine installed in your Qt kit when `QGC_STREAMING_3D=ON`.
- When enabled, QGC uses the streamed 3D runtime (WebEngine + Mapbox-backed terrain/imagery path).
- Streamed 3D also requires a valid Mapbox access token configured in **Application Settings -> Fly View -> 3D View**.
