//
// A simple Plask example, drawing a red circle on a gray background centered
// where the mouse was clicked.
//

var plask = require('plask');

plask.simpleWindow({
  init: function() {
    var canvas = this.canvas, paint = this.paint;

    // Keep track of where we want to draw the circle.
    this.center = {x: canvas.width/2, y: canvas.height/2};

    // Plask follows the event emitter conventions of Node.  The simpleWindow
    // object can be listened on for mouse and keyboard events.
    this.on('leftMouseDown', function(e) {
      this.center.x = e.x;
      this.center.y = e.y;
      // Since framerate() wasn't called, there is no draw timer set.  The
      // draw() method call and screen update will only happen when we
      // explicitly call redraw().
      this.redraw();
    });

    paint.setFill();
    paint.setAntiAlias(true);
    paint.setColor(80, 0, 0, 255);
  },

  draw: function() {
    var canvas = this.canvas, paint = this.paint;
    canvas.clear(230, 230, 230, 255);
    canvas.drawCircle(paint, this.center.x, this.center.y, 100);
  }
});
