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

#include "plask_bindings.h"

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>

#include "v8_utils.h"

#include "FreeImage.h"

#include <string>
#include <map>

#include <CoreFoundation/CoreFoundation.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreMIDI/CoreMIDI.h>
#include <ScriptingBridge/SBApplication.h>
#include <Foundation/NSObjCRuntime.h>
#include <AVFoundation/AVPlayer.h>
#include <AVFoundation/AVPlayerItem.h>
#include <AVFoundation/AVPlayerItemOutput.h>
#include <CoreMedia/CoreMedia.h>
#include <objc/runtime.h>

#define SK_SUPPORT_LEGACY_GETDEVICE 1
#define SK_RELEASE 1  // Hmmmm, really? SkPreConfig is thinking we are debug.
#include "SkBitmap.h"
#include "SkCanvas.h"
#include "SkColorPriv.h"  // For color ordering.
#include "SkDevice.h"
#include "SkString.h"
#include "SkTypeface.h"
#include "SkUnPreMultiply.h"
#include "SkXfermode.h"
#include "skia/include/utils/SkParsePath.h"
#include "skia/include/effects/SkGradientShader.h"
#include "skia/include/effects/SkDashPathEffect.h"
#include "skia/include/pdf/SkPDFDevice.h"
#include "skia/include/pdf/SkPDFDocument.h"
#include "skia/include/ports/SkTypeface_mac.h"  // SkCreateTypefaceFromCTFont.

#import <Syphon/Syphon.h>

template <typename T, size_t N>
char (&ArraySizeHelper(T (&array)[N]))[N];

// That gcc wants both of these prototypes seems mysterious. VC, for
// its part, can't decide which to use (another mystery). Matching of
// template overloads: the final frontier.
#ifndef _MSC_VER
template <typename T, size_t N>
char (&ArraySizeHelper(const T (&array)[N]))[N];
#endif

#define arraysize(array) (sizeof(ArraySizeHelper(array)))

template <typename T>
T Clamp(T v, T a, T b) {
  if (v < a) return a;
  if (v > b) return b;
  return v;
}

@interface TextureAVPlayer: AVQueuePlayer
{
  CVOpenGLTextureCacheRef cache_;
  AVPlayerItemVideoOutput* output_;
  NSMutableArray* playerItems_;
  BOOL loops_;
}

@end

@implementation TextureAVPlayer
-(TextureAVPlayer*) init {
  self = [super init];
  if (self) {
    cache_ = NULL;
    output_ = nil;
    loops_ = NO;
    playerItems_ = [[NSMutableArray alloc] init];

    self.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidReachEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:nil];
  }
  return self;
}

-(void) dealloc {
  CVOpenGLTextureCacheRelease(cache_);  // NULL safe.
  [output_ release];  // nil safe.
  [playerItems_ release];
  [super dealloc];  // Last thing, deallocs our underlying memory.
}

-(TextureAVPlayer*) initWithNSOpenGLContext:(NSOpenGLContext*)context {
  self = [self init];  // Objective-c constructor patterns, have no idea...
  if (self) {
    NSDictionary* attrs = @{ (NSString*)kCVPixelBufferPixelFormatTypeKey:
                             @( kCVPixelFormatType_32BGRA ) };
                             //@( kCVPixelFormatType_24BGR ) };  // Doesn't work
                             //@( kCVPixelFormatType_24RGB ) };  // Expensive CPU in glgConvertTo_32 RGB8 ARGB8

    CGLContextObj cglcontext = (CGLContextObj)[context CGLContextObj];
    CVReturn res = CVOpenGLTextureCacheCreate(
        NULL, NULL, cglcontext, CGLGetPixelFormat(cglcontext), NULL, &cache_);
    if (res)
      return nil;  // TODO best way to propagate errors?

    output_ = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attrs];
  }

  return self;
}

// Caller owns the CVOpenGLTextureRef object.
// The texture itself is owned by the cache and recycled next time around.
-(CVOpenGLTextureRef) textureForItemTime:(CMTime)itemTime {
  if (!output_)
    return NULL;

  CVImageBufferRef buffer =
      [output_ copyPixelBufferForItemTime:itemTime
                       itemTimeForDisplay:nil];
  if (buffer == nil)
    return NULL;

  CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
  // Apparently on IOS the cache is flushed implicitly (at least according
  // to the documentation), but it seems on Mac you must do it explicitly.
  CVOpenGLTextureCacheFlush(cache_, 0);

  CVOpenGLTextureRef texture;
  CVReturn res = CVOpenGLTextureCacheCreateTextureFromImage(
      NULL, cache_, buffer, NULL, &texture);
  CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
  CVPixelBufferRelease(buffer);

  if (res)
    return NULL;

  return texture;
}


-(void) setLoops:(BOOL)loops {
  loops_ = loops;
}

-(void) appendURL:(NSURL*)url {
  AVPlayerItem* item = [[AVPlayerItem alloc] initWithURL:url];
  [playerItems_ addObject:item];
  if (output_) [item addOutput:output_];
  [self insertItem:item afterItem:nil];
  [item release];
}

-(void) playAtIndex:(NSInteger)index {
  [self removeAllItems];
  for (int i = index; i <playerItems_.count; i ++) {
    AVPlayerItem* item = [playerItems_ objectAtIndex:i];
    if ([self canInsertItem:item afterItem:nil]) {
      [item seekToTime:kCMTimeZero];
      if (output_) [item addOutput:output_];
      [self insertItem:item afterItem:nil];
    }
  }
}

-(void) playerItemDidReachEnd:(NSNotification *)notification {
  AVPlayerItem* p = [notification object];
  AVPlayerItem* last = [self.items lastObject];
  if (!loops_ || ![p isEqual:last]) {
    [self advanceToNextItem];
    return;
  }

  // Looping...
  [self removeAllItems];
  for (int i = 0; i < playerItems_.count; i++) {
    [self playAtIndex:0];
  }
  [self play];
}

@end

@interface WrappedNSWindow: NSWindow {
  v8::Persistent<v8::Function> event_callback_;
}

-(void)setEventCallbackWithHandle:(v8::Handle<v8::Function>)func;

@end

@interface WindowDelegate : NSObject <NSWindowDelegate> {
}

@end

namespace {

// hack...
v8::Isolate* isolate;

void SetInternalIsolate(v8::Isolate* iso) { isolate = iso; }

template <class TypeName>
inline v8::Local<TypeName> StrongPersistentToLocal(
    const v8::PersistentBase<TypeName>& persistent) {
  return *reinterpret_cast<v8::Local<TypeName>*>(
      const_cast<v8::PersistentBase<TypeName>*>(&persistent));
}

template <class TypeName>
inline v8::Local<TypeName> WeakPersistentToLocal(
    v8::Isolate* isolate,
    const v8::PersistentBase<TypeName>& persistent) {
  return v8::Local<TypeName>::New(isolate, persistent);
}

template <class TypeName>
inline v8::Local<TypeName> PersistentToLocal(
    v8::Isolate* isolate,
    const v8::PersistentBase<TypeName>& persistent) {
  if (persistent.IsWeak()) {
    return WeakPersistentToLocal(isolate, persistent);
  } else {
    return StrongPersistentToLocal(persistent);
  }
}


int SizeOfArrayElementForType(v8::ExternalArrayType type) {
  switch (type) {
    case v8::kExternalInt8Array:
    case v8::kExternalUint8Array:
    case v8::kExternalUint8ClampedArray:
      return 1;
    case v8::kExternalInt16Array:
    case v8::kExternalUint16Array:
      return 2;
    case v8::kExternalInt32Array:
    case v8::kExternalUint32Array:
    case v8::kExternalFloat32Array:
      return 4;
    case v8::kExternalFloat64Array:
      return 8;
    default:
      abort();
      return 0;
  }
}

// FIXME ugly, but currently not a better way to access the backing store
// than just to wrap the ArrayBuffer in a new ArrayBufferView.
// Seems there is a difference between:
//   - new Float32Array(2);
//   - new Float32Array([0, 1]);
// The first doesn't have HasIndexedPropertiesInExternalArrayData
bool GetTypedArrayBytes(
    v8::Local<v8::Value> value, void** data, intptr_t* size) {

  v8::Local<v8::ArrayBuffer> buffer;

  if (value->IsArrayBuffer()) {
    buffer = v8::Handle<v8::ArrayBuffer>::Cast(value);
  } else if (value->IsArrayBufferView()) {
    buffer = v8::Local<v8::ArrayBufferView>::Cast(value)->Buffer();
  } else {
    return false;
  }

  // Always create a new wrapper, see above.
  v8::Local<v8::ArrayBufferView> view =
      v8::Uint8Array::New(buffer, 0, buffer->ByteLength());

  if (!view->HasIndexedPropertiesInExternalArrayData())
    abort();

  //printf("indexed %d\n", view->HasIndexedPropertiesInExternalArrayData());
  //printf("pixel %d\n", view->HasIndexedPropertiesInPixelData());

  *data = view->GetIndexedPropertiesExternalArrayData();
  *size = view->GetIndexedPropertiesExternalArrayDataLength() *
          SizeOfArrayElementForType(view->GetIndexedPropertiesExternalArrayDataType());
  return true;
}


const char kMsgNonConstructCall[] =
    "Constructor cannot be called as a function.";

#if 0
// A CGDataProvider that just provides from a pointer.
const void* PointerProviderGetBytePointer(void* info) {
  return info;
}

void PointerProviderReleaseData(void* info, const void* data, size_t size) {
}

size_t PointerProviderGetBytesAtPosition(char* info, void* buffer,
                                         off_t position, size_t count) {
  memcpy(buffer, info + position, count);
  return count;
}

void PointerProviderReleaseInfo(void* info) {
}

CGDataProviderDirectCallbacks PointerProviderCallbacks = {
  0, &PointerProviderGetBytePointer, &PointerProviderReleaseData,
     &PointerProviderGetBytesAtPosition, &PointerProviderReleaseInfo };
#endif

#define DEFINE_METHOD(name, arity) \
  static void name(const v8::FunctionCallbackInfo<v8::Value>& args) { \
    if (args.Length() != arity) \
      return v8_utils::ThrowError(isolate, "Wrong number of arguments.");

#define METHOD_ENTRY(name) { #name, &name }

struct BatchedConstants {
  const char* name;
  uint32_t val;
};

struct BatchedMethods {
  const char* name;
  v8::FunctionCallback func;
};


class WebGLActiveInfo {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &WebGLActiveInfo::V8New);

    ft->SetClassName(v8::String::NewFromUtf8(isolate, "WebGLActiveInfo"));
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(0);

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

  static v8::Handle<v8::Value> NewFromSizeTypeName(GLint size,
                                                   GLenum type,
                                                   const char* name) {
    v8::Local<v8::FunctionTemplate> ft = v8::Local<v8::FunctionTemplate>::New(
        isolate, WebGLActiveInfo::GetTemplate(isolate));
    v8::Local<v8::Object> obj = ft->InstanceTemplate()->NewInstance();
    obj->Set(v8::String::NewFromUtf8(isolate, "size"), v8::Integer::New(isolate, size), v8::ReadOnly);
    obj->Set(v8::String::NewFromUtf8(isolate, "type"),
             v8::Integer::NewFromUnsigned(isolate, type),
             v8::ReadOnly);
    obj->Set(v8::String::NewFromUtf8(isolate, "name"), v8::String::NewFromUtf8(isolate, name), v8::ReadOnly);
    return obj;
  }

 private:
  static void V8New(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);
  }
};

template <const char* TClassName>
class WebGLNameMappedObject {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &V8New);

    ft->SetClassName(v8::String::NewFromUtf8(isolate, TClassName));
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // GLuint name.

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

  static v8::Handle<v8::Value> NewFromName(
      GLuint name) {
    v8::Local<v8::FunctionTemplate> ft = v8::Local<v8::FunctionTemplate>::New(
        isolate, GetTemplate(isolate));
    v8::Local<v8::Object> obj = ft->InstanceTemplate()->NewInstance();
    obj->SetInternalField(0, v8::Integer::NewFromUnsigned(isolate, name));
    map.emplace(std::make_pair(name, v8::UniquePersistent<v8::Value>(isolate, obj)));
    return obj;
  }

  static v8::Handle<v8::Value> LookupFromName(
      v8::Isolate* isolate, GLuint name) {
    if (name != 0 && map.count(name) == 1)
      return PersistentToLocal(isolate, map[name]);
    return v8::Null(isolate);
  }

  // Use to set the name to 0, when it is deleted, for example.
  static void ClearName(v8::Handle<v8::Value> value) {
    GLuint name = ExtractNameFromValue(value);
    if (name != 0) {
      if (map.count(name) == 1) {
        map[name].Reset();
        if (map.erase(name) != 1) {
          printf("Warning: Should have erased name map entry.\n");
        }
      } else {
        printf("Warning: Should have disposed name map handle.\n");
      }
    }
    return v8::Handle<v8::Object>::Cast(value)->
        SetInternalField(0, v8::Integer::NewFromUnsigned(isolate, 0));
  }

  static GLuint ExtractNameFromValue(
      v8::Handle<v8::Value> value) {
    if (value->IsNull()) return 0;
    return v8::Handle<v8::Object>::Cast(value)->
        GetInternalField(0)->Uint32Value();
  }

  // If we call getParameter(FRAMEBUFFER_BINDING) twice, for example, we need
  // to get the same wrapper object (not a newly created one) as the one we
  // got from the call to frameFramebuffer().  (This is the WebGL spec).  So,
  // we must track a mapping between OpenGL GLuint "framebuffer object name"
  // and the wrapper objects.
  typedef std::map<GLuint, v8::UniquePersistent<v8::Value> > MapType;

  static void ClearMap() { map.clear(); }
  static MapType& Map() { return map; }

 private:
  static MapType map;

  static void V8New(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    // TODO(deanm): How to throw an exception when called from JavaScript?
    // For now we don't expose the object directly, so maybe it's okay
    // (although I suppose you can still get to it from an instance)...
    //return v8_utils::ThrowTypeError(isolate, "Type error.");

    // Initially set to 0.
    args.This()->SetInternalField(0, v8::Integer::NewFromUnsigned(isolate, 0));
  }
};


#define DEFINE_NAME_MAPPED_CLASS(name) \
  extern const char name##ClassNameString[] = #name; \
  typedef WebGLNameMappedObject<name##ClassNameString> name; \
  template <> \
  name::MapType name::map = name::MapType();

DEFINE_NAME_MAPPED_CLASS(WebGLBuffer)
DEFINE_NAME_MAPPED_CLASS(WebGLFramebuffer)
DEFINE_NAME_MAPPED_CLASS(WebGLProgram)
DEFINE_NAME_MAPPED_CLASS(WebGLRenderbuffer)
DEFINE_NAME_MAPPED_CLASS(WebGLShader)
DEFINE_NAME_MAPPED_CLASS(WebGLTexture)
DEFINE_NAME_MAPPED_CLASS(WebGLVertexArrayObject)

class NSOpenGLContextWrapper;

class WebGLUniformLocation {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &WebGLUniformLocation::V8New);

    ft->SetClassName(v8::String::NewFromUtf8(isolate, "WebGLUniformLocation"));
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // GLint location.

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

  static v8::Handle<v8::Value> NewFromLocation(GLint location) {
    v8::Local<v8::FunctionTemplate> ft = v8::Local<v8::FunctionTemplate>::New(
        isolate, WebGLUniformLocation::GetTemplate(isolate));
    v8::Local<v8::Object> obj = ft->InstanceTemplate()->NewInstance();
    obj->SetInternalField(0, v8::Integer::New(isolate, location));
    return obj;
  }

  static GLint ExtractLocationFromValue(v8::Handle<v8::Value> value) {
    return v8::Handle<v8::Object>::Cast(value)->
        GetInternalField(0)->Int32Value();
  }

 private:
  static void V8New(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    // TODO(deanm): How to throw an exception when called from JavaScript but
    // not from NewFromLocation?
    //return v8_utils::ThrowTypeError(isolate, "Type error.");
  }
};


// TODO
// 5.12 WebGLShaderPrecisionFormat


class SyphonServerWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &SyphonServerWrapper::V8New);

    ft->SetClassName(v8::String::NewFromUtf8(isolate, "SyphonServer"));
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // SyphonServer

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
      { "kValue", 12 },
    };

    static BatchedMethods methods[] = {
      { "publishFrameTexture", &SyphonServerWrapper::publishFrameTexture },
      { "bindToDrawFrameOfSize", &SyphonServerWrapper::bindToDrawFrameOfSize },
      { "unbindAndPublish", &SyphonServerWrapper::unbindAndPublish },
      { "hasClients", &SyphonServerWrapper::hasClients },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      ft->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
              v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
                    v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, methods[i].name),
                    v8::FunctionTemplate::New(isolate, methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

  static SyphonServer* ExtractSyphonServerPointer(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<SyphonServer*>(obj->GetAlignedPointerFromInternalField(0));
  }

  static v8::Handle<v8::Value> NewFromSyphonServer(SyphonServer* server) {
    v8::Local<v8::FunctionTemplate> ft = v8::Local<v8::FunctionTemplate>::New(
        isolate, SyphonServerWrapper::GetTemplate(isolate));
    v8::Local<v8::Object> obj = ft->InstanceTemplate()->NewInstance();
    obj->SetAlignedPointerInInternalField(0, server);
    return obj;
  }

 private:
  static void V8New(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);
  }

  DEFINE_METHOD(publishFrameTexture, 9)
    SyphonServer* server = ExtractSyphonServerPointer(args.Holder());
    [server publishFrameTexture:args[0]->Uint32Value()
            textureTarget:args[1]->Uint32Value()
            imageRegion:NSMakeRect(args[2]->Int32Value(),
                                   args[3]->Int32Value(),
                                   args[4]->Int32Value(),
                                   args[5]->Int32Value())
            textureDimensions:NSMakeSize(args[6]->Int32Value(),
                                         args[7]->Int32Value())
            flipped:args[8]->BooleanValue()];
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(bindToDrawFrameOfSize, 2)    SyphonServer* server = ExtractSyphonServerPointer(args.Holder());
    BOOL res = [server bindToDrawFrameOfSize:NSMakeSize(args[0]->Int32Value(),
                                                        args[1]->Int32Value())];
    return args.GetReturnValue().Set((bool)res);
  }

  static void unbindAndPublish(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SyphonServer* server = ExtractSyphonServerPointer(args.Holder());
    [server unbindAndPublish];
    return args.GetReturnValue().SetUndefined();
  }

  static void hasClients(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SyphonServer* server = ExtractSyphonServerPointer(args.Holder());
    return args.GetReturnValue().Set((bool)[server hasClients]);
  }
};

class SyphonClientWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &SyphonClientWrapper::V8New);

    ft->SetClassName(v8::String::NewFromUtf8(isolate, "SyphonClient"));
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(2);  // SyphonClient, CGLContextObj

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
      { "kValue", 12 },
    };

    static BatchedMethods methods[] = {
      { "newFrameImage", &SyphonClientWrapper::newFrameImage },
      { "isValid", &SyphonClientWrapper::isValid },
      { "hasNewFrame", &SyphonClientWrapper::hasNewFrame },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      ft->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
              v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
                    v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, methods[i].name),
                    v8::FunctionTemplate::New(isolate, methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

  static SyphonClient* ExtractSyphonClientPointer(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<SyphonClient*>(obj->GetAlignedPointerFromInternalField(0));
  }

  static CGLContextObj ExtractContextObj(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<CGLContextObj>(obj->GetAlignedPointerFromInternalField(1));
  }

  static v8::Handle<v8::Value> NewFromSyphonClient(SyphonClient* client,
                                                   CGLContextObj context) {
    v8::Local<v8::FunctionTemplate> ft = v8::Local<v8::FunctionTemplate>::New(
        isolate, SyphonClientWrapper::GetTemplate(isolate));
    v8::Local<v8::Object> obj = ft->InstanceTemplate()->NewInstance();
    obj->SetAlignedPointerInInternalField(0, client);
    obj->SetAlignedPointerInInternalField(1, context);
    return obj;
  }

 private:
  static void V8New(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);
  }

  DEFINE_METHOD(newFrameImage, 0)
    SyphonClient* client = ExtractSyphonClientPointer(args.Holder());
    CGLContextObj context = ExtractContextObj(args.Holder());
    SyphonImage* image = [client newFrameImageForContext:context];

    if (!image) return args.GetReturnValue().SetNull();

    v8::Local<v8::Object> res = v8::Object::New(isolate);
    res->Set(v8::String::NewFromUtf8(isolate, "name"),
             v8::Integer::NewFromUnsigned(isolate, [image textureName]));
    res->Set(v8::String::NewFromUtf8(isolate, "width"),
             v8::Number::New(isolate, [image textureSize].width));
    res->Set(v8::String::NewFromUtf8(isolate, "height"),
             v8::Number::New(isolate, [image textureSize].height));

    // The SyphonImage is just a container of the data.  The lifetime of it has
    // no relationship with the lifetime of the texture.
    [image release];

    return args.GetReturnValue().Set(res);
  }

  static void isValid(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SyphonClient* client = ExtractSyphonClientPointer(args.Holder());
    return args.GetReturnValue().Set((bool)[client isValid]);
  }

  static void hasNewFrame(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SyphonClient* client = ExtractSyphonClientPointer(args.Holder());
    return args.GetReturnValue().Set((bool)[client hasNewFrame]);
  }
};

// We can't do a nested define so just declare the constants as a static var.
#define WEBGL_CONSTANTS_EACH(name, val) \
  static const GLenum WEBGL_##name = val;
#include "webgl_constants.h"
#undef WEBGL_CONSTANTS_EACH

class NSOpenGLContextWrapper {
 public:
  enum WebGLType {
    WebGLTypeInvalid = 0,
    WebGLTypeDOMString,
    WebGLTypeFloat32Arrayx2,
    WebGLTypeFloat32Arrayx4,
    WebGLTypeGLboolean,
    WebGLTypeGLbooleanx4,
    WebGLTypeGLenum,
    WebGLTypeGLfloat,
    WebGLTypeGLint,
    WebGLTypeGLuint,
    WebGLTypeInt32Arrayx2,
    WebGLTypeInt32Arrayx4,
    WebGLTypeUint32Array,
    WebGLTypeWebGLBuffer,
    WebGLTypeWebGLFramebuffer,
    WebGLTypeWebGLProgram,
    WebGLTypeWebGLRenderbuffer,
    WebGLTypeWebGLTexture,
    WebGLTypeWebGLVertexArrayObject,
  };

  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &NSOpenGLContextWrapper::V8New);
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(1);

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
#define WEBGL_CONSTANTS_EACH(name, val) \
      { #name, val },
#include "webgl_constants.h"
#undef WEBGL_CONSTANTS_EACH
    };

    static BatchedMethods methods[] = {
      { "makeCurrentContext", &NSOpenGLContextWrapper::makeCurrentContext },
      { "setSwapInterval", &NSOpenGLContextWrapper::setSwapInterval },
      { "writeImage", &NSOpenGLContextWrapper::writeImage },

      { "activeTexture", &NSOpenGLContextWrapper::activeTexture },
      { "attachShader", &NSOpenGLContextWrapper::attachShader },
      { "bindAttribLocation", &NSOpenGLContextWrapper::bindAttribLocation },
      { "bindBuffer", &NSOpenGLContextWrapper::bindBuffer },
      { "bindFramebuffer", &NSOpenGLContextWrapper::bindFramebuffer },
      { "bindRenderbuffer", &NSOpenGLContextWrapper::bindRenderbuffer },
      { "bindTexture", &NSOpenGLContextWrapper::bindTexture },
      { "bindVertexArray", &NSOpenGLContextWrapper::bindVertexArray },
      { "blendColor", &NSOpenGLContextWrapper::blendColor },
      { "blendEquation", &NSOpenGLContextWrapper::blendEquation },
      { "blendEquationSeparate",
          &NSOpenGLContextWrapper::blendEquationSeparate },
      { "blendFunc", &NSOpenGLContextWrapper::blendFunc },
      { "blendFuncSeparate", &NSOpenGLContextWrapper::blendFuncSeparate },
      { "bufferData", &NSOpenGLContextWrapper::bufferData },
      { "bufferSubData", &NSOpenGLContextWrapper::bufferSubData },
      { "checkFramebufferStatus",
          &NSOpenGLContextWrapper::checkFramebufferStatus },
      { "clear", &NSOpenGLContextWrapper::clear },
      { "clearColor", &NSOpenGLContextWrapper::clearColor },
      { "clearDepth", &NSOpenGLContextWrapper::clearDepth },
      { "clearStencil", &NSOpenGLContextWrapper::clearStencil },
      { "colorMask", &NSOpenGLContextWrapper::colorMask },
      { "compileShader", &NSOpenGLContextWrapper::compileShader },
      // { "copyTexImage2D", &NSOpenGLContextWrapper::copyTexImage2D },
      // { "copyTexSubImage2D", &NSOpenGLContextWrapper::copyTexSubImage2D },
      { "createBuffer", &NSOpenGLContextWrapper::createBuffer },
      { "createFramebuffer", &NSOpenGLContextWrapper::createFramebuffer },
      { "createProgram", &NSOpenGLContextWrapper::createProgram },
      { "createRenderbuffer", &NSOpenGLContextWrapper::createRenderbuffer },
      { "createShader", &NSOpenGLContextWrapper::createShader },
      { "createTexture", &NSOpenGLContextWrapper::createTexture },
      { "createVertexArray", &NSOpenGLContextWrapper::createVertexArray },
      { "cullFace", &NSOpenGLContextWrapper::cullFace },
      { "deleteBuffer", &NSOpenGLContextWrapper::deleteBuffer },
      { "deleteFramebuffer", &NSOpenGLContextWrapper::deleteFramebuffer },
      { "deleteProgram", &NSOpenGLContextWrapper::deleteProgram },
      { "deleteRenderbuffer", &NSOpenGLContextWrapper::deleteRenderbuffer },
      { "deleteShader", &NSOpenGLContextWrapper::deleteShader },
      { "deleteTexture", &NSOpenGLContextWrapper::deleteTexture },
      { "deleteVertexArray", &NSOpenGLContextWrapper::deleteVertexArray },
      { "depthFunc", &NSOpenGLContextWrapper::depthFunc },
      { "depthMask", &NSOpenGLContextWrapper::depthMask },
      { "depthRange", &NSOpenGLContextWrapper::depthRange },
      { "detachShader", &NSOpenGLContextWrapper::detachShader },
      { "disable", &NSOpenGLContextWrapper::disable },
      { "disableVertexAttribArray",
          &NSOpenGLContextWrapper::disableVertexAttribArray },
      { "drawArrays", &NSOpenGLContextWrapper::drawArrays },
      { "drawElements", &NSOpenGLContextWrapper::drawElements },
      { "vertexAttribDivisor", &NSOpenGLContextWrapper::vertexAttribDivisor },
      { "drawArraysInstanced", &NSOpenGLContextWrapper::drawArraysInstanced },
      { "drawElementsInstanced", &NSOpenGLContextWrapper::drawElementsInstanced },
      { "drawRangeElements", &NSOpenGLContextWrapper::drawRangeElements },
      { "enable", &NSOpenGLContextWrapper::enable },
      { "enableVertexAttribArray",
          &NSOpenGLContextWrapper::enableVertexAttribArray },
      { "finish", &NSOpenGLContextWrapper::finish },
      { "flush", &NSOpenGLContextWrapper::flush },
      { "framebufferRenderbuffer",
          &NSOpenGLContextWrapper::framebufferRenderbuffer },
      { "framebufferTexture2D", &NSOpenGLContextWrapper::framebufferTexture2D },
      { "frontFace", &NSOpenGLContextWrapper::frontFace },
      { "generateMipmap", &NSOpenGLContextWrapper::generateMipmap },
      { "getActiveAttrib", &NSOpenGLContextWrapper::getActiveAttrib },
      { "getActiveUniform", &NSOpenGLContextWrapper::getActiveUniform },
      { "getAttachedShaders", &NSOpenGLContextWrapper::getAttachedShaders },
      { "getAttribLocation", &NSOpenGLContextWrapper::getAttribLocation },
      { "getParameter", &NSOpenGLContextWrapper::getParameter },
      { "getBufferParameter", &NSOpenGLContextWrapper::getBufferParameter },
      { "getError", &NSOpenGLContextWrapper::getError },
      { "getFramebufferAttachmentParameter",
          &NSOpenGLContextWrapper::getFramebufferAttachmentParameter },
      { "getProgramParameter", &NSOpenGLContextWrapper::getProgramParameter },
      { "getProgramInfoLog", &NSOpenGLContextWrapper::getProgramInfoLog },
      { "getRenderbufferParameter",
          &NSOpenGLContextWrapper::getRenderbufferParameter },
      { "getShaderParameter", &NSOpenGLContextWrapper::getShaderParameter },
      { "getShaderInfoLog", &NSOpenGLContextWrapper::getShaderInfoLog },
      { "getShaderSource", &NSOpenGLContextWrapper::getShaderSource },
      { "getTexParameter", &NSOpenGLContextWrapper::getTexParameter },
      { "getUniform", &NSOpenGLContextWrapper::getUniform },
      { "getUniformLocation", &NSOpenGLContextWrapper::getUniformLocation },
      { "getVertexAttrib", &NSOpenGLContextWrapper::getVertexAttrib },
      { "getVertexAttribOffset",
          &NSOpenGLContextWrapper::getVertexAttribOffset },
      { "hint", &NSOpenGLContextWrapper::hint },
      { "isBuffer", &NSOpenGLContextWrapper::isBuffer },
      { "isEnabled", &NSOpenGLContextWrapper::isEnabled },
      { "isFramebuffer", &NSOpenGLContextWrapper::isFramebuffer },
      { "isProgram", &NSOpenGLContextWrapper::isProgram },
      { "isRenderbuffer", &NSOpenGLContextWrapper::isRenderbuffer },
      { "isShader", &NSOpenGLContextWrapper::isShader },
      { "isTexture", &NSOpenGLContextWrapper::isTexture },
      { "isVertexArray", &NSOpenGLContextWrapper::isVertexArray },
      { "lineWidth", &NSOpenGLContextWrapper::lineWidth },
      { "linkProgram", &NSOpenGLContextWrapper::linkProgram },
      { "pixelStorei", &NSOpenGLContextWrapper::pixelStorei },
      { "polygonOffset", &NSOpenGLContextWrapper::polygonOffset },
      { "readPixels", &NSOpenGLContextWrapper::readPixels },
      { "renderbufferStorage", &NSOpenGLContextWrapper::renderbufferStorage },
      { "renderbufferStorageMultisample", &NSOpenGLContextWrapper::renderbufferStorageMultisample },
      { "sampleCoverage", &NSOpenGLContextWrapper::sampleCoverage },
      { "scissor", &NSOpenGLContextWrapper::scissor },
      { "shaderSource", &NSOpenGLContextWrapper::shaderSource },
      { "stencilFunc", &NSOpenGLContextWrapper::stencilFunc },
      { "stencilFuncSeparate", &NSOpenGLContextWrapper::stencilFuncSeparate },
      { "stencilMask", &NSOpenGLContextWrapper::stencilMask },
      { "stencilMaskSeparate", &NSOpenGLContextWrapper::stencilMaskSeparate },
      { "stencilOp", &NSOpenGLContextWrapper::stencilOp },
      { "stencilOpSeparate", &NSOpenGLContextWrapper::stencilOpSeparate },
      { "texImage2D", &NSOpenGLContextWrapper::texImage2D },
      { "texImage2DSkCanvasB", &NSOpenGLContextWrapper::texImage2DSkCanvasB },
      { "texParameterf", &NSOpenGLContextWrapper::texParameterf },
      { "texParameteri", &NSOpenGLContextWrapper::texParameteri },
      { "texSubImage2D", &NSOpenGLContextWrapper::texSubImage2D },
      { "uniform1f", &NSOpenGLContextWrapper::uniform1f },
      { "uniform1fv", &NSOpenGLContextWrapper::uniform1fv },
      { "uniform1i", &NSOpenGLContextWrapper::uniform1i },
      { "uniform1iv", &NSOpenGLContextWrapper::uniform1iv },
      { "uniform2f", &NSOpenGLContextWrapper::uniform2f },
      { "uniform2fv", &NSOpenGLContextWrapper::uniform2fv },
      { "uniform2i", &NSOpenGLContextWrapper::uniform2i },
      { "uniform2iv", &NSOpenGLContextWrapper::uniform2iv },
      { "uniform3f", &NSOpenGLContextWrapper::uniform3f },
      { "uniform3fv", &NSOpenGLContextWrapper::uniform3fv },
      { "uniform3i", &NSOpenGLContextWrapper::uniform3i },
      { "uniform3iv", &NSOpenGLContextWrapper::uniform3iv },
      { "uniform4f", &NSOpenGLContextWrapper::uniform4f },
      { "uniform4fv", &NSOpenGLContextWrapper::uniform4fv },
      { "uniform4i", &NSOpenGLContextWrapper::uniform4i },
      { "uniform4iv", &NSOpenGLContextWrapper::uniform4iv },
      { "uniformMatrix2fv", &NSOpenGLContextWrapper::uniformMatrix2fv },
      { "uniformMatrix3fv", &NSOpenGLContextWrapper::uniformMatrix3fv },
      { "uniformMatrix4fv", &NSOpenGLContextWrapper::uniformMatrix4fv },
      { "useProgram", &NSOpenGLContextWrapper::useProgram },
      { "validateProgram", &NSOpenGLContextWrapper::validateProgram },
      { "vertexAttrib1f", &NSOpenGLContextWrapper::vertexAttrib1f },
      //{ "vertexAttrib1fv", &NSOpenGLContextWrapper::vertexAttrib1fv },
      { "vertexAttrib2f", &NSOpenGLContextWrapper::vertexAttrib2f },
      //{ "vertexAttrib2fv", &NSOpenGLContextWrapper::vertexAttrib2fv },
      { "vertexAttrib3f", &NSOpenGLContextWrapper::vertexAttrib3f },
      //{ "vertexAttrib3fv", &NSOpenGLContextWrapper::vertexAttrib3fv },
      { "vertexAttrib4f", &NSOpenGLContextWrapper::vertexAttrib4f },
      //{ "vertexAttrib4fv", &NSOpenGLContextWrapper::vertexAttrib4fv },
      { "vertexAttribPointer", &NSOpenGLContextWrapper::vertexAttribPointer },
      { "viewport", &NSOpenGLContextWrapper::viewport },
      // Plask-specific, not in WebGL.  From ARB_draw_buffers.
      { "drawBuffers", &NSOpenGLContextWrapper::drawBuffers },
      { "blitFramebuffer", &NSOpenGLContextWrapper::blitFramebuffer },
      { "drawSkCanvas", &NSOpenGLContextWrapper::drawSkCanvas },
      // Syphon.
      { "createSyphonServer", &NSOpenGLContextWrapper::createSyphonServer },
      { "createSyphonClient", &NSOpenGLContextWrapper::createSyphonClient },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      ft->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
              v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
                    v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, methods[i].name),
                    v8::FunctionTemplate::New(isolate, methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

  static NSOpenGLContext* ExtractContextPointer(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<NSOpenGLContext*>(obj->GetAlignedPointerFromInternalField(0));
  }

 private:
  static void V8New(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    args.This()->SetAlignedPointerInInternalField(0, NULL);
  }

  static void makeCurrentContext(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSOpenGLContext* context = ExtractContextPointer(args.Holder());
    [context makeCurrentContext];
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(createSyphonServer, 1)
    NSOpenGLContext* context = ExtractContextPointer(args.Holder());
    v8::String::Utf8Value name(args[0]);
    SyphonServer* server = [[SyphonServer alloc]
        initWithName:[NSString stringWithUTF8String:*name]
        context:reinterpret_cast<CGLContextObj>([context CGLContextObj])
        options:nil];
    return args.GetReturnValue().Set(SyphonServerWrapper::NewFromSyphonServer(server));
  }

  DEFINE_METHOD(createSyphonClient, 1)
    NSOpenGLContext* context = ExtractContextPointer(args.This());
    //v8::String::Utf8Value uuid(args[0]);
    v8::String::Utf8Value name(args[0]);

    NSArray* servers = [[SyphonServerDirectory sharedDirectory] servers];
    NSLog(@"Servers: %@", servers);

    NSDictionary* found_server = NULL;
    for (NSUInteger i = 0, il = [servers count]; i < il; ++i) {
      NSDictionary* server = reinterpret_cast<NSDictionary*>(
          [servers objectAtIndex:i]);
      //NSString* suuid = [server objectForKey:SyphonServerDescriptionUUIDKey];
      //NSLog(@"UUID: %@", suuid);
      NSString* sname = [server objectForKey:SyphonServerDescriptionNameKey];
      NSLog(@"Name: %@", sname);
      if (strcmp([sname UTF8String], *name) == 0) {
        found_server = server;
        break;
      }
    }

    if (!found_server)
      return v8_utils::ThrowError(isolate, "No server found matching given name.");

    SyphonClient* client = [[SyphonClient alloc]
        initWithServerDescription:found_server
        options:nil
        newFrameHandler:nil];
    return args.GetReturnValue().Set(SyphonClientWrapper::NewFromSyphonClient(
        client, reinterpret_cast<CGLContextObj>([context CGLContextObj])));
  }

  // aka vsync.
  static void setSwapInterval(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSOpenGLContext* context = ExtractContextPointer(args.Holder());
    GLint interval = args[0]->Int32Value();
    [context setValues:&interval forParameter:NSOpenGLCPSwapInterval];
    return args.GetReturnValue().SetUndefined();
  }

  // TODO(deanm): Share more code with SkCanvas#writeImage.
  static void writeImage(const v8::FunctionCallbackInfo<v8::Value>& args) {
    const uint32_t rmask = SK_R32_MASK << SK_R32_SHIFT;
    const uint32_t gmask = SK_G32_MASK << SK_G32_SHIFT;
    const uint32_t bmask = SK_B32_MASK << SK_B32_SHIFT;

    if (args.Length() < 2)
      return v8_utils::ThrowError(isolate, "Wrong number of arguments.");

    NSOpenGLContext* context = ExtractContextPointer(args.Holder());
    // TODO(deanm): There should be a better way to get the width and height.
    NSRect frame = [[context view] convertRectToBacking:[[context view] frame]];
    int width = frame.size.width;
    int height = frame.size.height;

    int buffer_type = args[3]->Int32Value();

    // Handle width / height in the optional options object.  This allows you
    // to override the width and height, for example if there is a framebuffer
    // object that is a different size than the window.
    // TODO(deanm): Also allow passing the x/y ?
    if (args.Length() >= 3 && args[2]->IsObject()) {
      v8::Handle<v8::Object> opts = v8::Handle<v8::Object>::Cast(args[2]);
      if (opts->Has(v8::String::NewFromUtf8(isolate, "width")))
        width = opts->Get(v8::String::NewFromUtf8(isolate, "width"))->Int32Value();
      if (opts->Has(v8::String::NewFromUtf8(isolate, "height")))
        height = opts->Get(v8::String::NewFromUtf8(isolate, "height"))->Int32Value();
    }

    FREE_IMAGE_FORMAT format;

    v8::String::Utf8Value type(args[0]);
    if (strcmp(*type, "png") == 0) {
      format = FIF_PNG;
    } else if (strcmp(*type, "tiff") == 0) {
      format = FIF_TIFF;
    } else if (strcmp(*type, "targa") == 0) {
      format = FIF_TARGA;
    } else {
      return v8_utils::ThrowError(isolate, "writeImage unsupported output type.");
    }

    v8::String::Utf8Value filename(args[1]);

    FIBITMAP* fb;

    if (buffer_type == 0) {  // RGBA color buffer.
      void* pixels = malloc(width * height * 4);
      glReadPixels(0, 0, width, height, GL_BGRA, GL_UNSIGNED_BYTE, pixels);

      fb = FreeImage_ConvertFromRawBits(
          reinterpret_cast<BYTE*>(pixels),
          width, height, width * 4, 32,
          rmask, gmask, bmask, FALSE);
      free(pixels);
      if (!fb)
        return v8_utils::ThrowError(isolate, "Couldn't allocate FreeImage bitmap.");
    } else {  // Floating point depth buffer
      fb = FreeImage_AllocateT(FIT_FLOAT, width, height);
      if (!fb)
        return v8_utils::ThrowError(isolate, "Couldn't allocate FreeImage bitmap.");
      glReadPixels(0, 0, width, height,
                   GL_DEPTH_COMPONENT, GL_FLOAT, FreeImage_GetBits(fb));
    }

    int save_flags = 0;

    if (args.Length() >= 3 && args[2]->IsObject()) {
      v8::Handle<v8::Object> opts = v8::Handle<v8::Object>::Cast(args[2]);
      if (opts->Has(v8::String::NewFromUtf8(isolate, "dotsPerMeterX"))) {
        FreeImage_SetDotsPerMeterX(fb,
            opts->Get(v8::String::NewFromUtf8(isolate, "dotsPerMeterX"))->Uint32Value());
      }
      if (opts->Has(v8::String::NewFromUtf8(isolate, "dotsPerMeterY"))) {
        FreeImage_SetDotsPerMeterY(fb,
            opts->Get(v8::String::NewFromUtf8(isolate, "dotsPerMeterY"))->Uint32Value());
      }
      if (format == FIF_TIFF && opts->Has(v8::String::NewFromUtf8(isolate, "tiffCompression"))) {
        if (!opts->Get(v8::String::NewFromUtf8(isolate, "tiffCompression"))->BooleanValue())
          save_flags = TIFF_NONE;
      }
    }

    bool saved = FreeImage_Save(format, fb, *filename, save_flags);
    FreeImage_Unload(fb);

    if (!saved)
      return v8_utils::ThrowError(isolate, "Failed to save png.");

    return args.GetReturnValue().SetUndefined();
  }

  // void activeTexture(GLenum texture)
  DEFINE_METHOD(activeTexture, 1)    glActiveTexture(args[0]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void attachShader(WebGLProgram program, WebGLShader shader)
  DEFINE_METHOD(attachShader, 2)
    if (!WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    if (!WebGLShader::HasInstance(isolate, args[1]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint program = WebGLProgram::ExtractNameFromValue(args[0]);
    GLuint shader = WebGLShader::ExtractNameFromValue(args[1]);

    glAttachShader(program, shader);
    return args.GetReturnValue().SetUndefined();
  }

  // void bindAttribLocation(WebGLProgram program, GLuint index, DOMString name)
  DEFINE_METHOD(bindAttribLocation, 3)
    if (!WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint program = WebGLProgram::ExtractNameFromValue(args[0]);

    v8::String::Utf8Value name(args[2]);
    glBindAttribLocation(program, args[1]->Uint32Value(), *name);
    return args.GetReturnValue().SetUndefined();
  }

  // void bindBuffer(GLenum target, WebGLBuffer buffer)
  DEFINE_METHOD(bindBuffer, 2)
    if (!args[1]->IsNull() && !WebGLBuffer::HasInstance(isolate, args[1]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint buffer = WebGLBuffer::ExtractNameFromValue(args[1]);

    glBindBuffer(args[0]->Uint32Value(), buffer);
    return args.GetReturnValue().SetUndefined();
  }

  // void bindFramebuffer(GLenum target, WebGLFramebuffer framebuffer)
  DEFINE_METHOD(bindFramebuffer, 2)
    // NOTE: ExtractNameFromValue handles null.
    if (!args[1]->IsNull() && !WebGLFramebuffer::HasInstance(isolate, args[1]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    glBindFramebuffer(
        args[0]->Uint32Value(),
        WebGLFramebuffer::ExtractNameFromValue(args[1]));
    return args.GetReturnValue().SetUndefined();
  }

  // void bindRenderbuffer(GLenum target, WebGLRenderbuffer renderbuffer)
  DEFINE_METHOD(bindRenderbuffer, 2)
    // NOTE: ExtractNameFromValue handles null.
    if (!args[1]->IsNull() && !WebGLRenderbuffer::HasInstance(isolate, args[1]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    glBindRenderbuffer(
        args[0]->Uint32Value(),
        WebGLRenderbuffer::ExtractNameFromValue(args[1]));
    return args.GetReturnValue().SetUndefined();
  }

  // void bindTexture(GLenum target, WebGLTexture texture)
  DEFINE_METHOD(bindTexture, 2)
    // NOTE: ExtractNameFromValue handles null.
    if (!args[1]->IsNull() && !WebGLTexture::HasInstance(isolate, args[1]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    glBindTexture(args[0]->Uint32Value(),
                  WebGLTexture::ExtractNameFromValue(args[1]));
    return args.GetReturnValue().SetUndefined();
  }

  // void bindVertexArray(WebGLVertexArrayObject? vertexArray)
  DEFINE_METHOD(bindVertexArray, 1)
    // NOTE: ExtractNameFromValue handles null.
    if (!args[0]->IsNull() && !WebGLVertexArrayObject::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    glBindVertexArrayAPPLE(WebGLVertexArrayObject::ExtractNameFromValue(args[0]));
    return args.GetReturnValue().SetUndefined();
  }

  // void blendColor(GLclampf red, GLclampf green,
  //                 GLclampf blue, GLclampf alpha)
  DEFINE_METHOD(blendColor, 4)
    glBlendColor(args[0]->NumberValue(),
                 args[1]->NumberValue(),
                 args[2]->NumberValue(),
                 args[3]->NumberValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void blendEquation(GLenum mode)
  DEFINE_METHOD(blendEquation, 1)    glBlendEquation(args[0]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void blendEquationSeparate(GLenum modeRGB, GLenum modeAlpha)
  DEFINE_METHOD(blendEquationSeparate, 2)    glBlendEquationSeparate(args[0]->Uint32Value(), args[1]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }


  // void blendFunc(GLenum sfactor, GLenum dfactor)
  DEFINE_METHOD(blendFunc, 2)    glBlendFunc(args[0]->Uint32Value(), args[1]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void blendFuncSeparate(GLenum srcRGB, GLenum dstRGB,
  //                        GLenum srcAlpha, GLenum dstAlpha)
  DEFINE_METHOD(blendFuncSeparate, 4)    glBlendFuncSeparate(args[0]->Uint32Value(), args[1]->Uint32Value(),
                        args[2]->Uint32Value(), args[3]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void bufferData(GLenum target, GLsizei size, GLenum usage)
  // void bufferData(GLenum target, ArrayBufferView data, GLenum usage)
  // void bufferData(GLenum target, ArrayBuffer data, GLenum usage)
  DEFINE_METHOD(bufferData, 3)
    GLsizeiptr size = 0;
    GLvoid* data = NULL;

    if (args[1]->IsObject()) {
      if (!GetTypedArrayBytes(args[1], &data, &size))
        return v8_utils::ThrowError(isolate, "Data must be a TypedArray.");
    } else {
      size = args[1]->Uint32Value();
    }

    glBufferData(args[0]->Uint32Value(), size, data, args[2]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void bufferSubData(GLenum target, GLsizeiptr offset, ArrayBufferView data)
  // void bufferSubData(GLenum target, GLsizeiptr offset, ArrayBuffer data)
  DEFINE_METHOD(bufferSubData, 3)
    GLsizeiptr size = 0;
    GLintptr offset = args[1]->Int32Value();
    GLvoid* data = NULL;

    if (args[2]->IsObject()) {
      if (!GetTypedArrayBytes(args[2], &data, &size))
        return v8_utils::ThrowError(isolate, "Data must be a TypedArray.");
    } else {
      size = args[2]->Uint32Value();
    }

    glBufferSubData(args[0]->Uint32Value(), offset, size, data);
    return args.GetReturnValue().SetUndefined();
  }

  // GLenum checkFramebufferStatus(GLenum target)
  DEFINE_METHOD(checkFramebufferStatus, 1)    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate,
        glCheckFramebufferStatus(args[0]->Uint32Value())));
  }

  // void clear(GLbitfield mask)
  DEFINE_METHOD(clear, 1)    glClear(args[0]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void clearColor(GLclampf red, GLclampf green,
  //                 GLclampf blue, GLclampf alpha)
  DEFINE_METHOD(clearColor, 4)
    glClearColor(args[0]->NumberValue(),
                 args[1]->NumberValue(),
                 args[2]->NumberValue(),
                 args[3]->NumberValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void clearDepth(GLclampf depth)
  DEFINE_METHOD(clearDepth, 1)
    glClearDepth(args[0]->NumberValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void clearStencil(GLint s)
  DEFINE_METHOD(clearStencil, 1)
    glClearStencil(args[0]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void colorMask(GLboolean red, GLboolean green,
  //                GLboolean blue, GLboolean alpha)
  DEFINE_METHOD(colorMask, 4)
    glColorMask(args[0]->BooleanValue(),
                args[1]->BooleanValue(),
                args[2]->BooleanValue(),
                args[3]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void compileShader(WebGLShader shader)
  DEFINE_METHOD(compileShader, 1)
    if (!WebGLShader::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint shader = WebGLShader::ExtractNameFromValue(args[0]);

    glCompileShader(shader);
    return args.GetReturnValue().SetUndefined();
  }

  // WebGLBuffer createBuffer()
  static void createBuffer(const v8::FunctionCallbackInfo<v8::Value>& args) {
    GLuint buffer;
    glGenBuffers(1, &buffer);
    return args.GetReturnValue().Set(WebGLBuffer::NewFromName(buffer));
  }

  // WebGLFramebuffer createFramebuffer()
  static void createFramebuffer(const v8::FunctionCallbackInfo<v8::Value>& args) {
    GLuint framebuffer;
    glGenFramebuffers(1, &framebuffer);
    return args.GetReturnValue().Set(WebGLFramebuffer::NewFromName(framebuffer));
  }

  // WebGLProgram createProgram()
  static void createProgram(const v8::FunctionCallbackInfo<v8::Value>& args) {
    return args.GetReturnValue().Set(WebGLProgram::NewFromName(glCreateProgram()));
  }

  // WebGLRenderbuffer createRenderbuffer()
  static void createRenderbuffer(const v8::FunctionCallbackInfo<v8::Value>& args) {
    GLuint renderbuffer;
    glGenRenderbuffers(1, &renderbuffer);
    return args.GetReturnValue().Set(WebGLRenderbuffer::NewFromName(renderbuffer));
  }

  // WebGLShader createShader(GLenum type)
  DEFINE_METHOD(createShader, 1)
    return args.GetReturnValue().Set(WebGLShader::NewFromName(
        glCreateShader(args[0]->Uint32Value())));
  }

  // WebGLTexture createTexture()
  static void createTexture(const v8::FunctionCallbackInfo<v8::Value>& args) {
    GLuint texture;
    glGenTextures(1, &texture);
    return args.GetReturnValue().Set(WebGLTexture::NewFromName(texture));
  }

  // WebGLVertexArrayObject? createVertexArray()
  static void createVertexArray(const v8::FunctionCallbackInfo<v8::Value>& args) {
    GLuint vao;
    glGenVertexArraysAPPLE(1, &vao);
    return args.GetReturnValue().Set(WebGLVertexArrayObject::NewFromName(vao));
  }

  // void cullFace(GLenum mode)
  DEFINE_METHOD(cullFace, 1)
    glCullFace(args[0]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void deleteBuffer(WebGLBuffer buffer)
  DEFINE_METHOD(deleteBuffer, 1)
    // Seems that Chrome does this...
    if (args[0]->IsNull() || args[0]->IsUndefined())
      return args.GetReturnValue().SetUndefined();

    if (!WebGLBuffer::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint buffer = WebGLBuffer::ExtractNameFromValue(args[0]);
    if (buffer != 0) {
      glDeleteBuffers(1, &buffer);
      WebGLBuffer::ClearName(args[0]);
    }
    return args.GetReturnValue().SetUndefined();
  }

  // void deleteFramebuffer(WebGLFramebuffer framebuffer)
  DEFINE_METHOD(deleteFramebuffer, 1)
    // Seems that Chrome does this...
    if (args[0]->IsNull() || args[0]->IsUndefined())
      return args.GetReturnValue().SetUndefined();

    if (!WebGLFramebuffer::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint framebuffer =
        WebGLFramebuffer::ExtractNameFromValue(args[0]);
    if (framebuffer != 0) {
      glDeleteFramebuffers(1, &framebuffer);
      WebGLFramebuffer::ClearName(args[0]);
    }
    return args.GetReturnValue().SetUndefined();
  }

  // void deleteProgram(WebGLProgram program)
  DEFINE_METHOD(deleteProgram, 1)
    // Seems that Chrome does this...
    if (args[0]->IsNull() || args[0]->IsUndefined())
      return args.GetReturnValue().SetUndefined();

    if (!WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint program = WebGLProgram::ExtractNameFromValue(args[0]);
    if (program != 0) {
      glDeleteProgram(program);
      WebGLProgram::ClearName(args[0]);
    }
    return args.GetReturnValue().SetUndefined();
  }

  // void deleteRenderbuffer(WebGLRenderbuffer renderbuffer)
  DEFINE_METHOD(deleteRenderbuffer, 1)
    // Seems that Chrome does this...
    if (args[0]->IsNull() || args[0]->IsUndefined())
      return args.GetReturnValue().SetUndefined();

    if (!WebGLRenderbuffer::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint renderbuffer =
        WebGLRenderbuffer::ExtractNameFromValue(args[0]);
    if (renderbuffer != 0) {
      glDeleteRenderbuffers(1, &renderbuffer);
      WebGLRenderbuffer::ClearName(args[0]);
    }
    return args.GetReturnValue().SetUndefined();
  }

  // void deleteShader(WebGLShader shader)
  DEFINE_METHOD(deleteShader, 1)
    // Seems that Chrome does this...
    if (args[0]->IsNull() || args[0]->IsUndefined())
      return args.GetReturnValue().SetUndefined();

    if (!WebGLShader::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint shader = WebGLShader::ExtractNameFromValue(args[0]);
    if (shader != 0) {
      glDeleteShader(shader);
      WebGLShader::ClearName(args[0]);
    }
    return args.GetReturnValue().SetUndefined();
  }

  // void deleteTexture(WebGLTexture texture)
  DEFINE_METHOD(deleteTexture, 1)
    // Seems that Chrome does this...
    if (args[0]->IsNull() || args[0]->IsUndefined())
      return args.GetReturnValue().SetUndefined();

    if (!WebGLTexture::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint texture =
        WebGLTexture::ExtractNameFromValue(args[0]);
    if (texture != 0) {
      glDeleteTextures(1, &texture);
      WebGLTexture::ClearName(args[0]);
    }
    return args.GetReturnValue().SetUndefined();
  }

  // void deleteVertexArray(WebGLVertexArrayObject? vertexArray)
  DEFINE_METHOD(deleteVertexArray, 1)
    // Seems that Chrome does this...
    if (args[0]->IsNull() || args[0]->IsUndefined())
      return args.GetReturnValue().SetUndefined();

    if (!WebGLVertexArrayObject::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint vao = WebGLVertexArrayObject::ExtractNameFromValue(args[0]);
    if (vao != 0) {
      glDeleteVertexArraysAPPLE(1, &vao);
      WebGLVertexArrayObject::ClearName(args[0]);
    }
    return args.GetReturnValue().SetUndefined();
  }

  // void depthFunc(GLenum func)
  DEFINE_METHOD(depthFunc, 1)
    glDepthFunc(args[0]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void depthMask(GLboolean flag)
  DEFINE_METHOD(depthMask, 1)
    glDepthMask(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void depthRange(GLclampf zNear, GLclampf zFar)
  DEFINE_METHOD(depthRange, 2)
    glDepthRange(args[0]->NumberValue(), args[1]->NumberValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void detachShader(WebGLProgram program, WebGLShader shader)
  DEFINE_METHOD(detachShader, 2)
    if (!WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    if (!WebGLShader::HasInstance(isolate, args[1]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint program = WebGLProgram::ExtractNameFromValue(args[0]);
    GLuint shader = WebGLShader::ExtractNameFromValue(args[1]);

    glDetachShader(program, shader);
    return args.GetReturnValue().SetUndefined();
  }

  // void disable(GLenum cap)
  DEFINE_METHOD(disable, 1)
    glDisable(args[0]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void disableVertexAttribArray(GLuint index)
  DEFINE_METHOD(disableVertexAttribArray, 1)
    glDisableVertexAttribArray(args[0]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void drawArrays(GLenum mode, GLint first, GLsizei count)
  DEFINE_METHOD(drawArrays, 3)
    glDrawArrays(args[0]->Uint32Value(),
                 args[1]->Int32Value(), args[2]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void drawElements(GLenum mode, GLsizei count,
  //                   GLenum type, GLsizeiptr offset)
  DEFINE_METHOD(drawElements, 4)
    glDrawElements(args[0]->Uint32Value(),
                   args[1]->Int32Value(),
                   args[2]->Uint32Value(),
                   reinterpret_cast<GLvoid*>(args[3]->Int32Value()));
    return args.GetReturnValue().SetUndefined();
  }

  // void vertexAttribDivisor(GLuint index, GLuint divisor)
  DEFINE_METHOD(vertexAttribDivisor, 2)
    glVertexAttribDivisorARB(args[0]->Uint32Value(),
                             args[1]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void drawArraysInstanced(GLenum mode, GLint first, GLsizei count, GLsizei instanceCount)
  DEFINE_METHOD(drawArraysInstanced, 4)
    glDrawArraysInstancedARB(args[0]->Uint32Value(),
                             args[1]->Int32Value(),
                             args[2]->Int32Value(),
                             args[3]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void drawElementsInstanced(GLenum mode, GLsizei count,
  //                            GLenum type, GLintptr offset,
  //                            GLsizei instanceCount)
  DEFINE_METHOD(drawElementsInstanced, 5)
    glDrawElementsInstancedARB(args[0]->Uint32Value(),
                               args[1]->Int32Value(),
                               args[2]->Uint32Value(),
                               reinterpret_cast<GLvoid*>(args[3]->Int32Value()),
                               args[4]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void drawRangeElements(GLenum mode,
  //                        GLuint start, GLuint end,
  //                        GLsizei count, GLenum type, GLintptr offset)
  DEFINE_METHOD(drawRangeElements, 6)
    glDrawRangeElementsEXT(args[0]->Uint32Value(),
                           args[1]->Uint32Value(),
                           args[2]->Uint32Value(),
                           args[3]->Int32Value(),
                           args[4]->Uint32Value(),
                           reinterpret_cast<GLvoid*>(args[5]->Int32Value()));
    return args.GetReturnValue().SetUndefined();
  }

  // void enable(GLenum cap)
  DEFINE_METHOD(enable, 1)
    glEnable(args[0]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void enableVertexAttribArray(GLuint index)
  DEFINE_METHOD(enableVertexAttribArray, 1)
    glEnableVertexAttribArray(args[0]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void finish()
  static void finish(const v8::FunctionCallbackInfo<v8::Value>& args) {
    glFinish();
    return args.GetReturnValue().SetUndefined();
  }

  // void flush()
  static void flush(const v8::FunctionCallbackInfo<v8::Value>& args) {
    glFlush();
    return args.GetReturnValue().SetUndefined();
  }

  // void framebufferRenderbuffer(GLenum target, GLenum attachment,
  //                              GLenum renderbuffertarget,
  //                              WebGLRenderbuffer renderbuffer)
  DEFINE_METHOD(framebufferRenderbuffer, 4)
    // NOTE: ExtractNameFromValue will handle null.
    if (!args[3]->IsNull() && !WebGLRenderbuffer::HasInstance(isolate, args[3]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    glFramebufferRenderbuffer(
        args[0]->Uint32Value(),
        args[1]->Uint32Value(),
        args[2]->Uint32Value(),
        WebGLRenderbuffer::ExtractNameFromValue(args[3]));
    return args.GetReturnValue().SetUndefined();
  }

  // void framebufferTexture2D(GLenum target, GLenum attachment,
  //                           GLenum textarget, WebGLTexture texture,
  //                           GLint level)
  DEFINE_METHOD(framebufferTexture2D, 5)
    // NOTE: ExtractNameFromValue will handle null.
    if (!args[3]->IsNull() && !WebGLTexture::HasInstance(isolate, args[3]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    glFramebufferTexture2D(args[0]->Uint32Value(),
                           args[1]->Uint32Value(),
                           args[2]->Uint32Value(),
                           WebGLTexture::ExtractNameFromValue(args[3]),
                           args[4]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void frontFace(GLenum mode)
  DEFINE_METHOD(frontFace, 1)
    glFrontFace(args[0]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void generateMipmap(GLenum target)
  DEFINE_METHOD(generateMipmap, 1)
    glGenerateMipmap(args[0]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // WebGLActiveInfo getActiveAttrib(WebGLProgram program, GLuint index)
  DEFINE_METHOD(getActiveAttrib, 2)
    if (!WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint program = WebGLProgram::ExtractNameFromValue(args[0]);

    char namebuf[1024];
    GLint size;
    GLenum type;

    glGetActiveAttrib(program, args[1]->Uint32Value(),
                      sizeof(namebuf), NULL, &size, &type, namebuf);

    return args.GetReturnValue().Set(
        WebGLActiveInfo::NewFromSizeTypeName(size, type, namebuf));
  }

  // WebGLActiveInfo getActiveUniform(WebGLProgram program, GLuint index)
  DEFINE_METHOD(getActiveUniform, 2)
    if (!WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint program = WebGLProgram::ExtractNameFromValue(args[0]);

    char namebuf[1024];
    GLint size;
    GLenum type;

    glGetActiveUniform(program, args[1]->Uint32Value(),
                       sizeof(namebuf), NULL, &size, &type, namebuf);

    return args.GetReturnValue().Set(WebGLActiveInfo::NewFromSizeTypeName(size, type, namebuf));
  }

  // WebGLShader[ ] getAttachedShaders(WebGLProgram program)
  DEFINE_METHOD(getAttachedShaders, 1)
    if (!WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint program = WebGLProgram::ExtractNameFromValue(args[0]);

    GLuint shaders[10];
    GLsizei count;
    glGetAttachedShaders(program, 10, &count, shaders);

    v8::Local<v8::Array> res = v8::Array::New(isolate, count);
    for (int i = 0; i < count; ++i) {
      res->Set(v8::Integer::New(isolate, i),
               WebGLShader::LookupFromName(isolate, shaders[i]));
    }

    return args.GetReturnValue().Set(res);
  }

  // GLint getAttribLocation(WebGLProgram program, DOMString name)
  DEFINE_METHOD(getAttribLocation, 2)
    if (!WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint program = WebGLProgram::ExtractNameFromValue(args[0]);

    v8::String::Utf8Value name(args[1]);
    return args.GetReturnValue().Set(v8::Integer::New(isolate, glGetAttribLocation(program, *name)));
  }

  static WebGLType get_parameter_type(GLenum pname) {
    switch (pname) {
#define WEBGL_PARAMS_EACH(name, ptype) \
      case WEBGL_##name: return WebGLType##ptype;
#include "webgl_constants.h"
#undef WEBGL_PARAMS_EACH
    }

    return WebGLTypeInvalid;
  }

  static v8::Handle<v8::Value> getBooleanArrayParameter(
      v8::Isolate* isolate,
      unsigned long pname, int length) {
    GLboolean* value = new GLboolean[length];
    glGetBooleanv(pname, value);
    v8::Local<v8::Array> ta = v8::Array::New(isolate, length);
    for (int i = 0; i < length; ++i) {
      ta->Set(i, v8::Boolean::New(isolate, value[i]));
    }
    delete[] value;

    return ta;
  }

  static v8::Handle<v8::Value> getFloat32ArrayParameter(
      v8::Isolate* isolate,
      unsigned long pname, int length) {
    float* value = new float[length];
    glGetFloatv(pname, value);
    v8::Local<v8::ArrayBuffer> buffer = v8::ArrayBuffer::New(
        isolate, sizeof(*value) * length);
    v8::Handle<v8::Float32Array> ta = v8::Float32Array::New(
        buffer, 0, buffer->ByteLength());
    for (int i = 0; i < length; ++i) {
      ta->Set(i, v8::Number::New(isolate, value[i]));
    }
    delete[] value;

    return ta;
  }

  static v8::Handle<v8::Value> getInt32ArrayParameter(
      v8::Isolate* isolate,
      unsigned long pname, int length) {
    int* value = new int[length];
    glGetIntegerv(pname, value);
    v8::Local<v8::ArrayBuffer> buffer = v8::ArrayBuffer::New(
        isolate, sizeof(*value) * length);
    v8::Handle<v8::Int32Array> ta = v8::Int32Array::New(
        buffer, 0, buffer->ByteLength());
    for (int i = 0; i < length; ++i) {
      ta->Set(i, v8::Integer::New(isolate, value[i]));
    }
    delete[] value;

    return ta;
  }

  static void getNameMappedParameter(
      v8::Isolate* isolate,
      const v8::FunctionCallbackInfo<v8::Value>& args,
      unsigned long pname,
      std::map<GLuint, v8::UniquePersistent<v8::Value> >& map) {
    int value;
    glGetIntegerv(pname, &value);
    GLuint name = static_cast<unsigned int>(value);
    if (name != 0 && map.count(name) == 1) {
      return args.GetReturnValue().Set(PersistentToLocal(isolate, map[name]));
    } else {
      return args.GetReturnValue().SetNull();
    }
  }

  // any getParameter(GLenum pname)
  DEFINE_METHOD(getParameter, 1)
    unsigned long pname = args[0]->Uint32Value();

    switch (pname) {
      case WEBGL_SHADING_LANGUAGE_VERSION:
      {
        std::string str = "WebGL GLSL ES 1.0 (";
        str.append(reinterpret_cast<const char*>(glGetString(pname)));
        str.push_back(')');
        return args.GetReturnValue().Set(
            v8::String::NewFromUtf8(isolate, str.c_str()));
      }
      case WEBGL_VENDOR:
      {
        std::string str = "Plask (";
        str.append(reinterpret_cast<const char*>(glGetString(pname)));
        str.push_back(')');
        return args.GetReturnValue().Set(
            v8::String::NewFromUtf8(isolate, str.c_str()));
      }
      case WEBGL_VERSION:
      {
        std::string str = "WebGL 1.0 (";
        str.append(reinterpret_cast<const char*>(glGetString(pname)));
        str.push_back(')');
        return args.GetReturnValue().Set(
            v8::String::NewFromUtf8(isolate, str.c_str()));
      }
    }

    WebGLType ptype = get_parameter_type(pname);
    switch (ptype) {
      case WebGLTypeDOMString:
        return args.GetReturnValue().Set(v8::String::NewFromUtf8(isolate,
            reinterpret_cast<const char*>(glGetString(pname))));
      case WebGLTypeFloat32Arrayx2:
        return args.GetReturnValue().Set(
            getFloat32ArrayParameter(isolate, pname, 2));
      case WebGLTypeFloat32Arrayx4:
        return args.GetReturnValue().Set(
            getFloat32ArrayParameter(isolate, pname, 4));
      case WebGLTypeGLboolean:
      {
        GLboolean value;
        glGetBooleanv(pname, &value);
        return args.GetReturnValue().Set((bool)static_cast<bool>(value));
      }
      case WebGLTypeGLbooleanx4:
        return args.GetReturnValue().Set(
            getBooleanArrayParameter(isolate, pname, 4));
      case WebGLTypeGLenum:
      case WebGLTypeGLuint:
      {
        GLuint value;
        glGetIntegerv(pname, reinterpret_cast<GLint*>(&value));
        return args.GetReturnValue().Set(value);
      }
      case WebGLTypeGLfloat:
      {
        float value;
        glGetFloatv(pname, &value);
        return args.GetReturnValue().Set(value);
      }
      case WebGLTypeGLint:
      {
        GLint value;
        glGetIntegerv(pname, &value);
        return args.GetReturnValue().Set(value);
      }
      case WebGLTypeInt32Arrayx2:
        return args.GetReturnValue().Set(
            getInt32ArrayParameter(isolate, pname, 2));
      case WebGLTypeInt32Arrayx4:
        return args.GetReturnValue().Set(
            getInt32ArrayParameter(isolate, pname, 4));
      case WebGLTypeUint32Array:
        // Only for compressed texture formats?
        return v8_utils::ThrowError(isolate, "Unimplemented.");
        break;
      case WebGLTypeWebGLBuffer:
        return getNameMappedParameter(isolate, args, pname, WebGLBuffer::Map());
      case WebGLTypeWebGLFramebuffer:
        return getNameMappedParameter(isolate, args, pname, WebGLFramebuffer::Map());
      case WebGLTypeWebGLProgram:
        return getNameMappedParameter(isolate, args, pname, WebGLProgram::Map());
      case WebGLTypeWebGLRenderbuffer:
        return getNameMappedParameter(isolate, args, pname, WebGLRenderbuffer::Map());
      case WebGLTypeWebGLTexture:
        return getNameMappedParameter(isolate, args, pname, WebGLTexture::Map());
      case WebGLTypeWebGLVertexArrayObject:
        return getNameMappedParameter(isolate, args, pname, WebGLVertexArrayObject::Map());
      case WebGLTypeInvalid:
        break;  // fall out.
    }

    return args.GetReturnValue().SetUndefined();
  }

  // any getBufferParameter(GLenum target, GLenum pname)
  DEFINE_METHOD(getBufferParameter, 1)
    GLenum target = args[0]->Int32Value();
    GLenum pname = args[1]->Int32Value();
    switch (pname) {
      case WEBGL_BUFFER_SIZE:
      case WEBGL_BUFFER_USAGE:
      {
        GLint value;
        glGetBufferParameteriv(target, pname, &value);
        return args.GetReturnValue().Set(value);
      }
    }

    return v8_utils::ThrowError(isolate, "INVALID_ENUM");
  }

  // GLenum getError()
  static void getError(const v8::FunctionCallbackInfo<v8::Value>& args) {
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, glGetError()));
  }

  // any getFramebufferAttachmentParameter(GLenum target, GLenum attachment,
  //                                       GLenum pname)
  DEFINE_METHOD(getFramebufferAttachmentParameter, 3)
    GLenum target     = args[0]->Uint32Value();
    GLenum attachment = args[1]->Uint32Value();
    GLenum pname      = args[2]->Uint32Value();

    GLint value;
    glGetFramebufferAttachmentParameteriv(target, attachment, pname, &value);

    switch (pname) {
      case WEBGL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME:  // Renderbuffer/texture
      {
        GLint type;
        glGetFramebufferAttachmentParameteriv(
            target, attachment, GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &type);
        switch (type) {
          case GL_RENDERBUFFER:
              return args.GetReturnValue().Set(WebGLRenderbuffer::LookupFromName(isolate, value));
          case GL_TEXTURE:
              return args.GetReturnValue().Set(WebGLTexture::LookupFromName(isolate, value));
        }
        return args.GetReturnValue().SetNull();
      }
      case WEBGL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE:  // GLenum
        return args.GetReturnValue().Set(
            v8::Integer::NewFromUnsigned(isolate, static_cast<GLenum>(value)));
      case WEBGL_FRAMEBUFFER_ATTACHMENT_TEXTURE_LEVEL:          // GLint
      case WEBGL_FRAMEBUFFER_ATTACHMENT_TEXTURE_CUBE_MAP_FACE:  // GLint
        return args.GetReturnValue().Set(v8::Integer::New(isolate, value));
    }

    return v8_utils::ThrowError(isolate, "Unimplemented.");
  }

  // any getProgramParameter(WebGLProgram program, GLenum pname)
  DEFINE_METHOD(getProgramParameter, 2)
    if (!WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint program = WebGLProgram::ExtractNameFromValue(args[0]);

    unsigned long pname = args[1]->Uint32Value();
    GLint value = 0;
    switch (pname) {
      case GL_DELETE_STATUS:
      case GL_VALIDATE_STATUS:
      case GL_LINK_STATUS:
        glGetProgramiv(program, pname, &value);
        return args.GetReturnValue().Set((bool)value);
      case GL_INFO_LOG_LENGTH:
      case GL_ATTACHED_SHADERS:
      case GL_ACTIVE_ATTRIBUTES:
      case GL_ACTIVE_ATTRIBUTE_MAX_LENGTH:
      case GL_ACTIVE_UNIFORMS:
      case GL_ACTIVE_UNIFORM_MAX_LENGTH:
        glGetProgramiv(program, pname, &value);
        return args.GetReturnValue().Set(v8::Integer::New(isolate, value));
      default:
        return args.GetReturnValue().SetUndefined();
    }
  }

  // DOMString getProgramInfoLog(WebGLProgram program)
  DEFINE_METHOD(getProgramInfoLog, 1)
    if (!WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint program = WebGLProgram::ExtractNameFromValue(args[0]);

    GLint length = 0;
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &length);
    GLchar* buf = new GLchar[length + 1];
    glGetProgramInfoLog(program, length + 1, NULL, buf);
    v8::Handle<v8::Value> res = v8::String::NewFromUtf8(
        isolate, buf, v8::String::kNormalString, length);
    delete[] buf;
    return args.GetReturnValue().Set(res);
  }

  // any getRenderbufferParameter(GLenum target, GLenum pname)
  static void getRenderbufferParameter(
      const v8::FunctionCallbackInfo<v8::Value>& args) {
    return v8_utils::ThrowError(isolate, "Unimplemented.");
  }

  // any getShaderParameter(WebGLShader shader, GLenum pname)
  DEFINE_METHOD(getShaderParameter, 2)
    if (!WebGLShader::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint shader = WebGLShader::ExtractNameFromValue(args[0]);
    unsigned long pname = args[1]->Uint32Value();
    GLint value = 0;
    switch (pname) {
      case GL_DELETE_STATUS:
      case GL_COMPILE_STATUS:
        glGetShaderiv(shader, pname, &value);
        return args.GetReturnValue().Set((bool)value);
      case GL_SHADER_TYPE:
        glGetShaderiv(shader, pname, &value);
        return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, value));
      case GL_INFO_LOG_LENGTH:
      case GL_SHADER_SOURCE_LENGTH:
        glGetShaderiv(shader, pname, &value);
        return args.GetReturnValue().Set(v8::Integer::New(isolate, value));
      default:
        return args.GetReturnValue().SetUndefined();
    }
  }

  // DOMString getShaderInfoLog(WebGLShader shader)
  DEFINE_METHOD(getShaderInfoLog, 1)
    if (!WebGLShader::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint shader = WebGLShader::ExtractNameFromValue(args[0]);
    GLint length = 0;
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &length);
    GLchar* buf = new GLchar[length + 1];
    glGetShaderInfoLog(shader, length + 1, NULL, buf);
    v8::Handle<v8::Value> res = v8::String::NewFromUtf8(
        isolate, buf, v8::String::kNormalString, length);
    delete[] buf;
    return args.GetReturnValue().Set(res);
  }

  // DOMString getShaderSource(WebGLShader shader)
  DEFINE_METHOD(getShaderSource, 1)
    if (!WebGLShader::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint shader = WebGLShader::ExtractNameFromValue(args[0]);
    GLint length = 0;
    glGetShaderiv(shader, GL_SHADER_SOURCE_LENGTH, &length);
    GLchar* buf = new GLchar[length + 1];
    glGetShaderSource(shader, length + 1, NULL, buf);
    v8::Handle<v8::Value> res = v8::String::NewFromUtf8(
        isolate, buf, v8::String::kNormalString, length);
    delete[] buf;
    return args.GetReturnValue().Set(res);
  }

  // any getTexParameter(GLenum target, GLenum pname)
  DEFINE_METHOD(getTexParameter, 2)
    // Too complicated to check GL error but specs says we should return null,
    // so just try to catch it a little bit.
    GLint value = GL_INVALID_ENUM;
    glGetTexParameteriv(args[0]->Uint32Value(),
                        args[1]->Uint32Value(),
                        &value);
    if (value == GL_INVALID_ENUM)
      return args.GetReturnValue().SetNull();
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, value));
  }

  // any getUniform(WebGLProgram program, WebGLUniformLocation location)
  static void getUniform(const v8::FunctionCallbackInfo<v8::Value>& args) {
    return v8_utils::ThrowError(isolate, "Unimplemented.");
  }

  // WebGLUniformLocation getUniformLocation(WebGLProgram program,
  //                                         DOMString name)
  DEFINE_METHOD(getUniformLocation, 2)
    if (!WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint program = WebGLProgram::ExtractNameFromValue(args[0]);

    v8::String::Utf8Value name(args[1]);
    GLint location = glGetUniformLocation(program, *name);
    if (location == -1)
      return args.GetReturnValue().SetNull();
    return args.GetReturnValue().Set(WebGLUniformLocation::NewFromLocation(location));
  }

  // any getVertexAttrib(GLuint index, GLenum pname)
  static void getVertexAttrib(
      const v8::FunctionCallbackInfo<v8::Value>& args) {
    return v8_utils::ThrowError(isolate, "Unimplemented.");
  }

  // GLsizeiptr getVertexAttribOffset(GLuint index, GLenum pname)
  static void getVertexAttribOffset(
      const v8::FunctionCallbackInfo<v8::Value>& args) {
    return v8_utils::ThrowError(isolate, "Unimplemented.");
  }

  // void hint(GLenum target, GLenum mode)
  DEFINE_METHOD(hint, 2)
    glHint(args[0]->Uint32Value(), args[1]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // GLboolean isBuffer(WebGLBuffer buffer)
  DEFINE_METHOD(isBuffer, 1)
    // Seems that Chrome does this...
    if (args[0]->IsNull() || args[0]->IsUndefined())
      return args.GetReturnValue().Set(false);

    if (!WebGLBuffer::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    return args.GetReturnValue().Set((bool)glIsBuffer(
        WebGLBuffer::ExtractNameFromValue(args[0])));
  }

  // GLboolean isEnabled(GLenum cap)
  DEFINE_METHOD(isEnabled, 1)
    return args.GetReturnValue().Set((bool)glIsEnabled(args[0]->Uint32Value()));
  }

  // GLboolean isFramebuffer(WebGLFramebuffer framebuffer)
  DEFINE_METHOD(isFramebuffer, 1)
    // Seems that Chrome does this...
    if (args[0]->IsNull() || args[0]->IsUndefined())
      return args.GetReturnValue().Set(false);

    if (!WebGLFramebuffer::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    return args.GetReturnValue().Set((bool)glIsFramebuffer(
        WebGLFramebuffer::ExtractNameFromValue(args[0])));
  }

  // GLboolean isProgram(WebGLProgram program)
  DEFINE_METHOD(isProgram, 1)
    // Seems that Chrome does this...
    if (args[0]->IsNull() || args[0]->IsUndefined())
      return args.GetReturnValue().Set(false);

    if (!WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    return args.GetReturnValue().Set((bool)glIsProgram(
        WebGLProgram::ExtractNameFromValue(args[0])));
  }

  // GLboolean isRenderbuffer(WebGLRenderbuffer renderbuffer)
  DEFINE_METHOD(isRenderbuffer, 1)
    // Seems that Chrome does this...
    if (args[0]->IsNull() || args[0]->IsUndefined())
      return args.GetReturnValue().Set(false);

    if (!WebGLRenderbuffer::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    return args.GetReturnValue().Set((bool)glIsRenderbuffer(
        WebGLRenderbuffer::ExtractNameFromValue(args[0])));
  }

  // GLboolean isShader(WebGLShader shader)
  DEFINE_METHOD(isShader, 1)
    // Seems that Chrome does this...
    if (args[0]->IsNull() || args[0]->IsUndefined())
      return args.GetReturnValue().Set(false);

    if (!WebGLShader::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    return args.GetReturnValue().Set((bool)glIsShader(
        WebGLShader::ExtractNameFromValue(args[0])));
  }

  // GLboolean isTexture(WebGLTexture texture)
  DEFINE_METHOD(isTexture, 1)
    // Seems that Chrome does this...
    if (args[0]->IsNull() || args[0]->IsUndefined())
      return args.GetReturnValue().Set(false);

    if (!WebGLTexture::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    return args.GetReturnValue().Set((bool)glIsTexture(
        WebGLTexture::ExtractNameFromValue(args[0])));
  }

  // GLboolean isVertexArray(WebGLVertexArrayObject? vertexArray)
  DEFINE_METHOD(isVertexArray, 1)
    // Seems that Chrome does this...
    if (args[0]->IsNull() || args[0]->IsUndefined())
      return args.GetReturnValue().Set(false);

    if (!WebGLVertexArrayObject::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    return args.GetReturnValue().Set((bool)glIsVertexArrayAPPLE(
        WebGLVertexArrayObject::ExtractNameFromValue(args[0])));
  }

  // void lineWidth(GLfloat width)
  DEFINE_METHOD(lineWidth, 1)
    glLineWidth(args[0]->NumberValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void linkProgram(WebGLProgram program)
  DEFINE_METHOD(linkProgram, 1)
    if (!WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    glLinkProgram(WebGLProgram::ExtractNameFromValue(args[0]));
    return args.GetReturnValue().SetUndefined();
  }

  // void pixelStorei(GLenum pname, GLint param)
  DEFINE_METHOD(pixelStorei, 2)
    glPixelStorei(args[0]->Uint32Value(), args[1]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void polygonOffset(GLfloat factor, GLfloat units)
  DEFINE_METHOD(polygonOffset, 2)
    glPolygonOffset(args[0]->NumberValue(), args[1]->NumberValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void readPixels(GLint x, GLint y, GLsizei width, GLsizei height,
  //                 GLenum format, GLenum type, ArrayBufferView pixels)
  DEFINE_METHOD(readPixels, 7)
    GLint x = args[0]->Int32Value();
    GLint y = args[1]->Int32Value();
    GLsizei width = args[2]->Int32Value();
    GLsizei height = args[3]->Int32Value();
    GLenum format = args[4]->Int32Value();
    GLenum type = args[5]->Int32Value();
    if (format != GL_RGBA)
      return v8_utils::ThrowError(isolate, "readPixels only supports GL_RGBA.");
    //format = GL_BGRA;  // TODO(deanm): Fixme.

    if (type != GL_UNSIGNED_BYTE)
      return v8_utils::ThrowError(isolate, "readPixels only supports GL_UNSIGNED_BYTE.");

    if (!args[6]->IsObject())
      return v8_utils::ThrowError(isolate, "readPixels only supports Uint8Array.");

    v8::Handle<v8::Object> data = v8::Handle<v8::Object>::Cast(args[6]);

    if (data->GetIndexedPropertiesExternalArrayDataType() !=
        v8::kExternalUnsignedByteArray)
      return v8_utils::ThrowError(isolate, "readPixels only supports Uint8Array.");

    // TODO(deanm):  From the spec (requires synthesizing gl errors):
    //   If pixels is non-null, but is not large enough to retrieve all of the
    //   pixels in the specified rectangle taking into account pixel store
    //   modes, an INVALID_OPERATION value is generated.
    if (data->GetIndexedPropertiesExternalArrayDataLength() < width*height*4)
      return v8_utils::ThrowError(isolate, "Uint8Array buffer too small.");

    glReadPixels(x, y, width, height, format, type,
                 data->GetIndexedPropertiesExternalArrayData());
    return args.GetReturnValue().SetUndefined();
  }

  // void renderbufferStorage(GLenum target, GLenum internalformat,
  //                          GLsizei width, GLsizei height)
  DEFINE_METHOD(renderbufferStorage, 4)
    glRenderbufferStorage(args[0]->Uint32Value(),
                          args[1]->Uint32Value(),
                          args[2]->Int32Value(),
                          args[3]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void renderbufferStorageMultisample(GLenum target, GLsizei samples,
  //                                     GLenum internalformat,
  //                                     GLsizei width, GLsizei height)
  DEFINE_METHOD(renderbufferStorageMultisample, 5)
    glRenderbufferStorageMultisample(args[0]->Uint32Value(),
                                     args[1]->Int32Value(),
                                     args[2]->Uint32Value(),
                                     args[3]->Int32Value(),
                                     args[4]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void sampleCoverage(GLclampf value, GLboolean invert)
  DEFINE_METHOD(sampleCoverage, 2)
    glSampleCoverage(args[0]->NumberValue(),
                     args[1]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void scissor(GLint x, GLint y, GLsizei width, GLsizei height)
  DEFINE_METHOD(scissor, 4)
    glScissor(args[0]->Int32Value(),
              args[1]->Int32Value(),
              args[2]->Int32Value(),
              args[3]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void shaderSource(WebGLShader shader, DOMString source)
  DEFINE_METHOD(shaderSource, 2)
    if (!WebGLShader::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint shader = WebGLShader::ExtractNameFromValue(args[0]);

    v8::String::Utf8Value data(args[1]);
    // NOTE(deanm): We want GLSL version 1.20.  Is there a better way to do this
    // than sneaking in a #version at the beginning?
    const GLchar* strs[] = { "#version 120\n", *data };
    glShaderSource(shader, 2, strs, NULL);
    return args.GetReturnValue().SetUndefined();
  }

  // void stencilFunc(GLenum func, GLint ref, GLuint mask)
  DEFINE_METHOD(stencilFunc, 3)
    glStencilFunc(args[0]->Uint32Value(),
                  args[1]->Int32Value(),
                  args[2]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void stencilFuncSeparate(GLenum face, GLenum func, GLint ref, GLuint mask)
  DEFINE_METHOD(stencilFuncSeparate, 4)
    glStencilFuncSeparate(args[0]->Uint32Value(),
                          args[1]->Uint32Value(),
                          args[2]->Int32Value(),
                          args[3]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void stencilMask(GLuint mask)
  DEFINE_METHOD(stencilMask, 1)
    glStencilMask(args[0]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void stencilMaskSeparate(GLenum face, GLuint mask)
  DEFINE_METHOD(stencilMaskSeparate, 2)
    glStencilMaskSeparate(args[0]->Uint32Value(), args[1]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void stencilOp(GLenum fail, GLenum zfail, GLenum zpass)
  DEFINE_METHOD(stencilOp, 3)
    glStencilOp(args[0]->Uint32Value(),
                args[1]->Uint32Value(),
                args[2]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void stencilOpSeparate(GLenum face, GLenum fail,
  //                        GLenum zfail, GLenum zpass)
  DEFINE_METHOD(stencilOpSeparate, 4)
    glStencilOpSeparate(args[0]->Uint32Value(),
                        args[1]->Uint32Value(),
                        args[2]->Uint32Value(),
                        args[3]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void texImage2D(GLenum target, GLint level, GLenum internalformat,
  //                 GLsizei width, GLsizei height, GLint border,
  //                 GLenum format, GLenum type, ArrayBufferView pixels)
  // void texImage2D(GLenum target, GLint level, GLenum internalformat,
  //                 GLenum format, GLenum type, ImageData pixels)
  // void texImage2D(GLenum target, GLint level, GLenum internalformat,
  //                 GLenum format, GLenum type, HTMLImageElement image)
  // void texImage2D(GLenum target, GLint level, GLenum internalformat,
  //                 GLenum format, GLenum type, HTMLCanvasElement canvas)
  // void texImage2D(GLenum target, GLint level, GLenum internalformat,
  //                 GLenum format, GLenum type, HTMLVideoElement video)
  DEFINE_METHOD(texImage2D, 9)
    GLvoid* data = NULL;
    GLsizeiptr size = 0;  // FIXME use size

    if (!args[8]->IsNull()) {
      // TODO(deanm): Check size / format.  For now just use it correctly.
      if (!GetTypedArrayBytes(args[8], &data, &size))
        return v8_utils::ThrowError(isolate, "Data must be a TypedArray.");
    }

    // TODO(deanm): Support more than just the zero initialization case.
    glTexImage2D(args[0]->Uint32Value(),  // target
                 args[1]->Int32Value(),   // level
                 args[2]->Int32Value(),   // internalFormat
                 args[3]->Int32Value(),   // width
                 args[4]->Int32Value(),   // height
                 args[5]->Int32Value(),   // border
                 args[6]->Uint32Value(),  // format
                 args[7]->Uint32Value(),  // type
                 data);                   // data
    return args.GetReturnValue().SetUndefined();
  }

  // NOTE: implemented outside of class definition (SkCanvasWrapper dependency).
  static void texImage2DSkCanvasB(const v8::FunctionCallbackInfo<v8::Value>& args);
  static void drawSkCanvas(const v8::FunctionCallbackInfo<v8::Value>& args);

  // void texParameterf(GLenum target, GLenum pname, GLfloat param)
  DEFINE_METHOD(texParameterf, 3)
    glTexParameterf(args[0]->Uint32Value(),
                    args[1]->Uint32Value(),
                    args[2]->NumberValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void texParameteri(GLenum target, GLenum pname, GLint param)
  DEFINE_METHOD(texParameteri, 3)
    glTexParameteri(args[0]->Uint32Value(),
                    args[1]->Uint32Value(),
                    args[2]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void texSubImage2D(GLenum target, GLint level,
  //                    GLint xoffset, GLint yoffset,
  //                    GLsizei width, GLsizei height,
  //                    GLenum format, GLenum type, ArrayBufferView pixels)
  // void texSubImage2D(GLenum target, GLint level,
  //                    GLint xoffset, GLint yoffset,
  //                    GLenum format, GLenum type, ImageData pixels)
  // void texSubImage2D(GLenum target, GLint level,
  //                    GLint xoffset, GLint yoffset,
  //                    GLenum format, GLenum type, HTMLImageElement image)
  // void texSubImage2D(GLenum target, GLint level,
  //                    GLint xoffset, GLint yoffset,
  //                    GLenum format, GLenum type, HTMLCanvasElement canvas)
  // void texSubImage2D(GLenum target, GLint level,
  //                    GLint xoffset, GLint yoffset,
  //                    GLenum format, GLenum type, HTMLVideoElement video)

  DEFINE_METHOD(texSubImage2D, 9)
    GLvoid* data = NULL;
    GLsizeiptr size = 0;  // FIXME use size

    if (!args[8]->IsNull()) {
      if (!GetTypedArrayBytes(args[8], &data, &size))
        return v8_utils::ThrowError(isolate, "Data must be a TypedArray.");
    }

    glTexSubImage2D(args[0]->Uint32Value(),  // target
                    args[1]->Int32Value(),   // level
                    args[2]->Int32Value(),   // xoffset
                    args[3]->Int32Value(),   // yoffset
                    args[4]->Int32Value(),   // width
                    args[5]->Int32Value(),   // height
                    args[6]->Uint32Value(),  // format
                    args[7]->Uint32Value(),  // type
                    data);                   // data
    return args.GetReturnValue().SetUndefined();
  }

  static void uniformfvHelper(
      void (*uniformFunc)(GLint, GLsizei, const GLfloat*),
      GLsizei numcomps,
      const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError(isolate, "Wrong number of arguments.");

    if (args[0]->IsNull())  // null location is silently ignored.
      return args.GetReturnValue().SetUndefined();

    if (!WebGLUniformLocation::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    int length = 0;
    if (!args[1]->IsObject())
      return v8_utils::ThrowError(isolate, "value must be an Sequence.");

    v8::Handle<v8::Object> obj = v8::Handle<v8::Object>::Cast(args[1]);
    if (obj->IsTypedArray()) {
      length = v8::Handle<v8::TypedArray>::Cast(obj)->Length();
    } else if (obj->IsArray()) {
      length = v8::Handle<v8::Array>::Cast(obj)->Length();
    } else {
      return v8_utils::ThrowError(isolate, "value must be an Sequence.");
    }

    if (length % numcomps)
      return v8_utils::ThrowError(isolate, "Sequence size not multiple of components.");

    float* buffer = new float[length];
    if (!buffer)
      return v8_utils::ThrowError(isolate, "Unable to allocate memory for sequence.");

    for (int i = 0; i < length; ++i) {
      buffer[i] = obj->Get(i)->NumberValue();
    }
    uniformFunc(location, length / numcomps, buffer);
    delete[] buffer;
    return args.GetReturnValue().SetUndefined();
  }

  static void uniformivHelper(
      void (*uniformFunc)(GLint, GLsizei, const GLint*),
      GLsizei numcomps,
      const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError(isolate, "Wrong number of arguments.");

    if (args[0]->IsNull())  // null location is silently ignored.
      return args.GetReturnValue().SetUndefined();

    if (!WebGLUniformLocation::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    int length = 0;
    if (!args[1]->IsObject())
      return v8_utils::ThrowError(isolate, "value must be an Sequence.");

    v8::Handle<v8::Object> obj = v8::Handle<v8::Object>::Cast(args[1]);
    if (obj->IsTypedArray()) {
      length = v8::Handle<v8::TypedArray>::Cast(obj)->Length();
    } else if (obj->IsArray()) {
      length = v8::Handle<v8::Array>::Cast(obj)->Length();
    } else {
      return v8_utils::ThrowError(isolate, "value must be an Sequence.");
    }

    if (length % numcomps)
      return v8_utils::ThrowError(isolate, "Sequence size not multiple of components.");

    GLint* buffer = new GLint[length];
    if (!buffer)
      return v8_utils::ThrowError(isolate, "Unable to allocate memory for sequence.");

    for (int i = 0; i < length; ++i) {
      buffer[i] = obj->Get(i)->Int32Value();
    }
    uniformFunc(location, length / numcomps, buffer);
    delete[] buffer;
    return args.GetReturnValue().SetUndefined();
  }

  // void uniform1f(WebGLUniformLocation location, GLfloat x)
  DEFINE_METHOD(uniform1f, 2)
    if (args[0]->IsNull())  // null location is silently ignored.
      return args.GetReturnValue().SetUndefined();

    if (!WebGLUniformLocation::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform1f(location, args[1]->NumberValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void uniform1fv(WebGLUniformLocation location, Float32Array v)
  // void uniform1fv(WebGLUniformLocation location, sequence v)
  static void uniform1fv(const v8::FunctionCallbackInfo<v8::Value>& args) {
    return uniformfvHelper(glUniform1fv, 1, args);
  }

  // void uniform1i(WebGLUniformLocation location, GLint x)
  DEFINE_METHOD(uniform1i, 2)
    if (args[0]->IsNull())  // null location is silently ignored.
      return args.GetReturnValue().SetUndefined();

    if (!WebGLUniformLocation::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform1i(location, args[1]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void uniform1iv(WebGLUniformLocation location, Int32Array v)
  // void uniform1iv(WebGLUniformLocation location, sequence v)
  static void uniform1iv(const v8::FunctionCallbackInfo<v8::Value>& args) {
    return uniformivHelper(glUniform1iv, 1, args);
  }

  // void uniform2f(WebGLUniformLocation location, GLfloat x, GLfloat y)
  DEFINE_METHOD(uniform2f, 3)
    if (args[0]->IsNull())  // null location is silently ignored.
      return args.GetReturnValue().SetUndefined();

    if (!WebGLUniformLocation::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform2f(location,
                args[1]->NumberValue(),
                args[2]->NumberValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void uniform2fv(WebGLUniformLocation location, Float32Array v)
  // void uniform2fv(WebGLUniformLocation location, sequence v)
  static void uniform2fv(const v8::FunctionCallbackInfo<v8::Value>& args) {
    return uniformfvHelper(glUniform2fv, 2, args);
  }

  // void uniform2i(WebGLUniformLocation location, GLint x, GLint y)
  DEFINE_METHOD(uniform2i, 3)
    if (args[0]->IsNull())  // null location is silently ignored.
      return args.GetReturnValue().SetUndefined();

    if (!WebGLUniformLocation::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform2i(location,
                args[1]->Int32Value(),
                args[2]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void uniform2iv(WebGLUniformLocation location, Int32Array v)
  // void uniform2iv(WebGLUniformLocation location, sequence v)
  static void uniform2iv(const v8::FunctionCallbackInfo<v8::Value>& args) {
    return uniformivHelper(glUniform2iv, 2, args);
  }

  // void uniform3f(WebGLUniformLocation location, GLfloat x, GLfloat y,
  //                GLfloat z)
  DEFINE_METHOD(uniform3f, 4)
    if (args[0]->IsNull())  // null location is silently ignored.
      return args.GetReturnValue().SetUndefined();

    if (!WebGLUniformLocation::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform3f(location,
                args[1]->NumberValue(),
                args[2]->NumberValue(),
                args[3]->NumberValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void uniform3fv(WebGLUniformLocation location, Float32Array v)
  // void uniform3fv(WebGLUniformLocation location, sequence v)
  static void uniform3fv(const v8::FunctionCallbackInfo<v8::Value>& args) {
    return uniformfvHelper(glUniform3fv, 3, args);
  }

  // void uniform3i(WebGLUniformLocation location, GLint x, GLint y, GLint z)
  DEFINE_METHOD(uniform3i, 4)
    if (args[0]->IsNull())  // null location is silently ignored.
      return args.GetReturnValue().SetUndefined();

    if (!WebGLUniformLocation::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform3i(location,
                args[1]->Int32Value(),
                args[2]->Int32Value(),
                args[3]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void uniform3iv(WebGLUniformLocation location, Int32Array v)
  // void uniform3iv(WebGLUniformLocation location, sequence v)
  static void uniform3iv(const v8::FunctionCallbackInfo<v8::Value>& args) {
    return uniformivHelper(glUniform3iv, 3, args);
  }

  // void uniform4f(WebGLUniformLocation location, GLfloat x, GLfloat y,
  //                GLfloat z, GLfloat w)
  DEFINE_METHOD(uniform4f, 5)
    if (args[0]->IsNull())  // null location is silently ignored.
      return args.GetReturnValue().SetUndefined();

    if (!WebGLUniformLocation::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform4f(location,
                args[1]->NumberValue(),
                args[2]->NumberValue(),
                args[3]->NumberValue(),
                args[4]->NumberValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void uniform4fv(WebGLUniformLocation location, Float32Array v)
  // void uniform4fv(WebGLUniformLocation location, sequence v)
  static void uniform4fv(const v8::FunctionCallbackInfo<v8::Value>& args) {
    return uniformfvHelper(glUniform4fv, 4, args);
  }

  // void uniform4i(WebGLUniformLocation location, GLint x, GLint y,
  //                GLint z, GLint w)
  DEFINE_METHOD(uniform4i, 5)
    if (args[0]->IsNull())  // null location is silently ignored.
      return args.GetReturnValue().SetUndefined();

    if (!WebGLUniformLocation::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform4i(location,
                args[1]->Int32Value(),
                args[2]->Int32Value(),
                args[3]->Int32Value(),
                args[4]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void uniform4iv(WebGLUniformLocation location, Int32Array v)
  // void uniform4iv(WebGLUniformLocation location, sequence v)
  static void uniform4iv(const v8::FunctionCallbackInfo<v8::Value>& args) {
    return uniformivHelper(glUniform4iv, 4, args);
  }

  static void uniformMatrixfvHelper(
      void (*uniformFunc)(GLint, GLsizei, GLboolean, const GLfloat*),
      GLsizei numcomps,
      const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (args.Length() != 3)
      return v8_utils::ThrowError(isolate, "Wrong number of arguments.");

    if (args[0]->IsNull())  // null location is silently ignored.
      return args.GetReturnValue().SetUndefined();

    if (!WebGLUniformLocation::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    int length = 0;
    if (!args[2]->IsObject())
      return v8_utils::ThrowError(isolate, "value must be an Sequence.");

    v8::Handle<v8::Object> obj = v8::Handle<v8::Object>::Cast(args[2]);
    if (obj->IsTypedArray()) {
      length = v8::Handle<v8::TypedArray>::Cast(obj)->Length();
    } else if (obj->IsArray()) {
      length = v8::Handle<v8::Array>::Cast(obj)->Length();
    } else {
      return v8_utils::ThrowError(isolate, "value must be an Sequence.");
    }

    if (length % numcomps)
      return v8_utils::ThrowError(isolate, "Sequence size not multiple of components.");

    float* buffer = new float[length];
    if (!buffer)
      return v8_utils::ThrowError(isolate, "Unable to allocate memory for sequence.");

    for (int i = 0; i < length; ++i) {
      buffer[i] = obj->Get(i)->NumberValue();
    }
    uniformFunc(location, length / numcomps, GL_FALSE, buffer);
    delete[] buffer;
    return args.GetReturnValue().SetUndefined();
  }

  // void uniformMatrix2fv(WebGLUniformLocation location, GLboolean transpose,
  //                       Float32Array value)
  // void uniformMatrix2fv(WebGLUniformLocation location, GLboolean transpose,
  //                       sequence value)
  static void uniformMatrix2fv(const v8::FunctionCallbackInfo<v8::Value>& args) {
    return uniformMatrixfvHelper(glUniformMatrix2fv, 4, args);
  }

  // void uniformMatrix3fv(WebGLUniformLocation location, GLboolean transpose,
  //                       Float32Array value)
  // void uniformMatrix3fv(WebGLUniformLocation location, GLboolean transpose,
  //                       sequence value)
  static void uniformMatrix3fv(const v8::FunctionCallbackInfo<v8::Value>& args) {
    return uniformMatrixfvHelper(glUniformMatrix3fv, 9, args);
  }

  // void uniformMatrix4fv(WebGLUniformLocation location, GLboolean transpose,
  //                       Float32Array value)
  // void uniformMatrix4fv(WebGLUniformLocation location, GLboolean transpose,
  //                       sequence value)
  static void uniformMatrix4fv(const v8::FunctionCallbackInfo<v8::Value>& args) {
    return uniformMatrixfvHelper(glUniformMatrix4fv, 16, args);
  }

  // void useProgram(WebGLProgram program)
  DEFINE_METHOD(useProgram, 1)
    // Break the WebGL spec by allowing you to pass 'null' to unbind
    // the shader, handy for drawSkCanvas, for example.
    // NOTE: ExtractNameFromValue handles null.
    if (!args[0]->IsNull() && !WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    glUseProgram(WebGLProgram::ExtractNameFromValue(args[0]));
    return args.GetReturnValue().SetUndefined();
  }

  // void validateProgram(WebGLProgram program)
  DEFINE_METHOD(validateProgram, 1)
    if (!WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint program = WebGLProgram::ExtractNameFromValue(args[0]);

    glValidateProgram(program);
    return args.GetReturnValue().SetUndefined();
  }

  // NOTE: The array forms (functions that end in v) are handled in plask.js.

  // void vertexAttrib1f(GLuint indx, GLfloat x)
  // void vertexAttrib1fv(GLuint indx, Float32Array values)
  // void vertexAttrib1fv(GLuint indx, sequence values)
  DEFINE_METHOD(vertexAttrib1f, 2)
    glVertexAttrib1f(args[0]->Uint32Value(),
                     args[1]->NumberValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void vertexAttrib2f(GLuint indx, GLfloat x, GLfloat y)
  // void vertexAttrib2fv(GLuint indx, Float32Array values)
  // void vertexAttrib2fv(GLuint indx, sequence values)
  DEFINE_METHOD(vertexAttrib2f, 3)
    glVertexAttrib2f(args[0]->Uint32Value(),
                     args[1]->NumberValue(),
                     args[2]->NumberValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void vertexAttrib3f(GLuint indx, GLfloat x, GLfloat y, GLfloat z)
  // void vertexAttrib3fv(GLuint indx, Float32Array values)
  // void vertexAttrib3fv(GLuint indx, sequence values)
  DEFINE_METHOD(vertexAttrib3f, 4)
    glVertexAttrib3f(args[0]->Uint32Value(),
                     args[1]->NumberValue(),
                     args[2]->NumberValue(),
                     args[3]->NumberValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void vertexAttrib4f(GLuint indx, GLfloat x, GLfloat y,
  //                     GLfloat z, GLfloat w)
  // void vertexAttrib4fv(GLuint indx, Float32Array values)
  // void vertexAttrib4fv(GLuint indx, sequence values)
  DEFINE_METHOD(vertexAttrib4f, 5)
    glVertexAttrib4f(args[0]->Uint32Value(),
                     args[1]->NumberValue(),
                     args[2]->NumberValue(),
                     args[3]->NumberValue(),
                     args[4]->NumberValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void vertexAttribPointer(GLuint indx, GLint size, GLenum type,
  //                          GLboolean normalized, GLsizei stride,
  //                          GLsizeiptr offset)
  DEFINE_METHOD(vertexAttribPointer, 6)
    glVertexAttribPointer(args[0]->Uint32Value(),
                          args[1]->Int32Value(),
                          args[2]->Uint32Value(),
                          args[3]->BooleanValue(),
                          args[4]->Int32Value(),
                          reinterpret_cast<GLvoid*>(args[5]->Int32Value()));
    return args.GetReturnValue().SetUndefined();
  }

  // void viewport(GLint x, GLint y, GLsizei width, GLsizei height)
  DEFINE_METHOD(viewport, 4)
    glViewport(args[0]->Int32Value(),
               args[1]->Int32Value(),
               args[2]->Int32Value(),
               args[3]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void DrawBuffersARB(sizei n, const enum *bufs);
  DEFINE_METHOD(drawBuffers, 1)
    if (!args[0]->IsArray())
      return v8_utils::ThrowError(isolate, "Sequence must be an Array.");

    v8::Local<v8::Array> arr = v8::Local<v8::Array>::Cast(args[0]);

    uint32_t length = arr->Length();
    GLenum* attachments = new GLenum[length];
    for (uint32_t i = 0; i < length; ++i) {
      attachments[i] = arr->Get(i)->Uint32Value();
    }

    glDrawBuffers(length, attachments);
    delete[] attachments;
    return args.GetReturnValue().SetUndefined();
  }

  // void glBlitFramebuffer(GLint srcX0,
  //                        GLint srcY0,
  //                        GLint srcX1,
  //                        GLint srcY1,
  //                        GLint dstX0,
  //                        GLint dstY0,
  //                        GLint dstX1,
  //                        GLint dstY1,
  //                        GLbitfield mask,
  //                        GLenum filter);
  DEFINE_METHOD(blitFramebuffer, 10)
    glBlitFramebuffer(args[0]->Int32Value(),
                      args[1]->Int32Value(),
                      args[2]->Int32Value(),
                      args[3]->Int32Value(),
                      args[4]->Int32Value(),
                      args[5]->Int32Value(),
                      args[6]->Int32Value(),
                      args[7]->Int32Value(),
                      args[8]->Uint32Value(),
                      args[9]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }
};


class NSWindowWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &NSWindowWrapper::V8New);
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(2);  // NSWindow, and gl context.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
      { "kValue", 12 },
    };

    static BatchedMethods methods[] = {
      { "blit", &NSWindowWrapper::blit },
      { "mouseLocationOutsideOfEventStream",
        &NSWindowWrapper::mouseLocationOutsideOfEventStream },
      { "setAcceptsMouseMovedEvents",
        &NSWindowWrapper::setAcceptsMouseMovedEvents },
      { "setAcceptsFileDrag", &NSWindowWrapper::setAcceptsFileDrag },
      { "setEventCallback",
        &NSWindowWrapper::setEventCallback },
      { "setTitle", &NSWindowWrapper::setTitle },
      { "setFrameTopLeftPoint", &NSWindowWrapper::setFrameTopLeftPoint },
      { "center", &NSWindowWrapper::center },
      { "hideCursor", &NSWindowWrapper::hideCursor },
      { "showCursor", &NSWindowWrapper::showCursor },
      { "hide", &NSWindowWrapper::hide },
      { "show", &NSWindowWrapper::show },
      { "screenSize", &NSWindowWrapper::screenSize },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      ft->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
              v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
                    v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, methods[i].name),
                    v8::FunctionTemplate::New(isolate, methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static WrappedNSWindow* ExtractWindowPointer(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<WrappedNSWindow*>(obj->GetAlignedPointerFromInternalField(0));
  }

  static NSOpenGLContext* ExtractContextPointer(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<NSOpenGLContext*>(obj->GetAlignedPointerFromInternalField(1));
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

 private:
  DEFINE_METHOD(V8New, 8)
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    uint32_t type = args[0]->Uint32Value();
    uint32_t bwidth = args[1]->Uint32Value();
    uint32_t bheight = args[2]->Uint32Value();
    bool multisample = args[3]->BooleanValue();
    int display = args[4]->Int32Value();
    bool borderless = args[5]->BooleanValue();
    bool fullscreen = args[6]->BooleanValue();
    uint32_t dpi_factor = args[7]->Uint32Value();

    if (type != 1)
      return v8_utils::ThrowError(isolate, "2d windows no longer supported.");

    NSScreen* screen = [NSScreen mainScreen];
    NSArray* screens = [NSScreen screens];

    if (display < [screens count]) {
      screen = [screens objectAtIndex:display];
      NSLog(@"Using alternate screen: %@", screen);
    }

    bool use_highdpi = false;
    uint32_t width = bwidth;
    uint32_t height = bheight;

    if (dpi_factor == 2) {
      if ((bwidth & 1) || (bheight & 1)) {
        NSLog(@"Warning, width/height must be multiple of 2 for highdpi.");
      } else if (![screen respondsToSelector:@selector(backingScaleFactor)]) {
        NSLog(@"Warning, OSX version doesn't support highdpi (<10.7?).");
      } else if ([screen backingScaleFactor] != dpi_factor) {
        NSLog(@"Warning, screen didn't support highdpi.");
      } else {
        use_highdpi = true;
        width = bwidth >> 1;
        height = bheight >> 1;
      }
    }

    int style_mask = NSTitledWindowMask; // | NSClosableWindowMask

    if (borderless)
      style_mask = NSBorderlessWindowMask;

    WrappedNSWindow* window = [[WrappedNSWindow alloc]
        initWithContentRect:NSMakeRect(0.0, 0.0,
                                       width,
                                       height)
        styleMask:style_mask
        backing:NSBackingStoreBuffered
        defer:NO
        screen: screen];

    // Don't really see the point of the "User Interface Preservation" (added
    // in 10.7) for something like Plask.  Disable it on our windows.
    if ([window respondsToSelector:@selector(setRestorable:)])
      [window setRestorable:NO];

    // CGColorSpaceRef rgb_space = CGColorSpaceCreateDeviceRGB();
    // CGBitmapContextCreate(NULL, width, height, 8, width * 4, rgb_space,
    //                       kCGBitmapByteOrder32Little |
    //                       kCGImageAlphaNoneSkipFirst);
    // CGColorSpaceRelease(rgb_space)
    //
    // kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little;
    NSOpenGLContext* context = NULL;

    NSOpenGLPixelFormatAttribute attrs[] = {
        NSOpenGLPFAColorSize, 24,
        NSOpenGLPFADepthSize, 16,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAAccelerated,
        NSOpenGLPFAStencilSize, 8,
        // Truncate here for non-multisampling
        NSOpenGLPFAMultisample,
        NSOpenGLPFASampleBuffers, 1,
        NSOpenGLPFASamples, 4,
        NSOpenGLPFANoRecovery,
        0
    };

    if (!multisample)
      attrs[6] = 0;

    NSOpenGLPixelFormat* format = [[NSOpenGLPixelFormat alloc]
                                      initWithAttributes:attrs];
    NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0,
                                                            width, height)];
    if (use_highdpi)
      [view setWantsBestResolutionOpenGLSurface:YES];
    context = [[NSOpenGLContext alloc] initWithFormat:format
                                       shareContext:nil];
    [format release];
    [window setContentView:view];
    [context setView:view];
    [view release];

    // Make sure both sides of the buffer are cleared.
    [context makeCurrentContext];
    for (int i = 0; i < 2; ++i) {
      glClearColor(0, 0, 0, 0);
      glClear(GL_COLOR_BUFFER_BIT |
              GL_DEPTH_BUFFER_BIT |
              GL_STENCIL_BUFFER_BIT);
      [context flushBuffer];
    }

    if (multisample) {
      glEnable(GL_MULTISAMPLE_ARB);
      glHint(GL_MULTISAMPLE_FILTER_HINT_NV, GL_NICEST);
    }

    // Point sprite support.
    glEnable(GL_POINT_SPRITE);
    glEnable(GL_VERTEX_PROGRAM_POINT_SIZE);

    v8::Local<v8::FunctionTemplate> ft = v8::Local<v8::FunctionTemplate>::New(
        isolate, NSOpenGLContextWrapper::GetTemplate(isolate));
    v8::Local<v8::Object> context_wrapper = ft->
        InstanceTemplate()->NewInstance();
    context_wrapper->SetAlignedPointerInInternalField(0, context);
    args.This()->Set(v8::String::NewFromUtf8(isolate, "context"), context_wrapper);

    if (fullscreen)
      [window setLevel:NSMainMenuWindowLevel+1];
    // NOTE(deanm): We currently aren't even using the delegate for anything,
    // so might as well leave it to nil for now.
    // And oh yeah, setDelegate doesn't retain (because delegates could create
    // cycles, or be the same object, etc).  There was previously a bug here
    // where the delegate was autoreleased.  clang's memory static analysis
    // was no help for that one either.
    // [window setDelegate:[[WindowDelegate alloc] init]];
    [window makeKeyAndOrderFront:nil];

    args.This()->SetAlignedPointerInInternalField(0, window);
    args.This()->SetAlignedPointerInInternalField(1, context);


  }

  static void blit(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSOpenGLContext* context = ExtractContextPointer(args.Holder());
    [context flushBuffer];
    return args.GetReturnValue().SetUndefined();
  }

  static void mouseLocationOutsideOfEventStream(
      const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
    NSPoint pos = [window mouseLocationOutsideOfEventStream];
    v8::Local<v8::Object> res = v8::Object::New(isolate);
    res->Set(v8::String::NewFromUtf8(isolate, "x"), v8::Number::New(isolate, pos.x));
    res->Set(v8::String::NewFromUtf8(isolate, "y"), v8::Number::New(isolate, pos.y));
    return args.GetReturnValue().Set(res);
  }

  static void setAcceptsMouseMovedEvents(
      const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
    [window setAcceptsMouseMovedEvents:args[0]->BooleanValue()];
    return args.GetReturnValue().SetUndefined();
  }

  static void setAcceptsFileDrag(
      const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
    if (args[0]->BooleanValue()) {
      [window registerForDraggedTypes:
          [NSArray arrayWithObject:NSFilenamesPboardType]];
    } else {
      [window unregisterDraggedTypes];
    }
    return args.GetReturnValue().SetUndefined();
  }

  // You should only really call this once, it's a pretty raw function.
  static void setEventCallback(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (args.Length() != 1 || !args[0]->IsFunction())
      return v8_utils::ThrowError(isolate, "Incorrect invocation of setEventCallback.");
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
    [window setEventCallbackWithHandle:v8::Handle<v8::Function>::Cast(args[0])];
    return args.GetReturnValue().SetUndefined();
  }

  static void setTitle(const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
    v8::String::Utf8Value title(args[0]);
    [window setTitle:[NSString stringWithUTF8String:*title]];
    return args.GetReturnValue().SetUndefined();
  }
  DEFINE_METHOD(setFrameTopLeftPoint, 2)
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
    [window setFrameTopLeftPoint:NSMakePoint(args[0]->NumberValue(),
                                             args[1]->NumberValue())];
    return args.GetReturnValue().SetUndefined();
  }

  static void center(const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
    [window center];
    return args.GetReturnValue().SetUndefined();
  }

  static void hideCursor(const v8::FunctionCallbackInfo<v8::Value>& args) {
    CGDisplayHideCursor(kCGDirectMainDisplay);
    return args.GetReturnValue().SetUndefined();
  }

  static void showCursor(const v8::FunctionCallbackInfo<v8::Value>& args) {
    CGDisplayShowCursor(kCGDirectMainDisplay);
    return args.GetReturnValue().SetUndefined();
  }

  static void hide(const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
    [window orderOut:nil];
    return args.GetReturnValue().SetUndefined();
  }

  static void show(const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
    switch (args[0]->Uint32Value()) {
      case 0:  // Also when no argument was passed.
        [window makeKeyAndOrderFront:nil];
        break;
      case 1:
        [window orderFront:nil];
        break;
      case 2:
        [window orderBack:nil];
        break;
      default:
        return v8_utils::ThrowError(isolate, "Unknown argument to show().");
        break;
    }

    return args.GetReturnValue().SetUndefined();
  }

  static void screenSize(const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
    NSRect frame = [[window screen] frame];
    v8::Local<v8::Object> res = v8::Object::New(isolate);
    res->Set(v8::String::NewFromUtf8(isolate, "width"), v8::Number::New(isolate, frame.size.width));
    res->Set(v8::String::NewFromUtf8(isolate, "height"), v8::Number::New(isolate, frame.size.height));
    return args.GetReturnValue().Set(res);
  }

};


class NSEventWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &NSEventWrapper::V8New);
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // NSEvent pointer.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
      { "NSLeftMouseDown", NSLeftMouseDown },
      { "NSLeftMouseUp", NSLeftMouseUp },
      { "NSRightMouseDown", NSRightMouseDown },
      { "NSRightMouseUp", NSRightMouseUp },
      { "NSMouseMoved", NSMouseMoved },
      { "NSLeftMouseDragged", NSLeftMouseDragged },
      { "NSRightMouseDragged", NSRightMouseDragged },
      { "NSMouseEntered", NSMouseEntered },
      { "NSMouseExited", NSMouseExited },
      { "NSKeyDown", NSKeyDown },
      { "NSKeyUp", NSKeyUp },
      { "NSFlagsChanged", NSFlagsChanged },
      { "NSAppKitDefined", NSAppKitDefined },
      { "NSSystemDefined", NSSystemDefined },
      { "NSApplicationDefined", NSApplicationDefined },
      { "NSPeriodic", NSPeriodic },
      { "NSCursorUpdate", NSCursorUpdate },
      { "NSScrollWheel", NSScrollWheel },
      { "NSTabletPoint", NSTabletPoint },
      { "NSTabletProximity", NSTabletProximity },
      { "NSOtherMouseDown", NSOtherMouseDown },
      { "NSOtherMouseUp", NSOtherMouseUp },
      { "NSOtherMouseDragged", NSOtherMouseDragged },
      { "NSEventTypeGesture", NSEventTypeGesture },
      { "NSEventTypeMagnify", NSEventTypeMagnify },
      { "NSEventTypeSwipe", NSEventTypeSwipe },
      { "NSEventTypeRotate", NSEventTypeRotate },
      { "NSEventTypeBeginGesture", NSEventTypeBeginGesture },
      { "NSEventTypeEndGesture", NSEventTypeEndGesture },
      { "NSAlphaShiftKeyMask", NSAlphaShiftKeyMask },
      { "NSShiftKeyMask", NSShiftKeyMask },
      { "NSControlKeyMask", NSControlKeyMask },
      { "NSAlternateKeyMask", NSAlternateKeyMask },
      { "NSCommandKeyMask", NSCommandKeyMask },
      { "NSNumericPadKeyMask", NSNumericPadKeyMask },
      { "NSHelpKeyMask", NSHelpKeyMask },
      { "NSFunctionKeyMask", NSFunctionKeyMask },
      { "NSDeviceIndependentModifierFlagsMask",
          NSDeviceIndependentModifierFlagsMask },
    };

    static BatchedMethods class_methods[] = {
      { "pressedMouseButtons", &NSEventWrapper::class_pressedMouseButtons },
    };

    static BatchedMethods methods[] = {
      { "type", &NSEventWrapper::type },
      { "buttonNumber", &NSEventWrapper::buttonNumber },
      { "characters", &NSEventWrapper::characters },
      { "keyCode", &NSEventWrapper::keyCode },
      { "locationInWindow", &NSEventWrapper::locationInWindow },
      { "deltaX", &NSEventWrapper::deltaX },
      { "deltaY", &NSEventWrapper::deltaY },
      { "deltaZ", &NSEventWrapper::deltaZ },
      { "pressure", &NSEventWrapper::pressure },
      { "isEnteringProximity", &NSEventWrapper::isEnteringProximity },
      { "modifierFlags", &NSEventWrapper::modifierFlags },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      ft->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
              v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
                    v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(class_methods); ++i) {
      ft->Set(v8::String::NewFromUtf8(isolate, class_methods[i].name),
              v8::FunctionTemplate::New(isolate, class_methods[i].func,
                                              v8::Handle<v8::Value>()));
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, methods[i].name),
                    v8::FunctionTemplate::New(isolate, methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

  static NSEvent* ExtractPointer(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<NSEvent*>(obj->GetAlignedPointerFromInternalField(0));
  }

 private:
  static void WeakCallback(
      const v8::WeakCallbackData<v8::Object, v8::Persistent<v8::Object> >& data) {
    NSEvent* event = ExtractPointer(data.GetValue());

    v8::Persistent<v8::Object>* persistent = data.GetParameter();
    persistent->ClearWeak();
    persistent->Reset();
    delete persistent;

    [event release];  // Okay even if event is nil.
  }

  // This will be called when we create a new instance from the instance
  // template, wrapping a NSEvent*.  It can also be called directly from
  // JavaScript, which is a bit of a problem, but we'll survive.
  static void V8New(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    args.This()->SetAlignedPointerInInternalField(0, NULL);

    v8::Persistent<v8::Object>* persistent = new v8::Persistent<v8::Object>;
    persistent->Reset(isolate, args.This());
    persistent->SetWeak(persistent, &NSEventWrapper::WeakCallback);

    args.GetReturnValue().Set(args.This());
  }

  static void class_pressedMouseButtons(
      const v8::FunctionCallbackInfo<v8::Value>& args) {
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, [NSEvent pressedMouseButtons]));
  }

  static void type(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, [event type]));
  }

  static void buttonNumber(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, [event buttonNumber]));
  }

  static void characters(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSEvent* event = ExtractPointer(args.Holder());
    NSString* characters = [event characters];
    return args.GetReturnValue().Set(v8::String::NewFromUtf8(isolate,
        [characters UTF8String],
        v8::String::kNormalString,
        [characters lengthOfBytesUsingEncoding:NSUTF8StringEncoding]));
  }

  static void keyCode(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, [event keyCode]));
  }

  static void locationInWindow(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSEvent* event = ExtractPointer(args.Holder());
    // If window is nil we'll instead get screen coordinates.
    if ([event window] == nil)
      return v8_utils::ThrowError(isolate, "Calling locationInWindow with nil window.");
    NSPoint pos = [event locationInWindow];
    v8::Local<v8::Object> res = v8::Object::New(isolate);
    res->Set(v8::String::NewFromUtf8(isolate, "x"), v8::Number::New(isolate, pos.x));
    res->Set(v8::String::NewFromUtf8(isolate, "y"), v8::Number::New(isolate, pos.y));
    return args.GetReturnValue().Set(res);
  }

  static void deltaX(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [event deltaX]));
  }

  static void deltaY(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [event deltaY]));
  }

  static void deltaZ(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [event deltaZ]));
  }

  static void pressure(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [event pressure]));
  }

  static void isEnteringProximity(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set((bool)[event isEnteringProximity]);
  }

  static void modifierFlags(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, [event modifierFlags]));
  }
};

class SkPathWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &SkPathWrapper::V8New);
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // SkPath pointer.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
      // FillType.
      { "kWindingFillType", SkPath::kWinding_FillType },
      { "kEvenOddFillType", SkPath::kEvenOdd_FillType },
      { "kInverseWindingFillType", SkPath::kInverseWinding_FillType },
      { "kInverseEvenOddFillType", SkPath::kInverseEvenOdd_FillType },
    };

    static BatchedMethods methods[] = {
      { "reset", &SkPathWrapper::reset },
      { "rewind", &SkPathWrapper::rewind },
      { "moveTo", &SkPathWrapper::moveTo },
      { "lineTo", &SkPathWrapper::lineTo },
      { "rLineTo", &SkPathWrapper::rLineTo },
      { "quadTo", &SkPathWrapper::quadTo },
      { "cubicTo", &SkPathWrapper::cubicTo },
      { "arcTo", &SkPathWrapper::arcTo },
      { "arct", &SkPathWrapper::arct },
      { "addRect", &SkPathWrapper::addRect },
      { "addOval", &SkPathWrapper::addOval },
      { "addCircle", &SkPathWrapper::addCircle },
      { "close", &SkPathWrapper::close },
      { "offset", &SkPathWrapper::offset },
      { "getBounds", &SkPathWrapper::getBounds },
      { "toSVGString", &SkPathWrapper::toSVGString },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      ft->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
              v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
                    v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, methods[i].name),
                    v8::FunctionTemplate::New(isolate, methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static SkPath* ExtractPointer(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<SkPath*>(obj->GetAlignedPointerFromInternalField(0));
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

 private:
  static void reset(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());
    path->reset();
    return args.GetReturnValue().SetUndefined();
  }

  static void rewind(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());
    path->rewind();
    return args.GetReturnValue().SetUndefined();
  }

  static void moveTo(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());

    path->moveTo(SkDoubleToScalar(args[0]->NumberValue()),
                 SkDoubleToScalar(args[1]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  static void lineTo(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());

    path->lineTo(SkDoubleToScalar(args[0]->NumberValue()),
                 SkDoubleToScalar(args[1]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  static void rLineTo(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());

    path->rLineTo(SkDoubleToScalar(args[0]->NumberValue()),
                  SkDoubleToScalar(args[1]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  static void quadTo(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());

    path->quadTo(SkDoubleToScalar(args[0]->NumberValue()),
                 SkDoubleToScalar(args[1]->NumberValue()),
                 SkDoubleToScalar(args[2]->NumberValue()),
                 SkDoubleToScalar(args[3]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  static void cubicTo(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());

    path->cubicTo(SkDoubleToScalar(args[0]->NumberValue()),
                  SkDoubleToScalar(args[1]->NumberValue()),
                  SkDoubleToScalar(args[2]->NumberValue()),
                  SkDoubleToScalar(args[3]->NumberValue()),
                  SkDoubleToScalar(args[4]->NumberValue()),
                  SkDoubleToScalar(args[5]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  static void arcTo(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());

    SkRect rect = { SkDoubleToScalar(args[0]->NumberValue()),
                    SkDoubleToScalar(args[1]->NumberValue()),
                    SkDoubleToScalar(args[2]->NumberValue()),
                    SkDoubleToScalar(args[3]->NumberValue()) };
    path->arcTo(rect,
                SkDoubleToScalar(args[4]->NumberValue()),
                SkDoubleToScalar(args[5]->NumberValue()),
                args[6]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  static void arct(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());

    path->arcTo(SkDoubleToScalar(args[0]->NumberValue()),
                SkDoubleToScalar(args[1]->NumberValue()),
                SkDoubleToScalar(args[2]->NumberValue()),
                SkDoubleToScalar(args[3]->NumberValue()),
                SkDoubleToScalar(args[4]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  static void addRect(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());

    path->addRect(SkDoubleToScalar(args[0]->NumberValue()),
                  SkDoubleToScalar(args[1]->NumberValue()),
                  SkDoubleToScalar(args[2]->NumberValue()),
                  SkDoubleToScalar(args[3]->NumberValue()),
                  args[4]->BooleanValue() ? SkPath::kCCW_Direction :
                                            SkPath::kCW_Direction);
    return args.GetReturnValue().SetUndefined();
  }

  static void addOval(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());

    SkRect rect = { SkDoubleToScalar(args[0]->NumberValue()),
                    SkDoubleToScalar(args[1]->NumberValue()),
                    SkDoubleToScalar(args[2]->NumberValue()),
                    SkDoubleToScalar(args[3]->NumberValue()) };
    path->addOval(rect, args[4]->BooleanValue() ? SkPath::kCCW_Direction :
                                                  SkPath::kCW_Direction);
    return args.GetReturnValue().SetUndefined();
  }

  static void addCircle(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());

    path->addCircle(SkDoubleToScalar(args[0]->NumberValue()),
                    SkDoubleToScalar(args[1]->NumberValue()),
                    SkDoubleToScalar(args[2]->NumberValue()),
                    args[3]->BooleanValue() ? SkPath::kCCW_Direction :
                                              SkPath::kCW_Direction);
    return args.GetReturnValue().SetUndefined();
  }

  static void close(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());
    path->close();
    return args.GetReturnValue().SetUndefined();
  }

  static void offset(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());
    path->offset(SkDoubleToScalar(args[0]->NumberValue()),
                 SkDoubleToScalar(args[1]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  static void getBounds(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());
    SkRect bounds = path->getBounds();
    v8::Local<v8::Array> res = v8::Array::New(isolate, 4);
    res->Set(v8::Integer::New(isolate, 0), v8::Number::New(isolate, bounds.fLeft));
    res->Set(v8::Integer::New(isolate, 1), v8::Number::New(isolate, bounds.fTop));
    res->Set(v8::Integer::New(isolate, 2), v8::Number::New(isolate, bounds.fRight));
    res->Set(v8::Integer::New(isolate, 3), v8::Number::New(isolate, bounds.fBottom));
    return args.GetReturnValue().Set(res);
  }

  static void toSVGString(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());
    SkString str;
    SkParsePath::ToSVGString(*path, &str);
    return args.GetReturnValue().Set(v8::String::NewFromUtf8(
        isolate, str.c_str(), v8::String::kNormalString, str.size()));
  }

  static void V8New(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    SkPath* prev_path = NULL;
    if (SkPathWrapper::HasInstance(isolate, args[0])) {
      prev_path = SkPathWrapper::ExtractPointer(
          v8::Handle<v8::Object>::Cast(args[0]));
    }

    SkPath* path = prev_path ? new SkPath(*prev_path) : new SkPath;
    args.This()->SetAlignedPointerInInternalField(0, path);
  }
};


class SkPaintWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &SkPaintWrapper::V8New);
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // SkPaint pointer.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
      // Flags.
      { "kAntiAliasFlag", SkPaint::kAntiAlias_Flag },
      { "kDitherFlag", SkPaint::kDither_Flag },
      { "kUnderlineTextFlag", SkPaint::kUnderlineText_Flag },
      { "kStrikeThruTextFlag", SkPaint::kStrikeThruText_Flag },
      { "kFakeBoldTextFlag", SkPaint::kFakeBoldText_Flag },
      { "kLinearTextFlag", SkPaint::kLinearText_Flag },
      { "kSubpixelTextFlag", SkPaint::kSubpixelText_Flag },
      { "kDevKernTextFlag", SkPaint::kDevKernText_Flag },
      { "kAllFlags", SkPaint::kAllFlags },
      // Style.
      { "kFillStyle", SkPaint::kFill_Style },
      { "kStrokeStyle", SkPaint::kStroke_Style },
      { "kStrokeAndFillStyle", SkPaint::kStrokeAndFill_Style },
      // Port duff modes SkXfermode::Mode.
      { "kClearMode", SkXfermode::kClear_Mode },
      { "kSrcMode", SkXfermode::kSrc_Mode },
      { "kDstMode", SkXfermode::kDst_Mode },
      { "kSrcOverMode", SkXfermode::kSrcOver_Mode },
      { "kDstOverMode", SkXfermode::kDstOver_Mode },
      { "kSrcInMode", SkXfermode::kSrcIn_Mode },
      { "kDstInMode", SkXfermode::kDstIn_Mode },
      { "kSrcOutMode", SkXfermode::kSrcOut_Mode },
      { "kDstOutMode", SkXfermode::kDstOut_Mode },
      { "kSrcATopMode", SkXfermode::kSrcATop_Mode },
      { "kDstATopMode", SkXfermode::kDstATop_Mode },
      { "kXorMode", SkXfermode::kXor_Mode },
      { "kPlusMode", SkXfermode::kPlus_Mode },
      { "kMultiplyMode", SkXfermode::kMultiply_Mode },
      { "kScreenMode", SkXfermode::kScreen_Mode },
      { "kOverlayMode", SkXfermode::kOverlay_Mode },
      { "kDarkenMode", SkXfermode::kDarken_Mode },
      { "kLightenMode", SkXfermode::kLighten_Mode },
      { "kColorDodgeMode", SkXfermode::kColorDodge_Mode },
      { "kColorBurnMode", SkXfermode::kColorBurn_Mode },
      { "kHardLightMode", SkXfermode::kHardLight_Mode },
      { "kSoftLightMode", SkXfermode::kSoftLight_Mode },
      { "kDifferenceMode", SkXfermode::kDifference_Mode },
      { "kExclusionMode", SkXfermode::kExclusion_Mode },
      // Cap
      { "kButtCap", SkPaint::kButt_Cap },
      { "kRoundCap", SkPaint::kRound_Cap },
      { "kSquareCap", SkPaint::kSquare_Cap },
      { "kDefaultCap", SkPaint::kDefault_Cap },
      // Join
      { "kMiterJoin", SkPaint::kMiter_Join },
      { "kRoundJoin", SkPaint::kRound_Join },
      { "kBevelJoin", SkPaint::kBevel_Join },
      { "kDefaultJoin", SkPaint::kDefault_Join },
    };

    static BatchedMethods methods[] = {
      { "reset", &SkPaintWrapper::reset },
      { "getFlags", &SkPaintWrapper::getFlags },
      { "setFlags", &SkPaintWrapper::setFlags },
      { "setAntiAlias", &SkPaintWrapper::setAntiAlias },
      { "setDither", &SkPaintWrapper::setDither },
      { "setUnderlineText", &SkPaintWrapper::setUnderlineText },
      { "setStrikeThruText", &SkPaintWrapper::setStrikeThruText },
      { "setFakeBoldText", &SkPaintWrapper::setFakeBoldText },
      { "setSubpixelText", &SkPaintWrapper::setSubpixelText },
      { "setDevKernText", &SkPaintWrapper::setDevKernText },
      { "setLCDRenderText", &SkPaintWrapper::setLCDRenderText },
      { "setAutohinted", &SkPaintWrapper::setAutohinted },
      { "setStrokeWidth", &SkPaintWrapper::setStrokeWidth },
      { "getStyle", &SkPaintWrapper::getStyle },
      { "setStyle", &SkPaintWrapper::setStyle },
      { "setFill", &SkPaintWrapper::setFill },
      { "setStroke", &SkPaintWrapper::setStroke },
      { "setFillAndStroke", &SkPaintWrapper::setFillAndStroke },
      { "getStrokeCap", &SkPaintWrapper::getStrokeCap },
      { "setStrokeCap", &SkPaintWrapper::setStrokeCap },
      { "getStrokeJoin", &SkPaintWrapper::getStrokeJoin },
      { "setStrokeJoin", &SkPaintWrapper::setStrokeJoin },
      { "getStrokeMiter", &SkPaintWrapper::getStrokeMiter },
      { "setStrokeMiter", &SkPaintWrapper::setStrokeMiter },
      { "getFillPath", &SkPaintWrapper::getFillPath },
      { "setColor", &SkPaintWrapper::setColor },
      { "setColorHSV", &SkPaintWrapper::setColorHSV },
      { "setTextSize", &SkPaintWrapper::setTextSize },
      { "setXfermodeMode", &SkPaintWrapper::setXfermodeMode },
      { "setFontFamily", &SkPaintWrapper::setFontFamily },
      { "setFontFamilyPostScript", &SkPaintWrapper::setFontFamilyPostScript },
      { "setLinearGradientShader", &SkPaintWrapper::setLinearGradientShader },
      { "setRadialGradientShader", &SkPaintWrapper::setRadialGradientShader },
      { "clearShader", &SkPaintWrapper::clearShader },
      { "setDashPathEffect", &SkPaintWrapper::setDashPathEffect },
      { "clearPathEffect", &SkPaintWrapper::clearPathEffect },
      { "measureText", &SkPaintWrapper::measureText },
      { "measureTextBounds", &SkPaintWrapper::measureTextBounds },
      { "getFontMetrics", &SkPaintWrapper::getFontMetrics },
      { "getTextPath", &SkPaintWrapper::getTextPath }
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      ft->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
              v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
                    v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, methods[i].name),
                    v8::FunctionTemplate::New(isolate, methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static SkPaint* ExtractPointer(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<SkPaint*>(obj->GetAlignedPointerFromInternalField(0));
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

 private:
  static void reset(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->reset();
    return args.GetReturnValue().SetUndefined();
  }

  static void getFlags(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Uint32::New(isolate, paint->getFlags()));
  }

  static void setFlags(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setFlags(v8_utils::ToInt32(args[0]));
    return args.GetReturnValue().SetUndefined();
  }

  static void setAntiAlias(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setAntiAlias(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  static void setDither(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setDither(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  static void setUnderlineText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setUnderlineText(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  static void setStrikeThruText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setStrikeThruText(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  static void setFakeBoldText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setFakeBoldText(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  static void setSubpixelText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setSubpixelText(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  static void setDevKernText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setDevKernText(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  static void setLCDRenderText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setLCDRenderText(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  static void setAutohinted(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setAutohinted(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  static void getStrokeWidth(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, SkScalarToDouble(paint->getStrokeWidth())));
  }

  static void setStrokeWidth(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setStrokeWidth(SkDoubleToScalar(args[0]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  static void getStyle(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Uint32::New(isolate, paint->getStyle()));
  }

  static void setStyle(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setStyle(static_cast<SkPaint::Style>(v8_utils::ToInt32(args[0])));
    return args.GetReturnValue().SetUndefined();
  }

  static void setFill(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setStyle(SkPaint::kFill_Style);
    return args.GetReturnValue().SetUndefined();
  }

  static void setStroke(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setStyle(SkPaint::kStroke_Style);
    return args.GetReturnValue().SetUndefined();
  }

  static void setFillAndStroke(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    // We flip the name around because it makes more sense, generally you think
    // of the stroke happening after the fill.
    paint->setStyle(SkPaint::kStrokeAndFill_Style);
    return args.GetReturnValue().SetUndefined();
  }

  static void getStrokeCap(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Uint32::New(isolate, paint->getStrokeCap()));
  }

  static void setStrokeCap(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setStrokeCap(static_cast<SkPaint::Cap>(v8_utils::ToInt32(args[0])));
    return args.GetReturnValue().SetUndefined();
  }

  static void getStrokeJoin(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Uint32::New(isolate, paint->getStrokeJoin()));
  }

  static void setStrokeJoin(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setStrokeJoin(static_cast<SkPaint::Join>(v8_utils::ToInt32(args[0])));
    return args.GetReturnValue().SetUndefined();
  }

  static void getStrokeMiter(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, SkScalarToDouble(paint->getStrokeMiter())));
  }

  static void setStrokeMiter(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setStrokeMiter(SkDoubleToScalar(args[0]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  static void getFillPath(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());

    if (!SkPathWrapper::HasInstance(isolate, args[0]))
      return args.GetReturnValue().SetUndefined();

    if (!SkPathWrapper::HasInstance(isolate, args[1]))
      return args.GetReturnValue().SetUndefined();

    SkPath* src = SkPathWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));
    SkPath* dst = SkPathWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[1]));

    return args.GetReturnValue().Set((bool)paint->getFillPath(*src, dst));
  }

  // We wrap it as 4 params instead of 1 to try to keep things as SMIs.
  static void setColor(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());

    int r = Clamp(v8_utils::ToInt32WithDefault(args[0], 0), 0, 255);
    int g = Clamp(v8_utils::ToInt32WithDefault(args[1], 0), 0, 255);
    int b = Clamp(v8_utils::ToInt32WithDefault(args[2], 0), 0, 255);
    int a = Clamp(v8_utils::ToInt32WithDefault(args[3], 255), 0, 255);

    paint->setColor(SkColorSetARGB(a, r, g, b));
    return args.GetReturnValue().SetUndefined();
  }

  static void setColorHSV(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());

    // TODO(deanm): Clamp.
    SkScalar hsv[] = { SkDoubleToScalar(args[0]->NumberValue()),
                       SkDoubleToScalar(args[1]->NumberValue()),
                       SkDoubleToScalar(args[2]->NumberValue()) };
    int a = Clamp(v8_utils::ToInt32WithDefault(args[3], 255), 0, 255);

    paint->setColor(SkHSVToColor(a, hsv));
    return args.GetReturnValue().SetUndefined();
  }

  static void setTextSize(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());

    paint->setTextSize(SkDoubleToScalar(args[0]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  static void setXfermodeMode(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());

    // TODO(deanm): Memory management.
    paint->setXfermodeMode(
          static_cast<SkXfermode::Mode>(v8_utils::ToInt32(args[0])));
    return args.GetReturnValue().SetUndefined();
  }

  static void setFontFamily(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (args.Length() < 1)
      return v8_utils::ThrowError(isolate, "Wrong number of arguments.");

    SkPaint* paint = ExtractPointer(args.Holder());
    v8::String::Utf8Value family_name(args[0]);
    paint->setTypeface(SkTypeface::CreateFromName(
        *family_name, static_cast<SkTypeface::Style>(args[1]->Uint32Value())));
    return args.GetReturnValue().SetUndefined();
  }

   DEFINE_METHOD(setFontFamilyPostScript, 1)
    SkPaint* paint = ExtractPointer(args.Holder());
    v8::String::Utf8Value postscript_name(args[0]);

    CFStringRef cfFontName = CFStringCreateWithCString(
        NULL, *postscript_name, kCFStringEncodingUTF8);
    if (cfFontName == NULL)
      return v8_utils::ThrowError(isolate, "Unable to create font CFString.");

    CTFontRef ctNamed = CTFontCreateWithName(cfFontName, 1, NULL);
    CFRelease(cfFontName);
    if (ctNamed == NULL)
      return v8_utils::ThrowError(isolate, "Unable to create CTFont.");

    SkTypeface* typeface = SkCreateTypefaceFromCTFont(ctNamed);
    paint->setTypeface(typeface);
    typeface->unref();  // setTypeface will have held a ref.
    CFRelease(ctNamed);  // SkCreateTypefaceFromCTFont will have held a ref.
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(setLinearGradientShader, 5)
    SkPaint* paint = ExtractPointer(args.Holder());

    SkPoint points[2] = {{SkDoubleToScalar(args[0]->NumberValue()),
                          SkDoubleToScalar(args[1]->NumberValue())},
                         {SkDoubleToScalar(args[2]->NumberValue()),
                          SkDoubleToScalar(args[3]->NumberValue())}};

    SkColor* colors = NULL;
    SkScalar* positions = NULL;
    uint32_t num = 0;

    if (args[4]->IsArray()) {
      v8::Handle<v8::Array> data = v8::Handle<v8::Array>::Cast(args[4]);
      uint32_t data_len = data->Length();
      num = data_len / 5;

      colors = new SkColor[num];
      positions = new SkScalar[num];

      for (uint32_t i = 0, j = 0; i < data_len; i += 5, ++j) {
        positions[j] = SkDoubleToScalar(data->Get(i)->NumberValue());
        colors[j] = SkColorSetARGB(data->Get(i+4)->Uint32Value() & 0xff,
                                   data->Get(i+1)->Uint32Value() & 0xff,
                                   data->Get(i+2)->Uint32Value() & 0xff,
                                   data->Get(i+3)->Uint32Value() & 0xff);
      }
    }

    // TODO(deanm): Tile mode.
    SkShader* s = SkGradientShader::CreateLinear(points, colors, positions, num,
                                                 SkShader::kClamp_TileMode);
    paint->setShader(s);

    delete[] colors;
    delete[] positions;

    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(setRadialGradientShader, 4)
    SkPaint* paint = ExtractPointer(args.Holder());

    SkPoint center = {SkDoubleToScalar(args[0]->NumberValue()),
                      SkDoubleToScalar(args[1]->NumberValue())};
    SkScalar radius = SkDoubleToScalar(args[2]->NumberValue());

    SkColor* colors = NULL;
    SkScalar* positions = NULL;
    uint32_t num = 0;

    if (args[3]->IsArray()) {
      v8::Handle<v8::Array> data = v8::Handle<v8::Array>::Cast(args[3]);
      uint32_t data_len = data->Length();
      num = data_len / 5;

      colors = new SkColor[num];
      positions = new SkScalar[num];

      for (uint32_t i = 0, j = 0; i < data_len; i += 5, ++j) {
        positions[j] = SkDoubleToScalar(data->Get(i)->NumberValue());
        colors[j] = SkColorSetARGB(data->Get(i+4)->Uint32Value() & 0xff,
                                   data->Get(i+1)->Uint32Value() & 0xff,
                                   data->Get(i+2)->Uint32Value() & 0xff,
                                   data->Get(i+3)->Uint32Value() & 0xff);
      }
    }

    // TODO(deanm): Tile mode.
    SkShader* s = SkGradientShader::CreateRadial(center, radius,
                                                 colors, positions, num,
                                                 SkShader::kClamp_TileMode);
    paint->setShader(s);

    delete[] colors;
    delete[] positions;

    return args.GetReturnValue().SetUndefined();
  }

  static void clearShader(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setShader(NULL);
    return args.GetReturnValue().SetUndefined();
  }


  static void setDashPathEffect(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args[0]->IsArray())
      return v8_utils::ThrowError(isolate, "Sequence must be an Array.");

    v8::Local<v8::Array> arr = v8::Local<v8::Array>::Cast(args[0]);
    uint32_t length = arr->Length();

    if (length & 1)
      return v8_utils::ThrowError(isolate, "Sequence must be even.");

    SkScalar* intervals = new SkScalar[length];
    if (!intervals)
      return v8_utils::ThrowError(isolate, "Unable to allocate intervals.");

    for (uint32_t i = 0; i < length; ++i) {
      intervals[i] = SkDoubleToScalar(arr->Get(i)->NumberValue());
    }

    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setPathEffect(SkDashPathEffect::Create(
        intervals, length,
        SkDoubleToScalar(args[1]->IsUndefined() ? 0.0 : args[1]->NumberValue())));
    delete[] intervals;
    return args.GetReturnValue().SetUndefined();
  }

  static void clearPathEffect(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setPathEffect(NULL);
    return args.GetReturnValue().SetUndefined();
  }

  static void measureText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());

    v8::String::Utf8Value utf8(args[0]);
    SkScalar width = paint->measureText(*utf8, utf8.length());
    return args.GetReturnValue().Set(v8::Number::New(isolate, width));
  }

  static void measureTextBounds(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());

    v8::String::Utf8Value utf8(args[0]);

    SkRect bounds = SkRect::MakeEmpty();
    paint->measureText(*utf8, utf8.length(), &bounds);

    v8::Local<v8::Array> res = v8::Array::New(isolate, 4);
    res->Set(v8::Integer::New(isolate, 0), v8::Number::New(isolate, bounds.fLeft));
    res->Set(v8::Integer::New(isolate, 1), v8::Number::New(isolate, bounds.fTop));
    res->Set(v8::Integer::New(isolate, 2), v8::Number::New(isolate, bounds.fRight));
    res->Set(v8::Integer::New(isolate, 3), v8::Number::New(isolate, bounds.fBottom));

    return args.GetReturnValue().Set(res);
  }

  static void getFontMetrics(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());

    SkPaint::FontMetrics metrics;

    paint->getFontMetrics(&metrics);

    v8::Local<v8::Object> res = v8::Object::New(isolate);

    //!< The greatest distance above the baseline for any glyph (will be <= 0)
    res->Set(v8::String::NewFromUtf8(isolate, "top"), v8::Number::New(isolate, metrics.fTop));
    //!< The recommended distance above the baseline (will be <= 0)
    res->Set(v8::String::NewFromUtf8(isolate, "ascent"), v8::Number::New(isolate, metrics.fAscent));
    //!< The recommended distance below the baseline (will be >= 0)
    res->Set(v8::String::NewFromUtf8(isolate, "descent"), v8::Number::New(isolate, metrics.fDescent));
    //!< The greatest distance below the baseline for any glyph (will be >= 0)
    res->Set(v8::String::NewFromUtf8(isolate, "bottom"), v8::Number::New(isolate, metrics.fBottom));
    //!< The recommended distance to add between lines of text (will be >= 0)
    res->Set(v8::String::NewFromUtf8(isolate, "leading"), v8::Number::New(isolate, metrics.fLeading));
    //!< the average charactor width (>= 0)
    res->Set(v8::String::NewFromUtf8(isolate, "avgcharwidth"),
             v8::Number::New(isolate, metrics.fAvgCharWidth));
    //!< The minimum bounding box x value for all glyphs
    res->Set(v8::String::NewFromUtf8(isolate, "xmin"), v8::Number::New(isolate, metrics.fXMin));
    //!< The maximum bounding box x value for all glyphs
    res->Set(v8::String::NewFromUtf8(isolate, "xmax"), v8::Number::New(isolate, metrics.fXMax));
    //!< the height of an 'x' in px, or 0 if no 'x' in face
    res->Set(v8::String::NewFromUtf8(isolate, "xheight"), v8::Number::New(isolate, metrics.fXHeight));

    return args.GetReturnValue().Set(res);
  }

  static void getTextPath(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());

    if (!SkPathWrapper::HasInstance(isolate, args[3]))
      return v8_utils::ThrowTypeError(isolate, "4th argument must be an SkPath.");

    SkPath* path = SkPathWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[3]));

    v8::String::Utf8Value utf8(args[0]);

    double x = SkDoubleToScalar(args[1]->NumberValue());
    double y = SkDoubleToScalar(args[2]->NumberValue());

    paint->getTextPath(*utf8, utf8.length(), x, y, path);
    return args.GetReturnValue().SetUndefined();
  }

  static void V8New(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    SkPaint* paint = NULL;
    if (SkPaintWrapper::HasInstance(isolate, args[0])) {
      paint = new SkPaint(*SkPaintWrapper::ExtractPointer(
          v8::Handle<v8::Object>::Cast(args[0])));
    } else {
      paint = new SkPaint;
      paint->setTypeface(SkTypeface::CreateFromName("Arial",
                                                    SkTypeface::kNormal));
      // Skia defaults to a stroke width of 0, which is a Skia specific
      // hair-line implementation.  It is most familiar to default to 1.
      paint->setStrokeWidth(1);
    }
    args.This()->SetAlignedPointerInInternalField(0, paint);
  }
};


class SkCanvasWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &SkCanvasWrapper::V8New);
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // SkCanvas pointers.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
      // PointMode.
      { "kPointsPointMode", SkCanvas::kPoints_PointMode },
      { "kLinesPointMode", SkCanvas::kLines_PointMode },
      { "kPolygonPointMode", SkCanvas::kPolygon_PointMode },
    };

    static BatchedMethods methods[] = {
      { "clipRect", &SkCanvasWrapper::clipRect },
      { "clipPath", &SkCanvasWrapper::clipPath },
      { "drawCircle", &SkCanvasWrapper::drawCircle },
      { "drawLine", &SkCanvasWrapper::drawLine },
      { "drawPaint", &SkCanvasWrapper::drawPaint },
      { "drawCanvas", &SkCanvasWrapper::drawCanvas },
      { "drawColor", &SkCanvasWrapper::drawColor },
      { "eraseColor", &SkCanvasWrapper::eraseColor },
      { "clear", &SkCanvasWrapper::eraseColor },
      { "drawPath", &SkCanvasWrapper::drawPath },
      { "drawPoints", &SkCanvasWrapper::drawPoints },
      { "drawRect", &SkCanvasWrapper::drawRect },
      { "drawRoundRect", &SkCanvasWrapper::drawRoundRect },
      { "drawText", &SkCanvasWrapper::drawText },
      { "drawTextOnPathHV", &SkCanvasWrapper::drawTextOnPathHV },
      { "concatMatrix", &SkCanvasWrapper::concatMatrix },
      { "setMatrix", &SkCanvasWrapper::setMatrix },
      { "resetMatrix", &SkCanvasWrapper::resetMatrix },
      { "translate", &SkCanvasWrapper::translate },
      { "scale", &SkCanvasWrapper::scale },
      { "rotate", &SkCanvasWrapper::rotate },
      { "skew", &SkCanvasWrapper::skew },
      { "save", &SkCanvasWrapper::save },
      { "restore", &SkCanvasWrapper::restore },
      { "writeImage", &SkCanvasWrapper::writeImage },
      { "writePDF", &SkCanvasWrapper::writePDF },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      ft->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
              v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
                    v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, methods[i].name),
                    v8::FunctionTemplate::New(isolate, methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static SkCanvas* ExtractPointer(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<SkCanvas*>(obj->GetAlignedPointerFromInternalField(0));
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

 private:
  static void WeakCallback(
      const v8::WeakCallbackData<v8::Object, v8::Persistent<v8::Object> >& data) {
    v8::Isolate* isolate = data.GetIsolate();
    SkCanvas* canvas = ExtractPointer(data.GetValue());

    SkImageInfo info = canvas->imageInfo();
    int size_bytes = info.width() * info.height() * info.bytesPerPixel();
    isolate->AdjustAmountOfExternalAllocatedMemory(-size_bytes);

    v8::Persistent<v8::Object>* persistent = data.GetParameter();
    persistent->ClearWeak();
    persistent->Reset();
    delete persistent;

    // Delete the backing SkCanvas object.  Skia reference counting should
    // handle cleaning up deeper resources (for example the backing pixels).
    delete canvas;
  }

  static void V8New(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    // We have a level of indirection (tbitmap vs bitmap) so that we don't need
    // to copy and create a new SkBitmap in the case it already exists (for
    // example for an NSWindow which has already has an SkBitmap).  This is
    // important since a copy of an SkBitmap will have a NULL pixel pointer.
    SkBitmap tbitmap;
    SkBitmap* bitmap = &tbitmap;

    SkCanvas* canvas;
    if (args[0]->StrictEquals(v8::String::NewFromUtf8(isolate, "%PDF"))) {  // PDF constructor.
      SkMatrix initial_matrix;
      initial_matrix.reset();
      SkISize page_size =
          SkISize::Make(args[1]->Int32Value(), args[2]->Int32Value());
      SkISize content_size =
          SkISize::Make(args[3]->Int32Value(), args[4]->Int32Value());
      SkPDFDevice* pdf_device = new SkPDFDevice(
          page_size, content_size, initial_matrix);
      canvas = new SkCanvas(pdf_device);
      // Bit of a hack to get the width and height properties set.
      tbitmap.setInfo(SkImageInfo::Make(
        pdf_device->width(), pdf_device->height(),
        kUnknown_SkColorType, kIgnore_SkAlphaType));
    } else if (args[0]->StrictEquals(v8::String::NewFromUtf8(isolate, "^IMG"))) {
      // Load an image, either a path to a file on disk, or a TypedArray or
      // other external array data backed JS object.
      // TODO(deanm): This is all super inefficent, we copy / flip / etc.

      FIBITMAP* fbitmap = NULL;

      if (args[1]->IsString()) {  // Path on disk.
        v8::String::Utf8Value filename(args[1]);

        FREE_IMAGE_FORMAT format = FreeImage_GetFileType(*filename, 0);
        // Some formats don't have a signature so we're supposed to guess from
        // the extension.
        if (format == FIF_UNKNOWN)
          format = FreeImage_GetFIFFromFilename(*filename);

        if (format == FIF_UNKNOWN || !FreeImage_FIFSupportsReading(format))
          return v8_utils::ThrowError(isolate, "Couldn't detect image type.");

        fbitmap = FreeImage_Load(format, *filename, 0);
        if (!fbitmap)
          return v8_utils::ThrowError(isolate, "Couldn't load image.");
      } else if (args[1]->IsObject()) {
        v8::Local<v8::Object> data = v8::Local<v8::Object>::Cast(args[1]);
        if (!data->HasIndexedPropertiesInExternalArrayData())
          return v8_utils::ThrowError(isolate, "Data must be an ExternalArrayData.");
        int element_size = SizeOfArrayElementForType(
            data->GetIndexedPropertiesExternalArrayDataType());
        // FreeImage's annoying Windows types...
        DWORD size = data->GetIndexedPropertiesExternalArrayDataLength() *
            element_size;
        BYTE* datadata = reinterpret_cast<BYTE*>(
            data->GetIndexedPropertiesExternalArrayData());

        FIMEMORY* mem = FreeImage_OpenMemory(datadata, size);
        FREE_IMAGE_FORMAT format = FreeImage_GetFileTypeFromMemory(mem, 0);
        if (format == FIF_UNKNOWN || !FreeImage_FIFSupportsReading(format))
          return v8_utils::ThrowError(isolate, "Couldn't detect image type.");

        fbitmap = FreeImage_LoadFromMemory(format, mem, 0);
        FreeImage_CloseMemory(mem);
        if (!fbitmap)
          return v8_utils::ThrowError(isolate, "Couldn't load image.");
      } else {
        return v8_utils::ThrowError(isolate, "SkCanvas image not path or data.");
      }

      if (FreeImage_GetBPP(fbitmap) != 32) {
        FIBITMAP* old_bitmap = fbitmap;
        fbitmap = FreeImage_ConvertTo32Bits(old_bitmap);
        FreeImage_Unload(old_bitmap);
        if (!fbitmap)
          return v8_utils::ThrowError(isolate, "Couldn't convert image to 32-bit.");
      }

      // Skia works in premultplied alpha, so divide RGB by A.
      // TODO(deanm): Should cache whether it used to have alpha before
      // converting it to 32bpp which now has alpha.
      if (!FreeImage_PreMultiplyWithAlpha(fbitmap))
        return v8_utils::ThrowError(isolate, "Couldn't premultiply image.");

      tbitmap.allocPixels(SkImageInfo::Make(
          FreeImage_GetWidth(fbitmap),
          FreeImage_GetHeight(fbitmap),
          kBGRA_8888_SkColorType,
          kPremul_SkAlphaType), FreeImage_GetWidth(fbitmap) * 4);

      // Despite taking red/blue/green masks, FreeImage_CovertToRawBits doesn't
      // actually use them and swizzle the color ordering.  We just require
      // that FreeImage and Skia are compiled with the same color ordering
      // (BGRA).  The masks are ignored for 32 bpp bitmaps so we just pass 0.
      // And of course FreeImage coordinates are upside down, so flip it.
      FreeImage_ConvertToRawBits(reinterpret_cast<BYTE*>(tbitmap.getPixels()),
                                 fbitmap, tbitmap.rowBytes(),
                                 32, 0, 0, 0, TRUE);
      FreeImage_Unload(fbitmap);

      canvas = new SkCanvas(tbitmap);
    } else if (args.Length() == 2) {  // width / height offscreen constructor.
      unsigned int width = args[0]->Uint32Value();
      unsigned int height = args[1]->Uint32Value();
      tbitmap.allocPixels(SkImageInfo::Make(
          width, height,
          kBGRA_8888_SkColorType,
          kPremul_SkAlphaType), width * 4);
      tbitmap.eraseARGB(0, 0, 0, 0);
      canvas = new SkCanvas(tbitmap);
    } else if (args.Length() == 1 && SkCanvasWrapper::HasInstance(isolate, args[0])) {
      SkCanvas* pcanvas = ExtractPointer(v8::Handle<v8::Object>::Cast(args[0]));
      // Allocate a new block of pixels with a copy from pbitmap.
      if (!pcanvas->readPixels(&tbitmap, 0, 0)) abort();
      canvas = new SkCanvas(tbitmap);
    } else {
      return v8_utils::ThrowError(isolate, "Improper SkCanvas constructor arguments.");
    }

    args.This()->SetAlignedPointerInInternalField(0, canvas);
    // Direct pixel access via array[] indexing.
    args.This()->SetIndexedPropertiesToPixelData(
        reinterpret_cast<uint8_t*>(bitmap->getPixels()), bitmap->getSize());
    args.This()->Set(v8::String::NewFromUtf8(isolate, "width"),
                     v8::Integer::NewFromUnsigned(isolate, bitmap->width()));
    args.This()->Set(v8::String::NewFromUtf8(isolate, "height"),
                     v8::Integer::NewFromUnsigned(isolate, bitmap->height()));

    // Notify the GC that we have a possibly large amount of data allocated
    // behind this object.  This is sometimes a bit of a lie, for example for
    // a PDF surface or an NSWindow surface.  Anyway, it's just a heuristic.
    int size_bytes = bitmap->width() * bitmap->height() * 4;
    isolate->AdjustAmountOfExternalAllocatedMemory(size_bytes);

    v8::Persistent<v8::Object>* persistent = new v8::Persistent<v8::Object>;
    persistent->Reset(isolate, args.This());
    persistent->SetWeak(persistent, &SkCanvasWrapper::WeakCallback);
  }

  static void concatMatrix(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    SkMatrix matrix;
    matrix.setAll(SkDoubleToScalar(args[0]->NumberValue()),
                  SkDoubleToScalar(args[1]->NumberValue()),
                  SkDoubleToScalar(args[2]->NumberValue()),
                  SkDoubleToScalar(args[3]->NumberValue()),
                  SkDoubleToScalar(args[4]->NumberValue()),
                  SkDoubleToScalar(args[5]->NumberValue()),
                  SkDoubleToScalar(args[6]->NumberValue()),
                  SkDoubleToScalar(args[7]->NumberValue()),
                  SkDoubleToScalar(args[8]->NumberValue()));
    canvas->concat(matrix);
    return args.GetReturnValue().Set(true);
  }

  static void setMatrix(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    SkMatrix matrix;
    matrix.setAll(SkDoubleToScalar(args[0]->NumberValue()),
                  SkDoubleToScalar(args[1]->NumberValue()),
                  SkDoubleToScalar(args[2]->NumberValue()),
                  SkDoubleToScalar(args[3]->NumberValue()),
                  SkDoubleToScalar(args[4]->NumberValue()),
                  SkDoubleToScalar(args[5]->NumberValue()),
                  SkDoubleToScalar(args[6]->NumberValue()),
                  SkDoubleToScalar(args[7]->NumberValue()),
                  SkDoubleToScalar(args[8]->NumberValue()));
    canvas->setMatrix(matrix);
    return args.GetReturnValue().SetUndefined();
  }

  static void resetMatrix(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->resetMatrix();
    return args.GetReturnValue().SetUndefined();
  }

  static void clipRect(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());

    SkRect rect = { SkDoubleToScalar(args[0]->NumberValue()),
                    SkDoubleToScalar(args[1]->NumberValue()),
                    SkDoubleToScalar(args[2]->NumberValue()),
                    SkDoubleToScalar(args[3]->NumberValue()) };
    canvas->clipRect(rect);
    return args.GetReturnValue().SetUndefined();
  }

  static void clipPath(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());

    if (!SkPathWrapper::HasInstance(isolate, args[0]))
      return args.GetReturnValue().SetUndefined();

    SkPath* path = SkPathWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    canvas->clipPath(*path);  // TODO(deanm): Handle the optional argument.
    return args.GetReturnValue().SetUndefined();
  }

  static void drawCircle(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(isolate, args[0]))
      return args.GetReturnValue().SetUndefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    canvas->drawCircle(SkDoubleToScalar(args[1]->NumberValue()),
                       SkDoubleToScalar(args[2]->NumberValue()),
                       SkDoubleToScalar(args[3]->NumberValue()),
                       *paint);
    return args.GetReturnValue().SetUndefined();
  }

  static void drawLine(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(isolate, args[0]))
      return args.GetReturnValue().SetUndefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    canvas->drawLine(SkDoubleToScalar(args[1]->NumberValue()),
                     SkDoubleToScalar(args[2]->NumberValue()),
                     SkDoubleToScalar(args[3]->NumberValue()),
                     SkDoubleToScalar(args[4]->NumberValue()),
                     *paint);
    return args.GetReturnValue().SetUndefined();
  }

  static void drawPaint(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(isolate, args[0]))
      return args.GetReturnValue().SetUndefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    canvas->drawPaint(*paint);
    return args.GetReturnValue().SetUndefined();
  }

  static void drawCanvas(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (args.Length() < 6)
      return v8_utils::ThrowError(isolate, "Wrong number of arguments.");

    if (!SkCanvasWrapper::HasInstance(isolate, args[1]))
      return v8_utils::ThrowError(isolate, "Bad arguments.");

    SkCanvas* canvas = ExtractPointer(args.Holder());
    SkPaint* paint = NULL;
    if (SkPaintWrapper::HasInstance(isolate, args[0])) {
      paint = SkPaintWrapper::ExtractPointer(
          v8::Handle<v8::Object>::Cast(args[0]));
    }

    SkCanvas* src_canvas = SkCanvasWrapper::ExtractPointer(
          v8::Handle<v8::Object>::Cast(args[1]));
    SkBaseDevice* src_device = src_canvas->getDevice();

    SkRect dst_rect = { SkDoubleToScalar(args[2]->NumberValue()),
                        SkDoubleToScalar(args[3]->NumberValue()),
                        SkDoubleToScalar(args[4]->NumberValue()),
                        SkDoubleToScalar(args[5]->NumberValue()) };

    int srcx1 = v8_utils::ToInt32WithDefault(args[6], 0);
    int srcy1 = v8_utils::ToInt32WithDefault(args[7], 0);
    int srcx2 = v8_utils::ToInt32WithDefault(args[8],
                                             srcx1 + src_device->width());
    int srcy2 = v8_utils::ToInt32WithDefault(args[9],
                                             srcy1 + src_device->height());
    SkIRect src_rect = { srcx1, srcy1, srcx2, srcy2 };

    canvas->drawBitmapRect(src_device->accessBitmap(false),
                           &src_rect, dst_rect, paint);
    return args.GetReturnValue().SetUndefined();
  }

  static void drawColor(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());

    int r = Clamp(v8_utils::ToInt32WithDefault(args[0], 0), 0, 255);
    int g = Clamp(v8_utils::ToInt32WithDefault(args[1], 0), 0, 255);
    int b = Clamp(v8_utils::ToInt32WithDefault(args[2], 0), 0, 255);
    int a = Clamp(v8_utils::ToInt32WithDefault(args[3], 255), 0, 255);
    int m = v8_utils::ToInt32WithDefault(args[4], SkXfermode::kSrcOver_Mode);

    canvas->drawARGB(a, r, g, b, static_cast<SkXfermode::Mode>(m));
    return args.GetReturnValue().SetUndefined();
  }

  static void eraseColor(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());

    int r = Clamp(v8_utils::ToInt32WithDefault(args[0], 0), 0, 255);
    int g = Clamp(v8_utils::ToInt32WithDefault(args[1], 0), 0, 255);
    int b = Clamp(v8_utils::ToInt32WithDefault(args[2], 0), 0, 255);
    int a = Clamp(v8_utils::ToInt32WithDefault(args[3], 255), 0, 255);

    canvas->getDevice()->accessBitmap(true).eraseColor(
        SkColorSetARGB(a, r, g, b));
    return args.GetReturnValue().SetUndefined();
  }

  static void drawPath(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(isolate, args[0]))
      return args.GetReturnValue().SetUndefined();

    if (!SkPathWrapper::HasInstance(isolate, args[1]))
      return args.GetReturnValue().SetUndefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    SkPath* path = SkPathWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[1]));

    canvas->drawPath(*path, *paint);
    return args.GetReturnValue().SetUndefined();
  }

  static void drawPoints(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(isolate, args[0]))
      return args.GetReturnValue().SetUndefined();

    if (!args[2]->IsArray())
      return args.GetReturnValue().SetUndefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    v8::Handle<v8::Array> data = v8::Handle<v8::Array>::Cast(args[2]);
    uint32_t data_len = data->Length();
    uint32_t points_len = data_len / 2;

    SkPoint* points = new SkPoint[points_len];

    for (uint32_t i = 0; i < points_len; ++i) {
      double x = data->Get(v8::Integer::New(isolate, i * 2))->NumberValue();
      double y = data->Get(v8::Integer::New(isolate, i * 2 + 1))->NumberValue();
      points[i].set(SkDoubleToScalar(x), SkDoubleToScalar(y));
    }

    canvas->drawPoints(
        static_cast<SkCanvas::PointMode>(v8_utils::ToInt32(args[1])),
        points_len, points, *paint);

    delete[] points;

    return args.GetReturnValue().SetUndefined();
  }

  static void drawRect(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(isolate, args[0]))
      return args.GetReturnValue().SetUndefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    SkRect rect = { SkDoubleToScalar(args[1]->NumberValue()),
                    SkDoubleToScalar(args[2]->NumberValue()),
                    SkDoubleToScalar(args[3]->NumberValue()),
                    SkDoubleToScalar(args[4]->NumberValue()) };
    canvas->drawRect(rect, *paint);
    return args.GetReturnValue().SetUndefined();
  }

  static void drawRoundRect(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(isolate, args[0]))
      return args.GetReturnValue().SetUndefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    SkRect rect = { SkDoubleToScalar(args[1]->NumberValue()),
                    SkDoubleToScalar(args[2]->NumberValue()),
                    SkDoubleToScalar(args[3]->NumberValue()),
                    SkDoubleToScalar(args[4]->NumberValue()) };
    canvas->drawRoundRect(rect,
                          SkDoubleToScalar(args[5]->NumberValue()),
                          SkDoubleToScalar(args[6]->NumberValue()),
                          *paint);
    return args.GetReturnValue().SetUndefined();
  }

  static void drawText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(isolate, args[0]))
      return args.GetReturnValue().SetUndefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    v8::String::Utf8Value utf8(args[1]);
    canvas->drawText(*utf8, utf8.length(),
                     SkDoubleToScalar(args[2]->NumberValue()),
                     SkDoubleToScalar(args[3]->NumberValue()),
                     *paint);
    return args.GetReturnValue().SetUndefined();
  }

  static void drawTextOnPathHV(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(isolate, args[0]))
      return args.GetReturnValue().SetUndefined();

    if (!SkPathWrapper::HasInstance(isolate, args[1]))
      return args.GetReturnValue().SetUndefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    SkPath* path = SkPathWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[1]));

    v8::String::Utf8Value utf8(args[2]);
    canvas->drawTextOnPathHV(*utf8, utf8.length(), *path,
                             SkDoubleToScalar(args[3]->NumberValue()),
                             SkDoubleToScalar(args[4]->NumberValue()),
                             *paint);
    return args.GetReturnValue().SetUndefined();
  }

  static void translate(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->translate(SkDoubleToScalar(args[0]->NumberValue()),
                      SkDoubleToScalar(args[1]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  static void scale(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->scale(SkDoubleToScalar(args[0]->NumberValue()),
                  SkDoubleToScalar(args[1]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  static void rotate(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->rotate(SkDoubleToScalar(args[0]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  static void skew(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->skew(SkDoubleToScalar(args[0]->NumberValue()),
                 SkDoubleToScalar(args[1]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  static void save(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->save();
    return args.GetReturnValue().SetUndefined();
  }

  static void restore(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->restore();
    return args.GetReturnValue().SetUndefined();
  }

  static void writeImage(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (args.Length() < 2)
      return v8_utils::ThrowError(isolate, "Wrong number of arguments.");

    const uint32_t rmask = SK_R32_MASK << SK_R32_SHIFT;
    const uint32_t gmask = SK_G32_MASK << SK_G32_SHIFT;
    const uint32_t bmask = SK_B32_MASK << SK_B32_SHIFT;

    SkCanvas* canvas = ExtractPointer(args.Holder());
    const SkBitmap& bitmap = canvas->getDevice()->accessBitmap(false);

    v8::String::Utf8Value type(args[0]);
    if (strcmp(*type, "png") != 0)
      return v8_utils::ThrowError(isolate, "writeImage can only write PNG types.");

    v8::String::Utf8Value filename(args[1]);

    FIBITMAP* fb = FreeImage_ConvertFromRawBits(
        reinterpret_cast<BYTE*>(bitmap.getPixels()),
        bitmap.width(), bitmap.height(), bitmap.rowBytes(), 32,
        rmask, gmask, bmask, TRUE);

    if (!fb)
      return v8_utils::ThrowError(isolate, "Couldn't allocate output FreeImage bitmap.");

    // Let's hope that ConvertFromRawBits made a copy.
    for (int y = 0; y < bitmap.height(); ++y) {
      uint32_t* scanline =
          reinterpret_cast<uint32_t*>(FreeImage_GetScanLine(fb, y));
      for (int x = 0; x < bitmap.width(); ++x) {
        scanline[x] = SkUnPreMultiply::PMColorToColor(scanline[x]);
      }
    }

    if (args.Length() >= 3 && args[2]->IsObject()) {
      v8::Handle<v8::Object> opts = v8::Handle<v8::Object>::Cast(args[2]);
      if (opts->Has(v8::String::NewFromUtf8(isolate, "dotsPerMeterX"))) {
        FreeImage_SetDotsPerMeterX(fb,
            opts->Get(v8::String::NewFromUtf8(isolate, "dotsPerMeterX"))->Uint32Value());
      }
      if (opts->Has(v8::String::NewFromUtf8(isolate, "dotsPerMeterY"))) {
        FreeImage_SetDotsPerMeterY(fb,
            opts->Get(v8::String::NewFromUtf8(isolate, "dotsPerMeterY"))->Uint32Value());
      }
    }

    bool saved = FreeImage_Save(FIF_PNG, fb, *filename, 0);
    FreeImage_Unload(fb);

    if (!saved)
      return v8_utils::ThrowError(isolate, "Failed to save png.");

    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(writePDF, 1)
    SkCanvas* canvas = ExtractPointer(args.Holder());

    v8::String::Utf8Value filename(args[0]);

    SkFILEWStream stream(*filename);
    SkPDFDocument document;
    // You shouldn't be calling this with an SkDevice (bitmap) backed SkCanvas.
    document.appendPage(reinterpret_cast<SkPDFDevice*>(canvas->getDevice()));

    if (!document.emitPDF(&stream))
      return v8_utils::ThrowError(isolate, "Error writing PDF.");

    return args.GetReturnValue().SetUndefined();
  }
};

class NSSoundWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &NSSoundWrapper::V8New);
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(1);

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
      { "kConstant", 1 },
    };

    static BatchedMethods methods[] = {
      { "isPlaying", &NSSoundWrapper::isPlaying },
      { "pause", &NSSoundWrapper::pause },
      { "play", &NSSoundWrapper::play },
      { "resume", &NSSoundWrapper::resume },
      { "stop", &NSSoundWrapper::stop },
      { "volume", &NSSoundWrapper::volume },
      { "setVolume", &NSSoundWrapper::setVolume },
      { "currentTime", &NSSoundWrapper::currentTime },
      { "setCurrentTime", &NSSoundWrapper::setCurrentTime },
      { "loops", &NSSoundWrapper::loops },
      { "setLoops", &NSSoundWrapper::setLoops },
      { "duration", &NSSoundWrapper::duration },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      ft->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
              v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
                    v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, methods[i].name),
                    v8::FunctionTemplate::New(isolate, methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static NSSound* ExtractNSSoundPointer(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<NSSound*>(obj->GetAlignedPointerFromInternalField(0));
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

 private:
  DEFINE_METHOD(V8New, 1)
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    v8::String::Utf8Value filename(args[0]);
    NSSound* sound = [[NSSound alloc] initWithContentsOfFile:
        [NSString stringWithUTF8String:*filename] byReference:YES];

    args.This()->SetAlignedPointerInInternalField(0, sound);
  }

  static void isPlaying(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSSound* sound = ExtractNSSoundPointer(args.Holder());
    return args.GetReturnValue().Set((bool)[sound isPlaying]);
  }

  static void pause(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSSound* sound = ExtractNSSoundPointer(args.Holder());
    return args.GetReturnValue().Set((bool)[sound pause]);
  }

  static void play(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSSound* sound = ExtractNSSoundPointer(args.Holder());
    return args.GetReturnValue().Set((bool)[sound play]);
  }

  static void resume(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSSound* sound = ExtractNSSoundPointer(args.Holder());
    return args.GetReturnValue().Set((bool)[sound resume]);
  }

  static void stop(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSSound* sound = ExtractNSSoundPointer(args.Holder());
    return args.GetReturnValue().Set((bool)[sound stop]);
  }

  static void volume(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSSound* sound = ExtractNSSoundPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [sound volume]));
  }

  DEFINE_METHOD(setVolume, 1)
    NSSound* sound = ExtractNSSoundPointer(args.Holder());
    [sound setVolume:args[0]->NumberValue()];
    return args.GetReturnValue().SetUndefined();
  }

  static void currentTime(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSSound* sound = ExtractNSSoundPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [sound currentTime]));
  }

  DEFINE_METHOD(setCurrentTime, 1)
    NSSound* sound = ExtractNSSoundPointer(args.Holder());
    [sound setCurrentTime:args[0]->NumberValue()];
    return args.GetReturnValue().SetUndefined();
  }

  static void loops(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSSound* sound = ExtractNSSoundPointer(args.Holder());
    return args.GetReturnValue().Set((bool)[sound loops]);
  }

  DEFINE_METHOD(setLoops, 1)
    NSSound* sound = ExtractNSSoundPointer(args.Holder());
    [sound setLoops:args[0]->BooleanValue()];
    return args.GetReturnValue().SetUndefined();
  }

  static void duration(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSSound* sound = ExtractNSSoundPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [sound duration]));
  }
};

void NSOpenGLContextWrapper::texImage2DSkCanvasB(
    const v8::FunctionCallbackInfo<v8::Value>& args) {
  if (args.Length() != 3)
    return v8_utils::ThrowError(isolate, "Wrong number of arguments.");

  if (!args[2]->IsObject() && !SkCanvasWrapper::HasInstance(isolate, args[2]))
    return v8_utils::ThrowError(isolate, "Expected image to be an SkCanvas instance.");

  SkCanvas* canvas = SkCanvasWrapper::ExtractPointer(
      v8::Handle<v8::Object>::Cast(args[2]));
  const SkBitmap& bitmap = canvas->getDevice()->accessBitmap(false);
  glTexImage2D(args[0]->Uint32Value(),
               args[1]->Int32Value(),
               GL_RGBA8,
               bitmap.width(),
               bitmap.height(),
               0,
               GL_BGRA,  // We have to swizzle, so this technically isn't ES.
               GL_UNSIGNED_INT_8_8_8_8_REV,
               bitmap.getPixels());
  return args.GetReturnValue().SetUndefined();
}

void NSOpenGLContextWrapper::drawSkCanvas(
    const v8::FunctionCallbackInfo<v8::Value>& args) {
  if (args.Length() != 1)
    return v8_utils::ThrowError(isolate, "Wrong number of arguments.");

  if (!args[0]->IsObject() && !SkCanvasWrapper::HasInstance(isolate, args[0]))
    return v8_utils::ThrowError(isolate, "Expected image to be an SkCanvas instance.");

  SkCanvas* canvas = SkCanvasWrapper::ExtractPointer(
      v8::Handle<v8::Object>::Cast(args[0]));
  const SkBitmap& bitmap = canvas->getDevice()->accessBitmap(false);

  GLfloat save_zoom_x, save_zoom_y;
  glGetFloatv(GL_ZOOM_X, &save_zoom_x);
  glGetFloatv(GL_ZOOM_Y, &save_zoom_y);
  glRasterPos2i(-1, 1);
  glPixelZoom(1, -1);
  glDrawPixels(bitmap.width(),
               bitmap.height(),
               GL_BGRA,  // We have to swizzle, so this technically isn't ES.
               GL_UNSIGNED_INT_8_8_8_8_REV,
               bitmap.getPixels());
  glPixelZoom(save_zoom_x, save_zoom_y);
  // TODO(deanm): We should also restore the raster position, but it's not as
  // simple since it goes through the transforms.  This should hopefully put us
  // back to the default (0, 0, 0, 1) at least.
  glRasterPos2i(-1, -1);
  return args.GetReturnValue().SetUndefined();
}

// MIDI notes (pun pun):
// Like UTF-8, there is tagging to identify the begin of a message.
// All first bytes are in the range of 0x80 - 0xff, the MSB is set.
// 8 = Note Off
// 9 = Note On
// A = AfterTouch (ie, key pressure)
// B = Control Change
// C = Program (patch) change
// D = Channel Pressure
// E = Pitch Wheel

// TODO(deanm): Global MIDIClientCreate, lazily initialized, ever torn down?
MIDIClientRef g_midi_client = NULL;

// This function was submitted by Douglas Casey Tucker and apparently
// derived largely from PortMidi.  (From RtMidi).
static CFStringRef EndpointName( MIDIEndpointRef endpoint, bool isExternal ) CF_RETURNS_RETAINED;
static CFStringRef EndpointName( MIDIEndpointRef endpoint, bool isExternal )
{
  CFMutableStringRef result = CFStringCreateMutable( NULL, 0 );
  CFStringRef str;

  // Begin with the endpoint's name.
  str = NULL;
  MIDIObjectGetStringProperty( endpoint, kMIDIPropertyName, &str );
  if ( str != NULL ) {
    CFStringAppend( result, str );
    CFRelease( str );
  }

  MIDIEntityRef entity = 0;
  MIDIEndpointGetEntity( endpoint, &entity );
  if ( entity == 0 )
    // probably virtual
    return result;

  if ( CFStringGetLength( result ) == 0 ) {
    // endpoint name has zero length -- try the entity
    str = NULL;
    MIDIObjectGetStringProperty( entity, kMIDIPropertyName, &str );
    if ( str != NULL ) {
      CFStringAppend( result, str );
      CFRelease( str );
    }
  }
  // now consider the device's name
  MIDIDeviceRef device = 0;
  MIDIEntityGetDevice( entity, &device );
  if ( device == 0 )
    return result;

  str = NULL;
  MIDIObjectGetStringProperty( device, kMIDIPropertyName, &str );
  if ( CFStringGetLength( result ) == 0 ) {
      CFRelease( result );
      return str;
  }
  if ( str != NULL ) {
    // if an external device has only one entity, throw away
    // the endpoint name and just use the device name
    if ( isExternal && MIDIDeviceGetNumberOfEntities( device ) < 2 ) {
      CFRelease( result );
      return str;
    } else {
      if ( CFStringGetLength( str ) == 0 ) {
        CFRelease( str );
        return result;
      }
      // does the entity name already start with the device name?
      // (some drivers do this though they shouldn't)
      // if so, do not prepend
        if ( CFStringCompareWithOptions( result, /* endpoint name */
             str /* device name */,
             CFRangeMake(0, CFStringGetLength( str ) ), 0 ) != kCFCompareEqualTo ) {
        // prepend the device name to the entity name
        if ( CFStringGetLength( result ) > 0 )
          CFStringInsert( result, 0, CFSTR(" ") );
        CFStringInsert( result, 0, str );
      }
      CFRelease( str );
    }
  }
  return result;
}

// This function was submitted by Douglas Casey Tucker and apparently
// derived largely from PortMidi.  (From RtMidi).
static CFStringRef ConnectedEndpointName( MIDIEndpointRef endpoint ) CF_RETURNS_RETAINED;
static CFStringRef ConnectedEndpointName( MIDIEndpointRef endpoint )
{
  CFMutableStringRef result = CFStringCreateMutable( NULL, 0 );
  CFStringRef str;
  OSStatus err;
  int i;

  // Does the endpoint have connections?
  CFDataRef connections = NULL;
  int nConnected = 0;
  bool anyStrings = false;
  err = MIDIObjectGetDataProperty( endpoint, kMIDIPropertyConnectionUniqueID, &connections );
  if ( err == noErr && connections != NULL ) {
    // It has connections, follow them
    // Concatenate the names of all connected devices
    nConnected = CFDataGetLength( connections ) / sizeof(MIDIUniqueID);
    if ( nConnected ) {
      const SInt32 *pid = (const SInt32 *)(CFDataGetBytePtr(connections));
      for ( i=0; i<nConnected; ++i, ++pid ) {
        MIDIUniqueID id = EndianS32_BtoN( *pid );
        MIDIObjectRef connObject;
        MIDIObjectType connObjectType;
        err = MIDIObjectFindByUniqueID( id, &connObject, &connObjectType );
        if ( err == noErr ) {
          if ( connObjectType == kMIDIObjectType_ExternalSource  ||
              connObjectType == kMIDIObjectType_ExternalDestination ) {
            // Connected to an external device's endpoint (10.3 and later).
            str = EndpointName( (MIDIEndpointRef)(connObject), true );
          } else {
            // Connected to an external device (10.2) (or something else, catch-
            str = NULL;
            MIDIObjectGetStringProperty( connObject, kMIDIPropertyName, &str );
          }
          if ( str != NULL ) {
            if ( anyStrings )
              CFStringAppend( result, CFSTR(", ") );
            else anyStrings = true;
            CFStringAppend( result, str );
            CFRelease( str );
          }
        }
      }
    }
    CFRelease( connections );
  }
  if ( anyStrings )
    return result;

  if ( result )
    CFRelease( result );

  // Here, either the endpoint had no connections, or we failed to obtain names
  return EndpointName( endpoint, false );
}


class CAMIDISourceWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &CAMIDISourceWrapper::V8New);
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(2);  // MIDIEndpointRef and MIDIPortRef.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
      { "blah", 1 },
    };

    static BatchedMethods methods[] = {
      { "destinations", &CAMIDISourceWrapper::destinations },
      { "openDestination", &CAMIDISourceWrapper::openDestination },
      { "createVirtual", &CAMIDISourceWrapper::createVirtual },
      { "sendData", &CAMIDISourceWrapper::sendData },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
                    v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, methods[i].name),
                    v8::FunctionTemplate::New(isolate, methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static MIDIEndpointRef ExtractEndpoint(v8::Handle<v8::Object> obj) {
    // NOTE(deanm): MIDIEndpointRef (MIDIObjectRef) is UInt32 on 64-bit.
    return (MIDIEndpointRef)(intptr_t)obj->GetAlignedPointerFromInternalField(0);
  }

  static MIDIPortRef ExtractPort(v8::Handle<v8::Object> obj) {
    return (MIDIPortRef)(intptr_t)obj->GetAlignedPointerFromInternalField(1);
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

 private:
  static MIDIPacketList* AllocateMIDIPacketList(size_t num_packets,
                                         ByteCount* out_cnt) {
    ByteCount cnt = num_packets * sizeof(MIDIPacket) +
                    (sizeof(MIDIPacketList) - sizeof(MIDIPacket));
    char* buf = new char[cnt];
    if (out_cnt)
      *out_cnt = cnt;
    return reinterpret_cast<MIDIPacketList*>(buf);
  }

  static void FreeMIDIPacketList(MIDIPacketList* pl) {
    delete[] reinterpret_cast<char*>(pl);
  }

  static void sendData(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args[0]->IsArray())
      return args.GetReturnValue().SetUndefined();

    MIDIEndpointRef endpoint = ExtractEndpoint(args.Holder());

    if (!endpoint) {
      return v8_utils::ThrowError(isolate, "Can't send on midi without an endpoint.");
    }

    MIDIPortRef port = ExtractPort(args.Holder());
    MIDITimeStamp timestamp = AudioGetCurrentHostTime();
    ByteCount pl_count;
    MIDIPacketList* pl = AllocateMIDIPacketList(1, &pl_count);
    MIDIPacket* cur_packet = MIDIPacketListInit(pl);

    v8::Handle<v8::Array> data = v8::Handle<v8::Array>::Cast(args[0]);
    uint32_t data_len = data->Length();

    Byte* data_buf = new Byte[data_len];

    for (uint32_t i = 0; i < data_len; ++i) {
      // Convert to an integer and truncate to 8 bits.
      data_buf[i] = data->Get(v8::Integer::New(isolate, i))->Uint32Value();
    }

    cur_packet = MIDIPacketListAdd(pl, pl_count, cur_packet,
                                   timestamp, data_len, data_buf);
    // Depending whether we are virtual we need to send differently.
    OSStatus result = port ? MIDISend(port, endpoint, pl) :
                             MIDIReceived(endpoint, pl);
    delete[] data_buf;
    FreeMIDIPacketList(pl);

    if (result != noErr) {
      return v8_utils::ThrowError(isolate, "Couldn't send midi data.");
    }

    return args.GetReturnValue().SetUndefined();
  }

  static void V8New(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    OSStatus result;

    if (!g_midi_client) {
      result = MIDIClientCreate(CFSTR("Plask"), NULL, NULL, &g_midi_client);
      if (result != noErr) {
        return v8_utils::ThrowError(isolate, "Couldn't create midi client object.");
      }
    }

    args.This()->SetAlignedPointerInInternalField(0, NULL);
    args.This()->SetAlignedPointerInInternalField(1, NULL);
  }

  DEFINE_METHOD(createVirtual, 1)
    OSStatus result;

    v8::String::Utf8Value name_val(args[0]);
    CFStringRef name =
        CFStringCreateWithCString(NULL, *name_val, kCFStringEncodingUTF8);

    MIDIEndpointRef endpoint;
    result = MIDISourceCreate(g_midi_client, name, &endpoint);
    CFRelease(name);
    if (result != noErr) {
      return v8_utils::ThrowError(isolate, "Couldn't create midi source object.");
    }

    // NOTE(deanm): MIDIEndpointRef (MIDIObjectRef) is UInt32 on 64-bit.
    args.This()->SetAlignedPointerInInternalField(0, (void*)(intptr_t)endpoint);
    args.This()->SetAlignedPointerInInternalField(1, NULL);
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(openDestination, 1)
    OSStatus result;

    ItemCount num_destinations = MIDIGetNumberOfDestinations();
    ItemCount index = args[0]->Uint32Value();
    if (index >= num_destinations)
      return v8_utils::ThrowError(isolate, "Invalid MIDI destination index.");

    MIDIEndpointRef destination = MIDIGetDestination(index);

    MIDIPortRef port;
    result = MIDIOutputPortCreate(
        g_midi_client, CFSTR("Plask"), &port);
    if (result != noErr)
      return v8_utils::ThrowError(isolate, "Couldn't create midi output port.");

    args.This()->SetAlignedPointerInInternalField(0, (void*)(intptr_t)destination);
    args.This()->SetAlignedPointerInInternalField(1, (void*)(intptr_t)port);

    return args.GetReturnValue().SetUndefined();
    return args.GetReturnValue().SetUndefined();
  }

  // NOTE(deanm): See API notes about sources(), same comments apply here.
  static void destinations(const v8::FunctionCallbackInfo<v8::Value>& args) {
    ItemCount num_destinations = MIDIGetNumberOfDestinations();
    v8::Local<v8::Array> arr = v8::Array::New(isolate, num_destinations);
    for (ItemCount i = 0; i < num_destinations; ++i) {
      MIDIEndpointRef point = MIDIGetDestination(i);
      CFStringRef name = ConnectedEndpointName(point);
      arr->Set(i, v8::String::NewFromUtf8(isolate, [(NSString*)name UTF8String]));
      CFRelease(name);
    }
    return args.GetReturnValue().Set(arr);
  }

};

class CAMIDIDestinationWrapper {
 private:
  struct State {
    MIDIEndpointRef endpoint;
    int64_t clocks;
    int pipe_fds[2];
  };

 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &CAMIDIDestinationWrapper::V8New);
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // MIDIEndpointRef.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
      { "kDummy", 1 },
    };

    static BatchedMethods methods[] = {
      { "createVirtual", &CAMIDIDestinationWrapper::createVirtual },
      { "sources", &CAMIDIDestinationWrapper::sources },
      { "openSource", &CAMIDIDestinationWrapper::openSource },
      { "syncClocks", &CAMIDIDestinationWrapper::syncClocks },
      { "getPipeDescriptor", &CAMIDIDestinationWrapper::getPipeDescriptor },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
                    v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, methods[i].name),
                    v8::FunctionTemplate::New(isolate, methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static State* ExtractPointer(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<State*>(obj->GetAlignedPointerFromInternalField(0));
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

 private:
  // TODO(deanm): Access to state isn't thread safe.  As long as we're 64-bit
  // I'm not particularly concerned.
  static void ReadCallback(const MIDIPacketList* pktlist,
                           void* state_raw,
                           void* src) {
    State* state = reinterpret_cast<State*>(state_raw);
    const MIDIPacket* packet = &pktlist->packet[0];
    for (int i = 0; i < pktlist->numPackets; ++i) {
      //printf("Packet: ");
      //for (int j = 0; j < packet->length; ++j) {
        //printf("%02x ", packet->data[j]);
      //}
      //printf("\n");
      if (packet->data[0] == 0xf2) {
        // NOTE(deanm): Wraps around bar 1024.
        int beat = packet->data[2] << 7 | packet->data[1];
        state->clocks = beat * 6;
      } else if (packet->data[0] == 0xf8) {
        ++state->clocks;
        //printf("Clock position: %lld\n", state->clocks);
      } else {
        // TODO(deanm): Message framing.
        ssize_t res = write(state->pipe_fds[1], packet->data, packet->length);
        if (res != packet->length) {
          printf("Error sending midi -> pipe (%zd)\n", res);
        }
      }
      packet = MIDIPacketNext(packet);
    }
  }

  static void syncClocks(const v8::FunctionCallbackInfo<v8::Value>& args) {
    State* state = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Integer::New(isolate, state->clocks));
  }

  static void getPipeDescriptor(const v8::FunctionCallbackInfo<v8::Value>& args) {
    State* state = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, state->pipe_fds[0]));
  }

  static void V8New(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    OSStatus result;

    if (!g_midi_client) {
      result = MIDIClientCreate(CFSTR("Plask"), NULL, NULL, &g_midi_client);
      if (result != noErr) {
        return v8_utils::ThrowError(isolate, "Couldn't create midi client object.");
      }
    }

    State* state = new State;
    state->endpoint = NULL;
    state->clocks = 0;
    int res = pipe(state->pipe_fds);
    if (res != 0)
      return v8_utils::ThrowError(isolate, "Couldn't create internal MIDI pipe.");
    args.This()->SetAlignedPointerInInternalField(0, state);
  }


  DEFINE_METHOD(createVirtual, 1)
    OSStatus result;
    v8::String::Utf8Value name_val(args[0]);
    CFStringRef name =
        CFStringCreateWithCString(NULL, *name_val, kCFStringEncodingUTF8);

    State* state = ExtractPointer(args.Holder());

    MIDIEndpointRef endpoint;
    result = MIDIDestinationCreate(
        g_midi_client, name, &ReadCallback, state, &endpoint);
    CFRelease(name);
    if (result != noErr)
      return v8_utils::ThrowError(isolate, "Couldn't create midi source object.");

    state->endpoint = endpoint;
    return args.GetReturnValue().SetUndefined();
  }

  // NOTE(deanm): Could make sense for the API to be numSources() and then
  // you query for sourceName(index), but really, do you ever want the index
  // without the name?  This could be a little extra work if you don't, but
  // really it seems to make sense in most of the use cases.
  static void sources(const v8::FunctionCallbackInfo<v8::Value>& args) {
    ItemCount num_sources = MIDIGetNumberOfSources();
    v8::Local<v8::Array> arr = v8::Array::New(isolate, num_sources);
    for (ItemCount i = 0; i < num_sources; ++i) {
      MIDIEndpointRef point = MIDIGetSource(i);
      CFStringRef name = ConnectedEndpointName(point);
      arr->Set(i, v8::String::NewFromUtf8(isolate, [(NSString*)name UTF8String]));
      CFRelease(name);
    }
    return args.GetReturnValue().Set(arr);
  }

  DEFINE_METHOD(openSource, 1)
    OSStatus result;
    State* state = ExtractPointer(args.Holder());

    ItemCount num_sources = MIDIGetNumberOfSources();
    ItemCount index = args[0]->Uint32Value();
    if (index >= num_sources)
      return v8_utils::ThrowError(isolate, "Invalid MIDI source index.");

    MIDIEndpointRef source = MIDIGetSource(index);

    MIDIPortRef port;
    result = MIDIInputPortCreate(
        g_midi_client, CFSTR("Plask"), &ReadCallback, state, &port);
    if (result != noErr)
      return v8_utils::ThrowError(isolate, "Couldn't create midi source object.");

    result = MIDIPortConnectSource(port, source, NULL);
    if (result != noErr)
      return v8_utils::ThrowError(isolate, "Couldn't create midi source object.");

    state->endpoint = source;

    return args.GetReturnValue().SetUndefined();
  }
};


class SBApplicationWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &SBApplicationWrapper::V8New);
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // id.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
      { "kDummy", 1 },
    };

    static BatchedMethods methods[] = {
      { "objcMethods", &SBApplicationWrapper::objcMethods },
      { "invokeVoid0", &SBApplicationWrapper::invokeVoid0 },
      { "invokeVoid1s", &SBApplicationWrapper::invokeVoid1s },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
                    v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, methods[i].name),
                    v8::FunctionTemplate::New(isolate, methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static id ExtractID(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<id>(obj->GetAlignedPointerFromInternalField(0));
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

 private:
  DEFINE_METHOD(V8New, 1)
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    v8::String::Utf8Value bundleid(args[0]);
    id obj = [SBApplication applicationWithBundleIdentifier:
        [NSString stringWithUTF8String:*bundleid]];
    [obj retain];

    if (obj == nil)
      return v8_utils::ThrowError(isolate, "Unable to create SBApplication.");

    args.This()->SetAlignedPointerInInternalField(0, obj);
  }

  static void objcMethods(const v8::FunctionCallbackInfo<v8::Value>& args) {
    id obj = ExtractID(args.Holder());
    unsigned int num_methods;
    Method* methods = class_copyMethodList(object_getClass(obj), &num_methods);
    v8::Local<v8::Array> res = v8::Array::New(isolate, num_methods);

    for (unsigned int i = 0; i < num_methods; ++i) {
      unsigned num_args = method_getNumberOfArguments(methods[i]);
      v8::Local<v8::Array> sig = v8::Array::New(isolate, num_args + 1);
      char rettype[256];
      method_getReturnType(methods[i], rettype, sizeof(rettype));
      sig->Set(v8::Integer::NewFromUnsigned(isolate, 0),
               v8::String::NewFromUtf8(isolate, sel_getName(method_getName(methods[i]))));
      sig->Set(v8::Integer::NewFromUnsigned(isolate, 1),
               v8::String::NewFromUtf8(isolate, rettype));
      for (unsigned j = 0; j < num_args; ++j) {
        char argtype[256];
        method_getArgumentType(methods[i], j, argtype, sizeof(argtype));
        sig->Set(v8::Integer::NewFromUnsigned(isolate, j + 2),
                 v8::String::NewFromUtf8(isolate, argtype));
      }
      res->Set(v8::Integer::NewFromUnsigned(isolate, i), sig);
    }

    return args.GetReturnValue().Set(res);
  }

  DEFINE_METHOD(invokeVoid0, 1)
    id obj = ExtractID(args.Holder());
    v8::String::Utf8Value method_name(args[0]);
    [obj performSelector:sel_getUid(*method_name)];
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(invokeVoid1s, 2)
    id obj = ExtractID(args.Holder());
    v8::String::Utf8Value method_name(args[0]);
    v8::String::Utf8Value arg(args[1]);
    [obj performSelector:sel_getUid(*method_name) withObject:
        [NSString stringWithUTF8String:*arg]];
    return args.GetReturnValue().SetUndefined();
  }
};


class NSAppleScriptWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &NSAppleScriptWrapper::V8New);
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // NSAppleScript*.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
      { "kDummy", 1 },
    };

    static BatchedMethods methods[] = {
      { "execute", &NSAppleScriptWrapper::execute },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
                    v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, methods[i].name),
                    v8::FunctionTemplate::New(isolate, methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static NSAppleScript* ExtractNSAppleScript(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<NSAppleScript*>(
        obj->GetAlignedPointerFromInternalField(0));
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

 private:
  DEFINE_METHOD(V8New, 1)
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    v8::String::Utf8Value src(args[0]);
    NSAppleScript* ascript = [[NSAppleScript alloc] initWithSource:
        [NSString stringWithUTF8String:*src]];

    if (ascript == nil)
      return v8_utils::ThrowError(isolate, "Unable to create NSAppleScript.");

    args.This()->SetAlignedPointerInInternalField(0, ascript);
  }

  static void execute(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSAppleScript* ascript = ExtractNSAppleScript(args.Holder());
    if ([ascript executeAndReturnError:nil] == nil)
      return v8_utils::ThrowError(isolate, "Error executing AppleScript.");
    return args.GetReturnValue().SetUndefined();
  }
};

class AVPlayerWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &V8New);

    ft->SetClassName(v8::String::NewFromUtf8(isolate, "AVPlayer"));
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // Player

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
      { "kValue", 12 },
    };

    static BatchedMethods methods[] = {
      METHOD_ENTRY( status ),
      METHOD_ENTRY( error ),
      METHOD_ENTRY( play ),
      METHOD_ENTRY( currentTime ),
      METHOD_ENTRY( seekToTime ),
      METHOD_ENTRY( currentFrameTexture ),
      METHOD_ENTRY( rate ),
      METHOD_ENTRY( setRate ),
      METHOD_ENTRY( playNext ),
      METHOD_ENTRY( appendURL ),
      METHOD_ENTRY( appendFile ),
      METHOD_ENTRY( removeAll ),
      METHOD_ENTRY( setLoops ),
      METHOD_ENTRY( volume ),
      METHOD_ENTRY( setVolume ),
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      ft->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
              v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::NewFromUtf8(isolate, constants[i].name),
                    v8::Uint32::New(isolate, constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::NewFromUtf8(isolate, methods[i].name),
                    v8::FunctionTemplate::New(isolate, methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    ft_cache.Reset(isolate, ft);
    return ft_cache;
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

  static TextureAVPlayer* ExtractPlayerPointer(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<TextureAVPlayer*>(obj->GetAlignedPointerFromInternalField(0));
  }

 private:
  static void WeakCallback(
      const v8::WeakCallbackData<v8::Object, v8::Persistent<v8::Object> >& data) {
    TextureAVPlayer* player = ExtractPlayerPointer(data.GetValue());

    v8::Persistent<v8::Object>* persistent = data.GetParameter();
    persistent->ClearWeak();
    persistent->Reset();
    delete persistent;

    [player release];
  }

  static void V8New(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    TextureAVPlayer* player = nil;

    if (args.Length() == 0) {
      player = [[TextureAVPlayer alloc] init];
    } else if (args.Length() == 1) {
      if (!NSOpenGLContextWrapper::HasInstance(isolate, args[0]))
        return v8_utils::ThrowError(isolate, "Expected NSOpenGLContext.");
      NSOpenGLContext* nscontext = NSOpenGLContextWrapper::ExtractContextPointer(
          v8::Handle<v8::Object>::Cast(args[0]));
      player = [[TextureAVPlayer alloc] initWithNSOpenGLContext:nscontext];
    } else {
      return v8_utils::ThrowError(isolate, "Wrong number of arguments.");
    }

    args.This()->SetAlignedPointerInInternalField(0, player);

    v8::Persistent<v8::Object>* persistent = new v8::Persistent<v8::Object>();
    persistent->Reset(isolate, args.This());
    persistent->SetWeak(persistent, &WeakCallback);
  }

  DEFINE_METHOD(volume, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [player volume]));
  }

  DEFINE_METHOD(setVolume, 1)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    [player setVolume:args[0]->NumberValue()];
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(setLoops, 1)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    [player setLoops:args[0]->BooleanValue()];
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(appendURL, 1)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    v8::String::Utf8Value url(args[0]);
    NSURL* nsurl = [NSURL URLWithString:[NSString stringWithUTF8String:*url]];
    [player appendURL:nsurl];
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(appendFile, 1)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    v8::String::Utf8Value filename(args[0]);
    NSURL* nsurl = [NSURL fileURLWithPath:[NSString stringWithUTF8String:*filename]];
    [player appendURL:nsurl];
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(removeAll, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    [player removeAllItems];
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(playNext, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    [player advanceToNextItem];
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(rate, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [player rate]));
  }

  DEFINE_METHOD(setRate, 1)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    [player setRate:args[0]->NumberValue()];
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(status, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    AVPlayerStatus status = [player status];
    const char* str = status == AVPlayerStatusUnknown ? "unknown" :
                          status == AVPlayerStatusReadyToPlay ? "ready" : "failed";
    return args.GetReturnValue().Set(v8::String::NewFromUtf8(isolate, str));
  }

  DEFINE_METHOD(error, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    NSError* error = [player error];
    return args.GetReturnValue().Set(static_cast<int32_t>([error code]));
  }

  DEFINE_METHOD(play, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    [player play];
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(currentTime, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    CMTime time = [player currentTime];
    if ((time.flags & kCMTimeFlags_Valid) == 0)
      return args.GetReturnValue().SetNull();
    return args.GetReturnValue().Set(time.value / (double)time.timescale);
  }

  DEFINE_METHOD(seekToTime, 1)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    // TODO(deanm): What if currentItem is invalid? What about the timescale?
    CMTime time = CMTimeMakeWithSeconds(args[0]->NumberValue(), [player currentTime].timescale);

    // We probably want max precision to be default ?
    [player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(currentFrameTexture, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());

    CVOpenGLTextureRef texture = [player textureForItemTime:[[player currentItem] currentTime]];
    if (texture == NULL)
      return args.GetReturnValue().SetNull();

    GLuint name = CVOpenGLTextureGetName(texture);

    GLfloat coords[8];
    CVOpenGLTextureGetCleanTexCoords(texture, coords, coords+2, coords+4, coords+6);

    v8::Local<v8::Object> obj = v8::Object::New(isolate);
    obj->Set(v8::String::NewFromUtf8(isolate, "target"),
             v8::Integer::NewFromUnsigned(isolate, CVOpenGLTextureGetTarget(texture)));
    obj->Set(v8::String::NewFromUtf8(isolate, "texture"), WebGLTexture::NewFromName(name));
    obj->Set(v8::String::NewFromUtf8(isolate, "flipped"),
             v8::Boolean::New(isolate, CVOpenGLTextureIsFlipped(texture)));
    // Lower Left
    obj->Set(v8::String::NewFromUtf8(isolate, "s0"), v8::Number::New(isolate, coords[0]));
    obj->Set(v8::String::NewFromUtf8(isolate, "t0"), v8::Number::New(isolate, coords[1]));
    // Lower Right
    obj->Set(v8::String::NewFromUtf8(isolate, "s1"), v8::Number::New(isolate, coords[2]));
    obj->Set(v8::String::NewFromUtf8(isolate, "t1"), v8::Number::New(isolate, coords[3]));
    // Upper Right
    obj->Set(v8::String::NewFromUtf8(isolate, "s2"), v8::Number::New(isolate, coords[4]));
    obj->Set(v8::String::NewFromUtf8(isolate, "t2"), v8::Number::New(isolate, coords[5]));
    // Upper Left
    obj->Set(v8::String::NewFromUtf8(isolate, "s3"), v8::Number::New(isolate, coords[6]));
    obj->Set(v8::String::NewFromUtf8(isolate, "t3"), v8::Number::New(isolate, coords[7]));

    CFRelease(texture);
    return args.GetReturnValue().Set(obj);
  }
};


}  // namespace

@implementation WrappedNSWindow

-(void)setEventCallbackWithHandle:(v8::Handle<v8::Function>)func {
  event_callback_.Reset(isolate, func);
}

-(void)processEvent:(NSEvent *)event {
  if (!event_callback_.IsEmpty()) {
    [event retain];  // Released by NSEventWrapper.
    v8::Local<v8::FunctionTemplate> ft = v8::Local<v8::FunctionTemplate>::New(
        isolate, NSEventWrapper::GetTemplate(isolate));
    v8::Local<v8::Object> res = ft->InstanceTemplate()->NewInstance();
    res->SetAlignedPointerInInternalField(0, event);
    v8::Local<v8::Value> argv[] = { v8::Number::New(isolate, 0), res };
    v8::TryCatch try_catch;
    PersistentToLocal(isolate, event_callback_)->Call(
        isolate->GetCurrentContext()->Global(), 2, argv);
    // Hopefully plask.js will have caught any exceptions already.
    if (try_catch.HasCaught()) {
      printf("Exception in event callback, TODO(deanm): print something.\n");
    }
  }
}

// In order to receive keyboard events, we need to be able to be the key window.
// By default this would be YES, except if we don't have a title bar, for
// example in fullscreen mode.  We want to always be able to become the key
// window and the main window.
-(BOOL)canBecomeMainWindow {
  return YES;
}

-(BOOL)canBecomeKeyWindow {
  return YES;
}

-(void)sendEvent:(NSEvent *)event {
  [super sendEvent:event];
  [self processEvent:event];
}

-(void)noResponderFor:(SEL)event_selector {
  // Overridden since the default implementation beeps for keyDown.
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
  return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
  NSPasteboard* board = [sender draggingPasteboard];
  NSArray* paths = [board propertyListForType:NSFilenamesPboardType];
  v8::Local<v8::Array> jspaths = v8::Array::New(isolate, [paths count]);
  for (int i = 0; i < [paths count]; ++i) {
    jspaths->Set(v8::Integer::New(isolate, i), v8::String::NewFromUtf8(isolate,
        [[paths objectAtIndex:i] UTF8String]));
  }

  NSPoint location = [sender draggingLocation];

  v8::Local<v8::Object> res = v8::Object::New(isolate);
  res->Set(v8::String::NewFromUtf8(isolate, "paths"), jspaths);
  res->Set(v8::String::NewFromUtf8(isolate, "x"), v8::Number::New(isolate, location.x));
  res->Set(v8::String::NewFromUtf8(isolate, "y"), v8::Number::New(isolate, location.y));

  v8::Handle<v8::Value> argv[] = { v8::Number::New(isolate, 1), res };
  v8::TryCatch try_catch;
  PersistentToLocal(isolate, event_callback_)->Call(
      isolate->GetCurrentContext()->Global(), 2, argv);
  // Hopefully plask.js will have caught any exceptions already.
  if (try_catch.HasCaught()) {
    printf("Exception in event callback, TODO(deanm): print something.\n");
  }

  return YES;
}


@end

@implementation WindowDelegate

-(void)windowDidMove:(NSNotification *)notification {
}

@end

void plask_setup_bindings(v8::Isolate* isolate,
                          v8::Handle<v8::ObjectTemplate> obj) {
  v8::HandleScope handle_scope(isolate);
  SetInternalIsolate(isolate);
  obj->Set(v8::String::NewFromUtf8(isolate, "NSWindow"),
           PersistentToLocal(isolate, NSWindowWrapper::GetTemplate(isolate)));
  obj->Set(v8::String::NewFromUtf8(isolate, "NSEvent"),
           PersistentToLocal(isolate, NSEventWrapper::GetTemplate(isolate)));
  obj->Set(v8::String::NewFromUtf8(isolate, "SkPath"),
           PersistentToLocal(isolate, SkPathWrapper::GetTemplate(isolate)));
  obj->Set(v8::String::NewFromUtf8(isolate, "SkPaint"),
           PersistentToLocal(isolate, SkPaintWrapper::GetTemplate(isolate)));
  obj->Set(v8::String::NewFromUtf8(isolate, "SkCanvas"),
           PersistentToLocal(isolate, SkCanvasWrapper::GetTemplate(isolate)));
  obj->Set(v8::String::NewFromUtf8(isolate, "NSOpenGLContext"),
           PersistentToLocal(isolate, NSOpenGLContextWrapper::GetTemplate(isolate)));
  obj->Set(v8::String::NewFromUtf8(isolate, "NSSound"),
           PersistentToLocal(isolate, NSSoundWrapper::GetTemplate(isolate)));
  obj->Set(v8::String::NewFromUtf8(isolate, "CAMIDISource"),
           PersistentToLocal(isolate, CAMIDISourceWrapper::GetTemplate(isolate)));
  obj->Set(v8::String::NewFromUtf8(isolate, "CAMIDIDestination"),
           PersistentToLocal(isolate, CAMIDIDestinationWrapper::GetTemplate(isolate)));
  obj->Set(v8::String::NewFromUtf8(isolate, "SBApplication"),
           PersistentToLocal(isolate, SBApplicationWrapper::GetTemplate(isolate)));
  obj->Set(v8::String::NewFromUtf8(isolate, "NSAppleScript"),
           PersistentToLocal(isolate, NSAppleScriptWrapper::GetTemplate(isolate)));
  obj->Set(v8::String::NewFromUtf8(isolate, "AVPlayer"),
           PersistentToLocal(isolate, AVPlayerWrapper::GetTemplate(isolate)));

}

void plask_teardown_bindings() {
  WebGLFramebuffer::ClearMap();
  WebGLTexture::ClearMap();
  WebGLRenderbuffer::ClearMap();
  WebGLBuffer::ClearMap();
  WebGLProgram::ClearMap();
  WebGLShader::ClearMap();
  WebGLVertexArrayObject::ClearMap();
}
