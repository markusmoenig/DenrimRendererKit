# Performance

DenrimRendererKit needs performance evidence from day one. The renderer is allowed to target high quality rather than game-engine frame rates, but slow scenes must produce numbers we can compare across commits, devices, and acceleration backends.

## Benchmark Command

Run the benchmark executable for quick local timing:

```sh
swift run denrim-render-benchmark cornell 16 256
swift run denrim-render-benchmark materials 16 256
swift run denrim-render-benchmark script 1 64 Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim
```

Write persistent JSON for future comparison:

```sh
swift run denrim-render-benchmark \
    script \
    1 \
    64 \
    Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim \
    --output Examples/Benchmarks/dragon-local-64px-1spp.json
```

The JSON records:

* creation time
* scene name and optional asset path
* resolution
* sample count
* max bounces
* Metal device name
* scene/script load time
* renderer creation time
* session / acceleration build time
* render time
* total time
* samples per second
* pixel-samples per second

## XCTest Benchmarks

Performance XCTest cases are opt-in so normal correctness tests stay fast:

```sh
DENRIM_RUN_PERFORMANCE_TESTS=1 swift test --filter PerformanceBenchmarkTests
```

These tests should print timing data and verify that benchmark execution is healthy, but device-specific pass/fail thresholds should live in explicit baseline files once enough devices have been measured.

## Current Priorities

The Stanford Dragon example currently shows that session / acceleration build time can dominate total runtime. That makes these near-term optimization targets:

* Avoid rebuilding unchanged BLAS / TLAS data between sessions.
* Cache loaded meshes and compiled acceleration data where app lifetimes allow it.
* Separate scene compilation time from sample rendering time in benchmarks.
* Expose backend selection in benchmark output.
* Add backend-specific baselines for flat BVH and Metal ray tracing paths.
* Profile GPU occupancy and memory bandwidth in Xcode Instruments.

