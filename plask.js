// Plask.
// (c) Dean McNamee <dean@gmail.com>, 2010.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.

var sys = require('sys');
var events = require('events');
var inherits = sys.inherits;

exports.SkPath = PlaskRawMac.SkPath;
exports.SkPaint = PlaskRawMac.SkPaint;
exports.SkCanvas = PlaskRawMac.SkCanvas;

var kPI  = 3.14159265358979323846264338327950288;
var kPI2 = 1.57079632679489661923132169163975144;
var kPI4 = 0.785398163397448309615660845819875721;
var k2PI = 6.28318530717958647692528676655900576;

function min(a, b) {
  if (a < b) return a;
  return b;
}

function max(a, b) {
  if (a > b) return a;
  return b;
}

// Keep the value |v| in the range vmin .. vmax.  This matches GLSL clamp().
function clamp(v, vmin, vmax) {
  return min(vmax, max(vmin, v));
}

// Linear interpolation on the line along points (0, |a|) and (1, |b|).  The
// position |t| is the x coordinate, where 0 is |a| and 1 is |b|.
function lerp(a, b, t) {
  return a + (b-a)*t;
}

PlaskRawMac.NSOpenGLContext.prototype.vertexAttrib1fv = function(idx, seq) {
  this.vertexAttrib1f(idx, seq[0]);
};

PlaskRawMac.NSOpenGLContext.prototype.vertexAttrib2fv = function(idx, seq) {
  this.vertexAttrib2f(idx, seq[0], seq[1]);
};

PlaskRawMac.NSOpenGLContext.prototype.vertexAttrib3fv = function(idx, seq) {
  this.vertexAttrib3f(idx, seq[0], seq[1], seq[2]);
};

PlaskRawMac.NSOpenGLContext.prototype.vertexAttrib4fv = function(idx, seq) {
  this.vertexAttrib4f(idx, seq[0], seq[1], seq[2], seq[3]);
};

var flipper_paint = new exports.SkPaint;
flipper_paint.setXfermodeMode(flipper_paint.kSrcMode);

PlaskRawMac.NSOpenGLContext.prototype.texImage2DSkCanvas = function(a, b, c) {
  var width = c.width, height = c.height;
  var flipped = new exports.SkCanvas(width, height);
  flipped.translate(0, height);
  flipped.scale(1, -1);
  flipped.drawCanvas(flipper_paint, c, 0, 0, width, height);
  return this.texImage2DSkCanvasB(a, b, flipped);
};

PlaskRawMac.NSOpenGLContext.prototype.texImage2DSkCanvasNoFlip = function() {
  return this.texImage2DSkCanvasB.apply(this, arguments);
};

function MidiSource(name) {
  name = name === undefined ? 'Plask' : name;
  this.casource_ = new PlaskRawMac.CAMIDISource(name);
}

MidiSource.prototype.sendData = function(bytes) {
  return this.casource_.sendData(bytes);
};

MidiSource.prototype.noteOn = function(chan, note, vel) {
  return this.sendData([0x90 | (chan & 0xf), note & 0x7f, vel & 0x7f]);
};

MidiSource.prototype.noteOff = function(chan, note, vel) {
  return this.sendData([0x80 | (chan & 0xf), note & 0x7f, vel & 0x7f]);
};

function MidiDestination(name) {
  name = name === undefined ? 'Plask' : name;
  this.cadest_ = new PlaskRawMac.CAMIDIDestination(name);
}

MidiDestination.prototype.syncClocks = function() {
  return this.cadest_.syncClocks();
};

exports.MidiSource = MidiSource;
exports.MidiDestination = MidiDestination;

exports.Window = function(width, height, opts) {
  var nswindow_ = new PlaskRawMac.NSWindow(
      opts.type === '3d' ? 1 : 0,
      width, height,
      opts.multisample === true,
      opts.fullscreen_display === undefined ? -1 : opts.fullscreen_display);
  var this_ = this;

  this.context = nswindow_.context;  // Export the 3d context (if it exists).

  this.width = width; this.height = height;

  // About mouse buttons.  One day it will be important to have consistent
  // numbering across platforms.  We name from base 1:
  //  1 left
  //  2 right
  //  3 middle
  //  ... Others (figure out wheel, etc).
  function buttonNumberToName(numBaseOne) {
    switch (numBaseOne) {
      case 1: return 'left';
      case 2: return 'right';
      case 3: return 'middle';
      default: return 'button' + numBaseOne;
    }
  }

  this.setTitle = function(title) {
    nswindow_.setTitle(title);
  }

  // This is quite noisy on the event loop if you don't need it.
  //nswindow_.setAcceptsMouseMovedEvents(true);

  function nsEventNameToEmitName(nsname) {
    switch (nsname) {
      case PlaskRawMac.NSEvent.NSLeftMouseUp: return 'leftMouseUp';
      case PlaskRawMac.NSEvent.NSLeftMouseDown: return 'leftMouseDown';
      case PlaskRawMac.NSEvent.NSRightMouseUp: return 'rightMouseUp';
      case PlaskRawMac.NSEvent.NSRightMouseDown: return 'rightMouseDown';
      case PlaskRawMac.NSEvent.NSOtherMouseUp: return 'otherMouseUp';
      case PlaskRawMac.NSEvent.NSOtherMouseDown: return 'otherMouseDown';
      case PlaskRawMac.NSEvent.NSLeftMouseDragged: return 'leftMouseDragged';
      case PlaskRawMac.NSEvent.NSRightMouseDragged: return 'rightMouseDragged';
      case PlaskRawMac.NSEvent.NSOtherMouseDragged: return 'otherMouseDragged';
      case PlaskRawMac.NSEvent.NSKeyUp: return 'keyUp';
      case PlaskRawMac.NSEvent.NSKeyDown: return 'keyDown';
      case PlaskRawMac.NSEvent.NSScrollWheel: return 'scrollWheel';
      default: return '';
    }
  }

  this.setMouseMovedEnabled = function(enabled) {
    nswindow_.setAcceptsMouseMovedEvents(enabled);
  };

  this.setFileDragEnabled = function(enabled) {
    nswindow_.setAcceptsFileDrag(enabled);
  };

  this.setFrameTopLeftPoint = function(x, y) {
    nswindow_.setFrameTopLeftPoint(x, y);
  };

  function handleRawNSEvent(e) {
    var type = e.type();
    if (0) {
    sys.puts("event: " + type);
    for (var key in e) {
      if (e[key] === type) sys.puts(key);
    }
    }

    switch (type) {
      case PlaskRawMac.NSEvent.NSLeftMouseDown:
      case PlaskRawMac.NSEvent.NSLeftMouseUp:
      case PlaskRawMac.NSEvent.NSRightMouseDown:
      case PlaskRawMac.NSEvent.NSRightMouseUp:
      case PlaskRawMac.NSEvent.NSOtherMouseDown:
      case PlaskRawMac.NSEvent.NSOtherMouseUp:
        var mods = e.modifierFlags();
        var loc = e.locationInWindow();
        var button = e.buttonNumber() + 1;  // We work starting from 1.
        var type_name = nsEventNameToEmitName(type);
        // We want to also emit middleMouseUp, etc, but NS buckets it as other.
        if (button === 3) type_name = type_name.replace('other', 'middle');
        var te = {
          type: type_name,
          x: loc.x,
          y: height - loc.y,  // Map from button left to top left.
          buttonNumber: button,
          buttonName: buttonNumberToName(button),
          capslock: (mods & e.NSAlphaShiftKeyMask) !== 0,
          shift: (mods & e.NSShiftKeyMask) !== 0,
          ctrl: (mods & e.NSControlKeyMask) !== 0,
          option: (mods & e.NSAlternateKeyMask) !== 0,
          cmd: (mods & e.NSCommandKeyMask) !== 0
        };
        // Filter out clicks on the title bar.
        if (te.y < 0) break;
        // Emit the specific per-button event.
        this_.emit(te.type, te);
        // Emit a generic up / down event for all buttons.
        this_.emit(te.type.substr(-2) === 'Up' ? 'mouseUp' : 'mouseDown', te);
        break;
      case PlaskRawMac.NSEvent.NSLeftMouseDragged:
      case PlaskRawMac.NSEvent.NSRightMouseDragged:
      case PlaskRawMac.NSEvent.NSOtherMouseDragged:
        var mods = e.modifierFlags();
        var loc = e.locationInWindow();
        var button = e.buttonNumber() + 1;  // We work starting from 1.
        var type_name = nsEventNameToEmitName(type);
        // We want to also emit middleMouseUp, etc, but NS buckets it as other.
        if (button === 3) type_name = type_name.replace('other', 'middle');
        var te = {
          type: type_name,
          x: loc.x,
          y: height - loc.y,
          dx: e.deltaX(),
          dy: e.deltaY(),  // Doesn't need flipping since it's in device space.
          dz: e.deltaZ(),
          buttonNumber: button,
          buttonName: buttonNumberToName(button),
          capslock: (mods & e.NSAlphaShiftKeyMask) !== 0,
          shift: (mods & e.NSShiftKeyMask) !== 0,
          ctrl: (mods & e.NSControlKeyMask) !== 0,
          option: (mods & e.NSAlternateKeyMask) !== 0,
          cmd: (mods & e.NSCommandKeyMask) !== 0
        };
        // TODO(deanm): This is wrong if the drag started in the content view.
        if (te.y < 0) break;
        // Emit the specific per-button event.
        this_.emit(te.type, te);
        // Emit a generic up / down event for all buttons.
        this_.emit('mouseDragged', te);
        break;
      case PlaskRawMac.NSEvent.NSKeyUp:
      case PlaskRawMac.NSEvent.NSKeyDown:
        var mods = e.modifierFlags();
        var te = {
          type: nsEventNameToEmitName(type),
          str: e.characters(),
          keyCode: e.keyCode(),  // I'll probably regret this.
          capslock: (mods & e.NSAlphaShiftKeyMask) !== 0,
          shift: (mods & e.NSShiftKeyMask) !== 0,
          ctrl: (mods & e.NSControlKeyMask) !== 0,
          option: (mods & e.NSAlternateKeyMask) !== 0,
          cmd: (mods & e.NSCommandKeyMask) !== 0
        };
        this_.emit(te.type, te);
        break;
      case PlaskRawMac.NSEvent.NSMouseMoved:
        var loc = e.locationInWindow();
        var te = {
          type: 'mouseMoved',
          x: loc.x,
          y: height - loc.y,
          dx: e.deltaX(),
          dy: e.deltaY(),  // Doesn't need flipping since it's in device space.
          dz: e.deltaZ()
        };
        this_.emit(te.type, te);
        break;
      case PlaskRawMac.NSEvent.NSScrollWheel:
        var mods = e.modifierFlags();
        var loc = e.locationInWindow();
        var te = {
          type: 'scrollWheel',
          x: loc.x,
          y: height - loc.y,
          dx: e.deltaX(),
          dy: e.deltaY(),  // Doesn't need flipping since it's in device space.
          dz: e.deltaZ(),
          capslock: (mods & e.NSAlphaShiftKeyMask) !== 0,
          shift: (mods & e.NSShiftKeyMask) !== 0,
          ctrl: (mods & e.NSControlKeyMask) !== 0,
          option: (mods & e.NSAlternateKeyMask) !== 0,
          cmd: (mods & e.NSCommandKeyMask) !== 0
        };
        this_.emit(te.type, te);
        break;
      default:
        break;
    }
  }

  // Handle events coming from the native layer.
  nswindow_.setEventCallback(function(msgtype, msgdata) {
    // Since emit is synchronous, we need to catch any exceptions that might
    // happen during event handlers.
    try {
      if (msgtype === 0) {  // Cocoa NSEvent.
        handleRawNSEvent(msgdata);
      } else if (msgtype === 1) {  // File drag.
        this_.emit('filesDropped', msgdata);
      }
    } catch(ex) {
      sys.puts(ex.stack);
    }
  });

  this.getRelativeMouseState = function() {
    var res = nswindow_.mouseLocationOutsideOfEventStream();
    res.y = height - res.y;  // Map from Desktop OSX bottom left to top left.
    var buttons = PlaskRawMac.NSEvent.pressedMouseButtons();
    for (var i = 0; i < 6; ++i) {
      res[buttonNumberToName(i + 1)] = ((buttons >> i) & 1) === 1;
    }
    return res;
  };

  this.makeWindowBackedCanvas = function() {
    return new PlaskRawMac.SkCanvas(nswindow_);
  };

  this.blit = function() {
    nswindow_.blit();
  };
};
inherits(exports.Window, events.EventEmitter);

exports.simpleWindow = function(obj) {
  var wintype = obj.type === '3d' ? '3d' : '2d';
  var width = obj.width === undefined ? 400 : obj.width;
  var height = obj.height === undefined ? 300 : obj.height;

  // TODO(deanm): Fullscreen.
  var window_ = new exports.Window(
      width, height, {type: wintype,
                      multisample: obj.multisample === true,
                      fullscreen_display: obj.fullscreen_display});

  var gl_ = window_.context;

  obj.window = window_;
  obj.width = width;
  obj.height = height;

  if (obj.title !== undefined)
    window_.setTitle(obj.title);

  if (obj.position !== undefined)
    window_.setFrameTopLeftPoint(obj.position.x, obj.position.y);

  obj.getRelativeMouseState = function() {
    return window_.getRelativeMouseState();
  };

  if (wintype === '3d') {
    obj.gl = gl_;
    if (obj.vsync === true)
      gl_.setSwapInterval(1);
  } else {
    obj.paint = new exports.SkPaint;
    obj.canvas = window_.makeWindowBackedCanvas();
  }

  var framerate_handle = null;
  obj.framerate = function(fps) {
    if (framerate_handle !== null)
      clearInterval(framerate_handle);
    framerate_handle = setInterval(function() {
      obj.redraw();
    }, 1000 / fps);
  }

  // Export listener API so you can "this.on" instead of "this.window.on".
  obj.on = function(e, listener) {
    // TODO(deanm): Do this properly
    if (e === 'mouseMoved')
      window_.setMouseMovedEnabled(true);
    if (e === 'filesDropped')
      window_.setFileDragEnabled(true);
    var this_ = this;
    return window_.on(e, function() {
      return listener.apply(this_, arguments);
    });
  };

  obj.removeListener = function(e, listener) {
    return window_.removeListener(e, listener);
  };

  this.getRelativeMouseState = function() {
    return window_.getRelativeMouseState();
  };

  // Call init as early as possible, to give the init routine a chance to
  // setup anything on the object it might want to do at runtime.
  if ('init' in obj) {
    try {
      obj.init();
    } catch (ex) {
      sys.error('Exception caught in simpleWindow init:\n' +
                ex + '\n' + ex.stack);
    }
  }

  var draw = null;
  if ('draw' in obj)
    draw = obj.draw;

  obj.redraw = function() {
    if (gl_ !== undefined)
      gl_.makeCurrentContext();
    if (draw !== null) {
      try {
        obj.draw();
      } catch (ex) {
        sys.error('Exception caught in simpleWindow draw:\n' +
                  ex + '\n' + ex.stack);
      }
    }
    window_.blit();  // Update the screen automatically.
  };

  obj.redraw();  // Draw the first frame.

  return obj;
};

// A class representing a 3 dimensional point and/or vector.  There isn't a
// good reason to differentiate between the two, and you often want to change
// how you think about the same set of values.  So there is only "vector".
//
// The class is designed without accessors or individual mutators, you should
// access the x, y, and z values directly on the object.
//
// Almost all of the core operations happen in place, writing to the current
// object.  If you want a copy, you can call dup().  For convenience, many
// operations have a passed-tense version that returns a new object.  Most
// methods return this to support chaining.
function Vec3(x, y, z) {
  this.x = x; this.y = y; this.z = z;
}

Vec3.prototype.set = function(x, y, z) {
  this.x = x; this.y = y; this.z = z;

  return this;
};

Vec3.prototype.setVec3 = function(v) {
  this.x = v.x; this.y = v.y; this.z = v.z;

  return this;
};

// Cross product, this = a x b.
Vec3.prototype.cross2 = function(a, b) {
  var ax = a.x, ay = a.y, az = a.z,
      bx = b.x, by = b.y, bz = b.z;

  this.x = ay * bz - az * by;
  this.y = az * bx - ax * bz;
  this.z = ax * by - ay * bx;

  return this;
};

// Cross product, this = this x b.
Vec3.prototype.cross = function(b) {
  return this.cross2(this, b);
};

// Returns the dot product, this . b.
Vec3.prototype.dot = function(b) {
  return this.x * b.x + this.y * b.y + this.z * b.z;
};

// Add two Vec3s, this = a + b.
Vec3.prototype.add2 = function(a, b) {
  this.x = a.x + b.x;
  this.y = a.y + b.y;
  this.z = a.z + b.z;

  return this;
};

Vec3.prototype.added2 = function(a, b) {
  return new Vec3(a.x + b.x,
                  a.y + b.y,
                  a.z + b.z);
};

// Add a Vec3, this = this + b.
Vec3.prototype.add = function(b) {
  return this.add2(this, b);
};

Vec3.prototype.added = function(b) {
  return this.added2(this, b);
};

// Subtract two Vec3s, this = a - b.
Vec3.prototype.sub2 = function(a, b) {
  this.x = a.x - b.x;
  this.y = a.y - b.y;
  this.z = a.z - b.z;

  return this;
};

Vec3.prototype.subbed2 = function(a, b) {
  return new Vec3(a.x - b.x,
                  a.y - b.y,
                  a.z - b.z);
};

// Subtract another Vec3, this = this - b.
Vec3.prototype.sub = function(b) {
  return this.sub2(this, b);
};

Vec3.prototype.subbed = function(b) {
  return this.subbed2(this, b);
};

// Multiply by a scalar.
Vec3.prototype.scale = function(s) {
  this.x *= s; this.y *= s; this.z *= s;

  return this;
};

Vec3.prototype.scaled = function(s) {
  return new Vec3(this.x * s, this.y * s, this.z * s);
};

// Interpolate between this and another Vec3 |b|, based on |t|.
Vec3.prototype.lerp = function(b, t) {
  this.x = this.x + (b.x-this.x)*t;
  this.y = this.y + (b.y-this.y)*t;
  this.z = this.z + (b.z-this.z)*t;

  return this;
};

// Magnitude (length).
Vec3.prototype.length = function() {
  var x = this.x, y = this.y, z = this.z;
  return Math.sqrt(x*x + y*y + z*z);
};

// Magnitude squared.
Vec3.prototype.lengthSquared = function() {
  var x = this.x, y = this.y, z = this.z;
  return x*x + y*y + z*z;
};

// Normalize, scaling so the magnitude is 1.  Invalid for a zero vector.
Vec3.prototype.normalize = function() {
  return this.scale(1/this.length());
};

Vec3.prototype.normalized = function() {
  return this.dup().normalize();
};


Vec3.prototype.dup = function() {
  return new Vec3(this.x, this.y, this.z);
};

Vec3.prototype.debugString = function() {
  return 'x: ' + this.x + ' y: ' + this.y + ' z: ' + this.z;
};

exports.kPI  = kPI;
exports.kPI2 = kPI2;
exports.kPI4 = kPI4;
exports.k2PI = k2PI;

exports.min = min;
exports.max = max;
exports.clamp = clamp;
exports.lerp = lerp;

exports.Vec3 = Vec3;
