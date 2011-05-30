// (c) dean@gmail.com

uniform mat4 u_p;  // Projection.
uniform mat4 u_mv;  // Model view.

attribute vec3 a_xyz;

void main() {
  gl_Position = u_p * u_mv * vec4(a_xyz, 1.0);
}
