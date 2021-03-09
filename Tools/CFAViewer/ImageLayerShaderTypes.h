static_assert(__METAL_VERSION__, "Only usable from Metal shader context");

struct VertexOutput {
    float4 pos [[position]];
    float2 posUnit;
};
