// Plask.
// (c) Dean McNamee <dean@gmail.com>, 2010.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.

var plask = require('plask');

// Math code from pre3d.
function dotProduct2d(a, b) {
  return a.x * b.x + a.y * b.y;
}
// a - b
function subPoints2d(a, b) {
  return {x: a.x - b.x, y: a.y - b.y};
}
// a + b
function addPoints2d(a, b) {
  return {x: a.x + b.x, y: a.y + b.y};
}
// a * s
function mulPoint2d(a, s) {
  return {x: a.x * s, y: a.y * s};
}
// a * b
function mulPoints2d(a, b) {
  return {x: a.x * b.x, y: a.y * b.y};
}
// |a|
function vecMag2d(a) {
  var ax = a.x, ay = a.y;
  return Math.sqrt(ax * ax + ay * ay);
}
// |a|
function vecMagSquared2d(a) {
  var ax = a.x, ay = a.y;
  return ax * ax + ay * ay;
}
// a / |a|
function unitVector2d(a) {
  return mulPoint2d(a, 1 / vecMag2d(a));
}

function reflect(u, n) {
  // r = u - 2(u.n)n
  return subPoints2d(u, mulPoint2d(n, dotProduct2d(u, n) * 2));
}

// Integer between 0 and max (but not including max).
function irand(max) {
  return (Math.random() * max) >> 0;
}

function Ball(position, direction, color) {
  this.p = position;
  this.d = direction;
  this.c = color;
}

function Explosion(position) {
  this.p = position;
  this.r = 0;  // Current radius.
}

var kBallRadius = 7;
var kExplosionRadius = 30;

var balls = Array(30);
for (var i = 0, il = balls.length; i < il; ++i) {
  var p = {x: irand(400 - kBallRadius * 4) + kBallRadius * 2, 
           y: irand(300 - kBallRadius * 4) + kBallRadius * 2};
  var d = unitVector2d({x: Math.random() - 0.5, y: Math.random() - 0.5});
  balls[i] = new Ball(p, d, {r: irand(255),
                             g: irand(255),
                             b: irand(255),
                             a: 128});
}

var explosions = [ ];

function step(dt) {
  for (var i = 0, il = balls.length; i < il; ++i) {
    var ball = balls[i];
    ball.p = addPoints2d(mulPoint2d(ball.d, dt / 5), ball.p);
  }

  // Collision detection.  Our circle all have a constant radius, so this
  // is pretty easy.  You can just picture the collision box inset from the
  // screen by the radius, so we are just collisioning the center point.
  for (var i = 0, il = balls.length; i < il; ++i) {
    var ball = balls[i];
    if (ball.p.x < kBallRadius) {
      ball.d = reflect(ball.d, {x: 1, y: 0});
    } else if (ball.p.x > (400 - kBallRadius)) {
      ball.d = reflect(ball.d, {x: -1, y: 0});
    }

    if (ball.p.y < kBallRadius) {
      ball.d = reflect(ball.d, {x: 0, y: 1});
    } else if (ball.p.y > (300 - kBallRadius)) {
      ball.d = reflect(ball.d, {x: 0, y: -1});
    }
  }

  // Grow / remove dead explosions.
  for (var i = 0, il = explosions.length; i < il; ++i) {
    var ex = explosions[i];
    ex.r += (dt / 20);
  }

  // We modify explosions in this loop, so we need to check length each time.
  for (var i = 0; i < explosions.length; ++i) {
    var ex = explosions[i];
    // TODO(deanm): This could be done a lot better by just swapping the
    // last entry of the array and removing that.
    if (ex.r > kExplosionRadius) {
      explosions.splice(i, 1);
      --i;
    }
  }

  // Check to see if any balls should be turned into explosions.
  for (var i = 0, il = explosions.length; i < il; ++i) {
    var ex = explosions[i];
    var dist2 = (ex.r + kBallRadius) * (ex.r + kBallRadius);
    // TODO(deanm): n^2... doom.
    // We modify balls in this loop, so we need to check length each time.
    for (var j = 0; j < balls.length; ++j) {
      var ball = balls[j];
      if (vecMagSquared2d(subPoints2d(ball.p, ex.p)) < dist2) {
        // TODO(deanm): We could just tag the ball as dead, that would be
        // simpler and wouldn't require any array shifting.
        balls.splice(j, 1);
        // We cached explosion length, so we can append to it for next update.
        explosions.push(new Explosion(ball.p));
      }
    }
  }
}

// Global paint settings, set them once.
var ball_paint = new plask.SkPaint;
ball_paint.setStyle(ball_paint.kFillStyle);
//ball_paint.setPorterDuffMode(ball_paint.kAddMode);
ball_paint.setFlags(ball_paint.kAntiAliasFlag);

plask.simpleWindow({
  width: 400,
  height: 300,

  init: function() {
    this.framerate(60);
    this.on('leftMouseDown', function(e) {
      // Only allow you to add an explosion if there are no others happening.
      if (explosions.length === 0)
        explosions.push(new Explosion({x: e.x, y: e.y}));
    });
  },

  draw: function() {
    var canvas = this.canvas, paint = this.paint;
    step(1000 / 60);

    // Clear the canvas.
    paint.setStyle(paint.kFillStyle);
    paint.setColor(0, 0, 0, 255);
    canvas.drawPaint(paint);

    // Draw balls.
    for (var i = 0, il = balls.length; i < il; ++i) {
      var ball = balls[i];
      ball_paint.setColor(ball.c.r, ball.c.g, ball.c.b, ball.c.a);
      canvas.drawCircle(ball_paint, ball.p.x, ball.p.y, kBallRadius);
    }

    // Draw explosions.
    for (var i = 0, il = explosions.length; i < il; ++i) {
      var ex = explosions[i];
      ball_paint.setColor(255, 140, 0, 128);
      canvas.drawCircle(ball_paint, ex.p.x, ex.p.y, ex.r);
    }
  }
});
