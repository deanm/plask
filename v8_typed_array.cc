// V8 Typed Array implementation.
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

#include <stdlib.h>  // calloc, etc

#include <v8.h>

#include "v8_typed_array.h"

namespace {

v8::Handle<v8::Value> ThrowError(const char* msg) {
  return v8::ThrowException(v8::Exception::Error(v8::String::New(msg)));
}

v8::Handle<v8::Value> ThrowTypeError(const char* msg) {
  return v8::ThrowException(v8::Exception::TypeError(v8::String::New(msg)));
}

struct BatchedMethods {
  const char* name;
  v8::Handle<v8::Value> (*func)(const v8::Arguments& args);
};

class ArrayBuffer {
 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&ArrayBuffer::V8New));
    ft_cache->SetClassName(v8::String::New("ArrayBuffer"));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // Buffer.

    return ft_cache;
  }

  static bool HasInstance(v8::Handle<v8::Value> value) {
    return GetTemplate()->HasInstance(value);
  }

 private:
  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    if (args.Length() != 1)
      return ThrowError("Wrong number of arguments.");

    size_t num_bytes = args[0]->Uint32Value();
    void* buf = calloc(num_bytes, 1);
    if (!buf)
      return ThrowError("Unable to allocate ArrayBuffer.");

    args.This()->SetPointerInInternalField(0, buf);

    args.This()->Set(v8::String::New("byteLength"),
                     v8::Integer::NewFromUnsigned(num_bytes),
                     (v8::PropertyAttribute)(v8::ReadOnly|v8::DontDelete));

    return args.This();
  }
};

template <int TBytes, v8::ExternalArrayType TEAType>
class TypedArray {
 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&TypedArray<TBytes, TEAType>::V8New));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(0);

    ft_cache->Set(v8::String::New("BYTES_PER_ELEMENT"),
                  v8::Uint32::New(TBytes), v8::ReadOnly);
    instance->Set(v8::String::New("BYTES_PER_ELEMENT"),
                  v8::Uint32::New(TBytes), v8::ReadOnly);

    return ft_cache;
  }

  static bool HasInstance(v8::Handle<v8::Value> value) {
    return GetTemplate()->HasInstance(value);
  }

 private:
  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    if (args.Length() != 1)
      return ThrowError("Wrong number of arguments.");

    v8::Local<v8::Object> buffer;
    int num_elements = 0;

    if (args[0]->IsObject()) {
      if (!args[0]->IsArray())
        return ThrowError("Sequence must be an Array.");

      v8::Local<v8::Array> arr = v8::Local<v8::Array>::Cast(args[0]);
      uint32_t il = arr->Length();

      // TODO(deanm): Handle integer overflow.
      v8::Handle<v8::Value> argv[1] = {
          v8::Integer::NewFromUnsigned(il * TBytes)};

      buffer = ArrayBuffer::GetTemplate()->
                 GetFunction()->NewInstance(1, argv);
      void* buf = buffer->GetPointerFromInternalField(0);
      num_elements = il;  // TODO(deanm): signedness mismatch.
      args.This()->SetIndexedPropertiesToExternalArrayData(
          buf, TEAType, num_elements);
      // TODO(deanm): check for failure.
      for (uint32_t i = 0; i < il; ++i) {
        // Use the v8 setter to deal with typing.  Maybe slow?
        args.This()->Set(i, arr->Get(i));
      }
    } else {
      num_elements = args[0]->Uint32Value();
      // TODO(deanm): Handle integer overflow.
      v8::Handle<v8::Value> argv[1] = {
          v8::Integer::NewFromUnsigned(num_elements * TBytes)};

      buffer = ArrayBuffer::GetTemplate()->
                 GetFunction()->NewInstance(1, argv);
      void* buf = buffer->GetPointerFromInternalField(0);

      args.This()->SetIndexedPropertiesToExternalArrayData(
          buf, TEAType, num_elements);
      // TODO(deanm): check for failure.
    }

    args.This()->Set(v8::String::New("buffer"),
                     buffer,
                     (v8::PropertyAttribute)(v8::ReadOnly|v8::DontDelete));
    args.This()->Set(v8::String::New("length"),
                     v8::Integer::New(num_elements),
                     (v8::PropertyAttribute)(v8::ReadOnly|v8::DontDelete));
    args.This()->Set(v8::String::New("byteOffset"),
                     v8::Integer::New(0),
                     (v8::PropertyAttribute)(v8::ReadOnly|v8::DontDelete));
    args.This()->Set(v8::String::New("byteLength"),
                     v8::Integer::NewFromUnsigned(num_elements * TBytes),
                     (v8::PropertyAttribute)(v8::ReadOnly|v8::DontDelete));

    return args.This();
  }
};

class Int8Array : public TypedArray<1, v8::kExternalByteArray> { };
class Uint8Array : public TypedArray<1, v8::kExternalUnsignedByteArray> { };
class Int16Array : public TypedArray<2, v8::kExternalShortArray> { };
class Uint16Array : public TypedArray<2, v8::kExternalUnsignedShortArray> { };
class Int32Array : public TypedArray<4, v8::kExternalIntArray> { };
class Uint32Array : public TypedArray<4, v8::kExternalUnsignedIntArray> { };
class Float32Array : public TypedArray<4, v8::kExternalFloatArray> { };

template <typename T>
v8::Handle<v8::Value> typedValueFactory(T) {
  return v8::Undefined();
}

template <>
v8::Handle<v8::Value> typedValueFactory(unsigned char val) {
  return v8::Integer::NewFromUnsigned(val);
}

template <>
v8::Handle<v8::Value> typedValueFactory(char val) {
  return v8::Integer::New(val);
}

template <>
v8::Handle<v8::Value> typedValueFactory(unsigned short val) {
  return v8::Integer::NewFromUnsigned(val);
}

template <>
v8::Handle<v8::Value> typedValueFactory(short val) {
  return v8::Integer::New(val);
}

template <>
v8::Handle<v8::Value> typedValueFactory(unsigned int val) {
  return v8::Integer::NewFromUnsigned(val);
}

template <>
v8::Handle<v8::Value> typedValueFactory(int val) {
  return v8::Integer::New(val);
}

template <>
v8::Handle<v8::Value> typedValueFactory(float val) {
  return v8::Number::New(val);
}

template <>
v8::Handle<v8::Value> typedValueFactory(double val) {
  return v8::Number::New(val);
}

class DataView {
 public:
  static v8::Persistent<v8::FunctionTemplate> GetTemplate() {
    static v8::Persistent<v8::FunctionTemplate> ft_cache;
    if (!ft_cache.IsEmpty())
      return ft_cache;

    v8::HandleScope scope;
    ft_cache = v8::Persistent<v8::FunctionTemplate>::New(
        v8::FunctionTemplate::New(&DataView::V8New));
    ft_cache->SetClassName(v8::String::New("DataView"));
    v8::Local<v8::ObjectTemplate> instance = ft_cache->InstanceTemplate();
    instance->SetInternalFieldCount(1);  // ArrayBuffer

    v8::Local<v8::Signature> default_signature = v8::Signature::New(ft_cache);

    static BatchedMethods methods[] = {
      { "getUint8", &DataView::getUint8 },
      { "getInt8", &DataView::getInt8 },
      { "getUint16", &DataView::getUint16 },
      { "getInt16", &DataView::getInt16 },
      { "getUint32", &DataView::getUint32 },
      { "getInt32", &DataView::getInt32 },
      { "getFloat32", &DataView::getFloat32 },
      { "getFloat64", &DataView::getFloat64 },
    };

    for (size_t i = 0; i < sizeof(methods) / sizeof(*methods); ++i) {
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

 private:
  static v8::Handle<v8::Value> V8New(const v8::Arguments& args) {
    if (args.Length() != 1)
      return ThrowError("Wrong number of arguments.");

    if (!args[0]->IsObject())
      return ThrowError("Object must be an ArrayBuffer.");

    v8::Handle<v8::Object> obj = v8::Handle<v8::Object>::Cast(args[0]);
    if (!obj->HasIndexedPropertiesInExternalArrayData())
      return ThrowError("Object must be an ArrayBuffer.");

    args.This()->SetInternalField(0, obj);
    return args.This();
  }

  template <typename T>
  static T getValue(void* ptr, int index) {
    // I don't know which standards I violate more, C++ or my own.
    return *reinterpret_cast<T*>(reinterpret_cast<char*>(ptr) + index);
  }

  template <typename T>
  static v8::Handle<v8::Value> getGeneric(const v8::Arguments& args) {
    if (args.Length() != 1)
      return ThrowError("Wrong number of arguments.");

    int index = args[0]->Int32Value();
    v8::Handle<v8::Object> obj = v8::Handle<v8::Object>::Cast(
        args.This()->GetInternalField(0));
    // TODO(deanm): All of these things should be cacheable.
    int element_size = v8_typed_array::SizeOfArrayElementForType(
        obj->GetIndexedPropertiesExternalArrayDataType());
    int size =
        obj->GetIndexedPropertiesExternalArrayDataLength() * element_size;

    if (index < 0 || index + sizeof(T) > size)
      return ThrowError("Index out of range.");

    void* ptr = obj->GetIndexedPropertiesExternalArrayData();
    return typedValueFactory<T>(getValue<T>(ptr, index));
  }

  static v8::Handle<v8::Value> getUint8(const v8::Arguments& args) {
    return getGeneric<unsigned char>(args);
  }

  static v8::Handle<v8::Value> getInt8(const v8::Arguments& args) {
    return getGeneric<char>(args);
  }

  static v8::Handle<v8::Value> getUint16(const v8::Arguments& args) {
    return getGeneric<unsigned short>(args);
  }

  static v8::Handle<v8::Value> getInt16(const v8::Arguments& args) {
    return getGeneric<short>(args);
  }

  static v8::Handle<v8::Value> getUint32(const v8::Arguments& args) {
    return getGeneric<unsigned int>(args);
  }

  static v8::Handle<v8::Value> getInt32(const v8::Arguments& args) {
    return getGeneric<int>(args);
  }

  static v8::Handle<v8::Value> getFloat32(const v8::Arguments& args) {
    return getGeneric<float>(args);
  }

  static v8::Handle<v8::Value> getFloat64(const v8::Arguments& args) {
    return getGeneric<double>(args);
  }
};


}  // namespace

namespace v8_typed_array {

void AttachBindings(v8::Handle<v8::Object> obj) {
  obj->Set(v8::String::New("ArrayBuffer"),
           ArrayBuffer::GetTemplate()->GetFunction());
  obj->Set(v8::String::New("Int8Array"),
           Int8Array::GetTemplate()->GetFunction());
  obj->Set(v8::String::New("Uint8Array"),
           Uint8Array::GetTemplate()->GetFunction());
  obj->Set(v8::String::New("Int16Array"),
           Int16Array::GetTemplate()->GetFunction());
  obj->Set(v8::String::New("Uint16Array"),
           Uint16Array::GetTemplate()->GetFunction());
  obj->Set(v8::String::New("Int32Array"),
           Int32Array::GetTemplate()->GetFunction());
  obj->Set(v8::String::New("Uint32Array"),
           Uint32Array::GetTemplate()->GetFunction());
  obj->Set(v8::String::New("Float32Array"),
           Float32Array::GetTemplate()->GetFunction());
  obj->Set(v8::String::New("DataView"),
           DataView::GetTemplate()->GetFunction());
}

int SizeOfArrayElementForType(v8::ExternalArrayType type) {
  switch (type) {
    case v8::kExternalByteArray:
    case v8::kExternalUnsignedByteArray:
      return 1;
    case v8::kExternalShortArray:
    case v8::kExternalUnsignedShortArray:
      return 2;
    case v8::kExternalIntArray:
    case v8::kExternalUnsignedIntArray:
    case v8::kExternalFloatArray:
      return 4;
    default:
      return 0;
  }
}

}  // namespace v8_typed_array
