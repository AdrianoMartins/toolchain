/* Toolchain wrapper -- pass Android's needed flags to the real compiler */
#include <libgen.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

enum {
	CPP	= 0x1,
	CC	= 0x2,
	CCLD	= 0x4,
	LD	= 0x8,
	SHLD	= 0x10,
} mode;
static const char *cpp_extras[] = {
	"-nostdinc",
	"-isystem",
	TCROOT "/lib/gcc/arm-linux-androideabi/" CCVERSION "/include/",
	"-isystem",
	DESTDIR "/system/include/",
	"-DANDROID"
};
static const char *ccld_extras[] = {
	"-nostdlib",
	"-L" DESTDIR "/system/lib/",
	"-Bdynamic",
	"-fPIE",
	"-fpie",
	"-Wl,--dynamic-linker,/system/bin/linker",
	"-Wl,-z,nocopyreloc",
	"-lc",
	"-lm",
	TCROOT "/arm-linux-androideabi/lib/crtbegin_dynamic.o",
	"-Wl,-O2",
	"-Wl,-z,noexecstack",
	"-Wl,-z,relro",
	"-Wl,-z,now",
	"-Wl,--icf=safe",
	"-Wl,--no-fix-cortex-a8",
	"-Wl,--no-undefined",
	TCROOT "/lib/gcc/arm-linux-androideabi/" CCVERSION "/armv7-a/libgcc.a",
	TCROOT "/arm-linux-androideabi/lib/crtend_android.o"
};
static const char *shld_extras[] = {
	"-nostdlib",
	"-L" DESTDIR "/system/lib/",
	"-Wl,--gc-sections",
	"-Wl,-shared,-Bsymbolic",
	"-Wl,--dynamic-linker,/system/bin/linker",
	"-Wl,-z,nocopyreloc",
	"-lc",
	"-lm",
	TCROOT "/arm-linux-androideabi/lib/crtbegin_so.o",
	"-Wl,-O2",
	"-Wl,-z,noexecstack",
	"-Wl,-z,relro",
	"-Wl,-z,now",
	"-Wl,--icf=safe",
	"-Wl,--no-fix-cortex-a8",
	"-Wl,--no-undefined",
	TCROOT "/lib/gcc/arm-linux-androideabi/" CCVERSION "/armv7-a/libgcc.a"
};
static const char *ld_extras[] = {
	"-nostdlib",
	"-L" DESTDIR "/system/lib/",
	"-Bdynamic",
	"-pie",
	"--dynamic-linker",
	"/system/bin/linker",
	"-z", "nocopyreloc",
	"-lc",
	"-lm",
	TCROOT "/arm-linux-androideabi/lib/crtbegin_dynamic.o",
	"-O2",
	"-z", "noexecstack",
	"-z", "relro",
	"-z", "now",
	"--icf=safe",
	"--no-fix-cortex-a8",
	"--no-undefined",
	TCROOT "/lib/gcc/arm-linux-androideabi/" CCVERSION "/armv7-a/libgcc.a",
	TCROOT "/arm-linux-androideabi/lib/crtend_android.o"
};
static const char *cc_extras[] = {
	"-march=armv7-a",
	"-mtune=cortex-a9",
	"-mcpu=cortex-a9",
	"-msoft-float",
	"-fpic",
	"-fPIE",
	"-ffunction-sections",
	"-fdata-sections",
	"-funwind-tables",
	"-fstack-protector",
	"-Wa,--noexecstack",
	"-fno-short-enums",
	"-mfloat-abi=softfp",
	"-mfpu=neon",
	"-mthumb-interwork",
	"-fgcse-after-reload",
	"-frerun-cse-after-loop",
	"-frename-registers"
};
int main(int argc, char **argv) {
	mode = CPP | CC | CCLD; // By default, gcc does preprocessing, compiling, and linking -- except:
	char *tool=basename(argv[0]);
	char *basetool=strchr(tool, '-') ? strrchr(tool, '-')+1 : tool;
	if(!strcmp(basetool, "cpp"))
		mode = CPP;
	else if(!strncmp(basetool, "ld", 2))
		mode = LD;
	for(int i=1; i<argc; i++) {
		if(!strcmp(argv[i], "-c") || !strcmp(argv[i], "-S")) {
			mode = CPP | CC; // No linking done with -c or -s
			break;
		} else if(!strcmp(argv[i], "-E")) {
			mode = CPP; // Just preprocessing...
			break;
		} else if(!strcmp(argv[i], "-shared")) {
			mode = SHLD; // Linking shared library
			break;
		}
	}
	int args = argc;
	if(mode & CPP)
		args += sizeof(cpp_extras)/sizeof(char*);
	if(mode & CC)
		args += sizeof(cc_extras)/sizeof(char*);
	if(mode & LD)
		args += sizeof(ld_extras)/sizeof(char*);
	if(mode & CCLD)
		args += sizeof(ccld_extras)/sizeof(char*);
	if(mode & SHLD)
		args += sizeof(shld_extras)/sizeof(char*);
	char **new_argv=(char**)malloc(sizeof(char*)*(args+2));
	new_argv[0]=(char*)malloc(strlen(TCROOT) + 6 + strlen(tool));
	sprintf(new_argv[0], "%s/bin/%s", TCROOT, tool);
	int arg;
	for(arg=1; arg<argc; arg++)
		new_argv[arg] = argv[arg];
	if(mode & CPP) {
		for(int i=0; i<sizeof(cpp_extras)/sizeof(char*); i++)
			new_argv[arg++]=cpp_extras[i];
	}
	if(mode & CC) {
		for(int i=0; i<sizeof(cc_extras)/sizeof(char*); i++)
			new_argv[arg++]=cc_extras[i];
	}
	if(mode & LD) {
		for(int i=0; i<sizeof(ld_extras)/sizeof(char*); i++)
			new_argv[arg++]=ld_extras[i];
	}
	if(mode & CCLD) {
		for(int i=0; i<sizeof(ccld_extras)/sizeof(char*); i++)
			new_argv[arg++]=ccld_extras[i];
	}
	if(mode & SHLD) {
		for(int i=0; i<sizeof(shld_extras)/sizeof(char*); i++) {
			if(strstr(shld_extras[i], "crtbegin_so.o")) { // Make sure we don't list this twice...
				int found = 0;
				for(int j=0; j<argc; j++) {
					if(strstr(argv[j], "crtbegin_so.o")) {
						found = 1;
						break;
					}
				}
				if(found)
					continue;
			}
			new_argv[arg++]=shld_extras[i];
		}
	}
	new_argv[arg]=0;
	FILE *f=fopen("/tmp/LOG", "a");
	for(int i=0; i<arg; i++)
		fprintf(f, "%s ", new_argv[i]);
	fprintf(f, "\n\n");
	fclose(f);
	execv(new_argv[0], new_argv);
}