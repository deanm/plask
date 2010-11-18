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

exports.Window = function(width, height, opts) {
  var nswindow_ = new PlaskRawMac.NSWindow(
      opts.type === '3d' ? 1 : 0, width, height, opts.multisample === true);
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
        var te = {
          type: nsEventNameToEmitName(type),
          str: e.characters(),
          keyCode: e.keyCode(),  // I'll probably regret this.
        };
        this_.emit(te.type, te);
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
      case PlaskRawMac.NSEvent.NSScrollWheel:
        var loc = e.locationInWindow();
        var te = {
          type: 'scrollWheel',
          x: loc.x,
          y: height - loc.y,
          dx: e.deltaX(),
          dy: e.deltaY(),  // Doesn't need flipping since it's in device space.
          dz: e.deltaZ()
        };
        this_.emit(te.type, te);
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
      width, height, {type: wintype, multisample: obj.multisample === true});

  var gl_ = window_.context;

  obj.window = window_;
  obj.width = width;
  obj.height = height;

  if (obj.title !== undefined)
    window_.setTitle(obj.title);

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
