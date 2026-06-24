#include <metal_stdlib>
#include <metal_raytracing>
using namespace metal;
using namespace raytracing;

struct GPUCamera {
    float4 origin;
    float4 lowerLeft;
    float4 horizontal;
    float4 vertical;
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

struct GPURenderConstants {
    uint width;
    uint height;
    uint triangleCount;
    uint materialCount;
    uint sampleIndex;
    uint maxBounces;
    uint frameSeed;
    uint accelerationNodeCount;
    uint transparentBackground;
    uint lightCount;
    uint environmentTextureIndexPlusOne;
    uint environmentDistributionCount;
    float environmentIntensity;
    float environmentRotationY;
    float environmentMaxRadiance;
    float sampleRadianceClamp;
    uint padding1;
};

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
    float3 normal;
    float2 uv;
    float3 tangent;
    float3 bitangent;
    uint materialID;
    uint objectID;
    uint primitiveID;
    bool frontFacing;
};

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

    float3 planePoint = camera.origin.xyz + toPoint * planeT;
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

static Hit emptyHit() {
    Hit closest;
    closest.hit = false;
    closest.t = INFINITY;
    closest.position = float3(0);
    closest.normal = float3(0, 1, 0);
    closest.uv = float2(0);
    closest.tangent = float3(1, 0, 0);
    closest.bitangent = float3(0, 0, 1);
    closest.materialID = 0;
    closest.objectID = 0;
    closest.primitiveID = 0;
    closest.frontFacing = true;
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
    constant uint *primitiveIndices
) {
    if (constants.accelerationNodeCount == 0 || nodes == nullptr || primitiveIndices == nullptr) {
        return intersectSceneLinear(ray, constants, triangles);
    }

    Hit closest = emptyHit();
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
        Hit boundaryHit = intersectScene(mediumRay, constants, triangles, nodes, primitiveIndices);
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

static Ray makeCameraRay(GPUCamera camera, uint width, uint height, uint2 gid, float jitterX, float jitterY) {
    float u = ((float)gid.x + jitterX) / (float)width;
    float v = 1.0f - (((float)gid.y + jitterY) / (float)height);

    Ray ray;
    ray.origin = camera.origin.xyz;
    ray.direction = normalize(camera.lowerLeft.xyz + u * camera.horizontal.xyz + v * camera.vertical.xyz - ray.origin);
    return ray;
}

static bool tracePrimaryAOV(
    Ray ray,
    constant GPURenderConstants &constants,
    constant GPUTriangle *triangles,
    constant GPUAccelerationNode *nodes,
    constant uint *primitiveIndices,
    constant GPUMaterial *materials,
    constant GPUTextureDescriptor *textureDescriptors,
    constant float4 *texturePixels,
    thread Hit &primaryHit,
    thread GPUMaterial &primaryMaterial
) {
    for (uint pass = 0; pass < 32u; ++pass) {
        Hit hit = intersectScene(ray, constants, triangles, nodes, primitiveIndices);
        if (!hit.hit) {
            return false;
        }

        GPUMaterial material = materials[min(hit.materialID, constants.materialCount - 1u)];
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

        GPUMaterial material = materials[min(hit.materialID, materialCount - 1u)];
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
    thread float3 &transmittance
) {
    float traveled = 0.0f;
    for (uint step = 0; step < 8u; ++step) {
        Hit shadowHit = intersectScene(shadowRay, constants, triangles, nodes, primitiveIndices);
        if (!shadowHit.hit || traveled + shadowHit.t >= maxDistance) {
            return false;
        }

        GPUMaterial shadowMaterial = materials[min(shadowHit.materialID, constants.materialCount - 1u)];
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

        GPUMaterial shadowMaterial = materials[min(shadowHit.materialID, constants.materialCount - 1u)];
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
                        materials,
                        nodes,
                        primitiveIndices,
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
                materials,
                nodes,
                primitiveIndices,
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
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= constants.width || gid.y >= constants.height) {
        return;
    }

    uint state = constants.frameSeed
        ^ hash(gid.x + gid.y * constants.width)
        ^ hash(constants.sampleIndex + 1u);

    Ray ray = makeCameraRay(
        camera,
        constants.width,
        constants.height,
        gid,
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
        Hit hit = intersectScene(ray, constants, triangles, nodes, primitiveIndices);
        if (!hit.hit) {
            if (constants.transparentBackground != 0u) {
                if (bounce == 0u) {
                    outputAlpha = 0.0f;
                }
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

        GPUMaterial material = materials[min(hit.materialID, constants.materialCount - 1u)];
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
            materials,
            nodes,
            primitiveIndices,
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

    float4 previous = accumulation.read(gid);
    float sampleWeight = 1.0f / ((float)constants.sampleIndex + 1.0f);
    float3 color = mix(previous.xyz, radiance, sampleWeight);
    float alpha = mix(previous.w, outputAlpha, sampleWeight);
    accumulation.write(float4(color, alpha), gid);

    Hit aovHit = emptyHit();
    GPUMaterial aovMaterial;
    bool hasAOVHit = primaryHit.hit;
    aovHit = primaryHit;
    aovMaterial = primaryMaterial;
    if (constants.padding1 != 0u) {
        hasAOVHit = tracePrimaryAOV(
            makeCameraRay(camera, constants.width, constants.height, gid, 0.5f, 0.5f),
            constants,
            triangles,
            nodes,
            primitiveIndices,
            materials,
            textureDescriptors,
            texturePixels,
            aovHit,
            aovMaterial
        );
    }

    if (hasAOVHit) {
        float3 encodedNormal = aovHit.normal * 0.5f + 0.5f;
        depthOutput.write(float4(aovHit.t, aovHit.t, aovHit.t, 1.0f), gid);
        normalOutput.write(float4(encodedNormal, 1.0f), gid);
        albedoOutput.write(float4(aovMaterial.baseColor.xyz, aovMaterial.baseColor.w), gid);
        float materialID = (float)(aovHit.materialID + 1u);
        float objectID = (float)(aovHit.objectID + 1u);
        materialIDOutput.write(float4(materialID, materialID, materialID, 1.0f), gid);
        objectIDOutput.write(float4(objectID, objectID, objectID, 1.0f), gid);

        float2 currentScreen;
        float2 previousScreen;
        if (projectToScreen(camera, aovHit.position, constants.width, constants.height, currentScreen)
            && projectToScreen(previousCamera, aovHit.position, constants.width, constants.height, previousScreen)) {
            float2 motion = previousScreen - currentScreen;
            motionVectorOutput.write(float4(motion.x, motion.y, 0.0f, 1.0f), gid);
        } else {
            motionVectorOutput.write(float4(0.0f), gid);
        }
    } else {
        depthOutput.write(float4(0.0f), gid);
        normalOutput.write(float4(0.5f, 0.5f, 0.5f, 0.0f), gid);
        albedoOutput.write(float4(0.0f), gid);
        materialIDOutput.write(float4(0.0f), gid);
        objectIDOutput.write(float4(0.0f), gid);
        motionVectorOutput.write(float4(0.0f), gid);
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

    if (gid.x >= constants.width || gid.y >= constants.height) {
        return;
    }

    uint state = constants.frameSeed
        ^ hash(gid.x + gid.y * constants.width)
        ^ hash(constants.sampleIndex + 1u);

    Ray ray = makeCameraRay(
        camera,
        constants.width,
        constants.height,
        gid,
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
            if (constants.transparentBackground != 0u) {
                if (bounce == 0u) {
                    outputAlpha = 0.0f;
                }
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

        GPUMaterial material = materials[min(hit.materialID, constants.materialCount - 1u)];
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

    float4 previous = accumulation.read(gid);
    float sampleWeight = 1.0f / ((float)constants.sampleIndex + 1.0f);
    float3 color = mix(previous.xyz, radiance, sampleWeight);
    float alpha = mix(previous.w, outputAlpha, sampleWeight);
    accumulation.write(float4(color, alpha), gid);

    Hit aovHit = emptyHit();
    GPUMaterial aovMaterial;
    bool hasAOVHit = primaryHit.hit;
    aovHit = primaryHit;
    aovMaterial = primaryMaterial;
    if (constants.padding1 != 0u) {
        hasAOVHit = tracePrimaryAOVHardware(
            makeCameraRay(camera, constants.width, constants.height, gid, 0.5f, 0.5f),
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
        depthOutput.write(float4(aovHit.t, aovHit.t, aovHit.t, 1.0f), gid);
        normalOutput.write(float4(encodedNormal, 1.0f), gid);
        albedoOutput.write(float4(aovMaterial.baseColor.xyz, aovMaterial.baseColor.w), gid);
        float materialID = (float)(aovHit.materialID + 1u);
        float objectID = (float)(aovHit.objectID + 1u);
        materialIDOutput.write(float4(materialID, materialID, materialID, 1.0f), gid);
        objectIDOutput.write(float4(objectID, objectID, objectID, 1.0f), gid);

        float2 currentScreen;
        float2 previousScreen;
        if (projectToScreen(camera, aovHit.position, constants.width, constants.height, currentScreen)
            && projectToScreen(previousCamera, aovHit.position, constants.width, constants.height, previousScreen)) {
            float2 motion = previousScreen - currentScreen;
            motionVectorOutput.write(float4(motion.x, motion.y, 0.0f, 1.0f), gid);
        } else {
            motionVectorOutput.write(float4(0.0f), gid);
        }
    } else {
        depthOutput.write(float4(0.0f), gid);
        normalOutput.write(float4(0.5f, 0.5f, 0.5f, 0.0f), gid);
        albedoOutput.write(float4(0.0f), gid);
        materialIDOutput.write(float4(0.0f), gid);
        objectIDOutput.write(float4(0.0f), gid);
        motionVectorOutput.write(float4(0.0f), gid);
    }
}
