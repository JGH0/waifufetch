#!/bin/sh
# Patch script for compiling bash 3.2 on Alpine/musl with GCC14
set -e
cd /bash-3.2

# Fix 1: Add missing function declarations to shell.c
sed -i '68i\
extern int get_tty_state ();\
extern int initialize_job_control (int);' shell.c

# Fix 2: Add shell.h include for bashversion.c
sed -i '1i#include "../shell.h"' support/bashversion.c

# Fix 3: Add missing job control declarations to parser
sed -i '1i\
extern int cleanup_dead_jobs (void);\
extern int count_all_jobs (void);' y.tab.c
touch y.tab.c

# Fix 4: Rename exp2 to avoid conflict with math.h
sed -i 's/\bexp2\b/exp2_func/g' expr.c

# Fix 5: Remove getopt_long_only to avoid warning
sed -i 's/^extern char \*\*getopt_long_only/extern int getopt_long_only/' shell.c 2>/dev/null || true
