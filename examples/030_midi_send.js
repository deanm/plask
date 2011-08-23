// Plask.
// (c) Dean McNamee <dean@gmail.com>, 2011.
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

var plask = require('plask');

plask.simpleWindow({
  settings: {
    width: 400,
    height: 300
  },

  init: function() {
    this.framerate(30);
    var canvas = this.canvas, paint = this.paint;
    paint.setAntiAlias(true);

    var midi = new plask.MidiOut();  // Create a midi output.
    midi.createVirtual('030_midi_send');  // Make it a virtual output.

    canvas.clear(0, 0, 0, 255);  // Draw the background.
    paint.setColor(0, 0, 255, 255);

    this.on('leftMouseDown', function(e) {
      var note = (e.x / this.width) * 50 + 50;
      var vel = (1 - (e.y / this.height)) * 127;

      // Trigger a 300ms long note.
      midi.noteOn(1, note, vel);  // Send a MIDI note on channel 1.
      setTimeout(function() { midi.noteOff(1, note, vel); }, 300);

      canvas.drawCircle(paint, e.x, e.y, 10);
    });
  },

  draw: function() {
    var canvas = this.canvas, paint = this.paint;
    canvas.drawColor(0, 0, 0, 30);  // Fade.
  }
});
