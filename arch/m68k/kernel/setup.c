// SPDX-License-Identifier: GPL-2.0
#if defined(CONFIG_M68KCLASSIC) || (defined(COLDFIRE) && defined(CONFIG_MMU))
#include "setup_classic_coldfire.c"
#else
#include "setup_uclinux.c"
#endif

#if IS_ENABLED(CONFIG_INPUT_M68K_BEEP)
void (*mach_beep)(unsigned int, unsigned int);
EXPORT_SYMBOL(mach_beep);
#endif
