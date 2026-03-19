shader_type spatial;
//render_mode blend_premul_alpha;

uniform float scale_0 : hint_range(0.01, 1024, 0.01);
uniform float scale_1 : hint_range(0.01, 1024, 0.01);

uniform float line_scale_0 : hint_range(0.001, 1, 0.001);
uniform float line_scale_1 : hint_range(0.001, 1, 0.001);
uniform float bg_alpha : hint_range(0.0, 1);

uniform vec4 color_0 : source_color;
uniform vec4 color_1 : source_color;


float pristineGrid( vec2 uv, vec2 lineWidth) {
    vec2 ddx = dFdx(uv);
    vec2 ddy = dFdy(uv);

    vec2 uvDeriv = vec2(length(vec2(ddx.x, ddy.x)), length(vec2(ddx.y, ddy.y)));
    bvec2 invertLine = bvec2(lineWidth.x > 0.5, lineWidth.y > 0.5);

    vec2 targetWidth = vec2(
      invertLine.x ? 1.0 - lineWidth.x : lineWidth.x,
      invertLine.y ? 1.0 - lineWidth.y : lineWidth.y
      );

    vec2 drawWidth = clamp(targetWidth, uvDeriv, vec2(0.5));
    vec2 lineAA = uvDeriv * 1.5;
    vec2 gridUV = abs(fract(uv) * 2.0 - 1.0);

    gridUV.x = invertLine.x ? gridUV.x : 1.0 - gridUV.x;
    gridUV.y = invertLine.y ? gridUV.y : 1.0 - gridUV.y;

    vec2 grid2 = smoothstep(drawWidth + lineAA, drawWidth - lineAA, gridUV);

    grid2 *= clamp(targetWidth / drawWidth, 0.0, 1.0);
    grid2 = mix(grid2, targetWidth, clamp(uvDeriv * 2.0 - 1.0, 0.0, 1.0));
    grid2.x = invertLine.x ? 1.0 - grid2.x : grid2.x;
    grid2.y = invertLine.y ? 1.0 - grid2.y : grid2.y;
    return mix(grid2.x, 1.0, grid2.y);
}

varying vec2 v;

//void vertex() {
 //v = VERTEX;
//}

void fragment() {
  vec2 uv = UV;
  vec4 grid_0 = vec4(pristineGrid(uv * float(scale_0), vec2(line_scale_0)));
  vec4 grid_1 = vec4(pristineGrid(uv * float(scale_1), vec2(line_scale_1)));
  //ALBEDO.a = bg_alpha;
  vec3 bg = vec3(0.0);
  ALBEDO.rgb = mix(bg.rgb, color_0.rgb, grid_0.rgb);
  ALBEDO.rgb = mix(bg.rgb, color_1.rgb, grid_1.rgb);
}