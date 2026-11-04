#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct InstanceData {
    float4x4 model;
    float4 color;
};

struct Uniforms {
    float4x4 viewProjection;
    float4 lightDirection;   // xyz: direction towards the light
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float4 color;
};

constant float kAmbient = 0.3;

vertex VertexOut cube_vertex(VertexIn in [[stage_in]],
                             constant Uniforms &uniforms [[buffer(1)]],
                             device const InstanceData *instances [[buffer(2)]],
                             uint instanceID [[instance_id]]) {
    InstanceData instance = instances[instanceID];

    VertexOut out;
    out.position = uniforms.viewProjection * (instance.model * float4(in.position, 1.0));
    // The model matrix is rotation + translation only, so it can transform normals directly.
    out.normal = (instance.model * float4(in.normal, 0.0)).xyz;
    out.color = instance.color;
    return out;
}

fragment float4 cube_fragment(VertexOut in [[stage_in]],
                              constant Uniforms &uniforms [[buffer(1)]]) {
    float diffuse = max(dot(normalize(in.normal), normalize(uniforms.lightDirection.xyz)), 0.0);
    float light = kAmbient + (1.0 - kAmbient) * diffuse;
    return float4(in.color.rgb * light, 1.0);
}
