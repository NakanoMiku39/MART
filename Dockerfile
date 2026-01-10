FROM crmirror.lcpu.dev/docker.io/ubuntu:22.04 AS builder

WORKDIR /riscv

COPY MART.zip .

ENV WORK_DIR=/riscv \
 TOOLCHAIN_PKG_DIR=/riscv/MART/packages/toolchain \
 GEM5_PKG_DIR=/riscv/MART/packages/gem5 \
 BOOM_PKG_DIR=/riscv/MART/packages/chipyard \
 MIBENCH_PKG_DIR=/riscv/MART/packages \
 INSTALL_DIR=/riscv/install \
 TOOLCHAIN_SRC_DIR=/riscv/riscv-toolchain \
 PATH=/riscv/install/rv64g/bin:/riscv/install/all/bin:$PATH \
 RISCV=/riscv/install/rv64g \
 CIRCT_SRC_DIR=/riscv/circt-481cb60
 
ARG DEBIAN_FRONTEND=noninteractive

RUN sed -ri.bak -e 's/\/\/.*?(archive.ubuntu.com|mirrors.*?)\/ubuntu/\/\/mirrors.pku.edu.cn\/ubuntu/g' -e '/security.ubuntu.com\/ubuntu/d' /etc/apt/sources.list && \
apt-get update && apt-get upgrade -y && apt-get install autoconf automake autotools-dev curl python3 python3-pip \
    libmpc-dev libmpfr-dev libgmp-dev gawk build-essential \
    bison flex texinfo gperf libtool patchutils bc zlib1g zlib1g-dev \
    libexpat-dev ninja-build git cmake libglib2.0-dev libslirp-dev \
    python3-venv python3-tomli zip m4 scons libprotobuf-dev protobuf-compiler libprotoc-dev libgoogle-perftools-dev \
    openjdk-8-jdk make gtkwave device-tree-compiler help2man jq gpg -y

RUN echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | tee /etc/apt/sources.list.d/sbt.list && \
echo "deb https://repo.scala-sbt.org/scalasbt/debian /" | tee /etc/apt/sources.list.d/sbt_old.list && \
curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x2EE0EA64E40A89B84B2DF73499E82A75642AC823" |  apt-key add && apt update && apt-get install sbt -y

# riscv-toolchain
RUN unzip MART.zip && cd $WORK_DIR && mkdir -p $INSTALL_DIR && mkdir riscv-toolchain && cd riscv-toolchain && \
    unzip $TOOLCHAIN_PKG_DIR/riscv-gnu-toolchain-2024.11.22.zip && \
    tar xf $TOOLCHAIN_PKG_DIR/binutils-2.43.tar.xz && \
    tar xf $TOOLCHAIN_PKG_DIR/gcc-14.2.0.tar.xz && \
    tar xf $TOOLCHAIN_PKG_DIR/glibc-2.40.tar.xz && \
	tar xf $TOOLCHAIN_PKG_DIR/newlib-4.4.0.20231231.tar.gz

RUN cd $TOOLCHAIN_SRC_DIR/riscv-gnu-toolchain-2024.11.22 && \
./configure --prefix=$INSTALL_DIR/rv64g \
--with-arch=rv64g \
--with-abi=lp64d \
--with-cmodel=medany \
--disable-gdb \
--disable-multilib \
--with-binutils-src=$TOOLCHAIN_SRC_DIR/binutils-2.43 \
--with-gcc-src=$TOOLCHAIN_SRC_DIR/gcc-14.2.0 \
--with-glibc-src=$TOOLCHAIN_SRC_DIR/glibc-2.40 \
--with-newlib-src=$TOOLCHAIN_SRC_DIR/newlib-4.4.0.20231231 && \
make -j 1 && \
make linux -j 1

# QEMU
RUN cd $WORK_DIR && tar xf $TOOLCHAIN_PKG_DIR/qemu-9.2.0.tar.xz && \
    mkdir build-qemu && cd build-qemu && \
    ../qemu-9.2.0/configure --prefix=$INSTALL_DIR/all --target-list=riscv64-linux-user --enable-plugins --disable-docs && \
    make -j 4 && \
    make install && \
    cp contrib/plugins/*.so $INSTALL_DIR/all/share/qemu/

# GEM5
RUN cd $WORK_DIR && unzip $GEM5_PKG_DIR/gem5-24.0.0.1.zip && cd gem5-24.0.0.1 && \
    patch -p1 < $GEM5_PKG_DIR/gem5--fix-syscall258.patch && patch -p1 < $GEM5_PKG_DIR/gem5--fix-renameat2.patch && \
    scons build/RISCV/gem5.opt -j 4

# Verilator
RUN cd $WORK_DIR && unzip $BOOM_PKG_DIR/verilator-5.030.zip && cd verilator-5.030/ && \
    autoconf && ./configure --prefix=$INSTALL_DIR/all && \
    make -j 4 && make install && cd ..

# Spike
RUN unzip $BOOM_PKG_DIR/riscv-isa-sim-de5094a.zip && \
    mv riscv-isa-sim-de5094a1a901d77ff44f89b38e00fefa15d4018e riscv-isa-sim-de5094a && cd riscv-isa-sim-de5094a && \
    mkdir build && cd build && \
    ../configure --prefix=$RISCV --with-boost=no --with-boost-asio=no --with-boost-regex=no && \
    make && make install && cd ../..

# Proxy kernel
RUN unzip $BOOM_PKG_DIR/riscv-pk-1a52fa4.zip && mv riscv-pk-1a52fa44aba49307137ea2ad5263613da33a877b riscv-pk-1a52fa4 && cd riscv-pk-1a52fa4 && \
    mkdir build && cd build && \
    ../configure --prefix=$RISCV --host=riscv64-unknown-elf --with-arch=rv64g_zifencei && \
    make && make install && cd ../..

# RISCV tests
RUN unzip $BOOM_PKG_DIR/riscv-tests-0494f95.zip && mv riscv-tests-0494f954a3d8d2ca9e4972da7a01e94b6a909bce riscv-tests-0494f95 && cd riscv-tests-0494f95 && \
    unzip $BOOM_PKG_DIR/riscv-test-env-4fabfb4.zip && mv riscv-test-env-4fabfb4e0d3eacc1dc791da70e342e4b68ea7e46 riscv-test-env-4fabfb4 && rm -r env && ln -s riscv-test-env-4fabfb4/ env && \
    mkdir build && cd build && ../configure --prefix=$RISCV/riscv64-unknown-elf --with-xlen=64 && \
    make && make install && cd ../..

# Libgloss
RUN unzip $BOOM_PKG_DIR/libgloss-htif-39234a1.zip && mv libgloss-htif-39234a16247ab1fa234821b251f1f1870c3de343 libgloss-39234a1 && cd libgloss-39234a1/ && \
    mkdir build && cd build && ../configure --prefix=$RISCV/riscv64-unknown-elf --host=riscv64-unknown-elf && \
    make && make install && cd ../..

## CIRCT & LLVM
RUN unzip $BOOM_PKG_DIR/circt-481cb60.zip && mv circt-481cb60add7358934414a3c6b396f5d29ad934fe circt-481cb60 && cd circt-481cb60/ && \
    unzip $BOOM_PKG_DIR/llvm-project-b52160d.zip && mv llvm-project-b52160dbae268cc87cb8f6cdf75553ca095e26a9 llvm-project-b52160d && rm -r llvm && ln -s llvm-project-b52160d/ llvm && \
    mkdir llvm/build && cd llvm/build/ && \
    cmake -G Ninja ../llvm \
    -DLLVM_ENABLE_PROJECTS="mlir" \
    -DLLVM_TARGETS_TO_BUILD="host" \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DCMAKE_BUILD_TYPE=RELEASE \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON && \
    ninja -j 4 && cd ../.. && \
    mkdir build && cd build && \
    cmake -G Ninja .. \
    -DMLIR_DIR=$CIRCT_SRC_DIR/llvm/build/lib/cmake/mlir \
    -DLLVM_DIR=$CIRCT_SRC_DIR/llvm/build/lib/cmake/llvm \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DCMAKE_BUILD_TYPE=RELEASE \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR/all && \
    ninja -j 4 && ninja install

# Rocket & BOOM
RUN cd $WORK_DIR && unzip $BOOM_PKG_DIR/chipyard-boom-master.zip && mv chipyard-boom-master-c0ac721c5ad0a051a6b8714f2b99f3dc477da264 chipyard-boom && cd chipyard-boom && \
tar -xf packages/chipyard-1.13.0.tar.gz && \ 
    mkdir modules && ./unpack-submodules.sh submodules.lst chipyard-1.13.0/ packages/ modules/ && \
    unzip $BOOM_PKG_DIR/riscv-boom-d2a64f7.zip && mv riscv-boom-d2a64f7ca9fd914d9c686cb23edcd32d3465a02e riscv-boom-d2a64f7 && rm -r chipyard-1.13.0/generators/boom/ && \
    ln -s $(realpath ./riscv-boom-d2a64f7) chipyard-1.13.0/generators/boom && \
    cd chipyard-1.13.0 && cd sims/verilator/ && \
    make && ./simulator-chipyard.harness-RocketConfig $INSTALL_DIR/rv64g/riscv64-unknown-elf/share/riscv-tests/isa/rv64ui-p-simple && \
    make CONFIG=MediumBoomV3Config && ./simulator-chipyard.harness-MediumBoomV3Config $INSTALL_DIR/rv64g/riscv64-unknown-elf/share/riscv-tests/isa/rv64ui-p-simple

# Cleanup - remove build directories
RUN rm -rf $TOOLCHAIN_SRC_DIR/riscv-gnu-toolchain-2024.11.22/build-* && \
    rm -rf build-qemu && \
    cd verilator-5.030 && make clean && cd .. && \
    rm -rf riscv-isa-sim-de5094a/build && \
    rm -rf riscv-pk-1a52fa4/build && \
    rm -rf riscv-tests-0494f95/build && \
    rm -rf libgloss-39234a1/build && \
    rm -rf $CIRCT_SRC_DIR/build && \
    rm -rf $CIRCT_SRC_DIR/llvm/build


FROM crmirror.lcpu.dev/docker.io/ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN sed -ri.bak -e 's/\/\/.*?(archive.ubuntu.com|mirrors.*?)\/ubuntu/\/\/mirrors.pku.edu.cn\/ubuntu/g' -e '/security.ubuntu.com\/ubuntu/d' /etc/apt/sources.list && \
apt-get update && apt-get upgrade -y && apt-get install autoconf automake autotools-dev curl python3 python3-pip \
    libmpc-dev libmpfr-dev libgmp-dev gawk build-essential \
    bison flex texinfo gperf libtool patchutils bc zlib1g zlib1g-dev \
    libexpat-dev ninja-build git cmake libglib2.0-dev libslirp-dev \
    python3-venv python3-tomli zip m4 scons libprotobuf-dev protobuf-compiler libprotoc-dev libgoogle-perftools-dev \
    openjdk-8-jdk make gtkwave device-tree-compiler help2man jq gpg -y

RUN echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | tee /etc/apt/sources.list.d/sbt.list && \
echo "deb https://repo.scala-sbt.org/scalasbt/debian /" | tee /etc/apt/sources.list.d/sbt_old.list && \
curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x2EE0EA64E40A89B84B2DF73499E82A75642AC823" |  apt-key add && apt update && apt-get install sbt -y

ENV WORK_DIR=/riscv \
    INSTALL_DIR=/riscv/install \
    PATH=/riscv/install/rv64g/bin:/riscv/install/all/bin:$PATH \
    RISCV=/riscv/install/rv64g

WORKDIR /riscv

COPY --from=builder /riscv /riscv
CMD ["/bin/bash"]