#!/bin/sh

ARCHS=${ARCHS:-"alpha amd64 arm64 armel armhf hppa hurd-i386 i386 kfreebsd-amd64 kfreebsd-i386 m68k mips mipsel powerpc powerpcspe ppc64 ppc64el s390x sh4 sparc64 x32"}

set -e

for arch in ${ARCHS}; do
    mkdir -p "${arch}/slim"

    # arch
    if [ ! -f "${arch}/arch" ]; then
	echo "${arch}" > "${arch}/arch"
    fi
    qemu_arch=$(cat "${arch}/qemu_arch")

    # deb
    if [ ! -f "${arch}/deb" ]; then
	(
	    set -x
	    curl -s https://packages.debian.org/sid/${arch}/busybox-static/download | tr '"' "\n" | grep -E "http://.*${arch}\\.deb" > "${arch}/deb"
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
    if [ ! -f "${arch}/slim/rootfs/bin/busybox" ]; then
	(
	    cd "${arch}"
	    set -x
	    ar vx busybox-static.deb data.tar.xz data.tar.gz
	    tar --strip=2 -xvf data.tar.* ./bin/busybox
	    mkdir -p ./slim/rootfs/bin
	    mv ./busybox ./slim/rootfs/bin/
	)
    fi

    # create symlinks
    if [ ! -f "${arch}/slim/rootfs/bin/ls" ]; then
	(
	    cd "${arch}/slim/rootfs"
	    echo "This need binfmt to be configured"
	    echo "  docker run --rm --privileged multiarch/qemu-user-static:register --reset."
	    for module in $("./bin/busybox" --list-modules); do
		mkdir -p "$(dirname $module)"
		ln -s /bin/busybox "${module}"
	    done
	)
    fi

    # create dirs and files
    if [ ! -d "${arch}/slim/rootfs/dev" ]; then
	(
	    cd "${arch}/slim/rootfs"
	    set -x
	    mkdir -p bin etc dev dev/pts lib proc sys tmp
	    cp /etc/nsswitch.conf etc/nsswitch.conf
	    echo root:x:0:0:root:/:/bin/sh > etc/passwd
	    echo root:x:0: > etc/group
	)
    fi

    # create archive
    if [ ! -f "${arch}/slim/rootfs.tar.xz" ]; then
	(
	    cd "${arch}/slim/rootfs"
	    set -x
	    tar --numeric-owner -cJf ../rootfs.tar.xz .
	)
    fi
    
    if [ -n "${qemu_arch}" -a ! -f "${arch}/qemu-${qemu_arch}-static.tar.xz" ]; then
	wget https://github.com/multiarch/qemu-user-static/releases/download/v2.0.0/amd64_qemu-${qemu_arch}-static.tar.xz -O "${arch}/qemu-${qemu_arch}-static.tar.xz"
    fi

    # create Dockerifle
    cat > "${arch}/slim/Dockerfile" <<EOF
FROM scratch
ADD rootfs.tar.xz /
CMD ["/bin/sh"]
ENV ARCH=${arch}
EOF
    if [ "${qemu_arch}" = "" ]; then
	cat > "${arch}/Dockerfile" <<EOF
FROM multiarch/busybox:${arch}-slim
EOF
    else
	cat > "${arch}/Dockerfile" <<EOF
FROM multiarch/busybox:${arch}-slim
ADD qemu-${qemu_arch}-static.tar.xz /usr/bin
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
    echo "qemu_arch=$qemu_arch"
    echo "deb=$deb"
    (
	set -x
	ls -la "${arch}/busybox-static.deb"
	du -hs "${arch}/slim/rootfs"
	find "${arch}/slim/rootfs" -type f | wc -l
	ls -la "${arch}/slim/rootfs.tar.xz"
    )

    # build & test
    (
	set -x
	docker build -t "multiarch/busybox:${arch}-slim" "${arch}/slim"
	docker build -t "multiarch/busybox:${arch}" "${arch}"
	if [ -n "${qemu_arch}" -o "${arch}" = "amd64" ]; then
	    docker run -it --rm "multiarch/busybox:${arch}" uname -a
	fi
    )

done
