# 🛠️ PREEMPT-RT Patch Guide for PetaLinux 2023.1 on Kria KR260

## ✅ Step-by-Step Instructions

### 1. Check Current Kernel Version
```bash
uname -r
# Should return something like: 6.1.5-xilinx-v2023.1
```

---

### 2. Clone the Xilinx Kernel Source
```bash
# Personally preference to use something like this
cd <project_root>/<RTpatch>

# Clone the official Xilinx Linux kernel repo
git clone https://github.com/Xilinx/linux-xlnx.git

# Rename the folder to match the PetaLinux version
sudo mv linux-xlnx linux-xlnx-2023_1

cd linux-xlnx-2023_1
```

### 3. Add the PREEMPT-RT Upstream Remote
```bash
git remote add rt_origin https://git.kernel.org/pub/scm/linux/kernel/git/rt/linux-rt-devel.git
git remote update
git checkout xilinx-v2023.1
```

### 4. Merge the RT Patch Version (`v6.1-rc7-rt5`)
```bash
git merge v6.1-rc7-rt5
git checkout --ours drivers/net/ethernet/xilinx/xilinx_axienet_main.c
git add drivers/net/ethernet/xilinx/xilinx_axienet_main.c
git merge --continue
```

### 5. Apply the patch
```bash
zcat patch-6.1.5-rt15.patch.gz | patch -p1
```

### 6. Customize the project kernel
```bash
petalinux-config 
    -> Linux Components Selection
        -> (X) ext-local-src
            -> <project_root>/<RTpatch>/linux-xlnx-2023_1
# This will make the petalinux project point this new kernel with the patch

petalinux-config -c kernel
    -> General Setup
        -> Preemtion Model
            -> (X) Fully Preemtible Kernel(Real-Time)
```

### 7. Add Preemtion Tests
```bash
nano <plnx_project>/project-spec/configs/rootfsconfigs
# Add this line at the bottom
CONFIG_rt-tests

petalinux-config -c rootfs
#now you should see it under rootfs config under user packages
# make sure its enabled
```
