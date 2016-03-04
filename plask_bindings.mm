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

#if PLASK_OSX
#include <CoreFoundation/CoreFoundation.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreMIDI/CoreMIDI.h>
#include <ScriptingBridge/SBApplication.h>
#include <Foundation/NSObjCRuntime.h>
#include <AVFoundation/AVPlayer.h>
#include <AVFoundation/AVPlayerItem.h>
#include <AVFoundation/AVPlayerItemOutput.h>
#include <AVFoundation/AVTime.h>  // CMTimeRangeValue
#include <CoreMedia/CoreMedia.h>
#include <objc/runtime.h>
#endif

#define SK_SUPPORT_LEGACY_GETDEVICE 1
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
#include "skia/include/effects/SkDiscretePathEffect.h"
#include "skia/include/core/SkDocument.h"
#include "skia/include/pathops/SkPathOps.h"

#if PLASK_OSX
#include "skia/include/ports/SkTypeface_mac.h"  // SkCreateTypefaceFromCTFont.
#endif

#if PLASK_GPUSKIA
#include "skia/include/core/SkSurface.h"
#include "skia/include/gpu/GrContext.h"
#include "skia/include/gpu/gl/GrGLInterface.h"
#endif

#if PLASK_SYPHON
#import <Syphon/Syphon.h>
#endif

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

#if PLASK_OSX
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

  // Our notification is registered globally, so a notification will be
  // broadcast even from other AVPlayer instances...
  if (![self.items containsObject:p]) return;

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

#endif  // PLASK_OSX

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


// Get the underlying data / size for an ArrayBuffer / ArrayBufferView.
bool GetTypedArrayBytes(
    v8::Local<v8::Value> value, void** data, intptr_t* size) {

  v8::Local<v8::ArrayBuffer> buffer;
  size_t offset = 0, length = 0;

  if (value->IsArrayBuffer()) {
    buffer = v8::Handle<v8::ArrayBuffer>::Cast(value);
    length = buffer->ByteLength();
  } else if (value->IsArrayBufferView()) {
    v8::Local<v8::ArrayBufferView> bv = v8::Local<v8::ArrayBufferView>::Cast(value);
    offset = bv->ByteOffset();
    length = bv->ByteLength();
    buffer = bv->Buffer();
  } else {
    return false;
  }

  v8::ArrayBuffer::Contents contents = buffer->GetContents();

  *data = reinterpret_cast<char*>(contents.Data()) + offset;
  *size = length;
  return true;
}

struct ScopedFree {
  ScopedFree(void* ptr) : ptr_(ptr) { }
  ~ScopedFree() { free(ptr_); }
  void* ptr_;
};

// Common routine shared for writing images from OpenGL or Skia.
void writeImageHelper(const v8::FunctionCallbackInfo<v8::Value>& args,
                      int width, int height, void* pixels, FIBITMAP* fb, bool flip) {
  const uint32_t rmask = SK_R32_MASK << SK_R32_SHIFT;
  const uint32_t gmask = SK_G32_MASK << SK_G32_SHIFT;
  const uint32_t bmask = SK_B32_MASK << SK_B32_SHIFT;

  if (args.Length() < 2)
    return v8_utils::ThrowError(isolate, "Wrong number of arguments.");

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

  if (!fb) {
    fb = FreeImage_ConvertFromRawBits(
        reinterpret_cast<BYTE*>(pixels),
        width, height, width * 4, 32,
        rmask, gmask, bmask, FALSE);
    if (!fb)
      return v8_utils::ThrowError(isolate, "Couldn't allocate FreeImage bitmap.");
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

    // TODO(deanm): Full metadata support, XMP with types, etc.
    if (opts->Has(v8::String::NewFromUtf8(isolate, "comment"))) {
      v8::String::Utf8Value val(opts->Get(v8::String::NewFromUtf8(isolate, "comment")));
      FITAG* tag = FreeImage_CreateTag();
      FreeImage_SetTagType(tag, FIDT_ASCII);
      FreeImage_SetTagKey(tag, "Comment");
      FreeImage_SetTagCount(tag, val.length());
      FreeImage_SetTagLength(tag, val.length());
      FreeImage_SetTagValue(tag, *val);
      // NOTE(deanm): If we want to support TIFFs then should use XMP.
      FreeImage_SetMetadata(FIMD_COMMENTS, fb, "Comment", tag);
      FreeImage_DeleteTag(tag);
    }
  }

  bool saved = true;
  if (flip)  saved = FreeImage_FlipVertical(fb);
  if (saved) saved = FreeImage_Save(format, fb, *filename, save_flags);
  FreeImage_Unload(fb);

  if (!saved)
    return v8_utils::ThrowError(isolate, "Failed to save png.");
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
    obj->DefineOwnProperty(
        isolate->GetCurrentContext(),
        v8::String::NewFromUtf8(isolate, "size"),
        v8::Integer::New(isolate, size),
        v8::ReadOnly).FromJust();
    obj->DefineOwnProperty(
        isolate->GetCurrentContext(),
        v8::String::NewFromUtf8(isolate, "type"),
        v8::Integer::NewFromUnsigned(isolate, type),
        v8::ReadOnly).FromJust();
    obj->DefineOwnProperty(
        isolate->GetCurrentContext(),
        v8::String::NewFromUtf8(isolate, "name"),
        v8::String::NewFromUtf8(isolate, name),
        v8::ReadOnly).FromJust();
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
    map.emplace(std::piecewise_construct,
      std::forward_as_tuple(name),
      std::forward_as_tuple(isolate, obj));
    return obj;
  }

  static v8::Handle<v8::Value> LookupFromName(
      v8::Isolate* isolate, GLuint name) {
    if (name != 0 && map.count(name) == 1)
      return PersistentToLocal(isolate, map.at(name));
    return v8::Null(isolate);
  }

  // Use to set the name to 0, when it is deleted, for example.
  static void ClearName(v8::Handle<v8::Value> value) {
    GLuint name = ExtractNameFromValue(value);
    if (name != 0) {
      if (map.count(name) == 1) {
        map.at(name).Reset();
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
DEFINE_NAME_MAPPED_CLASS(WebGLTransformFeedback)

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


#if PLASK_SYPHON
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
      METHOD_ENTRY( publishFrameTexture ),
      METHOD_ENTRY( bindToDrawFrameOfSize ),
      METHOD_ENTRY( unbindAndPublish ),
      METHOD_ENTRY( hasClients ),
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

  DEFINE_METHOD(bindToDrawFrameOfSize, 2)
    SyphonServer* server = ExtractSyphonServerPointer(args.Holder());
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
      METHOD_ENTRY( newFrameImage ),
      METHOD_ENTRY( isValid ),
      METHOD_ENTRY( hasNewFrame ),
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
#endif  // PLASK_SYPHON

// We can't do a nested define so just declare the constants as a static var.
#define WEBGL_CONSTANTS_EACH(name, val) \
  static const GLenum WEBGL_##name = val;
#include "webgl_constants.h"
#undef WEBGL_CONSTANTS_EACH

static const char* const kWebGLExtensions[] = {
  // https://www.khronos.org/registry/webgl/extensions/WEBGL_depth_texture/
  "WEBGL_depth_texture",
  // https://www.khronos.org/registry/webgl/extensions/OES_texture_float/
  "OES_texture_float",
  // https://www.khronos.org/registry/webgl/extensions/OES_standard_derivatives/
  "OES_standard_derivatives",
  // https://www.khronos.org/registry/webgl/extensions/EXT_shader_texture_lod/
  "EXT_shader_texture_lod",
};

// 10.33 Should Extension Macros be Globally Defined?
// RESOLUTION: The macros are defined globally.
static const char* const kWebGLSLPrefix =
  "#version 120\n"
  // https://www.khronos.org/registry/webgl/extensions/EXT_shader_texture_lod/
  "#define GL_EXT_shader_texture_lod 1\n"
  "#define texture2DLodEXT texture2DLod\n"
  "#define texture2DProjLodEXT texture2DProjLod\n"
  "#define textureCubeLodEXT textureCubeLod\n"
  "#define texture2DGradEXT texture2DGrad\n"
  "#define texture2DProjGradEXT texture2DProjGrad\n"
  "#define textureCubeGradEXT textureCubeGrad\n"
  // https://www.khronos.org/registry/webgl/extensions/OES_standard_derivatives/
  "#define GL_OES_standard_derivatives 1\n"
  "";

// NOTE: We do a memcpy so the overwrite needs to be the same length.
static const char* const kExtensionRewrites[] = {
  // https://www.khronos.org/registry/webgl/extensions/EXT_shader_texture_lod/
  "GL_EXT_shader_texture_lod", "GL_ARB_shader_texture_lod",
  // https://www.khronos.org/registry/webgl/extensions/OES_standard_derivatives/
  // Eat the GL_OES_standard_derivatives directive, just with another we have.
  "GL_OES_standard_derivatives", "GL_ARB_draw_buffers        ",
};

// Small rewriter, rewriting the string in place.  Does things like rewrite
// extension names to map from WebGL names to the native names.
static void RewriteWebGLSLtoGLSL(char* p, int len) {
  char prev = 0;
  int state = 0, state_before_cmt = 0;
  bool line_beginning = true;
  for ( ; len > 0; prev = *p++, --len) {
    char c = *p;

    if (c == '*' && prev == '/') {
      state_before_cmt = state;
      state = 1; continue;
    }
    if (c == '/' && prev == '/') {
      state_before_cmt = state;
      state = 2; continue;
    }

    // From GLSL ES 1.0.17
    //   "White space: the space character, horizontal tab, vertical tab, form
    //    feed, carriage-return, and line-feed."
    // NOTE: However, for preprocessor directives only space and horizonal tab.
    bool is_st = (c == ' ' || c == '\t');
    //bool is_ws = (is_st || c == '\v' || c == '\f' || c == '\r' || c == '\n');
    bool is_ws = (is_st || c == '\v' || c == '\f');
    bool is_nl = (c == '\r' || c == '\n');
    if (is_nl) line_beginning = true;

    switch (state) {
      case 0:
        // "Each number sign (#) can be preceded in its line only by spaces or
        //  horizontal tabs. It may also be followed by spaces and horizontal
        //  tabs, preceding the directive. Each directive is terminated by a
        //  new- line."
        if (line_beginning && c == '#') {
          state = 3; break;
        }
        break;
      case 1:  // Inside a /* */ comment.
        if (c == '/' && prev == '*') state = state_before_cmt;
        break;
      case 2:  // Inside a '//' line comment.
        if (c == '\r' || c == '\n') state = state_before_cmt;
        break;
      case 3:  // # found, check for extension
        if (is_st) break;  // # can be followed by space or tab.
        state = 0;
        if (len > 9 && memcmp(p, "extension", 9) == 0) {
          p += 8; state = 4;
        }
        break;
      case 4:  // #extension found, expect whitespace after for a proper token.
        // We also support something like #extension/**/BLAH, not sure if that
        // is proper in the grammar but probably via the tokenization process.
        state = (is_ws || prev != 'n') ? 5 : 0;
        break;
      case 5:
        // Keep eating whitespace, but preprocessor directives are terminated by a newline.
        if (line_beginning == true) {
          state = 0; break;
        }
        if (is_ws) break;
        for (int i = 0; i < arraysize(kExtensionRewrites); i += 2) {
          int elen = strlen(kExtensionRewrites[i]);
          if (len < elen) continue;
          if (memcmp(kExtensionRewrites[i], p, elen) == 0) {
            memcpy(p, kExtensionRewrites[i+1], elen);
            break;
          }
        }
        state = 0;
        break;
    }

    if (line_beginning && !is_nl && !is_st) line_beginning = false;
  }
}

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
    WebGLTypeWebGLTransformFeedback,
  };

  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &NSOpenGLContextWrapper::V8New);
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
#if PLASK_GPUSKIA
    instance->SetInternalFieldCount(3);  // gl context, SkSurface, and GrContext.
#else
    instance->SetInternalFieldCount(1);
#endif

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
#define WEBGL_CONSTANTS_EACH(name, val) \
      { #name, val },
#include "webgl_constants.h"
#undef WEBGL_CONSTANTS_EACH
    };

    static BatchedMethods methods[] = {
      METHOD_ENTRY( makeCurrentContext ),
      METHOD_ENTRY( pushAllState ),  // client and server state
      METHOD_ENTRY( popAllState ),   // client and server state
      METHOD_ENTRY( resetSkiaContext ),
      METHOD_ENTRY( setSwapInterval ),
      METHOD_ENTRY( writeImage ),

      METHOD_ENTRY( activeTexture ),
      METHOD_ENTRY( attachShader ),
      METHOD_ENTRY( bindAttribLocation ),
      METHOD_ENTRY( bindBuffer ),
      METHOD_ENTRY( bindFramebuffer ),
      METHOD_ENTRY( bindRenderbuffer ),
      METHOD_ENTRY( bindTexture ),
#if PLASK_WEBGL2
      METHOD_ENTRY( bindVertexArray ),
      METHOD_ENTRY( bindTransformFeedback ),
#endif
      METHOD_ENTRY( blendColor ),
      METHOD_ENTRY( blendEquation ),
      METHOD_ENTRY( blendEquationSeparate ),
      METHOD_ENTRY( blendFunc ),
      METHOD_ENTRY( blendFuncSeparate ),
      METHOD_ENTRY( bufferData ),
      METHOD_ENTRY( bufferSubData ),
      METHOD_ENTRY( checkFramebufferStatus ),
      METHOD_ENTRY( clear ),
      METHOD_ENTRY( clearColor ),
      METHOD_ENTRY( clearDepth ),
      METHOD_ENTRY( clearStencil ),
      METHOD_ENTRY( colorMask ),
      METHOD_ENTRY( compileShader ),
      // METHOD_ENTRY( copyTexImage2D ),
      // METHOD_ENTRY( copyTexSubImage2D ),
      METHOD_ENTRY( createBuffer ),
      METHOD_ENTRY( createFramebuffer ),
      METHOD_ENTRY( createProgram ),
      METHOD_ENTRY( createRenderbuffer ),
      METHOD_ENTRY( createShader ),
      METHOD_ENTRY( createTexture ),
#if PLASK_WEBGL2
      METHOD_ENTRY( createVertexArray ),
      METHOD_ENTRY( createTransformFeedback ),
#endif
      METHOD_ENTRY( cullFace ),
      METHOD_ENTRY( deleteBuffer ),
      METHOD_ENTRY( deleteFramebuffer ),
      METHOD_ENTRY( deleteProgram ),
      METHOD_ENTRY( deleteRenderbuffer ),
      METHOD_ENTRY( deleteShader ),
      METHOD_ENTRY( deleteTexture ),
#if PLASK_WEBGL2
      METHOD_ENTRY( deleteVertexArray ),
      METHOD_ENTRY( deleteTransformFeedback ),
#endif
      METHOD_ENTRY( depthFunc ),
      METHOD_ENTRY( depthMask ),
      METHOD_ENTRY( depthRange ),
      METHOD_ENTRY( detachShader ),
      METHOD_ENTRY( disable ),
      METHOD_ENTRY( disableVertexAttribArray ),
      METHOD_ENTRY( drawArrays ),
      METHOD_ENTRY( drawElements ),
#if PLASK_WEBGL2
      METHOD_ENTRY( vertexAttribDivisor ),
      METHOD_ENTRY( drawArraysInstanced ),
      METHOD_ENTRY( drawElementsInstanced ),
      METHOD_ENTRY( drawRangeElements ),
#endif
      METHOD_ENTRY( enable ),
      METHOD_ENTRY( enableVertexAttribArray ),
      METHOD_ENTRY( finish ),
      METHOD_ENTRY( flush ),
      METHOD_ENTRY( framebufferRenderbuffer ),
      METHOD_ENTRY( framebufferTexture2D ),
      METHOD_ENTRY( frontFace ),
      METHOD_ENTRY( generateMipmap ),
      METHOD_ENTRY( getActiveAttrib ),
      METHOD_ENTRY( getActiveUniform ),
      METHOD_ENTRY( getAttachedShaders ),
      METHOD_ENTRY( getAttribLocation ),
      METHOD_ENTRY( getParameter ),
      METHOD_ENTRY( getBufferParameter ),
      METHOD_ENTRY( getError ),
      METHOD_ENTRY( getFramebufferAttachmentParameter ),
      METHOD_ENTRY( getProgramParameter ),
      METHOD_ENTRY( getProgramInfoLog ),
      METHOD_ENTRY( getRenderbufferParameter ),
      METHOD_ENTRY( getShaderParameter ),
      METHOD_ENTRY( getShaderInfoLog ),
      METHOD_ENTRY( getShaderSource ),
      METHOD_ENTRY( getTexParameter ),
      METHOD_ENTRY( getUniform ),
      METHOD_ENTRY( getUniformLocation ),
      METHOD_ENTRY( getVertexAttrib ),
      METHOD_ENTRY( getVertexAttribOffset ),
      METHOD_ENTRY( hint ),
      METHOD_ENTRY( isBuffer ),
      METHOD_ENTRY( isEnabled ),
      METHOD_ENTRY( isFramebuffer ),
      METHOD_ENTRY( isProgram ),
      METHOD_ENTRY( isRenderbuffer ),
      METHOD_ENTRY( isShader ),
      METHOD_ENTRY( isTexture ),
#if PLASK_WEBGL2
      METHOD_ENTRY( isVertexArray ),
      METHOD_ENTRY( isTransformFeedback ),
#endif
      METHOD_ENTRY( lineWidth ),
      METHOD_ENTRY( linkProgram ),
      METHOD_ENTRY( pixelStorei ),
      METHOD_ENTRY( polygonOffset ),
      METHOD_ENTRY( readPixels ),
      METHOD_ENTRY( renderbufferStorage ),
#if PLASK_WEBGL2
      METHOD_ENTRY( renderbufferStorageMultisample ),
#endif
      METHOD_ENTRY( sampleCoverage ),
      METHOD_ENTRY( scissor ),
      METHOD_ENTRY( shaderSource ),
      METHOD_ENTRY( shaderSourceRaw ),  // Without WebGL rewriting.
#if PLASK_WEBGL2
      METHOD_ENTRY( beginTransformFeedback ),
      METHOD_ENTRY( endTransformFeedback ),
      METHOD_ENTRY( pauseTransformFeedback ),
      METHOD_ENTRY( resumeTransformFeedback ),
      METHOD_ENTRY( transformFeedbackVaryings ),
      METHOD_ENTRY( getTransformFeedbackVarying ),
      METHOD_ENTRY( bindBufferBase ),
      METHOD_ENTRY( bindBufferRange ),
      METHOD_ENTRY( getBufferSubData ),
#endif
      METHOD_ENTRY( stencilFunc ),
      METHOD_ENTRY( stencilFuncSeparate ),
      METHOD_ENTRY( stencilMask ),
      METHOD_ENTRY( stencilMaskSeparate ),
      METHOD_ENTRY( stencilOp ),
      METHOD_ENTRY( stencilOpSeparate ),
      METHOD_ENTRY( texImage2D ),
      METHOD_ENTRY( texImage2DSkCanvasB ),
      METHOD_ENTRY( compressedTexImage2D ),
      METHOD_ENTRY( texParameterf ),
      METHOD_ENTRY( texParameteri ),
      METHOD_ENTRY( texSubImage2D ),
      METHOD_ENTRY( uniform1f ),
      METHOD_ENTRY( uniform1fv ),
      METHOD_ENTRY( uniform1i ),
      METHOD_ENTRY( uniform1iv ),
      METHOD_ENTRY( uniform2f ),
      METHOD_ENTRY( uniform2fv ),
      METHOD_ENTRY( uniform2i ),
      METHOD_ENTRY( uniform2iv ),
      METHOD_ENTRY( uniform3f ),
      METHOD_ENTRY( uniform3fv ),
      METHOD_ENTRY( uniform3i ),
      METHOD_ENTRY( uniform3iv ),
      METHOD_ENTRY( uniform4f ),
      METHOD_ENTRY( uniform4fv ),
      METHOD_ENTRY( uniform4i ),
      METHOD_ENTRY( uniform4iv ),
      METHOD_ENTRY( uniformMatrix2fv ),
      METHOD_ENTRY( uniformMatrix3fv ),
      METHOD_ENTRY( uniformMatrix4fv ),
      METHOD_ENTRY( useProgram ),
      METHOD_ENTRY( validateProgram ),
      METHOD_ENTRY( vertexAttrib1f ),
      //METHOD_ENTRY( vertexAttrib1fv ),
      METHOD_ENTRY( vertexAttrib2f ),
      //METHOD_ENTRY( vertexAttrib2fv ),
      METHOD_ENTRY( vertexAttrib3f ),
      //METHOD_ENTRY( vertexAttrib3fv ),
      METHOD_ENTRY( vertexAttrib4f ),
      //METHOD_ENTRY( vertexAttrib4fv ),
      METHOD_ENTRY( vertexAttribPointer ),
      METHOD_ENTRY( viewport ),
      METHOD_ENTRY( getSupportedExtensions ),
      METHOD_ENTRY( getExtension ),
      // Plask-specific, not in WebGL.  From ARB_draw_buffers.
#if PLASK_WEBGL2
      METHOD_ENTRY( drawBuffers ),
      METHOD_ENTRY( blitFramebuffer ),
#endif
      METHOD_ENTRY( drawSkCanvas ),
#if PLASK_SYPHON
      METHOD_ENTRY( createSyphonServer ),
      METHOD_ENTRY( createSyphonClient ),
#endif
      METHOD_ENTRY( blit ),
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

#if PLASK_GPUSKIA
  static SkSurface* ExtractSkSurface(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<SkSurface*>(obj->GetAlignedPointerFromInternalField(1));
  }

  static GrContext* ExtractGrContext(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<GrContext*>(obj->GetAlignedPointerFromInternalField(2));
  }
#endif

 private:
  static void V8New(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    unsigned int multisample = args[0]->Uint32Value();

    NSOpenGLContext* context = NULL;

#if PLASK_OSX
    NSOpenGLPixelFormatAttribute attrs[] = {
        NSOpenGLPFAColorSize, 24,
        NSOpenGLPFADepthSize, 16,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAAccelerated,
        NSOpenGLPFAStencilSize, 8,
        // Truncate here for non-multisampling
        NSOpenGLPFAMultisample,
        NSOpenGLPFASampleBuffers, 1,
        NSOpenGLPFASamples, multisample,
        NSOpenGLPFANoRecovery,
        0
    };

    if (!multisample)
      attrs[8] = 0;

    NSOpenGLPixelFormat* format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    context = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
    [format release];

    [context makeCurrentContext];

    if (multisample) {
      glEnable(GL_MULTISAMPLE_ARB);
      glHint(GL_MULTISAMPLE_FILTER_HINT_NV, GL_NICEST);
    }

    // Point sprite support.
    glEnable(GL_POINT_SPRITE);
    glEnable(GL_VERTEX_PROGRAM_POINT_SIZE);
#endif  // PLASK_OSX

    return args.This()->SetAlignedPointerInInternalField(0, context);
  }

  static void makeCurrentContext(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSOpenGLContext* context = ExtractContextPointer(args.Holder());
#if PLASK_OSX
    [context makeCurrentContext];
#endif  // PLASK_OSX
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(pushAllState, 0)
    glPushAttrib(GL_ALL_ATTRIB_BITS);
    glPushClientAttrib(GL_CLIENT_ALL_ATTRIB_BITS);
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(popAllState, 0)
    glPopClientAttrib(); glPopAttrib();
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(resetSkiaContext, 0)
    ExtractGrContext(args.Holder())->resetContext();
    return args.GetReturnValue().SetUndefined();
  }

#if PLASK_SYPHON
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
#endif

  static void blit(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSOpenGLContext* context = ExtractContextPointer(args.Holder());
#if PLASK_OSX
    [context flushBuffer];
#endif
    return args.GetReturnValue().SetUndefined();
  }

  // void setSwapInterval(int interval)
  //
  // Sets the swap interval, aka vsync.  Ex: `1` for vsync and `0` for no sync.
  // This will normally be handled for you by the simpleWindow `vsync` setting.
  static void setSwapInterval(const v8::FunctionCallbackInfo<v8::Value>& args) {
    NSOpenGLContext* context = ExtractContextPointer(args.Holder());
    GLint interval = args[0]->Int32Value();
#if PLASK_OSX
    [context setValues:&interval forParameter:NSOpenGLCPSwapInterval];
#endif  // PLASK_OSX
    return args.GetReturnValue().SetUndefined();
  }

  // TODO(deanm): Share more code with SkCanvas#writeImage.

  // void writeImage(filetype, filename, opts)
  static void writeImage(const v8::FunctionCallbackInfo<v8::Value>& args) {
    GLint viewport[4];
    glGetIntegerv(GL_VIEWPORT, viewport);
    int width  = viewport[2];
    int height = viewport[3];

    int buffer_type = args[3]->Int32Value();

    if (buffer_type == 0) {  // RGBA color buffer.
      void* pixels = malloc(width * height * 4);
      ScopedFree freepixels(pixels);
      glReadPixels(0, 0, width, height, GL_BGRA, GL_UNSIGNED_BYTE, pixels);
      writeImageHelper(args, width, height, pixels, NULL, false);
    } else {  // Floating point depth buffer
      FIBITMAP* fb = FreeImage_AllocateT(FIT_FLOAT, width, height);  // Helper will dealloc
      if (!fb)
        return v8_utils::ThrowError(isolate, "Couldn't allocate FreeImage bitmap.");
      // Read into the FreeImage allocated buffer.
      glReadPixels(0, 0, width, height,
                   GL_DEPTH_COMPONENT, GL_FLOAT, FreeImage_GetBits(fb));
      writeImageHelper(args, width, height, NULL, fb, false);
    }

    return;
  }

  // void activeTexture(GLenum texture)
  DEFINE_METHOD(activeTexture, 1)
    glActiveTexture(args[0]->Uint32Value());
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

#ifdef PLASK_WEBGL2
  // void bindVertexArray(WebGLVertexArrayObject? vertexArray)
  DEFINE_METHOD(bindVertexArray, 1)
    // NOTE: ExtractNameFromValue handles null.
    if (!args[0]->IsNull() && !WebGLVertexArrayObject::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    glBindVertexArrayAPPLE(WebGLVertexArrayObject::ExtractNameFromValue(args[0]));
    return args.GetReturnValue().SetUndefined();
  }

  // void bindTransformFeedback (GLenum target, WebGLTransformFeedback? transformFeedback)
  DEFINE_METHOD(bindTransformFeedback, 2)
    // "If transformFeedback is null, the default transform feedback object
    // provided by the context is bound."
    // NOTE(deanm): For now Plask only ever has and uses the default object,
    // the feedback object related APIs are basically just no-ops.
    return args.GetReturnValue().SetUndefined();
    //return v8_utils::ThrowError(isolate, "Unimplemented.");
  }
#endif  // PLASK_WEBGL2

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
  DEFINE_METHOD(blendEquation, 1)
    glBlendEquation(args[0]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void blendEquationSeparate(GLenum modeRGB, GLenum modeAlpha)
  DEFINE_METHOD(blendEquationSeparate, 2)
    glBlendEquationSeparate(args[0]->Uint32Value(), args[1]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }


  // void blendFunc(GLenum sfactor, GLenum dfactor)
  DEFINE_METHOD(blendFunc, 2)
    glBlendFunc(args[0]->Uint32Value(), args[1]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void blendFuncSeparate(GLenum srcRGB, GLenum dstRGB,
  //                        GLenum srcAlpha, GLenum dstAlpha)
  DEFINE_METHOD(blendFuncSeparate, 4)
    glBlendFuncSeparate(args[0]->Uint32Value(), args[1]->Uint32Value(),
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
  DEFINE_METHOD(checkFramebufferStatus, 1)
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate,
        glCheckFramebufferStatus(args[0]->Uint32Value())));
  }

  // void clear(GLbitfield mask)
  DEFINE_METHOD(clear, 1)
    glClear(args[0]->Uint32Value());
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

#if PLASK_WEBGL2
  // WebGLVertexArrayObject? createVertexArray()
  static void createVertexArray(const v8::FunctionCallbackInfo<v8::Value>& args) {
    GLuint vao;
    glGenVertexArraysAPPLE(1, &vao);
    return args.GetReturnValue().Set(WebGLVertexArrayObject::NewFromName(vao));
  }

  // WebGLTransformFeedback? createTransformFeedback()
  static void createTransformFeedback(const v8::FunctionCallbackInfo<v8::Value>& args) {
    // NOTE(deanm): This is a bit tricky, trying to implement transform feedback
    // without requiring moving to OpenGL 3.0.  Can probably do it half way,
    // and just try to use GL_EXT_transform_feedback.
    return args.GetReturnValue().Set(WebGLTransformFeedback::NewFromName(0));
    //return v8_utils::ThrowError(isolate, "Unimplemented.");
  }
#endif  // PLASK_WEBGL2

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

#if PLASK_WEBGL2
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

  // void deleteTransformFeedback(WebGLTransformFeedback? vertexArray)
  DEFINE_METHOD(deleteTransformFeedback, 1)
    return args.GetReturnValue().SetUndefined();
    //return v8_utils::ThrowError(isolate, "Unimplemented.");
  }
#endif  // PLASK_WEBGL2

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

#if PLASK_WEBGL2
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
#endif  // PLASK_WEBGL2

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

  template <class T>
  static void getNameMappedParameter(
      v8::Isolate* isolate,
      const v8::FunctionCallbackInfo<v8::Value>& args,
      unsigned long pname) {
    int value;
    glGetIntegerv(pname, &value);
    GLuint name = static_cast<unsigned int>(value);
    if (name == 0)
      return args.GetReturnValue().SetNull();

    std::map<GLuint, v8::UniquePersistent<v8::Value> >& map = T::Map();
    if (map.count(name) == 1)  // Plask created, already have the wrapper.
      return args.GetReturnValue().Set(PersistentToLocal(isolate, map.at(name)));

    // In order to interface with external OpenGL code on our context, like
    // GPU accelerated Skia, it is possible we might encounter one of their
    // buffers when querying the mapping, it should be better to just create
    // a wrapper for it than to return NULL as if there wasn't a mapping.
    return args.GetReturnValue().Set(T::NewFromName(name));
  }

  // any getParameter(GLenum pname)
  DEFINE_METHOD(getParameter, 1)
    unsigned long pname = args[0]->Uint32Value();

    switch (pname) {
      case WEBGL_UNPACK_PREMULTIPLY_ALPHA_WEBGL:
        return args.GetReturnValue().Set(true);  // Always using premultiplied.
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
        return getNameMappedParameter<WebGLBuffer>(isolate, args, pname);
      case WebGLTypeWebGLFramebuffer:
        return getNameMappedParameter<WebGLFramebuffer>(isolate, args, pname);
      case WebGLTypeWebGLProgram:
        return getNameMappedParameter<WebGLProgram>(isolate, args, pname);
      case WebGLTypeWebGLRenderbuffer:
        return getNameMappedParameter<WebGLRenderbuffer>(isolate, args, pname);
      case WebGLTypeWebGLTexture:
        return getNameMappedParameter<WebGLTexture>(isolate, args, pname);
      case WebGLTypeWebGLVertexArrayObject:
        return getNameMappedParameter<WebGLVertexArrayObject>(isolate, args, pname);
      case WebGLTypeWebGLTransformFeedback:
        return getNameMappedParameter<WebGLTransformFeedback>(isolate, args, pname);
      case WebGLTypeInvalid:
        break;  // fall out.
    }

    return args.GetReturnValue().SetUndefined();
  }

  // any getBufferParameter(GLenum target, GLenum pname)
  DEFINE_METHOD(getBufferParameter, 2)
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

#if PLASK_WEBGL2
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

  // GLboolean isTransformFeedback(WebGLTransformFeedback? vertexArray)
  DEFINE_METHOD(isTransformFeedback, 1)
    return v8_utils::ThrowError(isolate, "Unimplemented.");
  }
#endif  // PLASK_WEBGL2

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
    GLenum pname = args[0]->Uint32Value();
    GLint  param = args[1]->Int32Value();
    // Catch unpack just so that we don't get a glError for an unknown enum,
    // and also print a message if you try to set it to unpremultiply.
    if (pname == WEBGL_UNPACK_PREMULTIPLY_ALPHA_WEBGL) {
      if (param == GL_FALSE) {
        fprintf(stderr, "Warning: Setting UNPACK_PREMULTIPLY_ALPHA_WEBGL to "
                        "unpremultiplied alpha but Plask is too lazy for that, "
                        "use premultiplied alpha, it is better, I promise.\n");
        fflush(stderr);
      }
    } else {
      glPixelStorei(pname, param);
    }
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

    GLvoid* data = NULL;
    GLsizeiptr size = 0;

    if (!GetTypedArrayBytes(args[6], &data, &size))
      return v8_utils::ThrowError(isolate, "Data must be a TypedArray.");

    // TODO(deanm):  From the spec (requires synthesizing gl errors):
    //   If pixels is non-null, but is not large enough to retrieve all of the
    //   pixels in the specified rectangle taking into account pixel store
    //   modes, an INVALID_OPERATION value is generated.
    if (size < width*height*4)
      return v8_utils::ThrowError(isolate, "TypedArray buffer too small.");

    glReadPixels(x, y, width, height, format, type, data);

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

#if PLASK_WEBGL2
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
#endif  // PLASK_WEBGL2

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

  // void shaderSourceRaw(WebGLShader shader, DOMString source)
  DEFINE_METHOD(shaderSourceRaw, 2)
    if (!WebGLShader::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint shader = WebGLShader::ExtractNameFromValue(args[0]);

    v8::String::Utf8Value data(args[1]);
    const GLchar* strs[] = { *data };
    glShaderSource(shader, 1, strs, NULL);
    return args.GetReturnValue().SetUndefined();
  }

  // void shaderSource(WebGLShader shader, DOMString source)
  DEFINE_METHOD(shaderSource, 2)
    if (!WebGLShader::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint shader = WebGLShader::ExtractNameFromValue(args[0]);

    v8::String::Utf8Value data(args[1]);

    // The string data is allocated in V8's zone, should be okay to modify it.
    RewriteWebGLSLtoGLSL(*data, data.length());

    const GLchar* strs[] = { kWebGLSLPrefix, *data };
    glShaderSource(shader, 2, strs, NULL);
    return args.GetReturnValue().SetUndefined();
  }

#if PLASK_WEBGL2
  // void beginTransformFeedback(GLenum primitiveMode)
  DEFINE_METHOD(beginTransformFeedback, 1)
    glBeginTransformFeedbackEXT(args[0]->Uint32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void endTransformFeedback()
  DEFINE_METHOD(endTransformFeedback, 0)
    glEndTransformFeedbackEXT();
    return args.GetReturnValue().SetUndefined();
  }

  // void pauseTransformFeedback()
  DEFINE_METHOD(pauseTransformFeedback, 0)
    return v8_utils::ThrowError(isolate, "Unimplemented.");
  }

  // void resumeTransformFeedback()
  DEFINE_METHOD(resumeTransformFeedback, 0)
    return v8_utils::ThrowError(isolate, "Unimplemented.");
  }

  // void transformFeedbackVaryings(WebGLProgram? program,
  //                                sequence<DOMString> varyings,
  //                                GLenum bufferMode)
  DEFINE_METHOD(transformFeedbackVaryings, 3)
    if (!WebGLProgram::HasInstance(isolate, args[0]))
      return v8_utils::ThrowTypeError(isolate, "Type error");
    if (!args[1]->IsArray())
      return v8_utils::ThrowError(isolate, "Sequence must be an Array.");

    GLuint program = WebGLProgram::ExtractNameFromValue(args[0]);
    v8::Local<v8::Array> arr = v8::Local<v8::Array>::Cast(args[1]);
    GLenum buffer_mode = args[2]->Uint32Value();

    uint32_t length = arr->Length();
    v8::String::Utf8Value** varyings = new v8::String::Utf8Value*[length];
    char** varyingc = new char*[length];
    for (uint32_t i = 0; i < length; ++i) {
      varyings[i] = new v8::String::Utf8Value(arr->Get(i));
      varyingc[i] = **varyings[i];
    }

    glTransformFeedbackVaryingsEXT(program, length, varyingc, buffer_mode);

    delete[] varyingc;
    for (uint32_t i = 0; i < length; ++i) delete varyings[i];
    delete[] varyings;

    return args.GetReturnValue().SetUndefined();
  }

  // WebGLActiveInfo? getTransformFeedbackVarying(WebGLProgram? program, GLuint index)
  DEFINE_METHOD(getTransformFeedbackVarying, 2)
    return v8_utils::ThrowError(isolate, "Unimplemented.");
  }

  // void bindBufferBase(GLenum target, GLuint index, WebGLBuffer? buffer)
  DEFINE_METHOD(bindBufferBase, 3)
    // NOTE(deanm): Don't know if the NULL handling is right here, can't tell
    // from the spec or the OpenGL docs if there should be unbinding behavior.
    if (!args[1]->IsNull() && !WebGLBuffer::HasInstance(isolate, args[2]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint buffer = WebGLBuffer::ExtractNameFromValue(args[2]);
    glBindBufferBaseEXT(args[0]->Uint32Value(), args[1]->Uint32Value(), buffer);
    return args.GetReturnValue().SetUndefined();
  }

  // void bindBufferRange(GLenum target, GLuint index, WebGLBuffer? buffer,
  //                      GLintptr offset, GLsizeiptr size)
  DEFINE_METHOD(bindBufferRange, 5)
    // NOTE(deanm): Don't know if the NULL handling is right here, can't tell
    // from the spec or the OpenGL docs if there should be unbinding behavior.
    if (!args[1]->IsNull() && !WebGLBuffer::HasInstance(isolate, args[2]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    GLuint buffer = WebGLBuffer::ExtractNameFromValue(args[2]);
    glBindBufferRangeEXT(args[0]->Uint32Value(), args[1]->Uint32Value(), buffer,
                         args[3]->Int32Value(), args[4]->Int32Value());
    return args.GetReturnValue().SetUndefined();
  }

  // void getBufferSubData(GLenum target, GLintptr offset, ArrayBuffer? returnedData)
  DEFINE_METHOD(getBufferSubData, 3)
    // "If returnedData is null then an INVALID_VALUE error is generated."
    if (args[2]->IsNull()) return args.GetReturnValue().SetUndefined();

    void* data;
    intptr_t size = 0;

    if (!args[2]->IsObject() || !GetTypedArrayBytes(args[2], &data, &size))
      return v8_utils::ThrowError(isolate, "Data must be a TypedArray.");

    GLenum target = args[0]->Uint32Value();
    GLintptr offset = args[1]->IntegerValue();

    GLboolean was_okay = false;

    while (!was_okay) {  // This loop seems like a horrible idea...
      //void* map = glMapBufferRange(target, offset, size, GL_MAP_READ_BIT);  // GL3
      void* map = glMapBuffer(target, GL_READ_ONLY);  // GL2
      if (!map) return args.GetReturnValue().SetUndefined();

      //memcpy(data, map, size);
      memcpy(data, reinterpret_cast<char*>(map) + offset, size);

      // "When a data store is unmapped, the pointer to its data store becomes
      //  invalid. glUnmapBuffer returns GL_TRUE unless the data store contents
      //  have become corrupt during the time the data store was mapped. This
      //  can occur for system-specific reasons that affect the availability of
      //  graphics memory, such as screen mode changes. In such situations,
      //  GL_FALSE is returned and the data store contents are undefined. An
      //  application must detect this rare condition and reinitialize the data
      //  store."
      was_okay = glUnmapBuffer(target);
    }

    return args.GetReturnValue().SetUndefined();
  }
#endif  // PLASK_WEBGL2

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

  // void compressedTexImage2D(GLenum target, GLint level, GLenum internalformat,
  //                           GLsizei width, GLsizei height, GLint border,
  //                           ArrayBufferView data)
  DEFINE_METHOD(compressedTexImage2D, 7)
    GLvoid* data = NULL;
    GLsizeiptr size = 0;  // FIXME use size

    if (!args[6]->IsNull()) {
      // TODO(deanm): Check size / format.  For now just use it correctly.
      if (!GetTypedArrayBytes(args[6], &data, &size))
        return v8_utils::ThrowError(isolate, "Data must be a TypedArray.");
    }

    // TODO(deanm): Support more than just the zero initialization case.
    glCompressedTexImage2D(args[0]->Uint32Value(),  // target
                           args[1]->Int32Value(),   // level
                           args[2]->Int32Value(),   // internalFormat
                           args[3]->Int32Value(),   // width
                           args[4]->Int32Value(),   // height
                           args[5]->Int32Value(),   // border
                           size,                    // size
                           data);                   // data
    return args.GetReturnValue().SetUndefined();
  }

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

  // sequence<DOMString>? getSupportedExtensions()
  DEFINE_METHOD(getSupportedExtensions, 0)
    v8::Local<v8::Array> res = v8::Array::New(isolate, arraysize(kWebGLExtensions));
    for (size_t i = 0; i < arraysize(kWebGLExtensions); ++i) {
      res->Set(v8::Integer::New(isolate, i),
               v8::String::NewFromUtf8(isolate, kWebGLExtensions[i]));
    }

    return args.GetReturnValue().Set(res);
  }

  // NOTE(deanm): Extensions should actually return a new object that just has
  // the methods and constants for the extension.  This would require creating
  // some new wrapper objects with the gl context embedded, which is just a
  // little bit cumbersome.  Instead we just return the main OpenGL object,
  // which will have the extension constants and methods, but also everything
  // else.  Hopefully this doesn't cause too much trouble.

  // object? getExtension(DOMString name)
  DEFINE_METHOD(getExtension, 1)
    v8::String::Utf8Value utf8(args[0]);
    for (size_t i = 0; i < arraysize(kWebGLExtensions); ++i) {
      if (strcasecmp(*utf8, kWebGLExtensions[i]) == 0)  // case insensitive.
        return args.GetReturnValue().Set(args.Holder());  // self
    }
    return args.GetReturnValue().SetNull();
  }

#if PLASK_WEBGL2
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
#endif  // PLASK_WEBGL2

#if PLASK_WEBGL2
  // void blitFramebuffer(GLint srcX0, GLint srcY0, GLint srcX1, GLint srcY1,
  //                      GLint dstX0, GLint dstY0, GLint dstX1, GLint dstY1,
  //                      GLbitfield mask, GLenum filter)
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
#endif  // PLASK_WEBGL2
};


class NSWindowWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &NSWindowWrapper::V8New);

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    ft->Set(v8::String::NewFromUtf8(isolate, "screensInfo"),
             v8::FunctionTemplate::New(isolate, screensInfo));

    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // NSWindow

    // Configure the template...
    static BatchedConstants constants[] = {
      { "kValue", 12 },
    };

    static BatchedMethods methods[] = {
      METHOD_ENTRY( mouseLocationOutsideOfEventStream ),
      METHOD_ENTRY( setAcceptsMouseMovedEvents ),
      METHOD_ENTRY( setAcceptsFileDrag ),
      METHOD_ENTRY( setEventCallback ),
      METHOD_ENTRY( setTitle ),
      METHOD_ENTRY( setFrameTopLeftPoint ),
      METHOD_ENTRY( center ),
      METHOD_ENTRY( hideCursor ),
      METHOD_ENTRY( unhideCursor ),
      METHOD_ENTRY( setCursor ),
      METHOD_ENTRY( pushCursor ),
      METHOD_ENTRY( popCursor ),
      METHOD_ENTRY( setCursorPosition ),
      METHOD_ENTRY( warpCursorPosition ),
      METHOD_ENTRY( associateMouse ),
      METHOD_ENTRY( hide ),
      METHOD_ENTRY( show ),
      METHOD_ENTRY( screenSize ),
      METHOD_ENTRY( setFullscreen ),
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

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

 private:
  DEFINE_METHOD(V8New, 8)
    if (!args.IsConstructCall())
      return v8_utils::ThrowTypeError(isolate, kMsgNonConstructCall);

    uint32_t window_type = args[0]->Uint32Value();
    uint32_t bwidth = args[1]->Uint32Value();
    uint32_t bheight = args[2]->Uint32Value();
    bool multisample = args[3]->BooleanValue();
    int display = args[4]->Int32Value();
    bool borderless = args[5]->BooleanValue();
    bool fullscreen = args[6]->BooleanValue();
    uint32_t dpi_factor = args[7]->Uint32Value();

#if PLASK_GPUSKIA
    if (window_type != 1 && window_type != 2)
#else
    if (window_type != 1)
#endif
      return v8_utils::ThrowError(isolate, "Unsupported window type.");

    bool use_highdpi = false;
    uint32_t width = bwidth;
    uint32_t height = bheight;

#if PLASK_OSX
    NSScreen* screen = [NSScreen mainScreen];
    NSArray* screens = [NSScreen screens];

    if (display < [screens count]) {
      screen = [screens objectAtIndex:display];
      NSLog(@"Using alternate screen: %@", screen);
    }

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

    v8::Local<v8::FunctionTemplate> gl_cls = v8::Local<v8::FunctionTemplate>::New(
        isolate, NSOpenGLContextWrapper::GetTemplate(isolate));
    v8::Local<v8::Value> js_multisample =
        v8::Integer::NewFromUnsigned(isolate, multisample ? 4 : 0);
    v8::Local<v8::Object> gl = gl_cls->GetFunction()->NewInstance(1, &js_multisample);

    NSOpenGLContext* context = NSOpenGLContextWrapper::ExtractContextPointer(gl);

    NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0,
                                                            width, height)];
    if (use_highdpi)
      [view setWantsBestResolutionOpenGLSurface:YES];
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

#endif  // PLASK_OSX

    // NOTE(deanm): I assume we want the real (highdpi) resolution here.
    // There is some discussion about this at:
    //   https://bugzilla.mozilla.org/show_bug.cgi?id=780361
    // readonly attribute GLsizei drawingBufferWidth;
    gl->DefineOwnProperty(
        isolate->GetCurrentContext(),
        v8::String::NewFromUtf8(isolate, "drawingBufferWidth"),
        v8::Integer::New(isolate, bwidth),
        v8::ReadOnly).FromJust();
    // readonly attribute GLsizei drawingBufferHeight;
    gl->DefineOwnProperty(
        isolate->GetCurrentContext(),
        v8::String::NewFromUtf8(isolate, "drawingBufferHeight"),
        v8::Integer::New(isolate, bheight),
        v8::ReadOnly).FromJust();

    args.This()->DefineOwnProperty(
        isolate->GetCurrentContext(),
        v8::String::NewFromUtf8(isolate, "context"),
        gl).FromJust();

#if PLASK_GPUSKIA
    SkSurface* sk_surface = NULL;
    GrContext* gr_context = NULL;

    if (window_type == 2) {  // OpenGL window with a Skia GPU canvas attached.
      // Save pre-Skia state in case the caller wants to restore it.
      glPushAttrib(GL_ALL_ATTRIB_BITS);
      glPushClientAttrib(GL_CLIENT_ALL_ATTRIB_BITS);
      const GrGLInterface* gr_native_interface = GrGLCreateNativeInterface();
      if (!gr_native_interface->validate())
        return v8_utils::ThrowError(isolate, "Skia GL Native Interface didn't validate.");
      GrGLInterface* gr_interface = GrGLInterface::NewClone(gr_native_interface);
      if (!gr_interface->validate())
        return v8_utils::ThrowError(isolate, "Skia GL Interface didn't validate.");
      gr_context = GrContext::Create(kOpenGL_GrBackend, (intptr_t)gr_interface);
      GrBackendRenderTargetDesc rt_desc;
      rt_desc.fWidth = bwidth; rt_desc.fHeight = bheight;
      rt_desc.fConfig = kSkia8888_GrPixelConfig;
      rt_desc.fRenderTargetHandle = 0;
      rt_desc.fOrigin = kBottomLeft_GrSurfaceOrigin;
      rt_desc.fSampleCnt = multisample ? 4 : 0;
      rt_desc.fStencilBits = 8;

      GrRenderTarget* gr_rt = gr_context->textureProvider()->wrapBackendRenderTarget(rt_desc);
      sk_surface = SkSurface::NewRenderTargetDirect(gr_rt);
    }

    gl->SetAlignedPointerInInternalField(1, sk_surface);
    gl->SetAlignedPointerInInternalField(2, gr_context);
#endif

#if PLASK_OSX
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
#endif
  }

  // object[ ] screensInfo()
  //
  // Returns an array of objects representing info about each screen.  The
  // objects have {id: int, width: float, height: float, highdpi: float}.
  DEFINE_METHOD(screensInfo, 0)  // static method on NSWindow.
    v8::Local<v8::Array> res = v8::Array::New(isolate);
#if PLASK_OSX
    NSArray* screens = [NSScreen screens];
    int num_screens = [screens count];
    for (int i = 0; i < num_screens; ++i) {
      NSScreen* screen = [screens objectAtIndex:i];
      NSRect frame = [screen frame];
      float highdpi = [screen respondsToSelector:@selector(backingScaleFactor)] ?
          [screen backingScaleFactor] : 1;
      v8::Local<v8::Object> info = v8::Object::New(isolate);
      info->Set(v8::String::NewFromUtf8(isolate, "id"),
                v8::Integer::New(isolate, i));
      info->Set(v8::String::NewFromUtf8(isolate, "width"),
                v8::Number::New(isolate, frame.size.width));
      info->Set(v8::String::NewFromUtf8(isolate, "height"),
                v8::Number::New(isolate, frame.size.height));
      info->Set(v8::String::NewFromUtf8(isolate, "highdpi"),
                v8::Number::New(isolate, highdpi));
      res->Set(i, info);
    }
#endif  // PLASK_OSX
    return args.GetReturnValue().Set(res);
  }

  static void mouseLocationOutsideOfEventStream(
      const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
    v8::Local<v8::Object> res = v8::Object::New(isolate);
#if PLASK_OSX
    NSPoint pos = [window mouseLocationOutsideOfEventStream];
    res->Set(v8::String::NewFromUtf8(isolate, "x"), v8::Number::New(isolate, pos.x));
    res->Set(v8::String::NewFromUtf8(isolate, "y"), v8::Number::New(isolate, pos.y));
#endif  // PLASK_OSX
    return args.GetReturnValue().Set(res);
  }

  static void setAcceptsMouseMovedEvents(
      const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
#if PLASK_OSX
    [window setAcceptsMouseMovedEvents:args[0]->BooleanValue()];
#endif  // PLASK_OSX
    return args.GetReturnValue().SetUndefined();
  }

  static void setAcceptsFileDrag(
      const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
#if PLASK_OSX
    if (args[0]->BooleanValue()) {
      [window registerForDraggedTypes:
          [NSArray arrayWithObject:NSFilenamesPboardType]];
    } else {
      [window unregisterDraggedTypes];
    }
#endif  // PLASK_OSX
    return args.GetReturnValue().SetUndefined();
  }

  // You should only really call this once, it's a pretty raw function.
  static void setEventCallback(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (args.Length() != 1 || !args[0]->IsFunction())
      return v8_utils::ThrowError(isolate, "Incorrect invocation of setEventCallback.");
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
#if PLASK_OSX
    [window setEventCallbackWithHandle:v8::Handle<v8::Function>::Cast(args[0])];
#endif  // PLASK_OSX
    return args.GetReturnValue().SetUndefined();
  }

  // void setTitle(string title)
  //
  // Sets the title shown in the frame at the top of the window.
  static void setTitle(const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
    v8::String::Utf8Value title(args[0]);
#if PLASK_OSX
    [window setTitle:[NSString stringWithUTF8String:*title]];
#endif  // PLASK_OSX
    return args.GetReturnValue().SetUndefined();
  }
  DEFINE_METHOD(setFrameTopLeftPoint, 2)
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
#if PLASK_OSX
    [window setFrameTopLeftPoint:NSMakePoint(args[0]->NumberValue(),
                                             args[1]->NumberValue())];
#endif  // PLASK_OSX
    return args.GetReturnValue().SetUndefined();
  }

  // void center()
  //
  // Position the window in the center of the screen.
  static void center(const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
#if PLASK_OSX
    [window center];
    return args.GetReturnValue().SetUndefined();
#endif  // PLASK_OSX
  }

  // void hideCursor()
  //
  // Hide the cursor.
  DEFINE_METHOD(hideCursor, 0)
#if PLASK_OSX
    [NSCursor hide];
#endif
    return args.GetReturnValue().SetUndefined();
  }

  // void unhideCursor()
  //
  // Un-hide the cursor.
  DEFINE_METHOD(unhideCursor, 0)
#if PLASK_OSX
    [NSCursor unhide];
#endif
    return args.GetReturnValue().SetUndefined();
  }

  // void setCursor(string name)
  //
  // Sets the cursor to `name`.
  DEFINE_METHOD(setCursor, 1)
#if PLASK_OSX
    SEL cursor_selector = NSSelectorFromString([NSString stringWithUTF8String:
        *(v8::String::Utf8Value(args[0]))]);
    if ([NSCursor respondsToSelector:cursor_selector])
      [[NSCursor performSelector:cursor_selector] set];
#endif
    return args.GetReturnValue().SetUndefined();
  }

  // void pushCursor(string name)
  //
  // Sets the cursor to `name` using the cursor stack.
  DEFINE_METHOD(pushCursor, 1)
#if PLASK_OSX
    SEL cursor_selector = NSSelectorFromString([NSString stringWithUTF8String:
        *(v8::String::Utf8Value(args[0]))]);
    if ([NSCursor respondsToSelector:cursor_selector])
      [[NSCursor performSelector:cursor_selector] push];
#endif
    return args.GetReturnValue().SetUndefined();
  }

  // void popCursor(string name)
  //
  // Pop the cursor from the top of the cursor stack.
  DEFINE_METHOD(popCursor, 0)
#if PLASK_OSX
    [NSCursor pop];
#endif
    return args.GetReturnValue().SetUndefined();
  }

  // void setCursorPosition(float x, float y)
  //
  // Set the cursor position (within the main display).
  DEFINE_METHOD(setCursorPosition, 2)
#if PLASK_OSX
    CGDisplayMoveCursorToPoint(
        CGMainDisplayID(),
        CGPointMake(args[0]->NumberValue(), args[1]->NumberValue()));
#endif
    return args.GetReturnValue().SetUndefined();
  }

  // void warpCursorPosition(float x, float y)
  //
  // Set the cursor position (in global display coordinate space), without
  // generating any events.
  DEFINE_METHOD(warpCursorPosition, 2)
#if PLASK_OSX
    CGWarpMouseCursorPosition(
        CGPointMake(args[0]->NumberValue(), args[1]->NumberValue()));
#endif
    return args.GetReturnValue().SetUndefined();
  }

  // void associateMouse(bool connted)
  //
  // Sets whether the mouse and the mouse cursor are connected (whether moving
  // the mouse moves the cursor).
  DEFINE_METHOD(associateMouse, 1)
#if PLASK_OSX
    CGAssociateMouseAndMouseCursorPosition(args[0]->BooleanValue());
#endif
    return args.GetReturnValue().SetUndefined();
  }

  // void hide()
  //
  // Hide the window.
  static void hide(const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
#if PLASK_OSX
    [window orderOut:nil];
#endif  // PLASK_OSX
    return args.GetReturnValue().SetUndefined();
  }

  // void show()
  //
  // Un-hide the window.
  static void show(const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
#if PLASK_OSX
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
#endif  // PLASK_OSX

    return args.GetReturnValue().SetUndefined();
  }

  // object screenSize()
  //
  // Returns an object {width: float, height: float} of the screen size of the
  // main screen the window is currently on.
  static void screenSize(const v8::FunctionCallbackInfo<v8::Value>& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
    v8::Local<v8::Object> res = v8::Object::New(isolate);
#if PLASK_OSX
    NSRect frame = [[window screen] frame];
    res->Set(v8::String::NewFromUtf8(isolate, "width"), v8::Number::New(isolate, frame.size.width));
    res->Set(v8::String::NewFromUtf8(isolate, "height"), v8::Number::New(isolate, frame.size.height));
#endif  // PLASK_OSX
    return args.GetReturnValue().Set(res);
  }

  // void setFullscreen(bool fullscreen)
  //
  // Switches the window in and out of "fullscreen".  Fullscreen means that
  // the window is borderless and on a higher window level.
  DEFINE_METHOD(setFullscreen, 1)
    WrappedNSWindow* window = ExtractWindowPointer(args.Holder());
    bool fullscreen = args[0]->BooleanValue();
#if PLASK_OSX
    // NOTE(deanm): When you create a window with NSBorderlessWindowMask it
    // seems like a bunch of things change under the hood that don't change
    // just by calling setStyleMask.  So we have to manually set shadow, etc.
    [window setLevel:(fullscreen ? NSMainMenuWindowLevel+1 : NSNormalWindowLevel)];
    // NOTE(deanm): Without fixing opaque when you switch from fullscreen to
    // not fullscreen the opacity around the corners of the title bar breaks
    // and there is just black in what should be the transparency space.
    // Seems occasionally glitchy if you don't set it before the style mask.
    [window setOpaque:fullscreen];
    [window setStyleMask:(fullscreen ? NSBorderlessWindowMask : NSTitledWindowMask)];
    [window setHasShadow:!fullscreen];
#endif  // PLASK_OSX
    return args.GetReturnValue().SetUndefined();
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
#if PLASK_OSX
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
#else
      { "kDummy", 1 },
#endif
    };

    static BatchedMethods class_methods[] = {
      { "pressedMouseButtons", &NSEventWrapper::class_pressedMouseButtons },
    };

    static BatchedMethods methods[] = {
      METHOD_ENTRY( type ),
      METHOD_ENTRY( buttonNumber ),
      METHOD_ENTRY( clickCount ),
      METHOD_ENTRY( characters ),
      METHOD_ENTRY( keyCode ),
      METHOD_ENTRY( locationInWindow ),
      METHOD_ENTRY( deltaX ),
      METHOD_ENTRY( deltaY ),
      METHOD_ENTRY( deltaZ ),
      METHOD_ENTRY( hasPreciseScrollingDeltas ),
      METHOD_ENTRY( scrollingDeltaX ),
      METHOD_ENTRY( scrollingDeltaY ),
      METHOD_ENTRY( pressure ),
      METHOD_ENTRY( isEnteringProximity ),
      METHOD_ENTRY( modifierFlags ),
      METHOD_ENTRY( isARepeat ),
      METHOD_ENTRY( phase ),
      METHOD_ENTRY( momentumPhase ),
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

#if PLASK_OSX
    [event release];  // Okay even if event is nil.
#endif  // PLASK_OSX
  }

  // This will be called when we create a new instance from the instance
  // template, wrapping a NSEvent*.  It can also be called directly from
  // JavaScript, which is a bit of a problem, but we'll survive.

  // new NSEvent()
  //
  // An NSEvent wraps the raw events from Cocoa, and will be automatically
  // constructed in response to Window and UI events from the windowing system.
  //
  // In typical usage you will not interact with this class directly, but
  // simpleWindow will translate these events into the objects that are
  // dispatched into the JavaScript event handlers.
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
#if PLASK_OSX
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, [NSEvent pressedMouseButtons]));
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // int type()
  static void type(const v8::FunctionCallbackInfo<v8::Value>& args) {
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, [event type]));
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // int buttonNumber()
  static void buttonNumber(const v8::FunctionCallbackInfo<v8::Value>& args) {
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, [event buttonNumber]));
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // int clickCount()
  DEFINE_METHOD(clickCount, 0)
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, [event clickCount]));
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // string characters()
  static void characters(const v8::FunctionCallbackInfo<v8::Value>& args) {
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    NSString* characters = [event characters];
    return args.GetReturnValue().Set(v8::String::NewFromUtf8(isolate,
        [characters UTF8String],
        v8::String::kNormalString,
        [characters lengthOfBytesUsingEncoding:NSUTF8StringEncoding]));
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // int keyCode()
  static void keyCode(const v8::FunctionCallbackInfo<v8::Value>& args) {
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, [event keyCode]));
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  static void locationInWindow(const v8::FunctionCallbackInfo<v8::Value>& args) {
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    // If window is nil we'll instead get screen coordinates.
    if ([event window] == nil)
      return v8_utils::ThrowError(isolate, "Calling locationInWindow with nil window.");
    NSPoint pos = [event locationInWindow];
    v8::Local<v8::Object> res = v8::Object::New(isolate);
    res->Set(v8::String::NewFromUtf8(isolate, "x"), v8::Number::New(isolate, pos.x));
    res->Set(v8::String::NewFromUtf8(isolate, "y"), v8::Number::New(isolate, pos.y));
    return args.GetReturnValue().Set(res);
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // float deltaX()
  static void deltaX(const v8::FunctionCallbackInfo<v8::Value>& args) {
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [event deltaX]));
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // float deltaY()
  static void deltaY(const v8::FunctionCallbackInfo<v8::Value>& args) {
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [event deltaY]));
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // float deltaZ()
  static void deltaZ(const v8::FunctionCallbackInfo<v8::Value>& args) {
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [event deltaZ]));
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // float hasPreciseScrollingDeltas()
  DEFINE_METHOD(hasPreciseScrollingDeltas, 0)
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(!![event hasPreciseScrollingDeltas]);
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // float scrollingDeltaX()
  DEFINE_METHOD(scrollingDeltaX, 0)
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [event scrollingDeltaX]));
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // float scrollingDeltaY()
  DEFINE_METHOD(scrollingDeltaY, 0)
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [event scrollingDeltaY]));
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // float pressure()
  static void pressure(const v8::FunctionCallbackInfo<v8::Value>& args) {
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [event pressure]));
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // bool isEnteringProximity()
  static void isEnteringProximity(const v8::FunctionCallbackInfo<v8::Value>& args) {
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set((bool)[event isEnteringProximity]);
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // int modifierFlags()
  static void modifierFlags(const v8::FunctionCallbackInfo<v8::Value>& args) {
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, [event modifierFlags]));
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // bool isARepeat()
  //
  // NOTE: Can only be called on key events or will throw an objc exception.
  DEFINE_METHOD(isARepeat, 0)
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(!![event isARepeat]);
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // int momentumPhase()
  DEFINE_METHOD(momentumPhase, 0)
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, [event momentumPhase]));
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
  }

  // int phase()
  DEFINE_METHOD(phase, 0)
#if PLASK_OSX
    NSEvent* event = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Integer::NewFromUnsigned(isolate, [event phase]));
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
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
      { "kDifferencePathOp", SkPathOp::kDifference_SkPathOp },  //!< subtract the op path from the first path
      { "kIntersectPathOp", SkPathOp::kIntersect_SkPathOp },  //!< intersect the two paths
      { "kUnionPathOp", SkPathOp::kUnion_SkPathOp },  //!< union (inclusive-or) the two paths
      { "kXORPathOp", SkPathOp::kXOR_SkPathOp },  //!< exclusive-or the two paths
      { "kReverseDifferencePathOp", SkPathOp::kReverseDifference_SkPathOp },  //!< subtract the first path from the op path
      // NOTE(deanm): These should have the same values as the PathOp version,
      // but they are different constants in Skia so also have them additionally
      // here.  Note there is also kReplaceOp which has no PathOp version.
      { "kDifferenceOp", SkRegion::kDifference_Op },  //!< subtract the op region from the first region
      { "kIntersectOp", SkRegion::kIntersect_Op },   //!< intersect the two regions
      { "kUnionOp", SkRegion::kUnion_Op },       //!< union (inclusive-or) the two regions
      { "kXOROp", SkRegion::kXOR_Op },         //!< exclusive-or the two regions
      { "kReverseDifferenceOp", SkRegion::kReverseDifference_Op },  /** subtract the first region from the op region */
      { "kReplaceOp", SkRegion::kReplace_Op },     //!< replace the dst region with the op region
      { "kMoveVerb",  SkPath::kMove_Verb },   //!< iter.next returns 1 point
      { "kLineVerb",  SkPath::kLine_Verb },   //!< iter.next returns 2 points
      { "kQuadVerb",  SkPath::kQuad_Verb },   //!< iter.next returns 3 points
      { "kConicVerb", SkPath::kConic_Verb },  //!< iter.next returns 3 points + iter.conicWeight()
      { "kCubicVerb", SkPath::kCubic_Verb },  //!< iter.next returns 4 points
      { "kCloseVerb", SkPath::kClose_Verb },  //!< iter.next returns 1 point (contour's moveTo pt)
      { "kDoneVerb",  SkPath::kDone_Verb },   //!< iter.next returns 0 points
    };

    static BatchedMethods methods[] = {
      METHOD_ENTRY( reset ),
      METHOD_ENTRY( rewind ),
      METHOD_ENTRY( moveTo ),
      METHOD_ENTRY( lineTo ),
      METHOD_ENTRY( rLineTo ),
      METHOD_ENTRY( quadTo ),
      METHOD_ENTRY( cubicTo ),
      METHOD_ENTRY( arcTo ),
      METHOD_ENTRY( arct ),
      METHOD_ENTRY( addRect ),
      METHOD_ENTRY( addOval ),
      METHOD_ENTRY( addCircle ),
      METHOD_ENTRY( close ),
      METHOD_ENTRY( offset ),
      METHOD_ENTRY( getBounds ),
      METHOD_ENTRY( transform ),
      METHOD_ENTRY( toSVGString ),
      METHOD_ENTRY( fromSVGString ),
      METHOD_ENTRY( op ),
      METHOD_ENTRY( getPoints ),
      METHOD_ENTRY( getVerbs ),
      METHOD_ENTRY( getFillType ),
      METHOD_ENTRY( setFillType ),
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
  // void reset()
  //
  // Reset the path to an empty path.
  static void reset(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());
    path->reset();
    return args.GetReturnValue().SetUndefined();
  }

  // void rewind()
  //
  // Reset the path to an empty path, but keeping the internal memory previously
  // allocated for the point storage.
  static void rewind(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());
    path->rewind();
    return args.GetReturnValue().SetUndefined();
  }

  // void moveTo(x, y)
  //
  // Move to (`x`, `y`).
  static void moveTo(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());

    path->moveTo(SkDoubleToScalar(args[0]->NumberValue()),
                 SkDoubleToScalar(args[1]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  // void lineTo(x, y)
  //
  // Line to (`x`, `y`).
  static void lineTo(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());

    path->lineTo(SkDoubleToScalar(args[0]->NumberValue()),
                 SkDoubleToScalar(args[1]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  // void rLineTo(rx, ry)
  //
  // Similar to lineTo(), except `rx` and `ry` are relative to the previous point.
  static void rLineTo(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());

    path->rLineTo(SkDoubleToScalar(args[0]->NumberValue()),
                  SkDoubleToScalar(args[1]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  // void quadTo(cx, cy, ex, ey)
  //
  // A quadratic bezier curve with control point (`cx`, `cy`) and endpoint (`ex`,
  // `ey`).
  static void quadTo(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());

    path->quadTo(SkDoubleToScalar(args[0]->NumberValue()),
                 SkDoubleToScalar(args[1]->NumberValue()),
                 SkDoubleToScalar(args[2]->NumberValue()),
                 SkDoubleToScalar(args[3]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  // void cubicTo(c0x, c0y, c1x, c1y, ex, ey)
  //
  // A cubic bezier curve with control points (`c0x`, `c0y`) and (`c1x`, `c1y`) and
  // endpoint (`ex`, `ey`).
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

  // void close()
  //
  // Close the path, connecting the path to the beginning.
  static void close(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());
    path->close();
    return args.GetReturnValue().SetUndefined();
  }

  // void offset(x, y)
  //
  // Offset the path by (`x`, `y`).
  static void offset(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());
    path->offset(SkDoubleToScalar(args[0]->NumberValue()),
                 SkDoubleToScalar(args[1]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  // float[ ] getBounds()
  //
  // Returns an array of [left, top, right, bottom], the bounding rectangle of the
  // path.
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

  // void transform(a, b, c, d, e, f, g, h, i)
  //
  // Transforms the path by the 3x3 homogeneous transformation matrix:
  //
  //     |a b c|
  //     |d e f|
  //     |g h i|
  DEFINE_METHOD(transform, 9)
    SkPath* path = ExtractPointer(args.Holder());
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
    path->transform(matrix);
    return args.GetReturnValue().SetUndefined();
  }

  // string toSVGString()
  //
  // Returns the path as a SVG path data representation.
  static void toSVGString(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());
    SkString str;
    SkParsePath::ToSVGString(*path, &str);
    return args.GetReturnValue().Set(v8::String::NewFromUtf8(
        isolate, str.c_str(), v8::String::kNormalString, str.size()));
  }

  // bool fromSVGString(string svgpath)
  //
  // Sets the path from an SVG path data representation.  Returns true on
  // success.
  static void fromSVGString(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPath* path = ExtractPointer(args.Holder());
    v8::String::Utf8Value utf8(args[0]);
    return args.GetReturnValue().Set(SkParsePath::FromSVGString(*utf8, path));
  }

  // bool Op(SkPath one, SkPath two, int pathop)
  //
  // Sets the path to the result of the operation `pathop` on `one` and `two`.
  DEFINE_METHOD(op, 3)
    SkPath* path = ExtractPointer(args.Holder());

    if (!HasInstance(isolate, args[0]) || !HasInstance(isolate, args[1]))
      return v8_utils::ThrowTypeError(isolate, "Type error");

    SkPath* one = ExtractPointer(v8::Handle<v8::Object>::Cast(args[0]));
    SkPath* two = ExtractPointer(v8::Handle<v8::Object>::Cast(args[1]));
    SkPathOp op = static_cast<SkPathOp>(args[2]->Uint32Value());

    return args.GetReturnValue().Set(::Op(*one, *two, op, path));
  }

  // float[] getPoints()
  DEFINE_METHOD(getPoints, 0)
    SkPath* path = ExtractPointer(args.Holder());
    int num = path->countPoints();
    SkPoint* points = new SkPoint[num];
    path->getPoints(points, num);
    v8::Local<v8::Array> res = v8::Array::New(isolate, num * 2);
    for (int i = 0; i < num; ++i) {
      SkPoint* p = points + i;
      res->Set(v8::Integer::New(isolate, i*2),   v8::Number::New(isolate, p->x()));
      res->Set(v8::Integer::New(isolate, i*2+1), v8::Number::New(isolate, p->y()));
    }
    delete[] points;

    return args.GetReturnValue().Set(res);
  }

  // float[] getVerbs()
  DEFINE_METHOD(getVerbs, 0)
    SkPath* path = ExtractPointer(args.Holder());
    int num = path->countVerbs();
    uint8_t* verbs = new uint8_t[num];
    if (path->getVerbs(verbs, num) != num) {
      delete[] verbs;
      return v8_utils::ThrowError(isolate, "getVerbs() failed");
    }

    v8::Local<v8::Array> res = v8::Array::New(isolate, num);
    for (int i = 0; i < num; ++i) {
      res->Set(v8::Integer::New(isolate, i), v8::Integer::New(isolate, verbs[i]));
    }
    delete[] verbs;

    return args.GetReturnValue().Set(res);
  }

  // int getFillType()
  DEFINE_METHOD(getFillType, 0)
    SkPath* path = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Uint32::New(isolate, path->getFillType()));
  }

  // void setFillType(int)
  DEFINE_METHOD(setFillType, 1)
    SkPath* path = ExtractPointer(args.Holder());
    path->setFillType(static_cast<SkPath::FillType>(v8_utils::ToInt32(args[0])));
    return args.GetReturnValue().SetUndefined();
  }

  // void SkPath(SkPath? path_to_copy)
  //
  // Construct a new path object, optionally based off of an existing path.
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
      // FilterLevel / SkFilterQuality.
      { "kNoneFilterLevel", kNone_SkFilterQuality },
      { "kLowFilterLevel", kLow_SkFilterQuality },
      { "kMediumFilterLevel", kMedium_SkFilterQuality },
      { "kHighFilterLevel", kHigh_SkFilterQuality },
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
      METHOD_ENTRY( reset ),
      METHOD_ENTRY( getFlags ),
      METHOD_ENTRY( setFlags ),
      METHOD_ENTRY( setAntiAlias ),
      METHOD_ENTRY( setDither ),
      METHOD_ENTRY( setUnderlineText ),
      METHOD_ENTRY( setStrikeThruText ),
      METHOD_ENTRY( setFakeBoldText ),
      METHOD_ENTRY( setSubpixelText ),
      METHOD_ENTRY( setDevKernText ),
      METHOD_ENTRY( setLCDRenderText ),
      METHOD_ENTRY( setAutohinted ),
      METHOD_ENTRY( setStrokeWidth ),
      METHOD_ENTRY( getStyle ),
      METHOD_ENTRY( setStyle ),
      METHOD_ENTRY( setFill ),
      METHOD_ENTRY( setStroke ),
      METHOD_ENTRY( setFillAndStroke ),
      METHOD_ENTRY( getStrokeCap ),
      METHOD_ENTRY( setStrokeCap ),
      METHOD_ENTRY( getStrokeJoin ),
      METHOD_ENTRY( setStrokeJoin ),
      METHOD_ENTRY( getStrokeMiter ),
      METHOD_ENTRY( setStrokeMiter ),
      METHOD_ENTRY( getFillPath ),
      METHOD_ENTRY( setColor ),
      METHOD_ENTRY( setColorHSV ),
      METHOD_ENTRY( setAlpha ),
      METHOD_ENTRY( setTextSize ),
      METHOD_ENTRY( setXfermodeMode ),
      METHOD_ENTRY( setFontFamily ),
      METHOD_ENTRY( setFontFamilyPostScript ),
      METHOD_ENTRY( setLinearGradientShader ),
      METHOD_ENTRY( setRadialGradientShader ),
      METHOD_ENTRY( clearShader ),
      METHOD_ENTRY( setDashPathEffect ),
      METHOD_ENTRY( setDiscretePathEffect ),
      METHOD_ENTRY( clearPathEffect ),
      METHOD_ENTRY( measureText ),
      METHOD_ENTRY( measureTextBounds ),
      METHOD_ENTRY( getFontMetrics ),
      METHOD_ENTRY( getTextPath ),
      METHOD_ENTRY( getFilterLevel ),
      METHOD_ENTRY( setFilterLevel ),
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
  // void reset()
  //
  // Reset the paint to the default settings.
  static void reset(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->reset();
    return args.GetReturnValue().SetUndefined();
  }

  // void getFlags()
  //
  // Return the paint flags.
  static void getFlags(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Uint32::New(isolate, paint->getFlags()));
  }

  // void setFlags(flags)
  //
  // Set the paint flags, such as whether to perform anti-aliasing.
  //
  //     // The follow flags are supported.  They should be OR'd together to set
  //     // multiple settings.
  //     //   kAntiAliasFlag
  //     //   kFilterBitmapFlag
  //     //   kDitherFlag
  //     //   kUnderlineTextFlag
  //     //   kStrikeThruTextFlag
  //     //   kFakeBoldTextFlag
  //     //   kLinearTextFlag
  //     //   kSubpixelTextFlag
  //     //   kDevKernTextFlag
  //
  //     paint.setFlags(paint.kAntiAliasFlag | paint.kFilterBitmapFlag);
  static void setFlags(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setFlags(v8_utils::ToInt32(args[0]));
    return args.GetReturnValue().SetUndefined();
  }

  // void setFilterLevel(int level)
  //
  // Set the filtering level (quality vs performance) for scaled images.
  //
  //     // kNoneFilterLevel
  //     // kLowFilterLevel
  //     // kMediumFilterLevel
  //     // kHighFilterLevel
  DEFINE_METHOD(setFilterLevel, 1)
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setFilterQuality(static_cast<SkFilterQuality>(v8_utils::ToInt32(args[0])));
    return args.GetReturnValue().SetUndefined();
  }

  // int getFilterLevel()
  //
  // Get the filtering level (quality vs performance) for scaled images.
  DEFINE_METHOD(getFilterLevel, 0)
    SkPaint* paint = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Uint32::New(isolate, paint->getFilterQuality()));
  }

  // void setAntiAlias(bool aa)
  static void setAntiAlias(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setAntiAlias(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void setDither(bool dither)
  static void setDither(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setDither(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void setUnderlineText(bool underline)
  static void setUnderlineText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setUnderlineText(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void setStrikeThruText(bool strike)
  static void setStrikeThruText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setStrikeThruText(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void setFakeBoldText(bool fakebold)
  static void setFakeBoldText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setFakeBoldText(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void setSubpixelText(bool subpixel)
  static void setSubpixelText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setSubpixelText(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void setDevKernText(bool devkern)
  static void setDevKernText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setDevKernText(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void setLCDRenderText(bool lcd)
  static void setLCDRenderText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setLCDRenderText(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void setAutohinted(bool autohint)
  static void setAutohinted(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setAutohinted(args[0]->BooleanValue());
    return args.GetReturnValue().SetUndefined();
  }

  // void getStrokeWidth()
  //
  // Return the current stroke width.
  static void getStrokeWidth(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, SkScalarToDouble(paint->getStrokeWidth())));
  }

  // void setStrokeWidth(width)
  //
  // Set the current stroke width to the floating point value `width`.  A width of
  // 0 causes Skia to draw in a special 'hairline' stroking mode.
  static void setStrokeWidth(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setStrokeWidth(SkDoubleToScalar(args[0]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  // void getStyle()
  //
  // Return the current style.
  static void getStyle(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Uint32::New(isolate, paint->getStyle()));
  }

  // void setStyle(style)
  //
  // Set the paint style, for example whether to stroke, fill, or both.
  //
  //     // The follow styles are supported:
  //     //   kFillStyle
  //     //   kStrokeStyle
  //     //   kStrokeAndFillStyle
  //
  //     paint.setStyle(paint.kStrokeStyle);
  static void setStyle(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setStyle(static_cast<SkPaint::Style>(v8_utils::ToInt32(args[0])));
    return args.GetReturnValue().SetUndefined();
  }

  // void setFill()
  //
  // Sets the current paint style to fill.
  static void setFill(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setStyle(SkPaint::kFill_Style);
    return args.GetReturnValue().SetUndefined();
  }

  // void setStroke()
  //
  // Sets the current paint style to stroke.
  static void setStroke(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setStyle(SkPaint::kStroke_Style);
    return args.GetReturnValue().SetUndefined();
  }

  // void setFillAndStroke()
  //
  // Sets the current paint style to fill and stroke.
  static void setFillAndStroke(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    // We flip the name around because it makes more sense, generally you think
    // of the stroke happening after the fill.
    paint->setStyle(SkPaint::kStrokeAndFill_Style);
    return args.GetReturnValue().SetUndefined();
  }

  // int getStrokeCap()
  //
  // Return the current stroke cap.
  static void getStrokeCap(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Uint32::New(isolate, paint->getStrokeCap()));
  }

  // void setStrokeCap(int cap)
  //
  // Set the stroke cap.
  //
  //     // The follow caps are supported:
  //     //   kButtCap
  //     //   kRoundCap
  //     //   kSquareCap
  //     //   kDefaultCap
  //
  //     paint.setStrokeCape(paint.kRoundCap);
  static void setStrokeCap(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setStrokeCap(static_cast<SkPaint::Cap>(v8_utils::ToInt32(args[0])));
    return args.GetReturnValue().SetUndefined();
  }

  // int getStrokeJoin()
  //
  // Returns the current stroke join setting.
  static void getStrokeJoin(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Uint32::New(isolate, paint->getStrokeJoin()));
  }

  // void setStrokeJoin(int join)
  static void setStrokeJoin(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setStrokeJoin(static_cast<SkPaint::Join>(v8_utils::ToInt32(args[0])));
    return args.GetReturnValue().SetUndefined();
  }

  // float getStrokeMiter()
  //
  // Returns the current stroke miter setting.
  static void getStrokeMiter(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    return args.GetReturnValue().Set(v8::Number::New(isolate, SkScalarToDouble(paint->getStrokeMiter())));
  }

  // float setStrokeMiter(float miter)
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

  // void setColor(r, g, b, a)
  //
  // Set the paint color, values are integers in the range of 0 to 255.
  static void setColor(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());

    int r = Clamp(v8_utils::ToInt32WithDefault(args[0], 0), 0, 255);
    int g = Clamp(v8_utils::ToInt32WithDefault(args[1], 0), 0, 255);
    int b = Clamp(v8_utils::ToInt32WithDefault(args[2], 0), 0, 255);
    int a = Clamp(v8_utils::ToInt32WithDefault(args[3], 255), 0, 255);

    paint->setColor(SkColorSetARGB(a, r, g, b));
    return args.GetReturnValue().SetUndefined();
  }

  // void setColorHSV(h, s, v, a)
  //
  // Set the paint color from HSV values, the HSV values are floating point, hue
  // from 0 to 360, and saturation and value from 0 to 1.  The alpha value is an
  // integer in the range of 0 to 255.
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

  // void setAlpha(float a)
  //
  // Set the alpha of the paint color, leaving rgb unchanged.
  DEFINE_METHOD(setAlpha, 1)
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setAlpha(Clamp(v8_utils::ToInt32WithDefault(args[0], 255), 0, 255));
    return args.GetReturnValue().SetUndefined();
  }

  // void setTextSize(size)
  //
  // Set the text size.
  static void setTextSize(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());

    paint->setTextSize(SkDoubleToScalar(args[0]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  // void setXfermodeMode(mode)
  //
  // Set the alpha blending (porter duff transfer) mode.
  //
  //     // The following blending modes are supported:
  //     //   kClearMode
  //     //   kSrcMode
  //     //   kDstMode
  //     //   kSrcOverMode
  //     //   kDstOverMode
  //     //   kSrcInMode
  //     //   kDstInMode
  //     //   kSrcOutMode
  //     //   kDstOutMode
  //     //   kSrcATopMode
  //     //   kDstATopMode
  //     //   kXorMode
  //     //   kPlusMode
  //     //   kMultiplyMode
  //     //   kScreenMode
  //     //   kOverlayMode
  //     //   kDarkenMode
  //     //   kLightenMode
  //     //   kColorDodgeMode
  //     //   kColorBurnMode
  //     //   kHardLightMode
  //     //   kSoftLightMode
  //     //   kDifferenceMode
  //     //   kExclusionMode
  //
  //     paint.setXfermodeMode(paint.kPlusMode);  // Additive blending.
  static void setXfermodeMode(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());

    // TODO(deanm): Memory management.
    paint->setXfermodeMode(
          static_cast<SkXfermode::Mode>(v8_utils::ToInt32(args[0])));
    return args.GetReturnValue().SetUndefined();
  }

  // void setFontFamily(family)
  //
  // Set the text font family.
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

#if PLASK_OSX
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
#endif  // PLASK_OSX
    return args.GetReturnValue().SetUndefined();
  }

  // void setLinearGradientShader(x0, y0, x1, y1, float[ ] colorpositions)
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

  // void setRadialGradientShader(x, y, radius, float[ ] colorpositions)
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

  // void clearShader()
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

  static void setDiscretePathEffect(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setPathEffect(SkDiscretePathEffect::Create(
        SkDoubleToScalar(args[0]->NumberValue()),
        SkDoubleToScalar(args[1]->NumberValue()),
        args[2]->Uint32Value()));
    return args.GetReturnValue().SetUndefined();
  }

  // void clearPathEffect()
  //
  // Clear any path effect.
  static void clearPathEffect(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());
    paint->setPathEffect(NULL);
    return args.GetReturnValue().SetUndefined();
  }

  // float measureText(string text)
  //
  // Measure the x-advance for the string `text` using the current
  // paint settings.
  static void measureText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkPaint* paint = ExtractPointer(args.Holder());

    v8::String::Utf8Value utf8(args[0]);
    SkScalar width = paint->measureText(*utf8, utf8.length());
    return args.GetReturnValue().Set(v8::Number::New(isolate, width));
  }

  // float[ ] measureTextBounds(string text)
  //
  // Returns an array of the bounds [left, top, right, bottom] for `text`.
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

  // void getTextPath(text, x, y, path)
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


// TODO(deanm): Should we use the Signature to enforce this instead?
#define SKCANVAS_PAINT_ARG0 \
    if (!SkPaintWrapper::HasInstance(isolate, args[0])) \
      return v8_utils::ThrowTypeError(isolate, "First argument not an SkPaint"); \
    SkPaint* paint = SkPaintWrapper::ExtractPointer( \
        v8::Handle<v8::Object>::Cast(args[0]))

class SkCanvasWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate>& GetTemplate(v8::Isolate* isolate) {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::Local<v8::FunctionTemplate> ft =
        v8::FunctionTemplate::New(isolate, &SkCanvasWrapper::V8New);
    v8::Local<v8::ObjectTemplate> instance = ft->InstanceTemplate();
    instance->SetInternalFieldCount(2);  // SkCanvas and SkDocument (pdf) pointers.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(isolate, ft);

    // Configure the template...
    static BatchedConstants constants[] = {
      // PointMode.
      { "kPointsPointMode", SkCanvas::kPoints_PointMode },
      { "kLinesPointMode", SkCanvas::kLines_PointMode },
      { "kPolygonPointMode", SkCanvas::kPolygon_PointMode },
    };

    static BatchedMethods methods[] = {
      METHOD_ENTRY( clipRect ),
      METHOD_ENTRY( clipPath ),
      METHOD_ENTRY( drawCircle ),
      METHOD_ENTRY( drawLine ),
      METHOD_ENTRY( drawPaint ),
      METHOD_ENTRY( drawCanvas ),
      METHOD_ENTRY( drawColor ),
      METHOD_ENTRY( clear ),
      METHOD_ENTRY( drawPath ),
      METHOD_ENTRY( drawPoints ),
      METHOD_ENTRY( drawRect ),
      METHOD_ENTRY( drawRoundRect ),
      METHOD_ENTRY( drawText ),
      METHOD_ENTRY( drawTextOnPathHV ),
      METHOD_ENTRY( concatMatrix ),
      METHOD_ENTRY( setMatrix ),
      METHOD_ENTRY( resetMatrix ),
      METHOD_ENTRY( translate ),
      METHOD_ENTRY( scale ),
      METHOD_ENTRY( rotate ),
      METHOD_ENTRY( skew ),
      METHOD_ENTRY( save ),
      METHOD_ENTRY( saveLayer ),
      METHOD_ENTRY( restore ),
      METHOD_ENTRY( writeImage ),
      METHOD_ENTRY( writePDF ),
      METHOD_ENTRY( flush ),
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

  static SkDocument* ExtractDocumentPointer(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<SkDocument*>(obj->GetAlignedPointerFromInternalField(1));
  }

  static bool HasInstance(v8::Isolate* isolate, v8::Handle<v8::Value> value) {
    return PersistentToLocal(isolate, GetTemplate(isolate))->HasInstance(value);
  }

 private:
  static void WeakCallback(
      const v8::WeakCallbackData<v8::Object, v8::Persistent<v8::Object> >& data) {
    v8::Isolate* isolate = data.GetIsolate();
    SkCanvas* canvas = ExtractPointer(data.GetValue());
    SkDocument* doc = ExtractDocumentPointer(data.GetValue());

    v8::Persistent<v8::Object>* persistent = data.GetParameter();
    persistent->ClearWeak();
    persistent->Reset();
    delete persistent;

    // Delete the backing SkCanvas object.  Skia reference counting should
    // handle cleaning up deeper resources (for example the backing pixels).
    if (doc) {
      doc->unref();  // Owns the canvas, right?
    } else {
      SkImageInfo info = canvas->imageInfo();
      int size_bytes = info.width() * info.height() * info.bytesPerPixel();
      isolate->AdjustAmountOfExternalAllocatedMemory(-size_bytes);
      delete canvas;
    }
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

    SkCanvas* canvas = NULL;
    SkDocument* doc = NULL;

    if (args[0]->StrictEquals(v8::String::NewFromUtf8(isolate, "%PDF"))) {  // PDF constructor.
      v8::String::Utf8Value filename(args[1]);
      doc = SkDocument::CreatePDF(*filename);
      if (!doc) return v8_utils::ThrowError(isolate, "Unable to create PDF document.");
      SkScalar width = args[2]->Int32Value(), height = args[3]->Int32Value();
      SkRect content = SkRect::MakeWH(args[4]->Int32Value(), args[5]->Int32Value());
      canvas = doc->beginPage(width, height, &content);
      // Bit of a hack to get the width and height properties set.
      tbitmap.setInfo(SkImageInfo::Make(width, height, kUnknown_SkColorType, kUnknown_SkAlphaType));
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
      } else if (args[1]->IsArrayBuffer() || args[1]->IsArrayBufferView()) {
        void* datadata = NULL;
        intptr_t datasize = 0;
        if (!GetTypedArrayBytes(args[1], &datadata, &datasize))
          return v8_utils::ThrowError(isolate, "Data must be a TypedArray.");

        FIMEMORY* mem = FreeImage_OpenMemory(reinterpret_cast<BYTE*>(datadata), datasize);
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
#if PLASK_GPUSKIA
    } else if (args.Length() == 1 && NSOpenGLContextWrapper::HasInstance(isolate, args[0])) {
      SkSurface* sk_surface =
          NSOpenGLContextWrapper::ExtractSkSurface(v8::Handle<v8::Object>::Cast(args[0]));
      if (!sk_surface)
        return v8_utils::ThrowError(isolate, "OpenGL does not have an attached Skia surface.");
      // NOTE(deanm): We fix up the width/height properties in plask.js.
      canvas = sk_surface->getCanvas();
#endif
    } else if (args.Length() == 1 && SkCanvasWrapper::HasInstance(isolate, args[0])) {
      SkCanvas* pcanvas = ExtractPointer(v8::Handle<v8::Object>::Cast(args[0]));
      // Allocate a new block of pixels with a copy from pbitmap.
      // NOTE(deanm): Don't think this version of readPixels allocates properly.
      // if (!pcanvas->readPixels(&tbitmap, 0, 0))
      if (!pcanvas->readPixels(pcanvas->imageInfo().bounds(), &tbitmap))
        return v8_utils::ThrowError(isolate, "SkCanvas constructor unable to readPixels().");
      canvas = new SkCanvas(tbitmap);
    } else {
      return v8_utils::ThrowError(isolate, "Improper SkCanvas constructor arguments.");
    }

    args.This()->SetAlignedPointerInInternalField(0, canvas);
    args.This()->SetAlignedPointerInInternalField(1, doc);
    // Direct pixel access via array[] indexing.
    // NOTE(deanm): Previously pixel access was directly on the canvas object,
    // however as TypedArrays developed V8 removed support for the arbitrary
    // "indexed external data" on all objects.  There are two choices, try to
    // make the canvas element a TypedArray, either doing some prototype chain
    // setup (not sure this would work for TypedArrays), or just having a real
    // TypedArray as a property on the canvas.  This unfortunately breaks
    // compatibility but it is probably the better choice.
    v8::Handle<v8::ArrayBuffer> pixels_data = v8::ArrayBuffer::New(
        isolate, bitmap->getPixels(), bitmap->getSize());  // Externalized
    v8::Handle<v8::Uint8ClampedArray> pixels = v8::Uint8ClampedArray::New(
        pixels_data, 0, bitmap->getSize());
    // NOTE(deanm): I hope that attaching additionaly properties to the
    // TypedArray doesn't have any performance ramifications.  I don't know
    // about the internal JIT implementation of TypedArrays, but brief testing
    // didn't seem to show any negative impact.  Fingers crossed.
#if 0  // NOTE(deanm): For now don't do it unless becomes really inconvenient.
    pixels->Set(v8::String::NewFromUtf8(isolate, "width"),
                v8::Integer::NewFromUnsigned(isolate, bitmap->width()));
    pixels->Set(v8::String::NewFromUtf8(isolate, "height"),
                v8::Integer::NewFromUnsigned(isolate, bitmap->height()));
#endif

    args.This()->Set(v8::String::NewFromUtf8(isolate, "width"),
                     v8::Integer::NewFromUnsigned(isolate, bitmap->width()));
    args.This()->Set(v8::String::NewFromUtf8(isolate, "height"),
                     v8::Integer::NewFromUnsigned(isolate, bitmap->height()));
    args.This()->Set(v8::String::NewFromUtf8(isolate, "pixels"), pixels);

    // Notify the GC that we have a possibly large amount of data allocated
    // behind this object for bitmap backed canvases.
    if (!doc) {
      int size_bytes = bitmap->width() * bitmap->height() * 4;
      isolate->AdjustAmountOfExternalAllocatedMemory(size_bytes);
    }

    v8::Persistent<v8::Object>* persistent = new v8::Persistent<v8::Object>;
    persistent->Reset(isolate, args.This());
    persistent->SetWeak(persistent, &SkCanvasWrapper::WeakCallback);
  }

  // void concatMatrix(a, b, c, d, e, f, g, h, i)
  //
  // Preconcat the current matrix with the specified matrix.
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

  // void setMatrix(a, b, c, d, e, f, g, h, i)
  //
  // Sets the the 3x3 homogeneous transformation matrix:
  //
  //     |a b c|
  //     |d e f|
  //     |g h i|
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

  // void resetMatrix()
  //
  // Reset the transform matrix to the identity.
  static void resetMatrix(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->resetMatrix();
    return args.GetReturnValue().SetUndefined();
  }

  // void clipRect(left, top, right, bottom)
  //
  // Set the clipping path to the rectangle of the upper-left and bottom-right
  // corners specified.  Setting the clipping path will prevent any pixels to be
  // drawn outside of this path.
  //
  // The save() and restore() functions are the best way to manage or reset the
  // clipping path.
  static void clipRect(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());

    SkRect rect = { SkDoubleToScalar(args[0]->NumberValue()),
                    SkDoubleToScalar(args[1]->NumberValue()),
                    SkDoubleToScalar(args[2]->NumberValue()),
                    SkDoubleToScalar(args[3]->NumberValue()) };
    canvas->clipRect(rect);
    return args.GetReturnValue().SetUndefined();
  }

  // void clipPath(path)
  //
  // Set the clipping path to the SkPath object `path`.  Setting the clipping path
  // will prevent any pixels to be drawn outside of this path.
  //
  // The save() and restore() functions are the best way to manage or reset the
  // clipping path.
  static void clipPath(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());

    if (!SkPathWrapper::HasInstance(isolate, args[0]))
      return args.GetReturnValue().SetUndefined();

    SkPath* path = SkPathWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    SkRegion::Op op = args[1]->IsUint32() ?
        static_cast<SkRegion::Op>(args[1]->Uint32Value()) : SkRegion::kIntersect_Op;
    bool aa = args[2]->BooleanValue();  // Defaults to false.

    canvas->clipPath(*path, op, aa);

    return args.GetReturnValue().SetUndefined();
  }

  // void drawCircle(paint, x, y, radius)
  //
  // Draw a circle centered at (`x`, `y`) of radius `radius`.
  static void drawCircle(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    SKCANVAS_PAINT_ARG0;

    canvas->drawCircle(SkDoubleToScalar(args[1]->NumberValue()),
                       SkDoubleToScalar(args[2]->NumberValue()),
                       SkDoubleToScalar(args[3]->NumberValue()),
                       *paint);
    return args.GetReturnValue().SetUndefined();
  }

  // void drawLine(paint, x0, y0, x1, y1)
  //
  // Draw a line between (`x0`, `y0`) and (`x1`, `y1`).
  static void drawLine(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    SKCANVAS_PAINT_ARG0;

    canvas->drawLine(SkDoubleToScalar(args[1]->NumberValue()),
                     SkDoubleToScalar(args[2]->NumberValue()),
                     SkDoubleToScalar(args[3]->NumberValue()),
                     SkDoubleToScalar(args[4]->NumberValue()),
                     *paint);
    return args.GetReturnValue().SetUndefined();
  }

  // void drawPaint(paint)
  //
  // Fill the entire canvas with a solid color, specified by the paint's color and
  // blending mode.
  static void drawPaint(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    SKCANVAS_PAINT_ARG0;

    canvas->drawPaint(*paint);
    return args.GetReturnValue().SetUndefined();
  }

  // void drawCanvas(paint, source, dst_left, dst_top, dst_right, dst_bottom, src_left, src_top, src_right, src_bottom)
  //
  // Draw one canvas on to another canvas.  The `paint` object controls settings
  // involved in the drawing, such as anti-aliasing.  The `source` parameter is the
  // source canvas to be drawn from.  The first four parameters define the rectangle
  // within the destination canvas that the image will be drawn.  The last four
  // parameters specify the rectangle within the source image.  This allows for
  // drawing portions of the source image, scaling, etc.
  //
  // The last four parameters are optional, and will default to the entire source
  // image (0, 0, source.width, source.height).
  //
  //     var img = plask.SkCanvas.createFromImage('tex.png');  // Size 100x150.
  //     // Draw the texture image scaled 2x larger.
  //     canvas.drawCanvas(paint, img,
  //                       0, 0, 200, 300,  // Draw at (0, 0) size 200x300.
  //                       0, 0, 100, 150)  // Draw the entire source image.
  static void drawCanvas(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (args.Length() < 2)
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

    double dstx1 = v8_utils::ToNumberWithDefault(args[2], 0);
    double dsty1 = v8_utils::ToNumberWithDefault(args[3], 0);
    double dstx2 = v8_utils::ToNumberWithDefault(args[4], dstx1 + src_device->width());
    double dsty2 = v8_utils::ToNumberWithDefault(args[5], dsty1 + src_device->height());

    SkRect dst_rect = { SkDoubleToScalar(dstx1), SkDoubleToScalar(dsty1),
                        SkDoubleToScalar(dstx2), SkDoubleToScalar(dsty2) };

    int srcx1 = v8_utils::ToInt32WithDefault(args[6], 0);
    int srcy1 = v8_utils::ToInt32WithDefault(args[7], 0);
    int srcx2 = v8_utils::ToInt32WithDefault(args[8], srcx1 + src_device->width());
    int srcy2 = v8_utils::ToInt32WithDefault(args[9], srcy1 + src_device->height());
    SkIRect src_rect = { srcx1, srcy1, srcx2, srcy2 };

    canvas->drawBitmapRect(src_device->accessBitmap(false), src_rect, dst_rect, paint);
    return args.GetReturnValue().SetUndefined();
  }

  // void drawColor(r, g, b, a, blendmode)
  //
  // Fill the entire canvas with a solid color.  If `blendmode` is not specified,
  // it defaults to SrcOver, which will blend with anything already on the canvas.
  //
  // Use eraseColor() when you do not need any alpha blending.
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

  // void clear(r, g, b, a)
  //
  // Sets the entire canvas to a uniform color.
  static void clear(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());

    int r = Clamp(v8_utils::ToInt32WithDefault(args[0], 0), 0, 255);
    int g = Clamp(v8_utils::ToInt32WithDefault(args[1], 0), 0, 255);
    int b = Clamp(v8_utils::ToInt32WithDefault(args[2], 0), 0, 255);
    int a = Clamp(v8_utils::ToInt32WithDefault(args[3], 255), 0, 255);

    canvas->clear(SkColorSetARGB(a, r, g, b));
    return args.GetReturnValue().SetUndefined();
  }

  // void drawPath(paint, path)
  //
  // Draw an SkPath.  The path will be stroked or filled depending on the paint's
  // style (see SkPaint#setStyle).
  static void drawPath(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    SKCANVAS_PAINT_ARG0;

    if (!SkPathWrapper::HasInstance(isolate, args[1]))
      return args.GetReturnValue().SetUndefined();

    SkPath* path = SkPathWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[1]));

    canvas->drawPath(*path, *paint);
    return args.GetReturnValue().SetUndefined();
  }

  // void drawPoints(paint, mode, points)
  //
  // An optimized drawing path for many points, lines, or polygons with many points.
  // The `mode` parameter is one of kPointsPointMode, kLinesPointMode, or
  // kPolygonPointMode.  The `points` parameter is an array of points, in the form
  // of [x0, y0, x1, y1, ...].
  static void drawPoints(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    SKCANVAS_PAINT_ARG0;

    if (!args[2]->IsArray())
      return args.GetReturnValue().SetUndefined();

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

  // void drawRect(paint, left, top, right, bottom)
  //
  // Draw a rectangle specified by the upper-left and bottom-right corners.
  static void drawRect(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    SKCANVAS_PAINT_ARG0;

    SkRect rect = { SkDoubleToScalar(args[1]->NumberValue()),
                    SkDoubleToScalar(args[2]->NumberValue()),
                    SkDoubleToScalar(args[3]->NumberValue()),
                    SkDoubleToScalar(args[4]->NumberValue()) };
    canvas->drawRect(rect, *paint);
    return args.GetReturnValue().SetUndefined();
  }

  // void drawRoundRect(paint, left, top, right, bottom, xradius, yradius)
  //
  // Draw a rectangle with rounded corners of radius `xradius` and `yradius`.
  static void drawRoundRect(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    SKCANVAS_PAINT_ARG0;

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

  // void drawText(paint, str, x, y)
  //
  // Draw the string `str` with the bottom left corner starting at (`x`, `y`).
  static void drawText(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    SKCANVAS_PAINT_ARG0;

    v8::String::Utf8Value utf8(args[1]);
    canvas->drawText(*utf8, utf8.length(),
                     SkDoubleToScalar(args[2]->NumberValue()),
                     SkDoubleToScalar(args[3]->NumberValue()),
                     *paint);
    return args.GetReturnValue().SetUndefined();
  }

  // void drawTextOnPathHV(paint, path, str, hoffset, voffset)
  //
  // Draw the string `str` along the path `path`, starting along the path at
  // `hoffset` and above or below the path by `voffset`.
  static void drawTextOnPathHV(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    SKCANVAS_PAINT_ARG0;

    if (!SkPathWrapper::HasInstance(isolate, args[1]))
      return args.GetReturnValue().SetUndefined();

    SkPath* path = SkPathWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[1]));

    v8::String::Utf8Value utf8(args[2]);
    canvas->drawTextOnPathHV(*utf8, utf8.length(), *path,
                             SkDoubleToScalar(args[3]->NumberValue()),
                             SkDoubleToScalar(args[4]->NumberValue()),
                             *paint);
    return args.GetReturnValue().SetUndefined();
  }

  // void translate(x, y)
  //
  // Translate the canvas by `x` and `y`.
  static void translate(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->translate(SkDoubleToScalar(args[0]->NumberValue()),
                      SkDoubleToScalar(args[1]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  // void scale(x, y)
  //
  // Scale the canvas by `x` and `y`.
  static void scale(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->scale(SkDoubleToScalar(args[0]->NumberValue()),
                  SkDoubleToScalar(args[1]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  // void rotate(degrees)
  //
  // Rotate the canvas by `degrees` degrees (not radians).
  static void rotate(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->rotate(SkDoubleToScalar(args[0]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  // void skew(x, y)
  //
  // Skew the canvas by `x` and `y`.
  static void skew(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->skew(SkDoubleToScalar(args[0]->NumberValue()),
                 SkDoubleToScalar(args[1]->NumberValue()));
    return args.GetReturnValue().SetUndefined();
  }

  // void save()
  //
  // Save the transform matrix to the matrix stack.
  static void save(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->save();
    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(saveLayer, 0)
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->saveLayer(NULL, NULL);  // TODO: arguments.
    return args.GetReturnValue().SetUndefined();
  }

  // void restore()
  //
  // Restore the transform matrix from the matrix stack.
  static void restore(const v8::FunctionCallbackInfo<v8::Value>& args) {
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->restore();
    return args.GetReturnValue().SetUndefined();
  }

  // void writeImage(typestr, filename)
  //
  // Write the current contents of the canvas as an image named `filename`.  The
  // `typestr` parameter selects the image format.  Currently only 'png' is
  // supported.
  static void writeImage(const v8::FunctionCallbackInfo<v8::Value>& args) {
    if (args.Length() < 2)
      return v8_utils::ThrowError(isolate, "Wrong number of arguments.");

    // NOTE(deanm): Would be nice if we could just peekPixels, but we need to unpremultiply.
    SkCanvas* canvas = ExtractPointer(args.Holder());
    SkImageInfo image_info =
        canvas->imageInfo().makeColorType(kN32_SkColorType).makeAlphaType(kUnpremul_SkAlphaType);

    int width = image_info.width(), height = image_info.height();

    void* pixels = malloc(width * height * 4);

    if (!pixels)
      return v8_utils::ThrowError(isolate, "writeImage: couldn't allocate pixels.");

    ScopedFree freepixels(pixels);

    if (!canvas->readPixels(image_info, pixels, 4 * width, 0, 0))
      return v8_utils::ThrowError(isolate, "writeImage: couldn't readPixels().");

    writeImageHelper(args, width, height, pixels, NULL, true);

    return;
  }

  // void writePDF()
  //
  // Write the contents of a vector-mode SkCanvas (created with createForPDF) to
  // the filename supplied when created with createForPDF.
  //
  // The canvas is no longer usable after a call to writePDF.  A PDF can
  // only be written once and no further calls can be made on the canvas.
  DEFINE_METHOD(writePDF, 0)
    SkDocument* doc = ExtractDocumentPointer(args.Holder());

    if (!doc)
      return v8_utils::ThrowError(isolate, "Not a PDF canvas.");

    args.Holder()->SetAlignedPointerInInternalField(0, NULL);  // Clear SkCanvas*
    doc->close();

    return args.GetReturnValue().SetUndefined();
  }

  // void flush()
  //
  // Flushes any pending operations to the underlying surface, for example
  // when using a GPU backed canvas.  Normally this will be called for you at
  // the appropriate place before drawing, so it is unlikely to call it directly.
  DEFINE_METHOD(flush, 0)
    SkCanvas* canvas = ExtractPointer(args.Holder());
    canvas->flush();
    return args.GetReturnValue().SetUndefined();
  }
};

#if PLASK_OSX
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
      METHOD_ENTRY( isPlaying ),
      METHOD_ENTRY( pause ),
      METHOD_ENTRY( play ),
      METHOD_ENTRY( resume ),
      METHOD_ENTRY( stop ),
      METHOD_ENTRY( volume ),
      METHOD_ENTRY( setVolume ),
      METHOD_ENTRY( currentTime ),
      METHOD_ENTRY( setCurrentTime ),
      METHOD_ENTRY( loops ),
      METHOD_ENTRY( setLoops ),
      METHOD_ENTRY( duration ),
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
#endif  // PLASK_OSX

void NSOpenGLContextWrapper::texImage2DSkCanvasB(
    const v8::FunctionCallbackInfo<v8::Value>& args) {
  if (args.Length() != 3)
    return v8_utils::ThrowError(isolate, "Wrong number of arguments.");

  if (!args[2]->IsObject() && !SkCanvasWrapper::HasInstance(isolate, args[2]))
    return v8_utils::ThrowError(isolate, "Expected image to be an SkCanvas instance.");

#if PLASK_OSX
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
#else
    return v8_utils::ThrowError(isolate, "Unimplemented.");
#endif
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

#if PLASK_OSX
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
#endif

  return args.GetReturnValue().SetUndefined();
}

#if PLASK_COREMIDI
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
      METHOD_ENTRY( destinations ),
      METHOD_ENTRY( openDestination ),
      METHOD_ENTRY( createVirtual ),
      METHOD_ENTRY( sendData ),
      METHOD_ENTRY( close ),
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
    return (MIDIEndpointRef)((intptr_t)obj->GetAlignedPointerFromInternalField(0) >> 2);
  }

  static MIDIPortRef ExtractPort(v8::Handle<v8::Object> obj) {
    return (MIDIPortRef)((intptr_t)obj->GetAlignedPointerFromInternalField(1) >> 2);
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

    uint64_t future_ns = args[1]->IntegerValue();

    MIDIEndpointRef endpoint = ExtractEndpoint(args.Holder());

    if (!endpoint) {
      return v8_utils::ThrowError(isolate, "Can't send on midi without an endpoint.");
    }

    MIDIPortRef port = ExtractPort(args.Holder());
    MIDITimeStamp timestamp = AudioGetCurrentHostTime();
    timestamp += future_ns;
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
    args.This()->SetAlignedPointerInInternalField(0, (void*)((intptr_t)endpoint << 2));
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

    args.This()->SetAlignedPointerInInternalField(0, (void*)((intptr_t)destination << 2));
    args.This()->SetAlignedPointerInInternalField(1, (void*)((intptr_t)port << 2));

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

  DEFINE_METHOD(close, 0)
    MIDIEndpointRef endpoint = ExtractEndpoint(args.Holder());
    MIDIPortRef port = ExtractPort(args.Holder());

    if (port) {  // Non-virtual connections
      MIDIPortDispose(port);
    } else if (endpoint) {  // Virtual
      // NOTE: Don't want to call MIDIEndpointDispose except when it was
      // created by us with createVirtual, otherwise we will close the source
      // across the entire CoreMIDI system, not just our process.
      MIDIEndpointDispose(endpoint);
    }

    args.This()->SetAlignedPointerInInternalField(0, 0);
    args.This()->SetAlignedPointerInInternalField(1, 0);

    return args.GetReturnValue().SetUndefined();
  }
};

class CAMIDIDestinationWrapper {
 private:
  struct State {
    MIDIEndpointRef endpoint;
    MIDIEndpointRef port;
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
      METHOD_ENTRY( createVirtual ),
      METHOD_ENTRY( sources ),
      METHOD_ENTRY( openSource ),
      METHOD_ENTRY( syncClocks ),
      METHOD_ENTRY( getPipeDescriptor ),
      METHOD_ENTRY( close ),
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
    state->endpoint = 0;
    state->port = 0;
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
    state->port     = port;

    return args.GetReturnValue().SetUndefined();
  }

  DEFINE_METHOD(close, 0)
    State* state = ExtractPointer(args.Holder());
    if (state->port) {  // Non-virtual connections
      MIDIPortDisconnectSource(state->port, state->endpoint);
      MIDIPortDispose(state->port);
    } else if (state->endpoint) {  // Virtual
      // NOTE: Don't want to call MIDIEndpointDispose except when it was
      // created by us with createVirtual, otherwise we will close the source
      // across the entire CoreMIDI system, not just our process.
      MIDIEndpointDispose(state->endpoint);
    }

    state->endpoint = 0;
    state->port     = 0;

    return args.GetReturnValue().SetUndefined();
  }
};
#endif  // PLASK_COREMIDI


#if PLASK_OSX
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
      METHOD_ENTRY( objcMethods ),
      METHOD_ENTRY( invokeVoid0 ),
      METHOD_ENTRY( invokeVoid1s ),
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
      METHOD_ENTRY( execute ),
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
      METHOD_ENTRY( currentDuration ),
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
      METHOD_ENTRY( prerollAtRate ),
      METHOD_ENTRY( currentLoadedTimeRanges ),
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

  // new AVPlayer(NSOpenGLContext? gl)
  //
  // Create a new instance of an AVPlayer.  For video playback a `gl` context
  // must be specified for the creation of textures.  For audio only playback
  // the context argument can be omitted.
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

  // float volume()
  //
  // Return the current audio volume setting.
  DEFINE_METHOD(volume, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [player volume]));
  }

  // void setVolume(float vol)
  //
  // Set the audio volume.
  DEFINE_METHOD(setVolume, 1)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    [player setVolume:args[0]->NumberValue()];
    return args.GetReturnValue().SetUndefined();
  }

  // void setLoops(bool loops)
  //
  // Set whether or not the playlist loops.
  DEFINE_METHOD(setLoops, 1)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    [player setLoops:args[0]->BooleanValue()];
    return args.GetReturnValue().SetUndefined();
  }

  // void appendURL(string url)
  //
  // Add a URL to the playlist.
  DEFINE_METHOD(appendURL, 1)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    v8::String::Utf8Value url(args[0]);
    NSURL* nsurl = [NSURL URLWithString:[NSString stringWithUTF8String:*url]];
    [player appendURL:nsurl];
    return args.GetReturnValue().SetUndefined();
  }

  // void appendFile(string path)
  //
  // Add a file to the playlist.
  DEFINE_METHOD(appendFile, 1)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    v8::String::Utf8Value filename(args[0]);
    NSURL* nsurl = [NSURL fileURLWithPath:[NSString stringWithUTF8String:*filename]];
    [player appendURL:nsurl];
    return args.GetReturnValue().SetUndefined();
  }

  // void removeAll()
  //
  // Remove all entries from the playlist.
  DEFINE_METHOD(removeAll, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    [player removeAllItems];
    return args.GetReturnValue().SetUndefined();
  }

  // void playNext()
  //
  // Play the next entry in the playlist.
  DEFINE_METHOD(playNext, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    [player advanceToNextItem];
    return args.GetReturnValue().SetUndefined();
  }

  // float rate()
  //
  // Return the current playback rate.
  DEFINE_METHOD(rate, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    return args.GetReturnValue().Set(v8::Number::New(isolate, [player rate]));
  }

  // void setRate(float rate)
  //
  // Set the current playback rate.
  DEFINE_METHOD(setRate, 1)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    [player setRate:args[0]->NumberValue()];
    return args.GetReturnValue().SetUndefined();
  }

  // string status()
  DEFINE_METHOD(status, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    AVPlayerStatus status = [player status];
    const char* str = status == AVPlayerStatusUnknown ? "unknown" :
                          status == AVPlayerStatusReadyToPlay ? "ready" : "failed";
    return args.GetReturnValue().Set(v8::String::NewFromUtf8(isolate, str));
  }

  // int error()
  DEFINE_METHOD(error, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    NSError* error = [player error];
    return args.GetReturnValue().Set(static_cast<int32_t>([error code]));
  }

  // void play()
  DEFINE_METHOD(play, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    [player play];
    return args.GetReturnValue().SetUndefined();
  }

  // float currentTime()
  DEFINE_METHOD(currentTime, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    CMTime time = [player currentTime];
    if ((time.flags & kCMTimeFlags_Valid) == 0)
      return args.GetReturnValue().SetNull();
    return args.GetReturnValue().Set(CMTimeGetSeconds(time));
  }

  // void seekToTime(float secs)
  DEFINE_METHOD(seekToTime, 1)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());

    CMTime curtime = [player currentTime];
    CMTime time = (curtime.flags & kCMTimeFlags_Valid) ?
        CMTimeMakeWithSeconds(args[0]->NumberValue(), curtime.timescale) :
        CMTimeMakeWithSeconds(args[0]->NumberValue(), 50000);  // FIXME

    // We probably want max precision to be default ?
    [player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    return args.GetReturnValue().SetUndefined();
  }

  // float currentDuration()
  DEFINE_METHOD(currentDuration, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    AVPlayerItem* item = [player currentItem];
    if (item == nil)
      return args.GetReturnValue().SetNull();
    return args.GetReturnValue().Set(CMTimeGetSeconds(item.duration));
  }

  // object currentFrameTexture()
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

  // bool prerollAtRate(float rate)
  DEFINE_METHOD(prerollAtRate, 1)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    // 'AVPlayer cannot service a preroll request until its status is AVPlayerStatusReadyToPlay.'
    if ([player status] != AVPlayerStatusReadyToPlay)
      return args.GetReturnValue().Set(false);
    [player prerollAtRate:args[0]->NumberValue() completionHandler:^(BOOL finished){ }];
    return args.GetReturnValue().Set(true);
  }

  // float[ ] currentLoadedTimeRanges()
  DEFINE_METHOD(currentLoadedTimeRanges, 0)
    TextureAVPlayer* player = ExtractPlayerPointer(args.This());
    AVPlayerItem* item = [player currentItem];
    if (item == nil)
      return args.GetReturnValue().SetNull();

    NSArray* ranges = item.loadedTimeRanges;
    v8::Local<v8::Array> jsranges = v8::Array::New(isolate, [ranges count] * 2);
    for (int i = 0; i < [ranges count]; ++i) {
      CMTimeRange range = [[ranges objectAtIndex:i] CMTimeRangeValue];
      jsranges->Set(v8::Integer::New(isolate, i*2),
                    v8::Number::New(isolate, CMTimeGetSeconds(range.start)));
      jsranges->Set(v8::Integer::New(isolate, i*2+1),
                    v8::Number::New(isolate, CMTimeGetSeconds(range.duration)));
    }
    return args.GetReturnValue().Set(jsranges);
  }
};

#endif  // PLASK_OSX

}  // namespace

#if PLASK_OSX
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

  // The drag doesn't count as an NSEvent, so the drag is dispatched from
  // within NSApplication nextEventMatchingMask, but it doesn't return.  So we
  // want to wake up the loop to reflect any possible event loop changes caused
  // by the JavaScript code just executed.  See main.mm kqueue_checker_thread.
  NSEvent* e = [NSEvent otherEventWithType:NSApplicationDefined
                                      location:NSMakePoint(0, 0)
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:0
                                       context:nil
                                       subtype:8  // Arbitrary
                                         data1:0
                                         data2:0];
  [NSApp postEvent:e atStart:YES];

  return YES;
}

/*
- (void)concludeDragOperation:(id<NSDraggingInfo>)sender {
  printf("Conclude drag\n");
  NSLog(@"%@",[NSThread callStackSymbols]);
}
*/

@end

@implementation WindowDelegate

-(void)windowDidMove:(NSNotification *)notification {
}

@end
#endif  // PLASK_OSX

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
#if PLASK_OSX
  obj->Set(v8::String::NewFromUtf8(isolate, "NSSound"),
           PersistentToLocal(isolate, NSSoundWrapper::GetTemplate(isolate)));
#endif
#if PLASK_COREMIDI
  obj->Set(v8::String::NewFromUtf8(isolate, "CAMIDISource"),
           PersistentToLocal(isolate, CAMIDISourceWrapper::GetTemplate(isolate)));
  obj->Set(v8::String::NewFromUtf8(isolate, "CAMIDIDestination"),
           PersistentToLocal(isolate, CAMIDIDestinationWrapper::GetTemplate(isolate)));
#endif
#if PLASK_OSX
  obj->Set(v8::String::NewFromUtf8(isolate, "SBApplication"),
           PersistentToLocal(isolate, SBApplicationWrapper::GetTemplate(isolate)));
  obj->Set(v8::String::NewFromUtf8(isolate, "NSAppleScript"),
           PersistentToLocal(isolate, NSAppleScriptWrapper::GetTemplate(isolate)));
  obj->Set(v8::String::NewFromUtf8(isolate, "AVPlayer"),
           PersistentToLocal(isolate, AVPlayerWrapper::GetTemplate(isolate)));
#endif

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
