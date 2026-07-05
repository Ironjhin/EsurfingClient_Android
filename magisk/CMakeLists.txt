cmake_minimum_required(VERSION 3.18.1)
project("esurfingd" LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Source root — relative to this file, pointing to the NDK cpp directory
set(SRC_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../android/app/src/main/cpp")

# ============================================================
# 头文件搜索路径
# ============================================================
include_directories(
    ${SRC_ROOT}
    ${SRC_ROOT}/cipher
    ${SRC_ROOT}/utils
    ${SRC_ROOT}/webserver
    ${SRC_ROOT}/external
    ${SRC_ROOT}/inc
    ${SRC_ROOT}/inc/cipher
    ${SRC_ROOT}/inc/utils
    ${SRC_ROOT}/inc/webserver
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
include_directories(${curl_SOURCE_DIR}/include)

# ============================================================
# 源文件
# ============================================================
file(GLOB CIPHER_SOURCES "${SRC_ROOT}/cipher/impl/*.c")
file(GLOB UTILS_SOURCES "${SRC_ROOT}/utils/*.c")
file(GLOB WEBSERVER_SOURCES "${SRC_ROOT}/webserver/*.c")

set(MAIN_SOURCES
    "${SRC_ROOT}/DialerClient.c"
    "${SRC_ROOT}/NetClient.c"
    "${SRC_ROOT}/States.c"
    "${SRC_ROOT}/cipher/CipherFactory.c"
    "${SRC_ROOT}/cipher/KeyData.c"
    "${SRC_ROOT}/cipher/CipherUtils.c"
    "${SRC_ROOT}/external/md5.c"
    "${SRC_ROOT}/main_magisk.c"
)

set(ALL_SOURCES
    ${MAIN_SOURCES}
    ${CIPHER_SOURCES}
    ${UTILS_SOURCES}
    ${WEBSERVER_SOURCES}
)

# ============================================================
# Build static executable
# ============================================================
find_package(Threads REQUIRED)
add_executable(esurfingd ${ALL_SOURCES})

target_link_libraries(esurfingd
    libcurl
    Threads::Threads
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
    -D__OPENWRT__=0
    -D__MAGISK__
)

target_include_directories(esurfingd PUBLIC
    ${SRC_ROOT}
    ${SRC_ROOT}/external
    ${SRC_ROOT}/inc
)
