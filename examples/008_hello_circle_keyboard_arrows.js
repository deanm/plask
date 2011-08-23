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
    title: "Move with the AWSD or arrow keys."
  },
  
  init: function() {
    var canvas = this.canvas, paint = this.paint;

    this.center = {x: canvas.width/2, y: canvas.height/2};

    this.on('keyDown', function(e) {
      // NOTE: The function keys are mapped into the private unicode area
      // 0xf700 by AppKit, see NSUpArrowFunctionKey and friends.
      switch (e.str) {
        case '\uf700': case 'w': case 'W':
          this.center.y -= e.shift ? 10 : 1; break;
        case '\uf701': case 's': case 'S':
          this.center.y += e.shift ? 10 : 1; break;
        case '\uf702': case 'a': case 'A':
          this.center.x -= e.shift ? 10 : 1; break;
        case '\uf703': case 'd': case 'D':
          this.center.x += e.shift ? 10 : 1; break;
      }

      // An alternative to the unicode |str| property is the low-level key
      // code.  This has different semantics, for example, an 'A' key with
      // shift held is the same code as without shift held.  Key codes are raw
      // identifiers of the keyboard, and generally you should use the |str|
      // property instead to account for keyboard layout and language.
      //
      // The keyCode version looks something like:
      //
      // switch (e.keyCode) {
      //   case 126: case 13: this.center.y -= e.shift ? 10 : 1; break;
      //   case 125: case 1: this.center.y += e.shift ? 10 : 1; break;
      //   case 123: case 0: this.center.x -= e.shift ? 10 : 1; break;
      //   case 124: case 2: this.center.x += e.shift ? 10 : 1; break;
      // }
      
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
