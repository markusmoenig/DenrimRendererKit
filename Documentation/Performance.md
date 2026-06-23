# Performance

DenrimRendererKit needs performance evidence from day one. The renderer is allowed to target high quality rather than game-engine frame rates, but slow scenes must produce numbers we can compare across commits, devices, and acceleration backends.

## Benchmark Command

Run the benchmark executable for quick local timing:

```sh
swift run -c release denrim-render-benchmark cornell 16 256
swift run -c release denrim-render-benchmark materials 16 256
swift run -c release denrim-render-benchmark script 1 64 Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim
```

Write persistent JSON for future comparison:

```sh
swift run -c release denrim-render-benchmark \
    script \
    1 \
    64 \
    Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim \
    --output Examples/Benchmarks/dragon-local-64px-1spp.json
```

Rectangular renders can be benchmarked with `--width` and `--height`:

```sh
swift run -c release denrim-render-benchmark \
    script \
    1 \
    320 \
    Examples/SceneScripts/Quality/DiningRoom/dining-room.denrim \
    --width 320 \
    --height 180 \
    --output Examples/Benchmarks/dining-room-local-320x180-1spp.json
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

The Stanford Dragon example showed that session / acceleration build time can dominate total runtime. The first fix is now in place:

* Identical mesh data is deduplicated into one mesh acceleration record shared by many instances.
* Automatic Metal ray tracing sessions skip the large flat fallback BVH when the hardware TLAS path is available.
* Automatic Metal ray tracing sessions also skip per-mesh local BVHs that are only needed by the CPU/flat fallback path.
* Emissive triangle lights are compiled into GPU light records with precomputed area, normal, and power-weighted selection CDF data shared by the flat BVH and hardware TLAS direct-light kernels.
* Direct lighting samples one emissive triangle by power-weighted CDF instead of looping over every light each bounce, which bounds direct-light shader work for scenes with many emissive triangles.
* BSDF-sampled emissive-hit MIS uses per-triangle light-record indices to compute light PDFs in constant time instead of scanning the full light list.
* Direct light samples and BSDF-sampled emissive hits use first-pass MIS weights to reduce double counting and stabilize highlight energy.
* Russian roulette terminates low-contribution paths after early bounces while compensating surviving throughput, reducing wasted deep-bounce work without the bias of a hard cutoff.
* OBJ loading now uses a byte scanner instead of `String.split` tokenization, reducing large text-mesh import overhead.
* Forced flat-BVH sessions still build the fallback acceleration buffers for parity testing and unsupported devices.

On an Apple M1 Max, the `dragon-material-variants.denrim` benchmark at 64 px / 1 spp dropped from roughly 4.7 seconds of session creation to roughly 0.67 seconds.

On the same device, the DiningRoom benchmark at 320x180 / 1 spp dropped from roughly 5.39 seconds of scene loading with the older string-tokenizing OBJ importer to roughly 0.66 seconds with the byte-scanning OBJ importer. The same run reports roughly 0.04 seconds of renderer creation, 0.42 seconds of session creation, and 0.06 seconds of rendering.

DiningRoom is the first manual heavy fixture. It is intentionally not part of normal correctness tests or `render-quality-examples.sh`; run it directly when measuring render quality or acceleration behavior:

```sh
./Examples/Tools/render-dining-room-quality.sh
./Examples/Tools/benchmark-dining-room.sh
```

The scene separates performance costs clearly: OBJ and texture loading, renderer creation, session / acceleration setup, and render sampling are all reported independently by the benchmark JSON.

Remaining near-term optimization targets:

* Use `SceneAssetCache` from Denrim products that repeatedly parse the same scene while changing camera, material, or sampling settings.
* Cache parsed SceneScript structure where app lifetimes allow it.
* Avoid rebuilding unchanged BLAS / TLAS data between sessions.
* Cache compiled acceleration data once asset caching is in place.
* Separate scene compilation time from sample rendering time in benchmarks.
* Expose backend selection in benchmark output.
* Add backend-specific baselines for flat BVH and Metal ray tracing paths.
* Profile GPU occupancy and memory bandwidth in Xcode Instruments.
