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
var fs = require('fs');
var path = require('path');
var events = require('events');
var dgram = require('dgram');
var inherits = sys.inherits;

exports.SkPath = PlaskRawMac.SkPath;
exports.SkPaint = PlaskRawMac.SkPaint;
exports.SkCanvas = PlaskRawMac.SkCanvas;

// NOTE(deanm): The SkCanvas constructor has become too complicated in
// supporting different types of canvases and ways to create them.  Use one of
// the following factory functions instead of calling the constructor directly.
exports.newSkCanvasFromImage = function(path) {
  return new exports.SkCanvas(path);
};

exports.newSkCanvasOfSize = function(width, height) {
  return new exports.SkCanvas(width, height);
};

exports.newSkCanvasBackedToNSWindow = function(nswindow) {
  return new exports.SkCanvas(nswindow);
};

// Sizes are in points, at 72 points per inch, letter would be 612x792.
// That makes A4 about 595x842.
// TODO(deanm): The sizes are integer, check the right size to use for A4.
exports.newPDFSkCanvas = function(page_width, page_height,
                                  content_width, content_height) {
  return new exports.SkCanvas(
      '%PDF',
      page_width, page_height,
      content_width === undefined ? page_width : content_width,
      content_height === undefined ? page_height : content_height);
};

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

// Test if |num| is a floating point -0.
function isNegZero(num) {
  return 1/num === -Infinity;
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
  var flipped = exports.newSkCanvasOfSize(width, height);
  flipped.translate(0, height);
  flipped.scale(1, -1);
  flipped.drawCanvas(flipper_paint, c, 0, 0, width, height);
  var result = this.texImage2DSkCanvasB(a, b, flipped);
  flipped.dispose();
  return result;
};

PlaskRawMac.NSOpenGLContext.prototype.texImage2DSkCanvasNoFlip = function() {
  return this.texImage2DSkCanvasB.apply(this, arguments);
};

// Depricated, use MidiOut.
function MidiSource(name) {
  name = name === undefined ? 'Plask' : name;
  this.casource_ = new PlaskRawMac.CAMIDISource();
  this.casource_.createVirtual(name);
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

// Pitch wheel takes a value between -1 .. 1, and will be mapped to 14-bit midi.
MidiSource.prototype.pitchWheel = function(chan, val) {
  var bits = clamp((val * 0.5 + 0.5) * 16384, 0, 16383);  // Not perfect at +1.
  return this.sendData([0xe0 | (chan & 0xf), bits & 0x7f, (bits >> 7) & 0x7f]);
};

MidiSource.prototype.controller = function(chan, con, val) {
  return this.sendData([0xb0 | (chan & 0xf), con & 0x7f, val & 0x7f]);
};

// Depricated, use MidiIn.
function MidiDestination(name) {
  name = name === undefined ? 'Plask' : name;
  this.cadest_ = new PlaskRawMac.CAMIDIDestination();
  this.cadest_.createVirtual(name);
}

MidiDestination.prototype.syncClocks = function() {
  return this.cadest_.syncClocks();
};

MidiDestination.prototype.setDgramPath = function(path) {
  return this.cadest_.setDgramPath(path);
};

exports.MidiSource = MidiSource;
exports.MidiDestination = MidiDestination;

exports.MidiIn = PlaskRawMac.CAMIDIDestination;
exports.MidiOut = PlaskRawMac.CAMIDISource;

inherits(PlaskRawMac.CAMIDIDestination, events.EventEmitter);

PlaskRawMac.CAMIDIDestination.prototype.on = function(evname, callback) {
  if (this._dgram_initialized !== true) {
    var path = '/tmp/plask_internal_midi_socket_' +
               process.pid + '_' + Date.now();
    var sock = dgram.createSocket('unix_dgram');
    sock.bind(path);
    var this_ = this;
    sock.on('message', function(msg, rinfo) {
      if (msg.length < 1) {
        console.log('Received zero length midi message.');
        return;
      }

      if ((msg[0] & 0x80) !== 0x80) {
        console.log('First MIDI byte not a status byte.');
        return;
      }

      // NOTE(deanm): We expect MIDI packets are the correct length, for
      // example 3 bytes for note on and off.  Instead of error checking, we'll
      // get undefined from msg[] if the message is shorter, maybe should
      // handle this better, but loads of length checking is annoying.
      switch (msg[0] & 0xf0) {
        case 0x90:  // Note on.
          this_.emit('noteOn', {type:'noteOn',
                                chan: msg[0] & 0x0f,
                                note: msg[1],
                                vel: msg[2]});
          break;
        case 0x80:  // Note off.
          this_.emit('noteOff', {type:'noteOff',
                                chan: msg[0] & 0x0f,
                                note: msg[1],
                                vel: msg[2]});
          break;
        case 0xb0:  // Controller message.
          this_.emit('controller', {type:'controller',
                                    chan: msg[0] & 0x0f,
                                    num: msg[1],
                                    val: msg[2]});
          break;
        default:
          console.log('Unhandled MIDI status byte: 0x' + msg[0].toString(16));
          break;
      }
    });
    this.setDgramPath(path);
    this._dgram_initialized = true;
  }

  events.EventEmitter.prototype.on.call(this, evname, callback);
};

exports.Window = function(width, height, opts) {
  var nswindow_ = new PlaskRawMac.NSWindow(
      opts.type === '3d' ? 1 : 0,
      width, height,
      opts.multisample === true,
      opts.display === undefined ? -1 : opts.display,
      opts.fullscreen === true);
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
      case PlaskRawMac.NSEvent.NSTabletPoint: return 'tabletPoint';
      case PlaskRawMac.NSEvent.NSTabletProximity: return 'tabletProximity';
      default: return '';
    }
  }

  this.setMouseMovedEnabled = function(enabled) {
    return nswindow_.setAcceptsMouseMovedEvents(enabled);
  };

  this.setFileDragEnabled = function(enabled) {
    return nswindow_.setAcceptsFileDrag(enabled);
  };

  this.setFrameTopLeftPoint = function(x, y) {
    return nswindow_.setFrameTopLeftPoint(x, y);
  };

  this.screenSize = function() {
    return nswindow_.screenSize();
  };

  this.hideCursor = function() {
    return nswindow_.hideCursor();
  };

  this.showCursor = function() {
    return nswindow_.showCursor();
  };

  this.center = function() {
    nswindow_.center();
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
          pressure: e.pressure(),
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
      case PlaskRawMac.NSEvent.NSTabletPoint:
        var mods = e.modifierFlags();
        var loc = e.locationInWindow();
        var te = {
          type: nsEventNameToEmitName(type),
          x: loc.x,
          y: height - loc.y,
          pressure: e.pressure(),
          capslock: (mods & e.NSAlphaShiftKeyMask) !== 0,
          shift: (mods & e.NSShiftKeyMask) !== 0,
          ctrl: (mods & e.NSControlKeyMask) !== 0,
          option: (mods & e.NSAlternateKeyMask) !== 0,
          cmd: (mods & e.NSCommandKeyMask) !== 0
        };
        this_.emit(te.type, te);
        break;
      case PlaskRawMac.NSEvent.NSTabletProximity:
        var te = {
          type: nsEventNameToEmitName(type),
          entering: e.isEnteringProximity()
        };
        this_.emit(te.type, te);
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
        var mods = e.modifierFlags();
        var loc = e.locationInWindow();
        var te = {
          type: 'mouseMoved',
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
    return exports.newSkCanvasBackedToNSWindow(nswindow_);
  };

  this.blit = function() {
    nswindow_.blit();
  };
};
inherits(exports.Window, events.EventEmitter);

exports.simpleWindow = function(obj) {
  // NOTE(deanm): Moving to a settings object to reduce the pollution of the
  // main simpleWindow object.  For now fall back for compat.
  var settings = obj.settings;
  if (settings === undefined) {
    settings = obj;
    if (obj.width !== undefined)
      console.log('Warning, using legacy settings, use the settings object.');
  }

  var wintype = (settings.type === '3d' || settings.type === '3d2d') ? '3d' :
                                                                       '2d';
  var width = settings.width === undefined ? 400 : settings.width;
  var height = settings.height === undefined ? 300 : settings.height;

  var syphon_server = null;

  // TODO(deanm): Fullscreen.
  var window_ = new exports.Window(
      width, height, {type: wintype,
                      multisample: settings.multisample === true,
                      display: settings.display,
                      fullscreen: settings.fullscreen});

  if (settings.position !== undefined) {
    var position_x = settings.position.x;
    var position_y = settings.position.y;
    if (position_y < 0 || isNegZero(position_y))
      position_y = window_.screenSize().height + position_y;
    if (position_x < 0 || isNegZero(position_x))
      position_x = window_.screenSize().width + position_x;
    window_.setFrameTopLeftPoint(position_x, position_y);
  } else if (settings.center !== false) {
    window_.center();
  }

  var gl_ = window_.context;

  // obj.window = window_;
  obj.width = width;
  obj.height = height;

  if (settings.title !== undefined)
    window_.setTitle(settings.title);

  obj.setTitle = function(title) { window_.setTitle(title); };

  if (settings.cursor === false)
    window_.hideCursor();

  obj.getRelativeMouseState = function() {
    return window_.getRelativeMouseState();
  };

  var canvas = null;  // Protected from getting clobbered on obj.

  if (wintype === '3d') {
    if (settings.vsync === true)
      gl_.setSwapInterval(1);
    if (settings.type === '3d') {  // Don't expose gl for 3d2d windows.
      obj.gl = gl_;
    } else {  // Create a canvas and paint for 3d2d windows.
      obj.paint = new exports.SkPaint;
      canvas = exports.newSkCanvasOfSize(width, height);  // Offscreen.
      obj.canvas = canvas;
    }
    if (obj.syphon_server !== undefined) {
      syphon_server = gl_.createSyphonServer(obj.syphon_server);
    }
  } else {
    obj.paint = new exports.SkPaint;
    canvas = window_.makeWindowBackedCanvas();
    obj.canvas = canvas;
  }

  var framerate_handle = null;
  obj.framerate = function(fps) {
    if (framerate_handle !== null)
      clearInterval(framerate_handle);
    if (fps === 0) return;
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
  var frameid = 0;
  var frame_start_time = Date.now();

  if ('draw' in obj)
    draw = obj.draw;

  obj.redraw = function() {
    if (gl_ !== undefined)
      gl_.makeCurrentContext();
    if (draw !== null) {
      obj.frameid = frameid;
      obj.frametime = (Date.now() - frame_start_time) / 1000;  // Secs.
      try {
        obj.draw();
      } catch (ex) {
        sys.error('Exception caught in simpleWindow draw:\n' +
                  ex + '\n' + ex.stack);
      }
      frameid++;
    }
    if (gl_ !== undefined && canvas !== null) {  // 3d2d
      // Blit to Syphon.
      if (syphon_server !== null && syphon_server.hasClients() === true) {
        if (syphon_server.bindToDrawFrameOfSize(width, height) === true) {
          gl_.drawSkCanvas(canvas);
          syphon_server.unbindAndPublish();
        } else {
          console.log('Error blitting for Syphon.');
        }
      }
      // Blit to the screen OpenGL context.
      gl_.drawSkCanvas(canvas);
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

// Add a Vec3, this = this + b.
Vec3.prototype.add = function(b) {
  return this.add2(this, b);
};

Vec3.prototype.added = function(b) {
  return new Vec3(this.x + b.x,
                  this.y + b.y,
                  this.z + b.z);
};

// Subtract two Vec3s, this = a - b.
Vec3.prototype.sub2 = function(a, b) {
  this.x = a.x - b.x;
  this.y = a.y - b.y;
  this.z = a.z - b.z;

  return this;
};

// Subtract another Vec3, this = this - b.
Vec3.prototype.sub = function(b) {
  return this.sub2(this, b);
};

Vec3.prototype.subbed = function(b) {
  return new Vec3(this.x - b.x,
                  this.y - b.y,
                  this.z - b.z);
};

// Multiply two Vec3s, this = a * b.
Vec3.prototype.mul2 = function(a, b) {
  this.x = a.x * b.x;
  this.y = a.y * b.y;
  this.z = a.z * b.z;

  return this;
};

// Multiply by another Vec3, this = this * b.
Vec3.prototype.mul = function(b) {
  return this.mul2(this, b);
};

Vec3.prototype.mulled = function(b) {
  return new Vec3(this.x * b.x,
                  this.y * b.y,
                  this.z * b.z);
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

Vec3.prototype.lerped = function(b, t) {
  return new Vec3(this.x + (b.x-this.x)*t,
                  this.y + (b.y-this.y)*t,
                  this.z + (b.z-this.z)*t);
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


// Like a z-less Vec3, Vec2.
function Vec2(x, y) {
  this.x = x; this.y = y;
}

Vec2.prototype.set = function(x, y) {
  this.x = x; this.y = y

  return this;
};

Vec2.prototype.setVec2 = function(v) {
  this.x = v.x; this.y = v.y;

  return this;
};

// Returns the dot product, this . b.
Vec2.prototype.dot = function(b) {
  return this.x * b.x + this.y * b.y;
};

// Add two Vec2s, this = a + b.
Vec2.prototype.add2 = function(a, b) {
  this.x = a.x + b.x;
  this.y = a.y + b.y;

  return this;
};

// Add a Vec2, this = this + b.
Vec2.prototype.add = function(b) {
  return this.add2(this, b);
};

Vec2.prototype.added = function(b) {
  return new Vec2(this.x + b.x,
                  this.y + b.y);
};

// Subtract two Vec2s, this = a - b.
Vec2.prototype.sub2 = function(a, b) {
  this.x = a.x - b.x;
  this.y = a.y - b.y;

  return this;
};

// Subtract another Vec2, this = this - b.
Vec2.prototype.sub = function(b) {
  return this.sub2(this, b);
};

Vec2.prototype.subbed = function(b) {
  return new Vec2(this.x - b.x,
                  this.y - b.y);
};

// Multiply two Vec2s, this = a * b.
Vec2.prototype.mul2 = function(a, b) {
  this.x = a.x * b.x;
  this.y = a.y * b.y;

  return this;
};

// Multiply by another Vec2, this = this * b.
Vec2.prototype.mul = function(b) {
  return this.mul2(this, b);
};

Vec2.prototype.mulled = function(b) {
  return new Vec2(this.x * b.x,
                  this.y * b.y);
};

// Multiply by a scalar.
Vec2.prototype.scale = function(s) {
  this.x *= s; this.y *= s;

  return this;
};

Vec2.prototype.scaled = function(s) {
  return new Vec2(this.x * s, this.y * s);
};

// Interpolate between this and another Vec2 |b|, based on |t|.
Vec2.prototype.lerp = function(b, t) {
  this.x = this.x + (b.x-this.x)*t;
  this.y = this.y + (b.y-this.y)*t;

  return this;
};

Vec2.prototype.lerped = function(b, t) {
  return new Vec2(this.x + (b.x-this.x)*t,
                  this.y + (b.y-this.y)*t);
};

// Magnitude (length).
Vec2.prototype.length = function() {
  var x = this.x, y = this.y;
  return Math.sqrt(x*x + y*y);
};

// Magnitude squared.
Vec2.prototype.lengthSquared = function() {
  var x = this.x, y = this.y;
  return x*x + y*y;
};

// Normalize, scaling so the magnitude is 1.  Invalid for a zero vector.
Vec2.prototype.normalize = function() {
  return this.scale(1/this.length());
};

Vec2.prototype.normalized = function() {
  return this.dup().normalize();
};

Vec2.prototype.dup = function() {
  return new Vec2(this.x, this.y);
};

Vec2.prototype.debugString = function() {
  return 'x: ' + this.x + ' y: ' + this.y;
};


// TODO(deanm): Vec4 is currently a skeleton container, it should match the
// features of Vec3.
function Vec4(x, y, z, w) {
  this.x = x; this.y = y; this.z = z; this.w = w;
}

Vec4.prototype.set = function(x, y, z, w) {
  this.x = x; this.y = y; this.z = z; this.w = w;

  return this;
};

Vec4.prototype.setVec4 = function(v) {
  this.x = v.x; this.y = v.y; this.z = v.z; this.w = v.w;

  return this;
};

Vec4.prototype.dup = function() {
  return new Vec4(this.x, this.y, this.z, this.w);
};

Vec4.prototype.toVec3 = function() {
  return new Vec3(this.x, this.y, this.z);
};


// This represents an affine 4x4 matrix, using mathematical notation,
// numbered (starting from 1) as aij, where i is the row and j is the column.
//   a11 a12 a13 a14
//   a21 a22 a23 a24
//   a31 a32 a33 a34
//   a41 a42 a43 a44
//
// Almost all operations are multiplies to the current matrix, and happen
// in place.  You can use dup() to return a copy.
//
// Most operations return this to support chaining.
//
// It's common to use toFloat32Array to get a Float32Array in OpenGL (column
// major) memory ordering.  NOTE: The code tries to be explicit about whether
// things are row major or column major, but remember that GLSL works in
// column major ordering, and PreGL generally uses row major ordering.
function Mat4() {
  this.reset();
}

// Set the full 16 elements of the 4x4 matrix, arguments in row major order.
// The elements are specified in row major order.  TODO(deanm): set4x4c.
Mat4.prototype.set4x4r = function(a11, a12, a13, a14, a21, a22, a23, a24,
                                  a31, a32, a33, a34, a41, a42, a43, a44) {
  this.a11 = a11; this.a12 = a12; this.a13 = a13; this.a14 = a14;
  this.a21 = a21; this.a22 = a22; this.a23 = a23; this.a24 = a24;
  this.a31 = a31; this.a32 = a32; this.a33 = a33; this.a34 = a34;
  this.a41 = a41; this.a42 = a42; this.a43 = a43; this.a44 = a44;

  return this;
};

// Reset the transform to the identity matrix.
Mat4.prototype.reset = function() {
  this.set4x4r(1, 0, 0, 0,
               0, 1, 0, 0,
               0, 0, 1, 0,
               0, 0, 0, 1);

  return this;
};

// Matrix multiply this = a * b
Mat4.prototype.mul2 = function(a, b) {
  var a11 = a.a11, a12 = a.a12, a13 = a.a13, a14 = a.a14,
      a21 = a.a21, a22 = a.a22, a23 = a.a23, a24 = a.a24,
      a31 = a.a31, a32 = a.a32, a33 = a.a33, a34 = a.a34,
      a41 = a.a41, a42 = a.a42, a43 = a.a43, a44 = a.a44;
  var b11 = b.a11, b12 = b.a12, b13 = b.a13, b14 = b.a14,
      b21 = b.a21, b22 = b.a22, b23 = b.a23, b24 = b.a24,
      b31 = b.a31, b32 = b.a32, b33 = b.a33, b34 = b.a34,
      b41 = b.a41, b42 = b.a42, b43 = b.a43, b44 = b.a44;

  this.a11 = a11*b11 + a12*b21 + a13*b31 + a14*b41;
  this.a12 = a11*b12 + a12*b22 + a13*b32 + a14*b42;
  this.a13 = a11*b13 + a12*b23 + a13*b33 + a14*b43;
  this.a14 = a11*b14 + a12*b24 + a13*b34 + a14*b44;
  this.a21 = a21*b11 + a22*b21 + a23*b31 + a24*b41;
  this.a22 = a21*b12 + a22*b22 + a23*b32 + a24*b42;
  this.a23 = a21*b13 + a22*b23 + a23*b33 + a24*b43;
  this.a24 = a21*b14 + a22*b24 + a23*b34 + a24*b44;
  this.a31 = a31*b11 + a32*b21 + a33*b31 + a34*b41;
  this.a32 = a31*b12 + a32*b22 + a33*b32 + a34*b42;
  this.a33 = a31*b13 + a32*b23 + a33*b33 + a34*b43;
  this.a34 = a31*b14 + a32*b24 + a33*b34 + a34*b44;
  this.a41 = a41*b11 + a42*b21 + a43*b31 + a44*b41;
  this.a42 = a41*b12 + a42*b22 + a43*b32 + a44*b42;
  this.a43 = a41*b13 + a42*b23 + a43*b33 + a44*b43;
  this.a44 = a41*b14 + a42*b24 + a43*b34 + a44*b44;

  return this;
};

// Matrix multiply this = this * b
Mat4.prototype.mul = function(b) {
  return this.mul2(this, b);
};

// Multiply the current matrix by 16 elements that would compose a Mat4
// object, but saving on creating the object.  this = this * b.
// The elements are specific in row major order.  TODO(deanm): mul4x4c.
// TODO(deanm): It's a shame to duplicate the multiplication code.
Mat4.prototype.mul4x4r = function(b11, b12, b13, b14, b21, b22, b23, b24,
                                  b31, b32, b33, b34, b41, b42, b43, b44) {
  var a11 = this.a11, a12 = this.a12, a13 = this.a13, a14 = this.a14,
      a21 = this.a21, a22 = this.a22, a23 = this.a23, a24 = this.a24,
      a31 = this.a31, a32 = this.a32, a33 = this.a33, a34 = this.a34,
      a41 = this.a41, a42 = this.a42, a43 = this.a43, a44 = this.a44;

  this.a11 = a11*b11 + a12*b21 + a13*b31 + a14*b41;
  this.a12 = a11*b12 + a12*b22 + a13*b32 + a14*b42;
  this.a13 = a11*b13 + a12*b23 + a13*b33 + a14*b43;
  this.a14 = a11*b14 + a12*b24 + a13*b34 + a14*b44;
  this.a21 = a21*b11 + a22*b21 + a23*b31 + a24*b41;
  this.a22 = a21*b12 + a22*b22 + a23*b32 + a24*b42;
  this.a23 = a21*b13 + a22*b23 + a23*b33 + a24*b43;
  this.a24 = a21*b14 + a22*b24 + a23*b34 + a24*b44;
  this.a31 = a31*b11 + a32*b21 + a33*b31 + a34*b41;
  this.a32 = a31*b12 + a32*b22 + a33*b32 + a34*b42;
  this.a33 = a31*b13 + a32*b23 + a33*b33 + a34*b43;
  this.a34 = a31*b14 + a32*b24 + a33*b34 + a34*b44;
  this.a41 = a41*b11 + a42*b21 + a43*b31 + a44*b41;
  this.a42 = a41*b12 + a42*b22 + a43*b32 + a44*b42;
  this.a43 = a41*b13 + a42*b23 + a43*b33 + a44*b43;
  this.a44 = a41*b14 + a42*b24 + a43*b34 + a44*b44;

  return this;
};

// TODO(deanm): Some sort of mat3x3.  There are two ways you could do it
// though, just multiplying the 3x3 portions of the 4x4 matrix, or doing a
// 4x4 multiply with the last row/column implied to be 0, 0, 0, 1.  This
// keeps true to the original matrix even if it's last row is not 0, 0, 0, 1.

// IN RADIANS, not in degrees like OpenGL.  Rotate about x, y, z.
// The caller must supply a x, y, z as a unit vector.
Mat4.prototype.rotate = function(theta, x, y, z) {
  // http://www.cs.rutgers.edu/~decarlo/428/gl_man/rotate.html
  var s = Math.sin(theta);
  var c = Math.cos(theta);
  this.mul4x4r(
      x*x*(1-c)+c, x*y*(1-c)-z*s, x*z*(1-c)+y*s, 0,
    y*x*(1-c)+z*s,   y*y*(1-c)+c, y*z*(1-c)-x*s, 0,
    x*z*(1-c)-y*s, y*z*(1-c)+x*s,   z*z*(1-c)+c, 0,
                0,             0,             0, 1);

  return this;
};

// Multiply by a translation of x, y, and z.
Mat4.prototype.translate = function(dx, dy, dz) {
  // TODO(deanm): Special case the multiply since most goes unchanged.
  this.mul4x4r(1, 0, 0, dx,
               0, 1, 0, dy,
               0, 0, 1, dz,
               0, 0, 0,  1);

  return this;
};

// Multiply by a scale of x, y, and z.
Mat4.prototype.scale = function(sx, sy, sz) {
  // TODO(deanm): Special case the multiply since most goes unchanged.
  this.mul4x4r(sx,  0,  0, 0,
                0, sy,  0, 0,
                0,  0, sz, 0,
                0,  0,  0, 1);

  return this;
};

// Multiply by a look at matrix, computed from the eye, center, and up points.
Mat4.prototype.lookAt = function(ex, ey, ez, cx, cy, cz, ux, uy, uz) {
  var z = (new Vec3(ex - cx, ey - cy, ez - cz)).normalize();
  var x = (new Vec3(ux, uy, uz)).cross(z).normalize();
  var y = z.dup().cross(x).normalize();
  // The new axis basis is formed as row vectors since we are transforming
  // the coordinate system (alias not alibi).
  this.mul4x4r(x.x, x.y, x.z, 0,
               y.x, y.y, y.z, 0,
               z.x, z.y, z.z, 0,
                 0,   0,   0, 1);
  this.translate(-ex, -ey, -ez);

  return this;
};

// Multiply by a frustum matrix computed from left, right, bottom, top,
// near, and far.
Mat4.prototype.frustum = function(l, r, b, t, n, f) {
  this.mul4x4r(
      (n+n)/(r-l),           0, (r+l)/(r-l),             0,
                0, (n+n)/(t-b), (t+b)/(t-b),             0,
                0,           0, (f+n)/(n-f), (2*f*n)/(n-f),
                0,           0,          -1,             0);

  return this;
};

// Multiply by a perspective matrix, computed from the field of view, aspect
// ratio, and the z near and far planes.
Mat4.prototype.perspective = function(fovy, aspect, znear, zfar) {
  // This could also be done reusing the frustum calculation:
  // var ymax = znear * Math.tan(fovy * kPI / 360.0);
  // var ymin = -ymax;
  //
  // var xmin = ymin * aspect;
  // var xmax = ymax * aspect;
  //
  // return makeFrustumAffine(xmin, xmax, ymin, ymax, znear, zfar);

  var f = 1.0 / Math.tan(fovy * kPI / 360.0);
  this.mul4x4r(
      f/aspect, 0,                         0,                         0,
             0, f,                         0,                         0,
             0, 0, (zfar+znear)/(znear-zfar), 2*znear*zfar/(znear-zfar),
             0, 0,                        -1,                         0);

  return this;
};

// Multiply by a orthographic matrix, computed from the clipping planes.
Mat4.prototype.ortho = function(l, r, b, t, n, f) {
  this.mul4x4r(2/(r-l),        0,        0,  (r+l)/(l-r),
                     0,  2/(t-b),        0,  (t+b)/(b-t),
                     0,        0,  2/(n-f),  (f+n)/(n-f),
                     0,        0,        0,            1);

  return this;
};

// Invert the matrix.  The matrix must be invertable.
Mat4.prototype.invert = function() {
  // Based on the math at:
  //   http://www.geometrictools.com/LibMathematics/Algebra/Wm5Matrix4.inl
  var  x0 = this.a11,  x1 = this.a12,  x2 = this.a13,  x3 = this.a14,
       x4 = this.a21,  x5 = this.a22,  x6 = this.a23,  x7 = this.a24,
       x8 = this.a31,  x9 = this.a32, x10 = this.a33, x11 = this.a34,
      x12 = this.a41, x13 = this.a42, x14 = this.a43, x15 = this.a44;

  var a0 = x0*x5 - x1*x4,
      a1 = x0*x6 - x2*x4,
      a2 = x0*x7 - x3*x4,
      a3 = x1*x6 - x2*x5,
      a4 = x1*x7 - x3*x5,
      a5 = x2*x7 - x3*x6,
      b0 = x8*x13 - x9*x12,
      b1 = x8*x14 - x10*x12,
      b2 = x8*x15 - x11*x12,
      b3 = x9*x14 - x10*x13,
      b4 = x9*x15 - x11*x13,
      b5 = x10*x15 - x11*x14;

  // TODO(deanm): These terms aren't reused, so get rid of the temporaries.
  var invdet = 1 / (a0*b5 - a1*b4 + a2*b3 + a3*b2 - a4*b1 + a5*b0);

  this.a11 = (+ x5*b5 - x6*b4 + x7*b3) * invdet;
  this.a12 = (- x1*b5 + x2*b4 - x3*b3) * invdet;
  this.a13 = (+ x13*a5 - x14*a4 + x15*a3) * invdet;
  this.a14 = (- x9*a5 + x10*a4 - x11*a3) * invdet;
  this.a21 = (- x4*b5 + x6*b2 - x7*b1) * invdet;
  this.a22 = (+ x0*b5 - x2*b2 + x3*b1) * invdet;
  this.a23 = (- x12*a5 + x14*a2 - x15*a1) * invdet;
  this.a24 = (+ x8*a5 - x10*a2 + x11*a1) * invdet;
  this.a31 = (+ x4*b4 - x5*b2 + x7*b0) * invdet;
  this.a32 = (- x0*b4 + x1*b2 - x3*b0) * invdet;
  this.a33 = (+ x12*a4 - x13*a2 + x15*a0) * invdet;
  this.a34 = (- x8*a4 + x9*a2 - x11*a0) * invdet;
  this.a41 = (- x4*b3 + x5*b1 - x6*b0) * invdet;
  this.a42 = (+ x0*b3 - x1*b1 + x2*b0) * invdet;
  this.a43 = (- x12*a3 + x13*a1 - x14*a0) * invdet;
  this.a44 = (+ x8*a3 - x9*a1 + x10*a0) * invdet;

  return this;
};

// Transpose the matrix, rows become columns and columns become rows.
Mat4.prototype.transpose = function() {
  var a11 = this.a11, a12 = this.a12, a13 = this.a13, a14 = this.a14,
      a21 = this.a21, a22 = this.a22, a23 = this.a23, a24 = this.a24,
      a31 = this.a31, a32 = this.a32, a33 = this.a33, a34 = this.a34,
      a41 = this.a41, a42 = this.a42, a43 = this.a43, a44 = this.a44;

  this.a11 = a11; this.a12 = a21; this.a13 = a31; this.a14 = a41;
  this.a21 = a12; this.a22 = a22; this.a23 = a32; this.a24 = a42;
  this.a31 = a13; this.a32 = a23; this.a33 = a33; this.a34 = a43;
  this.a41 = a14; this.a42 = a24; this.a43 = a34; this.a44 = a44;

  return this;
};

// Multiply Vec3 |v| by the current matrix, returning a Vec3 of this * v.
Mat4.prototype.mulVec3 = function(v) {
  var x = v.x, y = v.y, z = v.z;
  return new Vec3(this.a14 + this.a11*x + this.a12*y + this.a13*z,
                  this.a24 + this.a21*x + this.a22*y + this.a23*z,
                  this.a34 + this.a31*x + this.a32*y + this.a33*z);
};

// Multiply Vec4 |v| by the current matrix, returning a Vec4 of this * v.
Mat4.prototype.mulVec4 = function(v) {
  var x = v.x, y = v.y, z = v.z, w = v.w;
  return new Vec4(this.a14*w + this.a11*x + this.a12*y + this.a13*z,
                  this.a24*w + this.a21*x + this.a22*y + this.a23*z,
                  this.a34*w + this.a31*x + this.a32*y + this.a33*z,
                  this.a44*w + this.a41*x + this.a42*y + this.a43*z);
};

Mat4.prototype.dup = function() {
  var m = new Mat4();  // TODO(deanm): This could be better.
  m.set4x4r(this.a11, this.a12, this.a13, this.a14,
            this.a21, this.a22, this.a23, this.a24,
            this.a31, this.a32, this.a33, this.a34,
            this.a41, this.a42, this.a43, this.a44);
  return m;
};

Mat4.prototype.toFloat32Array = function() {
  return new Float32Array([this.a11, this.a21, this.a31, this.a41,
                           this.a12, this.a22, this.a32, this.a42,
                           this.a13, this.a23, this.a33, this.a43,
                           this.a14, this.a24, this.a34, this.a44]);
};

Mat4.prototype.debugString = function() {
  var s = [this.a11, this.a12, this.a13, this.a14,
           this.a21, this.a22, this.a23, this.a24,
           this.a31, this.a32, this.a33, this.a34,
           this.a41, this.a42, this.a43, this.a44];
  var row_lengths = [0, 0, 0, 0];
  for (var i = 0; i < 16; ++i) {
    s[i] += '';  // Stringify.
    var len = s[i].length;
    var row = i & 3;
    if (row_lengths[row] < len)
      row_lengths[row] = len;
  }

  var out = '';
  for (var i = 0; i < 16; ++i) {
    var len = s[i].length;
    var row_len = row_lengths[i & 3];
    var num_spaces = row_len - len;
    while (num_spaces--) out += ' ';
    out += s[i] + ((i & 3) === 3 ? '\n' : '  ');
  }

  return out;
};


var kFragmentShaderPrefix = "#ifdef GL_ES\n" +
                            "#ifdef GL_FRAGMENT_PRECISION_HIGH\n" +
                            "  precision highp float;\n" +
                            "#else\n" +
                            "  precision mediump float;\n" +
                            "#endif\n" +
                            "#endif\n";

// Given a string of GLSL source |source| of type |type|, create the shader
// and compile |source| to the shader.  Throws on error.  Returns the newly
// created WebGLShader.  Automatically compiles GL_ES default precision
// qualifiers before a fragment source.
function webGLcreateAndCompilerShader(gl, source, type) {
  var shader = gl.createShader(type);
  // NOTE(deanm): We're not currently running on ES, so we don't need this.
  // if (type === gl.FRAGMENT_SHADER) source = kFragmentShaderPrefix + source;
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (gl.getShaderParameter(shader, gl.COMPILE_STATUS) !== true)
    throw gl.getShaderInfoLog(shader);
  return shader;
}

// Given the source text of the vertex shader |vsource| and fragment shader
// |fsource|, create a new program with the shaders together.  Throws on
// error.  Returns the newly created WebGLProgram.  Does not call useProgram.
// Automatically compiles GL_ES default precision qualifiers before a
// fragment source.
function webGLcreateProgramFromShaderSources(gl, vsource, fsource) {
  var vshader = webGLcreateAndCompilerShader(gl, vsource, gl.VERTEX_SHADER);
  var fshader = webGLcreateAndCompilerShader(gl, fsource, gl.FRAGMENT_SHADER);
  var program = gl.createProgram();
  gl.attachShader(program, vshader);
  gl.attachShader(program, fshader);
  gl.linkProgram(program);
  if (gl.getProgramParameter(program, gl.LINK_STATUS) !== true)
    throw gl.getProgramInfoLog(program);
  return program;
}


function MagicProgram(gl, program) {
  this.gl = gl;
  this.program = program;

  this.use = function() {
    gl.useProgram(program);
  };

  function makeSetter(type, loc) {
    switch (type) {
      case gl.BOOL:  // NOTE: bool could be set with 1i or 1f.
      case gl.INT:
      case gl.SAMPLER_2D:
      case gl.SAMPLER_CUBE:
        return function(value) {
          gl.uniform1i(loc, value);
          return this;
        };
      case gl.FLOAT:
        return function(value) {
          gl.uniform1f(loc, value);
          return this;
        };
      case gl.FLOAT_VEC2:
        return function(v) {
          gl.uniform2f(loc, v.x, v.y);
        };
      case gl.FLOAT_VEC3:
        return function(v) {
          gl.uniform3f(loc, v.x, v.y, v.z);
        };
      case gl.FLOAT_VEC4:
        return function(v) {
          gl.uniform4f(loc, v.x, v.y, v.z, v.w);
        };
      case gl.FLOAT_MAT4:
        return function(mat4) {
          gl.uniformMatrix4fv(loc, false, mat4.toFloat32Array());
        };
      default:
        break;
    }

    return function() {
      throw "MagicProgram doesn't know how to set type: " + type;
    };
  }

  var num_uniforms = gl.getProgramParameter(program, gl.ACTIVE_UNIFORMS);
  for (var i = 0; i < num_uniforms; ++i) {
    var info = gl.getActiveUniform(program, i);
    var name = info.name;
    var loc = gl.getUniformLocation(program, name);
    this['set_' + name] = makeSetter(info.type, loc);
    this['location_' + name] = loc;
  }

  var num_attribs = gl.getProgramParameter(program, gl.ACTIVE_ATTRIBUTES);
  for (var i = 0; i < num_attribs; ++i) {
    var info = gl.getActiveAttrib(program, i);
    var name = info.name;
    var loc = gl.getAttribLocation(program, name);
    this['location_' + name] = loc;
  }
}

MagicProgram.createFromFiles = function(gl, vfn, ffn) {
  return new MagicProgram(gl, webGLcreateProgramFromShaderSources(
      gl, fs.readFileSync(vfn, 'utf8'), fs.readFileSync(ffn, 'utf8')));
}

MagicProgram.createFromBasename = function(gl, directory, base) {
  return MagicProgram.createFromFiles(
      gl,
      path.join(directory, base + '.vshader'),
      path.join(directory, base + '.fshader'));
}

exports.kPI  = kPI;
exports.kPI2 = kPI2;
exports.kPI4 = kPI4;
exports.k2PI = k2PI;

exports.min = min;
exports.max = max;
exports.clamp = clamp;
exports.lerp = lerp;

exports.Vec3 = Vec3;
exports.Vec2 = Vec2;
exports.Vec4 = Vec4;
exports.Mat4 = Mat4;

exports.gl = {MagicProgram: MagicProgram};
