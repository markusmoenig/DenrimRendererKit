#include <metal_stdlib>
#include <metal_raytracing>
using namespace metal;
using namespace raytracing;

struct GPURayTracingProbeRay {
    float4 origin;
    float4 direction;
};

kernel void metalRayTracingProbeKernel(
    acceleration_structure<instancing> scene [[buffer(0)]],
    constant GPURayTracingProbeRay &rayInput [[buffer(1)]],
    device uint4 *hitIDs [[buffer(2)]],
    device float *hitDistance [[buffer(3)]]
) {
    ray query;
    query.origin = rayInput.origin.xyz;
    query.direction = normalize(rayInput.direction.xyz);
    query.min_distance = 0.0005f;
    query.max_distance = 100000.0f;

    intersector<triangle_data, instancing> sceneIntersector;
    auto hit = sceneIntersector.intersect(query, scene);

    if (hit.type == intersection_type::triangle) {
        hitIDs[0] = uint4(1u, hit.primitive_id, hit.instance_id, hit.geometry_id);
        hitDistance[0] = hit.distance;
    } else {
        hitIDs[0] = uint4(0u);
        hitDistance[0] = INFINITY;
    }
}
