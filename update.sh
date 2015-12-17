#!/bin/sh

ARCHS="alpha amd64 arm64 armel armhf hppa hurd-i386 i386 kfreebsd-amd64 kfreebsd-i386 m68k mips mipsel powerpc powerpcspe ppc64 ppc64el s390x sh4 sparc64 x32"

set -e

for arch in ${ARCHS}; do
    mkdir -p "${arch}"

    # arch
    if [ ! -f "${arch}/arch" ]; then
	echo "${arch}" > "${arch}/arch"
    fi
    realarch=$(cat "${arch}/arch")

    # deb
    if [ ! -f "${arch}/deb" ]; then
	(
	    set -x
	    curl -s https://packages.debian.org/sid/alpha/busybox-static/download | tr '"' "\n" | grep -E "http://.*alpha\\.deb" > "${arch}/deb"
	)
    fi
    deb=$(head -n 1 "${arch}/deb")

    if [ ! -f "${arch}/busybox-static.deb" ]; then
	(
	    set -x
	    curl "${deb}" > "${arch}/busybox-static.deb.tmp"
	    mv "${arch}/busybox-static.deb.tmp" "${arch}/busybox-static.deb"
	)
    fi

    # extract /bin/busybox
    if [ ! -f "${arch}/rootfs/bin/busybox" ]; then
	(
	    cd "${arch}"
	    set -x
	    ar vx busybox-static.deb data.tar.xz data.tar.gz
	    tar --strip=2 -xvf data.tar.* ./bin/busybox
	    mkdir -p ./rootfs/bin
	    mv ./busybox ./rootfs/bin/
	)
    fi

    # create symlinks
    if [ ! -f "${arch}/rootfs/bin/ls" ]; then
	(
	    cd "${arch}/rootfs"
	    set -x
	    echo "This need binfmt to be configured"
	    echo "  docker run --rm --privileged multiarch/qemu-user-static:register --reset."
	    for module in $("./bin/busybox" --list-modules); do
		mkdir -p "$(dirname $module)"
		ln -s /bin/busybox "${module}"
	    done
	)
    fi

    # create dirs and files
    if [ ! -d "${arch}/rootfs/dev" ]; then
	(
	    cd "${arch}/rootfs"
	    set -x
	    mkdir -p bin etc dev dev/pts lib proc sys tmp
	    cp /etc/nsswitch.conf etc/nsswitch.conf
	    echo root:x:0:0:root:/:/bin/sh > etc/passwd
	    echo root:x:0: > etc/group
	)
    fi

    # create archive
    if [ ! -f "${arch}/rootfs.tar.xz" ]; then
	(
	    cd "${arch}/rootfs"
	    set -x
	    tar --numeric-owner -cJf ../rootfs.tar.xz .
	)
    fi

    # create Dockerifle
    if [ ! -f "${arch}/Dockerfile" ]; then
	cat > "${arch}/Dockerfile" <<EOF
FROM scratch
ADD rootfs.tar.xz /
EOF
    fi

    # create .dockerignore
    if [ ! -f "${arch}/.dockerignore" ]; then
	cat > "${arch}/.dockerignore" <<EOF
rootfs
data.tar.*
busybox-static.deb
EOF
    fi

    # info
    echo "======================="
    echo "arch=$arch"
    echo "realarch=$arch"
    echo "deb=$deb"
    (
	set -x
	ls -la "${arch}/busybox-static.deb"
	du -hs "${arch}/rootfs"
	find "${arch}/rootfs" -type f | wc -l
	ls -la "${arch}/rootfs.tar.xz"
    )

    # build & test
    (
	set -x
	docker build -t "multiarch/busybox:${arch}" "${arch}"
	# docker run -it --rm "multiarch/busybox:${arch}" uname -a
    )

done
