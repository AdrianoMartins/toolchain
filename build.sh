#!/bin/bash

# Wanted versions
[ -z "$BINUTILS" ] && BINUTILS=2.23.51.0.3
[ -z "$GCC" ] && GCC=lp:gcc-linaro
[ -z "$GMP" ] && GMP=5.0.5
[ -z "$MPFR" ] && MPFR=3.1.1
[ -z "$MPC" ] && MPC=1.0
[ -z "$MAKE" ] && MAKE=3.82
[ -z "$NCURSES" ] && NCURSES=5.9
[ -z "$VIM" ] && VIM=7.3
[ -z "$ANDROID" ] && ANDROID=4.1.2

# Installation location
[ -z "$DEST" ] && DEST=/tmp/android-native-toolchain

# Parallel build flag passed to make
[ -z "$SMP" ] && SMP="-j`getconf _NPROCESSORS_ONLN`"

# Don't edit anything below unless you know exactly what you're doing.
set -e

DIR="$(readlink -f $(dirname $0))"
cd "$DIR"
if ! [ -d android-toolchain-eabi ]; then
	wget https://android-build.linaro.org/jenkins/view/Toolchain/job/linaro-android_toolchain-4.7-bzr/lastSuccessfulBuild/artifact/build/out/android-toolchain-eabi-4.7-daily-linux-x86.tar.bz2
	tar xf android-toolchain-eabi-4.7-daily-linux-x86.tar.bz2
fi
TC="$DIR/android-toolchain-eabi"
if ! [ -d tc-wrapper ]; then
	# Workaround for
	#	1. toolchain not being properly sysrooted
	#	2. gcc not making a difference between CPPFLAGS for build and host machine
	mkdir tc-wrapper
	gcc -std=gnu99 -o tc-wrapper/arm-linux-androideabi-gcc tc-wrapper.c -DCCVERSION=\"4.7.3\" -DTCROOT=\"`pwd`/android-toolchain-eabi\" -DDESTDIR=\"/tmp/android-native-toolchain\"
	for i in cpp g++ c++; do
		ln -s arm-linux-androideabi-gcc tc-wrapper/arm-linux-androideabi-$i
	done
fi
SRC="$DIR/src"
[ -d src ] || mkdir src
cd src
if ! [ -d binutils ]; then
	git clone git://android.git.linaro.org/toolchain/binutils.git
	cd binutils
	git checkout -b linaro-master origin/linaro-master
	cd ..
fi
if ! [ -d gmp ]; then
	git clone git://android.git.linaro.org/toolchain/gmp.git
	cd gmp
	git checkout -b linaro-master origin/linaro-master
	cd ..
fi
if ! [ -d mpfr ]; then
	git clone git://android.git.linaro.org/toolchain/mpfr.git
	cd mpfr
	git checkout -b linaro-master origin/linaro-master
	cd ..
fi
if ! [ -d mpc ]; then
	git clone git://android.git.linaro.org/toolchain/mpc.git
	cd mpc
	git checkout -b linaro-master origin/linaro-master
	cd ..
fi
if ! [ -d gcc ]; then
	bzr branch $GCC gcc
	patch -p0 <"$DIR/gcc-4.7-android-workarounds.patch"
fi
if ! [ -d make-$MAKE ]; then
	wget ftp://ftp.gnu.org/gnu/make/make-$MAKE.tar.bz2
	tar xf make-$MAKE.tar.bz2
fi
if ! [ -d ncurses-$NCURSES ]; then
	wget ftp://invisible-island.net/ncurses/ncurses-$NCURSES.tar.gz
	tar xf ncurses-$NCURSES.tar.gz
fi
VIMD=`echo $VIM |sed -e 's,\.,,'` # Directory name is actually vim73 for vim-7.3 etc.
if ! [ -d vim$VIMD ]; then
	wget ftp://ftp.vim.org/pub/vim/unix/vim-$VIM.tar.bz2
	tar xf vim-$VIM.tar.bz2
fi
if ! [ -d android ]; then
	mkdir android
	cd android
	repo init -u git://android.git.linaro.org/platform/manifest.git -b linaro_android_$ANDROID -m tracking-panda.xml
	repo sync
	cd ..
fi
cd ..

export PATH="$DIR/tc-wrapper:$TC/bin:$PATH"

rm -rf "$DEST"
cd src/android
# Android can't be built out-of-source for the time being...
#make TARGET_TOOLS_PREFIX="$TC/bin/arm-linux-androideabi-" TARGET_PRODUCT=pandaboard BUILD_TINY_ANDROID=true
cd ../..
# FIXME this is a pretty awful hack to make sure gcc can find
# its headers even though it has been taught Android doesn't
# have system headers (no proper sysroot)
# At some point, we should build a properly sysrooted compiler
# even if AOSP doesn't.
#
# We can't just cp -a bionic/libc/include \
# 	bionic/libc/arch-arm-include ... \
#	"$TC"/lib/gcc/arm-linux-androideabi/*/include
# because some files in kernel/arch-arm are supposed to overwrite
# files from libc/include
mkdir -p "$DEST"/system/include
for i in libc/include libc/arch-arm/include libc/kernel/common libc/kernel/arch-arm libm/include; do
#	cp -a bionic/$i/* "$TC"/lib/gcc/arm-linux-androideabi/*/include/
	cp -a src/android/bionic/$i/* "$DEST"/system/include
done

rm -rf build
mkdir build
cd build
mkdir -p binutils
cd binutils
# FIXME gold is disabled for now because of its C++ dependency.
# Need to integrate stlport into the build before building it,
# then make it the default
$SRC/binutils/binutils-$BINUTILS/configure \
	--prefix=/system \
	--target=arm-linux-androideabi \
	--host=arm-linux-androideabi \
	--disable-gold \
	--disable-nls
make $SMP
make install DESTDIR=$DEST
rm -f $DEST/system/lib/*.la # libtool sucks, *.la files are harmful
cd ..

rm -rf gmp
mkdir -p gmp
cd gmp
$SRC/gmp/gmp-$GMP/configure \
	--prefix=/system \
	--disable-nls \
	--target=arm-linux-androideabi \
	--host=arm-linux-androideabi
make $SMP
make install DESTDIR=$DEST
rm -f $DEST/system/lib/*.la # libtool sucks, *.la files are harmful
cd ..

rm -rf mpfr
mkdir -p mpfr
cd mpfr
$SRC/mpfr/mpfr-$MPFR/configure \
	--prefix=/system \
	--target=arm-linux-androideabi \
	--host=arm-linux-androideabi \
	--with-sysroot=$DEST \
	--with-gmp-include=$DEST/system/include \
	--with-gmp-lib=$DEST/system/lib \
	--disable-nls
make $SMP
make install DESTDIR=$DEST
rm -f $DEST/system/lib/*.la # libtool sucks, *.la files are harmful
cd ..

rm -rf mpc
mkdir -p mpc
cd mpc
pushd $SRC/mpc/mpc-$MPC
# Got to rebuild the auto* bits - the auto* versions
# they were built with are too old to recognize
# "androideabi"
libtoolize --force
cp -f /usr/share/libtool/config/config.* .
aclocal -I m4
automake -a
autoconf
popd
# libtool rather sucks
rm -f $DEST/system/lib/*.la
$SRC/mpc/mpc-$MPC/configure \
	--prefix=/system \
	--target=arm-linux-androideabi \
	--host=arm-linux-androideabi
make $SMP
make install DESTDIR=$DEST
rm -f $DEST/system/lib/*.la # libtool sucks, *.la files are harmful
cd ..

# TODO build CLooG and friends for graphite

rm -rf gcc
mkdir -p gcc
cd gcc
$SRC/gcc/configure \
	--prefix=/system \
	--target=arm-linux-androideabi \
	--host=arm-linux-androideabi \
	--enable-languages=c \
	--with-gnu-as \
	--with-gnu-ar \
	--disable-libssp \
	--disable-libmudflap \
	--disable-nls \
	--disable-libquadmath \
	--disable-sjlj-exceptions
make $SMP
make install DESTDIR=$DEST
cd ..

rm -rf make
mkdir -p make
cd make
$SRC/make-$MAKE/configure \
	--prefix=/system \
	--target=arm-linux-androideabi \
	--host=arm-linux-androideabi
make $SMP
make install DESTDIR=$DEST
cd ..

rm -rf ncurses
mkdir ncurses
cd ncurses
$SRC/ncurses-$NCURSES/configure \
	--prefix=/system \
	--target=arm-linux-androideabi \
	--host=arm-linux-androideabi \
	--enable-hard-tabs \
	--enable-const \
	--without-cxx-binding \
	--without-ada \
	--without-manpages \
	--with-shared
make $SMP
make install DESTDIR=$DEST
cd ..

rm -rf vim
# vim doesn't currently support out-of-source builds
cp -a $SRC/vim$VIMD vim
cd vim
vim_cv_toupper_broken=no vim_cv_terminfo=yes vim_cv_tgent=zero \
vim_cv_stat_ignores_slash=no vim_cv_tty_group=system vim_cv_tty_mode=0666 vim_cv_getcwd_broken=no \
vim_cv_memmove_handles_overlap=yes \
	./configure \
		--prefix=/system \
		--target=arm-linux-androideabi \
		--host=arm-linux-androideabi
make $SMP STRIP=$TC/bin/arm-linux-androideabi-strip
make install DESTDIR=$DEST STRIP=$TC/bin/arm-linux-androideabi-strip
cd ..
