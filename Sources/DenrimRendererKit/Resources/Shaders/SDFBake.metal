#include <metal_stdlib>
using namespace metal;

struct GPUDistanceFieldBakeConstants {
    uint4 dimensions;
    float4 boundsMin;
    float4 extent;
    uint4 metadata;
};

struct GPUDistanceFieldBakePrimitive {
    float4 worldToPrimitive0;
    float4 worldToPrimitive1;
    float4 worldToPrimitive2;
    float4 worldToPrimitive3;
    float4 parameters;
    uint4 metadata;
    float4 controls;
};

struct GPUDistanceFieldBakeSample {
    float distance;
    uint materialA;
    uint materialB;
    float blend;
};

static float primitiveDistance(
    constant GPUDistanceFieldBakePrimitive &primitive,
    float3 position
) {
    float4x4 worldToPrimitive = float4x4(
        primitive.worldToPrimitive0,
        primitive.worldToPrimitive1,
        primitive.worldToPrimitive2,
        primitive.worldToPrimitive3
    );
    float3 local = (worldToPrimitive * float4(position, 1.0)).xyz;
    float distance = 0.0;

    switch (primitive.metadata.x) {
    case 1: {
        distance = length(local) - primitive.parameters.x;
        break;
    }
    case 2: {
        float3 q = abs(local) - primitive.parameters.xyz;
        distance = length(max(q, float3(0.0)))
            + min(max(q.x, max(q.y, q.z)), 0.0)
            - max(primitive.parameters.w, 0.0);
        break;
    }
    case 3: {
        float2 d = float2(length(local.xz), abs(local.y))
            - float2(primitive.parameters.x, primitive.parameters.y);
        distance = min(max(d.x, d.y), 0.0)
            + length(max(d, float2(0.0)));
        break;
    }
    default:
        distance = 1.0e20;
        break;
    }

    return distance * primitive.controls.y;
}

static GPUDistanceFieldBakeSample unionSample(
    GPUDistanceFieldBakeSample current,
    float candidateDistance,
    uint candidateMaterial,
    float smoothRadius
) {
    if (!isfinite(current.distance)) {
        current.distance = candidateDistance;
        current.materialA = candidateMaterial;
        current.materialB = candidateMaterial;
        current.blend = 0.0;
        return current;
    }

    float radius = max(smoothRadius, 0.0);
    if (radius <= 1.0e-6) {
        if (candidateDistance < current.distance) {
            current.distance = candidateDistance;
            current.materialA = candidateMaterial;
            current.materialB = candidateMaterial;
            current.blend = 0.0;
        }
        return current;
    }

    float h = clamp(0.5 + 0.5 * (candidateDistance - current.distance) / radius, 0.0, 1.0);
    float distance = mix(candidateDistance, current.distance, h) - radius * h * (1.0 - h);
    float candidateWeight = 1.0 - h;
    current.distance = distance;
    if (candidateWeight <= 0.001) {
        return current;
    }
    if (candidateWeight >= 0.999) {
        current.materialA = candidateMaterial;
        current.materialB = candidateMaterial;
        current.blend = 0.0;
        return current;
    }
    current.materialB = candidateMaterial;
    current.blend = candidateWeight;
    return current;
}

kernel void sdfBakeKernel(
    constant GPUDistanceFieldBakePrimitive *primitives [[buffer(0)]],
    device GPUDistanceFieldBakeSample *samples [[buffer(1)]],
    constant GPUDistanceFieldBakeConstants &constants [[buffer(2)]],
    uint sampleIndex [[thread_position_in_grid]]
) {
    uint sampleCount = constants.dimensions.w;
    if (sampleIndex >= sampleCount) {
        return;
    }

    uint width = constants.dimensions.x;
    uint height = constants.dimensions.y;
    uint xy = width * height;
    uint z = sampleIndex / xy;
    uint rem = sampleIndex - z * xy;
    uint y = rem / width;
    uint x = rem - y * width;

    float3 uvw = float3(
        width <= 1 ? 0.0 : float(x) / float(width - 1),
        height <= 1 ? 0.0 : float(y) / float(height - 1),
        constants.dimensions.z <= 1 ? 0.0 : float(z) / float(constants.dimensions.z - 1)
    );
    float3 position = constants.boundsMin.xyz + constants.extent.xyz * uvw;

    GPUDistanceFieldBakeSample field;
    field.distance = INFINITY;
    field.materialA = constants.metadata.y;
    field.materialB = constants.metadata.y;
    field.blend = 0.0;

    uint primitiveCount = constants.metadata.x;
    for (uint primitiveIndex = 0; primitiveIndex < primitiveCount; primitiveIndex++) {
        constant GPUDistanceFieldBakePrimitive &primitive = primitives[primitiveIndex];
        float distance = primitiveDistance(primitive, position);
        uint material = primitive.metadata.z;
        if (primitive.metadata.y == 1) {
            if (isfinite(field.distance)) {
                field.distance = max(field.distance, -distance);
            }
        } else {
            field = unionSample(field, distance, material, primitive.controls.x);
        }
    }

    samples[sampleIndex] = field;
}
