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
#include "v8_typed_array.h"

#include "FreeImage.h"

#include <string>

#include <CoreFoundation/CoreFoundation.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreMIDI/CoreMIDI.h>

#include "third_party/skia/include/core/SkBitmap.h"
#include "third_party/skia/include/core/SkCanvas.h"
#include "third_party/skia/include/core/SkColorPriv.h"  // For color ordering.
#include "third_party/skia/include/core/SkDevice.h"
#include "third_party/skia/include/core/SkString.h"
#include "third_party/skia/include/core/SkTypeface.h"
#include "third_party/skia/include/core/SkUnPreMultiply.h"
#include "third_party/skia/include/core/SkXfermode.h"
#include "third_party/skia/include/utils/SkParsePath.h"
#include "third_party/skia/include/effects/SkGradientShader.h"
#include "third_party/skia/include/pdf/SkPDFDevice.h"
#include "third_party/skia/include/pdf/SkPDFDocument.h"

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

@interface WrappedNSWindow: NSWindow {
  v8::Persistent<v8::Function> event_callback_;
}

-(void)setEventCallbackWithHandle:(v8::Handle<v8::Function>)func;

@end

@interface WindowDelegate : NSObject <NSWindowDelegate> {
}

@end

@interface BlitImageView : NSView {
  SkBitmap* bitmap_;
}

-(id)initWithSkBitmap:(SkBitmap*)bitmap;

@end

@interface BlitGLView : NSOpenGLView {
}

@end

namespace {

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

struct BatchedConstants {
  const char* name;
  uint32_t val;
};

struct BatchedMethods {
  const char* name;
  v8::Handle<v8::Value> (*func)(const v8::Arguments& args);
};


class WebGLActiveInfo {
 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&WebGLActiveInfo::V8New));
    ft_cache->SetClassName(v8::String::New("WebGLActiveInfo"));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(0);

    v8::Local<v8::Signature> default_signature = v8::Signature::New(ft_cache);

    return ft_cache;
  }

  static bool HasInstance(v8::Handle<v8::Value> value) {
    return GetTemplate()->HasInstance(value);
  }

  static v8::Handle<v8::Value> NewFromSizeTypeName(GLint size,
                                                   GLenum type,
                                                   const char* name) {
    v8::Local<v8::Object> obj = WebGLActiveInfo::GetTemplate()->
            InstanceTemplate()->NewInstance();
    obj->Set(v8::String::New("size"), v8::Integer::New(size), v8::ReadOnly);
    obj->Set(v8::String::New("type"),
             v8::Integer::NewFromUnsigned(type),
             v8::ReadOnly);
    obj->Set(v8::String::New("name"), v8::String::New(name), v8::ReadOnly);
    return obj;
  }

 private:
  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    return args.This();
  }
};

class WebGLProgram {
 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&WebGLProgram::V8New));
    ft_cache->SetClassName(v8::String::New("WebGLProgram"));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // GLuint ID.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(ft_cache);

    return ft_cache;
  }

  static bool HasInstance(v8::Handle<v8::Value> value) {
    return GetTemplate()->HasInstance(value);
  }

  static v8::Handle<v8::Value> NewFromID(GLuint id) {
    v8::Local<v8::Object> obj = WebGLProgram::GetTemplate()->
            InstanceTemplate()->NewInstance();
    obj->SetInternalField(0, v8::Integer::NewFromUnsigned(id));
    return obj;
  }

  static GLuint ExtractIDFromValue(v8::Handle<v8::Value> value) {
    return v8::Handle<v8::Object>::Cast(value)->
        GetInternalField(0)->Uint32Value();
  }

 private:
  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    // TODO(deanm): How to throw an exception when called from JavaScript but
    // not from NewFromID?
    //return v8_utils::ThrowTypeError("Type error.");
    return args.This();
  }
};


class WebGLUniformLocation {
 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&WebGLUniformLocation::V8New));
    ft_cache->SetClassName(v8::String::New("WebGLUniformLocation"));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // GLint location.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(ft_cache);

    return ft_cache;
  }

  static bool HasInstance(v8::Handle<v8::Value> value) {
    return GetTemplate()->HasInstance(value);
  }

  static v8::Handle<v8::Value> NewFromLocation(GLint location) {
    v8::Local<v8::Object> obj = WebGLUniformLocation::GetTemplate()->
            InstanceTemplate()->NewInstance();
    obj->SetInternalField(0, v8::Integer::New(location));
    return obj;
  }

  static GLint ExtractLocationFromValue(v8::Handle<v8::Value> value) {
    return v8::Handle<v8::Object>::Cast(value)->
        GetInternalField(0)->Int32Value();
  }

 private:
  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    // TODO(deanm): How to throw an exception when called from JavaScript but
    // not from NewFromLocation?
    //return v8_utils::ThrowTypeError("Type error.");
    return args.This();
  }
};


class SyphonServerWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&SyphonServerWrapper::V8New));
    ft_cache->SetClassName(v8::String::New("SyphonServer"));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // SyphonServer

    v8::Local<v8::Signature> default_signature = v8::Signature::New(ft_cache);

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
      ft_cache->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::New(methods[i].name),
                    v8::FunctionTemplate::New(methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    return ft_cache;
  }

  static bool HasInstance(v8::Handle<v8::Value> value) {
    return GetTemplate()->HasInstance(value);
  }

  static SyphonServer* ExtractSyphonServerPointer(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<SyphonServer*>(obj->GetPointerFromInternalField(0));
  }

  static v8::Handle<v8::Value> NewFromSyphonServer(SyphonServer* server) {
    v8::Local<v8::Object> obj = SyphonServerWrapper::GetTemplate()->
            InstanceTemplate()->NewInstance();
    obj->SetPointerInInternalField(0, server);
    return obj;
  }

 private:
  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    return args.This();
  }

  static v8::Handle<v8::Value> publishFrameTexture(const v8::Arguments& args) {
    if (args.Length() != 9)
      return v8_utils::ThrowError("Wrong number of arguments.");

    SyphonServer* server = ExtractSyphonServerPointer(args.This());
    [server publishFrameTexture:args[0]->Uint32Value()
            textureTarget:args[1]->Uint32Value()
            imageRegion:NSMakeRect(args[2]->Int32Value(),
                                   args[3]->Int32Value(),
                                   args[4]->Int32Value(),
                                   args[5]->Int32Value())
            textureDimensions:NSMakeSize(args[6]->Int32Value(),
                                         args[7]->Int32Value())
            flipped:args[8]->BooleanValue()];
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> bindToDrawFrameOfSize(
      const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");
    SyphonServer* server = ExtractSyphonServerPointer(args.This());
    BOOL res = [server bindToDrawFrameOfSize:NSMakeSize(args[0]->Int32Value(),
                                                        args[1]->Int32Value())];
    return v8::Boolean::New(res);
  }

  static v8::Handle<v8::Value> unbindAndPublish(const v8::Arguments& args) {
    SyphonServer* server = ExtractSyphonServerPointer(args.This());
    [server unbindAndPublish];
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> hasClients(const v8::Arguments& args) {
    SyphonServer* server = ExtractSyphonServerPointer(args.This());
    return v8::Boolean::New([server hasClients]);
  }
};


class NSOpenGLContextWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&NSOpenGLContextWrapper::V8New));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(1);

    v8::Local<v8::Signature> default_signature = v8::Signature::New(ft_cache);

    // Configure the template...
    static BatchedConstants constants[] = {
      /* ClearBufferMask */
      { "DEPTH_BUFFER_BIT", 0x00000100 },
      { "STENCIL_BUFFER_BIT", 0x00000400 },
      { "COLOR_BUFFER_BIT", 0x00004000 },

      /* Boolean */
      { "FALSE", 0 },
      { "TRUE", 1 },

      /* BeginMode */
      { "POINTS", 0x0000 },
      { "LINES", 0x0001 },
      { "LINE_LOOP", 0x0002 },
      { "LINE_STRIP", 0x0003 },
      { "TRIANGLES", 0x0004 },
      { "TRIANGLE_STRIP", 0x0005 },
      { "TRIANGLE_FAN", 0x0006 },

      /* AlphaFunction (not supported in ES20) */
      /*      NEVER */
      /*      LESS */
      /*      EQUAL */
      /*      LEQUAL */
      /*      GREATER */
      /*      NOTEQUAL */
      /*      GEQUAL */
      /*      ALWAYS */

      /* BlendingFactorDest */
      { "ZERO", 0 },
      { "ONE", 1 },
      { "SRC_COLOR", 0x0300 },
      { "ONE_MINUS_SRC_COLOR", 0x0301 },
      { "SRC_ALPHA", 0x0302 },
      { "ONE_MINUS_SRC_ALPHA", 0x0303 },
      { "DST_ALPHA", 0x0304 },
      { "ONE_MINUS_DST_ALPHA", 0x0305 },

      /* BlendingFactorSrc */
      /*      ZERO */
      /*      ONE */
      { "DST_COLOR", 0x0306 },
      { "ONE_MINUS_DST_COLOR", 0x0307 },
      { "SRC_ALPHA_SATURATE", 0x0308 },
      /*      SRC_ALPHA */
      /*      ONE_MINUS_SRC_ALPHA */
      /*      DST_ALPHA */
      /*      ONE_MINUS_DST_ALPHA */

      /* BlendEquationSeparate */
      { "FUNC_ADD", 0x8006 },
      { "BLEND_EQUATION", 0x8009 },
      { "BLEND_EQUATION_RGB", 0x8009 },   /* same as BLEND_EQUATION */
      { "BLEND_EQUATION_ALPHA", 0x883D },

      /* BlendSubtract */
      { "FUNC_SUBTRACT", 0x800A },
      { "FUNC_REVERSE_SUBTRACT", 0x800B },

      /* Separate Blend Functions */
      { "BLEND_DST_RGB", 0x80C8 },
      { "BLEND_SRC_RGB", 0x80C9 },
      { "BLEND_DST_ALPHA", 0x80CA },
      { "BLEND_SRC_ALPHA", 0x80CB },
      { "CONSTANT_COLOR", 0x8001 },
      { "ONE_MINUS_CONSTANT_COLOR", 0x8002 },
      { "CONSTANT_ALPHA", 0x8003 },
      { "ONE_MINUS_CONSTANT_ALPHA", 0x8004 },
      { "BLEND_COLOR", 0x8005 },

      /* Buffer Objects */
      { "ARRAY_BUFFER", 0x8892 },
      { "ELEMENT_ARRAY_BUFFER", 0x8893 },
      { "ARRAY_BUFFER_BINDING", 0x8894 },
      { "ELEMENT_ARRAY_BUFFER_BINDING", 0x8895 },

      { "STREAM_DRAW", 0x88E0 },
      { "STATIC_DRAW", 0x88E4 },
      { "DYNAMIC_DRAW", 0x88E8 },

      { "BUFFER_SIZE", 0x8764 },
      { "BUFFER_USAGE", 0x8765 },

      { "CURRENT_VERTEX_ATTRIB", 0x8626 },

      /* CullFaceMode */
      { "FRONT", 0x0404 },
      { "BACK", 0x0405 },
      { "FRONT_AND_BACK", 0x0408 },

      /* DepthFunction */
      /*      NEVER */
      /*      LESS */
      /*      EQUAL */
      /*      LEQUAL */
      /*      GREATER */
      /*      NOTEQUAL */
      /*      GEQUAL */
      /*      ALWAYS */

      /* EnableCap */
      { "TEXTURE_2D", 0x0DE1 },
      { "CULL_FACE", 0x0B44 },
      { "BLEND", 0x0BE2 },
      { "DITHER", 0x0BD0 },
      { "STENCIL_TEST", 0x0B90 },
      { "DEPTH_TEST", 0x0B71 },
      { "SCISSOR_TEST", 0x0C11 },
      { "POLYGON_OFFSET_FILL", 0x8037 },
      { "SAMPLE_ALPHA_TO_COVERAGE", 0x809E },
      { "SAMPLE_COVERAGE", 0x80A0 },

      /* ErrorCode */
      { "NO_ERROR", 0 },
      { "INVALID_ENUM", 0x0500 },
      { "INVALID_VALUE", 0x0501 },
      { "INVALID_OPERATION", 0x0502 },
      { "OUT_OF_MEMORY", 0x0505 },

      /* FrontFaceDirection */
      { "CW", 0x0900 },
      { "CCW", 0x0901 },

      /* GetPName */
      { "LINE_WIDTH", 0x0B21 },
      { "ALIASED_POINT_SIZE_RANGE", 0x846D },
      { "ALIASED_LINE_WIDTH_RANGE", 0x846E },
      { "CULL_FACE_MODE", 0x0B45 },
      { "FRONT_FACE", 0x0B46 },
      { "DEPTH_RANGE", 0x0B70 },
      { "DEPTH_WRITEMASK", 0x0B72 },
      { "DEPTH_CLEAR_VALUE", 0x0B73 },
      { "DEPTH_FUNC", 0x0B74 },
      { "STENCIL_CLEAR_VALUE", 0x0B91 },
      { "STENCIL_FUNC", 0x0B92 },
      { "STENCIL_FAIL", 0x0B94 },
      { "STENCIL_PASS_DEPTH_FAIL", 0x0B95 },
      { "STENCIL_PASS_DEPTH_PASS", 0x0B96 },
      { "STENCIL_REF", 0x0B97 },
      { "STENCIL_VALUE_MASK", 0x0B93 },
      { "STENCIL_WRITEMASK", 0x0B98 },
      { "STENCIL_BACK_FUNC", 0x8800 },
      { "STENCIL_BACK_FAIL", 0x8801 },
      { "STENCIL_BACK_PASS_DEPTH_FAIL", 0x8802 },
      { "STENCIL_BACK_PASS_DEPTH_PASS", 0x8803 },
      { "STENCIL_BACK_REF", 0x8CA3 },
      { "STENCIL_BACK_VALUE_MASK", 0x8CA4 },
      { "STENCIL_BACK_WRITEMASK", 0x8CA5 },
      { "VIEWPORT", 0x0BA2 },
      { "SCISSOR_BOX", 0x0C10 },
      /*      SCISSOR_TEST */
      { "COLOR_CLEAR_VALUE", 0x0C22 },
      { "COLOR_WRITEMASK", 0x0C23 },
      { "UNPACK_ALIGNMENT", 0x0CF5 },
      { "PACK_ALIGNMENT", 0x0D05 },
      { "MAX_TEXTURE_SIZE", 0x0D33 },
      { "MAX_VIEWPORT_DIMS", 0x0D3A },
      { "SUBPIXEL_BITS", 0x0D50 },
      { "RED_BITS", 0x0D52 },
      { "GREEN_BITS", 0x0D53 },
      { "BLUE_BITS", 0x0D54 },
      { "ALPHA_BITS", 0x0D55 },
      { "DEPTH_BITS", 0x0D56 },
      { "STENCIL_BITS", 0x0D57 },
      { "POLYGON_OFFSET_UNITS", 0x2A00 },
      /*      POLYGON_OFFSET_FILL */
      { "POLYGON_OFFSET_FACTOR", 0x8038 },
      { "TEXTURE_BINDING_2D", 0x8069 },
      { "SAMPLE_BUFFERS", 0x80A8 },
      { "SAMPLES", 0x80A9 },
      { "SAMPLE_COVERAGE_VALUE", 0x80AA },
      { "SAMPLE_COVERAGE_INVERT", 0x80AB },

      /* GetTextureParameter */
      /*      TEXTURE_MAG_FILTER */
      /*      TEXTURE_MIN_FILTER */
      /*      TEXTURE_WRAP_S */
      /*      TEXTURE_WRAP_T */

      { "NUM_COMPRESSED_TEXTURE_FORMATS", 0x86A2 },
      { "COMPRESSED_TEXTURE_FORMATS", 0x86A3 },

      /* HintMode */
      { "DONT_CARE", 0x1100 },
      { "FASTEST", 0x1101 },
      { "NICEST", 0x1102 },

      /* HintTarget */
      { "GENERATE_MIPMAP_HINT", 0x8192 },

      /* DataType */
      { "BYTE", 0x1400 },
      { "UNSIGNED_BYTE", 0x1401 },
      { "SHORT", 0x1402 },
      { "UNSIGNED_SHORT", 0x1403 },
      { "INT", 0x1404 },
      { "UNSIGNED_INT", 0x1405 },
      { "FLOAT", 0x1406 },
      { "FIXED", 0x140C },

      /* PixelFormat */
      { "DEPTH_COMPONENT", 0x1902 },
      { "ALPHA", 0x1906 },
      { "RGB", 0x1907 },
      { "RGBA", 0x1908 },
      { "LUMINANCE", 0x1909 },
      { "LUMINANCE_ALPHA", 0x190A },

      /* PixelType */
      /*      UNSIGNED_BYTE */
      { "UNSIGNED_SHORT_4_4_4_4", 0x8033 },
      { "UNSIGNED_SHORT_5_5_5_1", 0x8034 },
      { "UNSIGNED_SHORT_5_6_5", 0x8363 },

      /* Shaders */
      { "FRAGMENT_SHADER", 0x8B30 },
      { "VERTEX_SHADER", 0x8B31 },
      { "MAX_VERTEX_ATTRIBS", 0x8869 },
      { "MAX_VERTEX_UNIFORM_VECTORS", 0x8DFB },
      { "MAX_VARYING_VECTORS", 0x8DFC },
      { "MAX_COMBINED_TEXTURE_IMAGE_UNITS", 0x8B4D },
      { "MAX_VERTEX_TEXTURE_IMAGE_UNITS", 0x8B4C },
      { "MAX_TEXTURE_IMAGE_UNITS", 0x8872 },
      { "MAX_FRAGMENT_UNIFORM_VECTORS", 0x8DFD },
      { "SHADER_TYPE", 0x8B4F },
      { "DELETE_STATUS", 0x8B80 },
      { "LINK_STATUS", 0x8B82 },
      { "VALIDATE_STATUS", 0x8B83 },
      { "ATTACHED_SHADERS", 0x8B85 },
      { "ACTIVE_UNIFORMS", 0x8B86 },
      { "ACTIVE_UNIFORM_MAX_LENGTH", 0x8B87 },
      { "ACTIVE_ATTRIBUTES", 0x8B89 },
      { "ACTIVE_ATTRIBUTE_MAX_LENGTH", 0x8B8A },
      { "SHADING_LANGUAGE_VERSION", 0x8B8C },
      { "CURRENT_PROGRAM", 0x8B8D },

      /* StencilFunction */
      { "NEVER", 0x0200 },
      { "LESS", 0x0201 },
      { "EQUAL", 0x0202 },
      { "LEQUAL", 0x0203 },
      { "GREATER", 0x0204 },
      { "NOTEQUAL", 0x0205 },
      { "GEQUAL", 0x0206 },
      { "ALWAYS", 0x0207 },

      /* StencilOp */
      /*      ZERO */
      { "KEEP", 0x1E00 },
      { "REPLACE", 0x1E01 },
      { "INCR", 0x1E02 },
      { "DECR", 0x1E03 },
      { "INVERT", 0x150A },
      { "INCR_WRAP", 0x8507 },
      { "DECR_WRAP", 0x8508 },

      /* StringName */
      { "VENDOR", 0x1F00 },
      { "RENDERER", 0x1F01 },
      { "VERSION", 0x1F02 },
      { "EXTENSIONS", 0x1F03 },

      /* TextureMagFilter */
      { "NEAREST", 0x2600 },
      { "LINEAR", 0x2601 },

      /* TextureMinFilter */
      /*      NEAREST */
      /*      LINEAR */
      { "NEAREST_MIPMAP_NEAREST", 0x2700 },
      { "LINEAR_MIPMAP_NEAREST", 0x2701 },
      { "NEAREST_MIPMAP_LINEAR", 0x2702 },
      { "LINEAR_MIPMAP_LINEAR", 0x2703 },

      /* TextureParameterName */
      { "TEXTURE_MAG_FILTER", 0x2800 },
      { "TEXTURE_MIN_FILTER", 0x2801 },
      { "TEXTURE_WRAP_S", 0x2802 },
      { "TEXTURE_WRAP_T", 0x2803 },

      /* TextureTarget */
      /*      TEXTURE_2D */
      { "TEXTURE", 0x1702 },

      { "TEXTURE_CUBE_MAP", 0x8513 },
      { "TEXTURE_BINDING_CUBE_MAP", 0x8514 },
      { "TEXTURE_CUBE_MAP_POSITIVE_X", 0x8515 },
      { "TEXTURE_CUBE_MAP_NEGATIVE_X", 0x8516 },
      { "TEXTURE_CUBE_MAP_POSITIVE_Y", 0x8517 },
      { "TEXTURE_CUBE_MAP_NEGATIVE_Y", 0x8518 },
      { "TEXTURE_CUBE_MAP_POSITIVE_Z", 0x8519 },
      { "TEXTURE_CUBE_MAP_NEGATIVE_Z", 0x851A },
      { "MAX_CUBE_MAP_TEXTURE_SIZE", 0x851C },

      /* TextureUnit */
      { "TEXTURE0", 0x84C0 },
      { "TEXTURE1", 0x84C1 },
      { "TEXTURE2", 0x84C2 },
      { "TEXTURE3", 0x84C3 },
      { "TEXTURE4", 0x84C4 },
      { "TEXTURE5", 0x84C5 },
      { "TEXTURE6", 0x84C6 },
      { "TEXTURE7", 0x84C7 },
      { "TEXTURE8", 0x84C8 },
      { "TEXTURE9", 0x84C9 },
      { "TEXTURE10", 0x84CA },
      { "TEXTURE11", 0x84CB },
      { "TEXTURE12", 0x84CC },
      { "TEXTURE13", 0x84CD },
      { "TEXTURE14", 0x84CE },
      { "TEXTURE15", 0x84CF },
      { "TEXTURE16", 0x84D0 },
      { "TEXTURE17", 0x84D1 },
      { "TEXTURE18", 0x84D2 },
      { "TEXTURE19", 0x84D3 },
      { "TEXTURE20", 0x84D4 },
      { "TEXTURE21", 0x84D5 },
      { "TEXTURE22", 0x84D6 },
      { "TEXTURE23", 0x84D7 },
      { "TEXTURE24", 0x84D8 },
      { "TEXTURE25", 0x84D9 },
      { "TEXTURE26", 0x84DA },
      { "TEXTURE27", 0x84DB },
      { "TEXTURE28", 0x84DC },
      { "TEXTURE29", 0x84DD },
      { "TEXTURE30", 0x84DE },
      { "TEXTURE31", 0x84DF },
      { "ACTIVE_TEXTURE", 0x84E0 },

      /* TextureWrapMode */
      { "REPEAT", 0x2901 },
      { "CLAMP_TO_EDGE", 0x812F },
      { "MIRRORED_REPEAT", 0x8370 },

      /* Uniform Types */
      { "FLOAT_VEC2", 0x8B50 },
      { "FLOAT_VEC3", 0x8B51 },
      { "FLOAT_VEC4", 0x8B52 },
      { "INT_VEC2", 0x8B53 },
      { "INT_VEC3", 0x8B54 },
      { "INT_VEC4", 0x8B55 },
      { "BOOL", 0x8B56 },
      { "BOOL_VEC2", 0x8B57 },
      { "BOOL_VEC3", 0x8B58 },
      { "BOOL_VEC4", 0x8B59 },
      { "FLOAT_MAT2", 0x8B5A },
      { "FLOAT_MAT3", 0x8B5B },
      { "FLOAT_MAT4", 0x8B5C },
      { "SAMPLER_2D", 0x8B5E },
      { "SAMPLER_CUBE", 0x8B60 },

      /* Vertex Arrays */
      { "VERTEX_ATTRIB_ARRAY_ENABLED", 0x8622 },
      { "VERTEX_ATTRIB_ARRAY_SIZE", 0x8623 },
      { "VERTEX_ATTRIB_ARRAY_STRIDE", 0x8624 },
      { "VERTEX_ATTRIB_ARRAY_TYPE", 0x8625 },
      { "VERTEX_ATTRIB_ARRAY_NORMALIZED", 0x886A },
      { "VERTEX_ATTRIB_ARRAY_POINTER", 0x8645 },
      { "VERTEX_ATTRIB_ARRAY_BUFFER_BINDING", 0x889F },

      /* Read Format */
      { "IMPLEMENTATION_COLOR_READ_TYPE", 0x8B9A },
      { "IMPLEMENTATION_COLOR_READ_FORMAT", 0x8B9B },

      /* Shader Source */
      { "COMPILE_STATUS", 0x8B81 },
      { "INFO_LOG_LENGTH", 0x8B84 },
      { "SHADER_SOURCE_LENGTH", 0x8B88 },
      { "SHADER_COMPILER", 0x8DFA },

      /* Shader Binary */
      { "SHADER_BINARY_FORMATS", 0x8DF8 },
      { "NUM_SHADER_BINARY_FORMATS", 0x8DF9 },

      /* Shader Precision-Specified Types */
      { "LOW_FLOAT", 0x8DF0 },
      { "MEDIUM_FLOAT", 0x8DF1 },
      { "HIGH_FLOAT", 0x8DF2 },
      { "LOW_INT", 0x8DF3 },
      { "MEDIUM_INT", 0x8DF4 },
      { "HIGH_INT", 0x8DF5 },

      /* Framebuffer Object. */
      { "FRAMEBUFFER", 0x8D40 },
      { "RENDERBUFFER", 0x8D41 },

      { "RGBA4", 0x8056 },
      { "RGB5_A1", 0x8057 },
      { "RGB565", 0x8D62 },
      { "DEPTH_COMPONENT16", 0x81A5 },
      { "STENCIL_INDEX", 0x1901 },
      { "STENCIL_INDEX8", 0x8D48 },
      { "DEPTH_STENCIL", 0x84F9 },

      { "RENDERBUFFER_WIDTH", 0x8D42 },
      { "RENDERBUFFER_HEIGHT", 0x8D43 },
      { "RENDERBUFFER_INTERNAL_FORMAT", 0x8D44 },
      { "RENDERBUFFER_RED_SIZE", 0x8D50 },
      { "RENDERBUFFER_GREEN_SIZE", 0x8D51 },
      { "RENDERBUFFER_BLUE_SIZE", 0x8D52 },
      { "RENDERBUFFER_ALPHA_SIZE", 0x8D53 },
      { "RENDERBUFFER_DEPTH_SIZE", 0x8D54 },
      { "RENDERBUFFER_STENCIL_SIZE", 0x8D55 },

      { "FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE", 0x8CD0 },
      { "FRAMEBUFFER_ATTACHMENT_OBJECT_NAME", 0x8CD1 },
      { "FRAMEBUFFER_ATTACHMENT_TEXTURE_LEVEL", 0x8CD2 },
      { "FRAMEBUFFER_ATTACHMENT_TEXTURE_CUBE_MAP_FACE", 0x8CD3 },

      { "COLOR_ATTACHMENT0", 0x8CE0 },
      { "DEPTH_ATTACHMENT", 0x8D00 },
      { "STENCIL_ATTACHMENT", 0x8D20 },
      { "DEPTH_STENCIL_ATTACHMENT", 0x821A },

      { "NONE", 0 },

      { "FRAMEBUFFER_COMPLETE", 0x8CD5 },
      { "FRAMEBUFFER_INCOMPLETE_ATTACHMENT", 0x8CD6 },
      { "FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT", 0x8CD7 },
      { "FRAMEBUFFER_INCOMPLETE_DIMENSIONS", 0x8CD9 },
      { "FRAMEBUFFER_UNSUPPORTED", 0x8CDD },

      { "FRAMEBUFFER_BINDING", 0x8CA6 },
      { "RENDERBUFFER_BINDING", 0x8CA7 },
      { "MAX_RENDERBUFFER_SIZE", 0x84E8 },

      { "INVALID_FRAMEBUFFER_OPERATION", 0x0506 },

      /* WebGL-specific enums */
      { "UNPACK_FLIP_Y_WEBGL", 0x9240 },
      { "UNPACK_PREMULTIPLY_ALPHA_WEBGL", 0x9241 },

      // Some Plask non-WebGL enums, some of which are likely a bad idea.
      { "UNPACK_CLIENT_STORAGE_APPLE", GL_UNPACK_CLIENT_STORAGE_APPLE },
      { "RGBA16F", 0x881A },
      { "RGBA32F", 0x8814 },
      { "COLOR_ATTACHMENT1", 0x8CE1 },
      { "COLOR_ATTACHMENT2", 0x8CE2 },
      { "COLOR_ATTACHMENT3", 0x8CE3 },
      { "COLOR_ATTACHMENT4", 0x8CE4 },
      { "COLOR_ATTACHMENT5", 0x8CE5 },
      { "COLOR_ATTACHMENT6", 0x8CE6 },
      { "COLOR_ATTACHMENT7", 0x8CE7 },
      { "DEPTH_COMPONENT24", 0x81A6 },
      { "DEPTH_COMPONENT32", 0x81A7 },
      { "DRAW_FRAMEBUFFER", GL_DRAW_FRAMEBUFFER },
      { "READ_FRAMEBUFFER", GL_READ_FRAMEBUFFER },
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
      { "cullFace", &NSOpenGLContextWrapper::cullFace },
      { "deleteBuffer", &NSOpenGLContextWrapper::deleteBuffer },
      { "deleteFramebuffer", &NSOpenGLContextWrapper::deleteFramebuffer },
      { "deleteProgram", &NSOpenGLContextWrapper::deleteProgram },
      { "deleteRenderbuffer", &NSOpenGLContextWrapper::deleteRenderbuffer },
      { "deleteShader", &NSOpenGLContextWrapper::deleteShader },
      { "deleteTexture", &NSOpenGLContextWrapper::deleteTexture },
      { "depthFunc", &NSOpenGLContextWrapper::depthFunc },
      { "depthMask", &NSOpenGLContextWrapper::depthMask },
      { "depthRange", &NSOpenGLContextWrapper::depthRange },
      { "detachShader", &NSOpenGLContextWrapper::detachShader },
      { "disable", &NSOpenGLContextWrapper::disable },
      { "disableVertexAttribArray",
          &NSOpenGLContextWrapper::disableVertexAttribArray },
      { "drawArrays", &NSOpenGLContextWrapper::drawArrays },
      { "drawElements", &NSOpenGLContextWrapper::drawElements },
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
      { "lineWidth", &NSOpenGLContextWrapper::lineWidth },
      { "linkProgram", &NSOpenGLContextWrapper::linkProgram },
      { "pixelStorei", &NSOpenGLContextWrapper::pixelStorei },
      { "polygonOffset", &NSOpenGLContextWrapper::polygonOffset },
      { "readPixels", &NSOpenGLContextWrapper::readPixels },
      { "renderbufferStorage", &NSOpenGLContextWrapper::renderbufferStorage },
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
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      ft_cache->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::New(methods[i].name),
                    v8::FunctionTemplate::New(methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    return ft_cache;
  }

  static NSOpenGLContext* ExtractContextPointer(v8::Handle<v8::Object> obj) {
    return v8_utils::UnwrapCPointer<NSOpenGLContext>(obj->GetInternalField(0));
  }

 private:
  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    args.This()->SetInternalField(0, v8_utils::WrapCPointer(NULL));
    return args.This();
  }

  static v8::Handle<v8::Value> makeCurrentContext(const v8::Arguments& args) {
    NSOpenGLContext* context = ExtractContextPointer(args.This());
    [context makeCurrentContext];
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> createSyphonServer(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    NSOpenGLContext* context = ExtractContextPointer(args.This());
    v8::String::Utf8Value name(args[0]->ToString());
    SyphonServer* server = [[SyphonServer alloc]
        initWithName:[NSString stringWithUTF8String:*name]
        context:reinterpret_cast<CGLContextObj>([context CGLContextObj])
        options:nil];
    return SyphonServerWrapper::NewFromSyphonServer(server);
  }

  // aka vsync.
  static v8::Handle<v8::Value> setSwapInterval(const v8::Arguments& args) {
    NSOpenGLContext* context = ExtractContextPointer(args.This());
    GLint interval = args[0]->Int32Value();
    [context setValues:&interval forParameter:NSOpenGLCPSwapInterval];
    return v8::Undefined();
  }

  // TODO(deanm): Share more code with SkCanvas#writeImage.
  static v8::Handle<v8::Value> writeImage(const v8::Arguments& args) {
    const uint32_t rmask = SK_R32_MASK << SK_R32_SHIFT;
    const uint32_t gmask = SK_G32_MASK << SK_G32_SHIFT;
    const uint32_t bmask = SK_B32_MASK << SK_B32_SHIFT;

    if (args.Length() < 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    NSOpenGLContext* context = ExtractContextPointer(args.This());
    // TODO(deanm): There should be a better way to get the width and height.
    NSRect frame = [[context view] frame];
    int width = frame.size.width;
    int height = frame.size.height;

    int buffer_type = args[3]->Int32Value();

    FREE_IMAGE_FORMAT format;

    v8::String::Utf8Value type(args[0]->ToString());
    if (strcmp(*type, "png") == 0) {
      format = FIF_PNG;
    } else if (strcmp(*type, "tiff") == 0) {
      format = FIF_TIFF;
    } else if (strcmp(*type, "targa") == 0) {
      format = FIF_TARGA;
    } else {
      return v8_utils::ThrowError("writeImage unsupported output type.");
    }

    v8::String::Utf8Value filename(args[1]->ToString());

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
        return v8_utils::ThrowError("Couldn't allocate FreeImage bitmap.");
    } else {  // Floating point depth buffer
      fb = FreeImage_AllocateT(FIT_FLOAT, width, height);
      if (!fb)
        return v8_utils::ThrowError("Couldn't allocate FreeImage bitmap.");
      glReadPixels(0, 0, width, height,
                   GL_DEPTH_COMPONENT, GL_FLOAT, FreeImage_GetBits(fb));
    }

    int save_flags = 0;

    if (args.Length() >= 3 && args[2]->IsObject()) {
      v8::Handle<v8::Object> opts = v8::Handle<v8::Object>::Cast(args[2]);
      if (opts->Has(v8::String::New("dotsPerMeterX"))) {
        FreeImage_SetDotsPerMeterX(fb,
            opts->Get(v8::String::New("dotsPerMeterX"))->Uint32Value());
      }
      if (opts->Has(v8::String::New("dotsPerMeterY"))) {
        FreeImage_SetDotsPerMeterY(fb,
            opts->Get(v8::String::New("dotsPerMeterY"))->Uint32Value());
      }
      if (format == FIF_TIFF && opts->Has(v8::String::New("tiffCompression"))) {
        if (!opts->Get(v8::String::New("tiffCompression"))->BooleanValue())
          save_flags = TIFF_NONE;
      }
    }

    bool saved = FreeImage_Save(format, fb, *filename, save_flags);
    FreeImage_Unload(fb);

    if (!saved)
      return v8_utils::ThrowError("Failed to save png.");

    return v8::Undefined();
  }

  // void activeTexture(GLenum texture)
  static v8::Handle<v8::Value> activeTexture(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");
    glActiveTexture(args[0]->Uint32Value());
    return v8::Undefined();
  }

  // void attachShader(WebGLProgram program, WebGLShader shader)
  static v8::Handle<v8::Value> attachShader(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!WebGLProgram::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLProgram.");
    GLuint program = WebGLProgram::ExtractIDFromValue(args[0]);

    glAttachShader(program, args[1]->Uint32Value());
    return v8::Undefined();
  }

  // void bindAttribLocation(WebGLProgram program, GLuint index, DOMString name)
  static v8::Handle<v8::Value> bindAttribLocation(const v8::Arguments& args) {
    if (args.Length() != 3)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!WebGLProgram::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLProgram.");
    GLuint program = WebGLProgram::ExtractIDFromValue(args[0]);

    v8::String::Utf8Value name(args[2]->ToString());
    glBindAttribLocation(program, args[1]->Uint32Value(), *name);
    return v8::Undefined();
  }

  // void bindBuffer(GLenum target, WebGLBuffer buffer)
  static v8::Handle<v8::Value> bindBuffer(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");
    glBindBuffer(args[0]->Uint32Value(), args[1]->Uint32Value());
    return v8::Undefined();
  }

  // void bindFramebuffer(GLenum target, WebGLFramebuffer framebuffer)
  static v8::Handle<v8::Value> bindFramebuffer(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");
    glBindFramebuffer(args[0]->Uint32Value(), args[1]->Uint32Value());
    return v8::Undefined();
  }

  // void bindRenderbuffer(GLenum target, WebGLRenderbuffer renderbuffer)
  static v8::Handle<v8::Value> bindRenderbuffer(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");
    glBindRenderbuffer(args[0]->Uint32Value(), args[1]->Uint32Value());
    return v8::Undefined();
  }

  // void bindTexture(GLenum target, WebGLTexture texture)
  static v8::Handle<v8::Value> bindTexture(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");
    glBindTexture(args[0]->Uint32Value(), args[1]->Uint32Value());
    return v8::Undefined();
  }

  // void blendColor(GLclampf red, GLclampf green,
  //                 GLclampf blue, GLclampf alpha)
  static v8::Handle<v8::Value> blendColor(const v8::Arguments& args) {
    if (args.Length() != 4)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glBlendColor(args[0]->NumberValue(),
                 args[1]->NumberValue(),
                 args[2]->NumberValue(),
                 args[3]->NumberValue());
    return v8::Undefined();
  }

  // void blendEquation(GLenum mode)
  static v8::Handle<v8::Value> blendEquation(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");
    glBlendEquation(args[0]->Uint32Value());
    return v8::Undefined();
  }

  // void blendEquationSeparate(GLenum modeRGB, GLenum modeAlpha)
  static v8::Handle<v8::Value> blendEquationSeparate(
      const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");
    glBlendEquationSeparate(args[0]->Uint32Value(), args[1]->Uint32Value());
    return v8::Undefined();
  }


  // void blendFunc(GLenum sfactor, GLenum dfactor)
  static v8::Handle<v8::Value> blendFunc(
      const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");
    glBlendFunc(args[0]->Uint32Value(), args[1]->Uint32Value());
    return v8::Undefined();
  }

  // void blendFuncSeparate(GLenum srcRGB, GLenum dstRGB,
  //                        GLenum srcAlpha, GLenum dstAlpha)
  static v8::Handle<v8::Value> blendFuncSeparate(
      const v8::Arguments& args) {
    if (args.Length() != 4)
      return v8_utils::ThrowError("Wrong number of arguments.");
    glBlendFuncSeparate(args[0]->Uint32Value(), args[1]->Uint32Value(),
                        args[2]->Uint32Value(), args[3]->Uint32Value());
    return v8::Undefined();
  }

  // void bufferData(GLenum target, GLsizei size, GLenum usage)
  // void bufferData(GLenum target, ArrayBufferView data, GLenum usage)
  // void bufferData(GLenum target, ArrayBuffer data, GLenum usage)
  static v8::Handle<v8::Value> bufferData(
      const v8::Arguments& args) {
    if (args.Length() != 3)
      return v8_utils::ThrowError("Wrong number of arguments.");

    GLsizeiptr size = 0;
    GLvoid* data = NULL;

    if (args[1]->IsObject()) {
      v8::Local<v8::Object> obj = v8::Local<v8::Object>::Cast(args[1]);
      if (!obj->HasIndexedPropertiesInExternalArrayData())
        return v8_utils::ThrowError("Data must be an ArrayBuffer.");
      int element_size = v8_typed_array::SizeOfArrayElementForType(
          obj->GetIndexedPropertiesExternalArrayDataType());
      size = obj->GetIndexedPropertiesExternalArrayDataLength() * element_size;
      data = obj->GetIndexedPropertiesExternalArrayData();
    } else {
      size = args[1]->Uint32Value();
    }

    glBufferData(args[0]->Uint32Value(), size, data, args[2]->Uint32Value());
    return v8::Undefined();
  }

  // void bufferSubData(GLenum target, GLsizeiptr offset, ArrayBufferView data)
  // void bufferSubData(GLenum target, GLsizeiptr offset, ArrayBuffer data)
  static v8::Handle<v8::Value> bufferSubData(
      const v8::Arguments& args) {
    return v8::Undefined();
  }

  // GLenum checkFramebufferStatus(GLenum target)
  static v8::Handle<v8::Value> checkFramebufferStatus(
      const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");
    return v8::Integer::NewFromUnsigned(
        glCheckFramebufferStatus(args[0]->Uint32Value()));
  }

  // void clear(GLbitfield mask)
  static v8::Handle<v8::Value> clear(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");
    glClear(args[0]->Uint32Value());
    return v8::Undefined();
  }

  // void clearColor(GLclampf red, GLclampf green,
  //                 GLclampf blue, GLclampf alpha)
  static v8::Handle<v8::Value> clearColor(const v8::Arguments& args) {
    if (args.Length() != 4)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glClearColor(args[0]->NumberValue(),
                 args[1]->NumberValue(),
                 args[2]->NumberValue(),
                 args[3]->NumberValue());
    return v8::Undefined();
  }

  // void clearDepth(GLclampf depth)
  static v8::Handle<v8::Value> clearDepth(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glClearDepth(args[0]->NumberValue());
    return v8::Undefined();
  }

  // void clearStencil(GLint s)
  static v8::Handle<v8::Value> clearStencil(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glClearStencil(args[0]->Int32Value());
    return v8::Undefined();
  }

  // void colorMask(GLboolean red, GLboolean green,
  //                GLboolean blue, GLboolean alpha)
  static v8::Handle<v8::Value> colorMask(const v8::Arguments& args) {
    if (args.Length() != 4)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glColorMask(args[0]->BooleanValue(),
                args[1]->BooleanValue(),
                args[2]->BooleanValue(),
                args[3]->BooleanValue());
    return v8::Undefined();
  }

  // void compileShader(WebGLShader shader)
  static v8::Handle<v8::Value> compileShader(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glCompileShader(args[0]->Uint32Value());
    return v8::Undefined();
  }

  // WebGLBuffer createBuffer()
  static v8::Handle<v8::Value> createBuffer(const v8::Arguments& args) {
    GLuint buffer;
    glGenBuffers(1, &buffer);
    return v8::Integer::NewFromUnsigned(buffer);
  }

  // WebGLFramebuffer createFramebuffer()
  static v8::Handle<v8::Value> createFramebuffer(const v8::Arguments& args) {
    GLuint framebuffer;
    glGenFramebuffers(1, &framebuffer);
    return v8::Integer::NewFromUnsigned(framebuffer);
  }

  // WebGLProgram createProgram()
  static v8::Handle<v8::Value> createProgram(const v8::Arguments& args) {
    return WebGLProgram::NewFromID(glCreateProgram());
  }

  // WebGLRenderbuffer createRenderbuffer()
  static v8::Handle<v8::Value> createRenderbuffer(const v8::Arguments& args) {
    GLuint renderbuffer;
    glGenRenderbuffers(1, &renderbuffer);
    return v8::Integer::NewFromUnsigned(renderbuffer);
  }

  // WebGLShader createShader(GLenum type)
  static v8::Handle<v8::Value> createShader(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    return v8::Integer::NewFromUnsigned(glCreateShader(args[0]->Uint32Value()));
  }

  // WebGLTexture createTexture()
  static v8::Handle<v8::Value> createTexture(const v8::Arguments& args) {
    GLuint texture;
    glGenTextures(1, &texture);
    return v8::Integer::NewFromUnsigned(texture);
  }

  // void cullFace(GLenum mode)
  static v8::Handle<v8::Value> cullFace(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glCullFace(args[0]->Uint32Value());
    return v8::Undefined();
  }

  // void deleteBuffer(WebGLBuffer buffer)
  static v8::Handle<v8::Value> deleteBuffer(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    GLuint buffer = args[0]->Uint32Value();
    glDeleteBuffers(1, &buffer);
    return v8::Undefined();
  }

  // void deleteFramebuffer(WebGLFramebuffer framebuffer)
  static v8::Handle<v8::Value> deleteFramebuffer(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    GLuint buffer = args[0]->Uint32Value();
    glDeleteFramebuffers(1, &buffer);
    return v8::Undefined();
  }

  // void deleteProgram(WebGLProgram program)
  static v8::Handle<v8::Value> deleteProgram(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!WebGLProgram::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLProgram.");
    GLuint program = WebGLProgram::ExtractIDFromValue(args[0]);

    glDeleteProgram(program);
    return v8::Undefined();
  }

  // void deleteRenderbuffer(WebGLRenderbuffer renderbuffer)
  static v8::Handle<v8::Value> deleteRenderbuffer(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    GLuint buffer = args[0]->Uint32Value();
    glDeleteRenderbuffers(1, &buffer);
    return v8::Undefined();
  }

  // void deleteShader(WebGLShader shader)
  static v8::Handle<v8::Value> deleteShader(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glDeleteShader(args[0]->Uint32Value());
    return v8::Undefined();
  }

  // void deleteTexture(WebGLTexture texture)
  static v8::Handle<v8::Value> deleteTexture(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    GLuint buffer = args[0]->Uint32Value();
    glDeleteTextures(1, &buffer);
    return v8::Undefined();
  }

  // void depthFunc(GLenum func)
  static v8::Handle<v8::Value> depthFunc(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glDepthFunc(args[0]->Uint32Value());
    return v8::Undefined();
  }

  // void depthMask(GLboolean flag)
  static v8::Handle<v8::Value> depthMask(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glDepthMask(args[0]->BooleanValue());
    return v8::Undefined();
  }

  // void depthRange(GLclampf zNear, GLclampf zFar)
  static v8::Handle<v8::Value> depthRange(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glDepthRange(args[0]->NumberValue(), args[1]->NumberValue());
    return v8::Undefined();
  }

  // void detachShader(WebGLProgram program, WebGLShader shader)
  static v8::Handle<v8::Value> detachShader(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!WebGLProgram::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLProgram.");
    GLuint program = WebGLProgram::ExtractIDFromValue(args[0]);

    glDetachShader(program, args[1]->Uint32Value());
    return v8::Undefined();
  }

  // void disable(GLenum cap)
  static v8::Handle<v8::Value> disable(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glDisable(args[0]->Uint32Value());
    return v8::Undefined();
  }

  // void disableVertexAttribArray(GLuint index)
  static v8::Handle<v8::Value> disableVertexAttribArray(
      const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glDisableVertexAttribArray(args[0]->Uint32Value());
    return v8::Undefined();
  }

  // void drawArrays(GLenum mode, GLint first, GLsizei count)
  static v8::Handle<v8::Value> drawArrays(const v8::Arguments& args) {
    if (args.Length() != 3)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glDrawArrays(args[0]->Uint32Value(),
                 args[1]->Int32Value(), args[2]->Int32Value());
    return v8::Undefined();
  }

  // void drawElements(GLenum mode, GLsizei count,
  //                   GLenum type, GLsizeiptr offset)
  static v8::Handle<v8::Value> drawElements(const v8::Arguments& args) {
    if (args.Length() != 4)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glDrawElements(args[0]->Uint32Value(),
                   args[1]->Int32Value(),
                   args[2]->Uint32Value(),
                   reinterpret_cast<GLvoid*>(args[3]->Int32Value()));
    return v8::Undefined();
  }

  // void enable(GLenum cap)
  static v8::Handle<v8::Value> enable(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glEnable(args[0]->Uint32Value());
    return v8::Undefined();
  }

  // void enableVertexAttribArray(GLuint index)
  static v8::Handle<v8::Value> enableVertexAttribArray(
      const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glEnableVertexAttribArray(args[0]->Uint32Value());
    return v8::Undefined();
  }

  // void finish()
  static v8::Handle<v8::Value> finish(const v8::Arguments& args) {
    glFinish();
    return v8::Undefined();
  }

  // void flush()
  static v8::Handle<v8::Value> flush(const v8::Arguments& args) {
    glFlush();
    return v8::Undefined();
  }

  // void framebufferRenderbuffer(GLenum target, GLenum attachment,
  //                              GLenum renderbuffertarget,
  //                              WebGLRenderbuffer renderbuffer)
  static v8::Handle<v8::Value> framebufferRenderbuffer(
      const v8::Arguments& args) {
    if (args.Length() != 4)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glFramebufferRenderbuffer(args[0]->Uint32Value(),
                              args[1]->Uint32Value(),
                              args[2]->Uint32Value(),
                              args[3]->Uint32Value());
    return v8::Undefined();
  }

  // void framebufferTexture2D(GLenum target, GLenum attachment,
  //                           GLenum textarget, WebGLTexture texture,
  //                           GLint level)
  static v8::Handle<v8::Value> framebufferTexture2D(
      const v8::Arguments& args) {
    if (args.Length() != 5)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glFramebufferTexture2D(args[0]->Uint32Value(),
                           args[1]->Uint32Value(),
                           args[2]->Uint32Value(),
                           args[3]->Uint32Value(),
                           args[4]->Int32Value());
    return v8::Undefined();
  }

  // void frontFace(GLenum mode)
  static v8::Handle<v8::Value> frontFace(
      const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glFrontFace(args[0]->Uint32Value());
    return v8::Undefined();
  }

  // void generateMipmap(GLenum target)
  static v8::Handle<v8::Value> generateMipmap(
      const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glGenerateMipmap(args[0]->Uint32Value());
    return v8::Undefined();
  }

  // WebGLActiveInfo getActiveAttrib(WebGLProgram program, GLuint index)
  static v8::Handle<v8::Value> getActiveAttrib(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!WebGLProgram::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLProgram.");
    GLuint program = WebGLProgram::ExtractIDFromValue(args[0]);

    char namebuf[1024];
    GLint size;
    GLenum type;

    glGetActiveAttrib(program, args[1]->Uint32Value(),
                      sizeof(namebuf), NULL, &size, &type, namebuf);

    return WebGLActiveInfo::NewFromSizeTypeName(size, type, namebuf);
  }

  // WebGLActiveInfo getActiveUniform(WebGLProgram program, GLuint index)
  static v8::Handle<v8::Value> getActiveUniform(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!WebGLProgram::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLProgram.");
    GLuint program = WebGLProgram::ExtractIDFromValue(args[0]);

    char namebuf[1024];
    GLint size;
    GLenum type;

    glGetActiveUniform(program, args[1]->Uint32Value(),
                       sizeof(namebuf), NULL, &size, &type, namebuf);

    return WebGLActiveInfo::NewFromSizeTypeName(size, type, namebuf);
  }

  // WebGLShader[ ] getAttachedShaders(WebGLProgram program)
  static v8::Handle<v8::Value> getAttachedShaders(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    return v8_utils::ThrowError("Unimplemented.");
  }

  // GLint getAttribLocation(WebGLProgram program, DOMString name)
  static v8::Handle<v8::Value> getAttribLocation(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!WebGLProgram::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLProgram.");
    GLuint program = WebGLProgram::ExtractIDFromValue(args[0]);

    v8::String::Utf8Value name(args[1]->ToString());
    return v8::Integer::New(glGetAttribLocation(program, *name));
  }

  // Helper for getParameter, based on
  //   WebCore/html/canvas/WebGLRenderingContext.cpp
  static v8::Handle<v8::Value> getBooleanParameter(unsigned long pname) {
    unsigned char value;
    glGetBooleanv(pname, &value);
    return v8::Boolean::New(static_cast<bool>(value));
  }

  static v8::Handle<v8::Value> getBooleanArrayParameter(unsigned long pname) {
    return v8_utils::ThrowError("Unimplemented.");
//    if (pname != GL_COLOR_WRITEMASK) {
//      notImplemented();
//      return static v8::Handle<v8::Value>(0, 0);
//    }
//    unsigned char value[4] = {0};
//    m_context->getBooleanv(pname, value);
//    bool boolValue[4];
//    for (int ii = 0; ii < 4; ++ii)
//        boolValue[ii] = static_cast<bool>(value[ii]);
//    return static v8::Handle<v8::Value>(boolValue, 4);
  }

  static v8::Handle<v8::Value> getFloatParameter(unsigned long pname) {
    float value;
    glGetFloatv(pname, &value);
    return v8::Number::New(value);
  }

  static v8::Handle<v8::Value> getIntParameter(unsigned long pname) {
    return getLongParameter(pname);
  }

  static v8::Handle<v8::Value> getLongParameter(unsigned long pname) {
    int value;
    glGetIntegerv(pname, &value);
    return v8::Integer::New(static_cast<long>(value));
  }

  static v8::Handle<v8::Value> getUnsignedLongParameter(unsigned long pname) {
    int value;
    glGetIntegerv(pname, &value);
    unsigned int uValue = static_cast<unsigned int>(value);
    return v8::Integer::NewFromUnsigned(static_cast<unsigned long>(uValue));
  }

  static v8::Handle<v8::Value> getWebGLFloatArrayParameter(unsigned long pname) {
    return v8_utils::ThrowError("Unimplemented.");
//    float value[4] = {0};
//    m_context->getFloatv(pname, value);
//    unsigned length = 0;
//    switch (pname) {
//      case GL_ALIASED_POINT_SIZE_RANGE:
//      case GL_ALIASED_LINE_WIDTH_RANGE:
//      case GL_DEPTH_RANGE:
//        length = 2;
//        break;
//      case GL_BLEND_COLOR:
//      case GL_COLOR_CLEAR_VALUE:
//        length = 4;
//        break;
//      default:
//        notImplemented();
//    }
//    return static v8::Handle<v8::Value>(Float32Array::create(value, length));
  }

  static v8::Handle<v8::Value> getWebGLIntArrayParameter(unsigned long pname) {
    return v8_utils::ThrowError("Unimplemented.");
//    int value[4] = {0};
//    m_context->getIntegerv(pname, value);
//    unsigned length = 0;
//    switch (pname) {
//      case GL_MAX_VIEWPORT_DIMS:
//        length = 2;
//        break;
//      case GL_SCISSOR_BOX:
//      case GL_VIEWPORT:
//        length = 4;
//        break;
//      default:
//        notImplemented();
//    }
//    return static v8::Handle<v8::Value>(Int32Array::create(value, length));
  }

  // any getParameter(GLenum pname)
  static v8::Handle<v8::Value> getParameter(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    unsigned long pname = args[0]->Uint32Value();

    switch (pname) {
      case GL_ACTIVE_TEXTURE:
        return getUnsignedLongParameter(pname);
      case GL_ALIASED_LINE_WIDTH_RANGE:
        return getWebGLFloatArrayParameter(pname);
      case GL_ALIASED_POINT_SIZE_RANGE:
        return getWebGLFloatArrayParameter(pname);
      case GL_ALPHA_BITS:
        return getLongParameter(pname);
      case GL_ARRAY_BUFFER_BINDING:
        return v8_utils::ThrowError("Unimplemented.");
      case GL_BLEND:
        return getBooleanParameter(pname);
      case GL_BLEND_COLOR:
        return getWebGLFloatArrayParameter(pname);
      case GL_BLEND_DST_ALPHA:
        return getUnsignedLongParameter(pname);
      case GL_BLEND_DST_RGB:
        return getUnsignedLongParameter(pname);
      case GL_BLEND_EQUATION_ALPHA:
        return getUnsignedLongParameter(pname);
      case GL_BLEND_EQUATION_RGB:
        return getUnsignedLongParameter(pname);
      case GL_BLEND_SRC_ALPHA:
        return getUnsignedLongParameter(pname);
      case GL_BLEND_SRC_RGB:
        return getUnsignedLongParameter(pname);
      case GL_BLUE_BITS:
        return getLongParameter(pname);
      case GL_COLOR_CLEAR_VALUE:
        return getWebGLFloatArrayParameter(pname);
      case GL_COLOR_WRITEMASK:
        return getBooleanArrayParameter(pname);
      case GL_COMPRESSED_TEXTURE_FORMATS:
        // Defined as null in the spec
        return v8::Undefined();
      case GL_CULL_FACE:
        return getBooleanParameter(pname);
      case GL_CULL_FACE_MODE:
        return getUnsignedLongParameter(pname);
      case GL_CURRENT_PROGRAM:
        return v8_utils::ThrowError("Unimplemented.");
      case GL_DEPTH_BITS:
        return getLongParameter(pname);
      case GL_DEPTH_CLEAR_VALUE:
        return getFloatParameter(pname);
      case GL_DEPTH_FUNC:
        return getUnsignedLongParameter(pname);
      case GL_DEPTH_RANGE:
        return getWebGLFloatArrayParameter(pname);
      case GL_DEPTH_TEST:
        return getBooleanParameter(pname);
      case GL_DEPTH_WRITEMASK:
        return getBooleanParameter(pname);
      case GL_DITHER:
        return getBooleanParameter(pname);
      case GL_ELEMENT_ARRAY_BUFFER_BINDING:
        return v8_utils::ThrowError("Unimplemented.");
      case GL_FRAMEBUFFER_BINDING:
        return v8_utils::ThrowError("Unimplemented.");
      case GL_FRONT_FACE:
        return getUnsignedLongParameter(pname);
      case GL_GENERATE_MIPMAP_HINT:
        return getUnsignedLongParameter(pname);
      case GL_GREEN_BITS:
        return getLongParameter(pname);
      //case GL_IMPLEMENTATION_COLOR_READ_FORMAT:
      //  return getLongParameter(pname);
      //case GL_IMPLEMENTATION_COLOR_READ_TYPE:
      //  return getLongParameter(pname);
      case GL_LINE_WIDTH:
        return getFloatParameter(pname);
      case GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS:
        return getLongParameter(pname);
      case GL_MAX_CUBE_MAP_TEXTURE_SIZE:
        return getLongParameter(pname);
      //case GL_MAX_FRAGMENT_UNIFORM_VECTORS:
      //  return getLongParameter(pname);
      case GL_MAX_RENDERBUFFER_SIZE:
        return getLongParameter(pname);
      case GL_MAX_TEXTURE_IMAGE_UNITS:
        return getLongParameter(pname);
      case GL_MAX_TEXTURE_SIZE:
        return getLongParameter(pname);
      //case GL_MAX_VARYING_VECTORS:
      //  return getLongParameter(pname);
      case GL_MAX_VERTEX_ATTRIBS:
        return getLongParameter(pname);
      case GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS:
        return getLongParameter(pname);
      //case GL_MAX_VERTEX_UNIFORM_VECTORS:
      //  return getLongParameter(pname);
      case GL_MAX_VIEWPORT_DIMS:
        return getWebGLIntArrayParameter(pname);
      case GL_NUM_COMPRESSED_TEXTURE_FORMATS:
        // WebGL 1.0 specifies that there are no compressed texture formats.
        return v8::Integer::New(0);
      //case GL_NUM_SHADER_BINARY_FORMATS:
      //  // FIXME: should we always return 0 for this?
      //  return getLongParameter(pname);
      case GL_PACK_ALIGNMENT:
        return getLongParameter(pname);
      case GL_POLYGON_OFFSET_FACTOR:
        return getFloatParameter(pname);
      case GL_POLYGON_OFFSET_FILL:
        return getBooleanParameter(pname);
      case GL_POLYGON_OFFSET_UNITS:
        return getFloatParameter(pname);
      case GL_RED_BITS:
        return getLongParameter(pname);
      case GL_RENDERBUFFER_BINDING:
        return v8_utils::ThrowError("Unimplemented.");
      case GL_RENDERER:
        return v8::String::New(
            reinterpret_cast<const char*>(glGetString(pname)));
      case GL_SAMPLE_BUFFERS:
        return getLongParameter(pname);
      case GL_SAMPLE_COVERAGE_INVERT:
        return getBooleanParameter(pname);
      case GL_SAMPLE_COVERAGE_VALUE:
        return getFloatParameter(pname);
      case GL_SAMPLES:
        return getLongParameter(pname);
      case GL_SCISSOR_BOX:
        return getWebGLIntArrayParameter(pname);
      case GL_SCISSOR_TEST:
        return getBooleanParameter(pname);
      case GL_SHADING_LANGUAGE_VERSION:
      {
        std::string str = "WebGL GLSL ES 1.0 (";
        str.append(reinterpret_cast<const char*>(glGetString(pname)));
        str.push_back(')');
        return v8::String::New(str.c_str());
      }
      case GL_STENCIL_BACK_FAIL:
        return getUnsignedLongParameter(pname);
      case GL_STENCIL_BACK_FUNC:
        return getUnsignedLongParameter(pname);
      case GL_STENCIL_BACK_PASS_DEPTH_FAIL:
        return getUnsignedLongParameter(pname);
      case GL_STENCIL_BACK_PASS_DEPTH_PASS:
        return getUnsignedLongParameter(pname);
      case GL_STENCIL_BACK_REF:
        return getLongParameter(pname);
      case GL_STENCIL_BACK_VALUE_MASK:
        return getUnsignedLongParameter(pname);
      case GL_STENCIL_BACK_WRITEMASK:
        return getUnsignedLongParameter(pname);
      case GL_STENCIL_BITS:
        return getLongParameter(pname);
      case GL_STENCIL_CLEAR_VALUE:
        return getLongParameter(pname);
      case GL_STENCIL_FAIL:
        return getUnsignedLongParameter(pname);
      case GL_STENCIL_FUNC:
        return getUnsignedLongParameter(pname);
      case GL_STENCIL_PASS_DEPTH_FAIL:
        return getUnsignedLongParameter(pname);
      case GL_STENCIL_PASS_DEPTH_PASS:
        return getUnsignedLongParameter(pname);
      case GL_STENCIL_REF:
        return getLongParameter(pname);
      case GL_STENCIL_TEST:
        return getBooleanParameter(pname);
      case GL_STENCIL_VALUE_MASK:
        return getUnsignedLongParameter(pname);
      case GL_STENCIL_WRITEMASK:
        return getUnsignedLongParameter(pname);
      case GL_SUBPIXEL_BITS:
        return getLongParameter(pname);
      case GL_TEXTURE_BINDING_2D:
        return v8_utils::ThrowError("Unimplemented.");
      case GL_TEXTURE_BINDING_CUBE_MAP:
        return v8_utils::ThrowError("Unimplemented.");
      case GL_UNPACK_ALIGNMENT:
        // FIXME: should this be "long" in the spec?
        return getIntParameter(pname);
      //case GL_UNPACK_FLIP_Y_WEBGL:
      //  return v8_utils::ThrowError("Unimplemented.");
      //case GL_UNPACK_PREMULTIPLY_ALPHA_WEBGL:
      //  return v8_utils::ThrowError("Unimplemented.");
      case GL_VENDOR:
      {
        std::string str = "Plask (";
        str.append(reinterpret_cast<const char*>(glGetString(pname)));
        str.push_back(')');
        return v8::String::New(str.c_str());
      }
      case GL_VERSION:
      {
        std::string str = "WebGL 1.0 (";
        str.append(reinterpret_cast<const char*>(glGetString(pname)));
        str.push_back(')');
        return v8::String::New(str.c_str());
      }
      case GL_VIEWPORT:
        return getWebGLIntArrayParameter(pname);
      default:
        return v8::Undefined();
    }
  }

  // any getBufferParameter(GLenum target, GLenum pname)
  static v8::Handle<v8::Value> getBufferParameter(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    unsigned long pname = args[0]->Uint32Value();
    if (pname == GL_BUFFER_SIZE)
      return getLongParameter(pname);
    else
      return getUnsignedLongParameter(pname);
  }

  // GLenum getError()
  static v8::Handle<v8::Value> getError(const v8::Arguments& args) {
    return v8::Integer::NewFromUnsigned(glGetError());
  }

  // any getFramebufferAttachmentParameter(GLenum target, GLenum attachment,
  //                                       GLenum pname)
  static v8::Handle<v8::Value> getFramebufferAttachmentParameter(
      const v8::Arguments& args) {
    return v8_utils::ThrowError("Unimplemented.");
  }

  // any getProgramParameter(WebGLProgram program, GLenum pname)
  static v8::Handle<v8::Value> getProgramParameter(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!WebGLProgram::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLProgram.");
    GLuint program = WebGLProgram::ExtractIDFromValue(args[0]);

    unsigned long pname = args[1]->Uint32Value();
    GLint value = 0;
    switch (pname) {
      case GL_DELETE_STATUS:
      case GL_VALIDATE_STATUS:
      case GL_LINK_STATUS:
        glGetProgramiv(program, pname, &value);
        return v8::Boolean::New(value);
      case GL_INFO_LOG_LENGTH:
      case GL_ATTACHED_SHADERS:
      case GL_ACTIVE_ATTRIBUTES:
      case GL_ACTIVE_ATTRIBUTE_MAX_LENGTH:
      case GL_ACTIVE_UNIFORMS:
      case GL_ACTIVE_UNIFORM_MAX_LENGTH:
        glGetProgramiv(program, pname, &value);
        return v8::Integer::New(value);
      default:
        return v8::Undefined();
    }
  }

  // DOMString getProgramInfoLog(WebGLProgram program)
  static v8::Handle<v8::Value> getProgramInfoLog(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!WebGLProgram::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLProgram.");
    GLuint program = WebGLProgram::ExtractIDFromValue(args[0]);

    GLint length = 0;
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &length);
    GLchar* buf = new GLchar[length + 1];
    glGetProgramInfoLog(program, length + 1, NULL, buf);
    v8::Handle<v8::Value> res = v8::String::New(buf, length);
    delete[] buf;
    return res;
  }

  // any getRenderbufferParameter(GLenum target, GLenum pname)
  static v8::Handle<v8::Value> getRenderbufferParameter(
      const v8::Arguments& args) {
    return v8_utils::ThrowError("Unimplemented.");
  }

  // any getShaderParameter(WebGLShader shader, GLenum pname)
  static v8::Handle<v8::Value> getShaderParameter(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    GLuint shader = args[0]->Uint32Value();
    unsigned long pname = args[1]->Uint32Value();
    GLint value = 0;
    switch (pname) {
      case GL_DELETE_STATUS:
      case GL_COMPILE_STATUS:
        glGetShaderiv(shader, pname, &value);
        return v8::Boolean::New(value);
      case GL_SHADER_TYPE:
        glGetShaderiv(shader, pname, &value);
        return v8::Integer::NewFromUnsigned(value);
      case GL_INFO_LOG_LENGTH:
      case GL_SHADER_SOURCE_LENGTH:
        glGetShaderiv(shader, pname, &value);
        return v8::Integer::New(value);
      default:
        return v8::Undefined();
    }
  }

  // DOMString getShaderInfoLog(WebGLShader shader)
  static v8::Handle<v8::Value> getShaderInfoLog(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    GLuint shader = args[0]->Uint32Value();
    GLint length = 0;
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &length);
    GLchar* buf = new GLchar[length + 1];
    glGetShaderInfoLog(shader, length + 1, NULL, buf);
    v8::Handle<v8::Value> res = v8::String::New(buf, length);
    delete[] buf;
    return res;
  }

  // DOMString getShaderSource(WebGLShader shader)
  static v8::Handle<v8::Value> getShaderSource(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    GLuint shader = args[0]->Uint32Value();
    GLint length = 0;
    glGetShaderiv(shader, GL_SHADER_SOURCE_LENGTH, &length);
    GLchar* buf = new GLchar[length + 1];
    glGetShaderSource(shader, length + 1, NULL, buf);
    v8::Handle<v8::Value> res = v8::String::New(buf, length);
    delete[] buf;
    return res;
  }

  // any getTexParameter(GLenum target, GLenum pname)
  static v8::Handle<v8::Value> getTexParameter(const v8::Arguments& args) {
    return v8_utils::ThrowError("Unimplemented.");
  }

  // any getUniform(WebGLProgram program, WebGLUniformLocation location)
  static v8::Handle<v8::Value> getUniform(const v8::Arguments& args) {
    return v8_utils::ThrowError("Unimplemented.");
  }

  // WebGLUniformLocation getUniformLocation(WebGLProgram program,
  //                                         DOMString name)
  static v8::Handle<v8::Value> getUniformLocation(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!WebGLProgram::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLProgram.");
    GLuint program = WebGLProgram::ExtractIDFromValue(args[0]);

    v8::String::Utf8Value name(args[1]->ToString());
    GLint location = glGetUniformLocation(program, *name);
    if (location == -1)
      return v8::Null();
    return WebGLUniformLocation::NewFromLocation(location);
  }

  // any getVertexAttrib(GLuint index, GLenum pname)
  static v8::Handle<v8::Value> getVertexAttrib(
      const v8::Arguments& args) {
    return v8_utils::ThrowError("Unimplemented.");
  }

  // GLsizeiptr getVertexAttribOffset(GLuint index, GLenum pname)
  static v8::Handle<v8::Value> getVertexAttribOffset(
      const v8::Arguments& args) {
    return v8_utils::ThrowError("Unimplemented.");
  }

  // void hint(GLenum target, GLenum mode)
  static v8::Handle<v8::Value> hint(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glHint(args[0]->Uint32Value(), args[1]->Uint32Value());
    return v8::Undefined();
  }

  // GLboolean isBuffer(WebGLBuffer buffer)
  static v8::Handle<v8::Value> isBuffer(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    return v8::Boolean::New(glIsBuffer(args[0]->Uint32Value()));
  }

  // GLboolean isEnabled(GLenum cap)
  static v8::Handle<v8::Value> isEnabled(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    return v8::Boolean::New(glIsEnabled(args[0]->Uint32Value()));
  }

  // GLboolean isFramebuffer(WebGLFramebuffer framebuffer)
  static v8::Handle<v8::Value> isFramebuffer(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    return v8::Boolean::New(glIsFramebuffer(args[0]->Uint32Value()));
  }

  // GLboolean isProgram(WebGLProgram program)
  static v8::Handle<v8::Value> isProgram(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!WebGLProgram::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLProgram.");
    GLuint program = WebGLProgram::ExtractIDFromValue(args[0]);

    return v8::Boolean::New(glIsProgram(program));
  }

  // GLboolean isRenderbuffer(WebGLRenderbuffer renderbuffer)
  static v8::Handle<v8::Value> isRenderbuffer(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    return v8::Boolean::New(glIsRenderbuffer(args[0]->Uint32Value()));
  }

  // GLboolean isShader(WebGLShader shader)
  static v8::Handle<v8::Value> isShader(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    return v8::Boolean::New(glIsShader(args[0]->Uint32Value()));
  }

  // GLboolean isTexture(WebGLTexture texture)
  static v8::Handle<v8::Value> isTexture(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    return v8::Boolean::New(glIsTexture(args[0]->Uint32Value()));
  }

  // void lineWidth(GLfloat width)
  static v8::Handle<v8::Value> lineWidth(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glLineWidth(args[0]->NumberValue());
    return v8::Undefined();
  }

  // void linkProgram(WebGLProgram program)
  static v8::Handle<v8::Value> linkProgram(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!WebGLProgram::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLProgram.");
    GLuint program = WebGLProgram::ExtractIDFromValue(args[0]);

    glLinkProgram(program);
    return v8::Undefined();
  }

  // void pixelStorei(GLenum pname, GLint param)
  static v8::Handle<v8::Value> pixelStorei(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glPixelStorei(args[0]->Uint32Value(), args[1]->Int32Value());
    return v8::Undefined();
  }

  // void polygonOffset(GLfloat factor, GLfloat units)
  static v8::Handle<v8::Value> polygonOffset(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glPolygonOffset(args[0]->NumberValue(), args[1]->NumberValue());
    return v8::Undefined();
  }

  // void readPixels(GLint x, GLint y, GLsizei width, GLsizei height,
  //                 GLenum format, GLenum type, ArrayBufferView pixels)
  static v8::Handle<v8::Value> readPixels(
      const v8::Arguments& args) {
    if (args.Length() != 7)
      return v8_utils::ThrowError("Wrong number of arguments.");

    GLint x = args[0]->Int32Value();
    GLint y = args[1]->Int32Value();
    GLsizei width = args[2]->Int32Value();
    GLsizei height = args[3]->Int32Value();
    GLenum format = args[4]->Int32Value();
    GLenum type = args[5]->Int32Value();
    if (format != GL_RGBA)
      return v8_utils::ThrowError("readPixels only supports GL_RGBA.");
    //format = GL_BGRA;  // TODO(deanm): Fixme.

    if (type != GL_UNSIGNED_BYTE)
      return v8_utils::ThrowError("readPixels only supports GL_UNSIGNED_BYTE.");

    if (!args[6]->IsObject())
      return v8_utils::ThrowError("readPixels only supports Uint8Array.");

    v8::Handle<v8::Object> data = v8::Handle<v8::Object>::Cast(args[6]);

    if (data->GetIndexedPropertiesExternalArrayDataType() !=
        v8::kExternalUnsignedByteArray)
      return v8_utils::ThrowError("readPixels only supports Uint8Array.");

    // TODO(deanm):  From the spec (requires synthesizing gl errors):
    //   If pixels is non-null, but is not large enough to retrieve all of the
    //   pixels in the specified rectangle taking into account pixel store
    //   modes, an INVALID_OPERATION value is generated.
    if (data->GetIndexedPropertiesExternalArrayDataLength() < width*height*4)
      return v8_utils::ThrowError("Uint8Array buffer too small.");

    glReadPixels(x, y, width, height, format, type,
                 data->GetIndexedPropertiesExternalArrayData());
    return v8::Undefined();
  }

  // void renderbufferStorage(GLenum target, GLenum internalformat,
  //                          GLsizei width, GLsizei height)
  static v8::Handle<v8::Value> renderbufferStorage(const v8::Arguments& args) {
    if (args.Length() != 4)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glRenderbufferStorage(args[0]->Uint32Value(),
                          args[1]->Uint32Value(),
                          args[2]->Int32Value(),
                          args[3]->Int32Value());
    return v8::Undefined();
  }

  // void sampleCoverage(GLclampf value, GLboolean invert)
  static v8::Handle<v8::Value> sampleCoverage(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glSampleCoverage(args[0]->NumberValue(),
                     args[1]->BooleanValue());
    return v8::Undefined();
  }

  // void scissor(GLint x, GLint y, GLsizei width, GLsizei height)
  static v8::Handle<v8::Value> scissor(const v8::Arguments& args) {
    if (args.Length() != 4)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glScissor(args[0]->Int32Value(),
              args[1]->Int32Value(),
              args[2]->Int32Value(),
              args[3]->Int32Value());
    return v8::Undefined();
  }

  // void shaderSource(WebGLShader shader, DOMString source)
  static v8::Handle<v8::Value> shaderSource(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    v8::String::Utf8Value data(args[1]->ToString());
    // NOTE(deanm): We want GLSL version 1.20.  Is there a better way to do this
    // than sneaking in a #version at the beginning?
    const GLchar* strs[] = { "#version 120\n", *data };
    glShaderSource(args[0]->Uint32Value(), 2, strs, NULL);
    return v8::Undefined();
  }

  // void stencilFunc(GLenum func, GLint ref, GLuint mask)
  static v8::Handle<v8::Value> stencilFunc(const v8::Arguments& args) {
    if (args.Length() != 3)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glStencilFunc(args[0]->Uint32Value(),
                  args[1]->Int32Value(),
                  args[2]->Uint32Value());
    return v8::Undefined();
  }

  // void stencilFuncSeparate(GLenum face, GLenum func, GLint ref, GLuint mask)
  static v8::Handle<v8::Value> stencilFuncSeparate(const v8::Arguments& args) {
    if (args.Length() != 4)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glStencilFuncSeparate(args[0]->Uint32Value(),
                          args[1]->Uint32Value(),
                          args[2]->Int32Value(),
                          args[3]->Uint32Value());
    return v8::Undefined();
  }

  // void stencilMask(GLuint mask)
  static v8::Handle<v8::Value> stencilMask(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glStencilMask(args[0]->Uint32Value());
    return v8::Undefined();
  }

  // void stencilMaskSeparate(GLenum face, GLuint mask)
  static v8::Handle<v8::Value> stencilMaskSeparate(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glStencilMaskSeparate(args[0]->Uint32Value(), args[1]->Uint32Value());
    return v8::Undefined();
  }

  // void stencilOp(GLenum fail, GLenum zfail, GLenum zpass)
  static v8::Handle<v8::Value> stencilOp(const v8::Arguments& args) {
    if (args.Length() != 3)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glStencilOp(args[0]->Uint32Value(),
                args[1]->Uint32Value(),
                args[2]->Uint32Value());
    return v8::Undefined();
  }

  // void stencilOpSeparate(GLenum face, GLenum fail,
  //                        GLenum zfail, GLenum zpass)
  static v8::Handle<v8::Value> stencilOpSeparate(const v8::Arguments& args) {
    if (args.Length() != 4)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glStencilOpSeparate(args[0]->Uint32Value(),
                        args[1]->Uint32Value(),
                        args[2]->Uint32Value(),
                        args[3]->Uint32Value());
    return v8::Undefined();
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
  static v8::Handle<v8::Value> texImage2D(const v8::Arguments& args) {
    if (args.Length() != 9)
      return v8_utils::ThrowError("Wrong number of arguments.");

    GLvoid* data = NULL;

    if (!args[8]->IsNull()) {
      if (!args[8]->IsObject())
        return v8_utils::ThrowError("Data must be an ArrayBuffer.");

      v8::Local<v8::Object> obj = v8::Local<v8::Object>::Cast(args[8]);
      if (!obj->HasIndexedPropertiesInExternalArrayData())
        return v8_utils::ThrowError("Data must be an ArrayBuffer.");

      // TODO(deanm): Check size / format.  For now just use it correctly.
      data = obj->GetIndexedPropertiesExternalArrayData();
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
    return v8::Undefined();
  }

  // NOTE: implemented outside of class definition (SkCanvasWrapper dependency).
  static v8::Handle<v8::Value> texImage2DSkCanvasB(const v8::Arguments& args);
  static v8::Handle<v8::Value> drawSkCanvas(const v8::Arguments& args);

  // void texParameterf(GLenum target, GLenum pname, GLfloat param)
  static v8::Handle<v8::Value> texParameterf(const v8::Arguments& args) {
    if (args.Length() != 3)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glTexParameterf(args[0]->Uint32Value(),
                    args[1]->Uint32Value(),
                    args[2]->NumberValue());
    return v8::Undefined();
  }

  // void texParameteri(GLenum target, GLenum pname, GLint param)
  static v8::Handle<v8::Value> texParameteri(const v8::Arguments& args) {
    if (args.Length() != 3)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glTexParameteri(args[0]->Uint32Value(),
                    args[1]->Uint32Value(),
                    args[2]->Int32Value());
    return v8::Undefined();
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

  static v8::Handle<v8::Value> texSubImage2D(const v8::Arguments& args) {
    if (args.Length() != 9)
      return v8_utils::ThrowError("Wrong number of arguments.");

    GLvoid* data = NULL;

    if (!args[8]->IsNull()) {
      if (!args[8]->IsObject())
        return v8_utils::ThrowError("Data must be an ArrayBuffer.");

      v8::Local<v8::Object> obj = v8::Local<v8::Object>::Cast(args[8]);
      if (!obj->HasIndexedPropertiesInExternalArrayData())
        return v8_utils::ThrowError("Data must be an ArrayBuffer.");

      // TODO(deanm): Check size / format.  For now just use it correctly.
      data = obj->GetIndexedPropertiesExternalArrayData();
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
    return v8::Undefined();
  }

  template<void uniformFuncT(GLint, GLsizei, const GLfloat*)>
  static v8::Handle<v8::Value> uniformfHelper(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (args[0]->IsNull())  // null location is silently ignored.
      return v8::Undefined();

    if (!WebGLUniformLocation::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    int length = 0;
    if (!args[1]->IsObject())
      return v8_utils::ThrowError("value must be an Sequence.");

    v8::Handle<v8::Object> obj = v8::Handle<v8::Object>::Cast(args[1]);
    if (obj->HasIndexedPropertiesInExternalArrayData()) {
      length = obj->GetIndexedPropertiesExternalArrayDataLength();
    } else if (obj->IsArray()) {
      length = v8::Handle<v8::Array>::Cast(obj)->Length();
    } else {
      return v8_utils::ThrowError("value must be an Sequence.");
    }

    float* buffer = new float[length];
    for (int i = 0; i < length; ++i) {
      buffer[i] = obj->Get(i)->NumberValue();
    }
    uniformFuncT(location, length, buffer);
    delete[] buffer;
    return v8::Undefined();
  }

  template<void uniformFuncT(GLint, GLsizei, const GLint*)>
  static v8::Handle<v8::Value> uniformiHelper(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (args[0]->IsNull())  // null location is silently ignored.
      return v8::Undefined();

    if (!WebGLUniformLocation::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    int length = 0;
    if (!args[1]->IsObject())
      return v8_utils::ThrowError("value must be an Sequence.");

    v8::Handle<v8::Object> obj = v8::Handle<v8::Object>::Cast(args[1]);
    if (obj->HasIndexedPropertiesInExternalArrayData()) {
      length = obj->GetIndexedPropertiesExternalArrayDataLength();
    } else if (obj->IsArray()) {
      length = v8::Handle<v8::Array>::Cast(obj)->Length();
    } else {
      return v8_utils::ThrowError("value must be an Sequence.");
    }

    GLint* buffer = new GLint[length];
    for (int i = 0; i < length; ++i) {
      buffer[i] = obj->Get(i)->Int32Value();
    }
    uniformFuncT(location, length, buffer);
    delete[] buffer;
    return v8::Undefined();
  }

  // void uniform1f(WebGLUniformLocation location, GLfloat x)
  static v8::Handle<v8::Value> uniform1f(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (args[0]->IsNull())  // null location is silently ignored.
      return v8::Undefined();

    if (!WebGLUniformLocation::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform1f(location, args[1]->NumberValue());
    return v8::Undefined();
  }

  // void uniform1fv(WebGLUniformLocation location, Float32Array v)
  // void uniform1fv(WebGLUniformLocation location, sequence v)
  static v8::Handle<v8::Value> uniform1fv(const v8::Arguments& args) {
    return uniformfHelper<glUniform1fv>(args);
  }

  // void uniform1i(WebGLUniformLocation location, GLint x)
  static v8::Handle<v8::Value> uniform1i(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (args[0]->IsNull())  // null location is silently ignored.
      return v8::Undefined();

    if (!WebGLUniformLocation::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform1i(location, args[1]->Int32Value());
    return v8::Undefined();
  }

  // void uniform1iv(WebGLUniformLocation location, Int32Array v)
  // void uniform1iv(WebGLUniformLocation location, sequence v)
  static v8::Handle<v8::Value> uniform1iv(const v8::Arguments& args) {
    return uniformiHelper<glUniform1iv>(args);
  }

  // void uniform2f(WebGLUniformLocation location, GLfloat x, GLfloat y)
  static v8::Handle<v8::Value> uniform2f(const v8::Arguments& args) {
    if (args.Length() != 3)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (args[0]->IsNull())  // null location is silently ignored.
      return v8::Undefined();

    if (!WebGLUniformLocation::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform2f(location,
                args[1]->NumberValue(),
                args[2]->NumberValue());
    return v8::Undefined();
  }

  // void uniform2fv(WebGLUniformLocation location, Float32Array v)
  // void uniform2fv(WebGLUniformLocation location, sequence v)
  static v8::Handle<v8::Value> uniform2fv(const v8::Arguments& args) {
    return uniformfHelper<glUniform2fv>(args);
  }

  // void uniform2i(WebGLUniformLocation location, GLint x, GLint y)
  static v8::Handle<v8::Value> uniform2i(const v8::Arguments& args) {
    if (args.Length() != 3)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (args[0]->IsNull())  // null location is silently ignored.
      return v8::Undefined();

    if (!WebGLUniformLocation::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform2i(location,
                args[1]->Int32Value(),
                args[2]->Int32Value());
    return v8::Undefined();
  }

  // void uniform2iv(WebGLUniformLocation location, Int32Array v)
  // void uniform2iv(WebGLUniformLocation location, sequence v)
  static v8::Handle<v8::Value> uniform2iv(const v8::Arguments& args) {
    return uniformiHelper<glUniform2iv>(args);
  }

  // void uniform3f(WebGLUniformLocation location, GLfloat x, GLfloat y,
  //                GLfloat z)
  static v8::Handle<v8::Value> uniform3f(const v8::Arguments& args) {
    if (args.Length() != 4)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (args[0]->IsNull())  // null location is silently ignored.
      return v8::Undefined();

    if (!WebGLUniformLocation::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform3f(location,
                args[1]->NumberValue(),
                args[2]->NumberValue(),
                args[3]->NumberValue());
    return v8::Undefined();
  }

  // void uniform3fv(WebGLUniformLocation location, Float32Array v)
  // void uniform3fv(WebGLUniformLocation location, sequence v)
  static v8::Handle<v8::Value> uniform3fv(const v8::Arguments& args) {
    return uniformfHelper<glUniform3fv>(args);
  }

  // void uniform3i(WebGLUniformLocation location, GLint x, GLint y, GLint z)
  static v8::Handle<v8::Value> uniform3i(const v8::Arguments& args) {
    if (args.Length() != 4)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (args[0]->IsNull())  // null location is silently ignored.
      return v8::Undefined();

    if (!WebGLUniformLocation::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform3i(location,
                args[1]->Int32Value(),
                args[2]->Int32Value(),
                args[3]->Int32Value());
    return v8::Undefined();
  }

  // void uniform3iv(WebGLUniformLocation location, Int32Array v)
  // void uniform3iv(WebGLUniformLocation location, sequence v)
  static v8::Handle<v8::Value> uniform3iv(const v8::Arguments& args) {
    return uniformiHelper<glUniform3iv>(args);
  }

  // void uniform4f(WebGLUniformLocation location, GLfloat x, GLfloat y,
  //                GLfloat z, GLfloat w)
  static v8::Handle<v8::Value> uniform4f(const v8::Arguments& args) {
    if (args.Length() != 5)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (args[0]->IsNull())  // null location is silently ignored.
      return v8::Undefined();

    if (!WebGLUniformLocation::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform4f(location,
                args[1]->NumberValue(),
                args[2]->NumberValue(),
                args[3]->NumberValue(),
                args[4]->NumberValue());
    return v8::Undefined();
  }

  // void uniform4fv(WebGLUniformLocation location, Float32Array v)
  // void uniform4fv(WebGLUniformLocation location, sequence v)
  static v8::Handle<v8::Value> uniform4fv(const v8::Arguments& args) {
    return uniformfHelper<glUniform4fv>(args);
  }

  // void uniform4i(WebGLUniformLocation location, GLint x, GLint y,
  //                GLint z, GLint w)
  static v8::Handle<v8::Value> uniform4i(const v8::Arguments& args) {
    if (args.Length() != 5)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (args[0]->IsNull())  // null location is silently ignored.
      return v8::Undefined();

    if (!WebGLUniformLocation::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    glUniform4i(location,
                args[1]->Int32Value(),
                args[2]->Int32Value(),
                args[3]->Int32Value(),
                args[4]->Int32Value());
    return v8::Undefined();
  }

  // void uniform4iv(WebGLUniformLocation location, Int32Array v)
  // void uniform4iv(WebGLUniformLocation location, sequence v)
  static v8::Handle<v8::Value> uniform4iv(const v8::Arguments& args) {
    return uniformiHelper<glUniform4iv>(args);
  }

  template<void uniformFuncT(GLint, GLsizei, GLboolean, const GLfloat*)>
  static v8::Handle<v8::Value> uniformMatrixHelper(const v8::Arguments& args) {
    if (args.Length() != 3)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (args[0]->IsNull())  // null location is silently ignored.
      return v8::Undefined();

    if (!WebGLUniformLocation::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLUniformLocation.");
    GLuint location = WebGLUniformLocation::ExtractLocationFromValue(args[0]);

    int length = 0;
    if (!args[2]->IsObject())
      return v8_utils::ThrowError("value must be an Sequence.");

    v8::Handle<v8::Object> obj = v8::Handle<v8::Object>::Cast(args[2]);
    if (obj->HasIndexedPropertiesInExternalArrayData()) {
      length = obj->GetIndexedPropertiesExternalArrayDataLength();
    } else if (obj->IsArray()) {
      length = v8::Handle<v8::Array>::Cast(obj)->Length();
    } else {
      return v8_utils::ThrowError("value must be an Sequence.");
    }

    float* buffer = new float[length];
    for (int i = 0; i < length; ++i) {
      buffer[i] = obj->Get(i)->NumberValue();
    }
    // TODO(deanm): Count should probably not be hardcoded.  It should probably
    // be based on the length and the number of elements per matrix.
    uniformFuncT(location, 1, GL_FALSE, buffer);
    delete[] buffer;
    return v8::Undefined();
  }

  // void uniformMatrix2fv(WebGLUniformLocation location, GLboolean transpose,
  //                       Float32Array value)
  // void uniformMatrix2fv(WebGLUniformLocation location, GLboolean transpose,
  //                       sequence value)
  static v8::Handle<v8::Value> uniformMatrix2fv(const v8::Arguments& args) {
    return uniformMatrixHelper<glUniformMatrix2fv>(args);
  }

  // void uniformMatrix3fv(WebGLUniformLocation location, GLboolean transpose,
  //                       Float32Array value)
  // void uniformMatrix3fv(WebGLUniformLocation location, GLboolean transpose,
  //                       sequence value)
  static v8::Handle<v8::Value> uniformMatrix3fv(const v8::Arguments& args) {
    return uniformMatrixHelper<glUniformMatrix3fv>(args);
  }

  // void uniformMatrix4fv(WebGLUniformLocation location, GLboolean transpose,
  //                       Float32Array value)
  // void uniformMatrix4fv(WebGLUniformLocation location, GLboolean transpose,
  //                       sequence value)
  static v8::Handle<v8::Value> uniformMatrix4fv(const v8::Arguments& args) {
    return uniformMatrixHelper<glUniformMatrix4fv>(args);
  }

  // void useProgram(WebGLProgram program)
  static v8::Handle<v8::Value> useProgram(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!WebGLProgram::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLProgram.");
    GLuint program = WebGLProgram::ExtractIDFromValue(args[0]);

    glUseProgram(program);
    return v8::Undefined();
  }

  // void validateProgram(WebGLProgram program)
  static v8::Handle<v8::Value> validateProgram(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!WebGLProgram::HasInstance(args[0]))
      return v8_utils::ThrowTypeError("Expected a WebGLProgram.");
    GLuint program = WebGLProgram::ExtractIDFromValue(args[0]);

    glValidateProgram(program);
    return v8::Undefined();
  }

  // NOTE: The array forms (functions that end in v) are handled in plask.js.

  // void vertexAttrib1f(GLuint indx, GLfloat x)
  // void vertexAttrib1fv(GLuint indx, Float32Array values)
  // void vertexAttrib1fv(GLuint indx, sequence values)
  static v8::Handle<v8::Value> vertexAttrib1f(const v8::Arguments& args) {
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glVertexAttrib1f(args[0]->Uint32Value(),
                     args[1]->NumberValue());
    return v8::Undefined();
  }

  // void vertexAttrib2f(GLuint indx, GLfloat x, GLfloat y)
  // void vertexAttrib2fv(GLuint indx, Float32Array values)
  // void vertexAttrib2fv(GLuint indx, sequence values)
  static v8::Handle<v8::Value> vertexAttrib2f(const v8::Arguments& args) {
    if (args.Length() != 3)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glVertexAttrib2f(args[0]->Uint32Value(),
                     args[1]->NumberValue(),
                     args[2]->NumberValue());
    return v8::Undefined();
  }

  // void vertexAttrib3f(GLuint indx, GLfloat x, GLfloat y, GLfloat z)
  // void vertexAttrib3fv(GLuint indx, Float32Array values)
  // void vertexAttrib3fv(GLuint indx, sequence values)
  static v8::Handle<v8::Value> vertexAttrib3f(const v8::Arguments& args) {
    if (args.Length() != 4)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glVertexAttrib3f(args[0]->Uint32Value(),
                     args[1]->NumberValue(),
                     args[2]->NumberValue(),
                     args[3]->NumberValue());
    return v8::Undefined();
  }

  // void vertexAttrib4f(GLuint indx, GLfloat x, GLfloat y,
  //                     GLfloat z, GLfloat w)
  // void vertexAttrib4fv(GLuint indx, Float32Array values)
  // void vertexAttrib4fv(GLuint indx, sequence values)
  static v8::Handle<v8::Value> vertexAttrib4f(const v8::Arguments& args) {
    if (args.Length() != 5)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glVertexAttrib4f(args[0]->Uint32Value(),
                     args[1]->NumberValue(),
                     args[2]->NumberValue(),
                     args[3]->NumberValue(),
                     args[4]->NumberValue());
    return v8::Undefined();
  }

  // void vertexAttribPointer(GLuint indx, GLint size, GLenum type,
  //                          GLboolean normalized, GLsizei stride,
  //                          GLsizeiptr offset)
  static v8::Handle<v8::Value> vertexAttribPointer(const v8::Arguments& args) {
    if (args.Length() != 6)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glVertexAttribPointer(args[0]->Uint32Value(),
                          args[1]->Int32Value(),
                          args[2]->Uint32Value(),
                          args[3]->BooleanValue(),
                          args[4]->Int32Value(),
                          reinterpret_cast<GLvoid*>(args[5]->Int32Value()));
    return v8::Undefined();
  }

  // void viewport(GLint x, GLint y, GLsizei width, GLsizei height)
  static v8::Handle<v8::Value> viewport(const v8::Arguments& args) {
    if (args.Length() != 4)
      return v8_utils::ThrowError("Wrong number of arguments.");

    glViewport(args[0]->Int32Value(),
               args[1]->Int32Value(),
               args[2]->Int32Value(),
               args[3]->Int32Value());
    return v8::Undefined();
  }

  // void DrawBuffersARB(sizei n, const enum *bufs);
  static v8::Handle<v8::Value> drawBuffers(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!args[0]->IsArray())
      return v8_utils::ThrowError("Sequence must be an Array.");

    v8::Local<v8::Array> arr = v8::Local<v8::Array>::Cast(args[0]);

    uint32_t length = arr->Length();
    GLenum* attachments = new GLenum[length];
    for (uint32_t i = 0; i < length; ++i) {
      attachments[i] = arr->Get(i)->Uint32Value();
    }

    glDrawBuffers(length, attachments);
    delete[] attachments;
    return v8::Undefined();
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
  static v8::Handle<v8::Value> blitFramebuffer(const v8::Arguments& args) {
    if (args.Length() != 10)
      return v8_utils::ThrowError("Wrong number of arguments.");

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
    return v8::Undefined();
  }
};


class NSWindowWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&NSWindowWrapper::V8New));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(3);  // NSWindow, bitmap, and context.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(ft_cache);

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
      ft_cache->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::New(methods[i].name),
                    v8::FunctionTemplate::New(methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    return ft_cache;
  }

  static WrappedNSWindow* ExtractWindowPointer(v8::Handle<v8::Object> obj) {
    return v8_utils::UnwrapCPointer<WrappedNSWindow>(obj->GetInternalField(0));
  }

  static SkBitmap* ExtractSkBitmapPointer(v8::Handle<v8::Object> obj) {
    return v8_utils::UnwrapCPointer<SkBitmap>(obj->GetInternalField(1));
  }

  static NSOpenGLContext* ExtractContextPointer(v8::Handle<v8::Object> obj) {
    return v8_utils::UnwrapCPointer<NSOpenGLContext>(obj->GetInternalField(2));
  }

  static bool HasInstance(v8::Handle<v8::Value> value) {
    return GetTemplate()->HasInstance(value);
  }

 private:
  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    if (args.Length() != 6)
      return v8_utils::ThrowError("Wrong number of arguments.");
    uint32_t type = args[0]->Uint32Value();
    uint32_t width = args[1]->Uint32Value();
    uint32_t height = args[2]->Uint32Value();
    bool multisample = args[3]->BooleanValue();
    int display = args[4]->Int32Value();
    bool fullscreen = args[5]->BooleanValue();

    NSScreen* screen = [NSScreen mainScreen];
    NSArray* screens = [NSScreen screens];

    if (display < [screens count]) {
      screen = [screens objectAtIndex:display];
      NSLog(@"Using alternate screen: %@", screen);
    }

    int style_mask = NSTitledWindowMask; // | NSClosableWindowMask

    if (fullscreen)
      style_mask = NSBorderlessWindowMask;

    WrappedNSWindow* window = [[WrappedNSWindow alloc]
        initWithContentRect:NSMakeRect(0.0, 0.0,
                                       width,
                                       height)
        styleMask:style_mask
        backing:NSBackingStoreBuffered
        defer:NO
        screen: screen];
    // CGColorSpaceRef rgb_space = CGColorSpaceCreateDeviceRGB();
    // CGBitmapContextCreate(NULL, width, height, 8, width * 4, rgb_space,
    //                       kCGBitmapByteOrder32Little |
    //                       kCGImageAlphaNoneSkipFirst);
    // CGColorSpaceRelease(rgb_space)
    //
    // kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little;
    SkBitmap* bitmap = NULL;
    NSOpenGLContext* context = NULL;

    if (type == 0) {  // 2d window.
      bitmap = new SkBitmap;
      bitmap->setConfig(SkBitmap::kARGB_8888_Config, width, height, width * 4);
      bitmap->allocPixels();
      bitmap->eraseARGB(0, 0, 0, 0);

      BlitImageView* view = [[BlitImageView alloc] initWithSkBitmap:bitmap];
      [window setContentView:view];
      [view release];
    } else if (type == 1) {  // 3d window.
      NSOpenGLPixelFormatAttribute attrs[] = {
          NSOpenGLPFAColorSize, 24,
          NSOpenGLPFADepthSize, 16,
          NSOpenGLPFADoubleBuffer,
          NSOpenGLPFAAccelerated,
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

      v8::Local<v8::Object> context_wrapper =
          NSOpenGLContextWrapper::GetTemplate()->
              InstanceTemplate()->NewInstance();
      context_wrapper->SetInternalField(0, v8_utils::WrapCPointer(context));
      args.This()->Set(v8::String::New("context"), context_wrapper);
    }

    if (fullscreen)
      [window setLevel:NSMainMenuWindowLevel+1];
    [window setDelegate:[[[WindowDelegate alloc] init] autorelease]];
    [window makeKeyAndOrderFront:nil];

    args.This()->SetInternalField(0, v8_utils::WrapCPointer(window));
    args.This()->SetInternalField(1, v8_utils::WrapCPointer(bitmap));
    args.This()->SetInternalField(2, v8_utils::WrapCPointer(context));

    return args.This();
  }

  static v8::Handle<v8::Value> blit(const v8::Arguments& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.This());
    NSOpenGLContext* context = ExtractContextPointer(args.This());
    if (context) {  // 3d, swap the buffers.
      [context flushBuffer];
    } else {  // 2d, redisplay the view.
      [[window contentView] display];
    }
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> mouseLocationOutsideOfEventStream(
      const v8::Arguments& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.This());
    NSPoint pos = [window mouseLocationOutsideOfEventStream];
    v8::Local<v8::Object> res = v8::Object::New();
    res->Set(v8::String::New("x"), v8::Number::New(pos.x));
    res->Set(v8::String::New("y"), v8::Number::New(pos.y));
    return res;
  }

  static v8::Handle<v8::Value> setAcceptsMouseMovedEvents(
      const v8::Arguments& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.This());
    [window setAcceptsMouseMovedEvents:args[0]->BooleanValue()];
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> setAcceptsFileDrag(
      const v8::Arguments& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.This());
    if (args[0]->BooleanValue()) {
      [window registerForDraggedTypes:
          [NSArray arrayWithObject:NSFilenamesPboardType]];
    } else {
      [window unregisterDraggedTypes];
    }
    return v8::Undefined();
  }

  // You should only really call this once, it's a pretty raw function.
  static v8::Handle<v8::Value> setEventCallback(const v8::Arguments& args) {
    if (args.Length() != 1 || !args[0]->IsFunction())
      return v8_utils::ThrowError("Incorrect invocation of setEventCallback.");
    WrappedNSWindow* window = ExtractWindowPointer(args.This());
    [window setEventCallbackWithHandle:v8::Handle<v8::Function>::Cast(args[0])];
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> setTitle(const v8::Arguments& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.This());
    v8::String::Utf8Value title(args[0]->ToString());
    [window setTitle:[NSString stringWithUTF8String:*title]];
    return v8::Undefined();
  }
  static v8::Handle<v8::Value> setFrameTopLeftPoint(const v8::Arguments& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.This());
    if (args.Length() != 2)
      return v8_utils::ThrowError("Wrong number of arguments.");
    [window setFrameTopLeftPoint:NSMakePoint(args[0]->NumberValue(),
                                             args[1]->NumberValue())];
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> center(const v8::Arguments& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.This());
    [window center];
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> hideCursor(const v8::Arguments& args) {
    CGDisplayHideCursor(kCGDirectMainDisplay);
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> showCursor(const v8::Arguments& args) {
    CGDisplayShowCursor(kCGDirectMainDisplay);
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> hide(const v8::Arguments& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.This());
    [window orderOut:nil];
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> show(const v8::Arguments& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.This());
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
        return v8_utils::ThrowError("Unknown argument to show().");
        break;
    }

    return v8::Undefined();
  }

  static v8::Handle<v8::Value> screenSize(const v8::Arguments& args) {
    WrappedNSWindow* window = ExtractWindowPointer(args.This());
    NSRect frame = [[window screen] frame];
    v8::Local<v8::Object> res = v8::Object::New();
    res->Set(v8::String::New("width"), v8::Number::New(frame.size.width));
    res->Set(v8::String::New("height"), v8::Number::New(frame.size.height));
    return res;
  }

};


class NSEventWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&NSEventWrapper::V8New));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // NSEvent pointer.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(ft_cache);

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
      ft_cache->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(class_methods); ++i) {
      ft_cache->Set(v8::String::New(class_methods[i].name),
                    v8::FunctionTemplate::New(class_methods[i].func,
                                              v8::Handle<v8::Value>()));
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::New(methods[i].name),
                    v8::FunctionTemplate::New(methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    return ft_cache;
  }

  static bool HasInstance(v8::Handle<v8::Value> value) {
    return GetTemplate()->HasInstance(value);
  }

  static NSEvent* ExtractPointer(v8::Handle<v8::Object> obj) {
    return v8_utils::UnwrapCPointer<NSEvent>(obj->GetInternalField(0));
  }

 private:
  // This will be called when we create a new instance from the instance
  // template, wrapping a NSEvent*.  It can also be called directly from
  // JavaScript, which is a bit of a problem, but we'll survive.
  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    args.This()->SetInternalField(0, v8_utils::WrapCPointer(NULL));
    return args.This();
  }

  static v8::Handle<v8::Value> class_pressedMouseButtons(
      const v8::Arguments& args) {
    return v8::Integer::NewFromUnsigned([NSEvent pressedMouseButtons]);
  }

  static v8::Handle<v8::Value> type(const v8::Arguments& args) {
    NSEvent* event = NSEventWrapper::ExtractPointer(args.This());
    return v8::Integer::NewFromUnsigned([event type]);
  }

  static v8::Handle<v8::Value> buttonNumber(const v8::Arguments& args) {
    NSEvent* event = NSEventWrapper::ExtractPointer(args.This());
    return v8::Integer::NewFromUnsigned([event buttonNumber]);
  }

  static v8::Handle<v8::Value> characters(const v8::Arguments& args) {
    NSEvent* event = NSEventWrapper::ExtractPointer(args.This());
    NSString* characters = [event characters];
    return v8::String::New(
        [characters UTF8String],
        [characters lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
  }

  static v8::Handle<v8::Value> keyCode(const v8::Arguments& args) {
    NSEvent* event = NSEventWrapper::ExtractPointer(args.This());
    return v8::Integer::NewFromUnsigned([event keyCode]);
  }

  static v8::Handle<v8::Value> locationInWindow(const v8::Arguments& args) {
    NSEvent* event = NSEventWrapper::ExtractPointer(args.This());
    // If window is nil we'll instead get screen coordinates.
    if ([event window] == nil)
      return v8_utils::ThrowError("Calling locationInWindow with nil window.");
    NSPoint pos = [event locationInWindow];
    v8::Local<v8::Object> res = v8::Object::New();
    res->Set(v8::String::New("x"), v8::Number::New(pos.x));
    res->Set(v8::String::New("y"), v8::Number::New(pos.y));
    return res;
  }

  static v8::Handle<v8::Value> deltaX(const v8::Arguments& args) {
    NSEvent* event = NSEventWrapper::ExtractPointer(args.This());
    return v8::Number::New([event deltaX]);
  }

  static v8::Handle<v8::Value> deltaY(const v8::Arguments& args) {
    NSEvent* event = NSEventWrapper::ExtractPointer(args.This());
    return v8::Number::New([event deltaY]);
  }

  static v8::Handle<v8::Value> deltaZ(const v8::Arguments& args) {
    NSEvent* event = NSEventWrapper::ExtractPointer(args.This());
    return v8::Number::New([event deltaZ]);
  }

  static v8::Handle<v8::Value> pressure(const v8::Arguments& args) {
    NSEvent* event = NSEventWrapper::ExtractPointer(args.This());
    return v8::Number::New([event pressure]);
  }

  static v8::Handle<v8::Value> isEnteringProximity(const v8::Arguments& args) {
    NSEvent* event = NSEventWrapper::ExtractPointer(args.This());
    return v8::Boolean::New([event isEnteringProximity]);
  }

  static v8::Handle<v8::Value> modifierFlags(const v8::Arguments& args) {
    NSEvent* event = NSEventWrapper::ExtractPointer(args.This());
    return v8::Integer::NewFromUnsigned([event modifierFlags]);
  }
};

class SkPathWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&SkPathWrapper::V8New));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // SkPath pointer.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(ft_cache);

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
      { "addCircle", &SkPathWrapper::addCircle },
      { "close", &SkPathWrapper::close },
      { "offset", &SkPathWrapper::offset },
      { "getBounds", &SkPathWrapper::getBounds },
      { "toSVGString", &SkPathWrapper::toSVGString },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      ft_cache->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::New(methods[i].name),
                    v8::FunctionTemplate::New(methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    return ft_cache;
  }

  static SkPath* ExtractPointer(v8::Handle<v8::Object> obj) {
    return v8_utils::UnwrapCPointer<SkPath>(obj->GetInternalField(0));
  }

  static bool HasInstance(v8::Handle<v8::Value> value) {
    return GetTemplate()->HasInstance(value);
  }

 private:
  static v8::Handle<v8::Value> reset(const v8::Arguments& args) {
    SkPath* path = ExtractPointer(args.This());  // TODO should be holder?
    path->reset();
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> rewind(const v8::Arguments& args) {
    SkPath* path = ExtractPointer(args.This());  // TODO should be holder?
    path->rewind();
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> moveTo(const v8::Arguments& args) {
    SkPath* path = ExtractPointer(args.This());  // TODO should be holder?

    path->moveTo(SkDoubleToScalar(args[0]->NumberValue()),
                 SkDoubleToScalar(args[1]->NumberValue()));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> lineTo(const v8::Arguments& args) {
    SkPath* path = ExtractPointer(args.This());  // TODO should be holder?

    path->lineTo(SkDoubleToScalar(args[0]->NumberValue()),
                 SkDoubleToScalar(args[1]->NumberValue()));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> rLineTo(const v8::Arguments& args) {
    SkPath* path = ExtractPointer(args.This());  // TODO should be holder?

    path->rLineTo(SkDoubleToScalar(args[0]->NumberValue()),
                  SkDoubleToScalar(args[1]->NumberValue()));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> quadTo(const v8::Arguments& args) {
    SkPath* path = ExtractPointer(args.This());  // TODO should be holder?

    path->quadTo(SkDoubleToScalar(args[0]->NumberValue()),
                 SkDoubleToScalar(args[1]->NumberValue()),
                 SkDoubleToScalar(args[2]->NumberValue()),
                 SkDoubleToScalar(args[3]->NumberValue()));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> cubicTo(const v8::Arguments& args) {
    SkPath* path = ExtractPointer(args.This());  // TODO should be holder?

    path->cubicTo(SkDoubleToScalar(args[0]->NumberValue()),
                  SkDoubleToScalar(args[1]->NumberValue()),
                  SkDoubleToScalar(args[2]->NumberValue()),
                  SkDoubleToScalar(args[3]->NumberValue()),
                  SkDoubleToScalar(args[4]->NumberValue()),
                  SkDoubleToScalar(args[5]->NumberValue()));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> addCircle(const v8::Arguments& args) {
    SkPath* path = ExtractPointer(args.This());  // TODO should be holder?

    path->addCircle(SkDoubleToScalar(args[0]->NumberValue()),
                  SkDoubleToScalar(args[1]->NumberValue()),
                  SkDoubleToScalar(args[2]->NumberValue()));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> close(const v8::Arguments& args) {
    SkPath* path = ExtractPointer(args.This());  // TODO should be holder?
    path->close();
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> offset(const v8::Arguments& args) {
    SkPath* path = ExtractPointer(args.This());  // TODO should be holder?
    path->offset(SkDoubleToScalar(args[0]->NumberValue()),
                 SkDoubleToScalar(args[1]->NumberValue()));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> getBounds(const v8::Arguments& args) {
    SkPath* path = ExtractPointer(args.This());  // TODO should be holder?
    SkRect bounds = path->getBounds();
    v8::Local<v8::Array> res = v8::Array::New(4);
    res->Set(v8::Integer::New(0), v8::Number::New(bounds.fLeft));
    res->Set(v8::Integer::New(1), v8::Number::New(bounds.fTop));
    res->Set(v8::Integer::New(2), v8::Number::New(bounds.fRight));
    res->Set(v8::Integer::New(3), v8::Number::New(bounds.fBottom));
    return res;
  }

  static v8::Handle<v8::Value> toSVGString(const v8::Arguments& args) {
    SkPath* path = ExtractPointer(args.This());  // TODO should be holder?
    SkString str;
    SkParsePath::ToSVGString(*path, &str);
    return v8::String::New(str.c_str(), str.size());
  }

  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    SkPath* prev_path = NULL;
    if (SkPathWrapper::HasInstance(args[0])) {
      prev_path = SkPathWrapper::ExtractPointer(
          v8::Handle<v8::Object>::Cast(args[0]));
    }

    SkPath* path = prev_path ? new SkPath(*prev_path) : new SkPath;
    args.This()->SetInternalField(0, v8_utils::WrapCPointer(path));
    return args.This();
  }
};


class SkPaintWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&SkPaintWrapper::V8New));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // SkPaint pointer.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(ft_cache);

    // Configure the template...
    static BatchedConstants constants[] = {
      // Flags.
      { "kAntiAliasFlag", SkPaint::kAntiAlias_Flag },
      { "kFilterBitmapFlag", SkPaint::kFilterBitmap_Flag },
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
      { "getStrokeWidth", &SkPaintWrapper::getStrokeWidth },
      { "setStrokeWidth", &SkPaintWrapper::setStrokeWidth },
      { "getStyle", &SkPaintWrapper::getStyle },
      { "setStyle", &SkPaintWrapper::setStyle },
      { "getStrokeCap", &SkPaintWrapper::getStrokeCap },
      { "setStrokeCap", &SkPaintWrapper::setStrokeCap },
      { "setColor", &SkPaintWrapper::setColor },
      { "setColorHSV", &SkPaintWrapper::setColorHSV },
      { "setTextSize", &SkPaintWrapper::setTextSize },
      { "setXfermodeMode", &SkPaintWrapper::setXfermodeMode },
      { "setFontFamily", &SkPaintWrapper::setFontFamily },
      { "setLinearGradientShader", &SkPaintWrapper::setLinearGradientShader },
      { "setRadialGradientShader", &SkPaintWrapper::setRadialGradientShader },
      { "clearShader", &SkPaintWrapper::clearShader },
      { "measureText", &SkPaintWrapper::measureText },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      ft_cache->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::New(methods[i].name),
                    v8::FunctionTemplate::New(methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    return ft_cache;
  }

  static SkPaint* ExtractPointer(v8::Handle<v8::Object> obj) {
    return v8_utils::UnwrapCPointer<SkPaint>(obj->GetInternalField(0));
  }

  static bool HasInstance(v8::Handle<v8::Value> value) {
    return GetTemplate()->HasInstance(value);
  }

 private:
  static v8::Handle<v8::Value> reset(const v8::Arguments& args) {
    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?
    paint->reset();
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> getFlags(const v8::Arguments& args) {
    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?
    return v8::Uint32::New(paint->getFlags());
  }

  static v8::Handle<v8::Value> setFlags(const v8::Arguments& args) {
    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?
    paint->setFlags(v8_utils::ToInt32(args[0]));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> getStrokeWidth(const v8::Arguments& args) {
    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?
    return v8::Number::New(SkScalarToDouble(paint->getStrokeWidth()));
  }

  static v8::Handle<v8::Value> setStrokeWidth(const v8::Arguments& args) {
    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?
    paint->setStrokeWidth(SkDoubleToScalar(args[0]->NumberValue()));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> getStyle(const v8::Arguments& args) {
    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?
    return v8::Uint32::New(paint->getStyle());
  }

  static v8::Handle<v8::Value> setStyle(const v8::Arguments& args) {
    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?
    paint->setStyle(static_cast<SkPaint::Style>(v8_utils::ToInt32(args[0])));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> getStrokeCap(const v8::Arguments& args) {
    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?
    return v8::Uint32::New(paint->getStrokeCap());
  }

  static v8::Handle<v8::Value> setStrokeCap(const v8::Arguments& args) {
    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?
    paint->setStrokeCap(static_cast<SkPaint::Cap>(v8_utils::ToInt32(args[0])));
    return v8::Undefined();
  }

  // We wrap it as 4 params instead of 1 to try to keep things as SMIs.
  static v8::Handle<v8::Value> setColor(const v8::Arguments& args) {
    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?

    int r = Clamp(v8_utils::ToInt32WithDefault(args[0], 0), 0, 255);
    int g = Clamp(v8_utils::ToInt32WithDefault(args[1], 0), 0, 255);
    int b = Clamp(v8_utils::ToInt32WithDefault(args[2], 0), 0, 255);
    int a = Clamp(v8_utils::ToInt32WithDefault(args[3], 255), 0, 255);

    paint->setColor(SkColorSetARGB(a, r, g, b));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> setColorHSV(const v8::Arguments& args) {
    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?

    // TODO(deanm): Clamp.
    SkScalar hsv[] = { SkDoubleToScalar(args[0]->NumberValue()),
                       SkDoubleToScalar(args[1]->NumberValue()),
                       SkDoubleToScalar(args[2]->NumberValue()) };
    int a = Clamp(v8_utils::ToInt32WithDefault(args[3], 255), 0, 255);

    paint->setColor(SkHSVToColor(a, hsv));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> setTextSize(const v8::Arguments& args) {
    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?

    paint->setTextSize(SkDoubleToScalar(args[0]->NumberValue()));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> setXfermodeMode(const v8::Arguments& args) {
    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?

    // TODO(deanm): Memory management.
    paint->setXfermodeMode(
          static_cast<SkXfermode::Mode>(v8_utils::ToInt32(args[0])));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> setFontFamily(const v8::Arguments& args) {
    if (args.Length() < 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?
    v8::String::Utf8Value family_name(args[0]->ToString());
    paint->setTypeface(SkTypeface::CreateFromName(
        *family_name, static_cast<SkTypeface::Style>(args[1]->Uint32Value())));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> setLinearGradientShader(
      const v8::Arguments& args) {
    if (args.Length() != 5)
      return v8_utils::ThrowError("Wrong number of arguments.");

    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?

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

    return v8::Undefined();
  }

  static v8::Handle<v8::Value> setRadialGradientShader(
      const v8::Arguments& args) {
    if (args.Length() != 4)
      return v8_utils::ThrowError("Wrong number of arguments.");

    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?

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

    return v8::Undefined();
  }

  static v8::Handle<v8::Value> clearShader(const v8::Arguments& args) {
    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?
    paint->setShader(NULL);
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> measureText(const v8::Arguments& args) {
    SkPaint* paint = ExtractPointer(args.This());  // TODO should be holder?

    v8::String::Utf8Value utf8(args[0]->ToString());
    SkScalar width = paint->measureText(*utf8, utf8.length());
    return v8::Number::New(width);
  }

  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    SkPaint* paint = NULL;
    if (SkPaintWrapper::HasInstance(args[0])) {
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
    args.This()->SetInternalField(0, v8_utils::WrapCPointer(paint));
    return args.This();
  }
};


class SkCanvasWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&SkCanvasWrapper::V8New));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // SkCanvas pointers.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(ft_cache);

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
      { "drawPath", &SkCanvasWrapper::drawPath },
      { "drawPoints", &SkCanvasWrapper::drawPoints },
      { "drawRect", &SkCanvasWrapper::drawRect },
      { "drawRoundRect", &SkCanvasWrapper::drawRoundRect },
      { "drawText", &SkCanvasWrapper::drawText },
      { "drawTextOnPathHV", &SkCanvasWrapper::drawTextOnPathHV },
      { "resetMatrix", &SkCanvasWrapper::resetMatrix },
      { "translate", &SkCanvasWrapper::translate },
      { "scale", &SkCanvasWrapper::scale },
      { "rotate", &SkCanvasWrapper::rotate },
      { "skew", &SkCanvasWrapper::skew },
      { "save", &SkCanvasWrapper::save },
      { "restore", &SkCanvasWrapper::restore },
      { "writeImage", &SkCanvasWrapper::writeImage },
      { "dispose", &SkCanvasWrapper::dispose },
      { "writePDF", &SkCanvasWrapper::writePDF },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      ft_cache->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::New(methods[i].name),
                    v8::FunctionTemplate::New(methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    return ft_cache;
  }

  static SkCanvas* ExtractPointer(v8::Handle<v8::Object> obj) {
    return reinterpret_cast<SkCanvas*>(obj->GetPointerFromInternalField(0));
  }

  static bool HasInstance(v8::Handle<v8::Value> value) {
    return GetTemplate()->HasInstance(value);
  }

 private:
  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    // We have a level of indirection (tbitmap vs bitmap) so that we don't need
    // to copy and create a new SkBitmap in the case it already exists (for
    // example for an NSWindow which has already has an SkBitmap).  This is
    // important since a copy of an SkBitmap will have a NULL pixel pointer.
    SkBitmap tbitmap;
    SkBitmap* bitmap = &tbitmap;

    SkCanvas* canvas;
    if (args[0]->StrictEquals(v8::String::New("%PDF"))) {  // PDF constructor.
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
      tbitmap.setConfig(
          SkBitmap::kNo_Config, pdf_device->width(), pdf_device->height());
    } else if (args[0]->StrictEquals(v8::String::New("^IMG"))) {
      // Load an image, either a path to a file on disk, or a TypedArray or
      // other external array data backed JS object.
      // TODO(deanm): This is all super inefficent, we copy / flip / etc.

      FIBITMAP* fbitmap = NULL;

      if (args[1]->IsString()) {  // Path on disk.
        v8::String::Utf8Value filename(args[1]->ToString());

        FREE_IMAGE_FORMAT format = FreeImage_GetFileType(*filename, 0);
        // Some formats don't have a signature so we're supposed to guess from
        // the extension.
        if (format == FIF_UNKNOWN)
          format = FreeImage_GetFIFFromFilename(*filename);

        if (format == FIF_UNKNOWN || !FreeImage_FIFSupportsReading(format))
          return v8_utils::ThrowError("Couldn't detect image type.");

        fbitmap = FreeImage_Load(format, *filename, 0);
        if (!fbitmap)
          return v8_utils::ThrowError("Couldn't load image.");
      } else if (args[1]->IsObject()) {
        v8::Local<v8::Object> data = v8::Local<v8::Object>::Cast(args[1]);
        if (!data->HasIndexedPropertiesInExternalArrayData())
          return v8_utils::ThrowError("Data must be an ExternalArrayData.");
        int element_size = v8_typed_array::SizeOfArrayElementForType(
            data->GetIndexedPropertiesExternalArrayDataType());
        // FreeImage's annoying Windows types...
        DWORD size = data->GetIndexedPropertiesExternalArrayDataLength() *
            element_size;
        BYTE* datadata = reinterpret_cast<BYTE*>(
            data->GetIndexedPropertiesExternalArrayData());

        FIMEMORY* mem = FreeImage_OpenMemory(datadata, size);
        FREE_IMAGE_FORMAT format = FreeImage_GetFileTypeFromMemory(mem, 0);
        if (format == FIF_UNKNOWN || !FreeImage_FIFSupportsReading(format))
          return v8_utils::ThrowError("Couldn't detect image type.");

        fbitmap = FreeImage_LoadFromMemory(format, mem, 0);
        FreeImage_CloseMemory(mem);
        if (!fbitmap)
          return v8_utils::ThrowError("Couldn't load image.");
      } else {
        return v8_utils::ThrowError("SkCanvas image not path or data.");
      }

      if (FreeImage_GetBPP(fbitmap) != 32) {
        FIBITMAP* old_bitmap = fbitmap;
        fbitmap = FreeImage_ConvertTo32Bits(old_bitmap);
        FreeImage_Unload(old_bitmap);
        if (!fbitmap)
          return v8_utils::ThrowError("Couldn't convert image to 32-bit.");
      }

      // Skia works in premultplied alpha, so divide RGB by A.
      // TODO(deanm): Should cache whether it used to have alpha before
      // converting it to 32bpp which now has alpha.
      if (!FreeImage_PreMultiplyWithAlpha(fbitmap))
        return v8_utils::ThrowError("Couldn't premultiply image.");

      tbitmap.setConfig(SkBitmap::kARGB_8888_Config,
                       FreeImage_GetWidth(fbitmap),
                       FreeImage_GetHeight(fbitmap),
                       FreeImage_GetWidth(fbitmap) * 4);
      tbitmap.allocPixels();

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
      tbitmap.setConfig(SkBitmap::kARGB_8888_Config, width, height, width * 4);
      tbitmap.allocPixels();
      tbitmap.eraseARGB(0, 0, 0, 0);
      canvas = new SkCanvas(tbitmap);
    } else if (args.Length() == 1 && NSWindowWrapper::HasInstance(args[0])) {
      bitmap = NSWindowWrapper::ExtractSkBitmapPointer(
          v8::Handle<v8::Object>::Cast(args[0]));
      canvas = new SkCanvas(*bitmap);
    } else if (args.Length() == 1 && SkCanvasWrapper::HasInstance(args[0])) {
      SkCanvas* pcanvas = ExtractPointer(v8::Handle<v8::Object>::Cast(args[0]));
      const SkBitmap& pbitmap = pcanvas->getDevice()->accessBitmap(false);
      tbitmap = pbitmap;
      // Allocate a new block of pixels with a copy from pbitmap.
      pbitmap.copyTo(&tbitmap, pbitmap.config(), NULL);

      canvas = new SkCanvas(tbitmap);
    } else {
      return v8_utils::ThrowError("Improper SkCanvas constructor arguments.");
    }

    args.This()->SetPointerInInternalField(0, canvas);
    // Direct pixel access via array[] indexing.
    args.This()->SetIndexedPropertiesToPixelData(
        reinterpret_cast<uint8_t*>(bitmap->getPixels()), bitmap->getSize());
    args.This()->Set(v8::String::New("width"),
                     v8::Integer::NewFromUnsigned(bitmap->width()));
    args.This()->Set(v8::String::New("height"),
                     v8::Integer::NewFromUnsigned(bitmap->height()));

    return v8::Undefined();
  }

  static v8::Handle<v8::Value> resetMatrix(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    canvas->resetMatrix();
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> clipRect(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?

    SkRect rect = { SkDoubleToScalar(args[0]->NumberValue()),
                    SkDoubleToScalar(args[1]->NumberValue()),
                    SkDoubleToScalar(args[2]->NumberValue()),
                    SkDoubleToScalar(args[3]->NumberValue()) };
    canvas->clipRect(rect);
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> clipPath(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?

    if (!SkPathWrapper::HasInstance(args[0]))
      return v8::Undefined();

    SkPath* path = SkPathWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    canvas->clipPath(*path);  // TODO(deanm): Handle the optional argument.
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> drawCircle(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(args[0]))
      return v8::Undefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    canvas->drawCircle(SkDoubleToScalar(args[1]->NumberValue()),
                       SkDoubleToScalar(args[2]->NumberValue()),
                       SkDoubleToScalar(args[3]->NumberValue()),
                       *paint);
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> drawLine(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(args[0]))
      return v8::Undefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    canvas->drawLine(SkDoubleToScalar(args[1]->NumberValue()),
                     SkDoubleToScalar(args[2]->NumberValue()),
                     SkDoubleToScalar(args[3]->NumberValue()),
                     SkDoubleToScalar(args[4]->NumberValue()),
                     *paint);
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> drawPaint(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(args[0]))
      return v8::Undefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    canvas->drawPaint(*paint);
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> drawCanvas(const v8::Arguments& args) {
    if (args.Length() < 6)
      return v8_utils::ThrowError("Wrong number of arguments.");

    if (!SkCanvasWrapper::HasInstance(args[1]))
      return v8_utils::ThrowError("Bad arguments.");

    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    SkPaint* paint = NULL;
    if (SkPaintWrapper::HasInstance(args[0])) {
      paint = SkPaintWrapper::ExtractPointer(
          v8::Handle<v8::Object>::Cast(args[0]));
    }

    SkCanvas* src_canvas = SkCanvasWrapper::ExtractPointer(
          v8::Handle<v8::Object>::Cast(args[1]));
    SkDevice* src_device = src_canvas->getDevice();

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
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> drawColor(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?

    int r = Clamp(v8_utils::ToInt32WithDefault(args[0], 0), 0, 255);
    int g = Clamp(v8_utils::ToInt32WithDefault(args[1], 0), 0, 255);
    int b = Clamp(v8_utils::ToInt32WithDefault(args[2], 0), 0, 255);
    int a = Clamp(v8_utils::ToInt32WithDefault(args[3], 255), 0, 255);
    int m = v8_utils::ToInt32WithDefault(args[4], SkXfermode::kSrcOver_Mode);

    canvas->drawARGB(a, r, g, b, static_cast<SkXfermode::Mode>(m));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> eraseColor(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?

    int r = Clamp(v8_utils::ToInt32WithDefault(args[0], 0), 0, 255);
    int g = Clamp(v8_utils::ToInt32WithDefault(args[1], 0), 0, 255);
    int b = Clamp(v8_utils::ToInt32WithDefault(args[2], 0), 0, 255);
    int a = Clamp(v8_utils::ToInt32WithDefault(args[3], 255), 0, 255);

    canvas->getDevice()->eraseColor(SkColorSetARGB(a, r, g, b));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> drawPath(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(args[0]))
      return v8::Undefined();

    if (!SkPathWrapper::HasInstance(args[1]))
      return v8::Undefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    SkPath* path = SkPathWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[1]));

    canvas->drawPath(*path, *paint);
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> drawPoints(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(args[0]))
      return v8::Undefined();

    if (!args[2]->IsArray())
      return v8::Undefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    v8::Handle<v8::Array> data = v8::Handle<v8::Array>::Cast(args[2]);
    uint32_t data_len = data->Length();
    uint32_t points_len = data_len / 2;

    SkPoint* points = new SkPoint[points_len];

    for (uint32_t i = 0; i < points_len; ++i) {
      double x = data->Get(v8::Integer::New(i * 2))->NumberValue();
      double y = data->Get(v8::Integer::New(i * 2 + 1))->NumberValue();
      points[i].set(SkDoubleToScalar(x), SkDoubleToScalar(y));
    }

    canvas->drawPoints(
        static_cast<SkCanvas::PointMode>(v8_utils::ToInt32(args[1])),
        points_len, points, *paint);

    delete[] points;

    return v8::Undefined();
  }

  static v8::Handle<v8::Value> drawRect(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(args[0]))
      return v8::Undefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    SkRect rect = { SkDoubleToScalar(args[1]->NumberValue()),
                    SkDoubleToScalar(args[2]->NumberValue()),
                    SkDoubleToScalar(args[3]->NumberValue()),
                    SkDoubleToScalar(args[4]->NumberValue()) };
    canvas->drawRect(rect, *paint);
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> drawRoundRect(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(args[0]))
      return v8::Undefined();

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
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> drawText(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(args[0]))
      return v8::Undefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    v8::String::Utf8Value utf8(args[1]->ToString());
    canvas->drawText(*utf8, utf8.length(),
                     SkDoubleToScalar(args[2]->NumberValue()),
                     SkDoubleToScalar(args[3]->NumberValue()),
                     *paint);
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> drawTextOnPathHV(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    // TODO(deanm): Should we use the Signature to enforce this instead?
    if (!SkPaintWrapper::HasInstance(args[0]))
      return v8::Undefined();

    if (!SkPathWrapper::HasInstance(args[1]))
      return v8::Undefined();

    SkPaint* paint = SkPaintWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[0]));

    SkPath* path = SkPathWrapper::ExtractPointer(
        v8::Handle<v8::Object>::Cast(args[1]));

    v8::String::Utf8Value utf8(args[2]->ToString());
    canvas->drawTextOnPathHV(*utf8, utf8.length(), *path,
                             SkDoubleToScalar(args[3]->NumberValue()),
                             SkDoubleToScalar(args[4]->NumberValue()),
                             *paint);
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> translate(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    canvas->translate(SkDoubleToScalar(args[0]->NumberValue()),
                      SkDoubleToScalar(args[1]->NumberValue()));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> scale(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    canvas->scale(SkDoubleToScalar(args[0]->NumberValue()),
                  SkDoubleToScalar(args[1]->NumberValue()));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> rotate(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    canvas->rotate(SkDoubleToScalar(args[0]->NumberValue()));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> skew(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    canvas->skew(SkDoubleToScalar(args[0]->NumberValue()),
                 SkDoubleToScalar(args[1]->NumberValue()));
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> save(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    canvas->save();
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> restore(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    canvas->restore();
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> writeImage(const v8::Arguments& args) {
    const uint32_t rmask = SK_R32_MASK << SK_R32_SHIFT;
    const uint32_t gmask = SK_G32_MASK << SK_G32_SHIFT;
    const uint32_t bmask = SK_B32_MASK << SK_B32_SHIFT;

    if (args.Length() < 2)
      return v8_utils::ThrowError("Wrong number of arguments.");

    SkCanvas* canvas = ExtractPointer(args.This());
    const SkBitmap& bitmap = canvas->getDevice()->accessBitmap(false);

    v8::String::Utf8Value type(args[0]->ToString());
    if (strcmp(*type, "png") != 0)
      return v8_utils::ThrowError("writeImage can only write PNG types.");

    v8::String::Utf8Value filename(args[1]->ToString());

    FIBITMAP* fb = FreeImage_ConvertFromRawBits(
        reinterpret_cast<BYTE*>(bitmap.getPixels()),
        bitmap.width(), bitmap.height(), bitmap.rowBytes(), 32,
        rmask, gmask, bmask, TRUE);

    if (!fb)
      return v8_utils::ThrowError("Couldn't allocate output FreeImage bitmap.");

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
      if (opts->Has(v8::String::New("dotsPerMeterX"))) {
        FreeImage_SetDotsPerMeterX(fb,
            opts->Get(v8::String::New("dotsPerMeterX"))->Uint32Value());
      }
      if (opts->Has(v8::String::New("dotsPerMeterY"))) {
        FreeImage_SetDotsPerMeterY(fb,
            opts->Get(v8::String::New("dotsPerMeterY"))->Uint32Value());
      }
    }

    bool saved = FreeImage_Save(FIF_PNG, fb, *filename, 0);
    FreeImage_Unload(fb);

    if (!saved)
      return v8_utils::ThrowError("Failed to save png.");

    return v8::Undefined();
  }

  // Delete the backing SkCanvas object.  Skia reference counting should handle
  // cleaning up deeper resources (for example the backing pixels).
  // Calling functions on the SkCanvas object after dispose() will currently
  // lead to a NULL pointer crash.
  static v8::Handle<v8::Value> dispose(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?
    delete canvas;
    args.This()->SetPointerInInternalField(0, NULL);
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> writePDF(const v8::Arguments& args) {
    SkCanvas* canvas = ExtractPointer(args.This());  // TODO should be holder?

    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    v8::String::Utf8Value filename(args[0]->ToString());

    SkFILEWStream stream(*filename);
    SkPDFDocument document;
    // You shouldn't be calling this with an SkDevice (bitmap) backed SkCanvas.
    document.appendPage(reinterpret_cast<SkPDFDevice*>(canvas->getDevice()));

    if (!document.emitPDF(&stream))
      return v8_utils::ThrowError("Error writing PDF.");

    return v8::Undefined();
  }
};

class NSSoundWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&NSSoundWrapper::V8New));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(1);

    v8::Local<v8::Signature> default_signature = v8::Signature::New(ft_cache);

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
      ft_cache->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
      instance->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::New(methods[i].name),
                    v8::FunctionTemplate::New(methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    return ft_cache;
  }

  static NSSound* ExtractNSSoundPointer(v8::Handle<v8::Object> obj) {
    return v8_utils::UnwrapCPointer<NSSound>(obj->GetInternalField(0));
  }

  static bool HasInstance(v8::Handle<v8::Value> value) {
    return GetTemplate()->HasInstance(value);
  }

 private:
  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    v8::String::Utf8Value filename(args[0]->ToString());
    NSSound* sound = [[NSSound alloc] initWithContentsOfFile:
        [NSString stringWithUTF8String:*filename] byReference:YES];

    args.This()->SetInternalField(0, v8_utils::WrapCPointer(sound));
    return args.This();
  }

  static v8::Handle<v8::Value> isPlaying(const v8::Arguments& args) {
    NSSound* sound = ExtractNSSoundPointer(args.This());
    return v8::Boolean::New([sound isPlaying]);
  }

  static v8::Handle<v8::Value> pause(const v8::Arguments& args) {
    NSSound* sound = ExtractNSSoundPointer(args.This());
    return v8::Boolean::New([sound pause]);
  }

  static v8::Handle<v8::Value> play(const v8::Arguments& args) {
    NSSound* sound = ExtractNSSoundPointer(args.This());
    return v8::Boolean::New([sound play]);
  }

  static v8::Handle<v8::Value> resume(const v8::Arguments& args) {
    NSSound* sound = ExtractNSSoundPointer(args.This());
    return v8::Boolean::New([sound resume]);
  }

  static v8::Handle<v8::Value> stop(const v8::Arguments& args) {
    NSSound* sound = ExtractNSSoundPointer(args.This());
    return v8::Boolean::New([sound stop]);
  }

  static v8::Handle<v8::Value> volume(const v8::Arguments& args) {
    NSSound* sound = ExtractNSSoundPointer(args.This());
    return v8::Number::New([sound volume]);
  }

  static v8::Handle<v8::Value> setVolume(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    NSSound* sound = ExtractNSSoundPointer(args.This());
    [sound setVolume:args[0]->NumberValue()];
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> currentTime(const v8::Arguments& args) {
    NSSound* sound = ExtractNSSoundPointer(args.This());
    return v8::Number::New([sound currentTime]);
  }

  static v8::Handle<v8::Value> setCurrentTime(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    NSSound* sound = ExtractNSSoundPointer(args.This());
    [sound setCurrentTime:args[0]->NumberValue()];
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> loops(const v8::Arguments& args) {
    NSSound* sound = ExtractNSSoundPointer(args.This());
    return v8::Boolean::New([sound loops]);
  }

  static v8::Handle<v8::Value> setLoops(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    NSSound* sound = ExtractNSSoundPointer(args.This());
    [sound setLoops:args[0]->BooleanValue()];
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> duration(const v8::Arguments& args) {
    NSSound* sound = ExtractNSSoundPointer(args.This());
    return v8::Number::New([sound duration]);
  }
};

v8::Handle<v8::Value> NSOpenGLContextWrapper::texImage2DSkCanvasB(
    const v8::Arguments& args) {
  if (args.Length() != 3)
    return v8_utils::ThrowError("Wrong number of arguments.");

  if (!args[2]->IsObject() && !SkCanvasWrapper::HasInstance(args[2]))
    return v8_utils::ThrowError("Expected image to be an SkCanvas instance.");

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
  return v8::Undefined();
}

v8::Handle<v8::Value> NSOpenGLContextWrapper::drawSkCanvas(
    const v8::Arguments& args) {
  if (args.Length() != 1)
    return v8_utils::ThrowError("Wrong number of arguments.");

  if (!args[0]->IsObject() && !SkCanvasWrapper::HasInstance(args[0]))
    return v8_utils::ThrowError("Expected image to be an SkCanvas instance.");

  SkCanvas* canvas = SkCanvasWrapper::ExtractPointer(
      v8::Handle<v8::Object>::Cast(args[0]));
  const SkBitmap& bitmap = canvas->getDevice()->accessBitmap(false);
  glDrawPixels(bitmap.width(),
               bitmap.height(),
               GL_BGRA,  // We have to swizzle, so this technically isn't ES.
               GL_UNSIGNED_INT_8_8_8_8_REV,
               bitmap.getPixels());
  return v8::Undefined();
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

  MIDIEntityRef entity = NULL;
  MIDIEndpointGetEntity( endpoint, &entity );
  if ( entity == NULL )
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
  MIDIDeviceRef device = NULL;
  MIDIEntityGetDevice( entity, &device );
  if ( device == NULL )
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
  if ( connections != NULL ) {
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

  // Here, either the endpoint had no connections, or we failed to obtain names
  return EndpointName( endpoint, false );
}


class CAMIDISourceWrapper {
 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&CAMIDISourceWrapper::V8New));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(2);  // MIDIEndpointRef and MIDIPortRef.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(ft_cache);

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
      instance->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::New(methods[i].name),
                    v8::FunctionTemplate::New(methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    return ft_cache;
  }

  static MIDIEndpointRef ExtractEndpoint(v8::Handle<v8::Object> obj) {
    // NOTE(deanm): MIDIEndpointRef (MIDIObjectRef) is UInt32 on 64-bit.
    return (MIDIEndpointRef)(intptr_t)obj->GetPointerFromInternalField(0);
  }

  static MIDIPortRef ExtractPort(v8::Handle<v8::Object> obj) {
    return (MIDIPortRef)(intptr_t)obj->GetPointerFromInternalField(1);
  }

  static bool HasInstance(v8::Handle<v8::Value> value) {
    return GetTemplate()->HasInstance(value);
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

  static v8::Handle<v8::Value> sendData(const v8::Arguments& args) {
    if (!args[0]->IsArray())
      return v8::Undefined();

    MIDIEndpointRef endpoint = ExtractEndpoint(args.This());

    if (!endpoint) {
      return v8_utils::ThrowError("Can't send on midi without an endpoint.");
    }

    MIDIPortRef port = ExtractPort(args.This());
    MIDITimeStamp timestamp = AudioGetCurrentHostTime();
    ByteCount pl_count;
    MIDIPacketList* pl = AllocateMIDIPacketList(1, &pl_count);
    MIDIPacket* cur_packet = MIDIPacketListInit(pl);

    v8::Handle<v8::Array> data = v8::Handle<v8::Array>::Cast(args[0]);
    uint32_t data_len = data->Length();

    Byte* data_buf = new Byte[data_len];

    for (uint32_t i = 0; i < data_len; ++i) {
      // Convert to an integer and truncate to 8 bits.
      data_buf[i] = data->Get(v8::Integer::New(i))->Uint32Value();
    }

    cur_packet = MIDIPacketListAdd(pl, pl_count, cur_packet,
                                   timestamp, data_len, data_buf);
    // Depending whether we are virtual we need to send differently.
    OSStatus result = port ? MIDISend(port, endpoint, pl) :
                             MIDIReceived(endpoint, pl);
    delete[] data_buf;
    FreeMIDIPacketList(pl);

    if (result != noErr) {
      return v8_utils::ThrowError("Couldn't send midi data.");
    }

    return v8::Undefined();
  }

  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    OSStatus result;

    if (!g_midi_client) {
      result = MIDIClientCreate(CFSTR("Plask"), NULL, NULL, &g_midi_client);
      if (result != noErr) {
        return v8_utils::ThrowError("Couldn't create midi client object.");
      }
    }

    args.This()->SetPointerInInternalField(0, NULL);
    args.This()->SetPointerInInternalField(1, NULL);
    return args.This();
  }

  static v8::Handle<v8::Value> createVirtual(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    OSStatus result;

    v8::String::Utf8Value name_val(args[0]->ToString());
    CFStringRef name =
        CFStringCreateWithCString(NULL, *name_val, kCFStringEncodingUTF8);

    MIDIEndpointRef endpoint;
    result = MIDISourceCreate(g_midi_client, name, &endpoint);
    CFRelease(name);
    if (result != noErr) {
      return v8_utils::ThrowError("Couldn't create midi source object.");
    }

    // NOTE(deanm): MIDIEndpointRef (MIDIObjectRef) is UInt32 on 64-bit.
    args.This()->SetPointerInInternalField(0, (void*)(intptr_t)endpoint);
    args.This()->SetPointerInInternalField(1, NULL);
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> openDestination(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    OSStatus result;

    ItemCount num_destinations = MIDIGetNumberOfDestinations();
    ItemCount index = args[0]->Uint32Value();
    if (index >= num_destinations)
      return v8_utils::ThrowError("Invalid MIDI destination index.");

    MIDIEndpointRef destination = MIDIGetDestination(index);

    MIDIPortRef port;
    result = MIDIOutputPortCreate(
        g_midi_client, CFSTR("Plask"), &port);
    if (result != noErr)
      return v8_utils::ThrowError("Couldn't create midi output port.");

    args.This()->SetPointerInInternalField(0, (void*)(intptr_t)destination);
    args.This()->SetPointerInInternalField(1, (void*)(intptr_t)port);

    return v8::Undefined();
    return v8::Undefined();
  }

  // NOTE(deanm): See API notes about sources(), same comments apply here.
  static v8::Handle<v8::Value> destinations(const v8::Arguments& args) {
    ItemCount num_destinations = MIDIGetNumberOfDestinations();
    v8::Local<v8::Array> arr = v8::Array::New(num_destinations);
    for (ItemCount i = 0; i < num_destinations; ++i) {
      MIDIEndpointRef point = MIDIGetDestination(i);
      CFStringRef name = ConnectedEndpointName(point);
      arr->Set(i, v8::String::New([(NSString*)name UTF8String]));
      CFRelease(name);
    }
    return arr;
  }

};

class CAMIDIDestinationWrapper {
 private:
  struct State {
    MIDIEndpointRef endpoint;
    int64_t clocks;
    int dgram_fd;
    struct sockaddr_un dgram_un;
    size_t dgram_un_len;
  };

 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&CAMIDIDestinationWrapper::V8New));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // MIDIEndpointRef.

    v8::Local<v8::Signature> default_signature = v8::Signature::New(ft_cache);

    // Configure the template...
    static BatchedConstants constants[] = {
      { "kDummy", 1 },
    };

    static BatchedMethods methods[] = {
      { "createVirtual", &CAMIDIDestinationWrapper::createVirtual },
      { "sources", &CAMIDIDestinationWrapper::sources },
      { "openSource", &CAMIDIDestinationWrapper::openSource },
      { "syncClocks", &CAMIDIDestinationWrapper::syncClocks },
      { "setDgramPath", &CAMIDIDestinationWrapper::setDgramPath },
    };

    for (size_t i = 0; i < arraysize(constants); ++i) {
      instance->Set(v8::String::New(constants[i].name),
                    v8::Uint32::New(constants[i].val), v8::ReadOnly);
    }

    for (size_t i = 0; i < arraysize(methods); ++i) {
      instance->Set(v8::String::New(methods[i].name),
                    v8::FunctionTemplate::New(methods[i].func,
                                              v8::Handle<v8::Value>(),
                                              default_signature));
    }

    return ft_cache;
  }

  // Can't use v8_utils::UnrwapCPointer because of LSB clear expectations.
  static State* ExtractPointer(v8::Handle<v8::Object> obj) {
    return v8_utils::UnwrapCPointer<State>(obj->GetInternalField(0));
  }

  static bool HasInstance(v8::Handle<v8::Value> value) {
    return GetTemplate()->HasInstance(value);
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
      } else if (state->dgram_fd != -1) {
        int res = sendto(state->dgram_fd, packet->data, packet->length, 0,
                         (sockaddr*)&state->dgram_un, state->dgram_un_len);
        if (res != packet->length) {
          printf("Error sending midi -> dgram (%d)\n", res);
        }
      }
      packet = MIDIPacketNext(packet);
    }
  }

  static v8::Handle<v8::Value> syncClocks(const v8::Arguments& args) {
    State* state = ExtractPointer(args.This());
    return v8::Integer::New(state->clocks);
  }

  static v8::Handle<v8::Value> setDgramPath(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    State* state = ExtractPointer(args.This());
    v8::String::Utf8Value path(args[0]->ToString());
    memset(&state->dgram_un, 0, sizeof(state->dgram_un));
    state->dgram_un.sun_family = AF_UNIX;
    memcpy(state->dgram_un.sun_path, *path, path.length());
    state->dgram_un_len = sizeof(state->dgram_un) -
                          sizeof(state->dgram_un.sun_path) +
                          path.length() + 1;
    state->dgram_fd = socket(AF_UNIX, SOCK_DGRAM, 0);
    return v8::Undefined();
  }

  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    OSStatus result;

    if (!g_midi_client) {
      result = MIDIClientCreate(CFSTR("Plask"), NULL, NULL, &g_midi_client);
      if (result != noErr) {
        return v8_utils::ThrowError("Couldn't create midi client object.");
      }
    }

    State* state = new State;
    state->dgram_fd = -1;
    state->endpoint = NULL;
    state->clocks = 0;
    args.This()->SetInternalField(0, v8::External::Wrap(state));
    return args.This();
  }


  static v8::Handle<v8::Value> createVirtual(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    OSStatus result;
    v8::String::Utf8Value name_val(args[0]->ToString());
    CFStringRef name =
        CFStringCreateWithCString(NULL, *name_val, kCFStringEncodingUTF8);

    State* state = ExtractPointer(args.This());

    MIDIEndpointRef endpoint;
    result = MIDIDestinationCreate(
        g_midi_client, name, &ReadCallback, state, &endpoint);
    CFRelease(name);
    if (result != noErr)
      return v8_utils::ThrowError("Couldn't create midi source object.");

    state->endpoint = endpoint;
    return v8::Undefined();
  }

  // NOTE(deanm): Could make sense for the API to be numSources() and then
  // you query for sourceName(index), but really, do you ever want the index
  // without the name?  This could be a little extra work if you don't, but
  // really it seems to make sense in most of the use cases.
  static v8::Handle<v8::Value> sources(const v8::Arguments& args) {
    ItemCount num_sources = MIDIGetNumberOfSources();
    v8::Local<v8::Array> arr = v8::Array::New(num_sources);
    for (ItemCount i = 0; i < num_sources; ++i) {
      MIDIEndpointRef point = MIDIGetSource(i);
      CFStringRef name = ConnectedEndpointName(point);
      arr->Set(i, v8::String::New([(NSString*)name UTF8String]));
      CFRelease(name);
    }
    return arr;
  }

  static v8::Handle<v8::Value> openSource(const v8::Arguments& args) {
    if (args.Length() != 1)
      return v8_utils::ThrowError("Wrong number of arguments.");

    OSStatus result;
    State* state = ExtractPointer(args.This());

    ItemCount num_sources = MIDIGetNumberOfSources();
    ItemCount index = args[0]->Uint32Value();
    if (index >= num_sources)
      return v8_utils::ThrowError("Invalid MIDI source index.");

    MIDIEndpointRef source = MIDIGetSource(index);

    MIDIPortRef port;
    result = MIDIInputPortCreate(
        g_midi_client, CFSTR("Plask"), &ReadCallback, state, &port);
    if (result != noErr)
      return v8_utils::ThrowError("Couldn't create midi source object.");

    result = MIDIPortConnectSource(port, source, NULL);
    if (result != noErr)
      return v8_utils::ThrowError("Couldn't create midi source object.");

    state->endpoint = source;

    return v8::Undefined();
  }
};

}  // namespace

@implementation WrappedNSWindow

-(void)setEventCallbackWithHandle:(v8::Handle<v8::Function>)func {
  event_callback_ = v8::Persistent<v8::Function>::New(func);
}

-(void)processEvent:(NSEvent *)event {
  if (*event_callback_) {
    [event retain];  // TODO(deanm): Release this someday.
    v8::Local<v8::Object> res =
        NSEventWrapper::GetTemplate()->InstanceTemplate()->NewInstance();
    res->SetInternalField(0, v8_utils::WrapCPointer(event));
    v8::Handle<v8::Value> argv[] = { v8::Number::New(0), res };
    v8::TryCatch try_catch;
    event_callback_->Call(v8::Context::GetCurrent()->Global(), 2, argv);
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
  v8::Local<v8::Array> jspaths = v8::Array::New([paths count]);
  for (int i = 0; i < [paths count]; ++i) {
    jspaths->Set(v8::Integer::New(i), v8::String::New(
        [[paths objectAtIndex:i] UTF8String]));
  }

  v8::Local<v8::Object> res = v8::Object::New();
  res->Set(v8::String::New("paths"), jspaths);

  v8::Handle<v8::Value> argv[] = { v8::Number::New(1), res };
  v8::TryCatch try_catch;
  event_callback_->Call(v8::Context::GetCurrent()->Global(), 2, argv);
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

@implementation BlitImageView

-(id)initWithSkBitmap:(SkBitmap*)bitmap {
  bitmap_ = bitmap;
  [self initWithFrame:NSMakeRect(0.0, 0.0,
                                 bitmap->width(), bitmap->height())];
  return self;
}

// TODO(deanm): There is too much copying going on here.  Can a CGImage back
// directly to my pixels without going through a decoder?
-(void)drawRect:(NSRect)dirty {
  int width = bitmap_->width(), height = bitmap_->height();
  void* pixels = bitmap_->getPixels();

  CFDataRef cfdata = CFDataCreateWithBytesNoCopy(
      NULL, (UInt8*)pixels, width * height * 4, kCFAllocatorNull);
  CGDataProviderRef cgdata_provider = CGDataProviderCreateWithCFData(cfdata);
  //CGDataProviderRef cgdata_provider =
  //    CGDataProviderCreateWithFilename("/tmp/maxmsp.png");
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
  CGImageRef cgimage = CGImageCreate(
      width, height, 8, 32, width * 4, colorspace,
      kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst,
      cgdata_provider, NULL, false, kCGRenderingIntentDefault);
  //CGImageRef cgimage = CGImageCreateWithPNGDataProvider(
  //  cgdata_provider, NULL, false, kCGRenderingIntentDefault);
  CGColorSpaceRelease(colorspace);

  CGRect image_rect = CGRectMake(0.0, 0.0, width, height);
  CGContextRef context =
      (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
  // TODO(deanm): Deal with subimages when dirty rect isn't full frame.
  CGContextDrawImage(context, image_rect, cgimage);

  CGImageRelease(cgimage);
  CGDataProviderRelease(cgdata_provider);
  CFRelease(cfdata);
}

@end

@implementation BlitGLView

-(void)drawRect:(NSRect)dirty {
  //glClearColor(1.0, 0, 0, 1.0);
  //glClear(GL_COLOR_BUFFER_BIT);
  //glFlush();
}

@end

void plask_setup_bindings(v8::Handle<v8::ObjectTemplate> obj) {
  v8::Handle<v8::Object> global(v8::Context::GetCurrent()->Global());

  v8_typed_array::AttachBindings(global);

  obj->Set(v8::String::New("NSWindow"), NSWindowWrapper::GetTemplate());
  obj->Set(v8::String::New("NSEvent"), NSEventWrapper::GetTemplate());
  obj->Set(v8::String::New("SkPath"), SkPathWrapper::GetTemplate());
  obj->Set(v8::String::New("SkPaint"), SkPaintWrapper::GetTemplate());
  obj->Set(v8::String::New("SkCanvas"), SkCanvasWrapper::GetTemplate());
  obj->Set(v8::String::New("NSOpenGLContext"),
           NSOpenGLContextWrapper::GetTemplate());
  obj->Set(v8::String::New("NSSound"), NSSoundWrapper::GetTemplate());
  obj->Set(v8::String::New("CAMIDISource"), CAMIDISourceWrapper::GetTemplate());
  obj->Set(v8::String::New("CAMIDIDestination"),
           CAMIDIDestinationWrapper::GetTemplate());
}
