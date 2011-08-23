//
// A simple Plask example, drawing a red circle on a gray background centered
// where the mouse is dragged and springing back to the center when let go.
//

var plask = require('plask');

plask.simpleWindow({
  init: function() {
    var canvas = this.canvas, paint = this.paint;

    this.center = {x: canvas.width/2, y: canvas.height/2};
    this.mouse_down = false;

    this.framerate(30);  // Run constantly for computing animations.

    function updatePosition(e) {
      this.center.x = e.x;
      this.center.y = e.y;
      this.mouse_down = true;
      // Don't redraw since a framerate timer is running.
    }

    // leftMouseClicked is only called once on a click, and not again if the
    // mouse is moved while clicked.  leftMouseDragged is not called for the
    // initial click, but is called when the mouse is moved when the button is
    // held.  Listen on both to get click and drag.  Dragging can return
    // positions outside the window bounds.
    this.on('leftMouseDown', updatePosition);
    this.on('leftMouseDragged', updatePosition);
    this.on('leftMouseUp', function(e) {
      this.mouse_down = false;
    });

    paint.setFill();
    paint.setAntiAlias(true);
    paint.setColor(80, 0, 0, 255);
  },

  draw: function() {
    var canvas = this.canvas, paint = this.paint;
    canvas.clear(230, 230, 230, 255);
    canvas.drawCircle(paint, this.center.x, this.center.y, 100);
    if (this.mouse_down === false) {
      // Not proper physics, but a simple non-linear tween.
      this.center.x = plask.lerp(this.center.x, canvas.width/2, 0.3);
      this.center.y = plask.lerp(this.center.y, canvas.height/2, 0.3);
    }
  }
});
