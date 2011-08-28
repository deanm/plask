var plask = require('plask');

var ascript = new plask.AppleScript(
    'tell application "iTunes"\n' +
    '  playpause\n' +
    'end tell');

ascript.execute();

// One day I'll fix the event loop and then programs will end automatically.
process.exit(0);  // Exit the program.
