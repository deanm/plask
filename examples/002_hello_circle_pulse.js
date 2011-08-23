//
// A simple Plask example, drawing a pulsing red circle on a gray background.
//

var plask = require('plask');

plask.simpleWindow({
  init: function() {
    var canvas = this.canvas, paint = this.paint;

    // The call to framerate() sets up how often the screen should be redrawn.
    // By default, the value is 0, and the screen is only drawn once during
    // initialization, and then any time when redraw() is called.  The value
    // is the number of frames that should be drawn every second.
    this.framerate(30);

    paint.setFill();
    paint.setAntiAlias(true);
    paint.setColor(80, 0, 0, 255);
  },

  draw: function() {
    var canvas = this.canvas, paint = this.paint;

    canvas.clear(230, 230, 230, 255);

    // The frametime property is automatically computed by simpleWindow(), and
    // contains the number of seconds since the window was created.
    var t = Math.sin(this.frametime) * 0.5 + 0.5;

    // The lerp function performs a linear interpolation between two values.
    // By cycling the value of the interpolation between 0 and 1, the radius
    // will cycle between 50 and 100 pixels.
    var radius = plask.lerp(50, 100, t);

    // The canvas object contains its width and height, which can be used to
    // compute the x and y coordinates of the center of the canvas.
    canvas.drawCircle(paint, canvas.width/2, canvas.height/2, radius);
  }
});
