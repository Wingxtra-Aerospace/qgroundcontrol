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
- The flag currently controls build-time dependency wiring only.
