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

#include <v8.h>

namespace v8_utils {

int ToInt32(v8::Handle<v8::Value> value, bool* ok);
int ToInt32(v8::Handle<v8::Value> value);
int ToInt32WithDefault(v8::Handle<v8::Value> value, int def);

const char* ToCString(const v8::String::Utf8Value& value);

void ReportException(v8::TryCatch* try_catch);
v8::Handle<v8::Value> Print(const v8::Arguments& args);
v8::Handle<v8::String> ReadFile(const char* name);
bool ExecuteString(v8::Handle<v8::String> source,
                   v8::Handle<v8::Value> name,
                   bool print_result,
                   bool report_exceptions);
v8::Handle<v8::Value> Print(const v8::Arguments& args);
int RunScript(const char* str);
v8::Handle<v8::Value> Load(const v8::Arguments& args);

v8::Handle<v8::Value> ThrowError(const char* msg);
v8::Handle<v8::Value> ThrowTypeError(const char* msg);

// Create a V8 wrapper for a C pointer
v8::Handle<v8::Value> WrapCPointer(void* cptr);

void* UnwrapCPointerRaw(v8::Handle<v8::Value> obj);

template <typename T>
T* UnwrapCPointer(v8::Handle<v8::Value> obj) {
  return reinterpret_cast<T*>(UnwrapCPointerRaw(obj));
}

}  // namespace v8_utils
