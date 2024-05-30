#!/usr/bin/env bash

echo -e "Install Necessary Packages"
sudo apt-get install binutils bzip2 flex gawk gcc grep libc-dev libz-dev make perl python3 rsync subversion unzip tar -y

WORK_DIR="$(pwd)"
SDK_DIR="${WORK_DIR}/openwrt-sdk"
# OPENWRT_BASE_URL="https://downloads.openwrt.org/releases" #Official
OPENWRT_BASE_URL="https://mirrors.cicku.me/openwrt/releases" #Cloudflare
OPENWRT_GITHUB_URL="https://github.com/openwrt/openwrt/releases/latest"

raw_version=$(curl -Ls -o /dev/null -w %{url_effective} ${OPENWRT_GITHUB_URL} | rev | cut -d "/" -f 1 | rev)
version=${raw_version//[^0-9.]/}

latest_url="${OPENWRT_BASE_URL}/${version}/targets/x86/64/"

latest_html=$(curl -s $latest_url | grep openwrt-sdk)
sdk_filename=$(echo -e ${latest_html//\"/\\n} | grep -E "openwrt-sdk.*\.xz$")
sdk_url=${latest_url}/${sdk_filename}

echo -e "Download OpenWrt SDK"
curl  -L ${sdk_url} -o ${sdk_filename}


echo -e "Extracting"
mkdir ${SDK_DIR}
tar -xf ${sdk_filename} -C ${SDK_DIR} --strip-components=1
rm -rf ${sdk_filename}

echo -e "Add Repository"
grep -v '^#' ${WORK_DIR}/feeds.conf | awk '{print $2}' > keywords.txt
awk 'BEGIN { while (getline < "keywords.txt") keys[$1] = 1 }
     /^#/ { print; next }
     { split($2, a, " "); if (a[1] in keys) print "#" $0; else print $0 }' ${SDK_DIR}/feeds.conf.default > temp.txt
rm -rf keywords.txt
mv temp.txt ${SDK_DIR}/feeds.conf.default
echo -e "# Official:\n$(cat ${SDK_DIR}/feeds.conf.default)\n\n" >${SDK_DIR}/feeds.conf.default
echo -e "# Third Party:\n$(cat ${WORK_DIR}/feeds.conf)" >> ${SDK_DIR}/feeds.conf.default

echo -e "Update Feeds"
cd ${SDK_DIR}
./scripts/feeds clean
./scripts/feeds update -a || true
./scripts/feeds install -a || true
rm -rf .config ./tmp

echo -e "Configure"
make defconfig


echo -e "Compile"
make -j"$(nproc)" package/feeds/luci/luci-base/compile
for src_dir in package/feeds/*; do
    [[ -d "${src_dir}" ]] || continue
    _build=1
    for official in base luci packages routing telephony; do
        if [[ ${src_dir} == "package/feeds/$official" || ${src_dir} == "package/feeds/$official/" ]]; then
            _build=0
            break
        fi
    done
    if [[ "${_build}" -gt 0 ]]; then
        for pkg in "${src_dir}"/*; do
            [[ -d ${pkg} ]] || continue
            make -j"$(nproc)" "${pkg}"/compile || true
        done
    fi
done