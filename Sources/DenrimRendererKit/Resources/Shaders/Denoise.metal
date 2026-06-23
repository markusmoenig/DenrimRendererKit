#include <metal_stdlib>
using namespace metal;

struct GPUDenoiseConstants {
    uint width;
    uint height;
    uint radius;
    uint padding;
    float normalSigma;
    float depthSigma;
    float albedoSigma;
    float colorSigma;
    uint stepWidth;
    uint padding2;
    uint padding3;
    uint padding4;
};

static float3 denoiseNormal(float4 encodedNormal) {
    return normalize(encodedNormal.xyz * 2.0f - 1.0f);
}

static float denoiseColorDistance(float3 lhs, float3 rhs) {
    float3 delta = lhs - rhs;
    return dot(delta, delta);
}

static float denoiseKernelWeight(int offset) {
    int absoluteOffset = abs(offset);
    if (absoluteOffset == 0) {
        return 0.375f;
    }
    if (absoluteOffset == 1) {
        return 0.25f;
    }
    return 0.0625f;
}

kernel void simpleSpatialDenoiseKernel(
    texture2d<float, access::read> beauty [[texture(0)]],
    texture2d<float, access::read> depth [[texture(1)]],
    texture2d<float, access::read> normal [[texture(2)]],
    texture2d<float, access::read> albedo [[texture(3)]],
    texture2d<float, access::write> denoisedBeauty [[texture(4)]],
    constant GPUDenoiseConstants &constants [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= constants.width || gid.y >= constants.height) {
        return;
    }

    float4 centerBeauty = beauty.read(gid);
    float centerDepth = depth.read(gid).x;
    if (centerBeauty.w <= 0.0001f || !isfinite(centerDepth) || centerDepth <= 0.0f) {
        denoisedBeauty.write(centerBeauty, gid);
        return;
    }

    float3 centerNormal = denoiseNormal(normal.read(gid));
    float3 centerAlbedo = albedo.read(gid).xyz;
    int radius = int(constants.radius);
    float normalSigmaSquared = constants.normalSigma * constants.normalSigma;
    float depthSigma = max(constants.depthSigma * max(centerDepth, 1.0f), 0.0001f);
    float depthSigmaSquared = depthSigma * depthSigma;
    float albedoSigmaSquared = constants.albedoSigma * constants.albedoSigma;
    float colorSigmaSquared = constants.colorSigma * constants.colorSigma;
    int stepWidth = int(max(constants.stepWidth, 1u));

    float3 weightedColor = float3(0.0f);
    float totalWeight = 0.0f;

    for (int y = -radius; y <= radius; ++y) {
        for (int x = -radius; x <= radius; ++x) {
            int2 samplePosition = int2(gid) + int2(x * stepWidth, y * stepWidth);
            samplePosition = clamp(
                samplePosition,
                int2(0),
                int2(int(constants.width) - 1, int(constants.height) - 1)
            );
            uint2 sampleGID = uint2(samplePosition);

            float4 sampleBeauty = beauty.read(sampleGID);
            float sampleDepth = depth.read(sampleGID).x;
            if (sampleBeauty.w <= 0.0001f || !isfinite(sampleDepth) || sampleDepth <= 0.0f) {
                continue;
            }

            float spatialWeight = denoiseKernelWeight(x) * denoiseKernelWeight(y);

            float3 sampleNormal = denoiseNormal(normal.read(sampleGID));
            float normalDistance = 1.0f - clamp(dot(centerNormal, sampleNormal), 0.0f, 1.0f);
            float normalWeight = exp(-(normalDistance * normalDistance) / (2.0f * normalSigmaSquared));

            float depthDelta = sampleDepth - centerDepth;
            float depthWeight = exp(-(depthDelta * depthDelta) / (2.0f * depthSigmaSquared));

            float3 sampleAlbedo = albedo.read(sampleGID).xyz;
            float albedoWeight = exp(
                -denoiseColorDistance(centerAlbedo, sampleAlbedo) / (2.0f * albedoSigmaSquared)
            );

            float colorWeight = exp(
                -denoiseColorDistance(centerBeauty.xyz, sampleBeauty.xyz) / (2.0f * colorSigmaSquared)
            );

            float weight = spatialWeight * normalWeight * depthWeight * albedoWeight * colorWeight;
            weightedColor += sampleBeauty.xyz * weight;
            totalWeight += weight;
        }
    }

    float3 denoised = totalWeight > 0.0f ? weightedColor / totalWeight : centerBeauty.xyz;
    denoised = mix(centerBeauty.xyz, denoised, 0.85f);
    denoisedBeauty.write(float4(denoised, centerBeauty.w), gid);
}

kernel void packSVGFDepthNormalKernel(
    texture2d<float, access::read> depth [[texture(0)]],
    texture2d<float, access::read> normal [[texture(1)]],
    texture2d<float, access::write> depthNormal [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= depthNormal.get_width() || gid.y >= depthNormal.get_height()) {
        return;
    }

    float4 depthValue = depth.read(gid);
    float4 encodedNormal = normal.read(gid);
    if (encodedNormal.w <= 0.0001f || !isfinite(depthValue.x) || depthValue.x <= 0.0f) {
        depthNormal.write(float4(1.0e6f, 0.0f, 0.0f, 1.0f), gid);
        return;
    }

    float3 signedNormal = normalize(encodedNormal.xyz * 2.0f - 1.0f);
    depthNormal.write(float4(depthValue.x, signedNormal), gid);
}

kernel void copySVGFOutputKernel(
    texture2d<float, access::read> denoised [[texture(0)]],
    texture2d<float, access::read> original [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    float4 filtered = denoised.read(gid);
    if (!all(isfinite(filtered.xyz))) {
        filtered = original.read(gid);
    }
    float originalAlpha = original.read(gid).w;
    output.write(float4(max(filtered.xyz, float3(0.0f)), originalAlpha), gid);
}
