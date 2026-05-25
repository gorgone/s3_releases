#!/bin/bash

#usage:
#to use colors start with initializeANSI first
#example red color text
#echo -e $r_n"red text"$re_"normal text"

initializeANSI(){

nc='\033[0;' #nc normal color
lc='\033[1;' #lc light  color
bc='\033['   #bc backcolor

# normal
bk_n=$nc'30m' #black
r_n=$nc'31m' #red
g_n=$nc'32m' #green
y_n=$nc'33m' #yellow
b_n=$nc'34m' #blue
p_n=$nc'35m' #pink
c_n=$nc'36m' #cyan
w_n=$nc'37m' #white

#light
bk_l=$nc'30m' #black
r_l=$lc'31m' #red
g_l=$lc'32m' #green
y_l=$lc'33m' #yellow
b_l=$lc'34m' #blue
p_l=$lc'35m' #pink
c_l=$lc'36m' #cyan
w_l=$lc'37m' #white

# normal background
bk_nb=$bc'40m' #black
r_nb=$bc'41m' #red
g_nb=$bc'42m' #green
y_nb=$bc'43m' #yellow
b_nb=$bc'44m' #blue
p_nb=$bc'45m' #pink
c_nb=$bc'46m' #cyan
w_nb=$bc'107m' #white

# light background
dg_lb=$bc'100m' #dark gray
r_lb=$bc'101m' #light red
g_lb=$bc'102m' #light green
y_lb=$bc'103m' #light yellow
b_lb=$bc'104m' #light blue
p_lb=$bc'105m' #light pink
c_lb=$bc'106m' #light cyan
lg_lb=$bc'47m' #light gray

#reset to normal
re_='\033[0m'   #resets all colors
re_f='\033[39m' #resets only foreground color
re_b='\033[49m' #resets only background color

#sed replace
W=$(echo -e '\033[0m')     #normal
Y=$(echo -e '\033[1;33m')  #yellow
YH=$(echo -e '\033[1;93m')  #yellow
R=$(echo -e '\033[1;31m')  #red
G=$(echo -e '\033[1;32m')  #green
GH=$(echo -e '\033[1;92m')  #green
P=$(echo -e '\033[1;35m')  #pink
C=$(echo -e '\033[1;36m')  #cyan
WH=$(echo -e '\033[1;37m') #lightgray
}
