// (c) dean@gmail.com

uniform mat4 u_p;  // Projection.
uniform mat4 u_mv;  // Model view.

varying vec3 v_norm;

attribute vec2 a_theta_phi;

void main() {
  float theta = a_theta_phi.x;
  float phi = a_theta_phi.y;
  float r = 1.0;
  
  // The mathy defintion is based on +Z pointing "up", but the graphicsy
  // definition would be +Y (and our texure maps follow this).  Keep a right
  // handed coordinate system and map XYZ -> YZX.
  vec4 pos = vec4(r * sin(theta) * sin(phi),  // Math-Y
                  r * cos(theta),             // Math-Z
                  r * sin(theta) * cos(phi),  // Math-X
                  1.0);

  // Map to eye space and project.
  gl_Position = u_p * u_mv * pos;
  v_norm = (u_mv * pos).xyz;
}
