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

struct GPUDistanceFieldProgramOperation {
    uint4 metadata;
    uint4 indices;
    float4 p0;
    float4 p1;
    float4 p2;
    float4 p3;
    float4 p4;
};

struct GPUDistanceFieldBakeSample {
    float distance;
    uint materialA;
    uint materialB;
    float blend;
};

struct GPUDistanceFieldProgramSample {
    GPUDistanceFieldBakeSample field;
    float4 attributes0;
    float4 attributes1;
};

struct GPUSparseDistanceFieldBakeConstants {
    uint4 dimensions;
    uint4 gridDimensions;
    uint4 metadata;
    float4 boundsMin;
    float4 extent;
    float4 settings;
};

struct GPUSparseBrickClassification {
    uint4 metadata;
};

struct GPUSparseBrickBakeRecord {
    uint4 originAndSampleOffset;
    uint4 dimensionsAndSampleCount;
    uint4 coreOrigin;
    uint4 coreDimensions;
};

struct GPUDistanceFieldProgramAttributeLayout {
    uint4 metadata;
    uint4 semantics0;
    uint4 semantics1;
};

struct GPUVolumeAttributeDescriptor {
    uint4 metadata;
    uint4 semantics0;
    uint4 semantics1;
};

struct GPUVolumeBrickDescriptor {
    float4 worldBoundsMin;
    float4 worldBoundsMax;
    float4 localBoundsMin;
    float4 localBoundsMax;
    float4 sampleBoundsMin;
    float4 sampleBoundsMax;
    uint4 gridOriginAndVolume;
    uint4 dimensionsAndSampleOffset;
};

struct GPUVolumeBrickGrid {
    uint4 dimensionsAndIndexOffset;
    uint4 brickSizeAndVolume;
    uint4 macroDimensionsAndIndexOffset;
    uint4 macroSizeAndReserved;
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

static GPUDistanceFieldBakeSample sampleField(
    constant GPUDistanceFieldBakePrimitive *primitives,
    uint primitiveCount,
    uint fallbackMaterial,
    float3 position
) {
    GPUDistanceFieldBakeSample field;
    field.distance = INFINITY;
    field.materialA = fallbackMaterial;
    field.materialB = fallbackMaterial;
    field.blend = 0.0;

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

    return field;
}

static float3 programLocalPosition(
    float3 position,
    float4x4 programToLocal,
    float twistYStrength
) {
    float3 local = (programToLocal * float4(position, 1.0)).xyz;
    if (abs(twistYStrength) > 1.0e-6) {
        float angle = -local.y * twistYStrength;
        float c = cos(angle);
        float s = sin(angle);
        local = float3(
            c * local.x - s * local.z,
            local.y,
            s * local.x + c * local.z
        );
    }
    return local;
}

static float programSphereDistance(float3 local, float radius) {
    return length(local) - radius;
}

static float programBoxDistance(float3 local, float3 halfExtents, float cornerRadius) {
    float3 q = abs(local) - halfExtents;
    return length(max(q, float3(0.0)))
        + min(max(q.x, max(q.y, q.z)), 0.0)
        - max(cornerRadius, 0.0);
}

static float programCylinderDistance(float3 local, float radius, float halfHeight) {
    float2 d = float2(length(local.xz), abs(local.y)) - float2(radius, halfHeight);
    return min(max(d.x, d.y), 0.0) + length(max(d, float2(0.0)));
}

static float programTaperedCapsuleDistance(
    float3 position,
    float3 start,
    float3 end,
    float startRadius,
    float endRadius
) {
    float3 segment = end - start;
    float lengthSquared = dot(segment, segment);
    float t = lengthSquared > 1.0e-8
        ? clamp(dot(position - start, segment) / lengthSquared, 0.0, 1.0)
        : 0.0;
    float radius = max(mix(startRadius, endRadius, t), 0.0);
    return length(position - (start + segment * t)) - radius;
}

static float3 programCubicBezierPoint(
    float3 control0,
    float3 control1,
    float3 control2,
    float3 control3,
    float t
) {
    float oneMinusT = 1.0 - t;
    float oneMinusT2 = oneMinusT * oneMinusT;
    float t2 = t * t;
    return control0 * (oneMinusT2 * oneMinusT)
        + control1 * (3.0 * oneMinusT2 * t)
        + control2 * (3.0 * oneMinusT * t2)
        + control3 * (t2 * t);
}

static float programSplineTubeDistance(
    float3 position,
    float3 control0,
    float3 control1,
    float3 control2,
    float3 control3,
    float startRadius,
    float endRadius
) {
    constexpr uint segmentCount = 16u;
    float bestDistance = INFINITY;
    float3 previousPoint = control0;
    float previousRadius = max(startRadius, 0.0);
    for (uint segmentIndex = 1u; segmentIndex <= segmentCount; ++segmentIndex) {
        float t = float(segmentIndex) / float(segmentCount);
        float3 point = programCubicBezierPoint(control0, control1, control2, control3, t);
        float radius = max(mix(startRadius, endRadius, t), 0.0);
        bestDistance = min(
            bestDistance,
            programTaperedCapsuleDistance(
                position,
                previousPoint,
                point,
                previousRadius,
                radius
            )
        );
        previousPoint = point;
        previousRadius = radius;
    }
    return bestDistance;
}

static GPUDistanceFieldBakeSample combineProgramSample(
    GPUDistanceFieldBakeSample current,
    float candidateDistance,
    uint candidateMaterial,
    float smoothRadius,
    uint operation
) {
    if (operation == 1u) {
        if (isfinite(current.distance)) {
            current.distance = max(current.distance, -candidateDistance);
        }
        return current;
    }
    return unionSample(current, candidateDistance, candidateMaterial, smoothRadius);
}

static GPUDistanceFieldProgramSample sampleProgramField(
    constant GPUDistanceFieldProgramOperation *operations,
    uint operationCount,
    uint fallbackMaterial,
    float3 position
) {
    GPUDistanceFieldProgramSample result;
    result.field.distance = INFINITY;
    result.field.materialA = fallbackMaterial;
    result.field.materialB = fallbackMaterial;
    result.field.blend = 0.0;
    result.attributes0 = float4(0.0);
    result.attributes1 = float4(0.0);

    float4x4 programToLocal = float4x4(
        float4(1.0, 0.0, 0.0, 0.0),
        float4(0.0, 1.0, 0.0, 0.0),
        float4(0.0, 0.0, 1.0, 0.0),
        float4(0.0, 0.0, 0.0, 1.0)
    );
    float distanceScale = 1.0;
    float twistYStrength = 0.0;
    float scalarRegisters[32];
    float3 vectorRegisters[32];
    for (uint registerIndex = 0u; registerIndex < 32u; ++registerIndex) {
        scalarRegisters[registerIndex] = 0.0;
        vectorRegisters[registerIndex] = float3(0.0);
    }

    for (uint operationIndex = 0; operationIndex < operationCount; operationIndex++) {
        constant GPUDistanceFieldProgramOperation &operation = operations[operationIndex];
        switch (operation.metadata.x) {
        case 1: {
            programToLocal = float4x4(
                float4(1.0, 0.0, 0.0, 0.0),
                float4(0.0, 1.0, 0.0, 0.0),
                float4(0.0, 0.0, 1.0, 0.0),
                float4(0.0, 0.0, 0.0, 1.0)
            );
            distanceScale = 1.0;
            twistYStrength = 0.0;
            break;
        }
        case 2: {
            programToLocal = float4x4(operation.p0, operation.p1, operation.p2, operation.p3);
            distanceScale = max(operation.p4.x, 1.0e-6);
            break;
        }
        case 3: {
            twistYStrength = operation.p0.x;
            break;
        }
        case 10: {
            float3 local = programLocalPosition(position, programToLocal, twistYStrength);
            float distance = programSphereDistance(local, operation.p0.x) * distanceScale;
            result.field = combineProgramSample(result.field, distance, operation.metadata.z, operation.p0.y, operation.metadata.y);
            break;
        }
        case 11: {
            float3 local = programLocalPosition(position, programToLocal, twistYStrength);
            float distance = programBoxDistance(local, operation.p0.xyz, operation.p0.w) * distanceScale;
            result.field = combineProgramSample(result.field, distance, operation.metadata.z, operation.p1.x, operation.metadata.y);
            break;
        }
        case 12: {
            float3 local = programLocalPosition(position, programToLocal, twistYStrength);
            float distance = programCylinderDistance(local, operation.p0.x, operation.p0.y) * distanceScale;
            result.field = combineProgramSample(result.field, distance, operation.metadata.z, operation.p0.z, operation.metadata.y);
            break;
        }
        case 100: {
            vectorRegisters[operation.metadata.y & 31u] = position;
            break;
        }
        case 101: {
            scalarRegisters[operation.metadata.y & 31u] = operation.p0.x;
            break;
        }
        case 102: {
            vectorRegisters[operation.metadata.y & 31u] = operation.p0.xyz;
            break;
        }
        case 110: {
            scalarRegisters[operation.metadata.y & 31u] = scalarRegisters[operation.metadata.z & 31u] + scalarRegisters[operation.metadata.w & 31u];
            break;
        }
        case 111: {
            scalarRegisters[operation.metadata.y & 31u] = scalarRegisters[operation.metadata.z & 31u] - scalarRegisters[operation.metadata.w & 31u];
            break;
        }
        case 112: {
            scalarRegisters[operation.metadata.y & 31u] = scalarRegisters[operation.metadata.z & 31u] * scalarRegisters[operation.metadata.w & 31u];
            break;
        }
        case 113: {
            float divisor = scalarRegisters[operation.metadata.w & 31u];
            scalarRegisters[operation.metadata.y & 31u] = abs(divisor) > 1.0e-8 ? scalarRegisters[operation.metadata.z & 31u] / divisor : 0.0;
            break;
        }
        case 114: {
            scalarRegisters[operation.metadata.y & 31u] = -scalarRegisters[operation.metadata.z & 31u];
            break;
        }
        case 115: {
            scalarRegisters[operation.metadata.y & 31u] = min(scalarRegisters[operation.metadata.z & 31u], scalarRegisters[operation.metadata.w & 31u]);
            break;
        }
        case 116: {
            scalarRegisters[operation.metadata.y & 31u] = max(scalarRegisters[operation.metadata.z & 31u], scalarRegisters[operation.metadata.w & 31u]);
            break;
        }
        case 117: {
            scalarRegisters[operation.metadata.y & 31u] = abs(scalarRegisters[operation.metadata.z & 31u]);
            break;
        }
        case 118: {
            scalarRegisters[operation.metadata.y & 31u] = sin(scalarRegisters[operation.metadata.z & 31u]);
            break;
        }
        case 119: {
            scalarRegisters[operation.metadata.y & 31u] = cos(scalarRegisters[operation.metadata.z & 31u]);
            break;
        }
        case 120: {
            scalarRegisters[operation.indices.x & 31u] = clamp(
                scalarRegisters[operation.indices.y & 31u],
                scalarRegisters[operation.indices.z & 31u],
                scalarRegisters[operation.indices.w & 31u]
            );
            break;
        }
        case 121: {
            float a = scalarRegisters[operation.indices.y & 31u];
            float b = scalarRegisters[operation.indices.z & 31u];
            float t = scalarRegisters[operation.indices.w & 31u];
            scalarRegisters[operation.indices.x & 31u] = mix(a, b, t);
            break;
        }
        case 130: {
            vectorRegisters[operation.metadata.y & 31u] = vectorRegisters[operation.metadata.z & 31u] + vectorRegisters[operation.metadata.w & 31u];
            break;
        }
        case 131: {
            vectorRegisters[operation.metadata.y & 31u] = vectorRegisters[operation.metadata.z & 31u] - vectorRegisters[operation.metadata.w & 31u];
            break;
        }
        case 132: {
            vectorRegisters[operation.metadata.y & 31u] = vectorRegisters[operation.metadata.z & 31u] * scalarRegisters[operation.metadata.w & 31u];
            break;
        }
        case 133: {
            vectorRegisters[operation.metadata.y & 31u] = abs(vectorRegisters[operation.metadata.z & 31u]);
            break;
        }
        case 134: {
            vectorRegisters[operation.metadata.y & 31u] = max(vectorRegisters[operation.metadata.z & 31u], float3(scalarRegisters[operation.metadata.w & 31u]));
            break;
        }
        case 135: {
            vectorRegisters[operation.metadata.y & 31u] = min(vectorRegisters[operation.metadata.z & 31u], float3(scalarRegisters[operation.metadata.w & 31u]));
            break;
        }
        case 136: {
            vectorRegisters[operation.indices.x & 31u] = float3(
                scalarRegisters[operation.indices.y & 31u],
                scalarRegisters[operation.indices.z & 31u],
                scalarRegisters[operation.indices.w & 31u]
            );
            break;
        }
        case 137: {
            scalarRegisters[operation.metadata.y & 31u] = vectorRegisters[operation.metadata.z & 31u].x;
            break;
        }
        case 138: {
            scalarRegisters[operation.metadata.y & 31u] = vectorRegisters[operation.metadata.z & 31u].y;
            break;
        }
        case 139: {
            scalarRegisters[operation.metadata.y & 31u] = vectorRegisters[operation.metadata.z & 31u].z;
            break;
        }
        case 140: {
            scalarRegisters[operation.metadata.y & 31u] = length(vectorRegisters[operation.metadata.z & 31u]);
            break;
        }
        case 141: {
            scalarRegisters[operation.indices.x & 31u] = programBoxDistance(
                vectorRegisters[operation.indices.y & 31u],
                vectorRegisters[operation.indices.z & 31u],
                scalarRegisters[operation.indices.w & 31u]
            );
            break;
        }
        case 142: {
            scalarRegisters[operation.indices.x & 31u] = programCylinderDistance(
                vectorRegisters[operation.indices.y & 31u],
                scalarRegisters[operation.indices.z & 31u],
                scalarRegisters[operation.indices.w & 31u]
            );
            break;
        }
        case 143: {
            scalarRegisters[operation.metadata.y & 31u] = programTaperedCapsuleDistance(
                vectorRegisters[operation.metadata.z & 31u],
                vectorRegisters[operation.metadata.w & 31u],
                vectorRegisters[operation.indices.x & 31u],
                scalarRegisters[operation.indices.y & 31u],
                scalarRegisters[operation.indices.z & 31u]
            );
            break;
        }
        case 144: {
            scalarRegisters[operation.metadata.y & 31u] = programSplineTubeDistance(
                vectorRegisters[operation.metadata.z & 31u],
                vectorRegisters[operation.metadata.w & 31u],
                vectorRegisters[operation.indices.x & 31u],
                vectorRegisters[operation.indices.y & 31u],
                vectorRegisters[operation.indices.z & 31u],
                scalarRegisters[operation.indices.w & 31u],
                scalarRegisters[uint(operation.p0.x) & 31u]
            );
            break;
        }
        case 150: {
            result.field = combineProgramSample(
                result.field,
                scalarRegisters[operation.metadata.y & 31u],
                operation.metadata.z,
                operation.p0.x,
                operation.metadata.w
            );
            break;
        }
        case 160: {
            uint channel = operation.metadata.y;
            float value = scalarRegisters[operation.metadata.z & 31u];
            if (channel < 4u) {
                result.attributes0[channel] = value;
            } else if (channel < 8u) {
                result.attributes1[channel - 4u] = value;
            }
            break;
        }
        default:
            break;
        }
    }

    return result;
}

static uint3 sparseBrickCell(uint brickIndex, uint3 gridDimensions) {
    uint xy = gridDimensions.x * gridDimensions.y;
    uint z = brickIndex / xy;
    uint rem = brickIndex - z * xy;
    uint y = rem / gridDimensions.x;
    uint x = rem - y * gridDimensions.x;
    return uint3(x, y, z);
}

static float3 sparseSamplePosition(uint3 sampleCoordinate, constant GPUSparseDistanceFieldBakeConstants &constants) {
    float3 denominator = max(float3(constants.dimensions.xyz) - float3(1.0), float3(1.0));
    float3 uvw = float3(sampleCoordinate) / denominator;
    return constants.boundsMin.xyz + constants.extent.xyz * uvw;
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

    samples[sampleIndex] = sampleField(primitives, constants.metadata.x, constants.metadata.y, position);
}

kernel void sdfSparseClassifyKernel(
    constant GPUDistanceFieldBakePrimitive *primitives [[buffer(0)]],
    device GPUSparseBrickClassification *classifications [[buffer(1)]],
    constant GPUSparseDistanceFieldBakeConstants &constants [[buffer(2)]],
    uint brickIndex [[thread_position_in_grid]]
) {
    uint candidateCount = constants.dimensions.w;
    if (brickIndex >= candidateCount) {
        return;
    }

    uint3 gridCell = sparseBrickCell(brickIndex, constants.gridDimensions.xyz);
    uint3 brickSize = max(uint3(constants.gridDimensions.w), uint3(1));
    uint overlap = constants.metadata.z;
    uint3 coreOrigin = gridCell * brickSize;
    uint3 coreEnd = min(coreOrigin + brickSize, constants.dimensions.xyz);
    uint3 storedOrigin = uint3(
        coreOrigin.x > overlap ? coreOrigin.x - overlap : 0,
        coreOrigin.y > overlap ? coreOrigin.y - overlap : 0,
        coreOrigin.z > overlap ? coreOrigin.z - overlap : 0
    );
    uint3 storedEnd = min(coreEnd + uint3(overlap), constants.dimensions.xyz);

    float minDistance = INFINITY;
    float maxDistance = -INFINITY;
    for (uint z = storedOrigin.z; z < storedEnd.z; ++z) {
        for (uint y = storedOrigin.y; y < storedEnd.y; ++y) {
            for (uint x = storedOrigin.x; x < storedEnd.x; ++x) {
                float3 position = sparseSamplePosition(uint3(x, y, z), constants);
                float distance = sampleField(
                    primitives,
                    constants.metadata.x,
                    constants.metadata.y,
                    position
                ).distance;
                minDistance = min(minDistance, distance);
                maxDistance = max(maxDistance, distance);
            }
        }
    }

    float band = max(constants.settings.x, 0.0);
    uint active = (minDistance <= band && maxDistance >= -band) ? 1u : 0u;
    classifications[brickIndex].metadata = uint4(active, 0, 0, 0);
}

kernel void sdfSparseBakeKernel(
    constant GPUDistanceFieldBakePrimitive *primitives [[buffer(0)]],
    constant GPUSparseBrickBakeRecord *records [[buffer(1)]],
    device GPUDistanceFieldBakeSample *samples [[buffer(2)]],
    constant GPUSparseDistanceFieldBakeConstants &constants [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint localSampleIndex = gid.x;
    uint brickIndex = gid.y;
    uint activeBrickCount = constants.metadata.w;
    if (brickIndex >= activeBrickCount) {
        return;
    }

    constant GPUSparseBrickBakeRecord &record = records[brickIndex];
    uint sampleCount = record.dimensionsAndSampleCount.w;
    if (localSampleIndex >= sampleCount) {
        return;
    }

    uint3 dimensions = record.dimensionsAndSampleCount.xyz;
    uint xy = dimensions.x * dimensions.y;
    uint z = localSampleIndex / xy;
    uint rem = localSampleIndex - z * xy;
    uint y = rem / dimensions.x;
    uint x = rem - y * dimensions.x;
    uint3 sampleCoordinate = record.originAndSampleOffset.xyz + uint3(x, y, z);
    float3 position = sparseSamplePosition(sampleCoordinate, constants);
    samples[record.originAndSampleOffset.w + localSampleIndex] = sampleField(
        primitives,
        constants.metadata.x,
        constants.metadata.y,
        position
    );
}

static float3 sparseGridToLocal(uint3 coordinate, constant GPUSparseDistanceFieldBakeConstants &constants) {
    float3 denominator = max(float3(constants.dimensions.xyz) - float3(1.0), float3(1.0));
    return constants.boundsMin.xyz + constants.extent.xyz * (float3(coordinate) / denominator);
}

static float3 sparseExpandedGridMinimum(uint3 origin, constant GPUSparseDistanceFieldBakeConstants &constants) {
    float3 denominator = max(float3(constants.dimensions.xyz) - float3(1.0), float3(1.0));
    float3 expanded = max(float3(origin) - float3(0.5), float3(0.0));
    return constants.boundsMin.xyz + constants.extent.xyz * (expanded / denominator);
}

static float3 sparseExpandedGridMaximum(uint3 origin, uint3 dimensions, constant GPUSparseDistanceFieldBakeConstants &constants) {
    float3 denominator = max(float3(constants.dimensions.xyz) - float3(1.0), float3(1.0));
    float3 expanded = min(float3(origin + dimensions - uint3(1)) + float3(0.5), denominator);
    return constants.boundsMin.xyz + constants.extent.xyz * (expanded / denominator);
}

constant uint sparseMacroCellSize = 4u;

static uint3 sparseMacroGridDimensions(uint3 gridDimensions) {
    return (gridDimensions + uint3(sparseMacroCellSize - 1u)) / uint3(sparseMacroCellSize);
}

kernel void sdfSparseBuildMacroGridKernel(
    device GPUVolumeBrickGrid *brickGrids [[buffer(0)]],
    device uint *gridIndices [[buffer(1)]],
    constant GPUSparseDistanceFieldBakeConstants &constants [[buffer(2)]],
    uint macroIndex [[thread_position_in_grid]]
) {
    uint3 gridDimensions = constants.gridDimensions.xyz;
    uint candidateCount = constants.dimensions.w;
    uint3 macroDimensions = sparseMacroGridDimensions(gridDimensions);
    uint macroCount = macroDimensions.x * macroDimensions.y * macroDimensions.z;
    if (macroIndex >= macroCount) {
        return;
    }

    if (macroIndex == 0u) {
        brickGrids[0].macroDimensionsAndIndexOffset = uint4(macroDimensions, candidateCount);
        brickGrids[0].macroSizeAndReserved = uint4(sparseMacroCellSize, sparseMacroCellSize, sparseMacroCellSize, 0u);
    }

    uint xy = macroDimensions.x * macroDimensions.y;
    uint z = macroIndex / xy;
    uint rem = macroIndex - z * xy;
    uint y = rem / macroDimensions.x;
    uint x = rem - y * macroDimensions.x;
    uint3 macroOrigin = uint3(x, y, z) * uint3(sparseMacroCellSize);
    uint3 macroEnd = min(macroOrigin + uint3(sparseMacroCellSize), gridDimensions);

    uint occupied = 0u;
    for (uint cellZ = macroOrigin.z; cellZ < macroEnd.z; ++cellZ) {
        for (uint cellY = macroOrigin.y; cellY < macroEnd.y; ++cellY) {
            for (uint cellX = macroOrigin.x; cellX < macroEnd.x; ++cellX) {
                uint slot = cellX + cellY * gridDimensions.x + cellZ * gridDimensions.x * gridDimensions.y;
                if (slot < candidateCount && gridIndices[slot] != 0xffffffffu) {
                    occupied = 1u;
                }
            }
        }
    }
    gridIndices[candidateCount + macroIndex] = occupied;
}

kernel void sdfSparseDirectGridBakeKernel(
    constant GPUDistanceFieldBakePrimitive *primitives [[buffer(0)]],
    device GPUDistanceFieldBakeSample *samples [[buffer(1)]],
    device GPUVolumeBrickDescriptor *brickDescriptors [[buffer(2)]],
    device GPUVolumeAttributeDescriptor *attributeDescriptors [[buffer(3)]],
    device GPUVolumeBrickGrid *brickGrids [[buffer(4)]],
    device uint *gridIndices [[buffer(5)]],
    constant GPUSparseDistanceFieldBakeConstants &constants [[buffer(6)]],
    uint3 threadPositionInThreadgroup [[thread_position_in_threadgroup]],
    uint3 threadgroupPosition [[threadgroup_position_in_grid]],
    uint3 threadsPerThreadgroupVector [[threads_per_threadgroup]]
) {
    uint localThreadIndex = threadPositionInThreadgroup.x;
    uint threadsPerThreadgroup = threadsPerThreadgroupVector.x;
    uint brickIndex = threadgroupPosition.x;
    uint candidateCount = constants.dimensions.w;
    if (brickIndex >= candidateCount) {
        return;
    }
    threadgroup float threadMinDistances[256];
    threadgroup float threadMaxDistances[256];

    uint3 gridDimensions = constants.gridDimensions.xyz;
    uint3 gridCell = sparseBrickCell(brickIndex, gridDimensions);
    uint3 brickSize = max(uint3(constants.gridDimensions.w), uint3(1));
    uint overlap = constants.metadata.z;
    uint maxStoredSampleCount = max(constants.metadata.w, 1u);
    uint3 coreOrigin = gridCell * brickSize;
    uint3 coreEnd = min(coreOrigin + brickSize, constants.dimensions.xyz);
    uint3 coreDimensions = coreEnd - coreOrigin;
    uint3 storedOrigin = uint3(
        coreOrigin.x > overlap ? coreOrigin.x - overlap : 0,
        coreOrigin.y > overlap ? coreOrigin.y - overlap : 0,
        coreOrigin.z > overlap ? coreOrigin.z - overlap : 0
    );
    uint3 storedEnd = min(coreEnd + uint3(overlap), constants.dimensions.xyz);
    uint3 storedDimensions = storedEnd - storedOrigin;
    uint storedSampleCount = storedDimensions.x * storedDimensions.y * storedDimensions.z;

    if (brickIndex == 0u) {
        brickGrids[0].dimensionsAndIndexOffset = uint4(gridDimensions, 0u);
        brickGrids[0].brickSizeAndVolume = uint4(brickSize, 0u);
        brickGrids[0].macroDimensionsAndIndexOffset = uint4(0u);
        brickGrids[0].macroSizeAndReserved = uint4(0u);
    }

    float minDistance = INFINITY;
    float maxDistance = -INFINITY;
    for (uint localSampleIndex = localThreadIndex; localSampleIndex < storedSampleCount; localSampleIndex += threadsPerThreadgroup) {
        uint xy = storedDimensions.x * storedDimensions.y;
        uint z = localSampleIndex / xy;
        uint rem = localSampleIndex - z * xy;
        uint y = rem / storedDimensions.x;
        uint x = rem - y * storedDimensions.x;
        float distance = sampleField(
            primitives,
            constants.metadata.x,
            constants.metadata.y,
            sparseSamplePosition(storedOrigin + uint3(x, y, z), constants)
        ).distance;
        minDistance = min(minDistance, distance);
        maxDistance = max(maxDistance, distance);
    }
    threadMinDistances[localThreadIndex] = minDistance;
    threadMaxDistances[localThreadIndex] = maxDistance;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint stride = threadsPerThreadgroup >> 1u; stride > 0u; stride >>= 1u) {
        if (localThreadIndex < stride) {
            threadMinDistances[localThreadIndex] = min(
                threadMinDistances[localThreadIndex],
                threadMinDistances[localThreadIndex + stride]
            );
            threadMaxDistances[localThreadIndex] = max(
                threadMaxDistances[localThreadIndex],
                threadMaxDistances[localThreadIndex + stride]
            );
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    float band = max(constants.settings.x, 0.0);
    bool active = threadMinDistances[0] <= band && threadMaxDistances[0] >= -band;
    uint sampleOffset = brickIndex * maxStoredSampleCount;
    if (localThreadIndex == 0u) {
        gridIndices[brickIndex] = active ? brickIndex : 0xffffffffu;
        attributeDescriptors[brickIndex].metadata = uint4(0u, sampleOffset, storedSampleCount, brickIndex);
        attributeDescriptors[brickIndex].semantics0 = uint4(0u);
        attributeDescriptors[brickIndex].semantics1 = uint4(0u);
    }

    if (!active) {
        return;
    }

    if (localThreadIndex == 0u) {
        float3 coreMin = sparseExpandedGridMinimum(coreOrigin, constants);
        float3 coreMax = sparseExpandedGridMaximum(coreOrigin, coreDimensions, constants);
        float3 sampleMin = sparseGridToLocal(storedOrigin, constants);
        float3 sampleMax = sparseGridToLocal(storedEnd - uint3(1), constants);
        brickDescriptors[brickIndex].worldBoundsMin = float4(coreMin, 0.0);
        brickDescriptors[brickIndex].worldBoundsMax = float4(coreMax, 0.0);
        brickDescriptors[brickIndex].localBoundsMin = float4(coreMin, 0.0);
        brickDescriptors[brickIndex].localBoundsMax = float4(coreMax, 0.0);
        brickDescriptors[brickIndex].sampleBoundsMin = float4(sampleMin, threadMinDistances[0]);
        brickDescriptors[brickIndex].sampleBoundsMax = float4(sampleMax, threadMaxDistances[0]);
        brickDescriptors[brickIndex].gridOriginAndVolume = uint4(storedOrigin, 0u);
        brickDescriptors[brickIndex].dimensionsAndSampleOffset = uint4(storedDimensions, sampleOffset);
    }

    for (uint localSampleIndex = localThreadIndex; localSampleIndex < storedSampleCount; localSampleIndex += threadsPerThreadgroup) {
        uint xy = storedDimensions.x * storedDimensions.y;
        uint z = localSampleIndex / xy;
        uint rem = localSampleIndex - z * xy;
        uint y = rem / storedDimensions.x;
        uint x = rem - y * storedDimensions.x;
        uint3 sampleCoordinate = storedOrigin + uint3(x, y, z);
        samples[sampleOffset + localSampleIndex] = sampleField(
            primitives,
            constants.metadata.x,
            constants.metadata.y,
            sparseSamplePosition(sampleCoordinate, constants)
        );
    }
}

kernel void sdfProgramSparseDirectGridBakeKernel(
    constant GPUDistanceFieldProgramOperation *operations [[buffer(0)]],
    device GPUDistanceFieldBakeSample *samples [[buffer(1)]],
    device GPUVolumeBrickDescriptor *brickDescriptors [[buffer(2)]],
    device GPUVolumeAttributeDescriptor *attributeDescriptors [[buffer(3)]],
    device GPUVolumeBrickGrid *brickGrids [[buffer(4)]],
    device uint *gridIndices [[buffer(5)]],
    constant GPUSparseDistanceFieldBakeConstants &constants [[buffer(6)]],
    device float4 *attributeSamples [[buffer(7)]],
    constant GPUDistanceFieldProgramAttributeLayout &attributeLayout [[buffer(8)]],
    uint3 threadPositionInThreadgroup [[thread_position_in_threadgroup]],
    uint3 threadgroupPosition [[threadgroup_position_in_grid]],
    uint3 threadsPerThreadgroupVector [[threads_per_threadgroup]]
) {
    uint localThreadIndex = threadPositionInThreadgroup.x;
    uint threadsPerThreadgroup = threadsPerThreadgroupVector.x;
    uint brickIndex = threadgroupPosition.x;
    uint candidateCount = constants.dimensions.w;
    if (brickIndex >= candidateCount) {
        return;
    }
    threadgroup float threadMinDistances[256];
    threadgroup float threadMaxDistances[256];

    uint3 gridDimensions = constants.gridDimensions.xyz;
    uint3 gridCell = sparseBrickCell(brickIndex, gridDimensions);
    uint3 brickSize = max(uint3(constants.gridDimensions.w), uint3(1));
    uint overlap = constants.metadata.z;
    uint maxStoredSampleCount = max(constants.metadata.w, 1u);
    uint3 coreOrigin = gridCell * brickSize;
    uint3 coreEnd = min(coreOrigin + brickSize, constants.dimensions.xyz);
    uint3 coreDimensions = coreEnd - coreOrigin;
    uint3 storedOrigin = uint3(
        coreOrigin.x > overlap ? coreOrigin.x - overlap : 0,
        coreOrigin.y > overlap ? coreOrigin.y - overlap : 0,
        coreOrigin.z > overlap ? coreOrigin.z - overlap : 0
    );
    uint3 storedEnd = min(coreEnd + uint3(overlap), constants.dimensions.xyz);
    uint3 storedDimensions = storedEnd - storedOrigin;
    uint storedSampleCount = storedDimensions.x * storedDimensions.y * storedDimensions.z;

    if (brickIndex == 0u) {
        brickGrids[0].dimensionsAndIndexOffset = uint4(gridDimensions, 0u);
        brickGrids[0].brickSizeAndVolume = uint4(brickSize, 0u);
        brickGrids[0].macroDimensionsAndIndexOffset = uint4(0u);
        brickGrids[0].macroSizeAndReserved = uint4(0u);
    }

    float minDistance = INFINITY;
    float maxDistance = -INFINITY;
    for (uint localSampleIndex = localThreadIndex; localSampleIndex < storedSampleCount; localSampleIndex += threadsPerThreadgroup) {
        uint xy = storedDimensions.x * storedDimensions.y;
        uint z = localSampleIndex / xy;
        uint rem = localSampleIndex - z * xy;
        uint y = rem / storedDimensions.x;
        uint x = rem - y * storedDimensions.x;
        float distance = sampleProgramField(
            operations,
            constants.metadata.x,
            constants.metadata.y,
            sparseSamplePosition(storedOrigin + uint3(x, y, z), constants)
        ).field.distance;
        minDistance = min(minDistance, distance);
        maxDistance = max(maxDistance, distance);
    }
    threadMinDistances[localThreadIndex] = minDistance;
    threadMaxDistances[localThreadIndex] = maxDistance;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint stride = threadsPerThreadgroup >> 1u; stride > 0u; stride >>= 1u) {
        if (localThreadIndex < stride) {
            threadMinDistances[localThreadIndex] = min(
                threadMinDistances[localThreadIndex],
                threadMinDistances[localThreadIndex + stride]
            );
            threadMaxDistances[localThreadIndex] = max(
                threadMaxDistances[localThreadIndex],
                threadMaxDistances[localThreadIndex + stride]
            );
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    float band = max(constants.settings.x, 0.0);
    bool active = threadMinDistances[0] <= band && threadMaxDistances[0] >= -band;
    uint sampleOffset = brickIndex * maxStoredSampleCount;
    uint packedVectorCount = min(attributeLayout.metadata.x, 2u);
    uint attributeOffset = sampleOffset * packedVectorCount;
    if (localThreadIndex == 0u) {
        gridIndices[brickIndex] = active ? brickIndex : 0xffffffffu;
        attributeDescriptors[brickIndex].metadata = uint4(attributeOffset, packedVectorCount, storedSampleCount, brickIndex);
        attributeDescriptors[brickIndex].semantics0 = attributeLayout.semantics0;
        attributeDescriptors[brickIndex].semantics1 = attributeLayout.semantics1;
    }

    if (!active) {
        return;
    }

    if (localThreadIndex == 0u) {
        float3 coreMin = sparseExpandedGridMinimum(coreOrigin, constants);
        float3 coreMax = sparseExpandedGridMaximum(coreOrigin, coreDimensions, constants);
        float3 sampleMin = sparseGridToLocal(storedOrigin, constants);
        float3 sampleMax = sparseGridToLocal(storedEnd - uint3(1), constants);
        brickDescriptors[brickIndex].worldBoundsMin = float4(coreMin, 0.0);
        brickDescriptors[brickIndex].worldBoundsMax = float4(coreMax, 0.0);
        brickDescriptors[brickIndex].localBoundsMin = float4(coreMin, 0.0);
        brickDescriptors[brickIndex].localBoundsMax = float4(coreMax, 0.0);
        brickDescriptors[brickIndex].sampleBoundsMin = float4(sampleMin, threadMinDistances[0]);
        brickDescriptors[brickIndex].sampleBoundsMax = float4(sampleMax, threadMaxDistances[0]);
        brickDescriptors[brickIndex].gridOriginAndVolume = uint4(storedOrigin, 0u);
        brickDescriptors[brickIndex].dimensionsAndSampleOffset = uint4(storedDimensions, sampleOffset);
    }

    for (uint localSampleIndex = localThreadIndex; localSampleIndex < storedSampleCount; localSampleIndex += threadsPerThreadgroup) {
        uint xy = storedDimensions.x * storedDimensions.y;
        uint z = localSampleIndex / xy;
        uint rem = localSampleIndex - z * xy;
        uint y = rem / storedDimensions.x;
        uint x = rem - y * storedDimensions.x;
        uint3 sampleCoordinate = storedOrigin + uint3(x, y, z);
        GPUDistanceFieldProgramSample programSample = sampleProgramField(
            operations,
            constants.metadata.x,
            constants.metadata.y,
            sparseSamplePosition(sampleCoordinate, constants)
        );
        samples[sampleOffset + localSampleIndex] = programSample.field;
        if (packedVectorCount > 0u) {
            uint attributeSampleIndex = attributeOffset + localSampleIndex * packedVectorCount;
            attributeSamples[attributeSampleIndex] = programSample.attributes0;
            if (packedVectorCount > 1u) {
                attributeSamples[attributeSampleIndex + 1u] = programSample.attributes1;
            }
        }
    }
}

kernel void sdfProgramSparseDirectGridBakeSelectedKernel(
    constant GPUDistanceFieldProgramOperation *operations [[buffer(0)]],
    device GPUDistanceFieldBakeSample *samples [[buffer(1)]],
    device GPUVolumeBrickDescriptor *brickDescriptors [[buffer(2)]],
    device GPUVolumeAttributeDescriptor *attributeDescriptors [[buffer(3)]],
    device GPUVolumeBrickGrid *brickGrids [[buffer(4)]],
    device uint *gridIndices [[buffer(5)]],
    constant GPUSparseDistanceFieldBakeConstants &constants [[buffer(6)]],
    constant uint *dirtyBrickIndices [[buffer(7)]],
    device float4 *attributeSamples [[buffer(8)]],
    constant GPUDistanceFieldProgramAttributeLayout &attributeLayout [[buffer(9)]],
    uint3 threadPositionInThreadgroup [[thread_position_in_threadgroup]],
    uint3 threadgroupPosition [[threadgroup_position_in_grid]],
    uint3 threadsPerThreadgroupVector [[threads_per_threadgroup]]
) {
    uint dirtyIndex = threadgroupPosition.x;
    uint brickIndex = dirtyBrickIndices[dirtyIndex];
    uint candidateCount = constants.dimensions.w;
    if (brickIndex >= candidateCount) {
        return;
    }

    uint localThreadIndex = threadPositionInThreadgroup.x;
    uint threadsPerThreadgroup = threadsPerThreadgroupVector.x;
    threadgroup float threadMinDistances[256];
    threadgroup float threadMaxDistances[256];

    uint3 gridDimensions = constants.gridDimensions.xyz;
    uint3 gridCell = sparseBrickCell(brickIndex, gridDimensions);
    uint3 brickSize = max(uint3(constants.gridDimensions.w), uint3(1));
    uint overlap = constants.metadata.z;
    uint maxStoredSampleCount = max(constants.metadata.w, 1u);
    uint3 coreOrigin = gridCell * brickSize;
    uint3 coreEnd = min(coreOrigin + brickSize, constants.dimensions.xyz);
    uint3 coreDimensions = coreEnd - coreOrigin;
    uint3 storedOrigin = uint3(
        coreOrigin.x > overlap ? coreOrigin.x - overlap : 0,
        coreOrigin.y > overlap ? coreOrigin.y - overlap : 0,
        coreOrigin.z > overlap ? coreOrigin.z - overlap : 0
    );
    uint3 storedEnd = min(coreEnd + uint3(overlap), constants.dimensions.xyz);
    uint3 storedDimensions = storedEnd - storedOrigin;
    uint storedSampleCount = storedDimensions.x * storedDimensions.y * storedDimensions.z;

    if (brickIndex == 0u && localThreadIndex == 0u) {
        brickGrids[0].dimensionsAndIndexOffset = uint4(gridDimensions, 0u);
        brickGrids[0].brickSizeAndVolume = uint4(brickSize, 0u);
        brickGrids[0].macroDimensionsAndIndexOffset = uint4(0u);
        brickGrids[0].macroSizeAndReserved = uint4(0u);
    }

    float minDistance = INFINITY;
    float maxDistance = -INFINITY;
    for (uint localSampleIndex = localThreadIndex; localSampleIndex < storedSampleCount; localSampleIndex += threadsPerThreadgroup) {
        uint xy = storedDimensions.x * storedDimensions.y;
        uint z = localSampleIndex / xy;
        uint rem = localSampleIndex - z * xy;
        uint y = rem / storedDimensions.x;
        uint x = rem - y * storedDimensions.x;
        float distance = sampleProgramField(
            operations,
            constants.metadata.x,
            constants.metadata.y,
            sparseSamplePosition(storedOrigin + uint3(x, y, z), constants)
        ).field.distance;
        minDistance = min(minDistance, distance);
        maxDistance = max(maxDistance, distance);
    }
    threadMinDistances[localThreadIndex] = minDistance;
    threadMaxDistances[localThreadIndex] = maxDistance;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint stride = threadsPerThreadgroup >> 1u; stride > 0u; stride >>= 1u) {
        if (localThreadIndex < stride) {
            threadMinDistances[localThreadIndex] = min(
                threadMinDistances[localThreadIndex],
                threadMinDistances[localThreadIndex + stride]
            );
            threadMaxDistances[localThreadIndex] = max(
                threadMaxDistances[localThreadIndex],
                threadMaxDistances[localThreadIndex + stride]
            );
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    float band = max(constants.settings.x, 0.0);
    bool active = threadMinDistances[0] <= band && threadMaxDistances[0] >= -band;
    uint sampleOffset = brickIndex * maxStoredSampleCount;
    uint packedVectorCount = min(attributeLayout.metadata.x, 2u);
    uint attributeOffset = sampleOffset * packedVectorCount;
    if (localThreadIndex == 0u) {
        gridIndices[brickIndex] = active ? brickIndex : 0xffffffffu;
        attributeDescriptors[brickIndex].metadata = uint4(attributeOffset, packedVectorCount, storedSampleCount, brickIndex);
        attributeDescriptors[brickIndex].semantics0 = attributeLayout.semantics0;
        attributeDescriptors[brickIndex].semantics1 = attributeLayout.semantics1;
    }

    if (!active) {
        return;
    }

    if (localThreadIndex == 0u) {
        float3 coreMin = sparseExpandedGridMinimum(coreOrigin, constants);
        float3 coreMax = sparseExpandedGridMaximum(coreOrigin, coreDimensions, constants);
        float3 sampleMin = sparseGridToLocal(storedOrigin, constants);
        float3 sampleMax = sparseGridToLocal(storedEnd - uint3(1), constants);
        brickDescriptors[brickIndex].worldBoundsMin = float4(coreMin, 0.0);
        brickDescriptors[brickIndex].worldBoundsMax = float4(coreMax, 0.0);
        brickDescriptors[brickIndex].localBoundsMin = float4(coreMin, 0.0);
        brickDescriptors[brickIndex].localBoundsMax = float4(coreMax, 0.0);
        brickDescriptors[brickIndex].sampleBoundsMin = float4(sampleMin, threadMinDistances[0]);
        brickDescriptors[brickIndex].sampleBoundsMax = float4(sampleMax, threadMaxDistances[0]);
        brickDescriptors[brickIndex].gridOriginAndVolume = uint4(storedOrigin, 0u);
        brickDescriptors[brickIndex].dimensionsAndSampleOffset = uint4(storedDimensions, sampleOffset);
    }

    for (uint localSampleIndex = localThreadIndex; localSampleIndex < storedSampleCount; localSampleIndex += threadsPerThreadgroup) {
        uint xy = storedDimensions.x * storedDimensions.y;
        uint z = localSampleIndex / xy;
        uint rem = localSampleIndex - z * xy;
        uint y = rem / storedDimensions.x;
        uint x = rem - y * storedDimensions.x;
        uint3 sampleCoordinate = storedOrigin + uint3(x, y, z);
        GPUDistanceFieldProgramSample programSample = sampleProgramField(
            operations,
            constants.metadata.x,
            constants.metadata.y,
            sparseSamplePosition(sampleCoordinate, constants)
        );
        samples[sampleOffset + localSampleIndex] = programSample.field;
        if (packedVectorCount > 0u) {
            uint attributeSampleIndex = attributeOffset + localSampleIndex * packedVectorCount;
            attributeSamples[attributeSampleIndex] = programSample.attributes0;
            if (packedVectorCount > 1u) {
                attributeSamples[attributeSampleIndex + 1u] = programSample.attributes1;
            }
        }
    }
}
