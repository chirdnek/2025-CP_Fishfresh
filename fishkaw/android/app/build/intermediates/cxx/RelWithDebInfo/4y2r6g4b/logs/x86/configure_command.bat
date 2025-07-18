@echo off
"C:\\Users\\Acer Lite\\AppData\\Local\\Android\\Sdk\\cmake\\3.22.1\\bin\\cmake.exe" ^
  "-HC:\\flutter_windows_3.24.2-stable\\flutter\\packages\\flutter_tools\\gradle\\src\\main\\scripts" ^
  "-DCMAKE_SYSTEM_NAME=Android" ^
  "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON" ^
  "-DCMAKE_SYSTEM_VERSION=21" ^
  "-DANDROID_PLATFORM=android-21" ^
  "-DANDROID_ABI=x86" ^
  "-DCMAKE_ANDROID_ARCH_ABI=x86" ^
  "-DANDROID_NDK=C:\\Users\\Acer Lite\\AppData\\Local\\Android\\Sdk\\ndk\\27.0.12077973" ^
  "-DCMAKE_ANDROID_NDK=C:\\Users\\Acer Lite\\AppData\\Local\\Android\\Sdk\\ndk\\27.0.12077973" ^
  "-DCMAKE_TOOLCHAIN_FILE=C:\\Users\\Acer Lite\\AppData\\Local\\Android\\Sdk\\ndk\\27.0.12077973\\build\\cmake\\android.toolchain.cmake" ^
  "-DCMAKE_MAKE_PROGRAM=C:\\Users\\Acer Lite\\AppData\\Local\\Android\\Sdk\\cmake\\3.22.1\\bin\\ninja.exe" ^
  "-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=C:\\fishfresh\\fishkaw\\android\\app\\build\\intermediates\\cxx\\RelWithDebInfo\\4y2r6g4b\\obj\\x86" ^
  "-DCMAKE_RUNTIME_OUTPUT_DIRECTORY=C:\\fishfresh\\fishkaw\\android\\app\\build\\intermediates\\cxx\\RelWithDebInfo\\4y2r6g4b\\obj\\x86" ^
  "-DCMAKE_BUILD_TYPE=RelWithDebInfo" ^
  "-BC:\\fishfresh\\fishkaw\\android\\app\\.cxx\\RelWithDebInfo\\4y2r6g4b\\x86" ^
  -GNinja ^
  -Wno-dev ^
  --no-warn-unused-cli
