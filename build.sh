#!/bin/bash
# ============================================================
#  Samsung Galaxy A32 (SM-A325F)
#  KernelSU Next + SUSFS (FINAL)
#  Target: GitHub Actions / Ubuntu
# ============================================================

set -e

# ================= USER CONFIG =================
DEVICE="A32F"
DEFCONFIG="a32_defconfig"     # GANTI jika defconfig beda
JOBS=$(nproc)

# ================= PATH =================
KERNEL_DIR=$(pwd)
OUT_DIR="$KERNEL_DIR/out"
CLANG_DIR="$KERNEL_DIR/proton-clang"
KSU_DIR="$KERNEL_DIR/kernelsu-next"
SUSFS_DIR="$KERNEL_DIR/susfs"

# ================= TOOLCHAIN =================
if [ ! -d "$CLANG_DIR" ]; then
    echo "[*] Cloning Proton-Clang..."
    git clone https://github.com/kdrag0n/proton-clang.git
fi
export PATH="$CLANG_DIR/bin:$PATH"

# ================= ENV =================
export ARCH=arm64
export SUBARCH=arm64
export CC=clang
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export STRIP=llvm-strip
export KBUILD_BUILD_USER="KernelSU"
export KBUILD_BUILD_HOST="Linux"

# ================= CLEAN =================
echo "[*] Cleaning output..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# ================= DEFCONFIG =================
echo "[*] Loading defconfig: $DEFCONFIG"
make O="$OUT_DIR" "$DEFCONFIG"

# ============================================================
#  KernelSU Next
# ============================================================
if [ ! -d "$KSU_DIR" ]; then
    echo "[*] Cloning KernelSU Next..."
    git clone https://github.com/KernelSU-Next/KernelSU-Next.git "$KSU_DIR"
fi

echo "[*] Injecting KernelSU Next..."
rm -rf drivers/kernelsu
cp -r "$KSU_DIR/kernel" drivers/kernelsu

# Register KernelSU in Makefile
grep -q "kernelsu" drivers/Makefile || \
    echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile

# Register KernelSU in Kconfig
grep -q "drivers/kernelsu/Kconfig" drivers/Kconfig || \
cat <<EOF >> drivers/Kconfig

source "drivers/kernelsu/Kconfig"
EOF

# ============================================================
#  SUSFS
# ============================================================
if [ ! -d "$SUSFS_DIR" ]; then
    echo "[*] Cloning SUSFS..."
    git clone https://github.com/KernelSU-Next/susfs.git "$SUSFS_DIR"
fi

echo "[*] Injecting SUSFS..."
rm -rf drivers/susfs
cp -r "$SUSFS_DIR/kernel" drivers/susfs

# Register SUSFS in Makefile
grep -q "susfs" drivers/Makefile || \
    echo 'obj-$(CONFIG_SUSFS) += susfs/' >> drivers/Makefile

# Register SUSFS in Kconfig
grep -q "drivers/susfs/Kconfig" drivers/Kconfig || \
cat <<EOF >> drivers/Kconfig

source "drivers/susfs/Kconfig"
EOF

# ============================================================
#  CONFIGURATION (KernelSU + SUSFS)
# ============================================================
echo "[*] Enabling KernelSU + SUSFS configs..."

CONFIG="$OUT_DIR/.config"

scripts/config --file "$CONFIG" \
    -e CONFIG_KSU \
    -e CONFIG_SUSFS \
    -e CONFIG_KALLSYMS \
    -e CONFIG_KALLSYMS_ALL \
    -e CONFIG_FHANDLE \
    -e CONFIG_PROC_FS \
    -e CONFIG_SYSFS \
    -e CONFIG_TMPFS \
    -e CONFIG_SECURITY \
    -e CONFIG_SECURITY_SELINUX \
    -e CONFIG_SECURITY_SELINUX_BOOTPARAM \
    -e CONFIG_DEFAULT_SECURITY_SELINUX \
    -d CONFIG_OVERLAY_FS

# Finalize config
make O="$OUT_DIR" olddefconfig

# ============================================================
#  BUILD
# ============================================================
echo "[*] Building kernel..."
make -j"$JOBS" \
    O="$OUT_DIR" \
    LLVM=1 \
    LLVM_IAS=1

# ================= RESULT =================
IMAGE="$OUT_DIR/arch/arm64/boot/Image.gz"

echo "================================================"
if [ -f "$IMAGE" ]; then
    echo "[✓] BUILD SUCCESS"
    echo "[✓] Kernel Image: $IMAGE"
else
    echo "[✗] BUILD FAILED"
    exit 1
fi
echo "================================================"
