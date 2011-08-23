//
// A simple Plask example, drawing a red circle on a gray background centered
// where the mouse is moved.
//

var plask = require('plask');

plask.simpleWindow({
  init: function() {
    var canvas = this.canvas, paint = this.paint;

    this.center = {x: canvas.width/2, y: canvas.height/2};

    // It can be a bad idea to draw every time mouse event is received,
    // especially for mouse move events which can happen very frequently.
    // This example runs a normal framerate timer instead of calling redraw().
    this.framerate(30);

    // Note that it can be troublesome to listen for mouseMoved as it
    // potentially generates a large amount of events.
    this.on('mouseMoved', function(e) {
      // Note that the mouse coordinates can go outside the window bounds.
      // Also note that when this example is first launched, the circle will
      // be centered even if the mouse is not, because a mouseMoved event will
      // not be received until the mouse is moved.
      this.center.x = e.x;
      this.center.y = e.y;
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
