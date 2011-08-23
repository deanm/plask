// Plask.
// (c) Dean McNamee <dean@gmail.com>, 2011.
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

// Given a list of points, fit a cubic bezier path smoothly through them.
function pointsToCatmullPath(points, path) {
  for (var i = 3, il = points.length; i < il; ++i) {
    var p0 = points[i - 3];
    var p1 = points[i - 2];
    var p2 = points[i - 1];
    var p3 = points[i]

    if (i === 3) path.moveTo(p1.x, p1.y);

    // Change of basis from Catmull-Rom to Bezier.
    // See Pyramid Algorithms by Ron Goldman.
    var c0x = (p2.x / 6) + p1.x - (p0.x / 6);
    var c0y = (p2.y / 6) + p1.y - (p0.y / 6);
    var c1x = (p3.x / -6) + p2.x + p1.x / 6;
    var c1y = (p3.y / -6) + p2.y + p1.y / 6;

    path.cubicTo(c0x, c0y, c1x, c1y, p2.x, p2.y);
  }
  return path;
}

plask.simpleWindow({
  settings: {
    width: 400,
    height: 300
  },

  init: function() {
    this.framerate(30);
    var canvas = this.canvas, paint = this.paint;

    paint.setAntiAlias(true);
    paint.setStroke();
    paint.setStrokeWidth(2);
    paint.setColor(255, 0, 255, 255);

    this.path = new plask.SkPath();  // A path to reuse each draw().

    var midi = new plask.MidiIn();  // Create a midi output.
    var sources = midi.sources();
    if (sources.length === 0)
      throw "No available MIDI sources.";
    midi.openSource(sources.length - 1);
    console.log('Using midi source: ' + sources[sources.length - 1]);

    // In order to animate, keep two sets of states.  What the current value is
    // and what it should be going towards.
    var cur_vel = Array(128);
    var dst_vel = Array(128);
    for (var i = 0, il = cur_vel.length; i < il; ++i)
      cur_vel[i] = dst_vel[i] = 0;

    this.cur_vel = cur_vel;
    this.dst_vel = dst_vel;

    midi.on('noteOn', function(e) {
      dst_vel[e.note] = e.vel / 127;
    });

    midi.on('noteOff', function(e) {
      dst_vel[e.note] = 0;
    });

    canvas.translate(this.width / 2, this.height / 2);  // Center at (0, 0).
  },

  draw: function() {
    var canvas = this.canvas, paint = this.paint, path = this.path;
    var cur_vel = this.cur_vel, dst_vel = this.dst_vel;

    var points = Array(128);
    for (var i = 0, il = points.length; i < il; ++i) {
      // Calculate the polar point.
      var theta = i / il * plask.k2PI;
      var r = cur_vel[i] * 100 + 50;
      var x = Math.cos(theta) * r, y = Math.sin(theta) * r;
      points[i] = {x: x, y: y};

      // Animate (interpolate) between previous state and where we want to be.
      cur_vel[i] = plask.lerp(cur_vel[i], dst_vel[i], 0.1);
    }

    // Since Catmull-Rom needs a point of context on each side, the path we
    // make wouldn't include the first or last segment.  Since we want it to
    // close and loop completely, duplicate the first 3 points at the end.
    points.push(points[0], points[1], points[2]);

    canvas.clear(0, 0, 0, 255);

    path.rewind();
    pointsToCatmullPath(points, path);
    path.close();  // Not really needed, but shouldn't hurt anything either.
    canvas.drawPath(paint, path);
  }
});
