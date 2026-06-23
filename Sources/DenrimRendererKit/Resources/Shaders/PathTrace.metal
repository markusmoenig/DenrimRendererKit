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
    float padding;
    float4 normal;
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
    uint padding1;
    uint padding2;
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

static float3 orientHemisphere(float3 localDirection, float3 normal) {
    float3 helper = fabs(normal.y) < 0.999f ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 tangent = normalize(cross(helper, normal));
    float3 bitangent = cross(normal, tangent);
    return normalize(localDirection.x * tangent + localDirection.y * bitangent + localDirection.z * normal);
}

static float maxComponent(float3 value) {
    return max(value.x, max(value.y, value.z));
}

static float luminance(float3 value) {
    return dot(value, float3(0.2126f, 0.7152f, 0.0722f));
}

static float3 fresnelSchlick(float cosTheta, float3 f0) {
    float factor = pow(clamp(1.0f - cosTheta, 0.0f, 1.0f), 5.0f);
    return f0 + (float3(1.0f) - f0) * factor;
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

static float materialClearcoatF0(GPUMaterial material) {
    return dielectricF0(material.specularColor.w, 1.0f);
}

static float distributionGGX(float nDotH, float roughness) {
    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;
    float denominator = nDotH * nDotH * (alpha2 - 1.0f) + 1.0f;
    return alpha2 / max(3.14159265359f * denominator * denominator, 1e-5f);
}

static float geometrySchlickGGX(float nDotV, float roughness) {
    float r = roughness + 1.0f;
    float k = (r * r) * 0.125f;
    return nDotV / max(nDotV * (1.0f - k) + k, 1e-5f);
}

static float geometrySmith(float nDotV, float nDotL, float roughness) {
    return geometrySchlickGGX(nDotV, roughness) * geometrySchlickGGX(nDotL, roughness);
}

static float3 evaluateMaterialBRDF(
    GPUMaterial material,
    float3 normal,
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
    float3 fresnel = fresnelSchlick(vDotH, f0);
    float distribution = distributionGGX(nDotH, roughness);
    float geometry = geometrySmith(nDotV, nDotL, roughness);
    float3 specular = distribution * geometry * fresnel / max(4.0f * nDotV * nDotL, 1e-5f);
    float clearcoat = materialClearcoat(material);
    float clearcoatF0 = materialClearcoatF0(material);
    float clearcoatRoughness = materialClearcoatRoughness(material);
    float3 clearcoatFresnel = fresnelSchlick(vDotH, float3(clearcoatF0));
    float clearcoatDistribution = distributionGGX(nDotH, clearcoatRoughness);
    float clearcoatGeometry = geometrySmith(nDotV, nDotL, clearcoatRoughness);
    float3 clearcoatSpecular = clearcoatDistribution * clearcoatGeometry * clearcoatFresnel / max(4.0f * nDotV * nDotL, 1e-5f);
    float3 clearcoatAttenuation = float3(1.0f) - clearcoatFresnel * clearcoat;
    float3 diffuse = clearcoatAttenuation * (float3(1.0f) - fresnel) * (1.0f - metallic) * baseColor * inversePi;

    return diffuse + clearcoatAttenuation * specular + clearcoatSpecular * clearcoat;
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
    float clearcoatF0 = materialClearcoatF0(material);
    float diffuseWeight = luminance(baseColor * (1.0f - metallic));
    float specularWeight = luminance(f0);
    float clearcoatWeight = clearcoat * max(clearcoatF0, 0.0f);
    float totalLobeWeight = max(diffuseWeight + specularWeight + clearcoatWeight, 1e-5f);

    clearcoatProbability = clearcoatWeight > 1e-5f
        ? clamp(clearcoatWeight / totalLobeWeight, 0.02f, 0.35f)
        : 0.0f;
    specularProbability = specularWeight > 1e-5f
        ? clamp(specularWeight / totalLobeWeight, 0.08f, 0.92f - clearcoatProbability)
        : 0.0f;
    diffuseProbability = max(0.0f, 1.0f - specularProbability - clearcoatProbability);
}

static float ggxReflectionPDF(float3 normal, float3 viewDirection, float3 lightDirection, float roughness) {
    float3 halfVector = normalize(viewDirection + lightDirection);
    float nDotH = max(dot(normal, halfVector), 0.0f);
    float vDotH = max(dot(viewDirection, halfVector), 0.0f);
    if (nDotH <= 0.0f || vDotH <= 0.0f) {
        return 0.0f;
    }
    return distributionGGX(nDotH, roughness) * nDotH / max(4.0f * vDotH, 1e-5f);
}

static float materialBSDFPDF(
    GPUMaterial material,
    float3 normal,
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
    float diffusePDF = nDotL * inversePi;
    float specularPDF = ggxReflectionPDF(normal, viewDirection, lightDirection, roughness);
    float clearcoatPDF = ggxReflectionPDF(normal, viewDirection, lightDirection, clearcoatRoughness);
    return diffuseProbability * diffusePDF
        + specularProbability * specularPDF
        + clearcoatProbability * clearcoatPDF;
}

static float lightSolidAnglePDF(float distanceSquared, float cosLight, float area) {
    return distanceSquared / max(cosLight * area, 1e-6f);
}

static float lightPDFForHit(Hit hit, float3 incomingDirection, constant GPULightRecord *lights, uint lightCount) {
    for (uint index = 0; index < lightCount; ++index) {
        constant GPULightRecord &light = lights[index];
        if (light.triangleIndex != hit.primitiveID || light.area <= 0.0f) {
            continue;
        }

        float cosLight = max(0.0f, dot(light.normal.xyz, -incomingDirection));
        if (cosLight <= 0.0f) {
            return 0.0f;
        }

        return lightSolidAnglePDF(hit.t * hit.t, cosLight, light.area);
    }

    return 0.0f;
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

static bool intersectTriangle(
    Ray ray,
    constant GPUTriangle &triangle,
    thread float &t,
    thread float3 &normal,
    thread float2 &uv,
    thread float3 &tangent,
    thread float3 &bitangent
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
        if (intersectTriangle(ray, triangles[index], t, normal, uv, tangent, bitangent) && t < closest.t) {
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
                if (intersectTriangle(ray, triangles[triangleIndex], t, normal, uv, tangent, bitangent) && t < closest.t) {
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
    thread uint &state
) {
    float3 direct = float3(0);

    for (uint index = 0; index < constants.lightCount; ++index) {
        constant GPULightRecord &light = lights[index];
        uint lightTriangleIndex = light.triangleIndex;
        if (lightTriangleIndex >= constants.triangleCount) {
            continue;
        }

        constant GPUTriangle &lightTriangle = triangles[lightTriangleIndex];
        GPUMaterial lightMaterial = materials[min(light.materialIndex, constants.materialCount - 1u)];
        float3 emission = lightMaterial.emission.xyz;

        float area = light.area;
        if (area <= 0.0f) {
            continue;
        }

        float3 lightPoint = sampleTriangle(lightTriangle, float2(randomFloat(state), randomFloat(state)));
        float3 toLight = lightPoint - hit.position;
        float distanceSquared = dot(toLight, toLight);
        float distanceToLight = sqrt(distanceSquared);
        float3 lightDirection = toLight / distanceToLight;
        float cosSurface = max(0.0f, dot(hit.normal, lightDirection));
        float3 lightNormal = light.normal.xyz;
        float cosLight = max(0.0f, dot(lightNormal, -lightDirection));

        if (cosSurface <= 0.0f || cosLight <= 0.0f) {
            continue;
        }

        float lightPDF = lightSolidAnglePDF(distanceSquared, cosLight, area);
        float bsdfPDF = materialBSDFPDF(surfaceMaterial, hit.normal, viewDirection, lightDirection);
        float misWeight = powerHeuristic(lightPDF, bsdfPDF);

        Ray shadowRay;
        shadowRay.origin = hit.position + hit.normal * 0.001f;
        shadowRay.direction = lightDirection;
        Hit shadowHit = intersectScene(shadowRay, constants, triangles, nodes, primitiveIndices);

        if (shadowHit.hit && shadowHit.t < distanceToLight - 0.002f) {
            continue;
        }

        float geometryTerm = cosSurface * cosLight * area / max(distanceSquared, 1e-6f);
        float3 brdf = evaluateMaterialBRDF(surfaceMaterial, hit.normal, viewDirection, lightDirection);
        direct += brdf * emission * geometryTerm * misWeight;
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
    thread uint &state
) {
    float3 direct = float3(0);

    for (uint index = 0; index < constants.lightCount; ++index) {
        constant GPULightRecord &light = lights[index];
        uint lightTriangleIndex = light.triangleIndex;
        if (lightTriangleIndex >= constants.triangleCount) {
            continue;
        }

        constant GPUTriangle &lightTriangle = triangles[lightTriangleIndex];
        GPUMaterial lightMaterial = materials[min(light.materialIndex, constants.materialCount - 1u)];
        float3 emission = lightMaterial.emission.xyz;

        float area = light.area;
        if (area <= 0.0f) {
            continue;
        }

        float3 lightPoint = sampleTriangle(lightTriangle, float2(randomFloat(state), randomFloat(state)));
        float3 toLight = lightPoint - hit.position;
        float distanceSquared = dot(toLight, toLight);
        float distanceToLight = sqrt(distanceSquared);
        float3 lightDirection = toLight / distanceToLight;
        float cosSurface = max(0.0f, dot(hit.normal, lightDirection));
        float3 lightNormal = light.normal.xyz;
        float cosLight = max(0.0f, dot(lightNormal, -lightDirection));

        if (cosSurface <= 0.0f || cosLight <= 0.0f) {
            continue;
        }

        float lightPDF = lightSolidAnglePDF(distanceSquared, cosLight, area);
        float bsdfPDF = materialBSDFPDF(surfaceMaterial, hit.normal, viewDirection, lightDirection);
        float misWeight = powerHeuristic(lightPDF, bsdfPDF);

        Ray shadowRay;
        shadowRay.origin = hit.position + hit.normal * 0.001f;
        shadowRay.direction = lightDirection;
        Hit shadowHit = intersectSceneHardware(shadowRay, scene, localTriangles, rtInstances);

        if (shadowHit.hit && shadowHit.t < distanceToLight - 0.002f) {
            continue;
        }

        float geometryTerm = cosSurface * cosLight * area / max(distanceSquared, 1e-6f);
        float3 brdf = evaluateMaterialBRDF(surfaceMaterial, hit.normal, viewDirection, lightDirection);
        direct += brdf * emission * geometryTerm * misWeight;
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
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= constants.width || gid.y >= constants.height) {
        return;
    }

    uint state = constants.frameSeed
        ^ hash(gid.x + gid.y * constants.width)
        ^ hash(constants.sampleIndex + 1u);

    float jitterX = randomFloat(state);
    float jitterY = randomFloat(state);
    float u = ((float)gid.x + jitterX) / (float)constants.width;
    float v = 1.0f - (((float)gid.y + jitterY) / (float)constants.height);

    Ray ray;
    ray.origin = camera.origin.xyz;
    ray.direction = normalize(camera.lowerLeft.xyz + u * camera.horizontal.xyz + v * camera.vertical.xyz - ray.origin);

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

    for (uint bounce = 0; bounce < constants.maxBounces; ++bounce) {
        Hit hit = intersectScene(ray, constants, triangles, nodes, primitiveIndices);
        if (!hit.hit) {
            if (constants.transparentBackground != 0u) {
                if (bounce == 0u) {
                    outputAlpha = 0.0f;
                }
            } else {
                float sky = 0.5f * (ray.direction.y + 1.0f);
                radiance += throughput * mix(float3(0.02f, 0.025f, 0.035f), float3(0.25f, 0.32f, 0.45f), sky);
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

        if (maxComponent(material.emission.xyz) > 0.0f) {
            float emissionWeight = 1.0f;
            if (bounce > 0u && previousBSDFPDF > 0.0f) {
                float lightPDF = lightPDFForHit(hit, ray.direction, lights, constants.lightCount);
                emissionWeight = powerHeuristic(previousBSDFPDF, lightPDF);
            }
            radiance += throughput * material.emission.xyz * emissionWeight;
            break;
        }

        radiance += throughput * sampleDirectLighting(
            hit,
            material,
            -ray.direction,
            constants,
            triangles,
            materials,
            nodes,
            primitiveIndices,
            lights,
            state
        );
        float roughness = clamp(material.parameters.x, 0.02f, 1.0f);
        float metallic = clamp(material.parameters.y, 0.0f, 1.0f);
        float3 baseColor = material.baseColor.xyz;
        float3 f0 = materialF0(material);
        float clearcoat = materialClearcoat(material);
        float clearcoatF0 = materialClearcoatF0(material);
        float clearcoatRoughness = materialClearcoatRoughness(material);
        float diffuseWeight = luminance(baseColor * (1.0f - metallic));
        float specularWeight = luminance(f0);
        float clearcoatWeight = clearcoat * max(clearcoatF0, 0.0f);
        float totalLobeWeight = max(diffuseWeight + specularWeight + clearcoatWeight, 1e-5f);
        float clearcoatProbability = clearcoatWeight > 1e-5f ? clamp(clearcoatWeight / totalLobeWeight, 0.02f, 0.35f) : 0.0f;
        float specularProbability = specularWeight > 1e-5f
            ? clamp(specularWeight / totalLobeWeight, 0.08f, 0.92f - clearcoatProbability)
            : 0.0f;
        float3 localDirection = cosineHemisphere(float2(randomFloat(state), randomFloat(state)));
        float3 diffuseDirection = orientHemisphere(localDirection, hit.normal);
        float3 nextDirection;
        float lobeSample = randomFloat(state);
        float3 viewDirection = -ray.direction;

        if (lobeSample < clearcoatProbability) {
            float3 halfVector = sampleGGXHalfVector(float2(randomFloat(state), randomFloat(state)), hit.normal, clearcoatRoughness);
            nextDirection = normalize(reflect(ray.direction, halfVector));
            if (dot(nextDirection, hit.normal) <= 0.0f) {
                nextDirection = diffuseDirection;
            }
            throughput *= clearcoat * fresnelSchlick(max(dot(viewDirection, halfVector), 0.0f), float3(clearcoatF0));
        } else if (lobeSample < clearcoatProbability + specularProbability) {
            float3 halfVector = sampleGGXHalfVector(float2(randomFloat(state), randomFloat(state)), hit.normal, roughness);
            nextDirection = normalize(reflect(ray.direction, halfVector));
            if (dot(nextDirection, hit.normal) <= 0.0f) {
                nextDirection = diffuseDirection;
            }
            float3 fresnel = fresnelSchlick(max(dot(viewDirection, halfVector), 0.0f), f0);
            throughput *= fresnel;
        } else {
            nextDirection = diffuseDirection;
            throughput *= baseColor * (1.0f - metallic);
        }

        previousBSDFPDF = materialBSDFPDF(material, hit.normal, viewDirection, nextDirection);
        ray.origin = hit.position + hit.normal * 0.001f;
        ray.direction = nextDirection;

        if (maxComponent(throughput) < 0.02f) {
            break;
        }
    }

    float4 previous = accumulation.read(gid);
    float sampleWeight = 1.0f / ((float)constants.sampleIndex + 1.0f);
    float3 color = mix(previous.xyz, radiance, sampleWeight);
    float alpha = mix(previous.w, outputAlpha, sampleWeight);
    accumulation.write(float4(color, alpha), gid);

    if (primaryHit.hit) {
        float3 encodedNormal = primaryHit.normal * 0.5f + 0.5f;
        depthOutput.write(float4(primaryHit.t, primaryHit.t, primaryHit.t, 1.0f), gid);
        normalOutput.write(float4(encodedNormal, 1.0f), gid);
        albedoOutput.write(float4(primaryMaterial.baseColor.xyz, primaryMaterial.baseColor.w), gid);
        float materialID = (float)(primaryHit.materialID + 1u);
        float objectID = (float)(primaryHit.objectID + 1u);
        materialIDOutput.write(float4(materialID, materialID, materialID, 1.0f), gid);
        objectIDOutput.write(float4(objectID, objectID, objectID, 1.0f), gid);

        float2 currentScreen;
        float2 previousScreen;
        if (projectToScreen(camera, primaryHit.position, constants.width, constants.height, currentScreen)
            && projectToScreen(previousCamera, primaryHit.position, constants.width, constants.height, previousScreen)) {
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

    float jitterX = randomFloat(state);
    float jitterY = randomFloat(state);
    float u = ((float)gid.x + jitterX) / (float)constants.width;
    float v = 1.0f - (((float)gid.y + jitterY) / (float)constants.height);

    Ray ray;
    ray.origin = camera.origin.xyz;
    ray.direction = normalize(camera.lowerLeft.xyz + u * camera.horizontal.xyz + v * camera.vertical.xyz - ray.origin);

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

    for (uint bounce = 0; bounce < constants.maxBounces; ++bounce) {
        Hit hit = intersectSceneHardware(ray, scene, localTriangles, rtInstances);
        if (!hit.hit) {
            if (constants.transparentBackground != 0u) {
                if (bounce == 0u) {
                    outputAlpha = 0.0f;
                }
            } else {
                float sky = 0.5f * (ray.direction.y + 1.0f);
                radiance += throughput * mix(float3(0.02f, 0.025f, 0.035f), float3(0.25f, 0.32f, 0.45f), sky);
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

        if (maxComponent(material.emission.xyz) > 0.0f) {
            float emissionWeight = 1.0f;
            if (bounce > 0u && previousBSDFPDF > 0.0f) {
                float lightPDF = lightPDFForHit(hit, ray.direction, lights, constants.lightCount);
                emissionWeight = powerHeuristic(previousBSDFPDF, lightPDF);
            }
            radiance += throughput * material.emission.xyz * emissionWeight;
            break;
        }

        radiance += throughput * sampleDirectLightingHardware(
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
            state
        );
        float roughness = clamp(material.parameters.x, 0.02f, 1.0f);
        float metallic = clamp(material.parameters.y, 0.0f, 1.0f);
        float3 baseColor = material.baseColor.xyz;
        float3 f0 = materialF0(material);
        float clearcoat = materialClearcoat(material);
        float clearcoatF0 = materialClearcoatF0(material);
        float clearcoatRoughness = materialClearcoatRoughness(material);
        float diffuseWeight = luminance(baseColor * (1.0f - metallic));
        float specularWeight = luminance(f0);
        float clearcoatWeight = clearcoat * max(clearcoatF0, 0.0f);
        float totalLobeWeight = max(diffuseWeight + specularWeight + clearcoatWeight, 1e-5f);
        float clearcoatProbability = clearcoatWeight > 1e-5f ? clamp(clearcoatWeight / totalLobeWeight, 0.02f, 0.35f) : 0.0f;
        float specularProbability = specularWeight > 1e-5f
            ? clamp(specularWeight / totalLobeWeight, 0.08f, 0.92f - clearcoatProbability)
            : 0.0f;
        float3 localDirection = cosineHemisphere(float2(randomFloat(state), randomFloat(state)));
        float3 diffuseDirection = orientHemisphere(localDirection, hit.normal);
        float3 nextDirection;
        float lobeSample = randomFloat(state);
        float3 viewDirection = -ray.direction;

        if (lobeSample < clearcoatProbability) {
            float3 halfVector = sampleGGXHalfVector(float2(randomFloat(state), randomFloat(state)), hit.normal, clearcoatRoughness);
            nextDirection = normalize(reflect(ray.direction, halfVector));
            if (dot(nextDirection, hit.normal) <= 0.0f) {
                nextDirection = diffuseDirection;
            }
            throughput *= clearcoat * fresnelSchlick(max(dot(viewDirection, halfVector), 0.0f), float3(clearcoatF0));
        } else if (lobeSample < clearcoatProbability + specularProbability) {
            float3 halfVector = sampleGGXHalfVector(float2(randomFloat(state), randomFloat(state)), hit.normal, roughness);
            nextDirection = normalize(reflect(ray.direction, halfVector));
            if (dot(nextDirection, hit.normal) <= 0.0f) {
                nextDirection = diffuseDirection;
            }
            float3 fresnel = fresnelSchlick(max(dot(viewDirection, halfVector), 0.0f), f0);
            throughput *= fresnel;
        } else {
            nextDirection = diffuseDirection;
            throughput *= baseColor * (1.0f - metallic);
        }

        previousBSDFPDF = materialBSDFPDF(material, hit.normal, viewDirection, nextDirection);
        ray.origin = hit.position + hit.normal * 0.001f;
        ray.direction = nextDirection;

        if (maxComponent(throughput) < 0.02f) {
            break;
        }
    }

    float4 previous = accumulation.read(gid);
    float sampleWeight = 1.0f / ((float)constants.sampleIndex + 1.0f);
    float3 color = mix(previous.xyz, radiance, sampleWeight);
    float alpha = mix(previous.w, outputAlpha, sampleWeight);
    accumulation.write(float4(color, alpha), gid);

    if (primaryHit.hit) {
        float3 encodedNormal = primaryHit.normal * 0.5f + 0.5f;
        depthOutput.write(float4(primaryHit.t, primaryHit.t, primaryHit.t, 1.0f), gid);
        normalOutput.write(float4(encodedNormal, 1.0f), gid);
        albedoOutput.write(float4(primaryMaterial.baseColor.xyz, primaryMaterial.baseColor.w), gid);
        float materialID = (float)(primaryHit.materialID + 1u);
        float objectID = (float)(primaryHit.objectID + 1u);
        materialIDOutput.write(float4(materialID, materialID, materialID, 1.0f), gid);
        objectIDOutput.write(float4(objectID, objectID, objectID, 1.0f), gid);

        float2 currentScreen;
        float2 previousScreen;
        if (projectToScreen(camera, primaryHit.position, constants.width, constants.height, currentScreen)
            && projectToScreen(previousCamera, primaryHit.position, constants.width, constants.height, previousScreen)) {
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
