/* config.h for LAME - cross-platform configuration */

#ifndef CONFIG_H_INCLUDED
#define CONFIG_H_INCLUDED

/* Define to 1 if you have the <stdint.h> header file. */
#define HAVE_STDINT_H 1

/* Define to 1 if you have the <inttypes.h> header file. */
#define HAVE_INTTYPES_H 1

/* Define to 1 if you have the <stdlib.h> header file. */
#define HAVE_STDLIB_H 1

/* Define to 1 if you have the <string.h> header file. */
#define HAVE_STRING_H 1

/* Define to 1 if you have the <memory.h> header file. */
#define HAVE_MEMORY_H 1

/* Define to 1 if you have the <strings.h> header file. */
#define HAVE_STRINGS_H 1

/* Define to 1 if you have the <sys/stat.h> header file. */
#define HAVE_SYS_STAT_H 1

/* Define to 1 if you have the <sys/types.h> header file. */
#define HAVE_SYS_TYPES_H 1

/* Define to 1 if you have the <unistd.h> header file. */
#ifndef _WIN32
#define HAVE_UNISTD_H 1
#endif

/* Define to 1 if you have the <fcntl.h> header file. */
#define HAVE_FCNTL_H 1

/* Define to 1 if you have the <limits.h> header file. */
#define HAVE_LIMITS_H 1

/* Define to 1 if you have the <errno.h> header file. */
#define HAVE_ERRNO_H 1

/* Define if you have the ANSI C header files. */
#define STDC_HEADERS 1

/* The number of bytes in various types */
#define SIZEOF_DOUBLE 8
#define SIZEOF_FLOAT 4
#define SIZEOF_INT 4
#define SIZEOF_SHORT 2
#define SIZEOF_UNSIGNED_INT 4
#define SIZEOF_UNSIGNED_SHORT 2

#if defined(__LP64__) || defined(_WIN64)
#define SIZEOF_LONG 8
#define SIZEOF_UNSIGNED_LONG 8
#else
#define SIZEOF_LONG 4
#define SIZEOF_UNSIGNED_LONG 4
#endif

#define SIZEOF_LONG_DOUBLE 16

/* Define if compiler has function prototypes */
#define PROTOTYPES 1

/* faster log implementation with less but enough precision */
#define USE_FAST_LOG 1

/* Functions available */
#define HAVE_STRCHR 1
#define HAVE_MEMCPY 1
#define HAVE_STRTOL 1

/* IEEE float types */
typedef long double ieee854_float80_t;
typedef double      ieee754_float64_t;
typedef float       ieee754_float32_t;

/* Name of package */
#define PACKAGE "lame"

/* Version number of package */
#define VERSION "3.100"

/* We're building the library */
#define LAME_LIBRARY_BUILD 1

#endif /* CONFIG_H_INCLUDED */
