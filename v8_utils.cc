#include "v8_utils.h"

#include <math.h>

#include <v8.h>

namespace v8_utils {

// Taken from the Chromium V8 bindings.
int ToInt32(v8::Handle<v8::Value> value, bool* ok) {
  *ok = true;

  // Fast case.  The value is already a 32-bit integer.
  if (value->IsInt32()) {
    return value->Int32Value();
  }

  // Can the value be converted to a number?
  v8::Local<v8::Number> number_object = value->ToNumber();
  if (number_object.IsEmpty()) {
    *ok = false;
    return 0;
  }

  // Does the value convert to nan or to an infinity?
  double number_value = number_object->Value();
  if (isnan(number_value) || isinf(number_value)) {
    *ok = false;
    return 0;
  }

  // Can the value be converted to a 32-bit integer?
  v8::Local<v8::Int32> int_value = value->ToInt32();
  if (int_value.IsEmpty()) {
    *ok = false;
    return 0;
  }

  // Return the result of the int32 conversion.
  return int_value->Value();
}

int ToInt32(v8::Handle<v8::Value> value) {
  bool ok;
  return ToInt32(value, &ok);
}

int ToInt32WithDefault(v8::Handle<v8::Value> value, int def) {
  bool ok;
  int res = ToInt32(value, &ok);
  return ok ? res : def;
}

v8::Handle<v8::Value> ThrowError(const char* msg) {
  return v8::ThrowException(v8::Exception::Error(v8::String::New(msg)));
}

v8::Handle<v8::Value> ThrowTypeError(const char* msg) {
  return v8::ThrowException(v8::Exception::TypeError(v8::String::New(msg)));
}

v8::Handle<v8::Value> WrapCPointer(void* cptr) {
  return v8::External::Wrap(cptr);
}

void* UnwrapCPointerRaw(v8::Handle<v8::Value> obj) {
  return v8::External::Unwrap(obj);
}

}  // namespace v8_utils
