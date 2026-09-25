// :emucore -- libemucore.so (emu/native: the DS and Virtual Console cores)
// for the HOME menu, which loads it with LuaJIT's FFI (fold3ds/emu.lua).
// build.sh copies this file into Azahar's Gradle project and fills in the
// @...@ paths.
plugins {
    id("com.android.library")
}

android {
    namespace = "org.fold3ds.emucore"
    compileSdk = 36
    ndkVersion = "27.3.13750724"

    defaultConfig {
        minSdk = 29
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DMELONDS_DIR=@MELONDS_DIR@",
                    "-DSKYEMU_DIR=@SKYEMU_DIR@",
                    "-DSKYEMU_COMMIT=@SKYEMU_COMMIT@",
                    // its own C++ runtime inside it: nothing to clash with
                    // Azahar's or LÖVE's libc++_shared.so
                    "-DANDROID_STL=c++_static",
                    "-DCMAKE_BUILD_TYPE=Release"
                )
                targets += listOf("emucore")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    externalNativeBuild {
        cmake {
            path = file("@NATIVE_DIR@/CMakeLists.txt")
            version = "3.30.3"
        }
    }
}
