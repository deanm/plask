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

var balls;

function initializeBalls() {
  balls = Array(30);
  for (var i = 0, il = balls.length; i < il; ++i) {
    var p = new plask.Vec2(irand(400 - kBallRadius * 4) + kBallRadius * 2,
                           irand(300 - kBallRadius * 4) + kBallRadius * 2);

    var d = new plask.Vec2(Math.random() - 0.5, Math.random() - 0.5);
    d.normalize();

    // NOTE: You can be unlucky and get a completely black ball.  Good luck :)
    balls[i] = new Ball(p, d, {r: irand(255),
                               g: irand(255),
                               b: irand(255),
                               a: 128});
  }
}

initializeBalls();

var explosions = [ ];

function step(dt) {
  for (var i = 0, il = balls.length; i < il; ++i) {
    var ball = balls[i];
    ball.p.add(ball.d.scaled(dt / 5));
  }

  // Collision detection.  Our circles all have a constant radius, so this
  // is pretty easy.  You can just picture the collision box inset from the
  // screen by the radius, so we are just collisioning the center point.
  for (var i = 0, il = balls.length; i < il; ++i) {
    var ball = balls[i];
    if (ball.p.x < kBallRadius) {
      ball.d.reflect(new plask.Vec2(1, 0));
    } else if (ball.p.x > (400 - kBallRadius)) {
      ball.d.reflect(new plask.Vec2(-1, 0));
    }

    if (ball.p.y < kBallRadius) {
      ball.d.reflect(new plask.Vec2(0, 1));
    } else if (ball.p.y > (300 - kBallRadius)) {
      ball.d.reflect(new plask.Vec2(0, -1));
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
    // TODO(deanm): This could be done better by just swapping the last entry
    // of the array and removing that.  Not really performance critical.
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
      if (ball.p.distSquared(ex.p) < dist2) {
        // TODO(deanm): We could just tag the ball as dead, that would be
        // simpler and wouldn't require any array shifting.
        balls.splice(j, 1);
        // We cached explosion length, so we can append to it for next update.
        explosions.push(new Explosion(ball.p));
      }
    }
  }
}

plask.simpleWindow({
  settings: {
    width: 400,
    height: 300
  },

  init: function() {
    this.framerate(60);
    this.on('leftMouseDown', function(e) {
      // Only allow you to add an explosion if there are no others happening.
      if (explosions.length === 0)
        explosions.push(new Explosion({x: e.x, y: e.y}));
    });

    // Global paint settings, set them once.
    var ball_paint = new plask.SkPaint;
    ball_paint.setStyle(ball_paint.kFillStyle);
    ball_paint.setFlags(ball_paint.kAntiAliasFlag);
    this.ball_paint = ball_paint;
  },

  draw: function() {
    var canvas = this.canvas, paint = this.paint, ball_paint = this.ball_paint;
    step(1000 / 60);  // Constant time step physics, not the best way to do it.

    canvas.clear(0, 0, 0, 255);  // Black background.

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

    if (balls.length === 0 && explosions.length === 0) {
      // Start another game.
      initializeBalls();
    }
  }
});
