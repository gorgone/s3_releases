#!/bin/bash

_fill_tc_array(){
	unset AVAI_TCLIST
	unset INST_TCLIST
	tcempty=0

	cd "$tccfgdir"
	if [ "$(ls -A "$tccfgdir")" ]
	then
		AVAI_TCLIST=(*)
	else
		printf "\n error in _fill_tc_array()\n please report error\n\n"
		exit
	fi

	cd "$tcdir"
	if [ "$(ls -A "$tcdir")" ]
	then
		tmp_tclist=(*)
		for t in "${tmp_tclist[@]}"
		do
			for a in "${AVAI_TCLIST[@]}"
			do
				[ "$t" == "$a" ] && INST_TCLIST+=($t)
			done
		done
	else
		tcempty=1
	fi

	if [ "$tcempty" == "1" ]
	then
		MISS_TCLIST=$(echo ${AVAI_TCLIST[@]} |sort)
	else
		MISS_TCLIST=(
		$(for el in $(diff_array AVAI_TCLIST[@] INST_TCLIST[@])
		do
			echo "$el"
		done |sort)
		)
	fi
}

_create_module_arrays(){
	i=0
	for e in $(echo "$addons" | sed 's/WEBIF_//g;s/WITH_//g;s/MODULE_//g;s/CS_//g;s/HAVE_//g;s/_CHARSETS//g;s/CW_CYCLE_CHECK/CWCC/g;s/SUPPORT//g';)
	do
		SHORT_ADDONS+=($e)
		SHORT_MODULENAMES+=($e)
	done

	for e in ${protocols//MODULE_/}
	do
		SHORT_PROTOCOLS+=($e)
		SHORT_MODULENAMES+=($e)
	done

	for e in ${readers//READER_/}
	do
		SHORT_READERS+=($e)
		SHORT_MODULENAMES+=($e)
	done

	for e in ${card_readers//CARDREADER_/}
	do
		SHORT_CARD_READERS+=($e)
		SHORT_MODULENAMES+=($e)
	done

	for e in $addons $protocols $readers $card_readers
	do
		ALL_MODULES_LONG+=($e)
	done

	for e in "${SHORT_MODULENAMES[@]}"
	do
		INTERNAL_MODULES["$e"]="${ALL_MODULES_LONG[i]}"
		((i++))
	done
}

diff_array(){
	awk 'BEGIN{RS=ORS=" "}{NR==FNR?a[$0]++:a[$0]--}END{for(k in a)if(a[k])print k}' <(echo -n "${!1}") <(echo -n "${!2}")
}
