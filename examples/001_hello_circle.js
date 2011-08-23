//
// A simple Plask example, drawing a red circle on a gray background.
//

// Plask follows the CommonJS specification for module loading.
var plask = require('plask');

plask.simpleWindow({
  init: function() {
    // The canvas is the drawing object, attached to the screen.
    // The paint holds the drawing settings: color, sizes, stoke/fill, etc.
    var canvas = this.canvas, paint = this.paint;

    // Set the paint to fill an anti-aliased dark red.
    paint.setFill();  // Fill is the default, so this is just for clarity.
    paint.setAntiAlias(true);
    paint.setColor(80, 0, 0, 255);
  },

  draw: function() {
    var canvas = this.canvas, paint = this.paint;

    // Draw the light gray background.
    canvas.clear(230, 230, 230, 255);

    // By default our window will be 400x300, so our center is at 200x150.
    // Using the settings on our paint set above, draw a circle of radius 100px.
    canvas.drawCircle(paint, 200, 150, 100);
  }
});
