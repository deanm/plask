//
// A Plask example, painting images where they are dropped onto the window.
//

var plask = require('plask');

plask.simpleWindow({
  settings: {
    width: 800,
    height: 600
  },

  init: function() {
    var canvas = this.canvas, paint = this.paint;

    this.image = null;
    this.image_pos = {x: 0, y: 0};

    this.on('filesDropped', function(e) {
      // Multiple files can be dropped at once, but for this example only the
      // first file is used.
      this.image = plask.SkCanvas.createFromImage(e.paths[0]);
      this.image_pos.x = e.x; this.image_pos.y = e.y;
      this.redraw();
    });

    canvas.clear(230, 230, 230, 255);  // Draw the background, just once.
  },

  draw: function() {
    var canvas = this.canvas, paint = this.paint;
    if (this.image !== null) {
      var p = this.image_pos;
      canvas.drawCanvas(paint, this.image,
                        p.x, p.y,
                        p.x + this.image.width, p.y + this.image.height);
    }
  }
});
