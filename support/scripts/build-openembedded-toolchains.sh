#!/bin/bash
#
# Open-Embedded SDK Toolchain Builder
# Groups machines by DEFAULTTUNE and builds only unique toolchains.
# Supports OE-Alliance, OpenDreambox, OpenPLi and other OE-based build environments.
#
# Usage: ./build-openembedded-toolchains.sh --env /path/to/build-env --branch <branch> --label <label> --output /path/to/output
#

set -o pipefail

# Defaults
ENV=""
BRANCH=""
OUTPUT=""
EXTRAS="openssl-dev openssl-staticdev libusb1-dev libusb1-staticdev libdvbcsa-dev libdvbcsa-staticdev pcsc-lite-dev curl-dev curl-staticdev"
UPLOAD=""
SSH_KEY=""
FILTER_MACHINE=""
RESUME=0
JOBS=1
VERSION=""
DOWNLOAD_URL="https://simplebuild.dedyn.io/toolchains"
LABEL="oealliance"
SCAN_ONLY=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
	echo "Open-Embedded SDK Toolchain Builder"
	echo ""
	echo "Usage: $0 [options]"
	echo ""
	echo "Required:"
	echo "  --env PATH         Path to OE build environment (git repo)"
	echo "  --branch VERSION   Branch name (e.g. 6.0, krogoth, scarthgap)"
	echo "  --output PATH      Output directory for toolchains and configs"
	echo ""
	echo "Optional:"
	echo "  --extras PKGS      SDK extra packages (quoted, space-separated)"
	echo "  --machine NAME     Build only this machine (default: all)"
	echo "  --resume           Skip already built toolchains"
	echo "  --jobs N           Parallel builds (default: 1)"
	echo "  --upload DEST      Upload destination (user@server:/path)"
	echo "  --ssh-key PATH     SSH key for upload"
	echo "  --url URL          Download base URL for toolchainfilename"
	echo "  --version VER      Version string (default: value of --branch)"
	echo "  --label NAME       Label for toolchain name (default: oealliance)"
	echo "  --scan-only        Only scan machines, don't build"
	echo ""
	echo "Example:"
	echo "  $0 --env /home/wxbet/oe-alliance/oatv-8.0 --branch 6.0 --label oealliance --output /home/wxbet/tc-output"
	echo "  $0 --env /home/wxbet/opendreambox/2.6 --branch pyro --label opendreambox --output /home/wxbet/tc-output"
	echo "  $0 --env /home/wxbet/opli --branch scarthgap --label openpli --output /home/wxbet/tc-output"
	echo "  $0 --env ... --scan-only                    # scan only, write scan.map"
	echo "  $0 --env ... --resume                        # resume, reuse cached scan.map"
	exit 1
}

log() {
	local level="$1"; shift
	local ts=$(date '+%H:%M:%S')
	case "$level" in
		INFO)  echo -e "${CYAN}[$ts]${NC} $*" >&2 ;;
		OK)    echo -e "${CYAN}[$ts]${NC} ${GREEN}$*${NC}" >&2 ;;
		WARN)  echo -e "${CYAN}[$ts]${NC} ${YELLOW}$*${NC}" >&2 ;;
		ERROR) echo -e "${CYAN}[$ts]${NC} ${RED}$*${NC}" >&2 ;;
		BUILD) echo -e "${CYAN}[$ts]${NC} ${BLUE}$*${NC}" >&2 ;;
	esac
	echo "[$ts] [$level] $*" >> "$LOGFILE"
}

# Parse arguments
while [ $# -gt 0 ]; do
	case "$1" in
		--env)       ENV="$2"; shift 2 ;;
		--branch)    BRANCH="$2"; shift 2 ;;
		--output)    OUTPUT="$2"; shift 2 ;;
		--extras)    EXTRAS="$2"; shift 2 ;;
		--machine)   FILTER_MACHINE="$2"; shift 2 ;;
		--resume)    RESUME=1; shift ;;
		--jobs)      JOBS="$2"; shift 2 ;;
		--upload)    UPLOAD="$2"; shift 2 ;;
		--ssh-key)   SSH_KEY="$2"; shift 2 ;;
		--url)       DOWNLOAD_URL="$2"; shift 2 ;;
		--version)   VERSION="$2"; shift 2 ;;
		--label)     LABEL="$2"; shift 2 ;;
		--scan-only) SCAN_ONLY=1; shift ;;
		*)           echo "Unknown option: $1"; usage ;;
	esac
done

# Validate required arguments
[ -z "$ENV" ] && echo "Error: --env is required" && usage
[ -z "$BRANCH" ] && echo "Error: --branch is required" && usage
[ -z "$OUTPUT" ] && echo "Error: --output is required" && usage
[ ! -d "$ENV" ] && echo "Error: Build environment not found: $ENV" && exit 1
[ ! -f "$ENV/Makefile" ] && echo "Error: No Makefile found in $ENV" && exit 1

# Create output directories
mkdir -p "$OUTPUT/toolchains" "$OUTPUT/toolchains.cfg" "$OUTPUT/templates" "$OUTPUT/logs"
LOGFILE="$OUTPUT/build-$(date +%F_%H%M%S).log"
SUMMARY="$OUTPUT/summary.txt"
echo "Open-Embedded SDK Toolchain Builder - $(date)" > "$SUMMARY"
echo "Environment: $ENV" >> "$SUMMARY"
echo "Branch: $BRANCH" >> "$SUMMARY"
echo "Label: $LABEL" >> "$SUMMARY"
echo "========================================" >> "$SUMMARY"

# Derive repo info from build environment
REPO_URL=$(cd "$ENV" && git remote get-url origin 2>/dev/null)
REPO_BRANCH=$(cd "$ENV" && git branch --show-current 2>/dev/null)
case "$LABEL" in
	oealliance) DISTRO="openatv" ;;
	*)          DISTRO="$LABEL" ;;
esac

log INFO "Open-Embedded SDK Toolchain Builder"
log INFO "Environment: $ENV"
log INFO "Branch: $BRANCH"
log INFO "Label: $LABEL"
log INFO "Distro: $DISTRO"
log INFO "Repo: $REPO_URL ($REPO_BRANCH)"
log INFO "Output: $OUTPUT"

# ============================================================================
# Phase 1: Machine-Liste ermitteln
# ============================================================================

get_machine_list() {
	local machines=()
	cd "$ENV"

	# Stufe 1: make list (Branch 6.0+)
	local list_output=$(make list 2>/dev/null)
	if [ -n "$list_output" ]; then
		log INFO "Using 'make list' for machine enumeration"
		while IFS= read -r line; do
			[[ "$line" =~ ^[[:space:]]*# ]] && continue
			[[ "$line" =~ ^---- ]] && continue
			local mb=$(echo "$line" | awk '{print $2}')
			local oem=$(echo "$line" | awk '{print $3}')
			[ -n "$mb" ] && [ -n "$oem" ] && machines+=("$mb:$oem")
		done <<< "$list_output"
	fi

	# Stufe 2: Makefile ifeq-Blocks parsen + direkte Machine-Configs (altes Makefile)
	if [ ${#machines[@]} -eq 0 ]; then
		log INFO "Using Makefile parsing for machine enumeration"
		declare -A ifeq_oems
		while IFS= read -r line; do
			[ -n "$line" ] && machines+=("$line")
			ifeq_oems["${line##*:}"]=1
		done < <(awk '/^else ifeq \(\$\(MACHINEBUILD\),/{
			mb=$0; gsub(/.*,/,"",mb); gsub(/\)/,"",mb);
			getline; m=$0; gsub(/MACHINE=/,"",m); gsub(/[[:space:]]/,"",m);
			if (m != "" && mb != "") print mb":"m
		}' Makefile 2>/dev/null)
		# OE-Alliance style: meta-oe-alliance/meta-brands/*/conf/machine/*.conf
		for conffile in meta-oe-alliance/meta-brands/*/conf/machine/*.conf; do
			[ -f "$conffile" ] || continue
			local oem=$(basename "$conffile" .conf)
			[ -z "${ifeq_oems[$oem]}" ] && machines+=("$oem:$oem")
		done
		# OpenPLi/other style: meta-*/conf/machine/*.conf (skip non-brand layers)
		if [ ${#machines[@]} -eq 0 ]; then
			for conffile in meta-*/conf/machine/*.conf; do
				[ -f "$conffile" ] || continue
				local layer=$(echo "$conffile" | cut -d'/' -f1)
				[[ "$layer" == meta-openembedded || "$layer" == meta-qt* || "$layer" == meta-clang || "$layer" == meta-local || "$layer" == meta-lts* ]] && continue
				local oem=$(basename "$conffile" .conf)
				machines+=("$oem:$oem")
			done
		fi
	fi

	# Filter
	if [ -n "$FILTER_MACHINE" ]; then
		local filtered=()
		for m in "${machines[@]}"; do
			local mb="${m%%:*}"
			[ "$mb" == "$FILTER_MACHINE" ] && filtered+=("$m")
		done
		machines=("${filtered[@]}")
	fi

	printf '%s\n' "${machines[@]}"
}

# ============================================================================
# Phase 1.5: Pre-Scan — ermittelt DEFAULTTUNE + KERNEL_VERSION pro OEM
# ============================================================================

# Helper: make init + source env for a machine, sets builddir as side-effect
setup_bitbake_env() {
	local machinebuild="$1"
	local oem="$2"

	cd "$ENV"
	MACHINE="$machinebuild" DISTRO=openatv DISTRO_TYPE=release make init >/dev/null 2>&1

	local bd=""
	for _p in "$ENV/builds/"*/release/$oem "$ENV/build/$oem" "$ENV/build"; do
		[ -d "$_p/conf" ] && bd="$(cd "$_p" && pwd)" && break
	done
	[ -z "$bd" ] && return 1

	if [ -f "$bd/env.source" ]; then
		source "$ENV/openembedded-core/oe-init-build-env" "$bd" >/dev/null 2>&1
		source "$bd/env.source" >/dev/null 2>&1
	elif [ -f "$ENV/bitbake.env" ]; then
		source "$ENV/bitbake.env" >/dev/null 2>&1
		cd "$bd"
	elif [ -f "$ENV/openembedded-core/oe-init-build-env" ]; then
		source "$ENV/openembedded-core/oe-init-build-env" "$bd" >/dev/null 2>&1
	fi
	command -v bitbake >/dev/null 2>&1 || export PATH="$ENV/openembedded-core/scripts:$ENV/bitbake/bin:$PATH"
	export MACHINE="$oem"
	return 0
}


# ============================================================================
# Phase 2: Toolchain bauen (pro Gruppe)
# ============================================================================

detect_bb_syntax() {
	local bb_major=$(bitbake --version 2>/dev/null | grep -oE '[0-9]+' | head -1)
	if [ -n "$bb_major" ] && [ "$bb_major" -ge 2 ] 2>/dev/null; then
		echo ":"
	else
		echo "_"
	fi
}

# Shorten tune name for use in filenames
shorten_tune() {
	local tune="$1"
	# cortexa15hf-neon-vfpv4 -> cortexa15hf
	# cortexa7hf             -> cortexa7hf
	# cortexa9hf-neon        -> cortexa9hf
	# mips32el               -> mips32el
	# mips32el-nf            -> mips32el-nf
	# aarch64                -> aarch64
	echo "$tune" | sed 's/-neon.*//; s/-vfpv.*//'
}

build_group_toolchain() {
	local group_key="$1"
	local tune="${group_key%%|*}"
	local libc_hdr="${group_key##*|}"
	local oem="$GROUP_BUILDER_OEM"
	local machinebuild="$GROUP_BUILDER_MB"
	local machines="${GROUP_MACHINES_MAP[$group_key]}"

	local tune_short=$(shorten_tune "$tune")
	local tc_name="${tune_short}_${LABEL}_${VERSION}"
	local tc_dir="$OUTPUT/toolchains/$tc_name"
	local tc_tarxz="$OUTPUT/toolchains/Toolchain-${tc_name}.tar.xz"
	local tc_cfg="$OUTPUT/toolchains.cfg/$tc_name"
	local build_log="$OUTPUT/logs/${tc_name}.log"

	# Resume check
	if [ "$RESUME" -eq 1 ] && [ -f "$tc_tarxz" ]; then
		log WARN "SKIP $tc_name (already exists)"
		echo "SKIP $tc_name (already exists)" >> "$SUMMARY"
		return 0
	fi

	local machine_count=$(echo "$machines" | wc -w)
	log BUILD "===== Building $tc_name ($machine_count OEMs, builder: $oem) ====="
	echo "" >> "$build_log"

	# 1. make init
	log INFO "[$tc_name] Running make init (MACHINE=$machinebuild)..."
	cd "$ENV"
	MACHINE="$machinebuild" DISTRO=openatv DISTRO_TYPE=release make init >> "$build_log" 2>&1
	if [ $? -ne 0 ]; then
		log ERROR "[$tc_name] make init failed"
		echo "FAIL $tc_name (make init)" >> "$SUMMARY"
		return 1
	fi

	# 2. Find build directory
	local builddir=""
	for _p in "$ENV/builds/"*/release/$oem "$ENV/build/$oem" "$ENV/build"; do
		[ -d "$_p/conf" ] && builddir="$(cd "$_p" && pwd)" && break
	done
	if [ -z "$builddir" ]; then
		builddir=$(grep -r "^TOPDIR" "$ENV/builds/"*/release/$oem/conf/*.conf "$ENV/build/"*/conf/*.conf "$ENV/build/conf/"*.conf 2>/dev/null | head -1 | sed 's/.*= *"\{0,1\}//;s/".*//')
	fi
	if [ -z "$builddir" ]; then
		builddir=$(find "$ENV" -maxdepth 5 -path "*/conf/local.conf" -exec grep -l "." {} \; 2>/dev/null | head -1 | xargs dirname | xargs dirname)
	fi
	if [ -z "$builddir" ]; then
		log ERROR "[$tc_name] Could not find build directory"
		echo "FAIL $tc_name (no build dir)" >> "$SUMMARY"
		return 1
	fi
	log INFO "[$tc_name] Build directory: $builddir"

	# 3. Source environment
	if [ -f "$builddir/env.source" ]; then
		source "$ENV/openembedded-core/oe-init-build-env" "$builddir" >> "$build_log" 2>&1
		source "$builddir/env.source" >> "$build_log" 2>&1
	elif [ -f "$ENV/bitbake.env" ]; then
		source "$ENV/bitbake.env" >> "$build_log" 2>&1
		cd "$builddir"
	elif [ -f "$ENV/openembedded-core/oe-init-build-env" ]; then
		source "$ENV/openembedded-core/oe-init-build-env" "$builddir" >> "$build_log" 2>&1
	fi
	command -v bitbake >/dev/null 2>&1 || export PATH="$ENV/openembedded-core/scripts:$ENV/bitbake/bin:$PATH"
	export MACHINE="$oem"

	# 4. Detect BitBake syntax and generate sdk-extras.conf
	local sep=$(detect_bb_syntax)
	echo "TOOLCHAIN_TARGET_TASK${sep}append = \" $EXTRAS\"" > ./sdk-extras.conf
	for _pkg in $EXTRAS; do
		case "$_pkg" in
			*-staticdev)
				local _pn="${_pkg%-staticdev}"
				echo "DISABLE_STATIC${sep}pn-${_pn} = \"\"" >> ./sdk-extras.conf
				;;
		esac
	done
	log INFO "[$tc_name] sdk-extras.conf generated (syntax: '${sep}' separator)"

	# 5. Build SDK
	log BUILD "[$tc_name] Running bitbake meta-toolchain..."
	local _status_file=$(mktemp)
	bitbake meta-toolchain -R ./sdk-extras.conf 2>&1 | tee -a "$build_log" | \
		awk -v name="$tc_name" '
		/^Currently / { printf "\r\033[K\033[0;36m[%s]\033[0m %s", name, $0 > "/dev/stderr"; fflush("/dev/stderr"); next }
		/Sstate summary:/ { printf "\r\033[K\033[0;36m[%s]\033[0m \033[0;33m%s\033[0m", name, $0 > "/dev/stderr"; fflush("/dev/stderr"); next }
		/NOTE:.*Running task/ { match($0, /\((.+)\)/, a); printf "\r\033[K\033[0;36m[%s]\033[0m \033[0;34m%s\033[0m", name, a[1] > "/dev/stderr"; fflush("/dev/stderr"); next }
		/NOTE:.*recipe.*task do_/ { sub(/NOTE: recipe /, ""); printf "\r\033[K\033[0;36m[%s]\033[0m %s", name, $0 > "/dev/stderr"; fflush("/dev/stderr"); next }
		/^ERROR:|^Summary:/ { printf "\r\033[K\033[0;31m%s\033[0m\n", $0 > "/dev/stderr"; fflush("/dev/stderr") }
		'
	local bb_exit=${PIPESTATUS[0]}
	printf "\r\033[K" >&2
	rm -f "$_status_file"
	if [ $bb_exit -ne 0 ]; then
		log ERROR "[$tc_name] bitbake meta-toolchain failed"
		echo "FAIL $tc_name (bitbake)" >> "$SUMMARY"
		return 1
	fi

	# 6. Install SDK
	[ -d "$tc_dir/sysroots" ] && rm -rf "$tc_dir"
	local sdk_sh=$(find . -path "*/deploy/sdk/*.sh" -name "*-${oem}-*" 2>/dev/null | head -1)
	[ -z "$sdk_sh" ] && sdk_sh=$(find . -path "*/deploy/sdk/*.sh" -name "*.sh" 2>/dev/null | head -1)
	if [ -z "$sdk_sh" ]; then
		log ERROR "[$tc_name] SDK installer not found"
		echo "FAIL $tc_name (no SDK installer)" >> "$SUMMARY"
		return 1
	fi
	log INFO "[$tc_name] Installing SDK: $sdk_sh"
	"$sdk_sh" -d "$tc_dir" -y >> "$build_log" 2>&1
	if [ $? -ne 0 ]; then
		log ERROR "[$tc_name] SDK install failed"
		echo "FAIL $tc_name (SDK install)" >> "$SUMMARY"
		return 1
	fi

	# 7. Post-install: bin symlink
	local env_script=$(ls "$tc_dir"/environment-setup-* 2>/dev/null | grep -v 'lib32\|multilib' | head -1)
	if [ -z "$env_script" ]; then
		log ERROR "[$tc_name] No environment-setup script found"
		echo "FAIL $tc_name (no env script)" >> "$SUMMARY"
		return 1
	fi
	local target_prefix=$(grep '^export TARGET_PREFIX=' "$env_script" | sed 's/.*=//;s/-$//')
	ln -sf "sysroots/x86_64-oesdk-linux/usr/bin/$target_prefix" "$tc_dir/bin"

	# 8. Copy relocate_sdk.py
	local rpy=$(find -L "$ENV" -name "relocate_sdk.py" 2>/dev/null | head -1)
	[ -n "$rpy" ] && cp "$rpy" "$tc_dir/relocate_sdk.py"

	# 9. Strip SDK
	log INFO "[$tc_name] Stripping SDK..."
	local hsys="$tc_dir/sysroots/x86_64-oesdk-linux"
	rm -rf "$hsys/usr/lib/locale" "$hsys/usr/share/qemu" "$hsys/usr/lib/python"* \
		"$hsys/usr/share/cmake"* "$hsys/usr/share/autoconf" "$hsys/usr/share/automake"* \
		"$hsys/usr/share/libtool" "$hsys/usr/share/gettext" "$hsys/usr/share/mime" \
		"$hsys/usr/share/gdb" "$hsys/usr/share/bison" "$hsys/usr/share/aclocal"* \
		"$hsys/usr/share/info" "$hsys/usr/share/man" "$hsys/usr/share/doc" \
		"$hsys/usr/lib/perl"* "$hsys/etc/ssl" 2>/dev/null
	find "$hsys/usr/bin" -maxdepth 1 -not -name "*-oe-linux-*" -not -name ".*" -type f -delete 2>/dev/null
	find "$hsys/usr/bin" -maxdepth 1 -not -name "*-oe-linux-*" -not -name ".*" -type l -delete 2>/dev/null
	local stripped_size=$(du -sh "$tc_dir" | cut -f1)
	log INFO "[$tc_name] Stripped size: $stripped_size"

	# 10. Extract toolchain info
	local sysroot_dir=$(basename $(grep '^export SDKTARGETSYSROOT=' "$env_script" | sed 's/.*sysroots\///;s/"//g'))
	local sysroot="sysroots/$sysroot_dir"
	local compiler="${target_prefix}-"
	local tune_ccargs=$(grep '^export OECORE_TUNE_CCARGS=' "$env_script" | sed 's/.*="//;s/"$//' | xargs)
	[ -z "$tune_ccargs" ] && tune_ccargs=$(grep '^export CC=' "$env_script" | sed 's/.*gcc //;s/ --sysroot.*//' | xargs)
	local interp=$(find "$tc_dir/$sysroot/lib" -name "ld-*.so*" -not -name "*.p" 2>/dev/null | head -1)
	local extra_ld=""
	[ -n "$interp" ] && extra_ld="-Wl,--dynamic-linker=/lib/$(basename "$interp")"
	local gcc_ver=$("$tc_dir/bin/${compiler}gcc" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
	local glibc_ver=$(strings "$tc_dir/$sysroot/lib/libc.so.6" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1 | sed 's/GLIBC_//')
	local linux_ver=$(grep '#define LINUX_VERSION_CODE' "$tc_dir/$sysroot/usr/include/linux/version.h" 2>/dev/null | awk '{printf "%d.%d.%d", $3/65536, $3%65536/256, $3%256}')
	local binutils_ver=$("$tc_dir/bin/${compiler}ld" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
	local gdb_ver=$("$tc_dir/bin/${compiler}gdb" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
	local as_ver=$("$tc_dir/bin/${compiler}as" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
	local arch=$(grep '^export ARCH=' "$env_script" 2>/dev/null | sed 's/.*=//')
	[ -z "$arch" ] && arch=$(echo "$target_prefix" | awk -F'-' '{print $1}')
	local bitness="32"
	[[ "$arch" == "aarch64" || "$arch" == "x86_64" || "$arch" == "mips64" ]] && bitness="64"
	local endianness="LE"

	local description="${LABEL} ${VERSION} ${tune}"

	# 11. Generate toolchain.cfg
	log INFO "[$tc_name] Generating toolchain.cfg..."
	local tfn=$(echo "${DOWNLOAD_URL}/\${pversion}/Toolchain-${tc_name}.tar.xz" | base64 -w0)

	cat > "$tc_cfg" << CFGEOF
_toolchainname="$tc_name";
default_use="USE_LIBCRYPTO USE_EXTRA";
extra_use="";
extra_cc="$tune_ccargs";
extra_ld="$extra_ld";
extra_c="";
_description="$description";
_oscamconfdir_default="/etc/tuxbox/config";
_oscamconfdir_custom="";
_compiler="$compiler";
_sysroot="$sysroot";
_libsearchdir="/usr/lib";
_extract_strip="0";
_toolchainfilename="$tfn";
_md5sum="pending";
_machines="$machines";
_tc_info="\n
!!! Open-Embedded-SDK Toolchain !!!\n
\n
$description\n
$arch $bitness-bit $endianness\n
gcc $gcc_ver, glibc $glibc_ver, binutils $binutils_ver, ld $binutils_ver${gdb_ver:+, gdb $gdb_ver}\n
linux $linux_ver\n";
_tc_infolines="6";
CFGEOF

	# 11b. Generate crosstool template
	local tpl_file="$OUTPUT/templates/${tc_name}"
	log INFO "[$tc_name] Generating template: $tpl_file"
	cat > "$tpl_file" << TPLEOF
#toolchain template: $description
#toolchain template version: 1
OESDK_MACHINE="$machinebuild"
OESDK_OEM=""
OESDK_DISTRO="$DISTRO"
OESDK_REPO_URL="$REPO_URL"
OESDK_REPO_BRANCH="$REPO_BRANCH"
OESDK_REPO_LOCATION="oe-sdk_${LABEL}_\${OESDK_REPO_BRANCH}"
OESDK_SDK_EXTRAS="$EXTRAS"
OESDK_MACHINES="$machines"
TPLEOF

	local stripped_size_val=$(du -sh "$tc_dir" | cut -f1)
	log OK "[$tc_name] Built! SDK: $stripped_size_val ($machine_count OEMs)"
	echo "OK   $tc_name (SDK: $stripped_size_val, $machine_count OEMs)" >> "$SUMMARY"

	return 0
}

# ============================================================================
# Main
# ============================================================================

log INFO "Phase 1: Enumerating machines..."
mapfile -t MACHINE_LIST < <(get_machine_list)

if [ ${#MACHINE_LIST[@]} -eq 0 ]; then
	log ERROR "No machines found!"
	exit 1
fi

log INFO "Found ${#MACHINE_LIST[@]} unique OEM machines"

[ -z "$VERSION" ] && VERSION="$BRANCH"
log INFO "Version: $VERSION"

# If --scan-file provided, pre-load known groups
declare -A BUILT_GROUPS       # key -> tc_name (already built)
declare -A GROUP_MACHINES_MAP # key -> space-separated OEM list
SCAN_MAP="$OUTPUT/scan.map"

# Create scan.map if it doesn't exist, keep existing entries for resume
[ ! -f "$SCAN_MAP" ] && > "$SCAN_MAP"
log INFO "Scan map: $SCAN_MAP ($(wc -l < "$SCAN_MAP") cached entries)"

# Build statistics
TOTAL=${#MACHINE_LIST[@]}
GROUPS_BUILT=0
GROUPS_SKIPPED=0
GROUPS_FAILED=0
DEDUP_SKIPPED=0

log INFO "Phase 2: Scan + Build (${TOTAL} machines)..."
echo "" >> "$SUMMARY"

for i in "${!MACHINE_LIST[@]}"; do
	entry="${MACHINE_LIST[$i]}"
	machinebuild="${entry%%:*}"
	oem="${entry##*:}"
	count=$((i + 1))

	# Check if already in scan.map
	cached=$(grep "^${oem}|" "$SCAN_MAP" 2>/dev/null | head -1)
	if [ -n "$cached" ]; then
		tune=$(echo "$cached" | cut -d'|' -f3)
		libc_hdr=$(echo "$cached" | cut -d'|' -f4)
		tune_flags=$(echo "$cached" | cut -d'|' -f5)
		[ "$tune" == "FAIL" ] || [ "$tune" == "UNKNOWN" ] && continue
		log INFO "[${count}/${TOTAL}] [$oem] cached: tune=$tune libc-hdr=$libc_hdr"
	else
		printf "\r\033[K${CYAN}[%d/%d]${NC} %s: scanning...\n" "$count" "$TOTAL" "$oem" >&2

		# Scan: make init + bitbake -e to get tune + libc-headers
		if ! setup_bitbake_env "$machinebuild" "$oem"; then
			log WARN "[$oem] make init failed, skipping"
			echo "$oem|$machinebuild|FAIL|FAIL|" >> "$SCAN_MAP"
			continue
		fi

		bb_env=$(MACHINE=$oem bitbake -e 2>/dev/null)
		tune=$(echo "$bb_env" | grep "^DEFAULTTUNE=" | sed 's/.*="//;s/"//')
		tune_flags=$(echo "$bb_env" | grep "^TUNE_CCARGS=" | sed 's/.*="//;s/"$//' | xargs)
		libc_hdr=$(MACHINE=$oem bitbake -e linux-libc-headers 2>/dev/null | grep "^PV=" | sed 's/.*="//;s/"//')

		if [ -z "$tune" ]; then
			log WARN "[$oem] Could not determine tune"
			echo "$oem|$machinebuild|UNKNOWN|${libc_hdr:-default}|" >> "$SCAN_MAP"
			continue
		fi

		echo "$oem|$machinebuild|$tune|${libc_hdr:-default}|$tune_flags" >> "$SCAN_MAP"
		log INFO "[${count}/${TOTAL}] [$oem] tune=$tune libc-hdr=${libc_hdr:-default} flags=$tune_flags"
	fi

	key="$tune"

	# Track machine membership (all MACHINEBUILDs, not just OEMs)
	if [ -z "${GROUP_MACHINES_MAP[$key]}" ]; then
		GROUP_MACHINES_MAP[$key]="$machinebuild"
	else
		if [[ " ${GROUP_MACHINES_MAP[$key]} " != *" $machinebuild "* ]]; then
			GROUP_MACHINES_MAP[$key]="${GROUP_MACHINES_MAP[$key]} $machinebuild"
		fi
	fi

	# Already built this group?
	if [ -n "${BUILT_GROUPS[$key]}" ]; then
		DEDUP_SKIPPED=$((DEDUP_SKIPPED + 1))
		# Update cfg with new machine
		tc_name="${BUILT_GROUPS[$key]}"
		tc_cfg="$OUTPUT/toolchains.cfg/$tc_name"
		[ "$tc_name" != "FAILED" ] && [ -f "$tc_cfg" ] && \
			sed -i "s|^_machines=.*|_machines=\"${GROUP_MACHINES_MAP[$key]}\";|" "$tc_cfg"
		log INFO "[$oem] -> group $tc_name (dedup skip)"
		continue
	fi

	# Build this group now (first OEM in group becomes the builder)
	printf "\r\033[K" >&2

	# Set group context for build function
	GROUP_BUILDER_OEM="$oem"
	GROUP_BUILDER_MB="$machinebuild"
	GROUP_KEY="$key"

	if build_group_toolchain "$key"; then
		tune_short=$(shorten_tune "$tune")
		tc_name="${tune_short}_${LABEL}_${VERSION}"
		BUILT_GROUPS[$key]="$tc_name"
		GROUPS_BUILT=$((GROUPS_BUILT + 1))
	else
		BUILT_GROUPS[$key]="FAILED"
		GROUPS_FAILED=$((GROUPS_FAILED + 1))
	fi

	cd "$ENV"
done
printf "\r\033[K" >&2

# Finalize: update machine lists, copy .config, create tar.xz, cleanup
log INFO "Finalizing toolchains..."
for key in "${!BUILT_GROUPS[@]}"; do
	tc_name="${BUILT_GROUPS[$key]}"
	[ "$tc_name" == "FAILED" ] && continue
	tc_cfg="$OUTPUT/toolchains.cfg/$tc_name"
	tc_dir="$OUTPUT/toolchains/$tc_name"
	tpl_file="$OUTPUT/templates/$tc_name"
	tc_tarxz="$OUTPUT/toolchains/Toolchain-${tc_name}.tar.xz"
	all_machines=$(echo "${GROUP_MACHINES_MAP[$key]}" | tr ' ' '\n' | sort | tr '\n' ' ' | xargs)
	machine_count=$(echo "$all_machines" | wc -w)

	# Update cfg + template with full MACHINEBUILD lists
	[ -f "$tc_cfg" ] && sed -i "s|^_machines=.*|_machines=\"${all_machines}\";|" "$tc_cfg"
	[ -f "$tpl_file" ] && sed -i "s|^OESDK_MACHINES=.*|OESDK_MACHINES=\"${all_machines}\"|" "$tpl_file"

	# Copy final template as .config into toolchain dir
	[ -f "$tpl_file" ] && [ -d "$tc_dir" ] && cp -f "$tpl_file" "$tc_dir/.config"

	# Create tar.xz
	if [ -d "$tc_dir" ]; then
		log BUILD "[$tc_name] Creating tar.xz ($machine_count machines)..."
		tar cJf "$tc_tarxz" -C "$tc_dir" . 2>> "$LOGFILE"
		if [ $? -eq 0 ]; then
			md5="$(cd "$(dirname "$tc_tarxz")" && md5sum "$(basename "$tc_tarxz")")"
			[ -f "$tc_cfg" ] && sed -i "s|_md5sum=\"pending\"|_md5sum=\"$md5\"|" "$tc_cfg"
			tarxz_size=$(du -sh "$tc_tarxz" | cut -f1)
			log OK "[$tc_name] tar.xz: $tarxz_size ($machine_count machines)"
		else
			log ERROR "[$tc_name] tar.xz creation failed"
		fi
		rm -rf "$tc_dir"
	fi
done

# Scan-only: exit after scan
if [ "$SCAN_ONLY" -eq 1 ]; then
	log OK "Scan complete. Scan map: $SCAN_MAP"
	cat "$SUMMARY"
	exit 0
fi

# Summary
TOTAL_GROUPS=$((GROUPS_BUILT + GROUPS_FAILED))
echo "" >> "$SUMMARY"
echo "========================================" >> "$SUMMARY"
echo "Machines: $TOTAL | Groups: $TOTAL_GROUPS | Built: $GROUPS_BUILT | Failed: $GROUPS_FAILED | Dedup skipped: $DEDUP_SKIPPED" >> "$SUMMARY"
echo "Finished: $(date)" >> "$SUMMARY"

log INFO "=========================================="
log INFO "Machines: $TOTAL | Groups: $TOTAL_GROUPS | Built: $GROUPS_BUILT | Failed: $GROUPS_FAILED | Dedup skipped: $DEDUP_SKIPPED"

# Phase 3: Upload
if [ -n "$UPLOAD" ]; then
	log INFO "Phase 3: Uploading toolchains..."
	local ssh_opts=""
	[ -n "$SSH_KEY" ] && ssh_opts="-e \"ssh -i $SSH_KEY\""
	eval rsync -avz $ssh_opts "$OUTPUT/toolchains/" "$OUTPUT/toolchains.cfg/" "$UPLOAD/" >> "$LOGFILE" 2>&1
	if [ $? -eq 0 ]; then
		log OK "Upload complete"
	else
		log ERROR "Upload failed"
	fi
fi

log OK "Done! Results in $OUTPUT"
log INFO "Summary: $SUMMARY"
log INFO "Log: $LOGFILE"

cat "$SUMMARY"
