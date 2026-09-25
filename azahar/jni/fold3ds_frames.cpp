// fold3ds: the address of a direct ByteBuffer, so the 3DS shell (LuaJIT's
// FFI) can read Azahar's frames in place (Fold3dsShell.kt).
#include <jni.h>
#include <cstdint>

extern "C" JNIEXPORT jlong JNICALL
Java_org_citra_citra_1emu_fold3ds_Fold3dsShell_addressOf(JNIEnv* env, jclass, jobject buffer) {
    return static_cast<jlong>(reinterpret_cast<std::intptr_t>(env->GetDirectBufferAddress(buffer)));
}
