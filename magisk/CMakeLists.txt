cmake_minimum_required(VERSION 3.18.1)
project("esurfingd" LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

set(PROGRAM_VERSION_MAJOR 2)
set(PROGRAM_VERSION_MINOR 2)
set(PROGRAM_VERSION_PATCH 0)
set(PROGRAM_VERSION_RELEASE 3)
set(PROGRAM_VERSION "..")
set(PROGRAM_FULL_VERSION "-r")

add_definitions(-DPROGRAM_VERSION="")
add_definitions(-DPROGRAM_FULL_VERSION="")

# Source root — relative to this file, pointing to the NDK cpp directory
set(SRC_ROOT "/../android/app/src/main/cpp")

# ============================================================
# 头文件搜索路径
# ============================================================
include_directories(
    
    /include
    /src
    /third_party
)

# ============================================================
# libcurl — 通过 FetchContent 自动拉取源码并静态编译
# ============================================================
include(FetchContent)
set(FETCHCONTENT_QUIET OFF)

FetchContent_Declare(curl
    GIT_REPOSITORY  https://github.com/curl/curl.git
    GIT_TAG         curl-8_9_0
    GIT_SHALLOW     TRUE
    GIT_PROGRESS    TRUE
)

set(BUILD_CURL_EXE        OFF  CACHE BOOL "")
set(BUILD_TESTING         OFF  CACHE BOOL "")
set(BUILD_SHARED_LIBS     OFF  CACHE BOOL "")
set(CURL_STATICLIB        ON   CACHE BOOL "")
set(HTTP_ONLY             ON   CACHE BOOL "")
set(CURL_DISABLE_TLS      ON   CACHE BOOL "")
set(CURL_USE_OPENSSL      OFF  CACHE BOOL "")
set(CURL_USE_SCHANNEL     OFF  CACHE BOOL "")
set(CURL_USE_SECTRANSP    OFF  CACHE BOOL "")
set(CURL_USE_MBEDTLS      OFF  CACHE BOOL "")
set(CURL_USE_BEARSSL      OFF  CACHE BOOL "")
set(CURL_USE_WOLFSSL      OFF  CACHE BOOL "")
set(CURL_USE_LIBSSH2      OFF  CACHE BOOL "")
set(CURL_USE_LIBPSL       OFF  CACHE BOOL "")
set(CURL_USE_LDAP         OFF  CACHE BOOL "")
set(CURL_USE_GSSAPI       OFF  CACHE BOOL "")
set(CMAKE_USE_OPENSSL     OFF  CACHE BOOL "")
set(CMAKE_USE_LIBSSH2     OFF  CACHE BOOL "")
set(ENABLE_CURL_MANUAL    OFF  CACHE BOOL "")
set(CURL_CA_PATH          ""   CACHE STRING "")
set(CURL_CA_BUNDLE        ""   CACHE STRING "")
set(CURL_DISABLE_LDAP     ON   CACHE BOOL "")
set(CURL_DISABLE_LDAPS    ON   CACHE BOOL "")
set(CURL_DISABLE_PROXY    ON   CACHE BOOL "")
set(CURL_DISABLE_DICT     ON   CACHE BOOL "")
set(CURL_DISABLE_FILE     ON   CACHE BOOL "")
set(CURL_DISABLE_FTP      ON   CACHE BOOL "")
set(CURL_DISABLE_GOPHER   ON   CACHE BOOL "")
set(CURL_DISABLE_IMAP     ON   CACHE BOOL "")
set(CURL_DISABLE_MQTT     ON   CACHE BOOL "")
set(CURL_DISABLE_POP3     ON   CACHE BOOL "")
set(CURL_DISABLE_RTSP     ON   CACHE BOOL "")
set(CURL_DISABLE_SMB      ON   CACHE BOOL "")
set(CURL_DISABLE_SMTP     ON   CACHE BOOL "")
set(CURL_DISABLE_TELNET   ON   CACHE BOOL "")
set(CURL_DISABLE_TFTP     ON   CACHE BOOL "")

FetchContent_MakeAvailable(curl)
include_directories(/include)

# ============================================================
# Android NDK log library & pthreads
# ============================================================
find_library(ANDROID_LOG log)
find_package(Threads REQUIRED)

# ============================================================
# 源文件
# ============================================================
file(GLOB_RECURSE CORE_SOURCES
    "/src/*.c"
    "/third_party/*.c"
)
list(FILTER CORE_SOURCES EXCLUDE REGEX ".*/ffi_bridge\\.c$")

# ============================================================
# Build executable
# ============================================================
add_executable(esurfingd )

target_link_libraries(esurfingd
    libcurl
    Threads::Threads
    
    m
)

target_compile_options(esurfingd PRIVATE
    -Wall
    -Wextra
    -Wno-unused-parameter
    -Wno-unused-variable
    -Wno-implicit-function-declaration
    -Wno-int-conversion
    -Wno-pointer-sign
    -DANDROID
    -D__ANDROID__
    -D__MAGISK__
)

target_compile_definitions(esurfingd PRIVATE
    PROGRAM_FULL_VERSION=""
)

target_include_directories(esurfingd PUBLIC
    
    /include
    /src
    /third_party
)
