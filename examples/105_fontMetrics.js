// (c) 2013 Marcin Ignac

var plask = require('plask');
var fs = require('fs');

plask.simpleWindow({
  settings: {
    width: 1280,
    height: 720,
  },
  init: function() {
    var canvas = this.canvas;
    var paint = this.paint;

    canvas.clear(255, 255, 255, 255);

    var fontSize = 200;
    paint.setFontFamily("Arial");
    paint.setTextSize(fontSize);
    paint.setFlags(paint.kAntiAliasFlag);
    paint.setFill();
    paint.setColor(0, 0, 0, 255);

    var text = "abcdefgÄÆŚŹ";

    var lineBounds = this.getTextBounds(paint, text);
    var fontMetrics = paint.getFontMetrics();
    var lineHeight = fontMetrics.descent - fontMetrics.ascent + fontMetrics.leading;

    var x = (this.width - lineBounds.w) / 2;
    var y = this.height / 2;

    canvas.drawText(paint, text, x, y);

    paint.setColor(230, 230, 230, 255);
    canvas.drawText(paint, text, x, y + lineHeight);

    paint.setTextSize(12);
    paint.setFill();
    paint.setColor(255, 0, 0, 255);

    canvas.drawLine(paint, x, y, x + lineBounds.w, y);
    canvas.drawText(paint, "BASELINE", x + 10, y + 16);

    paint.setColor(0, 150, 0, 255);
    canvas.drawLine(paint, x, y + fontMetrics.ascent, x + lineBounds.w, y + fontMetrics.ascent);
    canvas.drawText(paint, "ASCENT", x + 10, y + 16 + fontMetrics.ascent);

    canvas.drawLine(paint, x, y + fontMetrics.descent, x + lineBounds.w, y + fontMetrics.descent);
    canvas.drawText(paint, "DESCENT", x + 10, y + 16 + fontMetrics.descent);

    paint.setColor(0, 0, 200, 255);
    canvas.drawLine(paint, x, y + fontMetrics.top, x + lineBounds.w, y + fontMetrics.top);
    canvas.drawText(paint, "TOP", x + 10, y + 16 + fontMetrics.top);

    canvas.drawLine(paint, x, y + fontMetrics.bottom, x + lineBounds.w, y + fontMetrics.bottom);
    canvas.drawText(paint, "BOTTOM", x + 10, y + 16 + fontMetrics.bottom);

    paint.setColor(255, 100, 0, 255);
    canvas.drawLine(paint, x - 10, y + fontMetrics.descent, x - 10, y + fontMetrics.descent - fontSize);
    canvas.drawLine(paint, x - 15, y, x - 15, y - fontMetrics.xheight);

    paint.setColor(0, 255, 255, 128);
    paint.setStroke();
    canvas.drawRect(paint, x + lineBounds.x, y + lineBounds.y, x + lineBounds.x + lineBounds.w, y + lineBounds.y + lineBounds.h);
    canvas.drawText(paint, "BOUNDS", lineBounds.x, lineBounds.y);

    paint.setColor(100, 100, 100, 255);
    canvas.drawLine(paint, x, y + lineHeight, x + lineBounds.w, y + lineHeight);
    canvas.drawText(paint, "BASELINE", x + 10, y + 20 + lineHeight);
  },
  getTextBounds: function(paint, str, x, y) {
    x = x || 0;
    y = y || 0;
    //bounds [left, top, right, bottom]
    var bounds = paint.measureTextBounds(str);
    return {
        x1 : x + bounds[0],
        y1 : y + bounds[3],
        x2 : x + bounds[2],
        y2 : y + bounds[1],
        x : x + bounds[0],
        y : y + bounds[1],
        w : bounds[2] - bounds[0],
        h : bounds[3] - bounds[1]
    };
  },
  draw: function() {
    return;
    var canvas = this.canvas;
    var paint = this.paint;
    canvas.clear(255, 255, 255, 255);
    paint.setFill();
    paint.setColor(0, 0, 0, 255);
    paint.setFlags(paint.kAntiAliasFlag);
    var fontFamily = this.fontFamilies[this.framenum % this.fontFamilies.length];
    fontFamily = this.fontFamilies[0];

    var str = "abcdefghijklmnopqrstuvwxyz";
    var str2 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    var h = 100;
    var w = paint.measureText(str);
    var x = (this.width - w)/2;
    var y = (this.height - h)/2;
    var fontMetrics = paint.getFontMetrics();

    console.log(fontMetrics);

    var bounds = this.getTextBounds(paint, str, x, y);
    canvas.drawText(paint, str, x, y);

    var bounds2 = this.getTextBounds(paint, str, x, y);

    var lineHeight = fontMetrics.descent - fontMetrics.ascent + fontMetrics.leading;

    canvas.drawText(paint, str2, x, y + lineHeight);
    canvas.drawText(paint, str2, x, y + lineHeight * 2);

    console.log(bounds);

    paint.setStroke();
    paint.setColor(255, 0, 0, 255);
    canvas.drawRect(paint, bounds.x1, bounds.y1, bounds.x2, bounds.y2);

    paint.setColor(0, 255, 0, 255);
    canvas.drawRect(paint, bounds.x, bounds.y, bounds.x + bounds.w, bounds.y + bounds.h);

    paint.setColor(255, 0, 0, 128);
    canvas.drawLine(paint, x, y, x + bounds.w, y);

    canvas.drawLine(paint, x, y + lineHeight, x + bounds.w, y + lineHeight);

    canvas.drawLine(paint, x, y + lineHeight * 2, x + bounds.w, y + lineHeight * 2);
  }
});
