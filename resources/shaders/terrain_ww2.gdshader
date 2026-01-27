shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float sea_level = 0.0;

// World-space tuning
uniform float field_size = 160.0;   // meters-ish
uniform float road_step = 700.0;
uniform float road_width = 14.0;
uniform bool show_road_grid = false;

// Texture tiling scale (meters per texture repeat)
uniform float texture_scale = 32.0;

// External textures (optional - if not set, falls back to procedural colors)
uniform sampler2D grass_texture : hint_default_white;
uniform sampler2D pavement_texture : hint_default_white;
uniform bool use_textures = false;

// Palette
uniform vec3 grass_a : source_color = vec3(0.18, 0.28, 0.15);
uniform vec3 grass_b : source_color = vec3(0.24, 0.34, 0.18);
uniform vec3 crop_a  : source_color = vec3(0.36, 0.36, 0.20);
uniform vec3 crop_b  : source_color = vec3(0.30, 0.26, 0.16);
uniform vec3 hedge_c : source_color = vec3(0.05, 0.08, 0.04);

uniform vec3 road_c  : source_color = vec3(0.10, 0.10, 0.11);
uniform vec3 town_c  : source_color = vec3(0.18, 0.18, 0.20);
uniform vec3 rock_c  : source_color = vec3(0.30, 0.30, 0.31);
uniform vec3 water_c : source_color = vec3(0.06, 0.12, 0.17);

varying vec3 wpos;
varying float n0;
varying float slope;

float hash12(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));

    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    // Godot 4.x expects mat2 constructed from 2 vec2 columns (GLSL-style).
    mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
    for (int i = 0; i < 4; i++) {
        v += a * noise2(p);
        p = m * p;
        a *= 0.5;
    }
    return v;
}

void vertex() {
    wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    n0 = fbm(wpos.xz * 0.002);
    vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    slope = 1.0 - clamp(abs(wn.y), 0.0, 1.0);
}

void fragment() {
    vec2 p = wpos.xz;

    // Texture coordinates for tiling
    vec2 uv = p / texture_scale;

    // Sample textures if available
    vec3 grass_tex = vec3(1.0);
    vec3 pavement_tex = vec3(1.0);
    if (use_textures) {
        grass_tex = texture(grass_texture, uv).rgb;
        pavement_tex = texture(pavement_texture, uv).rgb;
    }

    // Patchwork fields (stable per cell)
    vec2 cell = floor(p / field_size);
    float h = hash12(cell);

    // Blend procedural colors with textures
    vec3 grass = mix(grass_a, grass_b, smoothstep(0.15, 0.85, h));
    vec3 crop  = mix(crop_a,  crop_b,  smoothstep(0.15, 0.85, 1.0 - h));
    vec3 base_color  = mix(grass, crop, smoothstep(0.55, 0.75, h));

    // Apply grass texture with procedural color tint
    vec3 base = base_color;
    if (use_textures) {
        base = mix(grass_tex, grass_tex * base_color, 0.4); // Reduce tinting significantly
    }

    // Hedgerows near field edges (DISABLED - too visible)
    // vec2 f = fract(p / field_size);
    // float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
    // float hedge = smoothstep(0.015, 0.0, edge);
    vec3 col = base;  // No hedgerows

    // Roads: mostly a coarse grid + a main highway (optional, controlled by show_road_grid)
    float road = 0.0;
    if (show_road_grid) {
        float gx = abs(fract(p.x / road_step) - 0.5) * road_step;
        float gz = abs(fract(p.y / road_step) - 0.5) * road_step;
        road = 1.0 - smoothstep(road_width, road_width + 12.0, min(gx, gz));

        // A couple of long "highways" for orientation
        float hw1 = 1.0 - smoothstep(18.0, 28.0, abs(p.x + 1200.0));
        float hw2 = 1.0 - smoothstep(18.0, 28.0, abs(p.y - 900.0));
        road = max(road, max(hw1, hw2) * 0.85);
    }

    // Apply road texture or procedural color
    vec3 road_col = road_c;
    if (use_textures) {
        road_col = pavement_tex * road_c * 1.5;
    }
    col = mix(col, road_col, road);

    // Town speckle near roads (optimized: simple hash instead of FBM)
    vec2 town_p = floor(p * 0.01 + vec2(4.2, 1.7));
    float town = smoothstep(0.67, 0.80, fract(sin(dot(town_p, vec2(12.9898, 78.233))) * 43758.5453)) * road;
    col = mix(col, town_c, town * 0.85);

    // Rock on steeper slopes / higher altitude
    float high = smoothstep(80.0, 150.0, wpos.y);
    float rock = high * smoothstep(0.18, 0.75, slope);
    col = mix(col, rock_c, rock);

    // Water tint near/below sea level
    float wet = smoothstep(sea_level - 5.0, sea_level + 2.0, wpos.y);
    col = mix(water_c, col, wet);

    // Subtle texture break-up
    col *= (0.92 + 0.10 * n0);

    ALBEDO = col;
    ROUGHNESS = 0.95;
    METALLIC = 0.0;
}
