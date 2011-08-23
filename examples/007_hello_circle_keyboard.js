//
// A simple Plask example, drawing a red circle on a gray background centered
// where the mouse is moved.
//

var plask = require('plask');

plask.simpleWindow({
  // Introducing the settings object, which allows you to set things like the
  // window width and height, title, window type and configuration, etc.
  settings: {
    width: 400,
    height: 300,
    title: "Move with the AWSD keys."
  },
  
  init: function() {
    var canvas = this.canvas, paint = this.paint;

    this.center = {x: canvas.width/2, y: canvas.height/2};

    this.on('keyDown', function(e) {
      // The |str| property on the key event is a string of the unicode
      // translation of the key.  Take bigger steps while holding shift.
      switch (e.str) {
        case 'w': this.center.y -= 1; break;
        case 'W': this.center.y -= 10; break;
        case 's': this.center.y += 1; break;
        case 'S': this.center.y += 10; break;
        case 'a': this.center.x -= 1; break;
        case 'A': this.center.x -= 10; break;
        case 'd': this.center.x += 1; break;
        case 'D': this.center.x += 10; break;
      }
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
