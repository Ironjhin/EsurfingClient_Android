cmake_minimum_required(VERSION 3.18.1)
project("esurfing_client" LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# ============================================================
#  头文件搜索路径
# ============================================================
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/cipher
    ${CMAKE_CURRENT_SOURCE_DIR}/utils
    ${CMAKE_CURRENT_SOURCE_DIR}/webserver
    ${CMAKE_CURRENT_SOURCE_DIR}/external
    ${CMAKE_CURRENT_SOURCE_DIR}/inc
    ${CMAKE_CURRENT_SOURCE_DIR}/inc/cipher
    ${CMAKE_CURRENT_SOURCE_DIR}/inc/utils
    ${CMAKE_CURRENT_SOURCE_DIR}/inc/webserver
)

# ============================================================
#  libcurl — 通过 FetchContent 自动拉取源码并为 Android 编译
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
#  Android NDK log library
# ============================================================
find_library(ANDROID_LOG log)

# ============================================================
#  源文件
# ============================================================
file(GLOB CIPHER_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/cipher/impl/*.c")

file(GLOB UTILS_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/utils/*.c")

file(GLOB WEBSERVER_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/webserver/*.c")

set(MAIN_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/DialerClient.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/NetClient.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/States.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/ffi_bridge.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/cipher/CipherFactory.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/cipher/KeyData.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/cipher/CipherUtils.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/external/md5.c"
)

set(ALL_SOURCES
    ${MAIN_SOURCES}
    ${CIPHER_SOURCES}
    ${UTILS_SOURCES}
    ${WEBSERVER_SOURCES}
)

# ============================================================
#  Build shared library
# ============================================================
add_library(esurfing_client SHARED ${ALL_SOURCES})

target_link_libraries(esurfing_client
    libcurl
    ${ANDROID_LOG}
)

target_compile_options(esurfing_client PRIVATE
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
)

target_include_directories(esurfing_client PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/external
    ${CMAKE_CURRENT_SOURCE_DIR}/inc
)
