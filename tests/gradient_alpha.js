// Test that a linear gradient with alpha is written out to a PNG and read
// back correctly.  This is a bit tricky because Skia uses premultiplied
// alpha but PNG doesn't.  The conversion generally will not be exact.

var plask = require('plask');

var canvas = plask.SkCanvas.create(200, 200);
var paint = new plask.SkPaint();
paint.setLinearGradientShader(0, 100, 200, 100, [0, 255, 0, 0, 255, 1, 255, 0, 0, 0]);
canvas.drawRect(paint, 0, 0, 200, 200);

canvas.writeImage('png', 'gradient_alpha.png');

var canvas2 = plask.SkCanvas.createFromImage('gradient_alpha.png');

for (var i = 0, il = 200 * 200 * 4; i < il; ++i) {
  var Δ = Math.abs(canvas[i] - canvas2[i]);
  if (Δ != 0) throw 'Error in pixel, difference: ' + Δ;
}
