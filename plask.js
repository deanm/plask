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
var net = require('net');
var inherits = sys.inherits;

exports.SkPath = PlaskRawMac.SkPath;
exports.SkPaint = PlaskRawMac.SkPaint;
exports.SkCanvas = PlaskRawMac.SkCanvas;

exports.AVPlayer = PlaskRawMac.AVPlayer;

// NOTE(deanm): The SkCanvas constructor has become too complicated in
// supporting different types of canvases and ways to create them.  Use one of
// the following factory functions instead of calling the constructor directly.

// static SkCanvas createFromImage(filename)
//
// Create a bitmap SkCanvas with the size/pixels from an image `filename`.
exports.SkCanvas.createFromImage = function(path) {
  return new exports.SkCanvas('^IMG', path);
};

// static SkCanvas createFromImageData(data)
//
// Create a bitmap SkCanvas with the size/pixels from an image `data`.
exports.SkCanvas.createFromImageData = function(data) {
  return new exports.SkCanvas('^IMG', data);
};

// static SkCanvas create(width, height)
//
// Create a bitmap SkCanvas with the specified size.
exports.SkCanvas.create = function(width, height) {
  return new exports.SkCanvas(width, height);
};

// Sizes are in points, at 72 points per inch, letter would be 612x792.
// That makes A4 about 595x842.
// TODO(deanm): The sizes are integer, check the right size to use for A4.

// static SkCanvas createForPDF(filename, page_width, page_height, content_width, content_height)
//
// Create a new vector-mode SkCanvas that can be written to a PDF with `writePDF`.
exports.SkCanvas.createForPDF = function(filename, page_width, page_height,
                                         content_width, content_height) {
  return new exports.SkCanvas(
      '%PDF',
      filename, page_width, page_height,
      content_width === undefined ? page_width : content_width,
      content_height === undefined ? page_height : content_height);
};

var kPI   = 3.14159265358979323846264338327950288;
var kPI2  = 1.57079632679489661923132169163975144;
var kPI4  = 0.785398163397448309615660845819875721;
var k2PI  = 6.28318530717958647692528676655900576;
var kLN2  = 0.693147180559945309417232121458176568;
var kLN10 = 2.30258509299404568401799145468436421;

// float min(float a, float b)
function min(a, b) {
  if (a < b) return a;
  return b;
}

// float max(float a, float b)
function max(a, b) {
  if (a > b) return a;
  return b;
}

// float clamp(float v, float vmin, float vmax)
//
// GLSL clamp.  Keep the value `v` in the range `vmin` .. `vmax`.
function clamp(v, vmin, vmax) {
  return min(vmax, max(vmin, v));
}

// float lerp(float a, float b, float t)
//
// Linear interpolation on the line along points (0, `a`) and (1, `b`).  The
// position `t` is the x coordinate, where 0 is `a` and 1 is `b`.
function lerp(a, b, t) {
  return a + (b-a)*t;
}

// float smoothstep(edge0, edge1, x)
//
// GLSL smoothstep.  NOTE: Undefined if edge0 == edge1.
function smoothstep(edge0, edge1, x) {
  var t = clamp((x - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - t - t);
}

// float smootherstep(edge0, edge1, x)
//
// Ken Perlin's "smoother" step function, with zero 1st and 2nd derivatives at
// the endpoints (whereas smoothstep has a 2nd derivative of +/- 6).  This is
// also for example used by Patel and Taylor in smooth simulation noise.
function smootherstep(edge0, edge1, x) {
  var t = clamp((x - edge0) / (edge1 - edge0), 0, 1);
  return t * t * t * (t * (t * 6 - 15) + 10);
}

// http://en.wikipedia.org/wiki/Fractional_part
//
// There are various conflicting ways to extend the fractional part function to
// negative numbers. It is either defined as frac(x) = x - floor(x)
// (Graham, Knuth & Patashnik 1992), as the part of the number to the
// right of the radix point, frac(x) = |x| - floor(|x|)
// (Daintith 2004), or as the odd function:
//    frac(x) = x - floor(x), x >= 0
//              x - ceil(x),  x <  0

// float fract(float x)
//
// Like GLSL fract(), returns x - floor(x).  NOTE, for negative numbers, this
// is a positive value, ex fract(-1.3) == 0.7.
function fract(x) { return x - Math.floor(x); }

// float fract2(float x)
//
// Returns the part of the number to the right of the radix point.
// For negative numbers, this is a positive value, ex fract(-1.25) == 0.25
function fract2(x) { return x < 0 ? (x|0) - x : x - (x|0); }

// float fract3(float x)
//
// Returns the signed part of the number to the right of the radix point.
// For negative numbers, this is a negative value, ex fract(-1.25) == -0.25
function fract3(x) { return x - (x|0); }

// Test if `num` is a floating point -0.
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
  var flipped = exports.SkCanvas.create(width, height);
  flipped.translate(0, height);
  flipped.scale(1, -1);
  flipped.drawCanvas(flipper_paint, c, 0, 0, width, height);
  var result = this.texImage2DSkCanvasB(a, b, flipped);
  return result;
};

PlaskRawMac.NSOpenGLContext.prototype.texImage2DSkCanvasNoFlip = function() {
  return this.texImage2DSkCanvasB.apply(this, arguments);
};

PlaskRawMac.CAMIDISource.prototype.noteOn = function(chan, note, vel, ns) {
  return this.sendData([0x90 | (chan & 0xf), note & 0x7f, vel & 0x7f], ns);
};

PlaskRawMac.CAMIDISource.prototype.noteOff = function(chan, note, vel, ns) {
  return this.sendData([0x80 | (chan & 0xf), note & 0x7f, vel & 0x7f], ns);
};

// Pitch wheel takes a value between -1 .. 1, and will be mapped to 14-bit midi.
PlaskRawMac.CAMIDISource.prototype.pitchWheel = function(chan, val) {
  var bits = clamp((val * 0.5 + 0.5) * 16384, 0, 16383);  // Not perfect at +1.
  return this.sendData([0xe0 | (chan & 0xf), bits & 0x7f, (bits >> 7) & 0x7f]);
};

PlaskRawMac.CAMIDISource.prototype.controller = function(chan, con, val) {
  return this.sendData([0xb0 | (chan & 0xf), con & 0x7f, val & 0x7f]);
};

PlaskRawMac.CAMIDISource.prototype.programChange = function(chan, val) {
  return this.sendData([0xc0 | (chan & 0xf), val & 0x7f]);
};

inherits(PlaskRawMac.CAMIDIDestination, events.EventEmitter);

PlaskRawMac.CAMIDIDestination.prototype.on = function(evname, callback) {
  // TODO(deanm): Move initialization to constructor (need to shim it).
  if (this._sock_initialized !== true) {
    var sock = new net.Socket({fd: this.getPipeDescriptor()});
    sock.writable = false;
    var this_ = this;

    function processMessage(msg) {
      if (msg.length < 1) return 'Received zero length midi message.';

      // NOTE(deanm): I would have assumed that every MIDI message should come
      // in as its own 'packet', but for example sending a snapshot from a
      // UC-33e sends some of the controller messages back to back in the same
      // packet.  I'm not sure if this is the expected behavior, but we'll
      // try to handle it...

      // TODO(deanm): Use framing instead of assuming atomic writes on the pipe.
      for (var j = 0, jl = msg.length; j < jl; ) {
        if ((msg[j] & 0x80) !== 0x80) {
          console.trace(msg);
          console.trace(msg.slice(j));
          return 'First MIDI byte not a status byte.';
        }

        var rem = jl - j;  // Number of bytes remaining.

        // NOTE(deanm): We expect MIDI packets are the correct length, for
        // example 3 bytes for note on and off.  Instead of error checking,
        // we'll get undefined from msg[] if the message is shorter, maybe
        // should handle this better, but loads of length checking is annoying.
        switch (msg[j] & 0xf0) {
          case 0x80:  // Note off.
            if (rem < 3) return 'Short noteOff message.';
            this_.emit('noteOff', {type:'noteOff',
                                  chan: msg[j+0] & 0x0f,
                                  note: msg[j+1],
                                  vel: msg[j+2]});
            j += 3; break;
          case 0x90:  // Note on.
            if (rem < 3) return 'Short noteOn message.';
            this_.emit('noteOn', {type:'noteOn',
                                  chan: msg[j+0] & 0x0f,
                                  note: msg[j+1],
                                  vel: msg[j+2]});
            j += 3; break;
          case 0xa0:  // Aftertouch.
            if (rem < 3) return 'Short aftertouch message.';
            this_.emit('aftertouch', {type:'aftertouch',
                                      chan: msg[j+0] & 0x0f,
                                      note: msg[j+1],
                                      pressure: msg[j+2]});
            j += 3; break;
          case 0xb0:  // Controller message.
            if (rem < 3) return 'Short controller message.';
            this_.emit('controller', {type:'controller',
                                      chan: msg[j+0] & 0x0f,
                                      num: msg[j+1],
                                      val: msg[j+2]});
            j += 3; break;
          case 0xc0:  // Program change.
            if (rem < 2) return 'Short programChange message.';
            this_.emit('programChange', {type:'programChange',
                                         chan: msg[j+0] & 0x0f,
                                         num: msg[j+1]});
            j += 2; break;
          case 0xd0:  // Channel pressure.
            if (rem < 2) return 'Short channelPressure message.';
            this_.emit('channelPressure', {type:'channelPressure',
                                           chan: msg[j+0] & 0x0f,
                                           pressure: msg[j+1]});
            j += 2; break;
          case 0xe0:  // Pitch wheel.
            if (rem < 3) return 'Short pitchWheel message.';
            this_.emit('pitchWheel', {type:'pitchWheel',
                                      chan: msg[j+0] & 0x0f,
                                      val: (msg[j+2] << 7) | msg[j+1]});
            j += 3; break;
          case 0xf0:  // SysEx and the 0xFx messages.
            if (msg[j] !== 0xf0)
              return 'Unhandled MIDI status byte: 0x' + msg[j].toString(16);
            var start = j;
            while (j+1 < msg.length && msg[j] !== 0xf7) ++j;
            if (msg[j++] !== 0xf7) return 'Missing expected SysEx termination.';
            this_.emit('sysex', {type: 'sysex', data: msg.slice(start, j)});
            break;
          default:
            return 'Unhandled MIDI status byte: 0x' + msg[j].toString(16);
        }
      }

      return null;
    }

    sock.on('data', function(msg, rinfo) {
      var res = processMessage(msg);
      if (res !== null) console.log(res);
    });

    this._sock_initialized = true;
  }

  events.EventEmitter.prototype.on.call(this, evname, callback);
};

exports.MidiIn = PlaskRawMac.CAMIDIDestination;
exports.MidiOut = PlaskRawMac.CAMIDISource;

exports.SBApplication = function(bundleid) {
  var sbapp = new PlaskRawMac.SBApplication(bundleid);
  var methods = sbapp.objcMethods();
  for (var i = 0, il = methods.length; i < il; ++i) {
    var sig = methods[i];
    if (sig.length === 4) {
      this[sig[0].replace(/:/g, '_')] = (function(name) {
        return function() {
          return sbapp.invokeVoid0(name);
        };
      })(sig[0]);
    }
    if (sig.length === 5 && sig[4] === '@') {  // Assume arg is a string.
      this[sig[0].replace(/:/g, '_')] = (function(name) {
        return function(arg) {
          return sbapp.invokeVoid1s(name, arg);
        };
      })(sig[0]);
    }
  }
  console.log(methods);
};

exports.AppleScript = PlaskRawMac.NSAppleScript;

exports.Window = function(width, height, opts) {
  setInterval(function() { }, 999999999);  // Hack to prevent empty event loop.
  var nswindow_ = new PlaskRawMac.NSWindow(
      opts.type === '3d+skia' ? 2 : opts.type === '3d' ? 1 : 0,
      width, height,
      opts.multisample === true,
      opts.display === undefined ? -1 : opts.display,
      opts.borderless === true,
      opts.fullscreen === true,
      opts.highdpi === undefined ? 0 : opts.highdpi);
  var this_ = this;

  var dpi_scale = opts.highdpi === 2 ? 2 : 1;  // For scaling mouse events.

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

  this.setTitle = function(title) { return nswindow_.setTitle(title); };
  this.setFullscreen = function(fs) { return nswindow_.setFullscreen(fs); };

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
      case PlaskRawMac.NSEvent.NSMouseMoved: return 'mouseMoved';
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

  function cursor_name_to_selector_name(name) {
    switch (name) {
      case 'arrow':               return 'arrowCursor';
      case 'context':             return 'contextualMenuCursor';
      case 'closedhand':          return 'closedHandCursor';
      case 'crosshair':           return 'crosshairCursor';
      case 'poof':
      case 'disappearingitem':    return 'disappearingItemCursor';
      case 'dragcopy':            return 'dragCopyCursor';
      case 'draglink':            return 'dragLinkCursor';
      case 'ibeam':               return 'IBeamCursor';
      case 'openhand':            return 'openHandCursor';
      case 'notallowed':          return 'operationNotAllowedCursor';
      case 'pointinghand':        return 'pointingHandCursor';
      case 'resizedown':          return 'resizeDownCursor';
      case 'resizeleft':          return 'resizeLeftCursor';
      case 'resizeleftright':     return 'resizeLeftRightCursor';
      case 'resizeright':         return 'resizeRightCursor';
      case 'resizeup':            return 'resizeUpCursor';
      case 'resizeupdown':        return 'resizeUpDownCursor';
      case 'vibeam':              return 'IBeamCursorForVerticalLayout';
    };
    return null;
  }

  this.unhideCursor = function() {
    return nswindow_.unhideCursor();
  };

  this.setCursor = function(name) {
    var selector = cursor_name_to_selector_name(name);
    return selector !== null ? nswindow_.setCursor(selector) : undefined;
  };

  this.pushCursor = function(name) {
    var selector = cursor_name_to_selector_name(name);
    return selector !== null ? nswindow_.pushCursor(selector) : undefined;
  };

  this.popCursor = function() {
    return nswindow_.popCursor();
  };

  this.setCursorPosition = function(x, y) {
    return nswindow_.setCursorPosition(x, y);
  };

  this.warpCursorPosition = function(x, y) {
    return nswindow_.warpCursorPosition(x, y);
  };

  this.associateMouse = function(connected) {
    return nswindow_.associateMouse(connected);
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
          x: loc.x * dpi_scale,
          y: height - loc.y * dpi_scale,  // Map from button left to top left.
          buttonNumber: button,
          buttonName: buttonNumberToName(button),
          clickCount: e.clickCount(),
          capslock: (mods & e.NSAlphaShiftKeyMask) !== 0,
          shift: (mods & e.NSShiftKeyMask) !== 0,
          ctrl: (mods & e.NSControlKeyMask) !== 0,
          option: (mods & e.NSAlternateKeyMask) !== 0,
          cmd: (mods & e.NSCommandKeyMask) !== 0,
          function: (mods & e.NSFunctionKeyMask) !== 0
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
          x: loc.x * dpi_scale,
          y: height - loc.y * dpi_scale,
          dx: e.deltaX() * dpi_scale,
          dy: e.deltaY() * dpi_scale,  // Doesn't need flip, in device space.
          dz: e.deltaZ(),
          pressure: e.pressure(),
          buttonNumber: button,
          buttonName: buttonNumberToName(button),
          capslock: (mods & e.NSAlphaShiftKeyMask) !== 0,
          shift: (mods & e.NSShiftKeyMask) !== 0,
          ctrl: (mods & e.NSControlKeyMask) !== 0,
          option: (mods & e.NSAlternateKeyMask) !== 0,
          cmd: (mods & e.NSCommandKeyMask) !== 0,
          function: (mods & e.NSFunctionKeyMask) !== 0
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
          x: loc.x * dpi_scale,
          y: height - loc.y * dpi_scale,
          pressure: e.pressure(),
          capslock: (mods & e.NSAlphaShiftKeyMask) !== 0,
          shift: (mods & e.NSShiftKeyMask) !== 0,
          ctrl: (mods & e.NSControlKeyMask) !== 0,
          option: (mods & e.NSAlternateKeyMask) !== 0,
          cmd: (mods & e.NSCommandKeyMask) !== 0,
          function: (mods & e.NSFunctionKeyMask) !== 0
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
          cmd: (mods & e.NSCommandKeyMask) !== 0,
          function: (mods & e.NSFunctionKeyMask) !== 0,
          repeat: e.isARepeat()
        };
        this_.emit(te.type, te);
        break;
      case PlaskRawMac.NSEvent.NSMouseMoved:
        var mods = e.modifierFlags();
        var loc = e.locationInWindow();
        var te = {
          type: nsEventNameToEmitName(type),
          x: loc.x * dpi_scale,
          y: height - loc.y * dpi_scale,
          dx: e.deltaX() * dpi_scale,
          dy: e.deltaY() * dpi_scale,  // Doesn't need flip, in device space.
          dz: e.deltaZ(),
          capslock: (mods & e.NSAlphaShiftKeyMask) !== 0,
          shift: (mods & e.NSShiftKeyMask) !== 0,
          ctrl: (mods & e.NSControlKeyMask) !== 0,
          option: (mods & e.NSAlternateKeyMask) !== 0,
          cmd: (mods & e.NSCommandKeyMask) !== 0,
          function: (mods & e.NSFunctionKeyMask) !== 0
        };
        this_.emit(te.type, te);
        break;
      case PlaskRawMac.NSEvent.NSScrollWheel:
        var mods = e.modifierFlags();
        var loc = e.locationInWindow();
        var te = {
          type: nsEventNameToEmitName(type),
          x: loc.x * dpi_scale,
          y: height - loc.y * dpi_scale,
          dx: e.deltaX() * dpi_scale,
          dy: e.deltaY() * dpi_scale,  // Doesn't need flip, in device space.
          dz: e.deltaZ(),
          hasPreciseScrollingDeltas: e.hasPreciseScrollingDeltas(),
          scrollingDeltaX: e.scrollingDeltaX(),
          scrollingDeltaY: e.scrollingDeltaY(),
          phase: e.phase(),
          momentumPhase: e.momentumPhase(),
          capslock: (mods & e.NSAlphaShiftKeyMask) !== 0,
          shift: (mods & e.NSShiftKeyMask) !== 0,
          ctrl: (mods & e.NSControlKeyMask) !== 0,
          option: (mods & e.NSAlternateKeyMask) !== 0,
          cmd: (mods & e.NSCommandKeyMask) !== 0,
          function: (mods & e.NSFunctionKeyMask) !== 0
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
        this_.emit('filesDropped', {type: 'filesDropped',
                                    paths: msgdata.paths,
                                    x: msgdata.x,
                                    y: height - msgdata.y});
      }
    } catch(ex) {
      sys.puts(ex.stack);
    }
  });

  this.getRelativeMouseState = function() {
    var res = nswindow_.mouseLocationOutsideOfEventStream();
    res.x *= dpi_scale;
    res.y = height - res.y * dpi_scale;  // Map from bottom left to top left.
    var buttons = PlaskRawMac.NSEvent.pressedMouseButtons();
    for (var i = 0; i < 6; ++i) {
      res[buttonNumberToName(i + 1)] = ((buttons >> i) & 1) === 1;
    }
    return res;
  };
};
inherits(exports.Window, events.EventEmitter);
exports.Window.screensInfo = PlaskRawMac.NSWindow.screensInfo;

exports.simpleWindow = function(obj) {
  // NOTE(deanm): Moving to a settings object to reduce the pollution of the
  // main simpleWindow object.  For now fall back for compat.
  var settings = obj.settings;
  if (settings === undefined) settings = { };

  var wintype = settings.type === '2dx' ? '3d+skia' : '3d';
  var width = settings.width === undefined ? 400 : settings.width;
  var height = settings.height === undefined ? 300 : settings.height;

  var syphon_server = null;

  // TODO(deanm): Fullscreen.
  var window_ = new exports.Window(
      width, height, {type: wintype,
                      multisample: settings.multisample === true,
                      display: settings.display,
                      borderless: settings.borderless === undefined ?
                          settings.fullscreen : settings.borderless,
                      fullscreen: settings.fullscreen,
                      highdpi: settings.highdpi});

  if (settings.position !== undefined) {
    var position_x = settings.position.x;
    var position_y = settings.position.y;
    if (position_y < 0 || isNegZero(position_y))
      position_y = window_.screenSize().height + position_y;
    if (position_x < 0 || isNegZero(position_x))
      position_x = window_.screenSize().width + position_x;
    window_.setFrameTopLeftPoint(position_x, position_y);
  } else if (settings.center === true ||
             (settings.fullscreen !== true && settings.center !== false)) {
    window_.center();
  }

  var gl_ = window_.context;

  // obj.window = window_;
  obj.width = width;
  obj.height = height;

  if (settings.title !== undefined)
    window_.setTitle(settings.title);

  obj.setTitle = function(title) { return window_.setTitle(title); };
  obj.setFullscreen = function(title) { return window_.setFullscreen(title); };

  obj.hideCursor = function() { return window_.hideCursor(); };
  obj.unhideCursor = function() { return window_.unhideCursor(); };
  obj.setCursor  = function(name) { return window_.setCursor(name); };
  obj.pushCursor = function(name) { return window_.pushCursor(name); };
  obj.popCursor  = function() { return window_.popCursor(); };
  obj.setCursorPosition = function(x, y) { return window_.setCursorPosition(x, y); };
  obj.warpCursorPosition = function(x, y) { return window_.warpCursorPosition(x, y); };
  obj.associateMouse = function(connected) { return window_.associateMouse(connected); };

  if (settings.cursor === false)
    window_.hideCursor();

  obj.getRelativeMouseState = function() {
    return window_.getRelativeMouseState();
  };

  var bitmap_canvas = null;  // Protected from getting clobbered on obj.
  var gpu_canvas = null;
  var canvas = null;

  // Default 3d2d windows to vsync also.
  if (settings.type !== '3d' || settings.vsync === true)
    gl_.setSwapInterval(1);
  if (settings.type === '3d') {  // Don't expose gl for 3d2d windows.
    obj.gl = gl_;
  } else {  // Create a canvas and paint for 3d2d windows.
    obj.paint = new exports.SkPaint;
    if (settings.type === '2dx') {  // GPU accelerated
      canvas = gpu_canvas = new exports.SkCanvas(gl_);
      canvas.width = width; canvas.height = height;
      obj.gl = gl_;  // Expose the OpenGL context for mixed usage.
    } else {
      canvas = bitmap_canvas = exports.SkCanvas.create(width, height);  // Offscreen.
    }
    obj.canvas = canvas;
  }
  if (settings.syphon_server !== undefined) {
    syphon_server = gl_.createSyphonServer(settings.syphon_server);
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
  var framenum = 0;
  var frame_start_time = Date.now();

  if ('draw' in obj)
    draw = obj.draw;

  obj.redraw = function() {
    if (gl_ !== undefined)
      gl_.makeCurrentContext();
    if (draw !== null) {
      obj.framenum = framenum;
      obj.frametime = (Date.now() - frame_start_time) / 1000;  // Secs.
      try {
        obj.draw();
      } catch (ex) {
        sys.error('Exception caught in simpleWindow draw:\n' +
                  ex + '\n' + ex.stack);
      }
      framenum++;
    }

    // TODO(deanm): For bitmap_canvas too?
    if (gpu_canvas !== null) gpu_canvas.flush();

    if (bitmap_canvas !== null) {  // 3d2d
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

    gl_.blit();  // Update the screen automatically.
  };

  // Sort of a debouncing version of redraw, which is convenient for use in
  // interaction event callbacks like mouse and keyboard.  If you have a big
  // flood of mouse move events, you don't want to synchronously redraw for
  // each one. This throttles it a bit by only doing the redraw the next time
  // around on the event loop.
  var redraw_soon_handle = null;
  obj.redrawSoon = function() {
    if (redraw_soon_handle === null) {
      redraw_soon_handle = setTimeout(function() {
        redraw_soon_handle = null;
        obj.redraw();
      }, 0);
    }
  };

  obj.redraw();  // Draw the first frame.

  return obj;
};


// new Vec3(x, y, z)
//
// A class representing a 3 dimensional point and/or vector.  There isn't a
// good reason to differentiate between the two, and you often want to change
// how you think about the same set of values.  So there is only "vector".
//
// The class is designed without accessors or individual mutators, you should
// access the x, y, and z values directly on the object.
//
// Almost all of the core operations happen in place, writing to the current
// object.  If you want a copy, you can call `dup`.  For convenience, many
// operations have a passed-tense version that returns a new object.  Most
// methods return `this` to support chaining.
function Vec3(x, y, z) {
  this.x = x; this.y = y; this.z = z;
}

// this set(x, y, z)
Vec3.prototype.set = function(x, y, z) {
  this.x = x; this.y = y; this.z = z;

  return this;
};

// this setVec3(Vec3 v)
Vec3.prototype.setVec3 = function(v) {
  this.x = v.x; this.y = v.y; this.z = v.z;

  return this;
};

// this cross2(Vec3 a, Vec3 b)
//
// Cross product, this = a x b.
Vec3.prototype.cross2 = function(a, b) {
  var ax = a.x, ay = a.y, az = a.z,
      bx = b.x, by = b.y, bz = b.z;

  this.x = ay * bz - az * by;
  this.y = az * bx - ax * bz;
  this.z = ax * by - ay * bx;

  return this;
};

// this cross(Vec3 b)
//
// Cross product, this = this x b.
Vec3.prototype.cross = function(b) {
  return this.cross2(this, b);
};

// float dot(Vec3 b)
//
// Returns the dot product, this . b.
Vec3.prototype.dot = function(b) {
  return this.x * b.x + this.y * b.y + this.z * b.z;
};

// this add2(Vec3 a, Vec3 b)
//
// Add two Vec3s, this = a + b.
Vec3.prototype.add2 = function(a, b) {
  this.x = a.x + b.x;
  this.y = a.y + b.y;
  this.z = a.z + b.z;

  return this;
};

// this add(Vec3 b)
//
// Add a Vec3, this = this + b.
Vec3.prototype.add = function(b) {
  return this.add2(this, b);
};

// Vec3 added(Vec3 b)
Vec3.prototype.added = function(b) {
  return new Vec3(this.x + b.x,
                  this.y + b.y,
                  this.z + b.z);
};

// this sub2(Vec3 a, Vec3 b)
//
// Subtract two Vec3s, this = a - b.
Vec3.prototype.sub2 = function(a, b) {
  this.x = a.x - b.x;
  this.y = a.y - b.y;
  this.z = a.z - b.z;

  return this;
};

// this sub(Vec3 b)
//
// Subtract another Vec3, this = this - b.
Vec3.prototype.sub = function(b) {
  return this.sub2(this, b);
};

// Vec3 subbed(Vec3 b)
Vec3.prototype.subbed = function(b) {
  return new Vec3(this.x - b.x,
                  this.y - b.y,
                  this.z - b.z);
};

// this mul2(Vec3 a, Vec3 b)
//
// Multiply two Vec3s, this = a * b.
Vec3.prototype.mul2 = function(a, b) {
  this.x = a.x * b.x;
  this.y = a.y * b.y;
  this.z = a.z * b.z;

  return this;
};

// this mul(Vec3 b)
//
// Multiply by another Vec3, this = this * b.
Vec3.prototype.mul = function(b) {
  return this.mul2(this, b);
};

// Vec3 mulled(Vec3 b)
Vec3.prototype.mulled = function(b) {
  return new Vec3(this.x * b.x,
                  this.y * b.y,
                  this.z * b.z);
};

// this scale(float s)
//
// Multiply by a scalar.
Vec3.prototype.scale = function(s) {
  this.x *= s; this.y *= s; this.z *= s;

  return this;
};

// Vec3 scaled(float s)
Vec3.prototype.scaled = function(s) {
  return new Vec3(this.x * s, this.y * s, this.z * s);
};

// this lerp(Vec3 b, float t)
//
// Interpolate between this and another Vec3 `b`, based on `t`.
Vec3.prototype.lerp = function(b, t) {
  this.x = this.x + (b.x-this.x)*t;
  this.y = this.y + (b.y-this.y)*t;
  this.z = this.z + (b.z-this.z)*t;

  return this;
};

// Vec3 lerped(Vec3 b, float t)
Vec3.prototype.lerped = function(b, t) {
  return new Vec3(this.x + (b.x-this.x)*t,
                  this.y + (b.y-this.y)*t,
                  this.z + (b.z-this.z)*t);
};

// float length()
//
// Magnitude (length).
Vec3.prototype.length = function() {
  var x = this.x, y = this.y, z = this.z;
  return Math.sqrt(x*x + y*y + z*z);
};

// float lengthSquared()
//
// Magnitude squared.
Vec3.prototype.lengthSquared = function() {
  var x = this.x, y = this.y, z = this.z;
  return x*x + y*y + z*z;
};

// float dist(Vec3 b)
//
// Distance to Vec3 `b`.
Vec3.prototype.dist = function(b) {
  var x = b.x - this.x;
  var y = b.y - this.y;
  var z = b.z - this.z;
  return Math.sqrt(x*x + y*y + z*z);
};

// float distSquared(Vec3 b)
//
// Squared Distance to Vec3 `b`.
Vec3.prototype.distSquared = function(b) {
  var x = b.x - this.x;
  var y = b.y - this.y;
  var z = b.z - this.z;
  return x*x + y*y + z*z;
};

// this normalize()
//
// Normalize, scaling so the magnitude is 1.  Invalid for a zero vector.
Vec3.prototype.normalize = function() {
  return this.scale(1/this.length());
};

// Vec3 normalized()
Vec3.prototype.normalized = function() {
  return this.dup().normalize();
};

// Vec3 dup()
//
// Return a new copy of the vector.
Vec3.prototype.dup = function() {
  return new Vec3(this.x, this.y, this.z);
};

Vec3.prototype.debugString = function() {
  return 'x: ' + this.x + ' y: ' + this.y + ' z: ' + this.z;
};


// new Vec2(x, y)
//
// Constructs a 2d vector (x, y).
function Vec2(x, y) {
  this.x = x; this.y = y;
}

// this set(float x, float y)
Vec2.prototype.set = function(x, y) {
  this.x = x; this.y = y

  return this;
};

// this setVec2(Vec2 v)
Vec2.prototype.setVec2 = function(v) {
  this.x = v.x; this.y = v.y;

  return this;
};

// float dot(Vec2 b)
//
// Returns the dot product, this . b.
Vec2.prototype.dot = function(b) {
  return this.x * b.x + this.y * b.y;
};

// this add2(Vec2 a, Vec2 b)
//
// Add two Vec2s, this = a + b.
Vec2.prototype.add2 = function(a, b) {
  this.x = a.x + b.x;
  this.y = a.y + b.y;

  return this;
};

// this add(Vec2 b)
//
// Add a Vec2, this = this + b.
Vec2.prototype.add = function(b) {
  return this.add2(this, b);
};

// Vec2 added(Vec2 b)
//
// Add a Vec2, returning the result as a new Vec2.
Vec2.prototype.added = function(b) {
  return new Vec2(this.x + b.x,
                  this.y + b.y);
};

// this sub2(Vec2 a, Vec2 b)
//
// Subtract two Vec2s, this = a - b.
Vec2.prototype.sub2 = function(a, b) {
  this.x = a.x - b.x;
  this.y = a.y - b.y;

  return this;
};

// this sub(Vec2 b)
//
// Subtract another Vec2, this = this - b.
Vec2.prototype.sub = function(b) {
  return this.sub2(this, b);
};

// Vec2 subbed(Vec2 b)
Vec2.prototype.subbed = function(b) {
  return new Vec2(this.x - b.x,
                  this.y - b.y);
};

// this mul2(Vec2 a, Vec2 b)
//
// Multiply two Vec2s, this = a * b.
Vec2.prototype.mul2 = function(a, b) {
  this.x = a.x * b.x;
  this.y = a.y * b.y;

  return this;
};

// this mul(Vec2 b)
//
// Multiply by another Vec2, this = this * b.
Vec2.prototype.mul = function(b) {
  return this.mul2(this, b);
};

// Vec2 mulled(Vec2 b)
Vec2.prototype.mulled = function(b) {
  return new Vec2(this.x * b.x,
                  this.y * b.y);
};

// this scale(float s)
//
// Multiply by a scalar.
Vec2.prototype.scale = function(s) {
  this.x *= s; this.y *= s;

  return this;
};

// Vec2 scaled(float s)
Vec2.prototype.scaled = function(s) {
  return new Vec2(this.x * s, this.y * s);
};

// this lerp(Vec2 b, float t)
//
// Interpolate between this and another Vec2 `b`, based on `t`.
Vec2.prototype.lerp = function(b, t) {
  this.x = this.x + (b.x-this.x)*t;
  this.y = this.y + (b.y-this.y)*t;

  return this;
};

// Vec2 lerped(Vec2 b, float t)
Vec2.prototype.lerped = function(b, t) {
  return new Vec2(this.x + (b.x-this.x)*t,
                  this.y + (b.y-this.y)*t);
};

// float length()
//
// Magnitude (length).
Vec2.prototype.length = function() {
  var x = this.x, y = this.y;
  return Math.sqrt(x*x + y*y);
};

// float lengthSquared()
//
// Magnitude squared.
Vec2.prototype.lengthSquared = function() {
  var x = this.x, y = this.y;
  return x*x + y*y;
};

// float dist(Vec2 b)
//
// Distance to Vec2 `b`.
Vec2.prototype.dist = function(b) {
  var x = b.x - this.x;
  var y = b.y - this.y;
  return Math.sqrt(x*x + y*y);
};

// float distSquared(Vec2 b)
//
// Squared Distance to Vec2 `b`.
Vec2.prototype.distSquared = function(b) {
  var x = b.x - this.x;
  var y = b.y - this.y;
  return x*x + y*y;
};

// this normalize()
//
// Normalize, scaling so the magnitude is 1.  Invalid for a zero vector.
Vec2.prototype.normalize = function() {
  return this.scale(1/this.length());
};

// Vec2 normalized()
Vec2.prototype.normalized = function() {
  return this.dup().normalize();
};

// this rotate(float theta)
//
// Rotate around the origin by `theta` radians (counter-clockwise).
Vec2.prototype.rotate = function(theta) {
  var st = Math.sin(theta);
  var ct = Math.cos(theta);
  var x = this.x, y = this.y;
  this.x = x * ct - y * st;
  this.y = x * st + y * ct;
  return this;
};

// Vec2 rotated(float theta)
Vec2.prototype.rotated = function(theta) {
  return this.dup().rotate(theta);
};

// this reflect(Vec2 n)
//
// Reflect a vector about the normal `n`.  The vectors should both be unit.
Vec2.prototype.reflect = function(n) {
  // r = u - 2(u.n)n
  // This could could basically be:
  //   this.sub(n.scaled(this.dot(n) * 2));
  // But we avoid some extra object allocated / etc and just flatten it.
  var s = this.dot(n) * 2;
  this.x -= n.x * s;
  this.y -= n.y * s;

  return this;
};

// Vec2 reflected(Vec2 n)
Vec2.prototype.reflected = function(n) {
  var s = this.dot(n) * 2;
  return Vec2(this.x - n.x * s,
              this.y - n.y * s);
};

// Vec2 dup()
//
// Return a new copy of the vector.
Vec2.prototype.dup = function() {
  return new Vec2(this.x, this.y);
};

Vec2.prototype.debugString = function() {
  return 'x: ' + this.x + ' y: ' + this.y;
};


// TODO(deanm): Vec4 is currently a skeleton container, it should match the
// features of Vec3.

// new Vec4(x, y, z, w)
function Vec4(x, y, z, w) {
  this.x = x; this.y = y; this.z = z; this.w = w;
}

// this set(x, y, z, w)
Vec4.prototype.set = function(x, y, z, w) {
  this.x = x; this.y = y; this.z = z; this.w = w;

  return this;
};

// this setVec4(Vec4 v)
Vec4.prototype.setVec4 = function(v) {
  this.x = v.x; this.y = v.y; this.z = v.z; this.w = v.w;

  return this;
};

// this scale(float s)
//
// Multiply by a scalar.
Vec4.prototype.scale = function(s) {
  this.x *= s; this.y *= s; this.z *= s; this.w *= s;

  return this;
};

// Vec4 scaled(float s)
Vec4.prototype.scaled = function(s) {
  return new Vec4(this.x * s, this.y * s, this.z * s, this.w * s);
};

// Vec4 dup()
//
// Return a new copy of the vector.
Vec4.prototype.dup = function() {
  return new Vec4(this.x, this.y, this.z, this.w);
};

// Vec3 toVec3()
//
// Return a new vector of (x, y, z), dropping w.
Vec4.prototype.toVec3 = function() {
  return new Vec3(this.x, this.y, this.z);
};


// new Mat3()
//
// Constructs an identity matrix.
//
// Mat3 represents an 3x3 matrix.  The elements are, using mathematical notation
// numbered starting from 1 as aij, where i is the row and j is the column:
//
//     a11 a12 a13
//     a21 a22 a23
//     a31 a32 a33
//
// Almost all operations are multiplies to the current matrix, and happen in
// place.  You can use `dup` to return a copy.  Most operations return this to
// support chaining.
//
// It is common to use `toFloat32Array` to get a Float32Array in OpenGL (column
// major) memory ordering.  NOTE: The code tries to be explicit about whether
// things are row major or column major, but remember that GLSL works in
// column major ordering, and this code generally uses row major ordering.
function Mat3() {
  this.reset();
}

// this reset()
//
// Reset to the identity matrix.
Mat3.prototype.reset = function() {
  this.set3x3r(1, 0, 0,
               0, 1, 0,
               0, 0, 1);

  return this;
};

// Mat3 dup()
//
// Return a new copy of the matrix.
Mat3.prototype.dup = function() {
  var m = new Mat3();  // TODO(deanm): This could be better.
  m.set3x3r(this.a11, this.a12, this.a13,
            this.a21, this.a22, this.a23,
            this.a31, this.a32, this.a33);
  return m;
};


// this set3x3r(a11, a12, a13, a21, a22, a23, a31, a32, a33)
//
// Set the full 9 elements of the 3x3 matrix, arguments in row major order.
// The elements are specified in row major order.
Mat3.prototype.set3x3r = function(a11, a12, a13, a21, a22, a23, a31, a32, a33) {
  this.a11 = a11; this.a12 = a12; this.a13 = a13;
  this.a21 = a21; this.a22 = a22; this.a23 = a23;
  this.a31 = a31; this.a32 = a32; this.a33 = a33;

  return this;
};

// TODO(deanm): set3x3c.

// this mul2(Mat3 a, Mat3 b)
//
// Matrix multiply this = a * b
Mat3.prototype.mul2 = function(a, b) {
  var a11 = a.a11, a12 = a.a12, a13 = a.a13,
      a21 = a.a21, a22 = a.a22, a23 = a.a23,
      a31 = a.a31, a32 = a.a32, a33 = a.a33;
  var b11 = b.a11, b12 = b.a12, b13 = b.a13,
      b21 = b.a21, b22 = b.a22, b23 = b.a23,
      b31 = b.a31, b32 = b.a32, b33 = b.a33;

  this.a11 = a11*b11 + a12*b21 + a13*b31;
  this.a12 = a11*b12 + a12*b22 + a13*b32;
  this.a13 = a11*b13 + a12*b23 + a13*b33;
  this.a21 = a21*b11 + a22*b21 + a23*b31;
  this.a22 = a21*b12 + a22*b22 + a23*b32;
  this.a23 = a21*b13 + a22*b23 + a23*b33;
  this.a31 = a31*b11 + a32*b21 + a33*b31;
  this.a32 = a31*b12 + a32*b22 + a33*b32;
  this.a33 = a31*b13 + a32*b23 + a33*b33;

  return this;
};

// this mul(Mat3 b)
//
// Matrix multiply this = this * b
Mat3.prototype.mul = function(b) {
  return this.mul2(this, b);
};

// Vec2 mulVec2(Vec2 v)
//
// Multiply Vec2 `v` by the current matrix, returning a Vec2 of `this * v`.
// Ignores perspective (only applies scale and translation).
Mat3.prototype.mulVec2 = function(v) {
  var x = v.x, y = v.y;
  return new Vec2(this.a11*x + this.a12*y + this.a13,
                  this.a21*x + this.a22*y + this.a23);
};

// Vec2 mulVec2p(Vec2 v)
//
// Multiply Vec2 `v` by the current matrix and perform a perspective divide.
// Implies that the missing z component of `v` would be 1.
Mat3.prototype.mulVec2p = function(v) {
  var x = v.x, y = v.y;
  var z = this.a31*x + this.a32*y + this.a33;
  return new Vec2((this.a11*x + this.a12*y + this.a13) / z,
                  (this.a21*x + this.a22*y + this.a23) / z);
}

// Vec3 mulVec3(Vec3 v)
//
// Multiply Vec3 `v` by the current matrix, returning a Vec3 of `this * v`.
Mat3.prototype.mulVec3 = function(v) {
  var x = v.x, y = v.y, z = v.z;
  return new Vec3(this.a11*x + this.a12*y + this.a13*z,
                  this.a21*x + this.a22*y + this.a23*z,
                  this.a31*x + this.a32*y + this.a33*z);
};

// this adjoint()
//
// Reference: http://en.wikipedia.org/wiki/Adjugate_matrix
Mat3.prototype.adjoint = function() {
  var a11 = this.a11, a12 = this.a12, a13 = this.a13,
      a21 = this.a21, a22 = this.a22, a23 = this.a23,
      a31 = this.a31, a32 = this.a32, a33 = this.a33;

  // Cofactor and transpose.
  this.a11 = a22*a33 - a32*a23;
  this.a12 = a32*a13 - a12*a33;
  this.a13 = a12*a23 - a22*a13;
  this.a21 = a23*a31 - a33*a21;
  this.a22 = a33*a11 - a13*a31;
  this.a23 = a13*a21 - a23*a11;
  this.a31 = a21*a32 - a31*a22;
  this.a32 = a31*a12 - a11*a32;
  this.a33 = a11*a22 - a21*a12;

  return this;
};

// this invert()
//
// Invert the matrix.  The matrix must be invertible.
Mat3.prototype.invert = function() {
  var a11 = this.a11, a12 = this.a12, a13 = this.a13,
      a21 = this.a21, a22 = this.a22, a23 = this.a23,
      a31 = this.a31, a32 = this.a32, a33 = this.a33;

  var invdet = 1 / this.determinant();

  // Cofactor and transpose.
  this.a11 = (a22*a33 - a32*a23) * invdet;
  this.a12 = (a32*a13 - a12*a33) * invdet;
  this.a13 = (a12*a23 - a22*a13) * invdet;
  this.a21 = (a23*a31 - a33*a21) * invdet;
  this.a22 = (a33*a11 - a13*a31) * invdet;
  this.a23 = (a13*a21 - a23*a11) * invdet;
  this.a31 = (a21*a32 - a31*a22) * invdet;
  this.a32 = (a31*a12 - a11*a32) * invdet;
  this.a33 = (a11*a22 - a21*a12) * invdet;

  return this;
};

// Mat3 inverted()
//
// Return an inverted matrix.  The matrix must be invertible.
Mat3.prototype.inverted = function() { return this.dup().invert(); };

// this transpose()
//
// Transpose the matrix, rows become columns and columns become rows.
Mat3.prototype.transpose = function() {
  var a11 = this.a11, a12 = this.a12, a13 = this.a13,
      a21 = this.a21, a22 = this.a22, a23 = this.a23,
      a31 = this.a31, a32 = this.a32, a33 = this.a33;

  this.a11 = a11; this.a12 = a21; this.a13 = a31;
  this.a21 = a12; this.a22 = a22; this.a23 = a32;
  this.a31 = a13; this.a32 = a23; this.a33 = a33;

  return this;
};

// float determinant()
Mat3.prototype.determinant = function() {
  var a11 = this.a11, a12 = this.a12, a13 = this.a13,
      a21 = this.a21, a22 = this.a22, a23 = this.a23,
      a31 = this.a31, a32 = this.a32, a33 = this.a33;

  return a11*(a22*a33 - a23*a32) - a12*(a21*a33 - a23*a31) +
         a13*(a21*a32 - a22*a31);
};

// this pmapSquareQuad(x0, y0, x1, y1, x2, y2, x3, y3)
//
// Find mapping between (0, 0), (1, 0), (1, 1), (0, 1) to (x0,y0) .. (x3, y3).
Mat3.prototype.pmapSquareQuad = function(x0, y0, x1, y1, x2, y2, x3, y3) {
  var px = x0-x1+x2-x3;
  var py = y0-y1+y2-y3;

  var dx1 = x1-x2, dy1 = y1-y2, dx2 = x3-x2, dy2 = y3-y2;
  var del = dx1*dy2 - dx2*dy1;
  // TODO check del === 0

  this.a31 = (px*dy2 - dx2*py) / del;
  this.a32 = (dx1*py - px*dy1) / del;
  this.a33 = 1;
  this.a11 = x1-x0+this.a31*x1;
  this.a12 = x3-x0+this.a32*x3;
  this.a13 = x0;
  this.a21 = y1-y0+this.a31*y1;
  this.a22 = y3-y0+this.a32*y3;
  this.a23 = y0;

  return this;
};

// this negate()
Mat3.prototype.negate = function() {
  this.a11 = -this.a11; this.a12 = -this.a12; this.a13 = -this.a13;
  this.a21 = -this.a21; this.a22 = -this.a22; this.a23 = -this.a23;
  this.a31 = -this.a31; this.a32 = -this.a32; this.a33 = -this.a33;

  return this;
};

// this pmapQuadQuad(x0, y0, x1, y1, x2, y2, x3, y3,
//                   u0, v0, u1, v1, u2, v2, u3, v3)
//
// Overwrite `this` with a matrix that maps from (x0,y0) .. (x3,y3) to
// (u0,v0) .. (u3,v3).  NOTE: This is sensitive to the coordinate ordering,
// they should follow the pattern as `pmapSquareQuad`.
//
// Reference: Paul Heckbert "Fundamentals of Texture Mapping and Image Warping"
Mat3.prototype.pmapQuadQuad = function(x0, y0, x1, y1, x2, y2, x3, y3,
                                       u0, v0, u1, v1, u2, v2, u3, v3) {
  var ms = new Mat3();
  ms.pmapSquareQuad(x0, y0, x1, y1, x2, y2, x3, y3);
  ms.adjoint();  // TODO(deanm): Check det === 0.

  var mt = new Mat3();
  mt.pmapSquareQuad(u0, v0, u1, v1, u2, v2, u3, v3);
  //this.mul2(ms, mt);
  this.mul2(mt, ms);

  return this;
};

// Float32Array toFloat32Array()
//
// Return a Float32Array in suitable column major order for WebGL.
Mat3.prototype.toFloat32Array = function() {
  return new Float32Array([this.a11, this.a21, this.a31,
                           this.a12, this.a22, this.a32,
                           this.a13, this.a23, this.a33]);
};

Mat3.prototype.debugString = function() {
  var s = [this.a11, this.a12, this.a13,
           this.a21, this.a22, this.a23,
           this.a31, this.a32, this.a33];
  var row_lengths = [0, 0, 0];
  for (var i = 0; i < 9; ++i) {
    s[i] += '';  // Stringify.
    var len = s[i].length;
    var row = i % 3;
    if (row_lengths[row] < len)
      row_lengths[row] = len;
  }

  var out = '';
  for (var i = 0; i < 9; ++i) {
    var len = s[i].length;
    var row_len = row_lengths[i % 3];
    var num_spaces = row_len - len;
    while (num_spaces--) out += ' ';
    out += s[i] + ((i % 3) === 2 ? '\n' : '  ');
  }

  return out;
};


// new Mat4()
//
// Constructs an identity matrix.
//
// Mat4 represents an 4x4 matrix.  The elements are, using mathematical notation
// numbered starting from 1 as aij, where i is the row and j is the column:
//
//     a11 a12 a13 a14
//     a21 a22 a23 a24
//     a31 a32 a33 a34
//     a41 a42 a43 a44
//
// Almost all operations are multiplies to the current matrix, and happen in
// place.  You can use `dup` to return a copy.  Most operations return this to
// support chaining.
//
// It is common to use `toFloat32Array` to get a Float32Array in OpenGL (column
// major) memory ordering.  NOTE: The code tries to be explicit about whether
// things are row major or column major, but remember that GLSL works in
// column major ordering, and this code generally uses row major ordering.
function Mat4() {
  this.reset();
}

// this set4x4r(a11, a12, a13, a14, a21, a22, a23, a24,
//              a31, a32, a33, a34, a41, a42, a43, a44)
//
// Set the full 16 elements of the 4x4 matrix, arguments in row major order.
// The elements are specified in row major order.
Mat4.prototype.set4x4r = function(a11, a12, a13, a14, a21, a22, a23, a24,
                                  a31, a32, a33, a34, a41, a42, a43, a44) {
  this.a11 = a11; this.a12 = a12; this.a13 = a13; this.a14 = a14;
  this.a21 = a21; this.a22 = a22; this.a23 = a23; this.a24 = a24;
  this.a31 = a31; this.a32 = a32; this.a33 = a33; this.a34 = a34;
  this.a41 = a41; this.a42 = a42; this.a43 = a43; this.a44 = a44;

  return this;
};

// TODO(deanm): set4x4c.

// this reset()
//
// Reset to the identity matrix.
Mat4.prototype.reset = function() {
  this.set4x4r(1, 0, 0, 0,
               0, 1, 0, 0,
               0, 0, 1, 0,
               0, 0, 0, 1);

  return this;
};

// this mul2(a, b)
//
// Matrix multiply `this = a * b`
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

// this mul(b)
//
// Matrix multiply `this = this * b`
Mat4.prototype.mul = function(b) {
  return this.mul2(this, b);
};

// this mul4x4r(b11, b12, b13, b14, b21, b22, b23, b24,
//              b31, b32, b33, b34, b41, b42, b43, b44)
//
// Multiply the current matrix by 16 elements that would compose a Mat4
// object, but saving on creating the object.  this = this * b.
// The elements are specified in row major order.
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

// TODO(deanm): mul4x4c.

// TODO(deanm): Some sort of mat3x3.  There are two ways you could do it
// though, just multiplying the 3x3 portions of the 4x4 matrix, or doing a
// 4x4 multiply with the last row/column implied to be 0, 0, 0, 1.  This
// keeps true to the original matrix even if it's last row is not 0, 0, 0, 1.

// this rotate(theta, x, y, z)
//
// IN RADIANS, not in degrees like OpenGL.  Rotate about x, y, z.
// The caller must supply x, y, z as a unit vector.
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

// this translate(x, y, z)
//
// Multiply by a translation of x, y, and z.
Mat4.prototype.translate = function(dx, dy, dz) {
  // TODO(deanm): Special case the multiply since most goes unchanged.
  this.mul4x4r(1, 0, 0, dx,
               0, 1, 0, dy,
               0, 0, 1, dz,
               0, 0, 0,  1);

  return this;
};

// this scale(x, y, z)
//
// Multiply by a scale of x, y, and z.
Mat4.prototype.scale = function(sx, sy, sz) {
  // TODO(deanm): Special case the multiply since most goes unchanged.
  this.mul4x4r(sx,  0,  0, 0,
                0, sy,  0, 0,
                0,  0, sz, 0,
                0,  0,  0, 1);

  return this;
};

// this lookAt(ex, ey, ez, cx, cy, cz, ux, uy, uz)
//
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

// this frustum(l, r, b, t, n, f)
//
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

// this perspective(fovy, aspect, znear, zfar)
//
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

// this ortho(l, r, b, t, n, f)
//
// Multiply by a orthographic matrix, computed from the clipping planes.
Mat4.prototype.ortho = function(l, r, b, t, n, f) {
  this.mul4x4r(2/(r-l),        0,        0,  (r+l)/(l-r),
                     0,  2/(t-b),        0,  (t+b)/(b-t),
                     0,        0,  2/(n-f),  (f+n)/(n-f),
                     0,        0,        0,            1);

  return this;
};

// this invert()
//
// Invert the matrix.  The matrix must be invertible.
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

// Mat4 inverted()
//
// Return an inverted matrix.  The matrix must be invertible.
Mat4.prototype.inverted = function() { return this.dup().invert(); };

// this transpose()
//
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

// Vec3 mulVec3(Vec3 v)
//
// Multiply Vec3 `v` by the current matrix, returning a Vec3 of this * v.
Mat4.prototype.mulVec3 = function(v) {
  var x = v.x, y = v.y, z = v.z;
  return new Vec3(this.a14 + this.a11*x + this.a12*y + this.a13*z,
                  this.a24 + this.a21*x + this.a22*y + this.a23*z,
                  this.a34 + this.a31*x + this.a32*y + this.a33*z);
};

// Vec3 mulVec3p(Vec3 v)
//
// Multiply Vec3 `v` by the current matrix, returning a Vec3 of this * v.
// Performs the perspective divide by `w`.
Mat4.prototype.mulVec3p = function(v) {
  var x = v.x, y = v.y, z = v.z;
  var w = this.a44 + this.a41*x + this.a42*y + this.a43*z;
  return new Vec3((this.a14 + this.a11*x + this.a12*y + this.a13*z)/w,
                  (this.a24 + this.a21*x + this.a22*y + this.a23*z)/w,
                  (this.a34 + this.a31*x + this.a32*y + this.a33*z)/w);
};

// Vec4 mulVec4(Vec4 v)
//
// Multiply Vec4 `v` by the current matrix, returning a Vec4 of this * v.
Mat4.prototype.mulVec4 = function(v) {
  var x = v.x, y = v.y, z = v.z, w = v.w;
  return new Vec4(this.a14*w + this.a11*x + this.a12*y + this.a13*z,
                  this.a24*w + this.a21*x + this.a22*y + this.a23*z,
                  this.a34*w + this.a31*x + this.a32*y + this.a33*z,
                  this.a44*w + this.a41*x + this.a42*y + this.a43*z);
};

// Mat4 dup()
//
// Return a new copy of the matrix.
Mat4.prototype.dup = function() {
  var m = new Mat4();  // TODO(deanm): This could be better.
  m.set4x4r(this.a11, this.a12, this.a13, this.a14,
            this.a21, this.a22, this.a23, this.a24,
            this.a31, this.a32, this.a33, this.a34,
            this.a41, this.a42, this.a43, this.a44);
  return m;
};

// Float32Array toFloat32Array()
//
// Return a Float32Array in suitable column major order for WebGL.
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

// Given a string of GLSL source `source` of type `type`, create the shader
// and compile `source` to the shader.  Throws on error.  Returns the newly
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

// Given the source text of the vertex shader `vsource` and fragment shader
// `fsource`, create a new program with the shaders together.  Throws on
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


// new MagicProgram(gl, program)
//
// Create a MagicProgram object, which is a wrapper around a GLSL program to
// make it easier to access uniforms and attribs.
function MagicProgram(gl, program) {
  this.gl = gl;
  this.program = program;

  function makeSetter(type, loc) {
    switch (type) {
      case gl.BOOL:  // NOTE: bool could be set with 1i or 1f.
      case gl.INT:
      case gl.SAMPLER_2D:
      case gl.SAMPLER_2D_RECT:
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
      case gl.FLOAT_MAT3:
        return function(mat3) {
          gl.uniformMatrix3fv(loc, false, mat3.toFloat32Array());
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

MagicProgram.prototype.use = function() {
  this.gl.useProgram(this.program);
};

MagicProgram.prototype.relink = function() {
  var gl = this.gl, program = this.program;
  gl.linkProgram(program);
  if (gl.getProgramParameter(program, gl.LINK_STATUS) !== true)
    throw gl.getProgramInfoLog(program);
  return true;
};

// static MagicProgram createFromStrings(gl, string vstr, string fstr)
//
// Create a new MagicProgram from the vertex shader source string `vstr` and
// the fragment shader source string `fstr`.
MagicProgram.createFromStrings = function(gl, vstr, fstr) {
  return new MagicProgram(gl, webGLcreateProgramFromShaderSources(
      gl, vstr, fstr));
};

// static MagicProgram createFromFiles(gl, vfilename, ffilename, opts)
//
// Create a new MagicProgram from the vertex shader source in file `vfilename`
// and the fragment shader source in file `ffilename`.
//
// If `opts` is supplied and `opts.watch` is true, the files will be watched
// for changes and automatically reloaded with a success or failure message
// printed to the console.
MagicProgram.createFromFiles = function(gl, vfn, ffn, opts) {
  function make() {
    return MagicProgram.createFromStrings(
      gl, fs.readFileSync(vfn, 'utf8'), fs.readFileSync(ffn, 'utf8'));
  }

  var mprogram = make();

  if (opts && opts.watch === true) {
    function update(e, filename) {
      try {
        var new_mprogram = make();
        mprogram.program = new_mprogram.program;
        console.log("Updated MagicProgram for " + filename);
      } catch(e) {
        console.log("Failed to update MagicProgram: " + e);
      }
    }
    fs.watch(vfn, { persistent: false }, update);
    fs.watch(ffn, { persistent: false }, update);
  }

  return mprogram;
};

// static MagicProgram createFromBasename(gl, directory, base, opts)
//
// Create a new MagicProgram from the vertex shader source in file
// `base`.vshader and the fragment shader source in file `base`.fshader in the
// directory `directory`.
//
//     // Creates a magic program from myshader.vshader and myshader.fshader in
//     // the same directory as the running source JavaScript file.
//     var mp = MagicProgram.createFromBasename(gl, __dirname, 'myshader');
MagicProgram.createFromBasename = function(gl, directory, base, opts) {
  return MagicProgram.createFromFiles(
      gl,
      path.join(directory, base + '.vshader'),
      path.join(directory, base + '.fshader'),
      opts);
};

exports.kPI  = kPI;
exports.kPI2 = kPI2;
exports.kPI4 = kPI4;
exports.k2PI = k2PI;
exports.kRadToDeg = 180/kPI;
exports.kDegToRad = kPI/180;
exports.kLN2  = kLN2;
exports.kLN10 = kLN10;

exports.min = min;
exports.max = max;
exports.clamp = clamp;
exports.lerp = lerp;
exports.smoothstep = smoothstep;
exports.smootherstep = smootherstep;

exports.fract  = fract;
exports.fract2 = fract2;
exports.fract3 = fract3;

exports.Vec3 = Vec3;
exports.Vec2 = Vec2;
exports.Vec4 = Vec4;
exports.Mat3 = Mat3;
exports.Mat4 = Mat4;

exports.gl = {MagicProgram: MagicProgram};
