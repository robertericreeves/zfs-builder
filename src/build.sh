#!/bin/bash
#
# Copyright The Titan Project Contributors.
#

set -xe

. $(dirname $0)/common.sh

# Check if ZFS is already available in the system
function check_zfs_availability() {
    echo "Checking if ZFS is already available..."
    
    # Check if ZFS filesystem is supported in kernel
    if grep -q "^nodev.*zfs" /proc/filesystems 2>/dev/null; then
        echo "✓ ZFS kernel support detected"
        ZFS_KERNEL_AVAILABLE=1
    else
        echo "✗ ZFS kernel support not found"
        ZFS_KERNEL_AVAILABLE=0
    fi
    
    # Check if ZFS device node exists
    if [ -c /dev/zfs ]; then
        echo "✓ ZFS device node (/dev/zfs) available"
        ZFS_DEVICE_AVAILABLE=1
    else
        echo "✗ ZFS device node (/dev/zfs) not found"
        ZFS_DEVICE_AVAILABLE=0
    fi
    
    # Check if ZFS userspace tools are available
    if command -v zpool >/dev/null 2>&1; then
        echo "✓ ZFS userspace tools (zpool) available"
        ZFS_USERSPACE_AVAILABLE=1
    else
        echo "✗ ZFS userspace tools not found"
        ZFS_USERSPACE_AVAILABLE=0
    fi
    
    # Check if we have complete ZFS support
    if [ "$ZFS_KERNEL_AVAILABLE" = "1" ] && [ "$ZFS_DEVICE_AVAILABLE" = "1" ] && [ "$ZFS_USERSPACE_AVAILABLE" = "1" ]; then
        echo "🎉 Complete ZFS support detected! No kernel build needed."
        return 0
    else
        echo "⚠️  Incomplete ZFS support detected. Kernel build required."
        return 1
    fi
}

function get_kernel_vars() {
    [ -z "$KERNEL_RELEASE" ] && KERNEL_RELEASE=$(uname -r)
    [ -z "$KERNEL_UNAME" ] && KERNEL_UNAME=$(uname -a)
    KERNEL_VERSION=${KERNEL_RELEASE%%-*}
    KERNEL_VARIANT=${KERNEL_RELEASE#*-}
}

function get_kernel_type() {
    case $KERNEL_VARIANT in
    linuxkit)
        echo linuxkit
        ;;
    microsoft-standard*)
        echo wsl
        ;;
    *)
        case $KERNEL_UNAME in
        *Ubuntu*)
            echo ubuntu
            ;;
        *.el[0-9].*)
            echo centos
            ;;
        *.el8_[0-9].*)
	    echo centos8x
            ;;
        *)
            echo vanilla
            ;;
        esac
    esac
}

if [ "$ZFS_CONFIG" != "user" ]; then
    get_kernel_vars
    kernel_type=$(get_kernel_type)
    
    # Check if ZFS is already available before building
    echo "Starting ZFS availability check..."
    if check_zfs_availability; then
        echo "ZFS is already fully available - skipping kernel build"
        echo "Current kernel: $(uname -r)"
        echo "ZFS support: COMPLETE"
        echo "No build required!"
        exit 0
    fi
    
    echo "ZFS not fully available - proceeding with kernel build for type: $kernel_type"
else
    kernel_type=vanilla
fi

. $(dirname $0)/$kernel_type.sh
build
