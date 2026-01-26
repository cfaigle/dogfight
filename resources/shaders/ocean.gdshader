shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec3 deep_color : source_color = vec3(0.02, 0.08, 0.18);
uniform vec3 glow_color : source_color = vec3(0.10, 0.30, 0.42);
uniform float wave_amp = 0.55;
uniform float wave_scale = 0.085;
uniform float wave_speed = 0.55;
uniform float fresnel = 2.5;

float hash(vec2 p){
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}
float noise(vec2 p){
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f*f*(3.0-2.0*f);
    return mix(a, b, u.x) + (c - a)*u.y*(1.0 - u.x) + (d - b)*u.x*u.y;
}

void vertex(){
    vec3 p = VERTEX;
    float t = TIME * wave_speed;
    float n = noise(p.xz * wave_scale + vec2(t, -t));
    float n2 = noise(p.xz * wave_scale * 2.0 + vec2(-t*1.7, t*1.2));
    p.y += (n*0.65 + n2*0.35 - 0.5) * wave_amp;
    VERTEX = p;
}

void fragment(){
    float ndv = clamp(dot(normalize(NORMAL), normalize(-VIEW)), 0.0, 1.0);
    float f = pow(1.0 - ndv, fresnel);
    vec3 col = mix(deep_color, glow_color, f);
    ALBEDO = col;
    EMISSION = col * 0.18;
    ALPHA = 1.0;
}
