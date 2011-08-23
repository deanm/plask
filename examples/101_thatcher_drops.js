// (c) Thatcher Ulrich

var plask = require('plask');

// *Symmetric* sigmoid, range: [-1,1]
function sigmoid(x) {
  return (1 / (1 + Math.exp(-x))) * 2 - 1;
}

var G = 1/1000000;
var F = 1/1000;
var P = 2;

function envelope(t) {
  return G * Math.pow(t, P) / (1 + Math.exp(t * F));
}


var particles = [];
var MAX_PARTICLES = 100;
function init_particles() {
  for (var i = 0; i < MAX_PARTICLES; i++) {
    particles.push({x: 0, y: 0, w: 0, a: 0, r: 0, g: 0, b: 0, t: 100 });
  }
}
init_particles();
var next_particle = 0;

var PARTICLE_LIFE = 50;

function emit_particle(x, y) {
  if (particles.length >= MAX_PARTICLES) {
    next_particle = (next_particle + 1) % MAX_PARTICLES;
  }
  var p = particles[next_particle];

  p.x = x;
  p.y = y;
  p.w = 50;
  p.r = (Math.random() * 255) >> 0;
  p.g = (Math.random() * 255) >> 0;
  p.b = (Math.random() * 255) >> 0;
  p.a = (Math.random() * 255) >> 0;
  p.t = 0;
}

function draw_particles(canvas, paint) {
  for (var i = 0; i < particles.length; i++) {
    var p = particles[i];
    if (p.t < PARTICLE_LIFE) {
      var radius = sigmoid(envelope(p.t * 100)) * 200 + 1;

      paint.setColor(p.r, p.g, p.b, p.a);
      canvas.drawCircle(paint, p.x, p.y, radius /*p.w*/);

      // Update
      p.a *= 0.9;
      p.w *= 0.93;
      p.y += 5 + Math.random() * 10;
      p.x += (Math.random() - 0.5) * 10;
      p.t++;
    }
  }
}

plask.simpleWindow({
  settings: {
    width: 800,
    height: 600
  },

  init: function() {
    var canvas = this.canvas, paint = this.paint;

    this.framerate(60);

    canvas.clear(100, 100, 100, 255);  // Initial background.
    paint.setAntiAlias(true);
    paint.setXfermodeMode(paint.kPlusMode);  // Additive blending.

    this.mousedown = false;
    this.mouse_x = 0;
    this.mouse_y = 0;

    this.on('leftMouseDown', function(e) {
      this.mousedown = true;
      this.mouse_x = e.x;
      this.mouse_y = e.y;
    });
    this.on('leftMouseDragged', function(e) {
      this.mouse_x = e.x;
      this.mouse_y = e.y;
    });
    this.on('leftMouseUp', function(e) {
      this.mousedown = false;
    });
  },

  draw: function draw() {
    var canvas = this.canvas, paint = this.paint;

    canvas.drawColor(100, 100, 100, 10);  // Blur.

    if (this.mousedown)
      emit_particle(this.mouse_x, this.mouse_y);
    draw_particles(canvas, paint);
  }
});
