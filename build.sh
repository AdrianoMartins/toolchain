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

export CFLAGS="$CFLAGS -Os -march=armv7-a"
export CXXFLAGS="$CXXFLAGS -Os -march=armv7-a"

# Don't edit anything below unless you know exactly what you're doing.
set -e

export LC_ALL=C

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
	patch -p0 <"$DIR/gcc-4.7-no-unneeded-multilib.patch"
fi
if ! [ -d make-$MAKE ]; then
	wget ftp://ftp.gnu.org/gnu/make/make-$MAKE.tar.bz2
	tar xf make-$MAKE.tar.bz2
fi
if ! [ -d ncurses-$NCURSES ]; then
	wget ftp://invisible-island.net/ncurses/ncurses-$NCURSES.tar.gz
	tar xf ncurses-$NCURSES.tar.gz
	cd ncurses-$NCURSES
	patch -p1 <"$DIR/ncurses-5.9-android.patch"
	cd ..
fi
if ! [ -d bionic ]; then
	git clone git://android.git.linaro.org/platform/bionic.git
	cd bionic
	git checkout -b linaro_android_$ANDROID origin/linaro_android_$ANDROID
	cd ..
fi
VIMD=`echo $VIM |sed -e 's,\.,,'` # Directory name is actually vim73 for vim-7.3 etc.
if ! [ -d vim$VIMD ]; then
	wget ftp://ftp.vim.org/pub/vim/unix/vim-$VIM.tar.bz2
	tar xf vim-$VIM.tar.bz2
	cd vim$VIMD
	patch -p1 <"$DIR/vim-7.3-crosscompile.patch"
	cd ..
fi
cd ..
export PATH="$DIR/tc-wrapper:$TC/bin:$PATH"

rm -rf "$DEST"
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
	cp -a src/bionic/$i/* "$DEST"/system/include
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
	--enable-shared \
	--disable-static \
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
	--disable-static \
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
	--disable-static \
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
	--disable-static \
	--target=arm-linux-androideabi \
	--host=arm-linux-androideabi
make $SMP
make install DESTDIR=$DEST
rm -f $DEST/system/lib/*.la # libtool sucks, *.la files are harmful
cd ..

# TODO build CLooG and friends for graphite

export CXXFLAGS="-O2 -frtti"
rm -rf gcc
mkdir -p gcc
cd gcc
$SRC/gcc/configure \
	--prefix=/system \
	--target=arm-linux-androideabi \
	--host=arm-linux-androideabi \
	--enable-languages=c,c++ \
	--with-gnu-as \
	--with-gnu-ar \
	--disable-libssp \
	--disable-libmudflap \
	--disable-libitm \
	--disable-nls \
	--disable-libquadmath \
	--disable-sjlj-exceptions
make $SMP
make install DESTDIR=$DEST
cd ..

# Remove superfluous bits
rm -rf \
	"$DEST"/system/lib/gcc/arm-linux-androideabi/*/include-fixed \
	"$DEST"/system/share/gcc-*

# Get rid of superfluous/obsolete multilibbing, Thumb-2 and ARM are
# always interworkable
rm -rf "$DEST"/system/lib/armv7-a/thumb

# Problem: Android has a libstdc++.so that is rather different from
# ours -- it's kind of libsupc++ supplemented by stlport.
# One possibility is to make gcc use stlport - the other is to get
# rid of Android's "libstdc++" in favor of the real thing.
# The latter is probably better for technical reasons, but the former
# is the only thing that will be accepted by AOSP because of libstdc++'s
# non-BSD licensing.
# People will just have to link to .so.6 manually if they need STL for now
rm "$DEST"/system/lib/armv7-a/libstdc++.so

mv "$DEST"/system/lib/armv7-a/* "$DEST"/system/lib/
rmdir "$DEST"/system/lib/armv7-a

# Libtool sucks
rm -f "$DEST"/system/lib/*.la

# TODO Actually build bionic instead of cheating by pulling those
# from the prebuilt toolchain
cp -a "$TC"/arm-linux-androideabi/lib/crt*.o "$DEST"/system/lib/

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

# Get rid of components we don't need, we just need what we need to run vim
rm -rf \
	"$DEST"/system/lib/libform* \
	"$DEST"/system/lib/libmenu* \
	"$DEST"/system/lib/libpanel* \
	"$DEST"/system/lib/libncurses*.a

# Get rid of most terminfo files... We just want:
# screen -- used by Android Terminal Emulator and just generally useful
# linux, xterm and variants -- useful when ssh-ing in
# vt100 -- that's what we get from "adb shell"
rm -rf	"$DEST"/system/share/terminfo/[0-9]* \
	"$DEST"/system/share/terminfo/[a-k]* \
	"$DEST"/system/share/terminfo/l/l[a-h]* \
	"$DEST"/system/share/terminfo/l/li[a-m]* \
	"$DEST"/system/share/terminfo/l/li[o-z]* \
	"$DEST"/system/share/terminfo/l/l[j-z]* \
	"$DEST"/system/share/terminfo/[m-r]* \
	"$DEST"/system/share/terminfo/s/s[0-9]* \
	"$DEST"/system/share/terminfo/s/s[a-b]* \
	"$DEST"/system/share/terminfo/s/sc[0-9]* \
	"$DEST"/system/share/terminfo/s/sc[a-q]* \
	"$DEST"/system/share/terminfo/s/screwpoint \
	"$DEST"/system/share/terminfo/s/scrhp \
	"$DEST"/system/share/terminfo/s/s[d-z]* \
	"$DEST"/system/share/terminfo/[t-u]* \
	"$DEST"/system/share/terminfo/v/v[0-9]* \
	"$DEST"/system/share/terminfo/v/v[a-s]* \
	"$DEST"/system/share/terminfo/v/vt100-am \
	"$DEST"/system/share/terminfo/v/vt102* \
	"$DEST"/system/share/terminfo/v/vt1[1-9]* \
	"$DEST"/system/share/terminfo/v/vt[2-9]* \
	"$DEST"/system/share/terminfo/v/vt-* \
	"$DEST"/system/share/terminfo/v/v[u-z]* \
	"$DEST"/system/share/terminfo/w* \
	"$DEST"/system/share/terminfo/x/x[0-9]* \
	"$DEST"/system/share/terminfo/x/x[a-s]* \
	"$DEST"/system/share/terminfo/x/xtalk* \
	"$DEST"/system/share/terminfo/x/x[u-z]* \
	"$DEST"/system/share/terminfo/[y-z]* \
	"$DEST"/system/share/terminfo/[A-Z]*
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
ln -s vim "$DEST"/system/bin/vi
cd ..

# save space (from vim)
rm -rf \
	"$DEST"/system/share/vim/vim$VIMD/doc \
	"$DEST"/system/share/vim/vim$VIMD/tutor \
	"$DEST"/system/share/vim/vim$VIMD/print \
	"$DEST"/system/bin/vimtutor
pushd "$DEST"/system/share/vim/vim$VIMD/syntax
for i in *; do
	[ "$i" = "config.vim" ] || \
	[ "$i" = "conf.vim" ] || \
	[ "$i" = "cpp.vim" ] || \
	[ "$i" = "c.vim" ] || \
	[ "$i" = "doxygen.vim" ] || \
	[ "$i" = "html.vim" ] || \
	[ "$i" = "javascript.vim" ] || \
	[ "$i" = "java.vim" ] || \
	[ "$i" = "manual.vim" ] || \
	[ "$i" = "sh.vim" ] || \
	[ "$i" = "syncolor.vim" ] || \
	[ "$i" = "synload.vim" ] || \
	[ "$i" = "syntax.vim" ] || \
	[ "$i" = "vim.vim" ] || \
		rm -f "$i"
done
popd

# Save space (from stuff accumulated by all projects)
rm -rf \
	"$DEST"/share/doc \
	"$DEST"/share/info

# strip everything so we can fit into the limited
# /system space on GNexus
# set +e because the strip command will fail, given it will also get
# to "strip" non-binaries.
set +e
find "$DEST" |xargs $TC/bin/arm-linux-androideabi-strip --strip-unneeded
echo
echo Toolchain build successful.
echo The native toolchain can be found in $DEST.