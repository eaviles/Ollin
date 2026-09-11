/*
    OllinSyphonPrefix.h

    Written for Ollin. Not part of the Syphon Framework, and not upstream.

    Syphon builds with a prefix header, which Xcode forces into every
    translation unit with `-include`. SwiftPM can pass that only as an unsafe
    build flag, and a target carrying one cannot be reached through a package
    that somebody depends on by version: `import OllinSyphon` then fails to
    resolve before it compiles. So each implementation file imports this
    instead, and it does the two things the prefix did for an Objective-C file:
    bring in Cocoa, and define the logging macro.

    The logging is empty here, which is what the prefix itself produces in any
    build without DEBUG, so the sources below see exactly what they expect.
*/

#import <Cocoa/Cocoa.h>

#ifndef SYPHONLOG
#define SYPHONLOG(format, ...)
#endif
