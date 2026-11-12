#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// Distance fog for the arena. RealityKit has no fog, so every arena material is converted to a
// CustomMaterial running this surface shader: a stand-in for PhysicallyBasedMaterial (same
// textures and constants) that then fades the surface towards the fog colour with distance.
//
// custom_parameter = (fog r, g, b, density). density 0 = no fog.
// Fog amount f = 1 - exp(-density * distance), thinned with height so it hugs the ground.
// The surface keeps (1 - f) of its colour and specular; the fog colour is added as emission,
// so it reads as lit mist whatever the lights are doing.
[[visible]]
void fogSurface(realitykit::surface_parameters params)
{
    constexpr sampler s(coord::normalized, address::repeat, filter::linear, mip_filter::linear);

    auto tex = params.textures();
    auto surface = params.surface();
    auto consts = params.material_constants();
    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;   // USD textures are flipped

    half4 colour = tex.base_color().sample(s, uv);
    half3 base = colour.rgb * half3(consts.base_color_tint());
    half3 emissive = max(tex.emissive_color().sample(s, uv).rgb, half3(consts.emissive_color()));
    half opacity = tex.opacity().sample(s, uv).r * consts.opacity_scale() * colour.a;
    half3 normal = realitykit::unpack_normal(tex.normal().sample(s, uv).rgb);
    half rough = tex.roughness().sample(s, uv).r * consts.roughness_scale();
    half metal = tex.metallic().sample(s, uv).r * consts.metallic_scale();
    half spec = tex.specular().sample(s, uv).r * consts.specular_scale();
    half ao = tex.ambient_occlusion().sample(s, uv).r;

    float4 fog = params.uniforms().custom_parameter();
    float3 world = params.geometry().world_position();
    float3 view = (params.uniforms().world_to_view() * float4(world, 1)).xyz;
    float dist = length(view);
    float heightFade = exp(-max(world.y, 0.0) / 18.0);          // thinner higher up
    float f = clamp(1.0 - exp(-fog.w * dist * heightFade), 0.0, 0.97);
    half k = half(1.0 - f);

    surface.set_base_color(base * k);
    surface.set_emissive_color(emissive * k + half3(fog.rgb) * half(f));
    surface.set_opacity(opacity);
    surface.set_normal(float3(normal));
    surface.set_roughness(rough);
    surface.set_metallic(metal * k);
    surface.set_specular(spec * k);
    surface.set_ambient_occlusion(ao);
}
