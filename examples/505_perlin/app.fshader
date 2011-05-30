// 3d perlin noise implementation, based on GPU Gems 2 implementation by Green.
// (c) dean@gmail.com

uniform sampler2D u_permgrad_tex;
uniform sampler2D u_perm2d_tex;

varying vec3 v_norm;

vec3 fade(vec3 t) {
  return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);  // new curve
}

vec4 perm2d(vec2 p) {
  return texture2D(u_perm2d_tex, p);
}

float gradperm(float x, vec3 p) {
  return dot(texture2D(u_permgrad_tex, vec2(x, 0.0)).xyz * 2.0 - 1.0, p);
}

// 3D noise
// optimized version
float inoise(vec3 p) {
  vec3 P = mod(floor(p), 256.0);   // FIND UNIT CUBE THAT CONTAINS POINT
  p -= floor(p);                   // FIND RELATIVE X,Y,Z OF POINT IN CUBE
  vec3 f = fade(p);                // COMPUTE FADE CURVES FOR EACH OF X,Y,Z

  P = P / 256.0;
  const float one = 1.0 / 256.0;

  // HASH COORDINATES OF THE 8 CUBE CORNERS
  vec4 AA = perm2d(P.xy) + P.z;

  // AND ADD BLENDED RESULTS FROM 8 CORNERS OF CUBE
  return mix(mix(mix(gradperm(AA.x, p),
                     gradperm(AA.z, p + vec3(-1, 0, 0)), f.x),
                 mix(gradperm(AA.y, p + vec3(0, -1, 0)),
                     gradperm(AA.w, p + vec3(-1, -1, 0)), f.x), f.y),

             mix(mix(gradperm(AA.x+one, p + vec3(0, 0, -1)),
                     gradperm(AA.z+one, p + vec3(-1, 0, -1)), f.x),
                 mix(gradperm(AA.y+one, p + vec3(0, -1, -1)),
                     gradperm(AA.w+one, p + vec3(-1, -1, -1)), f.x), f.y), f.z);
}

void main() {
  float n = (inoise(v_norm) + inoise(v_norm * 5.0)*0.07) * 0.5 + 0.5;
  n *= 1.1;  // Small boost towards white.
  gl_FragColor = vec4(n, n, n, 1.0);
}
