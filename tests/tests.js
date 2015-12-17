var plask = require('plask');

function assert_eq(a, b) {
  if (a !== b) {
    var m = 'assert_eq: ' + JSON.stringify(a) + ' !== ' + JSON.stringify(b);
    console.trace(m); throw m;
  }
}

function assert_throws(estr, cb) {
  try {
    cb();
  } catch(e) {
    assert_eq(estr, e.toString());
    return;
  }
  throw 'Expected an exception.';
}

function test_path() {
  var path = new plask.SkPath();
  path.moveTo(1, 2);
  path.lineTo(12, 15);
  path.cubicTo(16, 17, 18, 19, 20, 21);
  assert_eq("M1 2L12 15C16 17 18 19 20 21", path.toSVGString());
  path.transform(1, 0, 0, 0, 1, 0, 0, 0, 1);
  assert_eq("M1 2L12 15C16 17 18 19 20 21", path.toSVGString());
  path.transform(1, 0, 3, 0, 1, 7, 0, 0, 1);  // translate by (3, 7)
  assert_eq("M4 9L15 22C19 24 21 26 23 28", path.toSVGString());
  assert_eq(true, path.fromSVGString(" M 5 2L12-15C16 17 18 19 20 21"));
  assert_eq("M5 2L12 -15C16 17 18 19 20 21", path.toSVGString());
  // assert_eq(false, path.fromSVGString("M 5"));  // crashes Skia (bug 3491).
}

function test_fracts() {
  assert_eq( 0.25, plask.fract(  1.25));
  assert_eq( 0.25, plask.fract( -1.75));
  assert_eq( 0.25, plask.fract2( 1.25));
  assert_eq( 0.25, plask.fract2(-1.25));
  assert_eq( 0.25, plask.fract3( 1.25));
  assert_eq(-0.25, plask.fract3(-1.25));
}

function test_read_rgb() {
  var canvas = new plask.SkCanvas(3, 4);
  canvas.clear(1, 2, 3, 255);
  var pixels = canvas.pixels;
  assert_eq(3, pixels[0]);
  assert_eq(2, pixels[1]);
  assert_eq(1, pixels[2]);
  //assert_eq(3, pixels.width);
  //assert_eq(4, pixels.height);
}

test_path();
test_fracts();
test_read_rgb();
