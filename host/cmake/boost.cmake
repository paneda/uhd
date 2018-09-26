###########################################################################

# Makes sure that the boost-libs listed in "project_boost_libs" are built.

###########################################################################

message(" ")
message("### Boost config start ###")
message(" ")

set(Boost_NO_SYSTEM_PATHS ON)

# Default to debug if CMAKE_BUILD_TYPE is not set.

set(PROJECT_BUILD_TYPE ${CMAKE_BUILD_TYPE})
if(NOT PROJECT_BUILD_TYPE)
  set(PROJECT_BUILD_TYPE debug)
endif()
string(TOLOWER ${PROJECT_BUILD_TYPE} PROJECT_BUILD_TYPE)
message("PROJECT_BUILD_TYPE: ${PROJECT_BUILD_TYPE}")

# Header-only internal dependencies where possible
add_definitions(-DBOOST_ALL_NO_LIB)

# It is possible to override TEMPLATE_BOOST_ROOT by defining
# LOCAL_BOOST_ROOT before including boost.txt
if(NOT LOCAL_BOOST_ROOT)
  set(LOCAL_BOOST_ROOT $ENV{TEMPLATE_BOOST_ROOT})
endif()

message("TEMPLATE_BOOST_ROOT: $ENV{TEMPLATE_BOOST_ROOT}")
#message("TEMPLATE_BOOST_LIBRARYDIR: $ENV{TEMPLATE_BOOST_LIBRARYDIR}")

include(ExternalProject)

## Build boost b2 if it doesn't already exists. ##

set(B2_EXECUTABLE )
if(WIN32)
  set(B2_EXECUTABLE b2.exe)
  set(BOOST_BOOTSTRAP bootstrap.bat)
else()
  set(B2_EXECUTABLE b2)
  set(BOOST_BOOTSTRAP bootstrap.sh)
endif()

set(BUILD_B2 "")
if(NOT EXISTS "${LOCAL_BOOST_ROOT}/${B2_EXECUTABLE}")
  set(BUILD_B2 ${LOCAL_BOOST_ROOT}/${BOOST_BOOTSTRAP})
  execute_process(
    WORKING_DIRECTORY
            ${LOCAL_BOOST_ROOT}
        COMMAND
          cmake -E env BOOST_ROOT=${LOCAL_BOOST_ROOT} ${LOCAL_BOOST_ROOT}/${BOOST_BOOTSTRAP}
  )
endif()

# cmake and boost build engine use different notation for the gcc/gnu toolset.
set(TOOLSET "${CMAKE_CXX_COMPILER_ID}")
string(TOLOWER ${TOOLSET} TOOLSET)
if(TOOLSET STREQUAL "gnu")
  set(TOOLSET gcc)
endif()
message("Toolset: ${TOOLSET}")

# Find Boost version info
FILE(READ ${LOCAL_BOOST_ROOT}/boost/version.hpp BOOST_LIB_VERSION_FILE)
STRING(REGEX MATCH "\n#define BOOST_LIB_VERSION.*" BOOST_LIB_VERSION_LINE ${BOOST_LIB_VERSION_FILE})
STRING(REGEX MATCH "([0-9]+_[0-9]+_[0-9]+|[0-9]+_[0-9]+)" BOOST_LIB_VERSION ${BOOST_LIB_VERSION_LINE})

message("Boost version: ${BOOST_LIB_VERSION}")

# Create the b2 build-string with all desired libs
set(boost_with "")
message("Boost libs to build:")
foreach(libname ${project_boost_libs})
  set(boost_with ${boost_with} --with-${libname})
  message("- ${libname}")
endforeach()
message(" ")

SET(LIBBOOST_TEST_FRAMEWORK)
SET(LIBBOOST_LIBS)

set(BOOST_BUILD_COMMAND ${LOCAL_BOOST_ROOT}/${B2_EXECUTABLE})
set(BOOST_BUILD_COMMAND_ARGS
  -sBOOST_ROOT=${LOCAL_BOOST_ROOT}
  --layout=system
  --build-dir=${CMAKE_CURRENT_BINARY_DIR}/boost_libs
  --stagedir=${CMAKE_CURRENT_BINARY_DIR}/boost_libs
  --toolset=${TOOLSET}
  ${boost_with}
  variant=${PROJECT_BUILD_TYPE}
  link=static
  cflags=-fPIC
  cxxflags=-fPIC
  threading=multi
)

set(OsSpecific "")
if(WIN32)
  # Dry-run for Windows to setup Boost build cache that always returns errors as it tries to build for
  # ARM etc. as part of the system identification process. We send all output to null to avoid build
  # server problems. Once the system setup is in the Boost build cache it will build all libraries
  # without errors.
  set(WIN_PRE_BUILD_COMMAND_ARGS
    -sBOOST_ROOT=${LOCAL_BOOST_ROOT}
        --layout=system
        --build-dir=${CMAKE_CURRENT_BINARY_DIR}/boost_libs
        --stagedir=${CMAKE_CURRENT_BINARY_DIR}/boost_libs
        --toolset=${TOOLSET}
        --with-atomic variant=${PROJECT_BUILD_TYPE}
        link=static
        threading=multi
  )
  set(OsSpecific
    cmake -E env BOOST_ROOT=${LOCAL_BOOST_ROOT} ${BOOST_BUILD_COMMAND} ${WIN_PRE_BUILD_COMMAND_ARGS}
  )
endif()

# Build the boost libs

#message(BOOST_BUILD_COMMAND: "${BOOST_BUILD_COMMAND}")
#message(BOOST_BUILD_COMMAND_ARGS: "${BOOST_BUILD_COMMAND_ARGS}")
#message("OsSpecific: ${OsSpecific}")

ExternalProject_Add(boost_libs
    SOURCE_DIR ${LOCAL_BOOST_ROOT}
    PREFIX ${CMAKE_CURRENT_BINARY_DIR}/boost_libs
    INSTALL_DIR ""
    UPDATE_COMMAND ""
        LOG_CONFIGURE 1
    CONFIGURE_COMMAND "${OsSpecific}"
    BUILD_COMMAND
      cmake -E env BOOST_ROOT=${LOCAL_BOOST_ROOT} ${BOOST_BUILD_COMMAND} ${BOOST_BUILD_COMMAND_ARGS}
    BUILD_IN_SOURCE 1
    INSTALL_COMMAND ""
)

# Add the libs whereabouts to a list for easy use with target_link_libraries in your CMakeLists.txt

foreach(lib ${project_boost_libs})
  if(lib STREQUAL "test" )
    set(lib unit_test_framework)
        SET(LIBBOOST_TEST_FRAMEWORK
                optimized ${CMAKE_CURRENT_BINARY_DIR}/boost_libs/lib/libboost_${lib}${CMAKE_STATIC_LIBRARY_SUFFIX}
                debug ${CMAKE_CURRENT_BINARY_DIR}/boost_libs/lib/libboost_${lib}${CMAKE_STATIC_LIBRARY_SUFFIX}
        )
  else()
        SET(LIBBOOST_LIBS ${LIBBOOST_LIBS}
                optimized ${CMAKE_CURRENT_BINARY_DIR}/boost_libs/lib/libboost_${lib}${CMAKE_STATIC_LIBRARY_SUFFIX}
                debug ${CMAKE_CURRENT_BINARY_DIR}/boost_libs/lib/libboost_${lib}${CMAKE_STATIC_LIBRARY_SUFFIX}
        )
  endif()
endforeach()

ExternalProject_Get_Property(boost_libs BINARY_DIR)
set(LIBBOOST_DIRS "${BINARY_DIR}/lib")

message("### Boost config done! ###")
message(" ")
