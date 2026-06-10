set -e
git config --global user.name dongkuk
git config --global user.email dongkuk@mobilint.com
git config --global credential.helper store

# mobilint compiler
cd /workspace
git clone http://git.mobilint.com/algorithm-team/compiler/mobilint-compiler.git
cd /workspace/mobilint-compiler
mkdir build
cd build
cmake ..
make -j16

# qbcompiler
cd /workspace
git clone http://git.mobilint.com/algorithm-team/compiler/qbcompiler.git
cp /workspace/mobilint-compiler/build/src/compiler/mmc.cpython-310-x86_64-linux-gnu.so qbcompiler/src/qbcompiler

# quantizer
cd /workspace
git clone http://git.mobilint.com/algorithm-team/compiler/quantizer.git
cd /workspace/quantizer
mkdir build
cd build
cmake ..
make -j16
