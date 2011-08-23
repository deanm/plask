// (c) Ryan Alexander

var plask = require('plask');

function Particle(pos) {
  this.pos = pos.dup();
  this.vel = new plask.Vec2(0, 0);
  this.bias = Math.sqrt(Math.random()) * (Math.random() < 0.5 ? -1 : 1);
}

Particle.prototype = {
  update: function() {
    this.pos.add(this.vel);
  },
  damp: function(damping) {
    this.vel.scale(damping);
  },
  gravity: function(center, pow, mindist) {
    var xo = center.x - this.pos.x;
    var yo = center.y - this.pos.y;
    var dist = Math.sqrt(xo*xo + yo*yo);
    var force = pow / Math.max(dist, mindist);
    this.vel.add({
      x: force * xo / dist,
      y: force * yo / dist
    });
  },
  orbit: function(center, pow) {
    var xo = this.pos.x - center.x;
    var yo = this.pos.y - center.y;
    var dist = Math.sqrt(xo*xo + yo*yo);
    var force = pow / dist;
    this.vel.add({
      x: force * -yo / dist,
      y: force * xo / dist
    });
  }
};

var dots = [];

plask.simpleWindow({
  settings: {
    width: 1000,
    height: 600
  },

  init: function() {
    var canvas = this.canvas, paint = this.paint;

    canvas.clear(0, 0, 0, 255);
    paint.setAntiAlias(true);
    paint.setXfermodeMode(paint.kPlusMode);

    this.framerate(60);

    this.mouse_down = false;
    this.mouse_pos = new plask.Vec2(0, 0);

    this.on('leftMouseDown', function(e) {
      this.mouse_down = true;
      this.mouse_pos.set(e.x, e.y);
    });
    this.on('leftMouseDragged', function(e) {
      this.mouse_pos.set(e.x, e.y);
    });
    this.on('leftMouseUp', function(e) {
      this.mouse_down = false;
    });
      
    while (dots.length < 1000) {
      var p = new Particle(new plask.Vec2(
        Math.random() * this.width,
        Math.random() * this.height
      ));
      p.vel.add({
        x: Math.random() * 2 - 1,
        y: Math.random() * 2 - 1
      });
      dots.push(p);
    }
  },

  draw: function() {
    var canvas = this.canvas, paint = this.paint;

    canvas.clear(0, 0, 0, 255);
    
    paint.setFill();
    paint.setXfermodeMode(paint.kPlusMode);

    for (var i = dots.length; --i >= 0;) {
      var dot = dots[i];
      dot.gravity(this.mouse_pos, 150, 10);
      dot.orbit(this.mouse_pos, dot.bias * 150);
      dot.update();
      dot.damp(0.95);
      var u = Math.min(1, dot.vel.length() / 15);
      var b = plask.lerp(0, 255, Math.abs(dot.bias));
      paint.setColor(b, b, 255, plask.lerp(0, 64, u));
      canvas.drawCircle(paint,
        dot.pos.x,
        dot.pos.y,
        plask.lerp(20, 2, u)
      );
    }
  }
});
