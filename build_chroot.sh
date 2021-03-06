#!/bin/bash

if ! [ $# -eq 2 ]; then
    cat - <<EOF
    Usage: $0 toolchain_name buildroot-treeish

toolchain_name:
        This is a path to a toolchain fragment. '.config' will be appended to
        that path, and it will be copied as is to Buildroot's '.config' file.

buildroot-treeish:
        The git tree-ish object in which to checkout Buildroot to before
        building the toolchain.
EOF
    exit 1
fi

name=$1
brcommit=$2

apt-get install -y --force-yes -qq --no-install-recommends \
    build-essential locales bc ca-certificates file rsync gcc-multilib \
    git bzr cvs mercurial subversion unzip wget cpio curl git-core \
    libc6-i386 2>&1 1>/dev/null
if [ $? -ne 0 ] ; then
	echo "Package installation failed, aborting"
	exit 1
fi

sed -i 's/# \(en_US.UTF-8\)/\1/' /etc/locale.gen
/usr/sbin/locale-gen

cd /tmp

TOOLCHAIN_DIR=$(pwd)
TOOLCHAIN_BUILD_DIR=${TOOLCHAIN_DIR}
TOOLCHAIN_BR_DIR=${TOOLCHAIN_DIR}/buildroot

toolchaindir=${TOOLCHAIN_BUILD_DIR}/${name}
logfile=${TOOLCHAIN_BUILD_DIR}/${name}-build.log
builddir=${TOOLCHAIN_BUILD_DIR}/output
configfile=${builddir}/.config

git clone https://github.com/free-electrons/buildroot-toolchains.git ${TOOLCHAIN_BR_DIR}
if [ $? -ne 0 ] ; then
	exit 1
fi

cd ${TOOLCHAIN_BR_DIR}
echo "Checking out commit: ${brcommit}"
git checkout ${brcommit}
if [ $? -ne 0 ] ; then
	exit 1
fi
cd ${TOOLCHAIN_DIR}

git --git-dir=${TOOLCHAIN_BR_DIR}/.git describe > br_version
echo "Buildroot version: " $(cat br_version)

mkdir -p ${TOOLCHAIN_BUILD_DIR} &>/dev/null

function build {
    # Create output directory for the new toolchain
    rm -rf ${toolchaindir}
    mkdir ${toolchaindir}

    # Create build directory for the new toolchain
    rm -rf ${builddir}
    mkdir ${builddir}

    # Create the configuration
    cp ${name}.config ${configfile}
    echo "BR2_HOST_DIR=\"${toolchaindir}\"" >> ${configfile}

    echo "  starting at $(date)"

    # Generate the full configuration
    make -C ${TOOLCHAIN_BR_DIR} O=${builddir} olddefconfig > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
	    return 1
    fi

    # Generate fragment to ship in the README
    make -C ${TOOLCHAIN_BR_DIR} O=${builddir} savedefconfig > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
	    return 1
    fi

    echo "=================== BEGIN DEFCONFIG ======================"
    cat ${builddir}/defconfig
    echo "==================== END DEFCONFIG ======================="

    # Build
    timeout 225m make -C ${TOOLCHAIN_BR_DIR} O=${builddir} 2>&1 | tee ${logfile} | grep --colour=never ">>>"
    if [ $? -ne 0 ] ; then
        echo "  finished at $(date) ... FAILED"
        echo "  printing the end of the logs before exiting"
        echo "=================== BEGIN LOG FILE ======================"
        tail -n 200 ${logfile}
        echo "==================== END LOG FILE ======================="
        return 1
    fi

    echo "  finished at $(date) ... SUCCESS"

    # Making legals
    echo "  making legal infos at $(date)"
    make -C ${TOOLCHAIN_BR_DIR} O=${builddir} legal-info > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
	    return 1
    fi
    echo "  finished at $(date)"

    cp ${configfile} ${toolchaindir}/buildroot.config

    # Different versions of buildroot don't always product the same thing with
    # usr. Old version make usr to be a folder containing the toolchain, newer
    # version just make it a symbolic link for compatibility.
    if ! [ -L ${toolchaindir}/usr ]; then
        mv ${toolchaindir}/usr/* ${toolchaindir}/
        rmdir ${toolchaindir}/usr
    else
        make -C ${TOOLCHAIN_BR_DIR} O=${builddir} sdk
        if [ $? -ne 0 ] ; then
		return 1
        fi
        rm ${toolchaindir}/usr
    fi
    # Toolchain built
}

echo "Generating ${name}..."
if ! build $1; then
    echo "Error in toolchain build. Exiting"
    exit 1
fi


