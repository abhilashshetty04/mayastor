{ binutils
, cunit
, fetchFromGitHub
, pkgconfig
, lcov
, libaio
, libiscsi
, liburing
, libuuid
, nasm
, ninja
, meson
, ncurses
, numactl
, openssl
, python3
, stdenv
, system ? builtins.currentSystem
}:
let
  # Derivation attributes for production version of libspdk
  drvAttrs = rec {
    version = "21.01";

    src = fetchFromGitHub {
      owner = "openebs";
      repo = "spdk";
      rev = "37164626e403cca75afac7e8a47cd53b730bc921";
      sha256 = "0gkdqqs990hgblz0rlkg8355klxnxi2cdvy5p6ws9nqz8cxwrg14";
      #sha256 = stdenv.lib.fakeSha256;
      fetchSubmodules = true;
    };

    nativeBuildInputs = [
      meson
      ninja
      pkgconfig
      python3
    ];

    buildInputs = [
      binutils
      libaio
      libiscsi.dev
      liburing
      libuuid
      nasm
      ncurses
      numactl
      openssl
    ];

    configureFlags = (if (system == "x86_64-linux") then 
      [
        "--target-arch=nehalem"
        "--with-crypto"
      ]
    else
      []
    ) ++ [
      "--without-isal"
      "--with-iscsi-initiator"
      "--with-uring"
      "--disable-examples"
      "--disable-unit-tests"
      "--disable-tests"
    ];

    enableParallelBuilding = true;

    preConfigure = ''
      substituteInPlace dpdk/config/defconfig_x86_64-native-linux-gcc --replace native default
    '';

    configurePhase = ''
      patchShebangs ./.
      ./configure $configureFlags
    '';

    hardeningDisable = [ "all" ];

    buildPhase = ''
      make -j`nproc`
      find . -type f -name 'libspdk_event_nvmf.a' -delete
      find . -type f -name 'libspdk_sock_uring.a' -delete
      find . -type f -name 'libspdk_ut_mock.a' -delete

      $CC -shared -o libspdk.so \
        -lc  -laio -liscsi -lnuma -ldl -lrt -luuid -lpthread -lcrypto \
        -luring \
        -Wl,--whole-archive \
        $(find build/lib -type f -name 'libspdk_*.a*' -o -name 'librte_*.a*') \
        $(find dpdk/build/lib -type f -name 'librte_*.a*') \
        $(find intel-ipsec-mb -type f -name 'libIPSec_*.a*') \
        -Wl,--no-whole-archive
    '';

    installPhase = ''
      mkdir -p $out/lib
      mkdir $out/bin

      pushd include
      find . -type f -name "*.h" -exec install -D "{}" $out/include/{} \;
      popd

      pushd lib
      find . -type f -name "*.h" -exec install -D "{}" $out/include/spdk/lib/{} \;
      popd

      # copy private headers from bdev modules needed for creating of bdevs
      pushd module
      find . -type f -name "*.h" -exec install -D "{}" $out/include/spdk/module/{} \;
      popd

      # copy over the library
      cp libspdk.so $out/lib

      echo $(find $out -type f -name '*.a*' -delete)
      find . -executable -type f -name 'bdevperf' -exec install -D "{}" $out/bin \;
    '';
  };
in
{
  release = stdenv.mkDerivation (drvAttrs // {
    pname = "libspdk";
    separateDebugInfo = true;
    dontStrip = false;
    configureFlags = drvAttrs.configureFlags ++ [
      "--disable-tests"
      "--disable-unit-tests"
    ];
  });
  debug = stdenv.mkDerivation (drvAttrs // {
    pname = "libspdk-dev";
    separateDebugInfo = false;
    dontStrip = true;
    buildInputs = drvAttrs.buildInputs ++ [ cunit lcov ];
    configureFlags = drvAttrs.configureFlags ++ [
      "--enable-debug"
    ];
    installPhase = drvAttrs.installPhase + ''
      echo "Copying test files"
      cp -ar test $out/test
    '';
  });
}
