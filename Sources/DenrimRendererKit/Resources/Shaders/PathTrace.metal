#include <metal_stdlib>
#include <metal_raytracing>
using namespace metal;
using namespace raytracing;

struct GPUCamera {
    float4 origin;
    float4 lowerLeft;
    float4 horizontal;
    float4 vertical;
    float4 lens;
};

struct GPUTriangle {
    float4 v0;
    float4 v1;
    float4 v2;
    float4 n0;
    float4 n1;
    float4 n2;
    float4 uv0;
    float4 uv1;
    float4 uv2;
    float4 tangent;
    float4 bitangent;
    uint materialID;
    uint objectID;
    uint primitiveID;
    uint padding2;
};

struct GPUMaterial {
    float4 baseColor;
    float4 emission;
    float4 parameters;
    float4 parameters2;
    float4 specularColor;
    float4 sheenColor;
    float4 transmissionColor;
    float4 parameters3;
    float4 clearcoatColor;
    float4 clearcoatAttenuation;
    float4 transmissionAbsorption;
    float4 thinFilm;
    float4 subsurfaceColor;
    float4 subsurfaceRadius;
    float4 subsurfaceParameters;
    float4 volumeScattering;
    float4 volumeParameters;
};

struct GPUAccelerationNode {
    float4 boundsMin;
    float4 boundsMax;
    uint4 metadata;
};

struct GPUTextureDescriptor {
    uint4 metadata;
};

struct GPULightRecord {
    uint triangleIndex;
    uint materialIndex;
    float area;
    float selectionCDF;
    float4 normal;
};

struct GPUEnvironmentSample {
    float2 distribution;
};

struct GPUVolumeDescriptor {
    float4 worldBoundsMin;
    float4 worldBoundsMax;
    float4 localBoundsMin;
    float4 localBoundsMax;
    uint4 dimensions;
    uint4 metadata;
    uint4 materialProgram;
    float4 worldToLocal0;
    float4 worldToLocal1;
    float4 worldToLocal2;
    float4 worldToLocal3;
    float4 normalTransform0;
    float4 normalTransform1;
    float4 normalTransform2;
    float4 normalTransform3;
};

struct GPUVolumeSample {
    float distance;
    uint materialA;
    uint materialB;
    float materialBlend;
    float4 baseColorOpacity;
    float4 emissionTransmission;
    float4 surface;
    uint4 materialFieldFlags;
};

struct GPUVolumeBrickSample {
    float distance;
    uint materialA;
    uint materialB;
    float materialBlend;
};

struct GPUVolumeMaterialFieldSample {
    float4 baseColorOpacity;
    float4 emissionTransmission;
    float4 surface;
    uint4 materialFieldFlags;
};

struct GPUVolumeAttributeDescriptor {
    uint4 metadata;
    uint4 reserved0;
    uint4 reserved1;
};

struct GPUMaterialProgramDescriptor {
    uint4 metadata;
};

struct GPUMaterialProgramOperation {
    uint4 metadata;
    float4 data0;
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

struct GPURenderConstants {
    uint width;
    uint height;
    uint triangleCount;
    uint volumeCount;
    uint materialCount;
    uint sampleIndex;
    uint maxBounces;
    uint renderQuality;
    uint frameSeed;
    uint accelerationNodeCount;
    uint transparentBackground;
    uint showsEnvironmentBackground;
    uint lightCount;
    uint environmentTextureIndexPlusOne;
    uint environmentDistributionCount;
    float environmentIntensity;
    float environmentRotationY;
    float environmentMaxRadiance;
    float sampleRadianceClamp;
    float4 backgroundColor;
    uint volumeSampleCount;
    uint volumeAttributeSampleCount;
    uint volumeBrickCount;
    uint volumeBrickSampleCount;
    uint volumeBrickMaterialFieldSampleCount;
    uint volumeBrickAttributeSampleCount;
    uint volumeBrickBVHNodeCount;
    uint volumeBrickBVHIndexCount;
    uint volumeBrickGridCount;
    uint volumeBrickGridIndexCount;
    uint materialProgramCount;
    uint materialProgramOperationCount;
    uint denoiserEnabled;
    uint sdfTraversalStatsEnabled;
    uint tileX;
    uint tileY;
    uint tileWidth;
    uint tileHeight;
};

constant uint sdfCounterDenseVolumeTests = 0u;
constant uint sdfCounterDenseMarchSteps = 1u;
constant uint sdfCounterSparseGridCellsVisited = 2u;
constant uint sdfCounterSparseGridMacroSkips = 3u;
constant uint sdfCounterSparseBrickTests = 4u;
constant uint sdfCounterSparseBrickInvalid = 5u;
constant uint sdfCounterSparseBrickRangeCulls = 6u;
constant uint sdfCounterSparseBrickMarches = 7u;
constant uint sdfCounterSparseBrickMarchSteps = 8u;
constant uint sdfCounterSparseBrickHits = 9u;
constant uint sdfCounterPrimarySceneQueries = 10u;
constant uint sdfCounterBounceSceneQueries = 11u;
constant uint sdfCounterShadowSceneQueries = 12u;

static void addSDFTraversalCounter(
    device atomic_uint *sdfCounters,
    constant GPURenderConstants &constants,
    uint index,
    uint value = 1u
) {
    if (constants.sdfTraversalStatsEnabled != 0u && sdfCounters != nullptr) {
        atomic_fetch_add_explicit(&sdfCounters[index], value, memory_order_relaxed);
    }
}

struct GPURayTracingInstance {
    uint4 metadata;
    float4 normalTransform0;
    float4 normalTransform1;
    float4 normalTransform2;
    float4 normalTransform3;
};

struct Ray {
    float3 origin;
    float3 direction;
};

struct Hit {
    bool hit;
    float t;
    float3 position;
    float3 localPosition;
    float3 normal;
    float2 uv;
    float3 tangent;
    float3 bitangent;
    uint materialID;
    uint materialID2;
    float materialBlend;
    float4 volumeBaseColorOpacity;
    float4 volumeEmissionTransmission;
    float4 volumeSurface;
    uint volumeMaterialFieldFlags;
    uint materialProgramIndex;
    float4 volumeAttributes0;
    float4 volumeAttributes1;
    uint4 volumeAttributeSemantics0;
    uint4 volumeAttributeSemantics1;
    uint objectID;
    uint primitiveID;
    bool frontFacing;
};

constant uint volumeMaterialFieldBaseColor = 1u << 0;
constant uint volumeMaterialFieldOpacity = 1u << 1;
constant uint volumeMaterialFieldEmission = 1u << 2;
constant uint volumeMaterialFieldRoughness = 1u << 3;
constant uint volumeMaterialFieldMetallic = 1u << 4;
constant uint volumeMaterialFieldTransmission = 1u << 5;
constant uint volumeMaterialFieldSpecular = 1u << 6;
constant uint volumeMaterialFieldEmissionStrength = 1u << 7;

static uint hash(uint value) {
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    value ^= value >> 16;
    return value;
}

static float randomFloat(thread uint &state) {
    state = hash(state);
    return (float)(state & 0x00ffffffu) / (float)0x01000000u;
}

static float3 cosineHemisphere(float2 u) {
    float r = sqrt(u.x);
    float phi = 6.28318530718f * u.y;
    return float3(r * cos(phi), r * sin(phi), sqrt(max(0.0f, 1.0f - u.x)));
}

static float2 uniformDisk(float2 u) {
    float r = sqrt(u.x);
    float phi = 6.28318530718f * u.y;
    return float2(r * cos(phi), r * sin(phi));
}

static float3 uniformSphere(float2 u) {
    float z = 1.0f - 2.0f * u.x;
    float r = sqrt(max(0.0f, 1.0f - z * z));
    float phi = 6.28318530718f * u.y;
    return float3(r * cos(phi), r * sin(phi), z);
}

static float3 orientHemisphere(float3 localDirection, float3 normal) {
    float3 helper = fabs(normal.y) < 0.999f ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 tangent = normalize(cross(helper, normal));
    float3 bitangent = cross(normal, tangent);
    return normalize(localDirection.x * tangent + localDirection.y * bitangent + localDirection.z * normal);
}

static float3 orientAroundDirection(float3 localDirection, float3 direction) {
    float3 helper = fabs(direction.y) < 0.999f ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 tangent = normalize(cross(helper, direction));
    float3 bitangent = cross(direction, tangent);
    return normalize(localDirection.x * tangent + localDirection.y * bitangent + localDirection.z * direction);
}

static float3 sampleHenyeyGreenstein(float2 u, float3 direction, float anisotropy) {
    float g = clamp(anisotropy, -0.95f, 0.95f);
    if (fabs(g) < 1e-4f) {
        return uniformSphere(u);
    }

    float oneMinusGSquared = 1.0f - g * g;
    float denominator = 1.0f - g + 2.0f * g * u.x;
    float cosTheta = (1.0f + g * g - (oneMinusGSquared / max(denominator, 1e-5f)) * (oneMinusGSquared / max(denominator, 1e-5f))) / (2.0f * g);
    cosTheta = clamp(cosTheta, -1.0f, 1.0f);
    float sinTheta = sqrt(max(0.0f, 1.0f - cosTheta * cosTheta));
    float phi = 6.28318530718f * u.y;
    return orientAroundDirection(float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta), direction);
}

static float maxComponent(float3 value) {
    return max(value.x, max(value.y, value.z));
}

static float3 clampSampleContribution(float3 contribution, constant GPURenderConstants &constants) {
    if (!all(isfinite(contribution))) {
        return float3(0.0f);
    }

    float clampValue = max(constants.sampleRadianceClamp, 0.0f);
    if (clampValue <= 0.0f) {
        return contribution;
    }

    float peak = maxComponent(contribution);
    if (peak <= clampValue) {
        return contribution;
    }

    return contribution * (clampValue / max(peak, 1e-5f));
}

static float luminance(float3 value) {
    return dot(value, float3(0.2126f, 0.7152f, 0.0722f));
}

static float3 fresnelSchlick(float cosTheta, float3 f0) {
    float factor = pow(clamp(1.0f - cosTheta, 0.0f, 1.0f), 5.0f);
    return f0 + (float3(1.0f) - f0) * factor;
}

static float3 thinFilmTint(GPUMaterial material, float cosTheta) {
    float strength = clamp(material.thinFilm.x, 0.0f, 1.0f);
    float thickness = max(material.thinFilm.y, 0.0f);
    if (strength <= 0.0f || thickness <= 0.0f) {
        return float3(1.0f);
    }

    float filmIOR = max(material.thinFilm.z, 1.0001f);
    float angle = pow(clamp(1.0f - cosTheta, 0.0f, 1.0f), 0.65f);
    float opticalPath = 2.0f * filmIOR * thickness * (0.62f + 0.42f * angle);
    float3 wavelengths = float3(650.0f, 510.0f, 475.0f);
    float3 phase = 6.28318530718f * opticalPath / wavelengths;
    float3 interference = 0.62f + 0.38f * cos(phase);
    float normalizedLuminance = max(luminance(interference), 0.35f);
    float3 tint = clamp(interference / normalizedLuminance, float3(0.35f), float3(1.8f));
    return mix(float3(1.0f), tint, strength);
}

static float3 fresnelSchlickThinFilm(float cosTheta, float3 f0, GPUMaterial material) {
    return fresnelSchlick(cosTheta, f0) * thinFilmTint(material, cosTheta);
}

static float dielectricFresnel(float cosThetaI, float etaI, float etaT) {
    cosThetaI = clamp(cosThetaI, 0.0f, 1.0f);
    float eta = etaI / etaT;
    float sinThetaTSquared = eta * eta * max(0.0f, 1.0f - cosThetaI * cosThetaI);
    if (sinThetaTSquared >= 1.0f) {
        return 1.0f;
    }

    float cosThetaT = sqrt(max(0.0f, 1.0f - sinThetaTSquared));
    float parallel = ((etaT * cosThetaI) - (etaI * cosThetaT))
        / max((etaT * cosThetaI) + (etaI * cosThetaT), 1e-5f);
    float perpendicular = ((etaI * cosThetaI) - (etaT * cosThetaT))
        / max((etaI * cosThetaI) + (etaT * cosThetaT), 1e-5f);
    return clamp(0.5f * (parallel * parallel + perpendicular * perpendicular), 0.0f, 1.0f);
}

static float dielectricF0(float indexOfRefraction, float specularWeight) {
    float ior = max(indexOfRefraction, 1.0f);
    float f0 = (ior - 1.0f) / (ior + 1.0f);
    return f0 * f0 * clamp(specularWeight, 0.0f, 1.0f);
}

static float3 materialF0(GPUMaterial material) {
    float metallic = clamp(material.parameters.y, 0.0f, 1.0f);
    float dielectric = dielectricF0(material.parameters2.y, material.parameters2.x);
    float3 dielectricColor = dielectric * clamp(material.specularColor.xyz, float3(0.0f), float3(1.0f));
    return mix(dielectricColor, material.baseColor.xyz, metallic);
}

static float materialClearcoat(GPUMaterial material) {
    return clamp(material.parameters2.z, 0.0f, 1.0f);
}

static float materialClearcoatRoughness(GPUMaterial material) {
    return clamp(material.parameters2.w, 0.02f, 1.0f);
}

static float materialClearcoatThickness(GPUMaterial material) {
    return max(material.clearcoatAttenuation.w, 0.0f);
}

static float materialClearcoatF0(GPUMaterial material) {
    return dielectricF0(material.specularColor.w, 1.0f);
}

static float3 materialClearcoatF0Color(GPUMaterial material) {
    return materialClearcoatF0(material)
        * clamp(material.clearcoatColor.xyz, float3(0.0f), float3(1.0f));
}

static float3 materialClearcoatAttenuationColor(GPUMaterial material) {
    return clamp(material.clearcoatAttenuation.xyz, float3(0.0001f), float3(1.0f));
}

static float3 materialClearcoatDepthAttenuation(
    GPUMaterial material,
    float3 normal,
    float3 viewDirection,
    float3 lightDirection
) {
    float thickness = materialClearcoatThickness(material) * materialClearcoat(material);
    if (thickness <= 1e-5f) {
        return float3(1.0f);
    }

    float nDotV = max(dot(normal, viewDirection), 0.05f);
    float nDotL = max(dot(normal, lightDirection), 0.05f);
    float pathLength = thickness * 0.5f * (1.0f / nDotV + 1.0f / nDotL);
    return exp(log(materialClearcoatAttenuationColor(material)) * pathLength);
}

static float materialSpecularAnisotropy(GPUMaterial material) {
    return clamp(material.parameters3.w, -0.95f, 0.95f);
}

static float materialTransmission(GPUMaterial material) {
    return clamp(material.emission.w, 0.0f, 1.0f);
}

static float3 materialTransmissionColor(GPUMaterial material) {
    return clamp(material.transmissionColor.xyz, float3(0.0f), float3(1.0f));
}

static bool materialThinWalled(GPUMaterial material) {
    return material.transmissionColor.w > 0.5f;
}

static float materialTransmissionRoughness(GPUMaterial material) {
    return clamp(material.parameters3.y, 0.001f, 1.0f);
}

static float materialTransmissionIOR(GPUMaterial material) {
    return max(material.parameters3.z, 1.0001f);
}

static float materialSheen(GPUMaterial material) {
    return clamp(material.sheenColor.w, 0.0f, 1.0f);
}

static float3 materialSheenColor(GPUMaterial material) {
    return clamp(material.sheenColor.xyz, float3(0.0f), float3(1.0f));
}

static float materialSheenRoughness(GPUMaterial material) {
    return clamp(material.parameters3.x, 0.02f, 1.0f);
}

static float materialSubsurface(GPUMaterial material) {
    float metallic = clamp(material.parameters.y, 0.0f, 1.0f);
    float transmission = materialTransmission(material);
    return clamp(material.subsurfaceColor.w, 0.0f, 1.0f) * (1.0f - metallic) * (1.0f - transmission);
}

static float3 materialSubsurfaceColor(GPUMaterial material) {
    return clamp(material.subsurfaceColor.xyz, float3(0.0f), float3(0.999f));
}

static float3 materialSubsurfaceRadius(GPUMaterial material) {
    float scale = max(material.subsurfaceRadius.w, 0.0f);
    return max(material.subsurfaceRadius.xyz * scale, float3(1e-4f));
}

static float materialSubsurfaceAnisotropy(GPUMaterial material) {
    return clamp(material.subsurfaceParameters.x, -0.95f, 0.95f);
}

static float3 materialTransmissionTint(GPUMaterial material, float strength) {
    return mix(float3(1.0f), materialTransmissionColor(material), strength);
}

static float3 materialTransmissionAbsorptionCoefficient(GPUMaterial material) {
    float referenceDistance = material.transmissionAbsorption.w;
    if (referenceDistance <= 1e-5f) {
        return float3(0.0f);
    }

    float3 referenceColor = clamp(material.transmissionAbsorption.xyz, float3(0.0001f), float3(1.0f));
    return -log(referenceColor) / referenceDistance;
}

static float3 materialTransmissionAbsorption(GPUMaterial material, float distance, bool applies) {
    if (!applies || distance <= 0.0f) {
        return float3(1.0f);
    }

    return exp(-materialTransmissionAbsorptionCoefficient(material) * distance);
}

static float materialVolumeScattering(GPUMaterial material) {
    return clamp(material.volumeScattering.w, 0.0f, 1.0f);
}

static float3 materialVolumeScatteringColor(GPUMaterial material) {
    return clamp(material.volumeScattering.xyz, float3(0.0f), float3(1.0f));
}

static float materialVolumeScatteringDistance(GPUMaterial material) {
    return max(material.volumeParameters.x, 1e-4f);
}

static float materialVolumeAnisotropy(GPUMaterial material) {
    return clamp(material.volumeParameters.y, -0.95f, 0.95f);
}

static bool materialHasVolumeScattering(GPUMaterial material) {
    return materialTransmission(material) > 0.0f
        && !materialThinWalled(material)
        && materialVolumeScattering(material) > 0.0f;
}

static GPUMaterial blendMaterials(GPUMaterial a, GPUMaterial b, float blend) {
    float t = clamp(blend, 0.0f, 1.0f);
    a.baseColor = mix(a.baseColor, b.baseColor, t);
    a.emission = mix(a.emission, b.emission, t);
    a.parameters = mix(a.parameters, b.parameters, t);
    a.parameters2 = mix(a.parameters2, b.parameters2, t);
    a.specularColor = mix(a.specularColor, b.specularColor, t);
    a.sheenColor = mix(a.sheenColor, b.sheenColor, t);
    a.transmissionColor = mix(a.transmissionColor, b.transmissionColor, t);
    a.parameters3 = mix(a.parameters3, b.parameters3, t);
    a.clearcoatColor = mix(a.clearcoatColor, b.clearcoatColor, t);
    a.clearcoatAttenuation = mix(a.clearcoatAttenuation, b.clearcoatAttenuation, t);
    a.transmissionAbsorption = mix(a.transmissionAbsorption, b.transmissionAbsorption, t);
    a.thinFilm = mix(a.thinFilm, b.thinFilm, t);
    a.subsurfaceColor = mix(a.subsurfaceColor, b.subsurfaceColor, t);
    a.subsurfaceRadius = mix(a.subsurfaceRadius, b.subsurfaceRadius, t);
    a.subsurfaceParameters = mix(a.subsurfaceParameters, b.subsurfaceParameters, t);
    a.volumeScattering = mix(a.volumeScattering, b.volumeScattering, t);
    a.volumeParameters = mix(a.volumeParameters, b.volumeParameters, t);
    return a;
}

static GPUMaterial applyVolumeMaterialFields(GPUMaterial material, Hit hit) {
    uint flags = hit.volumeMaterialFieldFlags;
    if ((flags & volumeMaterialFieldBaseColor) != 0u) {
        material.baseColor.xyz = max(hit.volumeBaseColorOpacity.xyz, float3(0.0f));
    }
    if ((flags & volumeMaterialFieldOpacity) != 0u) {
        material.baseColor.w = clamp(hit.volumeBaseColorOpacity.w, 0.0f, 1.0f);
    }
    if ((flags & volumeMaterialFieldEmission) != 0u) {
        material.emission.xyz = max(hit.volumeEmissionTransmission.xyz, float3(0.0f));
    }
    if (((flags & volumeMaterialFieldEmission) != 0u) && ((flags & volumeMaterialFieldEmissionStrength) != 0u)) {
        material.emission.xyz = max(hit.volumeEmissionTransmission.xyz, float3(0.0f))
            * max(hit.volumeSurface.w, 0.0f);
    } else if ((flags & volumeMaterialFieldEmissionStrength) != 0u) {
        material.emission.xyz = max(material.emission.xyz, float3(0.0f)) * max(hit.volumeSurface.w, 0.0f);
    }
    if ((flags & volumeMaterialFieldTransmission) != 0u) {
        material.emission.w = clamp(hit.volumeEmissionTransmission.w, 0.0f, 1.0f);
    }
    if ((flags & volumeMaterialFieldRoughness) != 0u) {
        material.parameters.x = clamp(hit.volumeSurface.x, 0.02f, 1.0f);
    }
    if ((flags & volumeMaterialFieldMetallic) != 0u) {
        material.parameters.y = clamp(hit.volumeSurface.y, 0.0f, 1.0f);
    }
    if ((flags & volumeMaterialFieldSpecular) != 0u) {
        material.parameters2.x = clamp(hit.volumeSurface.z, 0.0f, 1.0f);
    }
    return material;
}

static float materialProgramBoxDistance(float3 local, float3 halfExtents, float cornerRadius) {
    float3 q = abs(local) - halfExtents;
    return length(max(q, float3(0.0)))
        + min(max(q.x, max(q.y, q.z)), 0.0)
        - max(cornerRadius, 0.0);
}

static float materialProgramCylinderDistance(float3 local, float radius, float halfHeight) {
    float2 d = float2(length(local.xz), abs(local.y)) - float2(radius, halfHeight);
    return min(max(d.x, d.y), 0.0) + length(max(d, float2(0.0)));
}

static float materialProgramTaperedCapsuleDistance(
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

static float3 materialProgramCubicBezierPoint(
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

static float materialProgramSplineTubeDistance(
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
        float3 point = materialProgramCubicBezierPoint(control0, control1, control2, control3, t);
        float radius = max(mix(startRadius, endRadius, t), 0.0);
        bestDistance = min(
            bestDistance,
            materialProgramTaperedCapsuleDistance(
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

static float materialProgramSmoothstep(float edge0, float edge1, float x) {
    float denominator = edge1 - edge0;
    if (abs(denominator) <= 1.0e-8) {
        return x < edge0 ? 0.0 : 1.0;
    }
    float t = clamp((x - edge0) / denominator, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

static float materialProgramHash3(float3 cell, float seed) {
    return fract(sin(dot(cell, float3(127.1, 311.7, 74.7)) + seed * 101.3) * 43758.5453);
}

static float materialProgramValueNoise3D(float3 position, float scale, float seed) {
    float3 p = position * max(scale, 1.0e-6);
    float3 cell = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);

    float c000 = materialProgramHash3(cell + float3(0.0, 0.0, 0.0), seed);
    float c100 = materialProgramHash3(cell + float3(1.0, 0.0, 0.0), seed);
    float c010 = materialProgramHash3(cell + float3(0.0, 1.0, 0.0), seed);
    float c110 = materialProgramHash3(cell + float3(1.0, 1.0, 0.0), seed);
    float c001 = materialProgramHash3(cell + float3(0.0, 0.0, 1.0), seed);
    float c101 = materialProgramHash3(cell + float3(1.0, 0.0, 1.0), seed);
    float c011 = materialProgramHash3(cell + float3(0.0, 1.0, 1.0), seed);
    float c111 = materialProgramHash3(cell + float3(1.0, 1.0, 1.0), seed);

    float x00 = mix(c000, c100, u.x);
    float x10 = mix(c010, c110, u.x);
    float x01 = mix(c001, c101, u.x);
    float x11 = mix(c011, c111, u.x);
    return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z);
}

static float materialProgramFBM3D(float3 position, float scale, float octaves, float lacunarity, float gain, float seed) {
    uint octaveCount = clamp(uint(floor(octaves)), 1u, 8u);
    float frequency = max(scale, 1.0e-6);
    float amplitude = 0.5;
    float sum = 0.0;
    float normalization = 0.0;
    for (uint octave = 0u; octave < octaveCount; ++octave) {
        sum += materialProgramValueNoise3D(position, frequency, seed + float(octave) * 17.17) * amplitude;
        normalization += amplitude;
        frequency *= max(lacunarity, 1.0e-6);
        amplitude *= max(gain, 0.0);
    }
    return normalization > 1.0e-8 ? sum / normalization : 0.0;
}

static float3 materialProgramCellular3D(float3 position, float scale, float seed) {
    float3 p = position * max(scale, 1.0e-6);
    float3 base = floor(p);
    float nearest = INFINITY;
    float secondNearest = INFINITY;
    float nearestID = 0.0;

    for (int z = -1; z <= 1; ++z) {
        for (int y = -1; y <= 1; ++y) {
            for (int x = -1; x <= 1; ++x) {
                float3 cell = base + float3(float(x), float(y), float(z));
                float3 feature = float3(
                    materialProgramHash3(cell, seed + 11.1),
                    materialProgramHash3(cell, seed + 37.7),
                    materialProgramHash3(cell, seed + 71.3)
                );
                float candidateDistance = length(cell + feature - p);
                if (candidateDistance < nearest) {
                    secondNearest = nearest;
                    nearest = candidateDistance;
                    nearestID = materialProgramHash3(cell, seed + 149.9);
                } else if (candidateDistance < secondNearest) {
                    secondNearest = candidateDistance;
                }
            }
        }
    }

    return float3(nearest, secondNearest, nearestID);
}

static float materialScalarInput(GPUMaterial material, uint input, Hit hit) {
    switch (input) {
        case 0u: return material.parameters.x;
        case 1u: return material.parameters.y;
        case 2u: return material.parameters2.x;
        case 3u: return material.emission.w;
        case 4u: return material.baseColor.w;
        case 5u: return length(material.emission.xyz);
        case 6u: return hit.materialBlend;
        default: return 0.0f;
    }
}

static float3 materialVectorInput(GPUMaterial material, uint input, Hit hit) {
    switch (input) {
        case 0u: return hit.position;
        case 1u: return hit.localPosition;
        case 2u: return hit.normal;
        case 3u: return float3(0.0f);
        case 4u: return material.baseColor.xyz;
        case 5u: return material.emission.xyz;
        default: return float3(0.0f);
    }
}

static float materialAttribute(Hit hit, uint channel) {
    if (channel < 4u) {
        return hit.volumeAttributes0[channel];
    }
    if (channel < 8u) {
        return hit.volumeAttributes1[channel - 4u];
    }
    return 0.0f;
}

static void writeScalarMaterialProgramField(thread GPUMaterial &material, uint field, float value) {
    switch (field) {
        case 2u:
            material.parameters.x = clamp(value, 0.02f, 1.0f);
            break;
        case 3u:
            material.parameters.y = clamp(value, 0.0f, 1.0f);
            break;
        case 4u:
            material.parameters2.x = clamp(value, 0.0f, 1.0f);
            break;
        case 5u:
            material.emission.w = clamp(value, 0.0f, 1.0f);
            break;
        case 6u:
            material.baseColor.w = clamp(value, 0.0f, 1.0f);
            break;
        case 8u:
            material.emission.xyz = max(material.emission.xyz, float3(0.0f)) * max(value, 0.0f);
            break;
        default:
            break;
    }
}

static void writeVectorMaterialProgramField(thread GPUMaterial &material, uint field, float3 value) {
    switch (field) {
        case 0u:
        case 1u:
            material.baseColor.xyz = max(value, float3(0.0f));
            break;
        case 7u:
            material.emission.xyz = max(value, float3(0.0f));
            break;
        default:
            break;
    }
}

static GPUMaterial applyDistanceFieldMaterialProgram(
    GPUMaterial material,
    Hit hit,
    constant GPUMaterialProgramDescriptor *programDescriptors,
    constant GPUMaterialProgramOperation *programOperations,
    uint materialProgramCount,
    uint materialProgramOperationCount
) {
    if (hit.materialProgramIndex == 0xffffffffu
        || hit.materialProgramIndex >= materialProgramCount
        || programDescriptors == nullptr
        || programOperations == nullptr) {
        return material;
    }

    constant GPUMaterialProgramDescriptor &descriptor = programDescriptors[hit.materialProgramIndex];
    uint offset = descriptor.metadata.x;
    uint count = descriptor.metadata.y;
    if (offset >= materialProgramOperationCount) {
        return material;
    }
    count = min(count, materialProgramOperationCount - offset);

    float scalarRegisters[32];
    float3 vectorRegisters[32];
    float masks[4];
    for (uint index = 0u; index < 32u; ++index) {
        scalarRegisters[index] = 0.0f;
    }
    for (uint index = 0u; index < 32u; ++index) {
        vectorRegisters[index] = float3(0.0f);
    }
    for (uint index = 0u; index < 4u; ++index) {
        masks[index] = 0.0f;
    }

    for (uint operationIndex = 0u; operationIndex < count; ++operationIndex) {
        constant GPUMaterialProgramOperation &operation = programOperations[offset + operationIndex];
        switch (operation.metadata.x) {
            case 1u:
                vectorRegisters[operation.metadata.y & 31u] = materialVectorInput(material, operation.metadata.z, hit);
                break;
            case 2u:
                scalarRegisters[operation.metadata.y & 31u] = materialScalarInput(material, operation.metadata.z, hit);
                break;
            case 3u:
                scalarRegisters[operation.metadata.y & 31u] = materialAttribute(hit, operation.metadata.z);
                break;
            case 10u:
                scalarRegisters[operation.metadata.y & 31u] = operation.data0.x;
                break;
            case 11u:
                vectorRegisters[operation.metadata.y & 31u] = operation.data0.xyz;
                break;
            case 20u:
                scalarRegisters[operation.metadata.y & 31u] = scalarRegisters[operation.metadata.z & 31u] + scalarRegisters[operation.metadata.w & 31u];
                break;
            case 21u:
                scalarRegisters[operation.metadata.y & 31u] = scalarRegisters[operation.metadata.z & 31u] - scalarRegisters[operation.metadata.w & 31u];
                break;
            case 22u:
                scalarRegisters[operation.metadata.y & 31u] = scalarRegisters[operation.metadata.z & 31u] * scalarRegisters[operation.metadata.w & 31u];
                break;
            case 23u:
                scalarRegisters[operation.metadata.y & 31u] = scalarRegisters[operation.metadata.z & 31u] / max(abs(scalarRegisters[operation.metadata.w & 31u]), 1e-6f);
                break;
            case 26u:
                scalarRegisters[operation.metadata.y & 31u] = -scalarRegisters[operation.metadata.z & 31u];
                break;
            case 27u:
                scalarRegisters[operation.metadata.y & 31u] = min(scalarRegisters[operation.metadata.z & 31u], scalarRegisters[operation.metadata.w & 31u]);
                break;
            case 28u:
                scalarRegisters[operation.metadata.y & 31u] = max(scalarRegisters[operation.metadata.z & 31u], scalarRegisters[operation.metadata.w & 31u]);
                break;
            case 29u:
                scalarRegisters[operation.metadata.y & 31u] = abs(scalarRegisters[operation.metadata.z & 31u]);
                break;
            case 34u:
                scalarRegisters[operation.metadata.y & 31u] = sin(scalarRegisters[operation.metadata.z & 31u]);
                break;
            case 35u:
                scalarRegisters[operation.metadata.y & 31u] = cos(scalarRegisters[operation.metadata.z & 31u]);
                break;
            case 36u:
                scalarRegisters[operation.metadata.y & 31u] = clamp(
                    scalarRegisters[operation.metadata.z & 31u],
                    scalarRegisters[operation.metadata.w & 31u],
                    scalarRegisters[uint(operation.data0.x) & 31u]
                );
                break;
            case 24u:
                scalarRegisters[operation.metadata.y & 31u] = clamp(scalarRegisters[operation.metadata.z & 31u], operation.data0.x, operation.data0.y);
                break;
            case 25u:
                scalarRegisters[operation.metadata.y & 31u] = mix(
                    scalarRegisters[operation.metadata.z & 31u],
                    scalarRegisters[operation.metadata.w & 31u],
                    scalarRegisters[uint(operation.data0.x) & 31u]
                );
                break;
            case 74u:
                scalarRegisters[operation.metadata.y & 31u] = materialProgramSmoothstep(
                    scalarRegisters[operation.metadata.z & 31u],
                    scalarRegisters[operation.metadata.w & 31u],
                    scalarRegisters[uint(operation.data0.x) & 31u]
                );
                break;
            case 75u:
                scalarRegisters[operation.metadata.y & 31u] = scalarRegisters[operation.metadata.w & 31u] < scalarRegisters[operation.metadata.z & 31u] ? 0.0 : 1.0;
                break;
            case 76u:
                scalarRegisters[operation.metadata.y & 31u] = clamp(scalarRegisters[operation.metadata.z & 31u], 0.0, 1.0);
                break;
            case 77u:
                scalarRegisters[operation.metadata.y & 31u] = fract(scalarRegisters[operation.metadata.z & 31u]);
                break;
            case 78u:
                scalarRegisters[operation.metadata.y & 31u] = floor(scalarRegisters[operation.metadata.z & 31u]);
                break;
            case 79u: {
                float divisor = scalarRegisters[operation.metadata.w & 31u];
                scalarRegisters[operation.metadata.y & 31u] = abs(divisor) > 1.0e-8 ? fmod(scalarRegisters[operation.metadata.z & 31u], divisor) : 0.0;
                break;
            }
            case 30u:
                vectorRegisters[operation.metadata.y & 31u] = float3(
                    scalarRegisters[operation.metadata.z & 31u],
                    scalarRegisters[operation.metadata.w & 31u],
                    scalarRegisters[uint(operation.data0.x) & 31u]
                );
                break;
            case 31u:
                scalarRegisters[operation.metadata.y & 31u] = vectorRegisters[operation.metadata.z & 31u].x;
                break;
            case 32u:
                scalarRegisters[operation.metadata.y & 31u] = vectorRegisters[operation.metadata.z & 31u].y;
                break;
            case 33u:
                scalarRegisters[operation.metadata.y & 31u] = vectorRegisters[operation.metadata.z & 31u].z;
                break;
            case 60u:
                vectorRegisters[operation.metadata.y & 31u] = vectorRegisters[operation.metadata.z & 31u] + vectorRegisters[operation.metadata.w & 31u];
                break;
            case 61u:
                vectorRegisters[operation.metadata.y & 31u] = vectorRegisters[operation.metadata.z & 31u] - vectorRegisters[operation.metadata.w & 31u];
                break;
            case 62u:
                vectorRegisters[operation.metadata.y & 31u] = vectorRegisters[operation.metadata.z & 31u] * scalarRegisters[operation.metadata.w & 31u];
                break;
            case 63u:
                vectorRegisters[operation.metadata.y & 31u] = abs(vectorRegisters[operation.metadata.z & 31u]);
                break;
            case 64u:
                vectorRegisters[operation.metadata.y & 31u] = max(vectorRegisters[operation.metadata.z & 31u], float3(scalarRegisters[operation.metadata.w & 31u]));
                break;
            case 65u:
                vectorRegisters[operation.metadata.y & 31u] = min(vectorRegisters[operation.metadata.z & 31u], float3(scalarRegisters[operation.metadata.w & 31u]));
                break;
            case 66u:
                scalarRegisters[operation.metadata.y & 31u] = length(vectorRegisters[operation.metadata.z & 31u]);
                break;
            case 80u:
                scalarRegisters[operation.metadata.y & 31u] = dot(vectorRegisters[operation.metadata.z & 31u], vectorRegisters[operation.metadata.w & 31u]);
                break;
            case 81u: {
                float3 source = vectorRegisters[operation.metadata.z & 31u];
                float sourceLength = length(source);
                vectorRegisters[operation.metadata.y & 31u] = sourceLength > 1.0e-8 ? source / sourceLength : float3(0.0);
                break;
            }
            case 82u:
                scalarRegisters[operation.metadata.y & 31u] = distance(vectorRegisters[operation.metadata.z & 31u], vectorRegisters[operation.metadata.w & 31u]);
                break;
            case 83u:
                scalarRegisters[operation.metadata.y & 31u] = materialProgramValueNoise3D(
                    vectorRegisters[operation.metadata.z & 31u],
                    scalarRegisters[operation.metadata.w & 31u],
                    scalarRegisters[uint(operation.data0.x) & 31u]
                );
                break;
            case 84u:
                scalarRegisters[operation.metadata.y & 31u] = materialProgramFBM3D(
                    vectorRegisters[operation.metadata.z & 31u],
                    scalarRegisters[operation.metadata.w & 31u],
                    scalarRegisters[uint(operation.data0.x) & 31u],
                    scalarRegisters[uint(operation.data0.y) & 31u],
                    scalarRegisters[uint(operation.data0.z) & 31u],
                    scalarRegisters[uint(operation.data0.w) & 31u]
                );
                break;
            case 85u: {
                float3 cellular = materialProgramCellular3D(
                    vectorRegisters[uint(operation.data0.x) & 31u],
                    scalarRegisters[uint(operation.data0.y) & 31u],
                    scalarRegisters[uint(operation.data0.z) & 31u]
                );
                scalarRegisters[operation.metadata.y & 31u] = cellular.x;
                scalarRegisters[operation.metadata.z & 31u] = cellular.y;
                scalarRegisters[operation.metadata.w & 31u] = cellular.z;
                break;
            }
            case 70u:
                scalarRegisters[operation.metadata.y & 31u] = materialProgramBoxDistance(
                    vectorRegisters[operation.metadata.z & 31u],
                    vectorRegisters[operation.metadata.w & 31u],
                    scalarRegisters[uint(operation.data0.x) & 31u]
                );
                break;
            case 71u:
                scalarRegisters[operation.metadata.y & 31u] = materialProgramCylinderDistance(
                    vectorRegisters[operation.metadata.z & 31u],
                    scalarRegisters[operation.metadata.w & 31u],
                    scalarRegisters[uint(operation.data0.x) & 31u]
                );
                break;
            case 72u:
                scalarRegisters[operation.metadata.y & 31u] = materialProgramTaperedCapsuleDistance(
                    vectorRegisters[operation.metadata.z & 31u],
                    vectorRegisters[operation.metadata.w & 31u],
                    vectorRegisters[uint(operation.data0.x) & 31u],
                    scalarRegisters[uint(operation.data0.y) & 31u],
                    scalarRegisters[uint(operation.data0.z) & 31u]
                );
                break;
            case 73u: {
                uint packedRadii = uint(operation.data0.w);
                scalarRegisters[operation.metadata.y & 31u] = materialProgramSplineTubeDistance(
                    vectorRegisters[operation.metadata.z & 31u],
                    vectorRegisters[operation.metadata.w & 31u],
                    vectorRegisters[uint(operation.data0.x) & 31u],
                    vectorRegisters[uint(operation.data0.y) & 31u],
                    vectorRegisters[uint(operation.data0.z) & 31u],
                    scalarRegisters[packedRadii & 255u],
                    scalarRegisters[(packedRadii >> 8u) & 255u]
                );
                break;
            }
            case 40u:
                if (operation.metadata.y < 4u) {
                    masks[operation.metadata.y] = clamp(scalarRegisters[operation.metadata.z & 31u], 0.0f, 1.0f);
                }
                break;
            case 41u:
                if (operation.metadata.y < 4u) {
                    scalarRegisters[operation.metadata.z & 31u] = masks[operation.metadata.y];
                }
                break;
            case 50u:
                writeScalarMaterialProgramField(material, operation.metadata.y, scalarRegisters[operation.metadata.z & 31u]);
                break;
            case 51u:
                writeVectorMaterialProgramField(material, operation.metadata.y, vectorRegisters[operation.metadata.z & 31u]);
                break;
            default:
                break;
        }
    }
    return material;
}

static GPUMaterial materialForHit(
    Hit hit,
    constant GPUMaterial *materials,
    uint materialCount,
    constant GPUMaterialProgramDescriptor *materialProgramDescriptors,
    constant GPUMaterialProgramOperation *materialProgramOperations,
    uint materialProgramCount,
    uint materialProgramOperationCount
) {
    uint materialA = min(hit.materialID, materialCount - 1u);
    GPUMaterial material = materials[materialA];
    if (hit.materialBlend > 0.0f) {
        uint materialB = min(hit.materialID2, materialCount - 1u);
        material = blendMaterials(material, materials[materialB], hit.materialBlend);
    }

    material = applyVolumeMaterialFields(material, hit);
    return applyDistanceFieldMaterialProgram(
        material,
        hit,
        materialProgramDescriptors,
        materialProgramOperations,
        materialProgramCount,
        materialProgramOperationCount
    );
}

static GPUMaterial materialForHit(
    Hit hit,
    constant GPUMaterial *materials,
    uint materialCount
) {
    return materialForHit(
        hit,
        materials,
        materialCount,
        nullptr,
        nullptr,
        0u,
        0u
    );
}

static float3 materialVolumeSigmaS(GPUMaterial material) {
    return materialVolumeScatteringColor(material)
        * materialVolumeScattering(material)
        / materialVolumeScatteringDistance(material);
}

static float3 materialVolumeSigmaT(GPUMaterial material) {
    return materialTransmissionAbsorptionCoefficient(material) + materialVolumeSigmaS(material);
}

static float3 materialVolumeTransmittance(GPUMaterial material, float distance) {
    return exp(-materialVolumeSigmaT(material) * distance);
}

struct TangentFrame {
    float3 tangent;
    float3 bitangent;
};

static TangentFrame makeTangentFrame(float3 normal, float3 rawTangent, float3 rawBitangent) {
    TangentFrame frame;
    float3 tangent = rawTangent - normal * dot(rawTangent, normal);
    if (dot(tangent, tangent) <= 1e-8f) {
        float3 helper = fabs(normal.y) < 0.999f ? float3(0.0f, 1.0f, 0.0f) : float3(1.0f, 0.0f, 0.0f);
        tangent = cross(helper, normal);
    }
    frame.tangent = normalize(tangent);

    float3 bitangent = rawBitangent
        - normal * dot(rawBitangent, normal)
        - frame.tangent * dot(rawBitangent, frame.tangent);
    if (dot(bitangent, bitangent) <= 1e-8f) {
        bitangent = cross(normal, frame.tangent);
    }
    frame.bitangent = normalize(bitangent);
    return frame;
}

static float2 anisotropicGGXAlpha(float roughness, float anisotropy) {
    float alpha = max(roughness * roughness, 0.001f);
    float amount = clamp(anisotropy, -0.95f, 0.95f);
    float aspect = sqrt(max(0.1f, 1.0f - 0.9f * fabs(amount)));
    float alphaLong = alpha / aspect;
    float alphaShort = alpha * aspect;
    return amount >= 0.0f
        ? float2(alphaLong, alphaShort)
        : float2(alphaShort, alphaLong);
}

static float distributionGGX(float nDotH, float roughness) {
    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;
    float denominator = nDotH * nDotH * (alpha2 - 1.0f) + 1.0f;
    return alpha2 / max(3.14159265359f * denominator * denominator, 1e-5f);
}

static float geometrySmithG1GGX(float nDotV, float roughness) {
    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;
    float denominator = nDotV + sqrt(max(alpha2 + (1.0f - alpha2) * nDotV * nDotV, 0.0f));
    return (2.0f * nDotV) / max(denominator, 1e-5f);
}

static float geometrySmith(float nDotV, float nDotL, float roughness) {
    return geometrySmithG1GGX(nDotV, roughness) * geometrySmithG1GGX(nDotL, roughness);
}

static float distributionGGXAnisotropic(
    float3 halfVector,
    float3 normal,
    float3 tangent,
    float3 bitangent,
    float roughness,
    float anisotropy
) {
    float nDotH = max(dot(normal, halfVector), 0.0f);
    if (nDotH <= 0.0f) {
        return 0.0f;
    }

    float2 alpha = anisotropicGGXAlpha(roughness, anisotropy);
    float tDotH = dot(tangent, halfVector);
    float bDotH = dot(bitangent, halfVector);
    float denominator = (tDotH * tDotH) / max(alpha.x * alpha.x, 1e-6f)
        + (bDotH * bDotH) / max(alpha.y * alpha.y, 1e-6f)
        + nDotH * nDotH;
    return 1.0f / max(3.14159265359f * alpha.x * alpha.y * denominator * denominator, 1e-6f);
}

static float geometrySmithG1GGXAnisotropic(
    float3 direction,
    float3 normal,
    float3 tangent,
    float3 bitangent,
    float roughness,
    float anisotropy
) {
    float nDotD = max(dot(normal, direction), 0.0f);
    if (nDotD <= 0.0f) {
        return 0.0f;
    }

    float2 alpha = anisotropicGGXAlpha(roughness, anisotropy);
    float tDotD = dot(tangent, direction);
    float bDotD = dot(bitangent, direction);
    float root = sqrt(max(
        alpha.x * alpha.x * tDotD * tDotD
            + alpha.y * alpha.y * bDotD * bDotD
            + nDotD * nDotD,
        0.0f
    ));
    return (2.0f * nDotD) / max(nDotD + root, 1e-5f);
}

static float geometrySmithAnisotropic(
    float3 viewDirection,
    float3 lightDirection,
    float3 normal,
    float3 tangent,
    float3 bitangent,
    float roughness,
    float anisotropy
) {
    return geometrySmithG1GGXAnisotropic(viewDirection, normal, tangent, bitangent, roughness, anisotropy)
        * geometrySmithG1GGXAnisotropic(lightDirection, normal, tangent, bitangent, roughness, anisotropy);
}

static float3 evaluateMaterialSheenBRDF(
    GPUMaterial material,
    float3 normal,
    float3 viewDirection,
    float3 lightDirection
) {
    float sheen = materialSheen(material);
    if (sheen <= 0.0f) {
        return float3(0.0f);
    }

    float metallic = clamp(material.parameters.y, 0.0f, 1.0f);
    float3 halfDirection = viewDirection + lightDirection;
    if (dot(halfDirection, halfDirection) <= 1e-8f) {
        return float3(0.0f);
    }

    float3 halfVector = normalize(halfDirection);
    float nDotL = max(dot(normal, lightDirection), 0.0f);
    float nDotV = max(dot(normal, viewDirection), 0.0f);
    float nDotH = max(dot(normal, halfVector), 0.0f);
    if (nDotL <= 0.0f || nDotV <= 0.0f) {
        return float3(0.0f);
    }

    float sinThetaH = sqrt(max(0.0f, 1.0f - nDotH * nDotH));
    float inverseAlpha = mix(20.0f, 0.5f, materialSheenRoughness(material));
    float distribution = (2.0f + inverseAlpha) * pow(sinThetaH, inverseAlpha) * 0.15915494309f;
    float visibility = 1.0f / max(4.0f * (nDotL + nDotV - nDotL * nDotV), 1e-5f);
    return sheen
        * (1.0f - metallic)
        * materialSheenColor(material)
        * distribution
        * visibility;
}

static float3 materialClearcoatAttenuationForDirection(
    GPUMaterial material,
    float3 normal,
    float3 viewDirection,
    float3 lightDirection
) {
    float clearcoat = materialClearcoat(material);
    if (clearcoat <= 0.0f) {
        return float3(1.0f);
    }

    float3 halfDirection = viewDirection + lightDirection;
    if (dot(halfDirection, halfDirection) <= 1e-8f) {
        return float3(1.0f);
    }

    float3 halfVector = normalize(halfDirection);
    float vDotH = max(dot(viewDirection, halfVector), 0.0f);
    float3 clearcoatFresnel = fresnelSchlickThinFilm(vDotH, materialClearcoatF0Color(material), material);
    float3 fresnelAttenuation = max(float3(0.0f), float3(1.0f) - clearcoatFresnel * clearcoat);
    return fresnelAttenuation * materialClearcoatDepthAttenuation(
        material,
        normal,
        viewDirection,
        lightDirection
    );
}

static float3 evaluateMaterialBRDF(
    GPUMaterial material,
    float3 normal,
    float3 tangent,
    float3 bitangent,
    float3 viewDirection,
    float3 lightDirection
) {
    constexpr float inversePi = 0.31830988618f;
    float roughness = clamp(material.parameters.x, 0.02f, 1.0f);
    float metallic = clamp(material.parameters.y, 0.0f, 1.0f);
    float3 baseColor = material.baseColor.xyz;
    float3 halfVector = normalize(viewDirection + lightDirection);
    float nDotL = max(dot(normal, lightDirection), 0.0f);
    float nDotV = max(dot(normal, viewDirection), 0.0f);
    float nDotH = max(dot(normal, halfVector), 0.0f);
    float vDotH = max(dot(viewDirection, halfVector), 0.0f);

    if (nDotL <= 0.0f || nDotV <= 0.0f) {
        return float3(0);
    }

    float3 f0 = materialF0(material);
    float3 fresnel = fresnelSchlickThinFilm(vDotH, f0, material);
    TangentFrame frame = makeTangentFrame(normal, tangent, bitangent);
    float anisotropy = materialSpecularAnisotropy(material);
    float distribution = distributionGGXAnisotropic(
        halfVector,
        normal,
        frame.tangent,
        frame.bitangent,
        roughness,
        anisotropy
    );
    float geometry = geometrySmithAnisotropic(
        viewDirection,
        lightDirection,
        normal,
        frame.tangent,
        frame.bitangent,
        roughness,
        anisotropy
    );
    float3 specular = distribution * geometry * fresnel / max(4.0f * nDotV * nDotL, 1e-5f);
    float clearcoat = materialClearcoat(material);
    float clearcoatRoughness = materialClearcoatRoughness(material);
    float3 clearcoatFresnel = fresnelSchlickThinFilm(vDotH, materialClearcoatF0Color(material), material);
    float clearcoatDistribution = distributionGGX(nDotH, clearcoatRoughness);
    float clearcoatGeometry = geometrySmith(nDotV, nDotL, clearcoatRoughness);
    float3 clearcoatSpecular = clearcoatDistribution * clearcoatGeometry * clearcoatFresnel / max(4.0f * nDotV * nDotL, 1e-5f);
    float3 clearcoatAttenuation = materialClearcoatAttenuationForDirection(
        material,
        normal,
        viewDirection,
        lightDirection
    );
    float3 diffuse = clearcoatAttenuation * (float3(1.0f) - fresnel) * (1.0f - metallic) * baseColor * inversePi;
    float3 sheen = evaluateMaterialSheenBRDF(material, normal, viewDirection, lightDirection);

    return diffuse + clearcoatAttenuation * (specular + sheen) + clearcoatSpecular * clearcoat;
}

static float powerHeuristic(float pdfA, float pdfB) {
    float a2 = pdfA * pdfA;
    float b2 = pdfB * pdfB;
    return a2 / max(a2 + b2, 1e-8f);
}

static void materialLobeProbabilities(
    GPUMaterial material,
    thread float &diffuseProbability,
    thread float &specularProbability,
    thread float &clearcoatProbability
) {
    float metallic = clamp(material.parameters.y, 0.0f, 1.0f);
    float3 baseColor = material.baseColor.xyz;
    float3 f0 = materialF0(material);
    float clearcoat = materialClearcoat(material);
    float sheenWeight = materialSheen(material) * luminance(materialSheenColor(material)) * (1.0f - metallic);
    float diffuseWeight = luminance(baseColor * (1.0f - metallic)) + sheenWeight;
    float specularWeight = luminance(f0);
    float clearcoatWeight = clearcoat * luminance(materialClearcoatF0Color(material));
    float totalLobeWeight = max(diffuseWeight + specularWeight + clearcoatWeight, 1e-5f);

    clearcoatProbability = clearcoatWeight > 1e-5f
        ? clamp(clearcoatWeight / totalLobeWeight, 0.02f, 0.35f)
        : 0.0f;
    float remainingProbability = max(0.0f, 1.0f - clearcoatProbability);
    if (specularWeight <= 1e-5f) {
        specularProbability = 0.0f;
    } else if (diffuseWeight <= 1e-5f) {
        specularProbability = remainingProbability;
    } else {
        specularProbability = clamp(specularWeight / totalLobeWeight, 0.08f, remainingProbability);
    }
    diffuseProbability = max(0.0f, 1.0f - specularProbability - clearcoatProbability);
}

static float ggxReflectionPDF(
    float3 normal,
    float3 tangent,
    float3 bitangent,
    float3 viewDirection,
    float3 lightDirection,
    float roughness,
    float anisotropy
) {
    float3 halfVector = normalize(viewDirection + lightDirection);
    float nDotH = max(dot(normal, halfVector), 0.0f);
    float nDotV = max(dot(normal, viewDirection), 0.0f);
    float vDotH = max(dot(viewDirection, halfVector), 0.0f);
    if (nDotH <= 0.0f || nDotV <= 0.0f || vDotH <= 0.0f) {
        return 0.0f;
    }
    TangentFrame frame = makeTangentFrame(normal, tangent, bitangent);
    return distributionGGXAnisotropic(halfVector, normal, frame.tangent, frame.bitangent, roughness, anisotropy)
        * geometrySmithG1GGXAnisotropic(viewDirection, normal, frame.tangent, frame.bitangent, roughness, anisotropy)
        / max(4.0f * nDotV, 1e-5f);
}

static float materialBSDFPDF(
    GPUMaterial material,
    float3 normal,
    float3 tangent,
    float3 bitangent,
    float3 viewDirection,
    float3 lightDirection
) {
    constexpr float inversePi = 0.31830988618f;
    float nDotL = max(dot(normal, lightDirection), 0.0f);
    float nDotV = max(dot(normal, viewDirection), 0.0f);
    if (nDotL <= 0.0f || nDotV <= 0.0f) {
        return 0.0f;
    }

    float diffuseProbability;
    float specularProbability;
    float clearcoatProbability;
    materialLobeProbabilities(material, diffuseProbability, specularProbability, clearcoatProbability);

    float roughness = clamp(material.parameters.x, 0.02f, 1.0f);
    float clearcoatRoughness = materialClearcoatRoughness(material);
    float anisotropy = materialSpecularAnisotropy(material);
    float diffusePDF = nDotL * inversePi;
    float specularPDF = ggxReflectionPDF(
        normal,
        tangent,
        bitangent,
        viewDirection,
        lightDirection,
        roughness,
        anisotropy
    );
    float clearcoatPDF = ggxReflectionPDF(
        normal,
        tangent,
        bitangent,
        viewDirection,
        lightDirection,
        clearcoatRoughness,
        0.0f
    );
    return diffuseProbability * diffusePDF
        + specularProbability * specularPDF
        + clearcoatProbability * clearcoatPDF;
}

static float3 materialDiffuseBounceWeight(
    GPUMaterial material,
    float3 normal,
    float3 viewDirection,
    float3 lightDirection
) {
    float metallic = clamp(material.parameters.y, 0.0f, 1.0f);
    float3 baseColor = material.baseColor.xyz;
    float3 halfDirection = viewDirection + lightDirection;
    if (dot(halfDirection, halfDirection) <= 1e-8f) {
        return float3(0.0f);
    }

    float3 halfVector = normalize(halfDirection);
    float vDotH = max(dot(viewDirection, halfVector), 0.0f);
    float3 fresnel = fresnelSchlickThinFilm(vDotH, materialF0(material), material);
    float3 clearcoatAttenuation = materialClearcoatAttenuationForDirection(
        material,
        normal,
        viewDirection,
        lightDirection
    );
    float3 diffuse = (float3(1.0f) - fresnel) * (1.0f - metallic) * baseColor;
    float3 sheen = evaluateMaterialSheenBRDF(material, normal, viewDirection, lightDirection)
        * 3.14159265359f;
    return clearcoatAttenuation * (diffuse + sheen);
}

static bool terminatePathWithRussianRoulette(
    uint bounce,
    thread float3 &throughput,
    thread uint &state
) {
    float continuationWeight = maxComponent(throughput);
    if (continuationWeight <= 0.0f) {
        return true;
    }

    if (bounce < 2u) {
        return false;
    }

    float survivalProbability = clamp(continuationWeight, 0.05f, 0.95f);
    if (randomFloat(state) > survivalProbability) {
        return true;
    }

    throughput /= survivalProbability;
    return false;
}

static float lightSolidAnglePDF(float distanceSquared, float cosLight, float area) {
    return distanceSquared / max(cosLight * area, 1e-6f);
}

static float lightSelectionCDF(constant GPULightRecord *lights, uint index) {
    return clamp(lights[index].selectionCDF, 0.0f, 1.0f);
}

static float lightSelectionPDF(constant GPULightRecord *lights, uint index) {
    float previousCDF = index == 0u ? 0.0f : lightSelectionCDF(lights, index - 1u);
    return max(lightSelectionCDF(lights, index) - previousCDF, 0.0f);
}

static uint selectLightIndex(constant GPULightRecord *lights, uint lightCount, float sample) {
    if (lightCount <= 1u) {
        return 0u;
    }

    float target = clamp(sample, 0.0f, 0.99999994f);
    uint low = 0u;
    uint high = lightCount - 1u;
    while (low < high) {
        uint mid = (low + high) >> 1u;
        if (target <= lightSelectionCDF(lights, mid)) {
            high = mid;
        } else {
            low = mid + 1u;
        }
    }
    return low;
}

static float lightPDFForHit(
    Hit hit,
    float3 incomingDirection,
    constant GPUTriangle *triangles,
    uint triangleCount,
    constant GPULightRecord *lights,
    uint lightCount
) {
    if (hit.primitiveID >= triangleCount) {
        return 0.0f;
    }

    uint lightIndexPlusOne = triangles[hit.primitiveID].padding2;
    if (lightIndexPlusOne == 0u) {
        return 0.0f;
    }

    uint index = lightIndexPlusOne - 1u;
    if (index >= lightCount) {
        return 0.0f;
    }

    constant GPULightRecord &light = lights[index];
    if (light.triangleIndex != hit.primitiveID || light.area <= 0.0f) {
        return 0.0f;
    }

    float cosLight = max(0.0f, dot(light.normal.xyz, -incomingDirection));
    if (cosLight <= 0.0f) {
        return 0.0f;
    }

    return lightSelectionPDF(lights, index) * lightSolidAnglePDF(hit.t * hit.t, cosLight, light.area);
}

static float3 sampleGGXHalfVector(float2 u, float3 normal, float roughness) {
    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;
    float phi = 6.28318530718f * u.x;
    float cosTheta = sqrt((1.0f - u.y) / max(1.0f + (alpha2 - 1.0f) * u.y, 1e-5f));
    float sinTheta = sqrt(max(0.0f, 1.0f - cosTheta * cosTheta));
    float3 localDirection = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
    return orientHemisphere(localDirection, normal);
}

static float3 sampleGGXVisibleNormal(
    float2 u,
    float3 normal,
    float3 tangent,
    float3 bitangent,
    float3 viewDirection,
    float roughness,
    float anisotropy
) {
    TangentFrame frame = makeTangentFrame(normal, tangent, bitangent);
    float2 alpha = anisotropicGGXAlpha(roughness, anisotropy);
    float3 localView = normalize(float3(
        dot(viewDirection, frame.tangent),
        dot(viewDirection, frame.bitangent),
        max(dot(viewDirection, normal), 1e-5f)
    ));
    float3 stretchedView = normalize(float3(alpha.x * localView.x, alpha.y * localView.y, localView.z));
    float lensq = stretchedView.x * stretchedView.x + stretchedView.y * stretchedView.y;
    float3 t1 = lensq > 1e-7f
        ? float3(-stretchedView.y, stretchedView.x, 0.0f) * rsqrt(lensq)
        : float3(1.0f, 0.0f, 0.0f);
    float3 t2 = cross(stretchedView, t1);

    float radius = sqrt(u.x);
    float phi = 6.28318530718f * u.y;
    float p1 = radius * cos(phi);
    float p2 = radius * sin(phi);
    float blend = 0.5f * (1.0f + stretchedView.z);
    p2 = mix(sqrt(max(0.0f, 1.0f - p1 * p1)), p2, blend);

    float3 visibleNormal = p1 * t1
        + p2 * t2
        + sqrt(max(0.0f, 1.0f - p1 * p1 - p2 * p2)) * stretchedView;
    float3 localHalfVector = normalize(float3(
        alpha.x * visibleNormal.x,
        alpha.y * visibleNormal.y,
        max(visibleNormal.z, 0.0f)
    ));
    return normalize(localHalfVector.x * frame.tangent + localHalfVector.y * frame.bitangent + localHalfVector.z * normal);
}

static bool projectToScreen(
    constant GPUCamera &camera,
    float3 worldPosition,
    uint width,
    uint height,
    thread float2 &screenPosition
) {
    float3 forward = normalize(cross(camera.vertical.xyz, camera.horizontal.xyz));
    float3 planeCenter = camera.lowerLeft.xyz + camera.horizontal.xyz * 0.5f + camera.vertical.xyz * 0.5f;
    float3 planePoint;
    if (camera.origin.w > 0.5f) {
        planePoint = worldPosition - forward * dot(worldPosition - planeCenter, forward);
    } else {
        float3 toPoint = worldPosition - camera.origin.xyz;
        float denominator = dot(toPoint, forward);

        if (fabs(denominator) <= 1e-5f) {
            return false;
        }

        float planeDistance = dot(planeCenter - camera.origin.xyz, forward);
        float planeT = planeDistance / denominator;

        if (planeT <= 0.0f) {
            return false;
        }

        planePoint = camera.origin.xyz + toPoint * planeT;
    }
    float3 relative = planePoint - camera.lowerLeft.xyz;
    float u = dot(relative, camera.horizontal.xyz) / max(dot(camera.horizontal.xyz, camera.horizontal.xyz), 1e-5f);
    float v = dot(relative, camera.vertical.xyz) / max(dot(camera.vertical.xyz, camera.vertical.xyz), 1e-5f);

    screenPosition = float2(u * (float)width, (1.0f - v) * (float)height);
    return true;
}

static float triangleArea(constant GPUTriangle &triangle) {
    float3 edge1 = triangle.v1.xyz - triangle.v0.xyz;
    float3 edge2 = triangle.v2.xyz - triangle.v0.xyz;
    return 0.5f * length(cross(edge1, edge2));
}

static float3 triangleNormal(constant GPUTriangle &triangle) {
    float3 edge1 = triangle.v1.xyz - triangle.v0.xyz;
    float3 edge2 = triangle.v2.xyz - triangle.v0.xyz;
    return normalize(cross(edge1, edge2));
}

static float3 sampleTriangle(constant GPUTriangle &triangle, float2 randomSample) {
    float su0 = sqrt(randomSample.x);
    float b0 = 1.0f - su0;
    float b1 = su0 * (1.0f - randomSample.y);
    float b2 = su0 * randomSample.y;
    return b0 * triangle.v0.xyz + b1 * triangle.v1.xyz + b2 * triangle.v2.xyz;
}

static bool continueTransmissiveSurface(
    Hit hit,
    GPUMaterial material,
    thread Ray &ray,
    thread float3 &throughput,
    thread float &previousBSDFPDF,
    thread uint &state
) {
    float transmission = materialTransmission(material);
    if (transmission <= 0.0f || randomFloat(state) > transmission) {
        return false;
    }

    float3 incomingDirection = ray.direction;
    float3 viewDirection = -incomingDirection;
    float roughness = materialTransmissionRoughness(material);
    float ior = materialTransmissionIOR(material);
    float3 microNormal = hit.normal;

    if (roughness > 0.01f) {
        microNormal = sampleGGXHalfVector(float2(randomFloat(state), randomFloat(state)), hit.normal, roughness);
        if (dot(microNormal, incomingDirection) > 0.0f) {
            microNormal = -microNormal;
        }
    }

    float etaI = hit.frontFacing ? 1.0f : ior;
    float etaT = hit.frontFacing ? ior : 1.0f;
    float eta = etaI / etaT;
    float cosThetaI = max(dot(viewDirection, microNormal), 0.0f);
    float fresnel = dielectricFresnel(cosThetaI, etaI, etaT);

    if (materialThinWalled(material)) {
        fresnel = dielectricFresnel(cosThetaI, 1.0f, ior);
        float reflectProbability = clamp(fresnel, 0.02f, 0.98f);
        if (randomFloat(state) < reflectProbability) {
            ray.direction = normalize(reflect(incomingDirection, microNormal));
            ray.origin = hit.position + microNormal * 0.001f;
            throughput *= fresnel / max(reflectProbability, 1e-5f);
        } else {
            ray.direction = incomingDirection;
            ray.origin = hit.position + ray.direction * 0.001f;
            float grazing = 1.0f - abs(dot(viewDirection, hit.normal));
            float tintStrength = mix(0.35f, 0.95f, grazing * grazing);
            float transmissionWeight = (1.0f - fresnel) / max(1.0f - reflectProbability, 1e-5f);
            throughput *= materialTransmissionTint(material, tintStrength) * transmissionWeight;
        }

        previousBSDFPDF = 0.0f;
        return true;
    }

    float3 refractedDirection = refract(incomingDirection, microNormal, eta);
    bool totalInternalReflection = dot(refractedDirection, refractedDirection) <= 1e-7f;
    float reflectProbability = totalInternalReflection ? 1.0f : clamp(fresnel, 0.02f, 0.98f);

    if (randomFloat(state) < reflectProbability) {
        ray.direction = normalize(reflect(incomingDirection, microNormal));
        ray.origin = hit.position + microNormal * 0.001f;
        throughput *= totalInternalReflection ? 1.0f : fresnel / max(reflectProbability, 1e-5f);
    } else {
        ray.direction = normalize(refractedDirection);
        ray.origin = hit.position + ray.direction * 0.001f;
        float grazing = 1.0f - abs(dot(viewDirection, hit.normal));
        float tintStrength = mix(0.35f, 0.95f, grazing * grazing);
        float transmissionWeight = (1.0f - fresnel) / max(1.0f - reflectProbability, 1e-5f);
        float3 absorption = materialTransmissionAbsorption(
            material,
            hit.t,
            !hit.frontFacing && !materialHasVolumeScattering(material)
        );
        throughput *= materialTransmissionTint(material, tintStrength) * absorption * transmissionWeight;
    }

    previousBSDFPDF = 0.0f;
    return true;
}

static bool intersectTriangle(
    Ray ray,
    constant GPUTriangle &triangle,
    thread float &t,
    thread float3 &normal,
    thread float2 &uv,
    thread float3 &tangent,
    thread float3 &bitangent,
    thread bool &frontFacing
) {
    float3 v0 = triangle.v0.xyz;
    float3 v1 = triangle.v1.xyz;
    float3 v2 = triangle.v2.xyz;
    float3 edge1 = v1 - v0;
    float3 edge2 = v2 - v0;
    float3 p = cross(ray.direction, edge2);
    float determinant = dot(edge1, p);

    if (fabs(determinant) < 1e-7f) {
        return false;
    }

    float invDeterminant = 1.0f / determinant;
    float3 s = ray.origin - v0;
    float u = invDeterminant * dot(s, p);
    if (u < 0.0f || u > 1.0f) {
        return false;
    }

    float3 q = cross(s, edge1);
    float v = invDeterminant * dot(ray.direction, q);
    if (v < 0.0f || u + v > 1.0f) {
        return false;
    }

    float candidateT = invDeterminant * dot(edge2, q);
    if (candidateT <= 0.0005f) {
        return false;
    }

    t = candidateT;
    float w = 1.0f - u - v;
    normal = normalize(w * triangle.n0.xyz + u * triangle.n1.xyz + v * triangle.n2.xyz);
    frontFacing = dot(normal, ray.direction) <= 0.0f;
    if (dot(normal, ray.direction) > 0.0f) {
        normal = -normal;
    }
    uv = w * triangle.uv0.xy + u * triangle.uv1.xy + v * triangle.uv2.xy;
    tangent = normalize(triangle.tangent.xyz);
    bitangent = normalize(triangle.bitangent.xyz);
    return true;
}

static bool intersectBounds(Ray ray, constant GPUAccelerationNode &node, float closestT) {
    float3 invDirection = 1.0f / ray.direction;
    float3 t0 = (node.boundsMin.xyz - ray.origin) * invDirection;
    float3 t1 = (node.boundsMax.xyz - ray.origin) * invDirection;
    float3 tNear3 = min(t0, t1);
    float3 tFar3 = max(t0, t1);
    float tNear = max(max(tNear3.x, tNear3.y), max(tNear3.z, 0.0f));
    float tFar = min(min(tFar3.x, tFar3.y), min(tFar3.z, closestT));
    return tNear <= tFar;
}

static bool intersectAABB(
    Ray ray,
    float3 boundsMin,
    float3 boundsMax,
    float closestT,
    thread float &tNear,
    thread float &tFar
) {
    float3 invDirection = 1.0f / ray.direction;
    float3 t0 = (boundsMin - ray.origin) * invDirection;
    float3 t1 = (boundsMax - ray.origin) * invDirection;
    float3 tNear3 = min(t0, t1);
    float3 tFar3 = max(t0, t1);
    tNear = max(max(tNear3.x, tNear3.y), max(tNear3.z, 0.0005f));
    tFar = min(min(tFar3.x, tFar3.y), min(tFar3.z, closestT));
    return tNear <= tFar;
}

static Hit emptyHit() {
    Hit closest;
    closest.hit = false;
    closest.t = INFINITY;
    closest.position = float3(0);
    closest.localPosition = float3(0);
    closest.normal = float3(0, 1, 0);
    closest.uv = float2(0);
    closest.tangent = float3(1, 0, 0);
    closest.bitangent = float3(0, 0, 1);
    closest.materialID = 0;
    closest.materialID2 = 0;
    closest.materialBlend = 0.0f;
    closest.volumeBaseColorOpacity = float4(0);
    closest.volumeEmissionTransmission = float4(0);
    closest.volumeSurface = float4(0);
    closest.volumeMaterialFieldFlags = 0u;
    closest.materialProgramIndex = 0xffffffffu;
    closest.volumeAttributes0 = float4(0);
    closest.volumeAttributes1 = float4(0);
    closest.volumeAttributeSemantics0 = uint4(0);
    closest.volumeAttributeSemantics1 = uint4(0);
    closest.objectID = 0;
    closest.primitiveID = 0;
    closest.frontFacing = true;
    return closest;
}

static float4x4 matrixFromColumns(float4 c0, float4 c1, float4 c2, float4 c3) {
    return float4x4(c0, c1, c2, c3);
}

static float sampleVolumeDistance(
    constant GPUVolumeDescriptor &volume,
    constant GPUVolumeSample *volumeSamples,
    uint volumeSampleCount,
    float3 localPosition
) {
    uint3 dimensions = uint3(volume.dimensions.xyz);
    uint sampleOffset = volume.metadata.x;
    uint sampleCount = dimensions.x * dimensions.y * dimensions.z;
    if (sampleOffset >= volumeSampleCount || sampleOffset + sampleCount > volumeSampleCount) {
        return INFINITY;
    }

    float3 localMin = volume.localBoundsMin.xyz;
    float3 localMax = volume.localBoundsMax.xyz;
    float3 extent = max(localMax - localMin, float3(1e-6f));
    float3 uvw = clamp((localPosition - localMin) / extent, float3(0.0f), float3(1.0f));
    float3 grid = uvw * float3(dimensions - uint3(1));
    uint3 base = uint3(floor(grid));
    uint3 next = min(base + uint3(1), dimensions - uint3(1));
    float3 fraction = grid - float3(base);

    uint strideY = dimensions.x;
    uint strideZ = dimensions.x * dimensions.y;
    uint i000 = sampleOffset + base.x + base.y * strideY + base.z * strideZ;
    uint i100 = sampleOffset + next.x + base.y * strideY + base.z * strideZ;
    uint i010 = sampleOffset + base.x + next.y * strideY + base.z * strideZ;
    uint i110 = sampleOffset + next.x + next.y * strideY + base.z * strideZ;
    uint i001 = sampleOffset + base.x + base.y * strideY + next.z * strideZ;
    uint i101 = sampleOffset + next.x + base.y * strideY + next.z * strideZ;
    uint i011 = sampleOffset + base.x + next.y * strideY + next.z * strideZ;
    uint i111 = sampleOffset + next.x + next.y * strideY + next.z * strideZ;

    float c00 = mix(volumeSamples[i000].distance, volumeSamples[i100].distance, fraction.x);
    float c10 = mix(volumeSamples[i010].distance, volumeSamples[i110].distance, fraction.x);
    float c01 = mix(volumeSamples[i001].distance, volumeSamples[i101].distance, fraction.x);
    float c11 = mix(volumeSamples[i011].distance, volumeSamples[i111].distance, fraction.x);
    float c0 = mix(c00, c10, fraction.y);
    float c1 = mix(c01, c11, fraction.y);
    return mix(c0, c1, fraction.z);
}

static GPUVolumeSample sampleVolumeMaterial(
    constant GPUVolumeDescriptor &volume,
    constant GPUVolumeSample *volumeSamples,
    uint volumeSampleCount,
    float3 localPosition
) {
    uint3 dimensions = uint3(volume.dimensions.xyz);
    uint sampleOffset = volume.metadata.x;
    uint sampleCount = dimensions.x * dimensions.y * dimensions.z;
    if (sampleOffset >= volumeSampleCount || sampleOffset + sampleCount > volumeSampleCount) {
        GPUVolumeSample fallback;
        fallback.distance = INFINITY;
        fallback.materialA = volume.dimensions.w;
        fallback.materialB = volume.dimensions.w;
        fallback.materialBlend = 0.0f;
        fallback.baseColorOpacity = float4(0);
        fallback.emissionTransmission = float4(0);
        fallback.surface = float4(0);
        fallback.materialFieldFlags = uint4(0);
        return fallback;
    }

    float3 extent = max(volume.localBoundsMax.xyz - volume.localBoundsMin.xyz, float3(1e-6f));
    float3 uvw = clamp((localPosition - volume.localBoundsMin.xyz) / extent, float3(0.0f), float3(1.0f));
    uint3 nearest = min(uint3(round(uvw * float3(dimensions - uint3(1)))), dimensions - uint3(1));
    uint index = sampleOffset + nearest.x + nearest.y * dimensions.x + nearest.z * dimensions.x * dimensions.y;
    return volumeSamples[index];
}

static void sampleVolumeAttributes(
    uint volumeIndex,
    constant GPUVolumeDescriptor &volume,
    constant GPUVolumeAttributeDescriptor *attributeDescriptors,
    constant float4 *attributeSamples,
    uint attributeSampleCount,
    float3 localPosition,
    thread float4 &attributes0,
    thread float4 &attributes1,
    thread uint4 &reserved0,
    thread uint4 &reserved1
) {
    attributes0 = float4(0);
    attributes1 = float4(0);
    reserved0 = uint4(0);
    reserved1 = uint4(0);
    constant GPUVolumeAttributeDescriptor &descriptor = attributeDescriptors[volumeIndex];
    uint packedVectorCount = descriptor.metadata.y;
    if (packedVectorCount == 0u) {
        return;
    }

    uint3 dimensions = uint3(volume.dimensions.xyz);
    uint sampleCount = dimensions.x * dimensions.y * dimensions.z;
    uint sampleOffset = descriptor.metadata.x;
    if (sampleOffset >= attributeSampleCount || sampleOffset + sampleCount * packedVectorCount > attributeSampleCount) {
        return;
    }

    float3 extent = max(volume.localBoundsMax.xyz - volume.localBoundsMin.xyz, float3(1e-6f));
    float3 uvw = clamp((localPosition - volume.localBoundsMin.xyz) / extent, float3(0.0f), float3(1.0f));
    uint3 nearest = min(uint3(round(uvw * float3(dimensions - uint3(1)))), dimensions - uint3(1));
    uint sampleIndex = nearest.x + nearest.y * dimensions.x + nearest.z * dimensions.x * dimensions.y;
    uint attributeIndex = sampleOffset + sampleIndex * packedVectorCount;

    attributes0 = attributeSamples[attributeIndex];
    if (packedVectorCount > 1u) {
        attributes1 = attributeSamples[attributeIndex + 1u];
    }
    reserved0 = descriptor.reserved0;
    reserved1 = descriptor.reserved1;
}

static float3 volumeNormal(
    constant GPUVolumeDescriptor &volume,
    constant GPUVolumeSample *volumeSamples,
    uint volumeSampleCount,
    float3 localPosition
) {
    float3 extent = max(volume.localBoundsMax.xyz - volume.localBoundsMin.xyz, float3(1e-6f));
    float3 spacing = extent / max(float3(volume.dimensions.xyz) - float3(1.0f), float3(1.0f));
    float dx = sampleVolumeDistance(volume, volumeSamples, volumeSampleCount, localPosition + float3(spacing.x, 0, 0))
        - sampleVolumeDistance(volume, volumeSamples, volumeSampleCount, localPosition - float3(spacing.x, 0, 0));
    float dy = sampleVolumeDistance(volume, volumeSamples, volumeSampleCount, localPosition + float3(0, spacing.y, 0))
        - sampleVolumeDistance(volume, volumeSamples, volumeSampleCount, localPosition - float3(0, spacing.y, 0));
    float dz = sampleVolumeDistance(volume, volumeSamples, volumeSampleCount, localPosition + float3(0, 0, spacing.z))
        - sampleVolumeDistance(volume, volumeSamples, volumeSampleCount, localPosition - float3(0, 0, spacing.z));
    float3 localNormal = float3(dx, dy, dz);
    if (dot(localNormal, localNormal) <= 1e-10f) {
        localNormal = float3(0, 1, 0);
    }

    float4x4 normalTransform = matrixFromColumns(
        volume.normalTransform0,
        volume.normalTransform1,
        volume.normalTransform2,
        volume.normalTransform3
    );
    return normalize((normalTransform * float4(normalize(localNormal), 0.0f)).xyz);
}

struct VolumeBrickSampleContext {
    uint3 dimensions;
    uint sampleOffset;
    uint strideY;
    uint strideZ;
    uint sampleCount;
    float3 sampleMin;
    float3 sampleMax;
    float3 sampleExtent;
    uint valid;
};

struct VolumeBrickDistanceGradient {
    float distance;
    float3 gradient;
};

static VolumeBrickSampleContext makeVolumeBrickSampleContext(
    constant GPUVolumeBrickDescriptor &brick,
    uint brickSampleCount
) {
    VolumeBrickSampleContext context;
    uint3 dimensions = uint3(brick.dimensionsAndSampleOffset.xyz);
    uint sampleOffset = brick.dimensionsAndSampleOffset.w;
    uint sampleCount = dimensions.x * dimensions.y * dimensions.z;
    context.dimensions = dimensions;
    context.sampleOffset = sampleOffset;
    context.strideY = dimensions.x;
    context.strideZ = dimensions.x * dimensions.y;
    context.sampleCount = sampleCount;
    context.sampleMin = brick.sampleBoundsMin.xyz;
    context.sampleMax = brick.sampleBoundsMax.xyz;
    context.sampleExtent = max(context.sampleMax - context.sampleMin, float3(1e-6f));
    bool sampleRangeValid = sampleOffset < brickSampleCount && sampleCount <= brickSampleCount - sampleOffset;
    context.valid = (dimensions.x >= 2u && dimensions.y >= 2u && dimensions.z >= 2u
        && sampleRangeValid) ? 1u : 0u;
    return context;
}

static float sampleVolumeBrickDistancePrepared(
    constant GPUVolumeBrickSample *brickSamples,
    VolumeBrickSampleContext context,
    float3 localPosition
) {
    if (context.valid == 0u) {
        return INFINITY;
    }

    float3 uvw = clamp((localPosition - context.sampleMin) / context.sampleExtent, float3(0.0f), float3(1.0f));
    float3 grid = uvw * float3(context.dimensions - uint3(1));
    uint3 base = uint3(floor(grid));
    uint3 next = min(base + uint3(1), context.dimensions - uint3(1));
    float3 fraction = grid - float3(base);

    uint i000 = context.sampleOffset + base.x + base.y * context.strideY + base.z * context.strideZ;
    uint i100 = context.sampleOffset + next.x + base.y * context.strideY + base.z * context.strideZ;
    uint i010 = context.sampleOffset + base.x + next.y * context.strideY + base.z * context.strideZ;
    uint i110 = context.sampleOffset + next.x + next.y * context.strideY + base.z * context.strideZ;
    uint i001 = context.sampleOffset + base.x + base.y * context.strideY + next.z * context.strideZ;
    uint i101 = context.sampleOffset + next.x + base.y * context.strideY + next.z * context.strideZ;
    uint i011 = context.sampleOffset + base.x + next.y * context.strideY + next.z * context.strideZ;
    uint i111 = context.sampleOffset + next.x + next.y * context.strideY + next.z * context.strideZ;

    float c00 = mix(brickSamples[i000].distance, brickSamples[i100].distance, fraction.x);
    float c10 = mix(brickSamples[i010].distance, brickSamples[i110].distance, fraction.x);
    float c01 = mix(brickSamples[i001].distance, brickSamples[i101].distance, fraction.x);
    float c11 = mix(brickSamples[i011].distance, brickSamples[i111].distance, fraction.x);
    float c0 = mix(c00, c10, fraction.y);
    float c1 = mix(c01, c11, fraction.y);
    return mix(c0, c1, fraction.z);
}

static float sampleVolumeBrickDistanceAtGrid(
    constant GPUVolumeBrickSample *brickSamples,
    VolumeBrickSampleContext context,
    uint3 coordinate
) {
    uint index = context.sampleOffset
        + coordinate.x
        + coordinate.y * context.strideY
        + coordinate.z * context.strideZ;
    return brickSamples[index].distance;
}

static float cubicCatmullRom(float p0, float p1, float p2, float p3, float t) {
    float t2 = t * t;
    float t3 = t2 * t;
    return 0.5f * (
        2.0f * p1
        + (-p0 + p2) * t
        + (2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3) * t2
        + (-p0 + 3.0f * p1 - 3.0f * p2 + p3) * t3
    );
}

static float cubicCatmullRomDerivative(float p0, float p1, float p2, float p3, float t) {
    float t2 = t * t;
    return 0.5f * (
        (-p0 + p2)
        + 2.0f * (2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3) * t
        + 3.0f * (-p0 + 3.0f * p1 - 3.0f * p2 + p3) * t2
    );
}

static VolumeBrickDistanceGradient sampleVolumeBrickDistanceGradientPrepared(
    constant GPUVolumeBrickSample *brickSamples,
    VolumeBrickSampleContext context,
    float3 localPosition
) {
    VolumeBrickDistanceGradient result;
    result.distance = INFINITY;
    result.gradient = float3(0.0f);
    if (context.valid == 0u) {
        return result;
    }

    float3 uvw = clamp((localPosition - context.sampleMin) / context.sampleExtent, float3(0.0f), float3(1.0f));
    float3 grid = uvw * float3(context.dimensions - uint3(1));
    uint3 base = uint3(floor(grid));
    uint3 next = min(base + uint3(1), context.dimensions - uint3(1));
    float3 fraction = grid - float3(base);

    uint i000 = context.sampleOffset + base.x + base.y * context.strideY + base.z * context.strideZ;
    uint i100 = context.sampleOffset + next.x + base.y * context.strideY + base.z * context.strideZ;
    uint i010 = context.sampleOffset + base.x + next.y * context.strideY + base.z * context.strideZ;
    uint i110 = context.sampleOffset + next.x + next.y * context.strideY + base.z * context.strideZ;
    uint i001 = context.sampleOffset + base.x + base.y * context.strideY + next.z * context.strideZ;
    uint i101 = context.sampleOffset + next.x + base.y * context.strideY + next.z * context.strideZ;
    uint i011 = context.sampleOffset + base.x + next.y * context.strideY + next.z * context.strideZ;
    uint i111 = context.sampleOffset + next.x + next.y * context.strideY + next.z * context.strideZ;

    float d000 = brickSamples[i000].distance;
    float d100 = brickSamples[i100].distance;
    float d010 = brickSamples[i010].distance;
    float d110 = brickSamples[i110].distance;
    float d001 = brickSamples[i001].distance;
    float d101 = brickSamples[i101].distance;
    float d011 = brickSamples[i011].distance;
    float d111 = brickSamples[i111].distance;

    float c00 = mix(d000, d100, fraction.x);
    float c10 = mix(d010, d110, fraction.x);
    float c01 = mix(d001, d101, fraction.x);
    float c11 = mix(d011, d111, fraction.x);
    float c0 = mix(c00, c10, fraction.y);
    float c1 = mix(c01, c11, fraction.y);
    result.distance = mix(c0, c1, fraction.z);

    float dxGrid = mix(
        mix(d100 - d000, d110 - d010, fraction.y),
        mix(d101 - d001, d111 - d011, fraction.y),
        fraction.z
    );
    float dyGrid = mix(
        mix(d010 - d000, d110 - d100, fraction.x),
        mix(d011 - d001, d111 - d101, fraction.x),
        fraction.z
    );
    float dzGrid = c1 - c0;
    float3 gridToLocal = float3(context.dimensions - uint3(1)) / context.sampleExtent;
    result.gradient = float3(dxGrid, dyGrid, dzGrid) * gridToLocal;
    return result;
}

static float3 sampleVolumeBrickCentralGradientPrepared(
    constant GPUVolumeBrickSample *brickSamples,
    VolumeBrickSampleContext context,
    float3 localPosition,
    float3 spacing
) {
    float3 minPosition = context.sampleMin;
    float3 maxPosition = context.sampleMax;

    float3 x0 = localPosition;
    float3 x1 = localPosition;
    x0.x = max(localPosition.x - spacing.x, minPosition.x);
    x1.x = min(localPosition.x + spacing.x, maxPosition.x);
    float xWidth = max(x1.x - x0.x, 1e-6f);
    float dx = (sampleVolumeBrickDistancePrepared(brickSamples, context, x1)
        - sampleVolumeBrickDistancePrepared(brickSamples, context, x0)) / xWidth;

    float3 y0 = localPosition;
    float3 y1 = localPosition;
    y0.y = max(localPosition.y - spacing.y, minPosition.y);
    y1.y = min(localPosition.y + spacing.y, maxPosition.y);
    float yWidth = max(y1.y - y0.y, 1e-6f);
    float dy = (sampleVolumeBrickDistancePrepared(brickSamples, context, y1)
        - sampleVolumeBrickDistancePrepared(brickSamples, context, y0)) / yWidth;

    float3 z0 = localPosition;
    float3 z1 = localPosition;
    z0.z = max(localPosition.z - spacing.z, minPosition.z);
    z1.z = min(localPosition.z + spacing.z, maxPosition.z);
    float zWidth = max(z1.z - z0.z, 1e-6f);
    float dz = (sampleVolumeBrickDistancePrepared(brickSamples, context, z1)
        - sampleVolumeBrickDistancePrepared(brickSamples, context, z0)) / zWidth;

    return float3(dx, dy, dz);
}

static VolumeBrickDistanceGradient sampleVolumeBrickDistanceGradientCubicPrepared(
    constant GPUVolumeBrickSample *brickSamples,
    VolumeBrickSampleContext context,
    float3 localPosition
) {
    if (context.valid == 0u) {
        VolumeBrickDistanceGradient invalid;
        invalid.distance = INFINITY;
        invalid.gradient = float3(0.0f);
        return invalid;
    }

    float3 uvw = clamp((localPosition - context.sampleMin) / context.sampleExtent, float3(0.0f), float3(1.0f));
    float3 grid = uvw * float3(context.dimensions - uint3(1));
    uint3 base = uint3(floor(grid));
    if (base.x < 1u || base.y < 1u || base.z < 1u
        || base.x + 2u >= context.dimensions.x
        || base.y + 2u >= context.dimensions.y
        || base.z + 2u >= context.dimensions.z) {
        return sampleVolumeBrickDistanceGradientPrepared(brickSamples, context, localPosition);
    }

    float3 fraction = grid - float3(base);
    float xRows[4][4];
    float dxRows[4][4];
    for (uint z = 0u; z < 4u; ++z) {
        for (uint y = 0u; y < 4u; ++y) {
            uint3 coordinate = uint3(base.x - 1u, base.y + y - 1u, base.z + z - 1u);
            float p0 = sampleVolumeBrickDistanceAtGrid(brickSamples, context, coordinate);
            coordinate.x = base.x;
            float p1 = sampleVolumeBrickDistanceAtGrid(brickSamples, context, coordinate);
            coordinate.x = base.x + 1u;
            float p2 = sampleVolumeBrickDistanceAtGrid(brickSamples, context, coordinate);
            coordinate.x = base.x + 2u;
            float p3 = sampleVolumeBrickDistanceAtGrid(brickSamples, context, coordinate);
            xRows[y][z] = cubicCatmullRom(p0, p1, p2, p3, fraction.x);
            dxRows[y][z] = cubicCatmullRomDerivative(p0, p1, p2, p3, fraction.x);
        }
    }

    float yRows[4];
    float dyRows[4];
    float dxYRows[4];
    for (uint z = 0u; z < 4u; ++z) {
        yRows[z] = cubicCatmullRom(xRows[0][z], xRows[1][z], xRows[2][z], xRows[3][z], fraction.y);
        dyRows[z] = cubicCatmullRomDerivative(xRows[0][z], xRows[1][z], xRows[2][z], xRows[3][z], fraction.y);
        dxYRows[z] = cubicCatmullRom(dxRows[0][z], dxRows[1][z], dxRows[2][z], dxRows[3][z], fraction.y);
    }

    VolumeBrickDistanceGradient result;
    result.distance = cubicCatmullRom(yRows[0], yRows[1], yRows[2], yRows[3], fraction.z);
    float dxGrid = cubicCatmullRom(dxYRows[0], dxYRows[1], dxYRows[2], dxYRows[3], fraction.z);
    float dyGrid = cubicCatmullRom(dyRows[0], dyRows[1], dyRows[2], dyRows[3], fraction.z);
    float dzGrid = cubicCatmullRomDerivative(yRows[0], yRows[1], yRows[2], yRows[3], fraction.z);
    float3 gridToLocal = float3(context.dimensions - uint3(1)) / context.sampleExtent;
    result.gradient = float3(dxGrid, dyGrid, dzGrid) * gridToLocal;
    return result;
}

static float sampleVolumeBrickDistance(
    constant GPUVolumeDescriptor &volume,
    constant GPUVolumeBrickDescriptor &brick,
    constant GPUVolumeBrickSample *brickSamples,
    uint brickSampleCount,
    float3 localPosition
) {
    (void)volume;
    VolumeBrickSampleContext context = makeVolumeBrickSampleContext(brick, brickSampleCount);
    return sampleVolumeBrickDistancePrepared(brickSamples, context, localPosition);
}

static GPUVolumeSample sampleVolumeBrickMaterial(
    constant GPUVolumeDescriptor &volume,
    constant GPUVolumeBrickDescriptor &brick,
    constant GPUVolumeBrickSample *brickSamples,
    constant GPUVolumeMaterialFieldSample *materialFieldSamples,
    uint brickSampleCount,
    uint materialFieldSampleCount,
    float3 localPosition
) {
    VolumeBrickSampleContext context = makeVolumeBrickSampleContext(brick, brickSampleCount);
    if (context.valid == 0u) {
        GPUVolumeSample fallback;
        fallback.distance = INFINITY;
        fallback.materialA = volume.dimensions.w;
        fallback.materialB = volume.dimensions.w;
        fallback.materialBlend = 0.0f;
        fallback.baseColorOpacity = float4(0);
        fallback.emissionTransmission = float4(0);
        fallback.surface = float4(0);
        fallback.materialFieldFlags = uint4(0);
        return fallback;
    }

    float3 uvw = clamp((localPosition - context.sampleMin) / context.sampleExtent, float3(0.0f), float3(1.0f));
    uint3 nearest = min(uint3(round(uvw * float3(context.dimensions - uint3(1)))), context.dimensions - uint3(1));
    uint index = context.sampleOffset + nearest.x + nearest.y * context.strideY + nearest.z * context.strideZ;
    constant GPUVolumeBrickSample &compact = brickSamples[index];
    GPUVolumeSample sample;
    sample.distance = compact.distance;
    sample.materialA = compact.materialA;
    sample.materialB = compact.materialB;
    sample.materialBlend = compact.materialBlend;
    sample.baseColorOpacity = float4(0);
    sample.emissionTransmission = float4(0);
    sample.surface = float4(0);
    sample.materialFieldFlags = uint4(0);
    if (materialFieldSamples != nullptr && materialFieldSampleCount == brickSampleCount && index < materialFieldSampleCount) {
        constant GPUVolumeMaterialFieldSample &fields = materialFieldSamples[index];
        sample.baseColorOpacity = fields.baseColorOpacity;
        sample.emissionTransmission = fields.emissionTransmission;
        sample.surface = fields.surface;
        sample.materialFieldFlags = fields.materialFieldFlags;
    }
    return sample;
}

static void sampleVolumeBrickAttributes(
    uint brickIndex,
    constant GPUVolumeDescriptor &volume,
    constant GPUVolumeBrickDescriptor &brick,
    constant GPUVolumeAttributeDescriptor *attributeDescriptors,
    constant float4 *attributeSamples,
    uint attributeSampleCount,
    float3 localPosition,
    thread float4 &attributes0,
    thread float4 &attributes1,
    thread uint4 &reserved0,
    thread uint4 &reserved1
) {
    attributes0 = float4(0);
    attributes1 = float4(0);
    reserved0 = uint4(0);
    reserved1 = uint4(0);
    constant GPUVolumeAttributeDescriptor &descriptor = attributeDescriptors[brickIndex];
    uint packedVectorCount = descriptor.metadata.y;
    if (packedVectorCount == 0u) {
        return;
    }

    uint3 dimensions = uint3(brick.dimensionsAndSampleOffset.xyz);
    uint sampleCount = dimensions.x * dimensions.y * dimensions.z;
    uint sampleOffset = descriptor.metadata.x;
    if (sampleOffset >= attributeSampleCount || sampleOffset + sampleCount * packedVectorCount > attributeSampleCount) {
        return;
    }

    float3 sampleMin = brick.sampleBoundsMin.xyz;
    float3 sampleMax = brick.sampleBoundsMax.xyz;
    float3 extent = max(sampleMax - sampleMin, float3(1e-6f));
    float3 uvw = clamp((localPosition - sampleMin) / extent, float3(0.0f), float3(1.0f));
    uint3 nearest = min(uint3(round(uvw * float3(dimensions - uint3(1)))), dimensions - uint3(1));
    uint sampleIndex = nearest.x + nearest.y * dimensions.x + nearest.z * dimensions.x * dimensions.y;
    uint attributeIndex = sampleOffset + sampleIndex * packedVectorCount;

    attributes0 = attributeSamples[attributeIndex];
    if (packedVectorCount > 1u) {
        attributes1 = attributeSamples[attributeIndex + 1u];
    }
    reserved0 = descriptor.reserved0;
    reserved1 = descriptor.reserved1;
}

static float3 volumeBrickNormal(
    constant GPUVolumeDescriptor &volume,
    constant GPUVolumeBrickSample *brickSamples,
    uint brickSampleCount,
    VolumeBrickSampleContext context,
    float3 localPosition,
    bool useCubicGradient,
    bool useCoarseFilteredGradient
) {
    (void)brickSampleCount;
    if (context.valid == 0u) {
        return float3(0, 1, 0);
    }

    float3 localNormal = useCubicGradient
        ? sampleVolumeBrickDistanceGradientCubicPrepared(
            brickSamples,
            context,
            localPosition
        ).gradient
        : sampleVolumeBrickDistanceGradientPrepared(
            brickSamples,
            context,
            localPosition
        ).gradient;
    if (useCoarseFilteredGradient) {
        float3 volumeExtent = max(volume.localBoundsMax.xyz - volume.localBoundsMin.xyz, float3(1e-6f));
        float3 spacing = volumeExtent / max(float3(volume.dimensions.xyz) - float3(1.0f), float3(1.0f));
        float3 centralNormal = sampleVolumeBrickCentralGradientPrepared(
            brickSamples,
            context,
            localPosition,
            spacing * 1.5f
        );
        if (dot(centralNormal, centralNormal) > 1e-10f) {
            localNormal = normalize(mix(normalize(localNormal), normalize(centralNormal), 0.35f));
        }
    }
    if (dot(localNormal, localNormal) <= 1e-10f) {
        localNormal = float3(0, 1, 0);
    }

    float4x4 normalTransform = matrixFromColumns(
        volume.normalTransform0,
        volume.normalTransform1,
        volume.normalTransform2,
        volume.normalTransform3
    );
    return normalize((normalTransform * float4(normalize(localNormal), 0.0f)).xyz);
}

static bool intersectVolume(
    uint volumeIndex,
    Ray ray,
    constant GPURenderConstants &constants,
    constant GPUVolumeDescriptor &volume,
    constant GPUVolumeSample *volumeSamples,
    constant GPUVolumeAttributeDescriptor *volumeAttributeDescriptors,
    constant float4 *volumeAttributeSamples,
    uint volumeSampleCount,
    uint volumeAttributeSampleCount,
    float closestT,
    device atomic_uint *sdfCounters,
    thread Hit &hit
) {
    float tNear;
    float tFar;
    if (!intersectAABB(ray, volume.worldBoundsMin.xyz, volume.worldBoundsMax.xyz, closestT, tNear, tFar)) {
        return false;
    }

    float4x4 worldToLocal = matrixFromColumns(
        volume.worldToLocal0,
        volume.worldToLocal1,
        volume.worldToLocal2,
        volume.worldToLocal3
    );
    float3 localRayStep = (worldToLocal * float4(ray.direction, 0.0f)).xyz;
    float localUnitsPerWorldUnit = max(length(localRayStep), 1e-6f);
    float3 extent = max(volume.localBoundsMax.xyz - volume.localBoundsMin.xyz, float3(1e-6f));
    float cellSize = min(extent.x / max((float)volume.dimensions.x - 1.0f, 1.0f),
        min(extent.y / max((float)volume.dimensions.y - 1.0f, 1.0f),
            extent.z / max((float)volume.dimensions.z - 1.0f, 1.0f)));
    float minimumStep = max(cellSize * 0.10f / localUnitsPerWorldUnit, 0.0005f);

    float previousT = tNear;
    float3 previousWorldPosition = ray.origin + ray.direction * previousT;
    float3 previousLocalPosition = (worldToLocal * float4(previousWorldPosition, 1.0f)).xyz;
    float previousDistance = sampleVolumeDistance(
        volume,
        volumeSamples,
        volumeSampleCount,
        previousLocalPosition
    );
    if (!isfinite(previousDistance)) {
        return false;
    }

    float t = previousT + max(fabs(previousDistance) / localUnitsPerWorldUnit * 0.9f, minimumStep);
    for (uint step = 0u; step < 512u && t <= tFar && t < closestT; ++step) {
        addSDFTraversalCounter(sdfCounters, constants, sdfCounterDenseMarchSteps);
        float3 worldPosition = ray.origin + ray.direction * t;
        float3 localPosition = (worldToLocal * float4(worldPosition, 1.0f)).xyz;
        float distance = sampleVolumeDistance(volume, volumeSamples, volumeSampleCount, localPosition);
        if (!isfinite(distance)) {
            return false;
        }

        bool crossedSurface = (previousDistance > 0.0f && distance <= 0.0f)
            || (previousDistance < 0.0f && distance >= 0.0f);
        if (crossedSurface) {
            float lowT = previousT;
            float highT = t;
            float lowDistance = previousDistance;
            float3 refinedLocalPosition = localPosition;
            float refinedT = t;
            for (uint refine = 0u; refine < 10u; ++refine) {
                float midT = 0.5f * (lowT + highT);
                float3 midWorldPosition = ray.origin + ray.direction * midT;
                float3 midLocalPosition = (worldToLocal * float4(midWorldPosition, 1.0f)).xyz;
                float midDistance = sampleVolumeDistance(volume, volumeSamples, volumeSampleCount, midLocalPosition);
                if ((lowDistance > 0.0f && midDistance > 0.0f)
                    || (lowDistance < 0.0f && midDistance < 0.0f)) {
                    lowT = midT;
                    lowDistance = midDistance;
                } else {
                    highT = midT;
                    refinedLocalPosition = midLocalPosition;
                }
                refinedT = 0.5f * (lowT + highT);
            }

            float3 refinedWorldPosition = ray.origin + ray.direction * refinedT;
            refinedLocalPosition = (worldToLocal * float4(refinedWorldPosition, 1.0f)).xyz;
            float3 normal = volumeNormal(volume, volumeSamples, volumeSampleCount, refinedLocalPosition);
            bool frontFacing = dot(normal, ray.direction) <= 0.0f;
            if (!frontFacing) {
                normal = -normal;
            }

            hit.hit = true;
            hit.t = refinedT;
            hit.position = refinedWorldPosition;
            hit.localPosition = refinedLocalPosition;
            hit.normal = normal;
            hit.uv = float2(0.0f);
            hit.tangent = normalize(cross(fabs(normal.y) < 0.999f ? float3(0, 1, 0) : float3(1, 0, 0), normal));
            hit.bitangent = normalize(cross(normal, hit.tangent));
            GPUVolumeSample materialSample = sampleVolumeMaterial(
                volume,
                volumeSamples,
                volumeSampleCount,
                refinedLocalPosition
            );
            hit.materialID = materialSample.materialA;
            hit.materialID2 = materialSample.materialB;
            hit.materialBlend = clamp(materialSample.materialBlend, 0.0f, 1.0f);
            hit.volumeBaseColorOpacity = materialSample.baseColorOpacity;
            hit.volumeEmissionTransmission = materialSample.emissionTransmission;
            hit.volumeSurface = materialSample.surface;
            hit.volumeMaterialFieldFlags = materialSample.materialFieldFlags.x;
            hit.materialProgramIndex = volume.materialProgram.x;
            sampleVolumeAttributes(
                volumeIndex,
                volume,
                volumeAttributeDescriptors,
                volumeAttributeSamples,
                volumeAttributeSampleCount,
                refinedLocalPosition,
                hit.volumeAttributes0,
                hit.volumeAttributes1,
                hit.volumeAttributeSemantics0,
                hit.volumeAttributeSemantics1
            );
            hit.objectID = volume.metadata.y;
            hit.primitiveID = volume.metadata.z;
            hit.frontFacing = frontFacing;
            return true;
        }

        previousT = t;
        previousDistance = distance;
        t += max(fabs(distance) / localUnitsPerWorldUnit * 0.8f, minimumStep);
    }

    return false;
}

static bool intersectVolumeBrickPrepared(
    uint brickIndex,
    Ray ray,
    constant GPURenderConstants &constants,
    constant GPUVolumeDescriptor &volume,
    constant GPUVolumeBrickDescriptor &brick,
    constant GPUVolumeBrickSample *brickSamples,
    constant GPUVolumeMaterialFieldSample *brickMaterialFieldSamples,
    constant GPUVolumeAttributeDescriptor *brickAttributeDescriptors,
    constant float4 *brickAttributeSamples,
    uint brickSampleCount,
    uint brickMaterialFieldSampleCount,
    uint brickAttributeSampleCount,
    float closestT,
    float3 localOrigin,
    float3 localDirection,
    float localUnitsPerWorldUnit,
    float cellSize,
    device atomic_uint *sdfCounters,
    thread Hit &hit
) {
    float tNear;
    float tFar;
    Ray localRay;
    localRay.origin = localOrigin;
    localRay.direction = localDirection;
    if (!intersectAABB(localRay, brick.localBoundsMin.xyz, brick.localBoundsMax.xyz, closestT, tNear, tFar)) {
        return false;
    }

    VolumeBrickSampleContext sampleContext = makeVolumeBrickSampleContext(brick, brickSampleCount);
    if (sampleContext.valid == 0u) {
        addSDFTraversalCounter(sdfCounters, constants, sdfCounterSparseBrickInvalid);
        return false;
    }
    if (brick.sampleBoundsMin.w > 0.0f || brick.sampleBoundsMax.w < 0.0f) {
        addSDFTraversalCounter(sdfCounters, constants, sdfCounterSparseBrickRangeCulls);
        return false;
    }

    addSDFTraversalCounter(sdfCounters, constants, sdfCounterSparseBrickMarches);

    float minimumStep = max(cellSize * 0.10f / localUnitsPerWorldUnit, 0.0005f);

    float previousT = tNear;
    float3 previousLocalPosition = localOrigin + localDirection * previousT;
    float previousDistance = sampleVolumeBrickDistancePrepared(brickSamples, sampleContext, previousLocalPosition);
    if (!isfinite(previousDistance)) {
        return false;
    }

    float originalEntryT = previousT;
    if (previousDistance <= 0.0f) {
        float backStep = max(cellSize / localUnitsPerWorldUnit * 0.5f, minimumStep);
        float searchT = previousT;
        for (uint backtrack = 0u; backtrack < 12u; ++backtrack) {
            searchT = max(searchT - backStep, 0.0005f);
            float3 searchLocalPosition = localOrigin + localDirection * searchT;
            float searchDistance = sampleVolumeBrickDistancePrepared(brickSamples, sampleContext, searchLocalPosition);
            if (!isfinite(searchDistance)) {
                break;
            }
            if (searchDistance > 0.0f) {
                previousT = searchT;
                previousLocalPosition = searchLocalPosition;
                previousDistance = searchDistance;
                break;
            }
            if (searchT <= 0.0005f) {
                break;
            }
        }
    }

    float t = max(originalEntryT, previousT + max(fabs(previousDistance) / localUnitsPerWorldUnit * 0.9f, minimumStep));
    for (uint step = 0u; step < 192u && t <= tFar && t < closestT; ++step) {
        addSDFTraversalCounter(sdfCounters, constants, sdfCounterSparseBrickMarchSteps);
        float3 localPosition = localOrigin + localDirection * t;
        float distance = sampleVolumeBrickDistancePrepared(brickSamples, sampleContext, localPosition);
        if (!isfinite(distance)) {
            return false;
        }

        bool crossedSurface = (previousDistance > 0.0f && distance <= 0.0f)
            || (previousDistance < 0.0f && distance >= 0.0f);
        if (crossedSurface) {
            float lowT = previousT;
            float highT = t;
            float lowDistance = previousDistance;
            float3 refinedLocalPosition = localPosition;
            float refinedT = t;
            for (uint refine = 0u; refine < 8u; ++refine) {
                float midT = 0.5f * (lowT + highT);
                float3 midLocalPosition = localOrigin + localDirection * midT;
                float midDistance = sampleVolumeBrickDistancePrepared(brickSamples, sampleContext, midLocalPosition);
                if ((lowDistance > 0.0f && midDistance > 0.0f)
                    || (lowDistance < 0.0f && midDistance < 0.0f)) {
                    lowT = midT;
                    lowDistance = midDistance;
                } else {
                    highT = midT;
                    refinedLocalPosition = midLocalPosition;
                }
                refinedT = 0.5f * (lowT + highT);
            }

            bool useCubicHitPolish = cellSize <= 0.03f;
            bool useCoarseFilteredGradient = constants.renderQuality > 0u && cellSize > 0.03f;
            refinedLocalPosition = localOrigin + localDirection * refinedT;
            if (useCubicHitPolish) {
                uint polishCount = constants.renderQuality > 1u ? 2u : 1u;
                for (uint polish = 0u; polish < polishCount; ++polish) {
                    VolumeBrickDistanceGradient polished = sampleVolumeBrickDistanceGradientCubicPrepared(
                        brickSamples,
                        sampleContext,
                        refinedLocalPosition
                    );
                    float distanceSlope = dot(polished.gradient, localDirection);
                    if (!isfinite(polished.distance) || fabs(distanceSlope) <= 1e-6f) {
                        break;
                    }

                    float projectedT = refinedT - polished.distance / distanceSlope;
                    if (projectedT <= lowT || projectedT >= highT) {
                        break;
                    }

                    refinedT = projectedT;
                    refinedLocalPosition = localOrigin + localDirection * refinedT;
                }
            }

            float3 refinedWorldPosition = ray.origin + ray.direction * refinedT;
            float3 normal = volumeBrickNormal(
                volume,
                brickSamples,
                brickSampleCount,
                sampleContext,
                refinedLocalPosition,
                useCubicHitPolish,
                useCoarseFilteredGradient
            );
            bool frontFacing = dot(normal, ray.direction) <= 0.0f;
            if (!frontFacing) {
                normal = -normal;
            }

            hit.hit = true;
            hit.t = refinedT;
            hit.position = refinedWorldPosition;
            hit.localPosition = refinedLocalPosition;
            hit.normal = normal;
            hit.uv = float2(0.0f);
            hit.tangent = normalize(cross(fabs(normal.y) < 0.999f ? float3(0, 1, 0) : float3(1, 0, 0), normal));
            hit.bitangent = normalize(cross(normal, hit.tangent));
            GPUVolumeSample materialSample = sampleVolumeBrickMaterial(
                volume,
                brick,
                brickSamples,
                brickMaterialFieldSamples,
                brickSampleCount,
                brickMaterialFieldSampleCount,
                refinedLocalPosition
            );
            hit.materialID = materialSample.materialA;
            hit.materialID2 = materialSample.materialB;
            hit.materialBlend = clamp(materialSample.materialBlend, 0.0f, 1.0f);
            hit.volumeBaseColorOpacity = materialSample.baseColorOpacity;
            hit.volumeEmissionTransmission = materialSample.emissionTransmission;
            hit.volumeSurface = materialSample.surface;
            hit.volumeMaterialFieldFlags = materialSample.materialFieldFlags.x;
            hit.materialProgramIndex = volume.materialProgram.x;
            sampleVolumeBrickAttributes(
                brickIndex,
                volume,
                brick,
                brickAttributeDescriptors,
                brickAttributeSamples,
                brickAttributeSampleCount,
                refinedLocalPosition,
                hit.volumeAttributes0,
                hit.volumeAttributes1,
                hit.volumeAttributeSemantics0,
                hit.volumeAttributeSemantics1
            );
            hit.objectID = volume.metadata.y;
            hit.primitiveID = volume.metadata.z;
            hit.frontFacing = frontFacing;
            addSDFTraversalCounter(sdfCounters, constants, sdfCounterSparseBrickHits);
            return true;
        }

        previousT = t;
        previousDistance = distance;
        previousLocalPosition = localPosition;
        t += max(fabs(distance) / localUnitsPerWorldUnit * 0.8f, minimumStep);
    }

    return false;
}

static bool intersectVolumeBrick(
    uint brickIndex,
    Ray ray,
    constant GPURenderConstants &constants,
    constant GPUVolumeDescriptor &volume,
    constant GPUVolumeBrickDescriptor &brick,
    constant GPUVolumeBrickSample *brickSamples,
    constant GPUVolumeMaterialFieldSample *brickMaterialFieldSamples,
    constant GPUVolumeAttributeDescriptor *brickAttributeDescriptors,
    constant float4 *brickAttributeSamples,
    uint brickSampleCount,
    uint brickMaterialFieldSampleCount,
    uint brickAttributeSampleCount,
    float closestT,
    device atomic_uint *sdfCounters,
    thread Hit &hit
) {
    float4x4 worldToLocal = matrixFromColumns(
        volume.worldToLocal0,
        volume.worldToLocal1,
        volume.worldToLocal2,
        volume.worldToLocal3
    );
    float3 localOrigin = (worldToLocal * float4(ray.origin, 1.0f)).xyz;
    float3 localDirection = (worldToLocal * float4(ray.direction, 0.0f)).xyz;
    float localUnitsPerWorldUnit = max(length(localDirection), 1e-6f);
    float3 volumeExtent = max(volume.localBoundsMax.xyz - volume.localBoundsMin.xyz, float3(1e-6f));
    float3 volumeSpacing = volumeExtent / max(float3(volume.dimensions.xyz) - float3(1.0f), float3(1.0f));
    float cellSize = min(volumeSpacing.x, min(volumeSpacing.y, volumeSpacing.z));

    return intersectVolumeBrickPrepared(
        brickIndex,
        ray,
        constants,
        volume,
        brick,
        brickSamples,
        brickMaterialFieldSamples,
        brickAttributeDescriptors,
        brickAttributeSamples,
        brickSampleCount,
        brickMaterialFieldSampleCount,
        brickAttributeSampleCount,
        closestT,
        localOrigin,
        localDirection,
        localUnitsPerWorldUnit,
        cellSize,
        sdfCounters,
        hit
    );
}

static bool findVolumeBrickGrid(
    uint volumeIndex,
    constant GPURenderConstants &constants,
    constant GPUVolumeBrickGrid *volumeBrickGrids,
    thread GPUVolumeBrickGrid &grid
) {
    if (volumeBrickGrids == nullptr) {
        return false;
    }
    for (uint gridIndex = 0u; gridIndex < constants.volumeBrickGridCount; ++gridIndex) {
        constant GPUVolumeBrickGrid &candidate = volumeBrickGrids[gridIndex];
        if (candidate.brickSizeAndVolume.w == volumeIndex) {
            grid = candidate;
            return true;
        }
    }
    return false;
}

static Hit closestSparseVolumeBrickDDAHit(
    uint volumeIndex,
    Ray ray,
    constant GPURenderConstants &constants,
    constant GPUVolumeDescriptor &volume,
    constant GPUVolumeBrickDescriptor *volumeBricks,
    constant GPUVolumeBrickSample *volumeBrickSamples,
    constant GPUVolumeMaterialFieldSample *volumeBrickMaterialFieldSamples,
    constant GPUVolumeAttributeDescriptor *volumeBrickAttributeDescriptors,
    constant float4 *volumeBrickAttributeSamples,
    constant GPUVolumeBrickGrid *volumeBrickGrids,
    constant uint *volumeBrickGridIndices,
    device atomic_uint *sdfCounters,
    float closestT
) {
    Hit closest = emptyHit();
    closest.t = closestT;

    GPUVolumeBrickGrid grid;
    if (!findVolumeBrickGrid(volumeIndex, constants, volumeBrickGrids, grid)
        || volumeBrickGridIndices == nullptr) {
        return closest;
    }

    uint3 gridDimensions = grid.dimensionsAndIndexOffset.xyz;
    uint gridIndexOffset = grid.dimensionsAndIndexOffset.w;
    uint3 brickSize = max(grid.brickSizeAndVolume.xyz, uint3(1u));
    if (gridDimensions.x == 0u || gridDimensions.y == 0u || gridDimensions.z == 0u) {
        return closest;
    }

    float tNear;
    float tFar;
    if (!intersectAABB(ray, volume.worldBoundsMin.xyz, volume.worldBoundsMax.xyz, closestT, tNear, tFar)) {
        return closest;
    }

    float4x4 worldToLocal = matrixFromColumns(
        volume.worldToLocal0,
        volume.worldToLocal1,
        volume.worldToLocal2,
        volume.worldToLocal3
    );
    float3 localOrigin = (worldToLocal * float4(ray.origin, 1.0f)).xyz;
    float3 localDirection = (worldToLocal * float4(ray.direction, 0.0f)).xyz;
    float3 extent = max(volume.localBoundsMax.xyz - volume.localBoundsMin.xyz, float3(1e-6f));
    float3 sampleDenominator = max(float3(volume.dimensions.xyz) - float3(1.0f), float3(1.0f));
    float3 brickSizeFloat = max(float3(brickSize), float3(1.0f));
    float3 volumeSpacing = extent / sampleDenominator;
    float cellSize = min(volumeSpacing.x, min(volumeSpacing.y, volumeSpacing.z));
    float localUnitsPerWorldUnit = max(length(localDirection), 1e-6f);

    float t = tNear;
    float3 localPosition = localOrigin + localDirection * t;
    float3 samplePosition = ((localPosition - volume.localBoundsMin.xyz) / extent) * sampleDenominator;
    float3 brickPosition = (samplePosition + float3(0.5f)) / brickSizeFloat;
    int3 cell = int3(clamp(floor(brickPosition), float3(0.0f), float3(gridDimensions) - float3(1.0f)));

    float3 brickVelocity = (localDirection / extent) * sampleDenominator / brickSizeFloat;
    int3 stepDirection = int3(
        brickVelocity.x > 0.0f ? 1 : (brickVelocity.x < 0.0f ? -1 : 0),
        brickVelocity.y > 0.0f ? 1 : (brickVelocity.y < 0.0f ? -1 : 0),
        brickVelocity.z > 0.0f ? 1 : (brickVelocity.z < 0.0f ? -1 : 0)
    );
    float3 nextBoundary = float3(
        stepDirection.x > 0 ? (float)cell.x + 1.0f : (float)cell.x,
        stepDirection.y > 0 ? (float)cell.y + 1.0f : (float)cell.y,
        stepDirection.z > 0 ? (float)cell.z + 1.0f : (float)cell.z
    );
    float3 tMax = float3(
        stepDirection.x == 0 ? INFINITY : t + (nextBoundary.x - brickPosition.x) / brickVelocity.x,
        stepDirection.y == 0 ? INFINITY : t + (nextBoundary.y - brickPosition.y) / brickVelocity.y,
        stepDirection.z == 0 ? INFINITY : t + (nextBoundary.z - brickPosition.z) / brickVelocity.z
    );
    float3 tDelta = float3(
        stepDirection.x == 0 ? INFINITY : fabs(1.0f / brickVelocity.x),
        stepDirection.y == 0 ? INFINITY : fabs(1.0f / brickVelocity.y),
        stepDirection.z == 0 ? INFINITY : fabs(1.0f / brickVelocity.z)
    );
    uint3 macroDimensions = grid.macroDimensionsAndIndexOffset.xyz;
    uint macroIndexOffset = grid.macroDimensionsAndIndexOffset.w;
    uint3 macroSize = max(grid.macroSizeAndReserved.xyz, uint3(1u));
    bool hasMacroGrid = macroDimensions.x > 0u
        && macroDimensions.y > 0u
        && macroDimensions.z > 0u
        && macroIndexOffset < constants.volumeBrickGridIndexCount;

    uint maximumSteps = min(gridDimensions.x + gridDimensions.y + gridDimensions.z + 8u, 1024u);
    for (uint step = 0u; step < maximumSteps && t <= tFar && t < closest.t; ++step) {
        addSDFTraversalCounter(sdfCounters, constants, sdfCounterSparseGridCellsVisited);
        if (cell.x < 0 || cell.y < 0 || cell.z < 0
            || cell.x >= (int)gridDimensions.x
            || cell.y >= (int)gridDimensions.y
            || cell.z >= (int)gridDimensions.z) {
            break;
        }

        if (hasMacroGrid) {
            uint3 unsignedCell = uint3(cell);
            uint3 macroCell = min(unsignedCell / macroSize, macroDimensions - uint3(1u));
            uint macroSlot = macroIndexOffset
                + macroCell.x
                + macroCell.y * macroDimensions.x
                + macroCell.z * macroDimensions.x * macroDimensions.y;
            if (macroSlot < constants.volumeBrickGridIndexCount
                && volumeBrickGridIndices[macroSlot] == 0u) {
                float3 currentBrickPosition = brickPosition + brickVelocity * (t - tNear);
                float3 macroBoundary = float3(
                    stepDirection.x > 0
                        ? min((macroCell.x + 1u) * macroSize.x, gridDimensions.x)
                        : macroCell.x * macroSize.x,
                    stepDirection.y > 0
                        ? min((macroCell.y + 1u) * macroSize.y, gridDimensions.y)
                        : macroCell.y * macroSize.y,
                    stepDirection.z > 0
                        ? min((macroCell.z + 1u) * macroSize.z, gridDimensions.z)
                        : macroCell.z * macroSize.z
                );
                float3 macroTMax = float3(
                    stepDirection.x == 0 ? INFINITY : t + (macroBoundary.x - currentBrickPosition.x) / brickVelocity.x,
                    stepDirection.y == 0 ? INFINITY : t + (macroBoundary.y - currentBrickPosition.y) / brickVelocity.y,
                    stepDirection.z == 0 ? INFINITY : t + (macroBoundary.z - currentBrickPosition.z) / brickVelocity.z
                );
                float macroNextT = min(macroTMax.x, min(macroTMax.y, macroTMax.z));
                if (macroNextT > t + 1e-6f) {
                    addSDFTraversalCounter(sdfCounters, constants, sdfCounterSparseGridMacroSkips);
                    if (macroNextT > tFar || macroNextT >= closest.t) {
                        break;
                    }

                    t = macroNextT + 1e-5f;
                    currentBrickPosition = brickPosition + brickVelocity * (t - tNear);
                    cell = int3(clamp(floor(currentBrickPosition), float3(0.0f), float3(gridDimensions) - float3(1.0f)));
                    nextBoundary = float3(
                        stepDirection.x > 0 ? (float)cell.x + 1.0f : (float)cell.x,
                        stepDirection.y > 0 ? (float)cell.y + 1.0f : (float)cell.y,
                        stepDirection.z > 0 ? (float)cell.z + 1.0f : (float)cell.z
                    );
                    tMax = float3(
                        stepDirection.x == 0 ? INFINITY : t + (nextBoundary.x - currentBrickPosition.x) / brickVelocity.x,
                        stepDirection.y == 0 ? INFINITY : t + (nextBoundary.y - currentBrickPosition.y) / brickVelocity.y,
                        stepDirection.z == 0 ? INFINITY : t + (nextBoundary.z - currentBrickPosition.z) / brickVelocity.z
                    );
                    continue;
                }
            }
        }

        uint slot = gridIndexOffset
            + (uint)cell.x
            + (uint)cell.y * gridDimensions.x
            + (uint)cell.z * gridDimensions.x * gridDimensions.y;
        if (slot < constants.volumeBrickGridIndexCount) {
            uint brickIndex = volumeBrickGridIndices[slot];
            if (brickIndex != 0xffffffffu && brickIndex < constants.volumeBrickCount) {
                addSDFTraversalCounter(sdfCounters, constants, sdfCounterSparseBrickTests);
                Hit candidate = emptyHit();
                if (intersectVolumeBrickPrepared(
                    brickIndex,
                    ray,
                    constants,
                    volume,
                    volumeBricks[brickIndex],
                    volumeBrickSamples,
                    volumeBrickMaterialFieldSamples,
                    volumeBrickAttributeDescriptors,
                    volumeBrickAttributeSamples,
                    constants.volumeBrickSampleCount,
                    constants.volumeBrickMaterialFieldSampleCount,
                    constants.volumeBrickAttributeSampleCount,
                    closest.t,
                    localOrigin,
                    localDirection,
                    localUnitsPerWorldUnit,
                    cellSize,
                    sdfCounters,
                    candidate
                ) && candidate.t < closest.t) {
                    closest = candidate;
                }
            }
        }

        float nextT = min(tMax.x, min(tMax.y, tMax.z));
        if (closest.hit && closest.t <= nextT + 0.0005f) {
            return closest;
        }
        if (nextT > tFar || nextT >= closest.t) {
            break;
        }

        if (tMax.x <= tMax.y && tMax.x <= tMax.z) {
            cell.x += stepDirection.x;
            t = tMax.x;
            tMax.x += tDelta.x;
        } else if (tMax.y <= tMax.z) {
            cell.y += stepDirection.y;
            t = tMax.y;
            tMax.y += tDelta.y;
        } else {
            cell.z += stepDirection.z;
            t = tMax.z;
            tMax.z += tDelta.z;
        }
    }

    return closest;
}

static Hit closestVolumeHit(
    Ray ray,
    constant GPURenderConstants &constants,
    constant GPUVolumeDescriptor *volumes,
    constant GPUVolumeSample *volumeSamples,
    constant GPUVolumeAttributeDescriptor *volumeAttributeDescriptors,
    constant float4 *volumeAttributeSamples,
    constant GPUVolumeBrickDescriptor *volumeBricks,
    constant GPUVolumeBrickSample *volumeBrickSamples,
    constant GPUVolumeMaterialFieldSample *volumeBrickMaterialFieldSamples,
    constant GPUVolumeAttributeDescriptor *volumeBrickAttributeDescriptors,
    constant float4 *volumeBrickAttributeSamples,
    constant GPUAccelerationNode *volumeBrickBVHNodes,
    constant uint *volumeBrickBVHIndices,
    constant GPUVolumeBrickGrid *volumeBrickGrids,
    constant uint *volumeBrickGridIndices,
    device atomic_uint *sdfCounters,
    float closestT
) {
    Hit closest = emptyHit();
    closest.t = closestT;
    for (uint index = 0; index < constants.volumeCount; ++index) {
        if (volumes[index].metadata.w != 0u) {
            continue;
        }
        addSDFTraversalCounter(sdfCounters, constants, sdfCounterDenseVolumeTests);
        Hit candidate = emptyHit();
        if (intersectVolume(
            index,
            ray,
            constants,
            volumes[index],
            volumeSamples,
            volumeAttributeDescriptors,
            volumeAttributeSamples,
            constants.volumeSampleCount,
            constants.volumeAttributeSampleCount,
            closest.t,
            sdfCounters,
            candidate
        ) && candidate.t < closest.t) {
            closest = candidate;
        }
    }

    if (constants.volumeBrickGridCount > 0u
        && constants.volumeBrickGridIndexCount > 0u
        && volumeBrickGrids != nullptr
        && volumeBrickGridIndices != nullptr) {
        for (uint index = 0u; index < constants.volumeCount; ++index) {
            if (volumes[index].metadata.w != 1u) {
                continue;
            }
            Hit candidate = closestSparseVolumeBrickDDAHit(
                index,
                ray,
                constants,
                volumes[index],
                volumeBricks,
                volumeBrickSamples,
                volumeBrickMaterialFieldSamples,
                volumeBrickAttributeDescriptors,
                volumeBrickAttributeSamples,
                volumeBrickGrids,
                volumeBrickGridIndices,
                sdfCounters,
                closest.t
            );
            if (candidate.hit && candidate.t < closest.t) {
                closest = candidate;
            }
        }
        return closest;
    }

    if (constants.volumeBrickBVHNodeCount > 0u && volumeBrickBVHNodes != nullptr && volumeBrickBVHIndices != nullptr) {
        uint stack[64];
        uint stackCount = 0;
        stack[stackCount++] = 0;

        while (stackCount > 0u) {
            uint nodeIndex = stack[--stackCount];
            if (nodeIndex >= constants.volumeBrickBVHNodeCount) {
                continue;
            }

            constant GPUAccelerationNode &node = volumeBrickBVHNodes[nodeIndex];
            if (!intersectBounds(ray, node, closest.t)) {
                continue;
            }

            uint firstBrickIndex = node.metadata.z;
            uint brickIndexCount = node.metadata.w;
            if (brickIndexCount > 0u) {
                for (uint offset = 0u; offset < brickIndexCount; ++offset) {
                    uint indexSlot = firstBrickIndex + offset;
                    if (indexSlot >= constants.volumeBrickBVHIndexCount) {
                        continue;
                    }

                    uint brickIndex = volumeBrickBVHIndices[indexSlot];
                    if (brickIndex >= constants.volumeBrickCount) {
                        continue;
                    }

                    uint volumeIndex = volumeBricks[brickIndex].gridOriginAndVolume.w;
                    if (volumeIndex >= constants.volumeCount || volumes[volumeIndex].metadata.w != 1u) {
                        continue;
                    }

                    Hit candidate = emptyHit();
                    addSDFTraversalCounter(sdfCounters, constants, sdfCounterSparseBrickTests);
                    if (intersectVolumeBrick(
                        brickIndex,
                        ray,
                        constants,
                        volumes[volumeIndex],
                        volumeBricks[brickIndex],
                        volumeBrickSamples,
                        volumeBrickMaterialFieldSamples,
                        volumeBrickAttributeDescriptors,
                        volumeBrickAttributeSamples,
                        constants.volumeBrickSampleCount,
                        constants.volumeBrickMaterialFieldSampleCount,
                        constants.volumeBrickAttributeSampleCount,
                        closest.t,
                        sdfCounters,
                        candidate
                    ) && candidate.t < closest.t) {
                        closest = candidate;
                    }
                }
            } else {
                uint leftChild = node.metadata.x;
                uint rightChild = node.metadata.y;
                if (stackCount + 2u <= 64u) {
                    stack[stackCount++] = rightChild;
                    stack[stackCount++] = leftChild;
                }
            }
        }

        return closest;
    }

    for (uint brickIndex = 0; brickIndex < constants.volumeBrickCount; ++brickIndex) {
        uint volumeIndex = volumeBricks[brickIndex].gridOriginAndVolume.w;
        if (volumeIndex >= constants.volumeCount || volumes[volumeIndex].metadata.w != 1u) {
            continue;
        }
        Hit candidate = emptyHit();
        addSDFTraversalCounter(sdfCounters, constants, sdfCounterSparseBrickTests);
        if (intersectVolumeBrick(
            brickIndex,
            ray,
            constants,
            volumes[volumeIndex],
            volumeBricks[brickIndex],
            volumeBrickSamples,
            volumeBrickMaterialFieldSamples,
            volumeBrickAttributeDescriptors,
            volumeBrickAttributeSamples,
            constants.volumeBrickSampleCount,
            constants.volumeBrickMaterialFieldSampleCount,
            constants.volumeBrickAttributeSampleCount,
            closest.t,
            sdfCounters,
            candidate
        ) && candidate.t < closest.t) {
            closest = candidate;
        }
    }
    return closest;
}

static Hit intersectSceneLinear(Ray ray, constant GPURenderConstants &constants, constant GPUTriangle *triangles) {
    Hit closest = emptyHit();
    for (uint index = 0; index < constants.triangleCount; ++index) {
        float t;
        float3 normal;
        float2 uv;
        float3 tangent;
        float3 bitangent;
        bool frontFacing;
        if (intersectTriangle(ray, triangles[index], t, normal, uv, tangent, bitangent, frontFacing) && t < closest.t) {
            closest.hit = true;
            closest.t = t;
            closest.position = ray.origin + t * ray.direction;
            closest.normal = normal;
            closest.uv = uv;
            closest.tangent = tangent;
            closest.bitangent = bitangent;
            closest.materialID = triangles[index].materialID;
            closest.materialID2 = triangles[index].materialID;
            closest.materialBlend = 0.0f;
            closest.objectID = triangles[index].objectID;
            closest.primitiveID = index;
            closest.frontFacing = frontFacing;
        }
    }

    return closest;
}

static Hit intersectScene(
    Ray ray,
    constant GPURenderConstants &constants,
    constant GPUTriangle *triangles,
    constant GPUAccelerationNode *nodes,
    constant uint *primitiveIndices,
    constant GPUVolumeDescriptor *volumes,
    constant GPUVolumeSample *volumeSamples,
    constant GPUVolumeAttributeDescriptor *volumeAttributeDescriptors,
    constant float4 *volumeAttributeSamples,
    constant GPUVolumeBrickDescriptor *volumeBricks,
    constant GPUVolumeBrickSample *volumeBrickSamples,
    constant GPUVolumeMaterialFieldSample *volumeBrickMaterialFieldSamples,
    constant GPUVolumeAttributeDescriptor *volumeBrickAttributeDescriptors,
    constant float4 *volumeBrickAttributeSamples,
    constant GPUAccelerationNode *volumeBrickBVHNodes,
    constant uint *volumeBrickBVHIndices,
    constant GPUVolumeBrickGrid *volumeBrickGrids,
    constant uint *volumeBrickGridIndices,
    device atomic_uint *sdfCounters
) {
    Hit closest = emptyHit();
    if (constants.accelerationNodeCount == 0 || nodes == nullptr || primitiveIndices == nullptr) {
        closest = intersectSceneLinear(ray, constants, triangles);
        Hit volumeHit = closestVolumeHit(
            ray,
            constants,
            volumes,
            volumeSamples,
            volumeAttributeDescriptors,
            volumeAttributeSamples,
            volumeBricks,
            volumeBrickSamples,
            volumeBrickMaterialFieldSamples,
            volumeBrickAttributeDescriptors,
            volumeBrickAttributeSamples,
            volumeBrickBVHNodes,
            volumeBrickBVHIndices,
            volumeBrickGrids,
            volumeBrickGridIndices,
            sdfCounters,
            closest.t
        );
        return volumeHit.hit ? volumeHit : closest;
    }

    uint stack[64];
    uint stackCount = 0;
    stack[stackCount++] = 0;

    while (stackCount > 0) {
        uint nodeIndex = stack[--stackCount];
        if (nodeIndex >= constants.accelerationNodeCount) {
            continue;
        }

        constant GPUAccelerationNode &node = nodes[nodeIndex];
        if (!intersectBounds(ray, node, closest.t)) {
            continue;
        }

        uint firstPrimitive = node.metadata.z;
        uint primitiveCount = node.metadata.w;

        if (primitiveCount > 0) {
            for (uint offset = 0; offset < primitiveCount; ++offset) {
                uint triangleIndex = primitiveIndices[firstPrimitive + offset];
                if (triangleIndex >= constants.triangleCount) {
                    continue;
                }

                float t;
                float3 normal;
                float2 uv;
                float3 tangent;
                float3 bitangent;
                bool frontFacing;
                if (intersectTriangle(ray, triangles[triangleIndex], t, normal, uv, tangent, bitangent, frontFacing) && t < closest.t) {
                    closest.hit = true;
                    closest.t = t;
                    closest.position = ray.origin + t * ray.direction;
                    closest.normal = normal;
                    closest.uv = uv;
                    closest.tangent = tangent;
                    closest.bitangent = bitangent;
                    closest.materialID = triangles[triangleIndex].materialID;
                    closest.materialID2 = triangles[triangleIndex].materialID;
                    closest.materialBlend = 0.0f;
                    closest.objectID = triangles[triangleIndex].objectID;
                    closest.primitiveID = triangleIndex;
                    closest.frontFacing = frontFacing;
                }
            }
        } else {
            uint leftChild = node.metadata.x;
            uint rightChild = node.metadata.y;
            if (stackCount + 2u <= 64u) {
                stack[stackCount++] = rightChild;
                stack[stackCount++] = leftChild;
            }
        }
    }

    Hit volumeHit = closestVolumeHit(
        ray,
        constants,
        volumes,
        volumeSamples,
        volumeAttributeDescriptors,
        volumeAttributeSamples,
        volumeBricks,
        volumeBrickSamples,
        volumeBrickMaterialFieldSamples,
        volumeBrickAttributeDescriptors,
        volumeBrickAttributeSamples,
        volumeBrickBVHNodes,
        volumeBrickBVHIndices,
        volumeBrickGrids,
        volumeBrickGridIndices,
        sdfCounters,
        closest.t
    );
    if (volumeHit.hit) {
        closest = volumeHit;
    }

    return closest;
}

static float3 transformRayTracingNormal(constant GPURayTracingInstance &instance, float3 normal) {
    float4x4 normalTransform = float4x4(
        instance.normalTransform0,
        instance.normalTransform1,
        instance.normalTransform2,
        instance.normalTransform3
    );
    return normalize((normalTransform * float4(normal, 0.0f)).xyz);
}

static Hit intersectSceneHardware(
    Ray ray,
    acceleration_structure<instancing> scene,
    constant GPUTriangle *localTriangles,
    constant GPURayTracingInstance *rtInstances
) {
    raytracing::ray query;
    query.origin = ray.origin;
    query.direction = ray.direction;
    query.min_distance = 0.0005f;
    query.max_distance = INFINITY;

    intersector<triangle_data, instancing> sceneIntersector;
    auto result = sceneIntersector.intersect(query, scene);
    if (result.type != intersection_type::triangle) {
        return emptyHit();
    }

    uint instanceID = result.instance_id;
    uint primitiveID = result.primitive_id;
    constant GPURayTracingInstance &instance = rtInstances[instanceID];
    uint triangleIndex = instance.metadata.x + primitiveID;
    constant GPUTriangle &triangle = localTriangles[triangleIndex];
    float2 barycentric = result.triangle_barycentric_coord;
    float w = 1.0f - barycentric.x - barycentric.y;

    Hit hit;
    hit.hit = true;
    hit.t = result.distance;
    hit.position = ray.origin + result.distance * ray.direction;
    hit.normal = transformRayTracingNormal(
        instance,
        normalize(w * triangle.n0.xyz + barycentric.x * triangle.n1.xyz + barycentric.y * triangle.n2.xyz)
    );
    hit.frontFacing = dot(hit.normal, ray.direction) <= 0.0f;
    if (dot(hit.normal, ray.direction) > 0.0f) {
        hit.normal = -hit.normal;
    }
    hit.uv = w * triangle.uv0.xy + barycentric.x * triangle.uv1.xy + barycentric.y * triangle.uv2.xy;
    hit.tangent = transformRayTracingNormal(instance, triangle.tangent.xyz);
    hit.bitangent = transformRayTracingNormal(instance, triangle.bitangent.xyz);
    hit.materialID = instance.metadata.y;
    hit.materialID2 = instance.metadata.y;
    hit.materialBlend = 0.0f;
    hit.volumeBaseColorOpacity = float4(0);
    hit.volumeEmissionTransmission = float4(0);
    hit.volumeSurface = float4(0);
    hit.volumeMaterialFieldFlags = 0u;
    hit.volumeAttributes0 = float4(0);
    hit.volumeAttributes1 = float4(0);
    hit.volumeAttributeSemantics0 = uint4(0);
    hit.volumeAttributeSemantics1 = uint4(0);
    hit.objectID = instance.metadata.z;
    hit.primitiveID = triangleIndex;
    return hit;
}

static float3 subsurfaceSigmaT(GPUMaterial material) {
    return 1.0f / materialSubsurfaceRadius(material);
}

static float sampleSubsurfaceFreeFlight(float3 sigmaT, float2 u) {
    float sigma = sigmaT.z;
    if (u.x < 0.33333333333f) {
        sigma = sigmaT.x;
    } else if (u.x < 0.66666666667f) {
        sigma = sigmaT.y;
    }

    return -log(max(1.0f - u.y, 1e-6f)) / max(sigma, 1e-4f);
}

static float subsurfaceCollisionPDF(float3 sigmaT, float distance) {
    float3 transmittance = exp(-sigmaT * distance);
    return max((sigmaT.x * transmittance.x + sigmaT.y * transmittance.y + sigmaT.z * transmittance.z) * 0.33333333333f, 1e-6f);
}

static float subsurfaceBoundaryPDF(float3 sigmaT, float distance) {
    float3 transmittance = exp(-sigmaT * distance);
    return max((transmittance.x + transmittance.y + transmittance.z) * 0.33333333333f, 1e-6f);
}

static float3 subsurfaceCollisionWeight(float3 sigmaT, float3 scatteringAlbedo, float distance) {
    float3 transmittance = exp(-sigmaT * distance);
    return scatteringAlbedo * sigmaT * transmittance / subsurfaceCollisionPDF(sigmaT, distance);
}

static float3 subsurfaceBoundaryWeight(float3 sigmaT, float distance) {
    float3 transmittance = exp(-sigmaT * distance);
    return transmittance / subsurfaceBoundaryPDF(sigmaT, distance);
}

static bool continueSubsurfaceRandomWalk(
    Hit entryHit,
    GPUMaterial material,
    constant GPURenderConstants &constants,
    constant GPUTriangle *triangles,
    constant GPUAccelerationNode *nodes,
    constant uint *primitiveIndices,
    constant GPUVolumeDescriptor *volumes,
    constant GPUVolumeSample *volumeSamples,
    constant GPUVolumeAttributeDescriptor *volumeAttributeDescriptors,
    constant float4 *volumeAttributeSamples,
    constant GPUVolumeBrickDescriptor *volumeBricks,
    constant GPUVolumeBrickSample *volumeBrickSamples,
    constant GPUVolumeMaterialFieldSample *volumeBrickMaterialFieldSamples,
    constant GPUVolumeAttributeDescriptor *volumeBrickAttributeDescriptors,
    constant float4 *volumeBrickAttributeSamples,
    constant GPUAccelerationNode *volumeBrickBVHNodes,
    constant uint *volumeBrickBVHIndices,
    constant GPUVolumeBrickGrid *volumeBrickGrids,
    constant uint *volumeBrickGridIndices,
    device atomic_uint *sdfCounters,
    thread Ray &ray,
    thread float3 &throughput,
    thread float &previousBSDFPDF,
    thread uint &state
) {
    float subsurface = materialSubsurface(material);
    if (subsurface <= 0.0f || !entryHit.frontFacing) {
        return false;
    }

    float3 entryDirection = orientHemisphere(
        cosineHemisphere(float2(randomFloat(state), randomFloat(state))),
        -entryHit.normal
    );
    Ray mediumRay;
    mediumRay.origin = entryHit.position + entryDirection * 0.001f;
    mediumRay.direction = entryDirection;

    float3 sigmaT = subsurfaceSigmaT(material);
    float3 scatteringAlbedo = materialSubsurfaceColor(material);
    float anisotropy = materialSubsurfaceAnisotropy(material);

    for (uint step = 0u; step < 8u; ++step) {
        addSDFTraversalCounter(sdfCounters, constants, sdfCounterBounceSceneQueries);
        Hit boundaryHit = intersectScene(
            mediumRay,
            constants,
            triangles,
            nodes,
            primitiveIndices,
            volumes,
            volumeSamples,
            volumeAttributeDescriptors,
            volumeAttributeSamples,
            volumeBricks,
            volumeBrickSamples,
            volumeBrickMaterialFieldSamples,
            volumeBrickAttributeDescriptors,
            volumeBrickAttributeSamples,
            volumeBrickBVHNodes,
            volumeBrickBVHIndices,
            volumeBrickGrids,
            volumeBrickGridIndices,
            sdfCounters
        );
        if (!boundaryHit.hit) {
            return false;
        }

        float freeFlight = sampleSubsurfaceFreeFlight(sigmaT, float2(randomFloat(state), randomFloat(state)));
        if (freeFlight < boundaryHit.t) {
            mediumRay.origin += mediumRay.direction * freeFlight;
            mediumRay.direction = sampleHenyeyGreenstein(
                float2(randomFloat(state), randomFloat(state)),
                mediumRay.direction,
                anisotropy
            );
            throughput *= subsurfaceCollisionWeight(sigmaT, scatteringAlbedo, freeFlight);
            if (maxComponent(throughput) <= 1e-4f) {
                return false;
            }
            continue;
        }

        float3 exitNormal = boundaryHit.frontFacing ? boundaryHit.normal : -boundaryHit.normal;
        exitNormal = normalize(exitNormal);
        float3 localDirection = cosineHemisphere(float2(randomFloat(state), randomFloat(state)));
        ray.direction = orientHemisphere(localDirection, exitNormal);
        ray.origin = boundaryHit.position + exitNormal * 0.001f;
        throughput *= subsurfaceBoundaryWeight(sigmaT, boundaryHit.t);
        previousBSDFPDF = max(dot(exitNormal, ray.direction), 0.0f) * 0.31830988618f;
        return true;
    }

    return false;
}

static bool continueSubsurfaceRandomWalkHardware(
    Hit entryHit,
    GPUMaterial material,
    acceleration_structure<instancing> scene,
    constant GPUTriangle *localTriangles,
    constant GPURayTracingInstance *rtInstances,
    thread Ray &ray,
    thread float3 &throughput,
    thread float &previousBSDFPDF,
    thread uint &state
) {
    float subsurface = materialSubsurface(material);
    if (subsurface <= 0.0f || !entryHit.frontFacing) {
        return false;
    }

    float3 entryDirection = orientHemisphere(
        cosineHemisphere(float2(randomFloat(state), randomFloat(state))),
        -entryHit.normal
    );
    Ray mediumRay;
    mediumRay.origin = entryHit.position + entryDirection * 0.001f;
    mediumRay.direction = entryDirection;

    float3 sigmaT = subsurfaceSigmaT(material);
    float3 scatteringAlbedo = materialSubsurfaceColor(material);
    float anisotropy = materialSubsurfaceAnisotropy(material);

    for (uint step = 0u; step < 8u; ++step) {
        Hit boundaryHit = intersectSceneHardware(mediumRay, scene, localTriangles, rtInstances);
        if (!boundaryHit.hit) {
            return false;
        }

        float freeFlight = sampleSubsurfaceFreeFlight(sigmaT, float2(randomFloat(state), randomFloat(state)));
        if (freeFlight < boundaryHit.t) {
            mediumRay.origin += mediumRay.direction * freeFlight;
            mediumRay.direction = sampleHenyeyGreenstein(
                float2(randomFloat(state), randomFloat(state)),
                mediumRay.direction,
                anisotropy
            );
            throughput *= subsurfaceCollisionWeight(sigmaT, scatteringAlbedo, freeFlight);
            if (maxComponent(throughput) <= 1e-4f) {
                return false;
            }
            continue;
        }

        float3 exitNormal = boundaryHit.frontFacing ? boundaryHit.normal : -boundaryHit.normal;
        exitNormal = normalize(exitNormal);
        float3 localDirection = cosineHemisphere(float2(randomFloat(state), randomFloat(state)));
        ray.direction = orientHemisphere(localDirection, exitNormal);
        ray.origin = boundaryHit.position + exitNormal * 0.001f;
        throughput *= subsurfaceBoundaryWeight(sigmaT, boundaryHit.t);
        previousBSDFPDF = max(dot(exitNormal, ray.direction), 0.0f) * 0.31830988618f;
        return true;
    }

    return false;
}

static bool continueTransmissionVolumeRandomWalk(
    Hit boundaryHit,
    GPUMaterial material,
    thread Ray &ray,
    thread float3 &throughput,
    thread float &previousBSDFPDF,
    thread uint &state
) {
    if (boundaryHit.frontFacing || !materialHasVolumeScattering(material)) {
        return false;
    }

    float3 sigmaT = materialVolumeSigmaT(material);
    float3 sigmaS = materialVolumeSigmaS(material);
    if (maxComponent(sigmaT) <= 1e-5f || maxComponent(sigmaS) <= 1e-5f) {
        return false;
    }

    float freeFlight = sampleSubsurfaceFreeFlight(sigmaT, float2(randomFloat(state), randomFloat(state)));
    if (freeFlight >= boundaryHit.t) {
        throughput *= materialVolumeTransmittance(material, boundaryHit.t)
            / subsurfaceBoundaryPDF(sigmaT, boundaryHit.t);
        return false;
    }

    float3 transmittance = exp(-sigmaT * freeFlight);
    throughput *= sigmaS * transmittance / subsurfaceCollisionPDF(sigmaT, freeFlight);
    ray.origin += ray.direction * freeFlight;
    ray.direction = sampleHenyeyGreenstein(
        float2(randomFloat(state), randomFloat(state)),
        ray.direction,
        materialVolumeAnisotropy(material)
    );
    ray.origin += ray.direction * 0.001f;
    previousBSDFPDF = 0.0f;
    return maxComponent(throughput) > 1e-4f;
}

static float4 sampleTexture(
    uint textureIndexPlusOne,
    float2 uv,
    constant GPUTextureDescriptor *textureDescriptors,
    constant float4 *texturePixels,
    float4 fallback
) {
    if (textureIndexPlusOne == 0u || textureDescriptors == nullptr || texturePixels == nullptr) {
        return fallback;
    }

    constant GPUTextureDescriptor &descriptor = textureDescriptors[textureIndexPlusOne - 1u];
    uint offset = descriptor.metadata.x;
    uint width = descriptor.metadata.y;
    uint height = descriptor.metadata.z;
    uint samplingMode = descriptor.metadata.w;

    if (width == 0u || height == 0u) {
        return fallback;
    }

    float2 wrapped = fract(uv);
    if (samplingMode == 1u && width > 1u && height > 1u) {
        float2 texelPosition = wrapped * float2((float)width, (float)height) - 0.5f;
        float2 base = floor(texelPosition);
        float2 blend = fract(texelPosition);
        uint x0 = (uint)fmod(base.x + (float)width, (float)width);
        uint y0 = (uint)fmod(base.y + (float)height, (float)height);
        uint x1 = (x0 + 1u) % width;
        uint y1 = (y0 + 1u) % height;
        float4 c00 = texturePixels[offset + y0 * width + x0];
        float4 c10 = texturePixels[offset + y0 * width + x1];
        float4 c01 = texturePixels[offset + y1 * width + x0];
        float4 c11 = texturePixels[offset + y1 * width + x1];
        return mix(mix(c00, c10, blend.x), mix(c01, c11, blend.x), blend.y);
    }

    uint x = min((uint)(wrapped.x * (float)width), width - 1u);
    uint y = min((uint)(wrapped.y * (float)height), height - 1u);
    return texturePixels[offset + y * width + x];
}

static float3 fallbackSky(float3 direction) {
    float sky = 0.5f * (direction.y + 1.0f);
    return mix(float3(0.02f, 0.025f, 0.035f), float3(0.25f, 0.32f, 0.45f), sky);
}

static float3 sampleEnvironment(
    float3 direction,
    constant GPURenderConstants &constants,
    constant GPUTextureDescriptor *textureDescriptors,
    constant float4 *texturePixels
) {
    float intensity = max(constants.environmentIntensity, 0.0f);
    if (constants.environmentTextureIndexPlusOne == 0u) {
        return fallbackSky(direction) * intensity;
    }

    float s = sin(constants.environmentRotationY);
    float c = cos(constants.environmentRotationY);
    float3 rotated = normalize(float3(
        c * direction.x - s * direction.z,
        direction.y,
        s * direction.x + c * direction.z
    ));
    float u = atan2(rotated.z, rotated.x) * 0.15915494309f + 0.5f;
    float v = acos(clamp(rotated.y, -1.0f, 1.0f)) * 0.31830988618f;
    v = clamp(v, 0.00001f, 0.99999f);
    float3 color = sampleTexture(
        constants.environmentTextureIndexPlusOne,
        float2(u, v),
        textureDescriptors,
        texturePixels,
        float4(fallbackSky(direction), 1.0f)
    ).xyz * intensity;
    float maxRadiance = max(constants.environmentMaxRadiance, 0.0f);
    if (maxRadiance > 0.0f) {
        color = min(color, float3(maxRadiance));
    }
    return color;
}

static float3 sampleInteractiveDiffuseEnvironment(
    float3 normal,
    constant GPURenderConstants &constants,
    constant GPUTextureDescriptor *textureDescriptors,
    constant float4 *texturePixels
) {
    float3 up = sampleEnvironment(float3(0.0f, 1.0f, 0.0f), constants, textureDescriptors, texturePixels);
    float3 down = sampleEnvironment(float3(0.0f, -1.0f, 0.0f), constants, textureDescriptors, texturePixels);
    float3 side = (
        sampleEnvironment(float3(1.0f, 0.0f, 0.0f), constants, textureDescriptors, texturePixels)
        + sampleEnvironment(float3(-1.0f, 0.0f, 0.0f), constants, textureDescriptors, texturePixels)
        + sampleEnvironment(float3(0.0f, 0.0f, 1.0f), constants, textureDescriptors, texturePixels)
        + sampleEnvironment(float3(0.0f, 0.0f, -1.0f), constants, textureDescriptors, texturePixels)
    ) * 0.25f;
    float upWeight = smoothstep(-0.15f, 0.85f, normal.y);
    float downWeight = smoothstep(0.15f, -0.85f, normal.y);
    float sideWeight = max(0.0f, 1.0f - upWeight - downWeight);
    return up * upWeight + down * downWeight + side * sideWeight;
}

static float3 interactiveHemisphereDirection(float3 direction, float3 normal) {
    float nDotD = dot(normal, direction);
    if (nDotD < 0.0f) {
        direction = direction - normal * (2.0f * nDotD);
    }
    return normalize(direction);
}

static float3 sampleInteractiveSpecularEnvironment(
    float3 reflectionDirection,
    float3 normal,
    float roughness,
    constant GPURenderConstants &constants,
    constant GPUTextureDescriptor *textureDescriptors,
    constant float4 *texturePixels
) {
    reflectionDirection = interactiveHemisphereDirection(normalize(reflectionDirection), normal);
    roughness = clamp(roughness, 0.0f, 1.0f);
    float spread = roughness * roughness;
    float3 helper = fabs(reflectionDirection.y) < 0.999f
        ? float3(0.0f, 1.0f, 0.0f)
        : float3(1.0f, 0.0f, 0.0f);
    float3 tangent = normalize(cross(helper, reflectionDirection));
    float3 bitangent = cross(reflectionDirection, tangent);

    float3 center = sampleEnvironment(reflectionDirection, constants, textureDescriptors, texturePixels);
    float3 cone = center * 0.42f;
    cone += sampleEnvironment(
        interactiveHemisphereDirection(reflectionDirection + tangent * spread * 0.95f + normal * spread * 0.18f, normal),
        constants,
        textureDescriptors,
        texturePixels
    ) * 0.145f;
    cone += sampleEnvironment(
        interactiveHemisphereDirection(reflectionDirection - tangent * spread * 0.95f + normal * spread * 0.18f, normal),
        constants,
        textureDescriptors,
        texturePixels
    ) * 0.145f;
    cone += sampleEnvironment(
        interactiveHemisphereDirection(reflectionDirection + bitangent * spread * 0.95f + normal * spread * 0.18f, normal),
        constants,
        textureDescriptors,
        texturePixels
    ) * 0.145f;
    cone += sampleEnvironment(
        interactiveHemisphereDirection(reflectionDirection - bitangent * spread * 0.95f + normal * spread * 0.18f, normal),
        constants,
        textureDescriptors,
        texturePixels
    ) * 0.145f;

    float3 diffuseFallback = sampleInteractiveDiffuseEnvironment(normal, constants, textureDescriptors, texturePixels);
    float roughDiffuseMix = smoothstep(0.62f, 0.95f, roughness);
    return mix(cone, diffuseFallback, roughDiffuseMix);
}

static uint environmentPixelIndexForDirection(
    float3 direction,
    constant GPURenderConstants &constants,
    constant GPUTextureDescriptor *textureDescriptors
) {
    if (constants.environmentTextureIndexPlusOne == 0u || textureDescriptors == nullptr) {
        return 0u;
    }

    constant GPUTextureDescriptor &descriptor = textureDescriptors[constants.environmentTextureIndexPlusOne - 1u];
    uint width = descriptor.metadata.y;
    uint height = descriptor.metadata.z;
    if (width == 0u || height == 0u) {
        return 0u;
    }

    float s = sin(constants.environmentRotationY);
    float c = cos(constants.environmentRotationY);
    float3 rotated = normalize(float3(
        c * direction.x - s * direction.z,
        direction.y,
        s * direction.x + c * direction.z
    ));
    float u = fract(atan2(rotated.z, rotated.x) * 0.15915494309f + 0.5f);
    float v = clamp(acos(clamp(rotated.y, -1.0f, 1.0f)) * 0.31830988618f, 0.0f, 0.99999994f);
    uint x = min((uint)(u * (float)width), width - 1u);
    uint y = min((uint)(v * (float)height), height - 1u);
    return y * width + x;
}

static float environmentPDF(
    float3 direction,
    constant GPURenderConstants &constants,
    constant GPUTextureDescriptor *textureDescriptors,
    constant GPUEnvironmentSample *environmentSamples
) {
    if (environmentSamples == nullptr || constants.environmentDistributionCount == 0u) {
        return 0.0f;
    }

    uint index = environmentPixelIndexForDirection(direction, constants, textureDescriptors);
    if (index >= constants.environmentDistributionCount) {
        return 0.0f;
    }
    return max(environmentSamples[index].distribution.y, 0.0f);
}

static uint selectEnvironmentSampleIndex(
    constant GPUEnvironmentSample *environmentSamples,
    uint count,
    float sample
) {
    if (count <= 1u) {
        return 0u;
    }

    float target = clamp(sample, 0.0f, 0.99999994f);
    uint low = 0u;
    uint high = count - 1u;
    while (low < high) {
        uint mid = (low + high) >> 1u;
        if (target <= environmentSamples[mid].distribution.x) {
            high = mid;
        } else {
            low = mid + 1u;
        }
    }
    return low;
}

static float3 sampleEnvironmentDirection(
    float2 pixelSample,
    float cdfSample,
    constant GPURenderConstants &constants,
    constant GPUTextureDescriptor *textureDescriptors,
    constant GPUEnvironmentSample *environmentSamples,
    thread float &pdf
) {
    pdf = 0.0f;
    if (constants.environmentTextureIndexPlusOne == 0u
        || constants.environmentDistributionCount == 0u
        || textureDescriptors == nullptr
        || environmentSamples == nullptr) {
        return float3(0.0f, 1.0f, 0.0f);
    }

    constant GPUTextureDescriptor &descriptor = textureDescriptors[constants.environmentTextureIndexPlusOne - 1u];
    uint width = descriptor.metadata.y;
    uint height = descriptor.metadata.z;
    if (width == 0u || height == 0u) {
        return float3(0.0f, 1.0f, 0.0f);
    }

    uint index = selectEnvironmentSampleIndex(
        environmentSamples,
        constants.environmentDistributionCount,
        cdfSample
    );
    index = min(index, constants.environmentDistributionCount - 1u);
    uint x = index % width;
    uint y = index / width;

    float u = ((float)x + pixelSample.x) / (float)width;
    float v = ((float)y + pixelSample.y) / (float)height;
    float phi = (u - 0.5f) * 6.28318530718f;
    float theta = clamp(v, 0.00001f, 0.99999f) * 3.14159265359f;
    float sinTheta = sin(theta);
    float3 localDirection = normalize(float3(
        cos(phi) * sinTheta,
        cos(theta),
        sin(phi) * sinTheta
    ));

    float s = sin(constants.environmentRotationY);
    float c = cos(constants.environmentRotationY);
    pdf = max(environmentSamples[index].distribution.y, 0.0f);
    return normalize(float3(
        c * localDirection.x + s * localDirection.z,
        localDirection.y,
        -s * localDirection.x + c * localDirection.z
    ));
}

static GPUMaterial applyBaseColorTexture(
    GPUMaterial material,
    Hit hit,
    constant GPUTextureDescriptor *textureDescriptors,
    constant float4 *texturePixels
) {
    uint textureIndexPlusOne = (uint)material.parameters.z;
    if (textureIndexPlusOne == 0u) {
        return material;
    }

    float4 texel = sampleTexture(textureIndexPlusOne, hit.uv, textureDescriptors, texturePixels, float4(1));
    material.baseColor *= texel;
    return material;
}

static Hit applyNormalMap(
    Hit hit,
    GPUMaterial material,
    constant GPUTextureDescriptor *textureDescriptors,
    constant float4 *texturePixels,
    float3 rayDirection
) {
    uint textureIndexPlusOne = (uint)material.parameters.w;
    if (textureIndexPlusOne == 0u) {
        return hit;
    }

    float3 mapped = sampleTexture(textureIndexPlusOne, hit.uv, textureDescriptors, texturePixels, float4(0.5f, 0.5f, 1.0f, 1.0f)).xyz;
    mapped = normalize(mapped * 2.0f - 1.0f);

    float3 tangent = hit.tangent - hit.normal * dot(hit.tangent, hit.normal);
    if (length(tangent) <= 1e-5f) {
        float3 helper = fabs(hit.normal.y) < 0.999f ? float3(0, 1, 0) : float3(1, 0, 0);
        tangent = cross(helper, hit.normal);
    }
    tangent = normalize(tangent);

    float3 bitangent = hit.bitangent - hit.normal * dot(hit.bitangent, hit.normal);
    if (length(bitangent) <= 1e-5f) {
        bitangent = cross(hit.normal, tangent);
    }
    bitangent = normalize(bitangent);

    hit.normal = normalize(mapped.x * tangent + mapped.y * bitangent + mapped.z * hit.normal);
    if (dot(hit.normal, rayDirection) > 0.0f) {
        hit.normal = -hit.normal;
    }
    return hit;
}

static Ray makeCameraRay(
    GPUCamera camera,
    uint width,
    uint height,
    uint2 gid,
    float jitterX,
    float jitterY,
    float lensX,
    float lensY
) {
    float u = ((float)gid.x + jitterX) / (float)width;
    float v = 1.0f - (((float)gid.y + jitterY) / (float)height);

    Ray ray;
    float3 planePoint = camera.lowerLeft.xyz + u * camera.horizontal.xyz + v * camera.vertical.xyz;
    if (camera.origin.w > 0.5f) {
        ray.origin = planePoint;
        ray.direction = normalize(cross(camera.vertical.xyz, camera.horizontal.xyz));
    } else {
        ray.origin = camera.origin.xyz;
        ray.direction = normalize(planePoint - ray.origin);
    }
    float apertureRadius = max(camera.lens.x, 0.0f);
    if (camera.origin.w <= 0.5f && apertureRadius > 0.0f) {
        float3 forward = normalize(cross(camera.vertical.xyz, camera.horizontal.xyz));
        float focusDistance = max(camera.lens.y, 0.0001f);
        float focalT = focusDistance / max(dot(ray.direction, forward), 0.0001f);
        float3 focalPoint = ray.origin + ray.direction * focalT;
        float2 disk = uniformDisk(float2(lensX, lensY)) * apertureRadius;
        float3 right = normalize(camera.horizontal.xyz);
        float3 trueUp = normalize(camera.vertical.xyz);
        ray.origin += right * disk.x + trueUp * disk.y;
        ray.direction = normalize(focalPoint - ray.origin);
    }
    return ray;
}

static bool tracePrimaryAOV(
    Ray ray,
    constant GPURenderConstants &constants,
    constant GPUTriangle *triangles,
    constant GPUAccelerationNode *nodes,
    constant uint *primitiveIndices,
    constant GPUVolumeDescriptor *volumes,
    constant GPUVolumeSample *volumeSamples,
    constant GPUVolumeAttributeDescriptor *volumeAttributeDescriptors,
    constant float4 *volumeAttributeSamples,
    constant GPUVolumeBrickDescriptor *volumeBricks,
    constant GPUVolumeBrickSample *volumeBrickSamples,
    constant GPUVolumeMaterialFieldSample *volumeBrickMaterialFieldSamples,
    constant GPUVolumeAttributeDescriptor *volumeBrickAttributeDescriptors,
    constant float4 *volumeBrickAttributeSamples,
    constant GPUAccelerationNode *volumeBrickBVHNodes,
    constant uint *volumeBrickBVHIndices,
    constant GPUVolumeBrickGrid *volumeBrickGrids,
    constant uint *volumeBrickGridIndices,
    device atomic_uint *sdfCounters,
    constant GPUMaterial *materials,
    constant GPUTextureDescriptor *textureDescriptors,
    constant float4 *texturePixels,
    thread Hit &primaryHit,
    thread GPUMaterial &primaryMaterial
) {
    for (uint pass = 0; pass < 32u; ++pass) {
        addSDFTraversalCounter(sdfCounters, constants, sdfCounterPrimarySceneQueries);
        Hit hit = intersectScene(
            ray,
            constants,
            triangles,
            nodes,
            primitiveIndices,
            volumes,
            volumeSamples,
            volumeAttributeDescriptors,
            volumeAttributeSamples,
            volumeBricks,
            volumeBrickSamples,
            volumeBrickMaterialFieldSamples,
            volumeBrickAttributeDescriptors,
            volumeBrickAttributeSamples,
            volumeBrickBVHNodes,
            volumeBrickBVHIndices,
            volumeBrickGrids,
            volumeBrickGridIndices,
            sdfCounters
        );
        if (!hit.hit) {
            return false;
        }

        GPUMaterial material = materialForHit(hit, materials, constants.materialCount);
        hit = applyNormalMap(hit, material, textureDescriptors, texturePixels, ray.direction);
        material = applyBaseColorTexture(material, hit, textureDescriptors, texturePixels);
        if (material.baseColor.w <= 0.001f) {
            ray.origin = hit.position + ray.direction * 0.001f;
            continue;
        }

        primaryHit = hit;
        primaryMaterial = material;
        return true;
    }

    return false;
}

static bool tracePrimaryAOVHardware(
    Ray ray,
    acceleration_structure<instancing> scene,
    constant GPURayTracingInstance *rtInstances,
    constant GPUTriangle *localTriangles,
    constant GPUMaterial *materials,
    uint materialCount,
    constant GPUTextureDescriptor *textureDescriptors,
    constant float4 *texturePixels,
    thread Hit &primaryHit,
    thread GPUMaterial &primaryMaterial
) {
    for (uint pass = 0; pass < 32u; ++pass) {
        Hit hit = intersectSceneHardware(ray, scene, localTriangles, rtInstances);
        if (!hit.hit) {
            return false;
        }

        GPUMaterial material = materialForHit(hit, materials, materialCount);
        hit = applyNormalMap(hit, material, textureDescriptors, texturePixels, ray.direction);
        material = applyBaseColorTexture(material, hit, textureDescriptors, texturePixels);
        if (material.baseColor.w <= 0.001f) {
            ray.origin = hit.position + ray.direction * 0.001f;
            continue;
        }

        primaryHit = hit;
        primaryMaterial = material;
        return true;
    }

    return false;
}

static bool shadowOccluded(
    Ray shadowRay,
    float maxDistance,
    constant GPURenderConstants &constants,
    constant GPUTriangle *triangles,
    constant GPUMaterial *materials,
    constant GPUAccelerationNode *nodes,
    constant uint *primitiveIndices,
    constant GPUVolumeDescriptor *volumes,
    constant GPUVolumeSample *volumeSamples,
    constant GPUVolumeAttributeDescriptor *volumeAttributeDescriptors,
    constant float4 *volumeAttributeSamples,
    constant GPUVolumeBrickDescriptor *volumeBricks,
    constant GPUVolumeBrickSample *volumeBrickSamples,
    constant GPUVolumeMaterialFieldSample *volumeBrickMaterialFieldSamples,
    constant GPUVolumeAttributeDescriptor *volumeBrickAttributeDescriptors,
    constant float4 *volumeBrickAttributeSamples,
    constant GPUAccelerationNode *volumeBrickBVHNodes,
    constant uint *volumeBrickBVHIndices,
    constant GPUVolumeBrickGrid *volumeBrickGrids,
    constant uint *volumeBrickGridIndices,
    device atomic_uint *sdfCounters,
    thread float3 &transmittance
) {
    float traveled = 0.0f;
    for (uint step = 0; step < 8u; ++step) {
        addSDFTraversalCounter(sdfCounters, constants, sdfCounterShadowSceneQueries);
        Hit shadowHit = intersectScene(
            shadowRay,
            constants,
            triangles,
            nodes,
            primitiveIndices,
            volumes,
            volumeSamples,
            volumeAttributeDescriptors,
            volumeAttributeSamples,
            volumeBricks,
            volumeBrickSamples,
            volumeBrickMaterialFieldSamples,
            volumeBrickAttributeDescriptors,
            volumeBrickAttributeSamples,
            volumeBrickBVHNodes,
            volumeBrickBVHIndices,
            volumeBrickGrids,
            volumeBrickGridIndices,
            sdfCounters
        );
        if (!shadowHit.hit || traveled + shadowHit.t >= maxDistance) {
            return false;
        }

        GPUMaterial shadowMaterial = materialForHit(shadowHit, materials, constants.materialCount);
        if (shadowMaterial.baseColor.w <= 0.001f) {
            traveled += shadowHit.t;
            shadowRay.origin = shadowHit.position + shadowRay.direction * 0.001f;
            continue;
        }

        float transmission = materialTransmission(shadowMaterial);
        if (transmission <= 0.001f) {
            return true;
        }

        bool insideSolid = !shadowHit.frontFacing && !materialThinWalled(shadowMaterial);
        float3 mediumTransmittance = materialHasVolumeScattering(shadowMaterial) && insideSolid
            ? materialVolumeTransmittance(shadowMaterial, shadowHit.t)
            : materialTransmissionAbsorption(shadowMaterial, shadowHit.t, insideSolid);
        transmittance *= materialTransmissionTint(shadowMaterial, 0.35f) * mediumTransmittance * transmission;
        if (maxComponent(transmittance) < 0.02f) {
            return true;
        }

        traveled += shadowHit.t;
        shadowRay.origin = shadowHit.position + shadowRay.direction * 0.001f;
    }

    return true;
}

static float interactiveContactAmbientOcclusion(
    Hit surfaceHit,
    GPUMaterial surfaceMaterial,
    float3 normal,
    constant GPURenderConstants &constants,
    constant GPUTriangle *triangles,
    constant GPUMaterial *materials,
    constant GPUAccelerationNode *nodes,
    constant uint *primitiveIndices,
    constant GPUVolumeDescriptor *volumes,
    constant GPUVolumeSample *volumeSamples,
    constant GPUVolumeAttributeDescriptor *volumeAttributeDescriptors,
    constant float4 *volumeAttributeSamples,
    constant GPUVolumeBrickDescriptor *volumeBricks,
    constant GPUVolumeBrickSample *volumeBrickSamples,
    constant GPUVolumeMaterialFieldSample *volumeBrickMaterialFieldSamples,
    constant GPUVolumeAttributeDescriptor *volumeBrickAttributeDescriptors,
    constant float4 *volumeBrickAttributeSamples,
    constant GPUAccelerationNode *volumeBrickBVHNodes,
    constant uint *volumeBrickBVHIndices,
    constant GPUVolumeBrickGrid *volumeBrickGrids,
    constant uint *volumeBrickGridIndices,
    device atomic_uint *sdfCounters
) {
    TangentFrame frame = makeTangentFrame(normal, surfaceHit.tangent, surfaceHit.bitangent);
    constexpr uint sampleCount = 4u;
    constexpr float radius = 0.34f;
    constexpr float3 localDirections[sampleCount] = {
        float3(0.000f, 0.000f, 1.000f),
        float3(0.780f, 0.180f, 0.600f),
        float3(-0.420f, 0.720f, 0.552f),
        float3(-0.620f, -0.520f, 0.587f)
    };

    float occlusion = 0.0f;
    for (uint sampleIndex = 0u; sampleIndex < sampleCount; ++sampleIndex) {
        float3 localDirection = normalize(localDirections[sampleIndex]);
        float3 direction = normalize(
            localDirection.x * frame.tangent
                + localDirection.y * frame.bitangent
                + localDirection.z * normal
        );

        Ray ray;
        ray.origin = surfaceHit.position + normal * 0.003f;
        ray.direction = direction;

        addSDFTraversalCounter(sdfCounters, constants, sdfCounterShadowSceneQueries);
        Hit occluder = intersectScene(
            ray,
            constants,
            triangles,
            nodes,
            primitiveIndices,
            volumes,
            volumeSamples,
            volumeAttributeDescriptors,
            volumeAttributeSamples,
            volumeBricks,
            volumeBrickSamples,
            volumeBrickMaterialFieldSamples,
            volumeBrickAttributeDescriptors,
            volumeBrickAttributeSamples,
            volumeBrickBVHNodes,
            volumeBrickBVHIndices,
            volumeBrickGrids,
            volumeBrickGridIndices,
            sdfCounters
        );
        if (!occluder.hit || occluder.t >= radius) {
            continue;
        }

        GPUMaterial occluderMaterial = materialForHit(occluder, materials, constants.materialCount);
        float occluderOpacity = clamp(occluderMaterial.baseColor.w, 0.0f, 1.0f);
        float occluderTransmission = materialTransmission(occluderMaterial);
        float blocker = occluderOpacity * (1.0f - occluderTransmission * 0.72f);
        float proximity = 1.0f - smoothstep(0.0f, radius, occluder.t);
        occlusion += blocker * proximity;
    }

    float transmission = materialTransmission(surfaceMaterial);
    float strength = mix(0.72f, 0.36f, transmission);
    return 1.0f - clamp((occlusion / (float)sampleCount) * strength, 0.0f, 0.72f);
}

static bool shadowOccludedHardware(
    Ray shadowRay,
    float maxDistance,
    constant GPURenderConstants &constants,
    constant GPUMaterial *materials,
    acceleration_structure<instancing> scene,
    constant GPUTriangle *localTriangles,
    constant GPURayTracingInstance *rtInstances,
    thread float3 &transmittance
) {
    float traveled = 0.0f;
    for (uint step = 0; step < 8u; ++step) {
        Hit shadowHit = intersectSceneHardware(shadowRay, scene, localTriangles, rtInstances);
        if (!shadowHit.hit || traveled + shadowHit.t >= maxDistance) {
            return false;
        }

        GPUMaterial shadowMaterial = materialForHit(shadowHit, materials, constants.materialCount);
        if (shadowMaterial.baseColor.w <= 0.001f) {
            traveled += shadowHit.t;
            shadowRay.origin = shadowHit.position + shadowRay.direction * 0.001f;
            continue;
        }

        float transmission = materialTransmission(shadowMaterial);
        if (transmission <= 0.001f) {
            return true;
        }

        bool insideSolid = !shadowHit.frontFacing && !materialThinWalled(shadowMaterial);
        float3 mediumTransmittance = materialHasVolumeScattering(shadowMaterial) && insideSolid
            ? materialVolumeTransmittance(shadowMaterial, shadowHit.t)
            : materialTransmissionAbsorption(shadowMaterial, shadowHit.t, insideSolid);
        transmittance *= materialTransmissionTint(shadowMaterial, 0.35f) * mediumTransmittance * transmission;
        if (maxComponent(transmittance) < 0.02f) {
            return true;
        }

        traveled += shadowHit.t;
        shadowRay.origin = shadowHit.position + shadowRay.direction * 0.001f;
    }

    return true;
}

static float3 sampleDirectLighting(
    Hit hit,
    GPUMaterial surfaceMaterial,
    float3 viewDirection,
    constant GPURenderConstants &constants,
    constant GPUTriangle *triangles,
    constant GPUMaterial *materials,
    constant GPUAccelerationNode *nodes,
    constant uint *primitiveIndices,
    constant GPUVolumeDescriptor *volumes,
    constant GPUVolumeSample *volumeSamples,
    constant GPUVolumeAttributeDescriptor *volumeAttributeDescriptors,
    constant float4 *volumeAttributeSamples,
    constant GPUVolumeBrickDescriptor *volumeBricks,
    constant GPUVolumeBrickSample *volumeBrickSamples,
    constant GPUVolumeMaterialFieldSample *volumeBrickMaterialFieldSamples,
    constant GPUVolumeAttributeDescriptor *volumeBrickAttributeDescriptors,
    constant float4 *volumeBrickAttributeSamples,
    constant GPUAccelerationNode *volumeBrickBVHNodes,
    constant uint *volumeBrickBVHIndices,
    constant GPUVolumeBrickGrid *volumeBrickGrids,
    constant uint *volumeBrickGridIndices,
    device atomic_uint *sdfCounters,
    constant GPULightRecord *lights,
    constant GPUEnvironmentSample *environmentSamples,
    constant GPUTextureDescriptor *textureDescriptors,
    constant float4 *texturePixels,
    thread uint &state
) {
    float3 direct = float3(0);

    if (constants.lightCount > 0u && lights != nullptr) {
        uint index = selectLightIndex(lights, constants.lightCount, randomFloat(state));
        constant GPULightRecord &light = lights[index];
        float selectionPDF = lightSelectionPDF(lights, index);
        uint lightTriangleIndex = light.triangleIndex;
        if (lightTriangleIndex < constants.triangleCount && selectionPDF > 0.0f) {
            constant GPUTriangle &lightTriangle = triangles[lightTriangleIndex];
            GPUMaterial lightMaterial = materials[min(light.materialIndex, constants.materialCount - 1u)];
            float3 emission = lightMaterial.emission.xyz;

            float area = light.area;
            if (area > 0.0f) {
                float3 lightPoint = sampleTriangle(lightTriangle, float2(randomFloat(state), randomFloat(state)));
                float3 toLight = lightPoint - hit.position;
                float distanceSquared = dot(toLight, toLight);
                float distanceToLight = sqrt(distanceSquared);
                float3 lightDirection = toLight / distanceToLight;
                float cosSurface = max(0.0f, dot(hit.normal, lightDirection));
                float3 lightNormal = light.normal.xyz;
                float cosLight = max(0.0f, dot(lightNormal, -lightDirection));

                if (cosSurface > 0.0f && cosLight > 0.0f) {
                    float lightPDF = selectionPDF * lightSolidAnglePDF(distanceSquared, cosLight, area);
                    float bsdfPDF = materialBSDFPDF(
                        surfaceMaterial,
                        hit.normal,
                        hit.tangent,
                        hit.bitangent,
                        viewDirection,
                        lightDirection
                    );
                    float misWeight = powerHeuristic(lightPDF, bsdfPDF);

                    Ray shadowRay;
                    shadowRay.origin = hit.position + hit.normal * 0.001f;
                    shadowRay.direction = lightDirection;
                    float3 shadowTransmittance = float3(1.0f);

                    if (!shadowOccluded(
                        shadowRay,
                        distanceToLight - 0.002f,
                        constants,
                        triangles,
                        materials,                        nodes,
                        primitiveIndices,
                        volumes,
                        volumeSamples,
                        volumeAttributeDescriptors,
                        volumeAttributeSamples,
                        volumeBricks,
                        volumeBrickSamples,
                        volumeBrickMaterialFieldSamples,
                        volumeBrickAttributeDescriptors,
                        volumeBrickAttributeSamples,
                        volumeBrickBVHNodes,
                        volumeBrickBVHIndices,
                        volumeBrickGrids,
                        volumeBrickGridIndices,
                        sdfCounters,
                        shadowTransmittance
                    )) {
                        float geometryTerm = cosSurface * cosLight * area / max(distanceSquared, 1e-6f);
                        float3 brdf = evaluateMaterialBRDF(
                            surfaceMaterial,
                            hit.normal,
                            hit.tangent,
                            hit.bitangent,
                            viewDirection,
                            lightDirection
                        );
                        direct += brdf * emission * geometryTerm * misWeight * shadowTransmittance / selectionPDF;
                    }
                }
            }
        }
    }

    constexpr uint environmentDirectSampleCount = 2u;
    for (uint environmentSampleIndex = 0u; environmentSampleIndex < environmentDirectSampleCount; ++environmentSampleIndex) {
        float environmentLightPDF;
        float3 environmentDirection = sampleEnvironmentDirection(
            float2(randomFloat(state), randomFloat(state)),
            randomFloat(state),
            constants,
            textureDescriptors,
            environmentSamples,
            environmentLightPDF
        );
        float environmentCosSurface = max(0.0f, dot(hit.normal, environmentDirection));
        if (environmentLightPDF > 0.0f && environmentCosSurface > 0.0f) {
            float bsdfPDF = materialBSDFPDF(
                surfaceMaterial,
                hit.normal,
                hit.tangent,
                hit.bitangent,
                viewDirection,
                environmentDirection
            );
            float misWeight = powerHeuristic(environmentLightPDF, bsdfPDF);
            Ray shadowRay;
            shadowRay.origin = hit.position + hit.normal * 0.001f;
            shadowRay.direction = environmentDirection;
            float3 shadowTransmittance = float3(1.0f);
            if (!shadowOccluded(
                shadowRay,
                1.0e20f,
                constants,
                triangles,
                materials,                nodes,
                primitiveIndices,
                volumes,
                volumeSamples,
                volumeAttributeDescriptors,
                volumeAttributeSamples,
                volumeBricks,
                volumeBrickSamples,
                volumeBrickMaterialFieldSamples,
                volumeBrickAttributeDescriptors,
                volumeBrickAttributeSamples,
                volumeBrickBVHNodes,
                volumeBrickBVHIndices,
                volumeBrickGrids,
                volumeBrickGridIndices,
                sdfCounters,
                shadowTransmittance
            )) {
                float3 brdf = evaluateMaterialBRDF(
                    surfaceMaterial,
                    hit.normal,
                    hit.tangent,
                    hit.bitangent,
                    viewDirection,
                    environmentDirection
                );
                float3 environmentRadiance = sampleEnvironment(
                    environmentDirection,
                    constants,
                    textureDescriptors,
                    texturePixels
                );
                direct += brdf * environmentRadiance * environmentCosSurface * misWeight
                    * shadowTransmittance / (environmentLightPDF * (float)environmentDirectSampleCount);
            }
        }
    }

    return direct;
}

static float3 sampleDirectLightingHardware(
    Hit hit,
    GPUMaterial surfaceMaterial,
    float3 viewDirection,
    constant GPURenderConstants &constants,
    constant GPUTriangle *triangles,
    constant GPUMaterial *materials,
    acceleration_structure<instancing> scene,
    constant GPUTriangle *localTriangles,
    constant GPURayTracingInstance *rtInstances,
    constant GPULightRecord *lights,
    constant GPUEnvironmentSample *environmentSamples,
    constant GPUTextureDescriptor *textureDescriptors,
    constant float4 *texturePixels,
    thread uint &state
) {
    float3 direct = float3(0);

    if (constants.lightCount > 0u && lights != nullptr) {
        uint index = selectLightIndex(lights, constants.lightCount, randomFloat(state));
        constant GPULightRecord &light = lights[index];
        float selectionPDF = lightSelectionPDF(lights, index);
        uint lightTriangleIndex = light.triangleIndex;
        if (lightTriangleIndex < constants.triangleCount && selectionPDF > 0.0f) {
            constant GPUTriangle &lightTriangle = triangles[lightTriangleIndex];
            GPUMaterial lightMaterial = materials[min(light.materialIndex, constants.materialCount - 1u)];
            float3 emission = lightMaterial.emission.xyz;

            float area = light.area;
            if (area > 0.0f) {
                float3 lightPoint = sampleTriangle(lightTriangle, float2(randomFloat(state), randomFloat(state)));
                float3 toLight = lightPoint - hit.position;
                float distanceSquared = dot(toLight, toLight);
                float distanceToLight = sqrt(distanceSquared);
                float3 lightDirection = toLight / distanceToLight;
                float cosSurface = max(0.0f, dot(hit.normal, lightDirection));
                float3 lightNormal = light.normal.xyz;
                float cosLight = max(0.0f, dot(lightNormal, -lightDirection));

                if (cosSurface > 0.0f && cosLight > 0.0f) {
                    float lightPDF = selectionPDF * lightSolidAnglePDF(distanceSquared, cosLight, area);
                    float bsdfPDF = materialBSDFPDF(
                        surfaceMaterial,
                        hit.normal,
                        hit.tangent,
                        hit.bitangent,
                        viewDirection,
                        lightDirection
                    );
                    float misWeight = powerHeuristic(lightPDF, bsdfPDF);

                    Ray shadowRay;
                    shadowRay.origin = hit.position + hit.normal * 0.001f;
                    shadowRay.direction = lightDirection;
                    float3 shadowTransmittance = float3(1.0f);

                    if (!shadowOccludedHardware(
                        shadowRay,
                        distanceToLight - 0.002f,
                        constants,
                        materials,
                        scene,
                        localTriangles,
                        rtInstances,
                        shadowTransmittance
                    )) {
                        float geometryTerm = cosSurface * cosLight * area / max(distanceSquared, 1e-6f);
                        float3 brdf = evaluateMaterialBRDF(
                            surfaceMaterial,
                            hit.normal,
                            hit.tangent,
                            hit.bitangent,
                            viewDirection,
                            lightDirection
                        );
                        direct += brdf * emission * geometryTerm * misWeight * shadowTransmittance / selectionPDF;
                    }
                }
            }
        }
    }

    constexpr uint environmentDirectSampleCount = 2u;
    for (uint environmentSampleIndex = 0u; environmentSampleIndex < environmentDirectSampleCount; ++environmentSampleIndex) {
        float environmentLightPDF;
        float3 environmentDirection = sampleEnvironmentDirection(
            float2(randomFloat(state), randomFloat(state)),
            randomFloat(state),
            constants,
            textureDescriptors,
            environmentSamples,
            environmentLightPDF
        );
        float environmentCosSurface = max(0.0f, dot(hit.normal, environmentDirection));
        if (environmentLightPDF > 0.0f && environmentCosSurface > 0.0f) {
            float bsdfPDF = materialBSDFPDF(
                surfaceMaterial,
                hit.normal,
                hit.tangent,
                hit.bitangent,
                viewDirection,
                environmentDirection
            );
            float misWeight = powerHeuristic(environmentLightPDF, bsdfPDF);
            Ray shadowRay;
            shadowRay.origin = hit.position + hit.normal * 0.001f;
            shadowRay.direction = environmentDirection;
            float3 shadowTransmittance = float3(1.0f);
            if (!shadowOccludedHardware(
                shadowRay,
                1.0e20f,
                constants,
                materials,
                scene,
                localTriangles,
                rtInstances,
                shadowTransmittance
            )) {
                float3 brdf = evaluateMaterialBRDF(
                    surfaceMaterial,
                    hit.normal,
                    hit.tangent,
                    hit.bitangent,
                    viewDirection,
                    environmentDirection
                );
                float3 environmentRadiance = sampleEnvironment(
                    environmentDirection,
                    constants,
                    textureDescriptors,
                    texturePixels
                );
                direct += brdf * environmentRadiance * environmentCosSurface * misWeight
                    * shadowTransmittance / (environmentLightPDF * (float)environmentDirectSampleCount);
            }
        }
    }

    return direct;
}

kernel void flatPreviewKernel(
    texture2d<float, access::read_write> accumulation [[texture(0)]],
    texture2d<float, access::write> depthOutput [[texture(1)]],
    texture2d<float, access::write> normalOutput [[texture(2)]],
    texture2d<float, access::write> albedoOutput [[texture(3)]],
    texture2d<float, access::write> materialIDOutput [[texture(4)]],
    texture2d<float, access::write> objectIDOutput [[texture(5)]],
    texture2d<float, access::write> motionVectorOutput [[texture(6)]],
    constant GPURenderConstants &constants [[buffer(0)]],
    constant GPUCamera &camera [[buffer(1)]],
    constant GPUTriangle *triangles [[buffer(2)]],
    constant GPUMaterial *materials [[buffer(3)]],
    constant GPUAccelerationNode *nodes [[buffer(4)]],
    constant uint *primitiveIndices [[buffer(5)]],
    constant GPUCamera &previousCamera [[buffer(6)]],
    constant GPUTextureDescriptor *textureDescriptors [[buffer(10)]],
    constant float4 *texturePixels [[buffer(11)]],
    constant GPULightRecord *lights [[buffer(12)]],
    constant GPUEnvironmentSample *environmentSamples [[buffer(13)]],
    constant GPUVolumeDescriptor *volumes [[buffer(14)]],
    constant GPUVolumeSample *volumeSamples [[buffer(15)]],
    constant GPUVolumeBrickDescriptor *volumeBricks [[buffer(16)]],
    constant GPUVolumeBrickSample *volumeBrickSamples [[buffer(17)]],
    constant GPUVolumeAttributeDescriptor *volumeAttributeDescriptors [[buffer(18)]],
    constant float4 *volumeAttributeSamples [[buffer(19)]],
    constant GPUVolumeAttributeDescriptor *volumeBrickAttributeDescriptors [[buffer(20)]],
    constant float4 *volumeBrickAttributeSamples [[buffer(21)]],
    constant GPUAccelerationNode *volumeBrickBVHNodes [[buffer(22)]],
    constant uint *volumeBrickBVHIndices [[buffer(23)]],
    constant GPUVolumeBrickGrid *volumeBrickGrids [[buffer(24)]],
    constant uint *volumeBrickGridIndices [[buffer(25)]],
    constant GPUVolumeMaterialFieldSample *volumeBrickMaterialFieldSamples [[buffer(26)]],
    device atomic_uint *sdfCounters [[buffer(27)]],
    constant GPUMaterialProgramDescriptor *materialProgramDescriptors [[buffer(28)]],
    constant GPUMaterialProgramOperation *materialProgramOperations [[buffer(29)]],
    uint2 gid [[thread_position_in_grid]]
) {
    (void)lights;
    (void)environmentSamples;

    if (gid.x >= constants.tileWidth || gid.y >= constants.tileHeight) {
        return;
    }
    uint2 pixel = gid + uint2(constants.tileX, constants.tileY);
    if (pixel.x >= constants.width || pixel.y >= constants.height) {
        return;
    }

    Ray ray = makeCameraRay(
        camera,
        constants.width,
        constants.height,
        pixel,
        0.5f,
        0.5f,
        0.0f,
        0.0f
    );

    addSDFTraversalCounter(sdfCounters, constants, sdfCounterPrimarySceneQueries);
    Hit hit = intersectScene(
        ray,
        constants,
        triangles,
        nodes,
        primitiveIndices,
        volumes,
        volumeSamples,
        volumeAttributeDescriptors,
        volumeAttributeSamples,
        volumeBricks,
        volumeBrickSamples,
        volumeBrickMaterialFieldSamples,
        volumeBrickAttributeDescriptors,
        volumeBrickAttributeSamples,
        volumeBrickBVHNodes,
        volumeBrickBVHIndices,
        volumeBrickGrids,
        volumeBrickGridIndices,
        sdfCounters
    );

    if (!hit.hit) {
        float alpha = constants.transparentBackground != 0u ? 0.0f : 1.0f;
        float3 color = max(constants.backgroundColor.xyz, float3(0.0f));
        if (constants.transparentBackground == 0u && constants.showsEnvironmentBackground != 0u) {
            color = sampleEnvironment(ray.direction, constants, textureDescriptors, texturePixels);
        }
        accumulation.write(float4(color, alpha), pixel);
        depthOutput.write(float4(0.0f), pixel);
        normalOutput.write(float4(0.5f, 0.5f, 0.5f, 0.0f), pixel);
        albedoOutput.write(float4(0.0f), pixel);
        materialIDOutput.write(float4(0.0f), pixel);
        objectIDOutput.write(float4(0.0f), pixel);
        motionVectorOutput.write(float4(0.0f), pixel);
        return;
    }

    GPUMaterial material = materialForHit(
        hit,
        materials,
        constants.materialCount,
        materialProgramDescriptors,
        materialProgramOperations,
        constants.materialProgramCount,
        constants.materialProgramOperationCount
    );
    hit = applyNormalMap(hit, material, textureDescriptors, texturePixels, ray.direction);
    material = applyBaseColorTexture(material, hit, textureDescriptors, texturePixels);

    float3 normal = normalize(hit.normal);
    float3 viewDirection = normalize(-ray.direction);
    float3 keyDirection = normalize(float3(0.35f, 0.72f, 0.58f));
    float lambert = max(dot(normal, keyDirection), 0.0f);
    float facing = max(dot(normal, viewDirection), 0.0f);
    float rim = pow(1.0f - facing, 2.0f) * 0.08f;
    float shade = 0.32f + 0.68f * lambert + rim;
    float3 color = max(material.baseColor.xyz, float3(0.0f)) * shade + max(material.emission.xyz, float3(0.0f));
    float alpha = constants.transparentBackground != 0u ? clamp(material.baseColor.w, 0.0f, 1.0f) : 1.0f;

    accumulation.write(float4(color, alpha), pixel);

    float3 encodedNormal = normal * 0.5f + 0.5f;
    depthOutput.write(float4(hit.t, hit.t, hit.t, 1.0f), pixel);
    normalOutput.write(float4(encodedNormal, 1.0f), pixel);
    albedoOutput.write(float4(material.baseColor.xyz, material.baseColor.w), pixel);
    float materialID = (float)(hit.materialID + 1u);
    float objectID = (float)(hit.objectID + 1u);
    materialIDOutput.write(float4(materialID, materialID, materialID, 1.0f), pixel);
    objectIDOutput.write(float4(objectID, objectID, objectID, 1.0f), pixel);

    float2 currentScreen;
    float2 previousScreen;
    if (projectToScreen(camera, hit.position, constants.width, constants.height, currentScreen)
        && projectToScreen(previousCamera, hit.position, constants.width, constants.height, previousScreen)) {
        float2 motion = previousScreen - currentScreen;
        motionVectorOutput.write(float4(motion.x, motion.y, 0.0f, 1.0f), pixel);
    } else {
        motionVectorOutput.write(float4(0.0f), pixel);
    }
}

kernel void interactiveMaterialKernel(
    texture2d<float, access::read_write> accumulation [[texture(0)]],
    texture2d<float, access::write> depthOutput [[texture(1)]],
    texture2d<float, access::write> normalOutput [[texture(2)]],
    texture2d<float, access::write> albedoOutput [[texture(3)]],
    texture2d<float, access::write> materialIDOutput [[texture(4)]],
    texture2d<float, access::write> objectIDOutput [[texture(5)]],
    texture2d<float, access::write> motionVectorOutput [[texture(6)]],
    constant GPURenderConstants &constants [[buffer(0)]],
    constant GPUCamera &camera [[buffer(1)]],
    constant GPUTriangle *triangles [[buffer(2)]],
    constant GPUMaterial *materials [[buffer(3)]],
    constant GPUAccelerationNode *nodes [[buffer(4)]],
    constant uint *primitiveIndices [[buffer(5)]],
    constant GPUCamera &previousCamera [[buffer(6)]],
    constant GPUTextureDescriptor *textureDescriptors [[buffer(10)]],
    constant float4 *texturePixels [[buffer(11)]],
    constant GPULightRecord *lights [[buffer(12)]],
    constant GPUEnvironmentSample *environmentSamples [[buffer(13)]],
    constant GPUVolumeDescriptor *volumes [[buffer(14)]],
    constant GPUVolumeSample *volumeSamples [[buffer(15)]],
    constant GPUVolumeBrickDescriptor *volumeBricks [[buffer(16)]],
    constant GPUVolumeBrickSample *volumeBrickSamples [[buffer(17)]],
    constant GPUVolumeAttributeDescriptor *volumeAttributeDescriptors [[buffer(18)]],
    constant float4 *volumeAttributeSamples [[buffer(19)]],
    constant GPUVolumeAttributeDescriptor *volumeBrickAttributeDescriptors [[buffer(20)]],
    constant float4 *volumeBrickAttributeSamples [[buffer(21)]],
    constant GPUAccelerationNode *volumeBrickBVHNodes [[buffer(22)]],
    constant uint *volumeBrickBVHIndices [[buffer(23)]],
    constant GPUVolumeBrickGrid *volumeBrickGrids [[buffer(24)]],
    constant uint *volumeBrickGridIndices [[buffer(25)]],
    constant GPUVolumeMaterialFieldSample *volumeBrickMaterialFieldSamples [[buffer(26)]],
    device atomic_uint *sdfCounters [[buffer(27)]],
    constant GPUMaterialProgramDescriptor *materialProgramDescriptors [[buffer(28)]],
    constant GPUMaterialProgramOperation *materialProgramOperations [[buffer(29)]],
    uint2 gid [[thread_position_in_grid]]
) {
    (void)environmentSamples;

    if (gid.x >= constants.tileWidth || gid.y >= constants.tileHeight) {
        return;
    }
    uint2 pixel = gid + uint2(constants.tileX, constants.tileY);
    if (pixel.x >= constants.width || pixel.y >= constants.height) {
        return;
    }

    Ray ray = makeCameraRay(
        camera,
        constants.width,
        constants.height,
        pixel,
        0.5f,
        0.5f,
        0.0f,
        0.0f
    );

    addSDFTraversalCounter(sdfCounters, constants, sdfCounterPrimarySceneQueries);
    Hit hit = intersectScene(
        ray,
        constants,
        triangles,
        nodes,
        primitiveIndices,
        volumes,
        volumeSamples,
        volumeAttributeDescriptors,
        volumeAttributeSamples,
        volumeBricks,
        volumeBrickSamples,
        volumeBrickMaterialFieldSamples,
        volumeBrickAttributeDescriptors,
        volumeBrickAttributeSamples,
        volumeBrickBVHNodes,
        volumeBrickBVHIndices,
        volumeBrickGrids,
        volumeBrickGridIndices,
        sdfCounters
    );

    if (!hit.hit) {
        float alpha = constants.transparentBackground != 0u ? 0.0f : 1.0f;
        float3 color = max(constants.backgroundColor.xyz, float3(0.0f));
        if (constants.transparentBackground == 0u && constants.showsEnvironmentBackground != 0u) {
            color = sampleEnvironment(ray.direction, constants, textureDescriptors, texturePixels);
        }
        accumulation.write(float4(color, alpha), pixel);
        depthOutput.write(float4(0.0f), pixel);
        normalOutput.write(float4(0.5f, 0.5f, 0.5f, 0.0f), pixel);
        albedoOutput.write(float4(0.0f), pixel);
        materialIDOutput.write(float4(0.0f), pixel);
        objectIDOutput.write(float4(0.0f), pixel);
        motionVectorOutput.write(float4(0.0f), pixel);
        return;
    }

    GPUMaterial material = materialForHit(
        hit,
        materials,
        constants.materialCount,
        materialProgramDescriptors,
        materialProgramOperations,
        constants.materialProgramCount,
        constants.materialProgramOperationCount
    );
    hit = applyNormalMap(hit, material, textureDescriptors, texturePixels, ray.direction);
    material = applyBaseColorTexture(material, hit, textureDescriptors, texturePixels);

    float3 normal = normalize(hit.normal);
    float3 viewDirection = normalize(-ray.direction);
    float roughness = clamp(material.parameters.x, 0.02f, 1.0f);
    float metallic = clamp(material.parameters.y, 0.0f, 1.0f);
    float opacity = clamp(material.baseColor.w, 0.0f, 1.0f);
    float3 baseColor = max(material.baseColor.xyz, float3(0.0f));
    float3 color = max(material.emission.xyz, float3(0.0f));

    uint interactiveLightCount = min(constants.lightCount, 12u);
    for (uint lightIndex = 0u; lightIndex < interactiveLightCount; ++lightIndex) {
        constant GPULightRecord &light = lights[lightIndex];
        if (light.triangleIndex >= constants.triangleCount || light.materialIndex >= constants.materialCount) {
            continue;
        }

        constant GPUTriangle &lightTriangle = triangles[light.triangleIndex];
        GPUMaterial lightMaterial = materials[light.materialIndex];
        float3 emission = max(lightMaterial.emission.xyz, float3(0.0f));
        if (maxComponent(emission) <= 0.0f || light.area <= 0.0f) {
            continue;
        }

        float3 lightPoint = (lightTriangle.v0.xyz + lightTriangle.v1.xyz + lightTriangle.v2.xyz) / 3.0f;
        float3 toLight = lightPoint - hit.position;
        float distanceSquared = max(dot(toLight, toLight), 1e-5f);
        float distanceToLight = sqrt(distanceSquared);
        float3 lightDirection = toLight / distanceToLight;
        float cosSurface = max(dot(normal, lightDirection), 0.0f);
        float cosLight = max(dot(light.normal.xyz, -lightDirection), 0.0f);
        if (cosSurface <= 0.0f || cosLight <= 0.0f) {
            continue;
        }

        Ray shadowRay;
        shadowRay.origin = hit.position + normal * 0.001f;
        shadowRay.direction = lightDirection;
        float3 shadowTransmittance = float3(1.0f);
        if (shadowOccluded(
            shadowRay,
            distanceToLight - 0.002f,
            constants,
            triangles,
            materials,            nodes,
            primitiveIndices,
            volumes,
            volumeSamples,
            volumeAttributeDescriptors,
            volumeAttributeSamples,
            volumeBricks,
            volumeBrickSamples,
            volumeBrickMaterialFieldSamples,
            volumeBrickAttributeDescriptors,
            volumeBrickAttributeSamples,
            volumeBrickBVHNodes,
            volumeBrickBVHIndices,
            volumeBrickGrids,
            volumeBrickGridIndices,
            sdfCounters,
            shadowTransmittance
        )) {
            continue;
        }

        float3 brdf = evaluateMaterialBRDF(
            material,
            normal,
            hit.tangent,
            hit.bitangent,
            viewDirection,
            lightDirection
        );
        float clearcoatGloss = materialClearcoat(material) * pow(1.0f - materialClearcoatRoughness(material), 2.0f);
        float directGlossWeight = clamp(
            metallic
                + clearcoatGloss
                + (1.0f - metallic) * pow(1.0f - roughness, 4.0f) * clamp(material.parameters2.x, 0.0f, 1.0f),
            0.0f,
            1.0f
        );
        float3 directF0 = materialF0(material);
        float3 diffuseOnly = (1.0f - metallic)
            * baseColor
            * max(float3(0.0f), float3(1.0f) - directF0)
            * 0.31830988618f;
        brdf = mix(diffuseOnly, brdf, directGlossWeight);
        float geometryTerm = cosSurface * cosLight * light.area / distanceSquared;
        color += brdf * emission * geometryTerm * shadowTransmittance;
    }

    float3 environmentDiffuse = sampleInteractiveDiffuseEnvironment(normal, constants, textureDescriptors, texturePixels);
    float3 reflectionDirection = normalize(reflect(-viewDirection, normal));
    float3 baseEnvironmentReflection = sampleInteractiveSpecularEnvironment(
        reflectionDirection,
        normal,
        roughness,
        constants,
        textureDescriptors,
        texturePixels
    );
    float clearcoatRoughness = materialClearcoatRoughness(material);
    float3 clearcoatEnvironmentReflection = sampleInteractiveSpecularEnvironment(
        reflectionDirection,
        normal,
        clearcoatRoughness,
        constants,
        textureDescriptors,
        texturePixels
    );
    float nDotV = max(dot(normal, viewDirection), 0.0f);
    float3 fresnel = fresnelSchlickThinFilm(nDotV, materialF0(material), material);
    float glossyWeight = pow(1.0f - roughness, 4.0f);
    float metalReflectionWeight = metallic * pow(1.0f - roughness, 2.0f);
    float clearcoatReflectionWeight = materialClearcoat(material) * pow(1.0f - clearcoatRoughness, 3.0f);
    float dielectricReflectionWeight = (1.0f - metallic) * glossyWeight * clamp(material.parameters2.x, 0.0f, 1.0f);
    float3 roughFresnel = mix(fresnel, materialF0(material), smoothstep(0.45f, 0.95f, roughness));
    float3 clearcoatFresnel = fresnelSchlickThinFilm(nDotV, materialClearcoatF0Color(material), material);
    float horizonOcclusion = 0.58f + 0.42f * clamp(normal.y * 0.5f + 0.5f, 0.0f, 1.0f);
    float contactOcclusion = interactiveContactAmbientOcclusion(
        hit,
        material,
        normal,
        constants,
        triangles,
        materials,        nodes,
        primitiveIndices,
        volumes,
        volumeSamples,
        volumeAttributeDescriptors,
        volumeAttributeSamples,
        volumeBricks,
        volumeBrickSamples,
        volumeBrickMaterialFieldSamples,
        volumeBrickAttributeDescriptors,
        volumeBrickAttributeSamples,
        volumeBrickBVHNodes,
        volumeBrickBVHIndices,
        volumeBrickGrids,
        volumeBrickGridIndices,
        sdfCounters
    );
    float ambientOcclusion = horizonOcclusion * contactOcclusion;
    float diffuseStrength = 0.58f * (1.0f - metallic) * ambientOcclusion;
    float baseReflectionStrength = metalReflectionWeight * 1.05f + dielectricReflectionWeight * 0.32f;
    color += baseColor * environmentDiffuse * diffuseStrength;
    color += baseEnvironmentReflection * roughFresnel * baseReflectionStrength;
    color += clearcoatEnvironmentReflection * clearcoatFresnel * clearcoatReflectionWeight * 0.42f;

    float3 keyDirection = normalize(float3(-0.32f, 0.78f, 0.52f));
    float keyAmount = max(dot(normal, keyDirection), 0.0f);
    color += baseColor * (1.0f - metallic) * keyAmount * 0.16f * contactOcclusion;

    float subsurface = materialSubsurface(material);
    if (subsurface > 0.0f) {
        float wrap = pow(1.0f - nDotV, 2.0f);
        color += materialSubsurfaceColor(material) * baseColor * environmentDiffuse * subsurface * (0.12f + 0.22f * wrap) * contactOcclusion;
    }

    float transmission = materialTransmission(material);
    if (transmission > 0.0f) {
        float3 transmitted = sampleEnvironment(ray.direction, constants, textureDescriptors, texturePixels);
        color = mix(color, transmitted * materialTransmissionTint(material, 0.65f), transmission * 0.55f);
        color += baseEnvironmentReflection * fresnel * transmission * 0.35f;
    }

    color = clamp(color, float3(0.0f), float3(max(constants.sampleRadianceClamp, 1.0f)));
    float alpha = constants.transparentBackground != 0u ? opacity : 1.0f;
    accumulation.write(float4(color, alpha), pixel);

    float3 encodedNormal = normal * 0.5f + 0.5f;
    depthOutput.write(float4(hit.t, hit.t, hit.t, 1.0f), pixel);
    normalOutput.write(float4(encodedNormal, 1.0f), pixel);
    albedoOutput.write(float4(baseColor, opacity), pixel);
    float materialID = (float)(hit.materialID + 1u);
    float objectID = (float)(hit.objectID + 1u);
    materialIDOutput.write(float4(materialID, materialID, materialID, 1.0f), pixel);
    objectIDOutput.write(float4(objectID, objectID, objectID, 1.0f), pixel);

    float2 currentScreen;
    float2 previousScreen;
    if (projectToScreen(camera, hit.position, constants.width, constants.height, currentScreen)
        && projectToScreen(previousCamera, hit.position, constants.width, constants.height, previousScreen)) {
        float2 motion = previousScreen - currentScreen;
        motionVectorOutput.write(float4(motion.x, motion.y, 0.0f, 1.0f), pixel);
    } else {
        motionVectorOutput.write(float4(0.0f), pixel);
    }
}

kernel void pathTraceKernel(
    texture2d<float, access::read_write> accumulation [[texture(0)]],
    texture2d<float, access::write> depthOutput [[texture(1)]],
    texture2d<float, access::write> normalOutput [[texture(2)]],
    texture2d<float, access::write> albedoOutput [[texture(3)]],
    texture2d<float, access::write> materialIDOutput [[texture(4)]],
    texture2d<float, access::write> objectIDOutput [[texture(5)]],
    texture2d<float, access::write> motionVectorOutput [[texture(6)]],
    constant GPURenderConstants &constants [[buffer(0)]],
    constant GPUCamera &camera [[buffer(1)]],
    constant GPUTriangle *triangles [[buffer(2)]],
    constant GPUMaterial *materials [[buffer(3)]],
    constant GPUAccelerationNode *nodes [[buffer(4)]],
    constant uint *primitiveIndices [[buffer(5)]],
    constant GPUCamera &previousCamera [[buffer(6)]],
    constant GPUTextureDescriptor *textureDescriptors [[buffer(10)]],
    constant float4 *texturePixels [[buffer(11)]],
    constant GPULightRecord *lights [[buffer(12)]],
    constant GPUEnvironmentSample *environmentSamples [[buffer(13)]],
    constant GPUVolumeDescriptor *volumes [[buffer(14)]],
    constant GPUVolumeSample *volumeSamples [[buffer(15)]],
    constant GPUVolumeBrickDescriptor *volumeBricks [[buffer(16)]],
    constant GPUVolumeBrickSample *volumeBrickSamples [[buffer(17)]],
    constant GPUVolumeAttributeDescriptor *volumeAttributeDescriptors [[buffer(18)]],
    constant float4 *volumeAttributeSamples [[buffer(19)]],
    constant GPUVolumeAttributeDescriptor *volumeBrickAttributeDescriptors [[buffer(20)]],
    constant float4 *volumeBrickAttributeSamples [[buffer(21)]],
    constant GPUAccelerationNode *volumeBrickBVHNodes [[buffer(22)]],
    constant uint *volumeBrickBVHIndices [[buffer(23)]],
    constant GPUVolumeBrickGrid *volumeBrickGrids [[buffer(24)]],
    constant uint *volumeBrickGridIndices [[buffer(25)]],
    constant GPUVolumeMaterialFieldSample *volumeBrickMaterialFieldSamples [[buffer(26)]],
    device atomic_uint *sdfCounters [[buffer(27)]],
    constant GPUMaterialProgramDescriptor *materialProgramDescriptors [[buffer(28)]],
    constant GPUMaterialProgramOperation *materialProgramOperations [[buffer(29)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= constants.tileWidth || gid.y >= constants.tileHeight) {
        return;
    }
    uint2 pixel = gid + uint2(constants.tileX, constants.tileY);
    if (pixel.x >= constants.width || pixel.y >= constants.height) {
        return;
    }

    uint state = constants.frameSeed
        ^ hash(pixel.x + pixel.y * constants.width)
        ^ hash(constants.sampleIndex + 1u);

    Ray ray = makeCameraRay(
        camera,
        constants.width,
        constants.height,
        pixel,
        randomFloat(state),
        randomFloat(state),
        randomFloat(state),
        randomFloat(state)
    );

    float3 radiance = float3(0);
    float3 throughput = float3(1);
    float outputAlpha = 1.0f;
    float previousBSDFPDF = 0.0f;

    Hit primaryHit = emptyHit();
    GPUMaterial primaryMaterial;
    primaryMaterial.baseColor = float4(0);
    primaryMaterial.emission = float4(0);
    primaryMaterial.parameters = float4(0);
    primaryMaterial.parameters2 = float4(0);
    primaryMaterial.specularColor = float4(0);
    primaryMaterial.sheenColor = float4(0);
    primaryMaterial.transmissionColor = float4(0);
    primaryMaterial.parameters3 = float4(0);
    primaryMaterial.clearcoatColor = float4(0);
    primaryMaterial.clearcoatAttenuation = float4(0);
    primaryMaterial.transmissionAbsorption = float4(0);
    primaryMaterial.thinFilm = float4(0);
    primaryMaterial.subsurfaceColor = float4(0);
    primaryMaterial.subsurfaceRadius = float4(0);
    primaryMaterial.subsurfaceParameters = float4(0);
    primaryMaterial.volumeScattering = float4(0);
    primaryMaterial.volumeParameters = float4(0);

    for (uint bounce = 0; bounce < constants.maxBounces; ++bounce) {
        addSDFTraversalCounter(
            sdfCounters,
            constants,
            bounce == 0u ? sdfCounterPrimarySceneQueries : sdfCounterBounceSceneQueries
        );
        Hit hit = intersectScene(
            ray,
            constants,
            triangles,
            nodes,
            primitiveIndices,
            volumes,
            volumeSamples,
            volumeAttributeDescriptors,
            volumeAttributeSamples,
            volumeBricks,
            volumeBrickSamples,
            volumeBrickMaterialFieldSamples,
            volumeBrickAttributeDescriptors,
            volumeBrickAttributeSamples,
            volumeBrickBVHNodes,
            volumeBrickBVHIndices,
            volumeBrickGrids,
            volumeBrickGridIndices,
            sdfCounters
        );
        if (!hit.hit) {
            if (constants.transparentBackground != 0u && !primaryHit.hit) {
                outputAlpha = 0.0f;
            } else if (constants.showsEnvironmentBackground == 0u && !primaryHit.hit) {
                outputAlpha = 1.0f;
                radiance += max(constants.backgroundColor.xyz, float3(0.0f));
            } else {
                float environmentWeight = 1.0f;
                if (bounce > 0u && previousBSDFPDF > 0.0f) {
                    float environmentLightPDF = environmentPDF(
                        ray.direction,
                        constants,
                        textureDescriptors,
                        environmentSamples
                    );
                    environmentWeight = powerHeuristic(previousBSDFPDF, environmentLightPDF);
                }
                float3 environmentContribution = throughput * sampleEnvironment(
                    ray.direction,
                    constants,
                    textureDescriptors,
                    texturePixels
                ) * environmentWeight;
                radiance += clampSampleContribution(environmentContribution, constants);
            }
            break;
        }

        GPUMaterial material = materialForHit(
            hit,
            materials,
            constants.materialCount,
            materialProgramDescriptors,
            materialProgramOperations,
            constants.materialProgramCount,
            constants.materialProgramOperationCount
        );
        hit = applyNormalMap(hit, material, textureDescriptors, texturePixels, ray.direction);
        material = applyBaseColorTexture(material, hit, textureDescriptors, texturePixels);
        if (material.baseColor.w <= 0.001f) {
            ray.origin = hit.position + ray.direction * 0.001f;
            continue;
        }
        if (!primaryHit.hit) {
            primaryHit = hit;
            primaryMaterial = material;
        }

        if (continueTransmissionVolumeRandomWalk(hit, material, ray, throughput, previousBSDFPDF, state)) {
            if (terminatePathWithRussianRoulette(bounce, throughput, state)) {
                break;
            }
            continue;
        }

        float subsurface = materialSubsurface(material);
        if (subsurface > 0.0f && randomFloat(state) < subsurface) {
            if (continueSubsurfaceRandomWalk(
                hit,
                material,
                constants,
                triangles,
                nodes,
                primitiveIndices,
                volumes,
                volumeSamples,
                volumeAttributeDescriptors,
                volumeAttributeSamples,
                volumeBricks,
                volumeBrickSamples,
                volumeBrickMaterialFieldSamples,
                volumeBrickAttributeDescriptors,
                volumeBrickAttributeSamples,
                volumeBrickBVHNodes,
                volumeBrickBVHIndices,
                volumeBrickGrids,
                volumeBrickGridIndices,
                sdfCounters,
                ray,
                throughput,
                previousBSDFPDF,
                state
            )) {
                if (terminatePathWithRussianRoulette(bounce, throughput, state)) {
                    break;
                }
                continue;
            }
        }

        if (continueTransmissiveSurface(hit, material, ray, throughput, previousBSDFPDF, state)) {
            if (terminatePathWithRussianRoulette(bounce, throughput, state)) {
                break;
            }
            continue;
        }

        if (maxComponent(material.emission.xyz) > 0.0f) {
            float emissionWeight = 1.0f;
            if (bounce > 0u && previousBSDFPDF > 0.0f) {
                float lightPDF = lightPDFForHit(
                    hit,
                    ray.direction,
                    triangles,
                    constants.triangleCount,
                    lights,
                    constants.lightCount
                );
                emissionWeight = powerHeuristic(previousBSDFPDF, lightPDF);
            }
            float3 emissionContribution = throughput * material.emission.xyz * emissionWeight;
            radiance += clampSampleContribution(emissionContribution, constants);
            break;
        }

        float3 directContribution = throughput * sampleDirectLighting(
            hit,
            material,
            -ray.direction,
            constants,
            triangles,
            materials,            nodes,
            primitiveIndices,
            volumes,
            volumeSamples,
            volumeAttributeDescriptors,
            volumeAttributeSamples,
            volumeBricks,
            volumeBrickSamples,
            volumeBrickMaterialFieldSamples,
            volumeBrickAttributeDescriptors,
            volumeBrickAttributeSamples,
            volumeBrickBVHNodes,
            volumeBrickBVHIndices,
            volumeBrickGrids,
            volumeBrickGridIndices,
            sdfCounters,
            lights,
            environmentSamples,
            textureDescriptors,
            texturePixels,
            state
        );
        radiance += clampSampleContribution(directContribution, constants);
        float roughness = clamp(material.parameters.x, 0.02f, 1.0f);
        float anisotropy = materialSpecularAnisotropy(material);
        float3 f0 = materialF0(material);
        float clearcoat = materialClearcoat(material);
        float clearcoatRoughness = materialClearcoatRoughness(material);
        float diffuseProbability;
        float specularProbability;
        float clearcoatProbability;
        materialLobeProbabilities(material, diffuseProbability, specularProbability, clearcoatProbability);
        float3 localDirection = cosineHemisphere(float2(randomFloat(state), randomFloat(state)));
        float3 diffuseDirection = orientHemisphere(localDirection, hit.normal);
        float3 nextDirection;
        float lobeSample = randomFloat(state);
        float3 viewDirection = -ray.direction;

        if (lobeSample < clearcoatProbability) {
            float3 halfVector = sampleGGXVisibleNormal(
                float2(randomFloat(state), randomFloat(state)),
                hit.normal,
                hit.tangent,
                hit.bitangent,
                viewDirection,
                clearcoatRoughness,
                0.0f
            );
            nextDirection = normalize(reflect(ray.direction, halfVector));
            if (dot(nextDirection, hit.normal) <= 0.0f) {
                nextDirection = diffuseDirection;
                throughput *= materialDiffuseBounceWeight(material, hit.normal, viewDirection, nextDirection)
                    / max(diffuseProbability, 1e-5f);
            } else {
                float nDotL = max(dot(hit.normal, nextDirection), 1e-5f);
                float vDotH = max(dot(viewDirection, halfVector), 1e-5f);
                throughput *= clearcoat
                    * fresnelSchlickThinFilm(vDotH, materialClearcoatF0Color(material), material)
                    * geometrySmithG1GGX(nDotL, clearcoatRoughness)
                    / max(clearcoatProbability, 1e-5f);
            }
        } else if (lobeSample < clearcoatProbability + specularProbability) {
            float3 halfVector = sampleGGXVisibleNormal(
                float2(randomFloat(state), randomFloat(state)),
                hit.normal,
                hit.tangent,
                hit.bitangent,
                viewDirection,
                roughness,
                anisotropy
            );
            nextDirection = normalize(reflect(ray.direction, halfVector));
            if (dot(nextDirection, hit.normal) <= 0.0f) {
                nextDirection = diffuseDirection;
                throughput *= materialDiffuseBounceWeight(material, hit.normal, viewDirection, nextDirection)
                    / max(diffuseProbability, 1e-5f);
            } else {
                float nDotL = max(dot(hit.normal, nextDirection), 1e-5f);
                float vDotH = max(dot(viewDirection, halfVector), 1e-5f);
                float3 fresnel = fresnelSchlickThinFilm(vDotH, f0, material);
                float3 clearcoatAttenuation = materialClearcoatAttenuationForDirection(
                    material,
                    hit.normal,
                    viewDirection,
                    nextDirection
                );
                throughput *= clearcoatAttenuation
                    * fresnel
                    * geometrySmithG1GGXAnisotropic(
                        nextDirection,
                        hit.normal,
                        hit.tangent,
                        hit.bitangent,
                        roughness,
                        anisotropy
                    )
                    / max(specularProbability, 1e-5f);
            }
        } else {
            nextDirection = diffuseDirection;
            throughput *= materialDiffuseBounceWeight(material, hit.normal, viewDirection, nextDirection)
                / max(diffuseProbability, 1e-5f);
        }

        previousBSDFPDF = materialBSDFPDF(
            material,
            hit.normal,
            hit.tangent,
            hit.bitangent,
            viewDirection,
            nextDirection
        );
        ray.origin = hit.position + hit.normal * 0.001f;
        ray.direction = nextDirection;

        if (terminatePathWithRussianRoulette(bounce, throughput, state)) {
            break;
        }
    }

    float4 previous = accumulation.read(pixel);
    float sampleWeight = 1.0f / ((float)constants.sampleIndex + 1.0f);
    float3 color = mix(previous.xyz, radiance, sampleWeight);
    float alpha = mix(previous.w, outputAlpha, sampleWeight);
    accumulation.write(float4(color, alpha), pixel);

    Hit aovHit = emptyHit();
    GPUMaterial aovMaterial;
    bool hasAOVHit = primaryHit.hit;
    aovHit = primaryHit;
    aovMaterial = primaryMaterial;
    if (constants.denoiserEnabled != 0u) {
        hasAOVHit = tracePrimaryAOV(
            makeCameraRay(camera, constants.width, constants.height, pixel, 0.5f, 0.5f, 0.0f, 0.0f),
            constants,
            triangles,
            nodes,
            primitiveIndices,
            volumes,
            volumeSamples,
            volumeAttributeDescriptors,
            volumeAttributeSamples,
            volumeBricks,
            volumeBrickSamples,
            volumeBrickMaterialFieldSamples,
            volumeBrickAttributeDescriptors,
            volumeBrickAttributeSamples,
            volumeBrickBVHNodes,
            volumeBrickBVHIndices,
            volumeBrickGrids,
            volumeBrickGridIndices,
            sdfCounters,
            materials,            textureDescriptors,
            texturePixels,
            aovHit,
            aovMaterial
        );
    }

    if (hasAOVHit) {
        float3 encodedNormal = aovHit.normal * 0.5f + 0.5f;
        depthOutput.write(float4(aovHit.t, aovHit.t, aovHit.t, 1.0f), pixel);
        normalOutput.write(float4(encodedNormal, 1.0f), pixel);
        albedoOutput.write(float4(aovMaterial.baseColor.xyz, aovMaterial.baseColor.w), pixel);
        float materialID = (float)(aovHit.materialID + 1u);
        float objectID = (float)(aovHit.objectID + 1u);
        materialIDOutput.write(float4(materialID, materialID, materialID, 1.0f), pixel);
        objectIDOutput.write(float4(objectID, objectID, objectID, 1.0f), pixel);

        float2 currentScreen;
        float2 previousScreen;
        if (projectToScreen(camera, aovHit.position, constants.width, constants.height, currentScreen)
            && projectToScreen(previousCamera, aovHit.position, constants.width, constants.height, previousScreen)) {
            float2 motion = previousScreen - currentScreen;
            motionVectorOutput.write(float4(motion.x, motion.y, 0.0f, 1.0f), pixel);
        } else {
            motionVectorOutput.write(float4(0.0f), pixel);
        }
    } else {
        depthOutput.write(float4(0.0f), pixel);
        normalOutput.write(float4(0.5f, 0.5f, 0.5f, 0.0f), pixel);
        albedoOutput.write(float4(0.0f), pixel);
        materialIDOutput.write(float4(0.0f), pixel);
        objectIDOutput.write(float4(0.0f), pixel);
        motionVectorOutput.write(float4(0.0f), pixel);
    }
}

kernel void pathTraceHardwareKernel(
    texture2d<float, access::read_write> accumulation [[texture(0)]],
    texture2d<float, access::write> depthOutput [[texture(1)]],
    texture2d<float, access::write> normalOutput [[texture(2)]],
    texture2d<float, access::write> albedoOutput [[texture(3)]],
    texture2d<float, access::write> materialIDOutput [[texture(4)]],
    texture2d<float, access::write> objectIDOutput [[texture(5)]],
    texture2d<float, access::write> motionVectorOutput [[texture(6)]],
    constant GPURenderConstants &constants [[buffer(0)]],
    constant GPUCamera &camera [[buffer(1)]],
    constant GPUTriangle *triangles [[buffer(2)]],
    constant GPUMaterial *materials [[buffer(3)]],
    constant GPUAccelerationNode *nodes [[buffer(4)]],
    constant uint *primitiveIndices [[buffer(5)]],
    constant GPUCamera &previousCamera [[buffer(6)]],
    acceleration_structure<instancing> scene [[buffer(7)]],
    constant GPUTriangle *localTriangles [[buffer(8)]],
    constant GPURayTracingInstance *rtInstances [[buffer(9)]],
    constant GPUTextureDescriptor *textureDescriptors [[buffer(10)]],
    constant float4 *texturePixels [[buffer(11)]],
    constant GPULightRecord *lights [[buffer(12)]],
    constant GPUEnvironmentSample *environmentSamples [[buffer(13)]],
    uint2 gid [[thread_position_in_grid]]
) {
    (void)nodes;
    (void)primitiveIndices;

    if (gid.x >= constants.tileWidth || gid.y >= constants.tileHeight) {
        return;
    }
    uint2 pixel = gid + uint2(constants.tileX, constants.tileY);
    if (pixel.x >= constants.width || pixel.y >= constants.height) {
        return;
    }

    uint state = constants.frameSeed
        ^ hash(pixel.x + pixel.y * constants.width)
        ^ hash(constants.sampleIndex + 1u);

    Ray ray = makeCameraRay(
        camera,
        constants.width,
        constants.height,
        pixel,
        randomFloat(state),
        randomFloat(state),
        randomFloat(state),
        randomFloat(state)
    );

    float3 radiance = float3(0);
    float3 throughput = float3(1);
    float outputAlpha = 1.0f;
    float previousBSDFPDF = 0.0f;

    Hit primaryHit = emptyHit();
    GPUMaterial primaryMaterial;
    primaryMaterial.baseColor = float4(0);
    primaryMaterial.emission = float4(0);
    primaryMaterial.parameters = float4(0);
    primaryMaterial.parameters2 = float4(0);
    primaryMaterial.specularColor = float4(0);
    primaryMaterial.sheenColor = float4(0);
    primaryMaterial.transmissionColor = float4(0);
    primaryMaterial.parameters3 = float4(0);
    primaryMaterial.clearcoatColor = float4(0);
    primaryMaterial.clearcoatAttenuation = float4(0);
    primaryMaterial.transmissionAbsorption = float4(0);
    primaryMaterial.thinFilm = float4(0);
    primaryMaterial.subsurfaceColor = float4(0);
    primaryMaterial.subsurfaceRadius = float4(0);
    primaryMaterial.subsurfaceParameters = float4(0);
    primaryMaterial.volumeScattering = float4(0);
    primaryMaterial.volumeParameters = float4(0);

    for (uint bounce = 0; bounce < constants.maxBounces; ++bounce) {
        Hit hit = intersectSceneHardware(ray, scene, localTriangles, rtInstances);
        if (!hit.hit) {
            if (constants.transparentBackground != 0u && !primaryHit.hit) {
                outputAlpha = 0.0f;
            } else if (constants.showsEnvironmentBackground == 0u && !primaryHit.hit) {
                outputAlpha = 1.0f;
                radiance += max(constants.backgroundColor.xyz, float3(0.0f));
            } else {
                float environmentWeight = 1.0f;
                if (bounce > 0u && previousBSDFPDF > 0.0f) {
                    float environmentLightPDF = environmentPDF(
                        ray.direction,
                        constants,
                        textureDescriptors,
                        environmentSamples
                    );
                    environmentWeight = powerHeuristic(previousBSDFPDF, environmentLightPDF);
                }
                float3 environmentContribution = throughput * sampleEnvironment(
                    ray.direction,
                    constants,
                    textureDescriptors,
                    texturePixels
                ) * environmentWeight;
                radiance += clampSampleContribution(environmentContribution, constants);
            }
            break;
        }

        GPUMaterial material = materialForHit(hit, materials, constants.materialCount);
        hit = applyNormalMap(hit, material, textureDescriptors, texturePixels, ray.direction);
        material = applyBaseColorTexture(material, hit, textureDescriptors, texturePixels);
        if (material.baseColor.w <= 0.001f) {
            ray.origin = hit.position + ray.direction * 0.001f;
            continue;
        }
        if (!primaryHit.hit) {
            primaryHit = hit;
            primaryMaterial = material;
        }

        if (continueTransmissionVolumeRandomWalk(hit, material, ray, throughput, previousBSDFPDF, state)) {
            if (terminatePathWithRussianRoulette(bounce, throughput, state)) {
                break;
            }
            continue;
        }

        float subsurface = materialSubsurface(material);
        if (subsurface > 0.0f && randomFloat(state) < subsurface) {
            if (continueSubsurfaceRandomWalkHardware(
                hit,
                material,
                scene,
                localTriangles,
                rtInstances,
                ray,
                throughput,
                previousBSDFPDF,
                state
            )) {
                if (terminatePathWithRussianRoulette(bounce, throughput, state)) {
                    break;
                }
                continue;
            }
        }

        if (continueTransmissiveSurface(hit, material, ray, throughput, previousBSDFPDF, state)) {
            if (terminatePathWithRussianRoulette(bounce, throughput, state)) {
                break;
            }
            continue;
        }

        if (maxComponent(material.emission.xyz) > 0.0f) {
            float emissionWeight = 1.0f;
            if (bounce > 0u && previousBSDFPDF > 0.0f) {
                float lightPDF = lightPDFForHit(
                    hit,
                    ray.direction,
                    triangles,
                    constants.triangleCount,
                    lights,
                    constants.lightCount
                );
                emissionWeight = powerHeuristic(previousBSDFPDF, lightPDF);
            }
            float3 emissionContribution = throughput * material.emission.xyz * emissionWeight;
            radiance += clampSampleContribution(emissionContribution, constants);
            break;
        }

        float3 directContribution = throughput * sampleDirectLightingHardware(
            hit,
            material,
            -ray.direction,
            constants,
            triangles,
            materials,
            scene,
            localTriangles,
            rtInstances,
            lights,
            environmentSamples,
            textureDescriptors,
            texturePixels,
            state
        );
        radiance += clampSampleContribution(directContribution, constants);
        float roughness = clamp(material.parameters.x, 0.02f, 1.0f);
        float anisotropy = materialSpecularAnisotropy(material);
        float3 f0 = materialF0(material);
        float clearcoat = materialClearcoat(material);
        float clearcoatRoughness = materialClearcoatRoughness(material);
        float diffuseProbability;
        float specularProbability;
        float clearcoatProbability;
        materialLobeProbabilities(material, diffuseProbability, specularProbability, clearcoatProbability);
        float3 localDirection = cosineHemisphere(float2(randomFloat(state), randomFloat(state)));
        float3 diffuseDirection = orientHemisphere(localDirection, hit.normal);
        float3 nextDirection;
        float lobeSample = randomFloat(state);
        float3 viewDirection = -ray.direction;

        if (lobeSample < clearcoatProbability) {
            float3 halfVector = sampleGGXVisibleNormal(
                float2(randomFloat(state), randomFloat(state)),
                hit.normal,
                hit.tangent,
                hit.bitangent,
                viewDirection,
                clearcoatRoughness,
                0.0f
            );
            nextDirection = normalize(reflect(ray.direction, halfVector));
            if (dot(nextDirection, hit.normal) <= 0.0f) {
                nextDirection = diffuseDirection;
                throughput *= materialDiffuseBounceWeight(material, hit.normal, viewDirection, nextDirection)
                    / max(diffuseProbability, 1e-5f);
            } else {
                float nDotL = max(dot(hit.normal, nextDirection), 1e-5f);
                float vDotH = max(dot(viewDirection, halfVector), 1e-5f);
                throughput *= clearcoat
                    * fresnelSchlickThinFilm(vDotH, materialClearcoatF0Color(material), material)
                    * geometrySmithG1GGX(nDotL, clearcoatRoughness)
                    / max(clearcoatProbability, 1e-5f);
            }
        } else if (lobeSample < clearcoatProbability + specularProbability) {
            float3 halfVector = sampleGGXVisibleNormal(
                float2(randomFloat(state), randomFloat(state)),
                hit.normal,
                hit.tangent,
                hit.bitangent,
                viewDirection,
                roughness,
                anisotropy
            );
            nextDirection = normalize(reflect(ray.direction, halfVector));
            if (dot(nextDirection, hit.normal) <= 0.0f) {
                nextDirection = diffuseDirection;
                throughput *= materialDiffuseBounceWeight(material, hit.normal, viewDirection, nextDirection)
                    / max(diffuseProbability, 1e-5f);
            } else {
                float nDotL = max(dot(hit.normal, nextDirection), 1e-5f);
                float vDotH = max(dot(viewDirection, halfVector), 1e-5f);
                float3 fresnel = fresnelSchlickThinFilm(vDotH, f0, material);
                float3 clearcoatAttenuation = materialClearcoatAttenuationForDirection(
                    material,
                    hit.normal,
                    viewDirection,
                    nextDirection
                );
                throughput *= clearcoatAttenuation
                    * fresnel
                    * geometrySmithG1GGXAnisotropic(
                        nextDirection,
                        hit.normal,
                        hit.tangent,
                        hit.bitangent,
                        roughness,
                        anisotropy
                    )
                    / max(specularProbability, 1e-5f);
            }
        } else {
            nextDirection = diffuseDirection;
            throughput *= materialDiffuseBounceWeight(material, hit.normal, viewDirection, nextDirection)
                / max(diffuseProbability, 1e-5f);
        }

        previousBSDFPDF = materialBSDFPDF(
            material,
            hit.normal,
            hit.tangent,
            hit.bitangent,
            viewDirection,
            nextDirection
        );
        ray.origin = hit.position + hit.normal * 0.001f;
        ray.direction = nextDirection;

        if (terminatePathWithRussianRoulette(bounce, throughput, state)) {
            break;
        }
    }

    float4 previous = accumulation.read(pixel);
    float sampleWeight = 1.0f / ((float)constants.sampleIndex + 1.0f);
    float3 color = mix(previous.xyz, radiance, sampleWeight);
    float alpha = mix(previous.w, outputAlpha, sampleWeight);
    accumulation.write(float4(color, alpha), pixel);

    Hit aovHit = emptyHit();
    GPUMaterial aovMaterial;
    bool hasAOVHit = primaryHit.hit;
    aovHit = primaryHit;
    aovMaterial = primaryMaterial;
    if (constants.denoiserEnabled != 0u) {
        hasAOVHit = tracePrimaryAOVHardware(
            makeCameraRay(camera, constants.width, constants.height, pixel, 0.5f, 0.5f, 0.0f, 0.0f),
            scene,
            rtInstances,
            localTriangles,
            materials,
            constants.materialCount,
            textureDescriptors,
            texturePixels,
            aovHit,
            aovMaterial
        );
    }

    if (hasAOVHit) {
        float3 encodedNormal = aovHit.normal * 0.5f + 0.5f;
        depthOutput.write(float4(aovHit.t, aovHit.t, aovHit.t, 1.0f), pixel);
        normalOutput.write(float4(encodedNormal, 1.0f), pixel);
        albedoOutput.write(float4(aovMaterial.baseColor.xyz, aovMaterial.baseColor.w), pixel);
        float materialID = (float)(aovHit.materialID + 1u);
        float objectID = (float)(aovHit.objectID + 1u);
        materialIDOutput.write(float4(materialID, materialID, materialID, 1.0f), pixel);
        objectIDOutput.write(float4(objectID, objectID, objectID, 1.0f), pixel);

        float2 currentScreen;
        float2 previousScreen;
        if (projectToScreen(camera, aovHit.position, constants.width, constants.height, currentScreen)
            && projectToScreen(previousCamera, aovHit.position, constants.width, constants.height, previousScreen)) {
            float2 motion = previousScreen - currentScreen;
            motionVectorOutput.write(float4(motion.x, motion.y, 0.0f, 1.0f), pixel);
        } else {
            motionVectorOutput.write(float4(0.0f), pixel);
        }
    } else {
        depthOutput.write(float4(0.0f), pixel);
        normalOutput.write(float4(0.5f, 0.5f, 0.5f, 0.0f), pixel);
        albedoOutput.write(float4(0.0f), pixel);
        materialIDOutput.write(float4(0.0f), pixel);
        objectIDOutput.write(float4(0.0f), pixel);
        motionVectorOutput.write(float4(0.0f), pixel);
    }
}
