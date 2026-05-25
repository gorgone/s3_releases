#!/bin/bash

_help_toolchain(){
	printf "$w_l  toolchains :\n  ------------$g_n\n"
	helpline1 "${AVAI_TCLIST[@]}"
	printf "\n"
}

helpline0(){
	ll=0
	printf "  ";
	for s in $(echo "$@" | xargs -n1 | sort -u | xargs)
	do

		if [ ! "$s" == "USE_MCA" ] \
		&& [ ! "$s" == "USE_LIBUSB" ] \
		&& [ ! "$s" == "USE_CONFDIR" ]
		then
			ll=$((ll + (${#s} + 4)))
			if [ "$ll" -lt "30" ]
			then
				printf "$s(_off) "
			else
				printf "$s(_off)\n  "
				ll=""
			fi
		fi

	done
}

helpline1(){
	ll=0
	printf "  "
	for s in $(echo "$@" | xargs -n1 | sort -u | xargs)
	do

		ll=$((ll + (${#s} + 4)))
		if [ "$ll" -lt "45" ]
		then
			printf "$s "
		else
			printf "$s\n  "
			ll=""
		fi

	done
}

_help(){
	clear
	s3logo
	printf "  --------------------------------------\n"
	printf "  $txt_help1 $0 menu\n"
	printf "  $txt_help2\n"
	printf "  --------------------------------------\n"
	printf "$w_l\n  toolchains :\n  ------------$g_n\n"
	helpline1 "${AVAI_TCLIST[@]}\n"

	printf "$w_l\n\n  simplebuild options :\n  ---------------------$c_n\n"
	helpline1 "${s3opts[@]}"
	_wait

	printf "\r$w_l\n  config_cases :\n  --------------$c_n\n"
	helpline0 "${config_cases[@]}"

	printf "$w_l\n\n  addons :\n  --------$p_l\n"
	helpline0 "${SHORT_ADDONS[@]}"
	_wait

	printf "\n$w_l  protocols :\n  -----------$y_l\n"
	helpline0 "${SHORT_PROTOCOLS[@]}"

	printf "$w_l\n\n  readers :\n  ---------$r_l\n"
	helpline0 "${SHORT_READERS[@]}"
	_wait

	printf "\n$w_l  card_readers :\n  --------------$b_l\n"
	helpline0 "${SHORT_CARD_READERS[@]}"

	printf "$w_l\n  use_vars :\n  --------$w_n\n"
	helpline0 "${!USE_vars[@]}"
	_wait
	_nl
}
