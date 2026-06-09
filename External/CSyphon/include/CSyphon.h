//
//  CSyphon.h
//  Curated umbrella header for the vendored Syphon Metal subset.
//
//  Not upstream Syphon source — added by Ollin so Swift `import CSyphon`
//  exposes only the Metal server/client and the server directory. The rest of
//  the vendored files (messaging, connection managers, base classes) are
//  implementation details reached through these, not part of the module's
//  public surface. See External/CSyphon/README.md for provenance.
//

#import "SyphonMetalServer.h"
#import "SyphonMetalClient.h"
#import "SyphonServerDirectory.h"
