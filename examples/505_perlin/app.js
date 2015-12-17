// (c) dean@gmail.com

var plask = require('plask');

// From PreGL:
// Generate a 2-component triangle strip of a 2 dimensional grid.
//
// If you were to draw a bad ascii diagram of a 3 column by 2 row
// tessellation, it would look something like this.  Y increase down starting
// at |start_y| and ending at |end_y|.  X increase right  from |start_x| to
// |end_x|.  The triangles are in counter-clockwise order, facing out of the
// page.
//         __ __ __ 
//     Y  | /| /| /|
//        |/ |/ |/ |
//     |   -- -- -- 
//     V  |\ |\ |\ |
//        | \| \| \|
//         -- -- -- 
//         X  ->
//
function makeTristripGrid2D(start_y, end_y, num_rows,
                            start_x, end_x, num_columns) {
  // Every row takes 2 points per cell, plus an extra point at the end.
  // The first row takes an additional point.  Every point is 2 components.
  var fa = new Float32Array((num_columns * 4 + 2) * num_rows + 2);
  var y_step = (end_y - start_y) / num_rows;
  var pos_x_step = (end_x - start_x) / num_columns;
  var neg_x_step = -pos_x_step;

  // You could see the algorithm looking like this.  You have a grid of
  // quads, each quad is divided into two triangles by a diagonal.  The
  // diagonal switches direction every row, as we zig back and forth every
  // row.  So the first row starts at start_x and ends at end_x, and the next
  // row starts at end_x, and ends and start_x.  For every row, we start by
  // omiting the first point at the start of the first diagonal.  For every
  // cell we are just emiting a vertical line, forming the diagonal connection
  // across the face inbetween the vertical lines.  These vertical lines are
  // the edge of the cell, going towards which every direction we as zagging.

  var y0 = start_y, y1 = start_y;
  for (var i = 0, k = 0; i < num_rows; ++i) {
    y0 = y1; y1 += y_step;

    // Swap the direction, we zig zag every row.
    var x0 = (i & 1) === 0 ? start_x : end_x;
    var x_step = (i & 1) === 0 ? pos_x_step : neg_x_step;

    // For the first row, we have to emit an extra point, the first point.
    if (i === 0) { fa[k++] = y0; fa[k++] = x0; }
    fa[k++] = y1; fa[k++] = x0;  // The starting point of the first diagonal.

    for (var j = 0; j < num_columns; ++j) {
      x0 += x_step;
      fa[k++] = y0; fa[k++] = x0;
      fa[k++] = y1; fa[k++] = x0;
    }
  }

  return fa;
}


// Create the permutation tables that get loaded into the shaders as textures.
function makePerlinDataTextures(gl) {
  var kPermutation = [151,160,137,91,90,15,
    131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
    190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
    88,237,149,56,87,174,20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,
    77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
    102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,18,169,200,196,
    135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,
    5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
    223,183,170,213,119,248,152, 2,44,154,163, 70,221,153,101,155,167, 43,172,9,
    129,22,39,253, 19,98,108,110,79,113,224,232,178,185, 112,104,218,246,97,228,
    251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
    49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,
    138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180];

  var kGradient = [
    1,1,0,
    -1,1,0,
    1,-1,0,
    -1,-1,0,
    1,0,1,
    -1,0,1,
    1,0,-1,
    -1,0,-1, 
    0,1,1,
    0,-1,1,
    0,1,-1,
    0,-1,-1,
    1,1,0,
    0,-1,1,
    -1,1,0,
    0,-1,-1];
  for (var i = 0, il = kGradient.length; i < il; ++i)
    kGradient[i] = ((kGradient[i] + 1) * 127.5) >> 0;

  function perm(i) { return kPermutation[i & 0xff]; }

  var permgrad_canvas = new plask.SkCanvas(256, 1);
  var permgrad = permgrad_canvas.pixels;
  for (var x = 0; x < 256; ++x) {
    var i = (kPermutation[x] & 0xf) * 3;
    permgrad[x*4 + 2] = kGradient[i];      // R
    permgrad[x*4 + 1] = kGradient[i + 1];  // G
    permgrad[x*4]     = kGradient[i + 2];  // B
  }

  var permgrad_tex = gl.createTexture();
  gl.activeTexture(gl.TEXTURE0);
  gl.bindTexture(gl.TEXTURE_2D, permgrad_tex);
  gl.texImage2DSkCanvasNoFlip(gl.TEXTURE_2D, 0, permgrad_canvas);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);

  var perm2d_canvas = new plask.SkCanvas(256, 256);
  var perm2d = perm2d_canvas.pixels;
  for (var x = 0; x < 256; ++x) {
    for (var y = 0; y < 256; ++y) {
      var A = perm(x) + y;
      var AA = perm(A);
      var AB = perm(A + 1);
      var B =  perm(x + 1) + y;
      var BA = perm(B);
      var BB = perm(B + 1);
      perm2d[y*256*4 + x*4 + 2] = AA;  // R
      perm2d[y*256*4 + x*4 + 1] = AB;  // G
      perm2d[y*256*4 + x*4]     = BA;  // B
      perm2d[y*256*4 + x*4 + 3] = BB;  // A
    }
  }

  var perm2d_tex = gl.createTexture();
  gl.activeTexture(gl.TEXTURE1);
  gl.bindTexture(gl.TEXTURE_2D, perm2d_tex);
  gl.texImage2DSkCanvasNoFlip(gl.TEXTURE_2D, 0, perm2d_canvas);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
}


plask.simpleWindow({
  settings: {
    width: 800,
    height: 600,
    type: '3d',
    vsync: true,  // Prevent tearing.
    multisample: true  // Anti-alias.
  },

  init: function() {
    var gl = this.gl;

    this.mprogram = new plask.gl.MagicProgram.createFromBasename(
        gl, __dirname, 'app');

    // Create a 2d grid (xy) of theta and phi.  The vertex shader will map
    // these vertices to the 3d position on the sphere.
    function makeSphere() {
      var kEp = 0.000001;  // Create holes at the poles.
      var buffer = gl.createBuffer();
      var data = makeTristripGrid2D(kEp, plask.kPI-kEp, 72,
                                      0,    plask.k2PI, 72);
      // Bind in and load our data.
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
      gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
      return {buffer: buffer, num: data.length / 2};
    }

    this.sphere = makeSphere();
    makePerlinDataTextures(this.gl);

    this.framerate(60);
  },

  draw: function() {
    var gl = this.gl;
    var sphere = this.sphere;
    var mprogram = this.mprogram;
    var t = this.frametime * 50;

    gl.clearColor(0, 0, 0, 0);
    gl.enable(gl.DEPTH_TEST);
    gl.disable(gl.BLEND);

    gl.cullFace(gl.BACK);
    gl.enable(gl.CULL_FACE);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

    var mv = new plask.Mat4();
    mv.translate(0, 0, -10 + Math.sin(t/50));
    mv.rotate(t / 50, 0, 1, 0);
    mv.rotate(t / 79, 0, 0, 1);

    var persp = new plask.Mat4();
    persp.perspective(10, this.width / this.height, 0.01, 1000);

    mprogram.use();
    // Set the transformation matrices.
    mprogram.set_u_p(persp);
    mprogram.set_u_mv(mv);
    // Set the texture IDs.
    mprogram.set_u_permgrad_tex(0);
    mprogram.set_u_perm2d_tex(1);

    // Draw the grid geometry, which will be transformed to a sphere by the
    // vertex shader.
    gl.bindBuffer(gl.ARRAY_BUFFER, sphere.buffer);
    gl.vertexAttribPointer(mprogram.location_a_theta_phi,
                           2,
                           gl.FLOAT,
                           false, 0, 0);
    gl.enableVertexAttribArray(mprogram.location_a_theta_phi);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, sphere.num);
  }
});
