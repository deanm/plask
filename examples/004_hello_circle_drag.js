//
// A simple Plask example, drawing a red circle on a gray background centered
// where the mouse is dragged.
//

var plask = require('plask');

plask.simpleWindow({
  init: function() {
    var canvas = this.canvas, paint = this.paint;

    this.center = {x: canvas.width/2, y: canvas.height/2};

    function updatePosition(e) {
      this.center.x = e.x;
      this.center.y = e.y;
      this.redraw();
    }

    // leftMouseClicked is only called once on a click, and not again if the
    // mouse is moved while clicked.  leftMouseDragged is not called for the
    // initial click, but is called when the mouse is moved when the button is
    // held.  Listen on both to get click and drag.  Dragging can return
    // positions outside the window bounds.
    this.on('leftMouseDown', updatePosition);
    this.on('leftMouseDragged', updatePosition);

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
